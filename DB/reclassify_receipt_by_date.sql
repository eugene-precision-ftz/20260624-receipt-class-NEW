-- DROP FUNCTION preftz.reclassify_receipt_by_date(int4, date, varchar);

CREATE OR REPLACE FUNCTION preftz.reclassify_receipt_by_date(p_receiptid integer, p_classify_date date, p_base_hts character varying DEFAULT NULL::character varying)
 RETURNS character varying
 LANGUAGE plpgsql
AS $function$

--Change Log:
-- KK 12/01/2025 Added HTS parameter for those receipts that have HTS change. Recarro had HTS number changed from 9401999081 to 9401999070.
-- KK 11/24/2025 Use temp table to backup receipt_classifications until sure classification has NOT FAILED.
-- KK 11/11/2025 Refactor logic for applying additional tariffs and implement logic for recent CBP guidance.
-- KK 06/04/2025 Add ability to reclassify a receipt using specified date.
--
-- Be careful, this will reclassify the receipt even if it has been depleted or partially depleted.
-- Typically, this should be used on receipts with no depletion (after making)

DECLARE
  v_result            VARCHAR(10);  --PASS or FAIL
  crs                 RECORD;
  v_classification    VARCHAR(12);
  v_tariff_number     VARCHAR(10);
  v_special_program   VARCHAR(2);
  v_added_tariffs     VARCHAR;
  v_added_cast_and_smelt_tariffs VARCHAR; --NKM 04/21/2023
  v_count             INTEGER;
  i                   INTEGER;
  v_position          INTEGER;
  v_zone_status       VARCHAR(1);
  v_additional_tariff VARCHAR(10);
  v_additional_status VARCHAR(1);
  v_tariff_type       VARCHAR(15);
  receipt_result      VARCHAR(10);  --PASS or FAIL
  before_messageid    INTEGER;
  after_messageid     INTEGER;
  v_base_hts          VARCHAR(10);  --RTJ 11/30/2022
  v_sec301_hts        VARCHAR(10);  --RTJ 11/30/2022
  v_bounds_hts        VARCHAR(10);  --RTJ 01/17/2023
  v_unit_value        DOUBLE PRECISION;
  v_classify_date     DATE;
  derivative_rs       RECORD;  -- KK 04/17/2025
  v_skip_added_tariffs   BOOLEAN DEFAULT false;  -- KK 05/06/2025

BEGIN
  INSERT INTO preftz.system_log (procedure_name, log_message)
  VALUES ('reclassify_receipt_by_date', 'started: ' || p_receiptid);

  v_result = 'PASS';

  CREATE TEMPORARY TABLE IF NOT EXISTS receipt_classifications_temp AS TABLE preftz.receipt_classifications WITH NO DATA;
  DELETE FROM receipt_classifications_temp
  WHERE receiptid = p_receiptid; 
  -- save original just in case we fail
  INSERT INTO  receipt_classifications_temp
  SELECT * FROM preftz.receipt_classifications WHERE receiptid = p_receiptid;

  DELETE FROM preftz.receipt_classifications rc
        USING preftz.receipts r
        WHERE r.receiptid = p_receiptid
          AND rc.receiptid = r.receiptid;

  SELECT COALESCE(MAX(messageid),0) INTO before_messageid FROM preftz.data_audit_messages;

  INSERT INTO preftz.data_audit_messages (audit_document, audit_message)
  SELECT DISTINCT r.zone_admission_no, 'Missing classification for part ' || r.part_number
    FROM preftz.receipts r
          LEFT JOIN preftz.parts p
                 ON r.part_number = p.part_number
          LEFT JOIN preftz.part_classifications pc
                 ON p.part_number = pc.part_number
   WHERE r.receiptid = p_receiptid
     AND pc.harmonized_tariff_schedule_number IS NULL;

  SELECT COALESCE(MAX(messageid),0) INTO after_messageid FROM preftz.data_audit_messages;

  IF after_messageid > before_messageid THEN v_result = 'FAIL'; END IF;

  FOR crs IN (SELECT r.receiptid, r.part_number, r.zone_status, r.country_of_origin,
                     r.unit_price, p.special_programs_indicator,
                     COALESCE(p_base_hts, pc.harmonized_tariff_schedule_number) as harmonized_tariff_schedule_number,
                     pc.split_fixed_unit_value, pc.split_value_percentage, tt.value_reported,
                     pc.tariff_type, pc.distinct_tariff_line_indicator, pc.primary_tariff,
                     pc.quantity1_conversion_rate quantity1_rate, --RTJ 11/23/2020
                     pc.quantity2_conversion_rate quantity2_rate, --RTJ 11/23/2020
                     rcn.antidumping_case_number, rcn.countervailing_case_number,  --RTJ 03/30/2021
                     rcs.country_of_cast, rcs.primary_country_of_smelt, rcs.secondary_country_of_smelt, --NKM 04/21/2023
                     q.harmonized_tariff_schedule_number override_tariff,  --RTJ 11/30/2022
                     preftz.get_receipt_value(r.receiptid) unit_value,  --RTJ 01/20/2023
                     r.zone_admission_no
                FROM preftz.receipts r
                     INNER JOIN preftz.parts p
                             ON r.part_number = p.part_number
                     INNER JOIN preftz.part_classifications pc
                             ON p.part_number = pc.part_number
                     INNER JOIN prehts.tariff_types tt
                             ON pc.tariff_type = tt.tariff_type
                      LEFT JOIN preftz.receipt_case_numbers rcn  --RTJ 03/30/2021
                             ON r.receiptid = rcn.receiptid
                      LEFT JOIN (SELECT o.part_number, o.harmonized_tariff_schedule_number  --RTJ 11/30/2022
                                   FROM preftz.part_classifications o
                                  WHERE o.tariff_type IN ('OVERRIDE','MTB')) q
                             ON r.part_number = q.part_number
                      LEFT JOIN preftz.receipt_cast_and_smelt rcs --NKM 04/21/2023
                             ON r.receiptid = rcs.receiptid
               WHERE r.receiptid = p_receiptid
                 AND pc.tariff_type <> 'SCRAP'
               ORDER BY r.receiptid, CASE pc.tariff_type WHEN 'BASE' THEN 0 ELSE 9 END)  --RTJ 11/30/2022
  LOOP
    INSERT INTO preftz.system_log (procedure_name, log_message)
    VALUES ('reclassify_receipt_by_date', 'relassify: ' || p_receiptid);
    RAISE NOTICE 'relassify: receiptid: %, part: %, hts: %, coo: %, spi: %', 
        crs.receiptid, crs.part_number, crs.harmonized_tariff_schedule_number, crs.country_of_origin, crs.special_programs_indicator;

      IF crs.zone_status <> 'D'
      THEN
          receipt_result = 'PASS';

          v_classify_date = COALESCE(p_classify_date, current_date);

          SELECT preftz.validate_classification
                (crs.harmonized_tariff_schedule_number, crs.special_programs_indicator, crs.country_of_origin,
                 v_classify_date)
            INTO v_classification;

          IF v_classification = 'FAIL' THEN
              v_result = 'FAIL';
              receipt_result = 'FAIL';

              INSERT INTO preftz.data_audit_messages
                     (audit_document, audit_message)
              VALUES (crs.zone_admission_no, 'Invalid HTS ' || crs.harmonized_tariff_schedule_number ||
                      ' for part ' || crs.part_number);

          ELSE
              v_tariff_number = TRIM(SUBSTR(v_classification,1,10));
              v_special_program = TRIM(SUBSTR(v_classification,11,2));
              v_zone_status = crs.zone_status;

              --RTJ 11/30/2022
              IF crs.tariff_type = 'BASE' THEN
                v_base_hts = crs.harmonized_tariff_schedule_number;

                --RTJ 01/17/2023
                v_unit_value = crs.unit_value;
                    IF p_base_hts IS NULL THEN  -- skip this section if using an old HTS
                        v_bounds_hts = preftz.get_bounds_hts(crs.part_number, v_unit_value);

                        IF v_bounds_hts = 'MISSINGHTS' THEN
                            v_result = 'FAIL';
                            receipt_result = 'FAIL';

                            INSERT INTO preftz.data_audit_messages
                                    (audit_document, audit_message, action_code, audit_reference)
                            VALUES (crs.zone_admission_no, 'Missing bounds HTS for part ' || crs.part_number ||
                                    ' and value ' || v_unit_value, 'ADDBOUNDS', crs.receiptid);

                        ELSIF v_bounds_hts = 'EDITBOUNDS' THEN
                            v_result = 'FAIL';
                            receipt_result = 'FAIL';

                            INSERT INTO preftz.data_audit_messages
                                    (audit_document, audit_message, action_code, audit_reference)
                            VALUES (crs.zone_admission_no, 'Overlapping bounds HTS for part ' || crs.part_number ||
                                    ' and value ' || v_unit_value, 'EDITBOUNDS', crs.receiptid);

                        ELSIF v_bounds_hts <> v_base_hts THEN
                            SELECT preftz.validate_classification
                                    (v_bounds_hts, crs.special_programs_indicator, crs.country_of_origin,
                                    v_classify_date)
                                INTO v_classification;

                            IF v_classification = 'FAIL' THEN
                                v_result = 'FAIL';
                                receipt_result = 'FAIL';

                                INSERT INTO preftz.data_audit_messages
                                        (audit_document, audit_message, action_code, audit_reference)
                                VALUES (crs.zone_admission_no, 'Invalid bounds HTS ' || v_bounds_hts ||
                                        ' for part ' || crs.part_number || ' and value ' || v_unit_value,
                                        'EDITBOUNDS', crs.receiptid);

                            ELSE
                                v_base_hts = v_bounds_hts;
                                v_tariff_number = TRIM(SUBSTR(v_classification,1,10));
                                v_special_program = TRIM(SUBSTR(v_classification,11,2));
                            END IF;
                        END IF;  --bounds hts check
                        --RTJ 01/17/2023
                    END IF; -- if p_base_hts IS NULL
              END IF;  --base hts

              IF crs.tariff_type = 'EXCLUSION301' THEN

                  SELECT a.additional_tariff_number INTO v_sec301_hts
                    FROM preftz.additional_tariffs a
                   WHERE a.tariff_prefix = SUBSTR(v_base_hts,1,LENGTH(a.tariff_prefix))
                     AND NOT v_base_hts LIKE ANY(COALESCE(a.exception_tariff_prefixes,'{}'::TEXT[])) --NKM 04/21/2023 --NKM 09/10/2023
                     AND (a.country_of_origin = crs.country_of_origin OR a.country_of_origin = 'ALL')
                     AND NOT crs.country_of_origin LIKE ANY(COALESCE(a.exception_countries,'{}'::TEXT[])) --NKM 09/10/2023
                     AND a.start_date <= v_classify_date
                     AND a.end_date >= v_classify_date
                     AND a.tariff_type = 'SECTION301';

              END IF;
              --RTJ 11/30/2022

              IF crs.tariff_type IN ('BASE','SPLIT','SCRAP') AND v_skip_added_tariffs = false THEN 

                    -- KK 10/15/2025 Refactored additional tariff logic
                    v_added_tariffs = preftz.get_all_additional_tariffs_string (
                        crs.part_number, crs.receiptid, v_tariff_number, crs.country_of_origin, p_classify_date, crs.special_programs_indicator,
                        crs.country_of_cast, crs.primary_country_of_smelt, crs.secondary_country_of_smelt);

                    RAISE NOTICE 'filtered_added_tariffs: %', v_added_tariffs;
              ELSE
                    v_added_tariffs = '';
              END IF;

              v_count = LENGTH(v_added_tariffs)/26;
              IF v_count > 0 THEN

                  FOR i IN 1 .. v_count
                  LOOP
                      v_position = (i-1) * 26 + 1;
                      v_additional_status = SUBSTR(v_added_tariffs, v_position + 10, 1);
                      v_additional_tariff = TRIM(SUBSTR(v_added_tariffs, v_position, 10));
                      v_tariff_type = TRIM(SUBSTR(v_added_tariffs, v_position + 11, 15));

                      IF v_additional_status > v_zone_status AND COALESCE(crs.override_tariff,'') = '' THEN --RTJ 11/30/2022
                          v_zone_status = v_additional_status;
                      END IF;

                      SELECT preftz.validate_classification
                            (v_additional_tariff, NULL, crs.country_of_origin, v_classify_date)
                        INTO v_classification;

                      IF v_classification = 'FAIL' THEN
                          v_result = 'FAIL';
                          receipt_result = 'FAIL';

                          INSERT INTO preftz.data_audit_messages
                                 (audit_document, audit_message)
                          VALUES (crs.zone_admission_no, 'Invalid additional HTS ' || v_additional_tariff ||
                                  ' for part/coo/tariff ' || crs.part_number || '/' || crs.country_of_origin ||
                                  '/' || v_tariff_number);

                      ELSE
                        --MH 4/16/2025
                        IF NOT EXISTS(select 'x' from preftz.receipt_classifications
                        where receiptid = crs.receiptid
                        and harmonized_tariff_schedule_number =v_additional_tariff
                        and tariff_type =  v_tariff_type) THEN
                            INSERT INTO preftz.receipt_classifications
                                    (receiptid, harmonized_tariff_schedule_number, special_programs_indicator, unit_value,
                                    tariff_type)
                            VALUES (crs.receiptid, v_additional_tariff, '', 0, v_tariff_type);
                        END IF;

                      END IF;
                  END LOOP;
              END IF;

              IF receipt_result = 'PASS' THEN
                  IF crs.value_reported = 'ZERO' THEN
                      v_unit_value = 0;
                  ELSIF crs.value_reported = 'SPLIT' THEN
                      --logic for split values needs to be added here
                  ELSE
                      v_unit_value = crs.unit_value;  --RTJ 01/19/2023
                  END IF;

                  RAISE NOTICE 'hts: %, unit_value: %', v_tariff_number, v_unit_value;

                  IF (crs.tariff_type <> 'EXCLUSION301' OR v_sec301_hts IS NOT NULL) AND
                         (v_skip_added_tariffs = false OR (v_skip_added_tariffs = true AND crs.tariff_type = 'BASE')) THEN  -- KK 05/06/2025
					IF NOT EXISTS(select 'x' from preftz.receipt_classifications
                        where receiptid = crs.receiptid
                        and harmonized_tariff_schedule_number =v_tariff_number
                        and tariff_type =  crs.primary_tariff) THEN	 -- MH 5/7/2025 added if not exist then add to remove failure from duplicate issue
                      INSERT INTO preftz.receipt_classifications
                             (receiptid, harmonized_tariff_schedule_number, special_programs_indicator,
                              unit_value, tariff_type, distinct_tariff_line_indicator, primary_tariff,
                              quantity1_rate, quantity2_rate)  --RTJ 11/23/2020
                      VALUES (crs.receiptid, v_tariff_number, v_special_program, v_unit_value,
                              crs.tariff_type, crs.distinct_tariff_line_indicator, crs.primary_tariff,
                              crs.quantity1_rate, crs.quantity2_rate);  --RTJ 11/23/2020
					END IF;
                  END IF;

                  --RTJ 03/30/2021
                  IF COALESCE(crs.antidumping_case_number,'') <> ''
                  OR COALESCE(crs.countervailing_case_number,'') <> '' THEN
                      v_zone_status = 'P';
                  END IF;
                  --RTJ 03/30/2021

                  -- KK 05/22/2025
                  IF v_skip_added_tariffs = true THEN
                      v_zone_status = 'N';
                  END IF;

                  IF v_zone_status <> crs.zone_status THEN
                      UPDATE preftz.receipts r
                         SET zone_status = v_zone_status
                       WHERE r.receiptid = crs.receiptid;

                      UPDATE preftz.inventory_items ii
                         SET zone_status = v_zone_status
                       WHERE ii.receiptid = crs.receiptid;
                  END IF;

                  --RTJ 05/24/2021
                  IF v_zone_status = 'P' THEN
                      UPDATE preftz.receipts r
                         SET privileged_date = COALESCE(r.privileged_date,r.receipt_date,v_classify_date) --NKM 09/18/2023
                       WHERE r.receiptid = crs.receiptid;
                  END IF;
                  --RTJ 05/24/2021

                  -- KK 08/20/2025 update quantity1_rate based on derivative percentage
                  -- This is not very efficient, need to refactor calls to these procs after hot-fix
                  -- order is IMPORTANT! calculate_derivative_quantity needs to be called before duty calculations
                  IF LENGTH(v_added_tariffs) > 0 THEN	
                      CALL preftz.calculate_derivative_quantity(crs.receiptid); 	
                  END IF;

                  CALL preftz.calculate_duty_liability(crs.receiptid);  --RTJ 07/12/2021

                  -- If Derivative of steel or aluminum recalculate BASE and derivative tariffs
                  IF LENGTH(v_added_tariffs) > 0 THEN
                      CALL preftz.calculate_derivative_duty_liability(crs.receiptid);
                  END IF;

              END IF;  --receipt result

          END IF;  --valid HTS
      END IF;  --zone status <> 'D'
  END LOOP;

  IF v_result <> 'PASS' THEN
    -- delete existing rows and insert new rows to receipt_classifications
    DELETE FROM preftz.receipt_classifications rc
    USING preftz.receipts r
    WHERE r.receiptid = p_receiptid
        AND rc.receiptid = r.receiptid;

    INSERT INTO preftz.receipt_classifications
    SELECT * FROM receipt_classifications_temp
    WHERE receiptid = p_receiptid;
    RAISE NOTICE 'inserted into receipt_classifications for receiptid: %', p_receiptid;
  END IF;

  INSERT INTO preftz.system_log (procedure_name, log_message)
  VALUES ('reclassify_receipt_by_date', 'ended: ' || p_receiptid || ' ' || v_result);

  RETURN v_result;

END;
$function$
;
