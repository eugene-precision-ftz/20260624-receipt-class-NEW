CREATE OR REPLACE FUNCTION preftz.classify_receipts(	
    p_admission_number character varying,	
    p_classify_date DATE DEFAULT NULL::date)
    RETURNS character varying	
    LANGUAGE 'plpgsql'	
    COST 100	
    VOLATILE PARALLEL UNSAFE	
AS $BODY$	
	
--Change Log:
-- KK 07/21/2026 Use ZTZ privileged_date and base_hts if this was a ZTZ transfer item.
-- EG 06/11/2026 strip IEEPA from those receipts on an Entry document, use privileged date from receipt if available when classifying receipts
-- EG 3/10/2026 changes for ztz_additional_tariffs DEV-229
-- KK 12/03/2025 If there are any added tariffs, call procedures for derivative quantity and duty calculations.
-- KK 11/11/2025 Refactor logic for applying additional tariffs and implement logic for recent CBP guidance.
-- KK 09/08/2025 do not add additional tariffs if receipt has an OVERRIDE tariff.
-- KK 08/20/2025 update quantity1_rate based on derivative percentage
-- KK 08/08/2025 Implement variable rate tariffs (minimum tariff) as defined by CSMS # 65807735 AnnexII.
-- KK 06/09/2025 Add stacking logic CSMS # 65236574 for additional tariff prioritization.
-- KK 05/22/2025 Added an optional parameter to allow us to re-classify admissions as they turn bypass_added_tariffs on/off. 
--               Also, force zone_status = 'N' for those admissions where bypass_added_tariffs = true.
-- KK 05/09/2025 Cast/Smelt and Melt/Pour reporting should NOT include derivatives that have zero percent aluminum or steel.
-- MH 5/7/2025 added if not exist then add to remove failure from duplicate issue
-- KK 05/07/2025 added flag bypass_added_tariffs to bypass adding any additional tariffs.	
-- KK 04/17/2025 SECTION232 Steel and aluminum derivatives	
--MH 4/16/2025 added if classification is not already present add receipt classification	
--NKM 09/18/2023 Does not update privileged date unless it is null	
--NKM 09/10/2023 Corrected exception logic to handle null exception_countries	
--NKM 04/21/2023 Added exceptions to additional_tariffs table and added cast & smelt tariffs	
--RTJ 01/19/2023 Add unit assist and receipt_dutiable_fees	
--RTJ 01/17/2023 Add audit for value low/high bounds	
--RTJ 11/30/2022 Do not shift to P status if an OVERRIDE HTS is associated with this receipt	
--               Do not include 301 exclusion if product is not subject to section 301	
--RTJ 09/05/2022 Do not pull additional tariffs for DUTY9 secondary tariff numbers	
--RTJ 07/12/2021 Add logic to calculate duty liability	
--RTJ 05/24/2021 Reset privileged date when receipts are classified	
--RTJ 04/21/2021 Moved cloning of receipt data for adjustments to process_adjustments procedure	
--RTJ 03/30/2021 Include handling for receipts with case number(s)	
--RTJ 03/05/2021 Add receipt/classification data for foreign up adjusts	
--RTJ 12/31/2020 Moved tariff_types table to PREHTS schema	
--RTJ 11/23/2020 Add statistical rate to receipt_classifications record	
	
DECLARE	
  v_result            VARCHAR(10);  --PASS or FAIL	
  crs                 RECORD;	
  v_classification    VARCHAR(12);	
  v_tariff_number     VARCHAR(10);	
  v_special_program   VARCHAR(2);	
  v_added_tariffs     VARCHAR;	
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
  derivative_rs       RECORD;  -- KK 04/17/2025	
  v_skip_added_tariffs   BOOLEAN DEFAULT false;  -- KK 05/06/2025	

  v_add_hts_count     INTEGER; -- EG 3/10/2026
  v_classify_date     DATE;    -- EG 3/10/2026 to potentially override classify date with privileged date provided in transfer item file
  
BEGIN	
  INSERT INTO preftz.system_log (procedure_name, log_message) 	
  VALUES ('classify_receipts', 'started: ' || p_admission_number);	
  	
  -- KK 05/07/2025	
  SELECT COALESCE(bypass_added_tariffs, false) 	
  INTO v_skip_added_tariffs	
  FROM preftz.e214_filing_statuses	
  WHERE zone_admission_no = p_admission_number;	
	
  v_result = 'PASS';	
	
  DELETE FROM preftz.receipt_classifications rc	
        USING preftz.receipts r	
        WHERE r.zone_admission_no = p_admission_number	
          AND rc.receiptid = r.receiptid;	
          	
  SELECT COALESCE(MAX(messageid),0) INTO before_messageid FROM preftz.data_audit_messages;	
  	
  INSERT INTO preftz.data_audit_messages (audit_document, audit_message)	
  SELECT DISTINCT p_admission_number, 'Missing classification for part ' || r.part_number	
    FROM preftz.receipts r	
          LEFT JOIN preftz.parts p	
                 ON r.part_number = p.part_number	
          LEFT JOIN preftz.part_classifications pc	
                 ON p.part_number = pc.part_number	
   WHERE r.zone_admission_no = p_admission_number	
     AND pc.harmonized_tariff_schedule_number IS NULL;	
     	
  SELECT COALESCE(MAX(messageid),0) INTO after_messageid FROM preftz.data_audit_messages;	
  	
  IF after_messageid > before_messageid THEN v_result = 'FAIL'; END IF;	
  	
  FOR crs IN (
        WITH ztz_details AS (  -- KK 07/21/2026
            SELECT r.receiptid, til.transfer_itemid, za.privileged_date, za.ztz_base_tariffs
            FROM preftz.inventory_items ii
            JOIN preftz.receipts r on r.receiptid = ii.receiptid
            JOIN preftz.transfer_items_links til on ii.itemid = til.itemid 
                AND r.part_number = ii.part_number
            JOIN preftz.transfer_ztz_archive za ON za.transfer_itemid = til.transfer_itemid
            WHERE r.zone_to_zone_transfer = 'Y'
                AND za.privileged_date IS NOT NULL
        )
        SELECT r.receiptid, r.part_number, r.zone_status, r.country_of_origin, r.unit_price, 
            CASE WHEN ztzd.ztz_base_tariffs IS NOT NULL AND pc.tariff_type = 'BASE' THEN
                ztzd.ztz_base_tariffs
            ELSE
                pc.harmonized_tariff_schedule_number
            END AS harmonized_tariff_schedule_number,  -- KK 07/21/2026 replace BASE with ztz_base_tariffs when ZTZ
            p.special_programs_indicator,	
            pc.split_fixed_unit_value, pc.split_value_percentage, tt.value_reported,	
            pc.tariff_type, pc.distinct_tariff_line_indicator, pc.primary_tariff,	
            pc.quantity1_conversion_rate quantity1_rate, --RTJ 11/23/2020	
            pc.quantity2_conversion_rate quantity2_rate, --RTJ 11/23/2020	
            rcn.antidumping_case_number, rcn.countervailing_case_number,  --RTJ 03/30/2021	
            rcs.country_of_cast, rcs.primary_country_of_smelt, rcs.secondary_country_of_smelt, --NKM 04/21/2023	
            q.harmonized_tariff_schedule_number override_tariff,  --RTJ 11/30/2022	
            preftz.get_receipt_value(r.receiptid) unit_value  --RTJ 01/20/2023	
            , COALESCE(ztzd.privileged_date, r.privileged_date) AS privileged_date  -- KK 07/21/2026
            , ztzd.ztz_base_tariffs IS NOT NULL AS is_transfer_item  -- KK 07/21/2026
        FROM preftz.receipts r 	
        INNER JOIN preftz.parts p ON r.part_number = p.part_number	
        INNER JOIN preftz.part_classifications pc ON p.part_number = pc.part_number	
        INNER JOIN prehts.tariff_types tt ON pc.tariff_type = tt.tariff_type	
        LEFT JOIN preftz.receipt_case_numbers rcn ON r.receiptid = rcn.receiptid	
        LEFT JOIN (
            SELECT o.part_number, o.harmonized_tariff_schedule_number
            FROM preftz.part_classifications o	
            WHERE o.tariff_type IN ('OVERRIDE','MTB')
        ) q	ON r.part_number = q.part_number	
        LEFT JOIN preftz.receipt_cast_and_smelt rcs ON r.receiptid = rcs.receiptid	
        LEFT JOIN ztz_details ztzd ON ztzd.receiptid = r.receiptid
        WHERE r.zone_admission_no = p_admission_number
            AND pc.tariff_type <> 'SCRAP'
            AND r.receiptid = 284598
        ORDER BY r.receiptid, CASE pc.tariff_type WHEN 'BASE' THEN 0 ELSE 9 END
  )
  LOOP	

   -- EG 06/11/2026
   -- may be overridden by privileged date from transfer item file if additional tariffs are present.
      
      IF p_classify_date IS NULL THEN
          v_classify_date := COALESCE(crs.privileged_date, CURRENT_DATE);
      ELSE
          v_classify_date := p_classify_date;
      END IF;


      IF crs.zone_status <> 'D'	
      THEN	
          receipt_result = 'PASS';	
          	
          SELECT preftz.validate_classification 	
                (crs.harmonized_tariff_schedule_number, crs.special_programs_indicator, crs.country_of_origin, 	
                 v_classify_date)	
            INTO v_classification;	
	
          IF v_classification = 'FAIL' THEN	
              v_result = 'FAIL';	
              receipt_result = 'FAIL';	
              	
              INSERT INTO preftz.data_audit_messages 	
                     (audit_document, audit_message)	
              VALUES (p_admission_number, 'Invalid HTS ' || crs.harmonized_tariff_schedule_number ||	
                      ' for part ' || crs.part_number);	
	
          ELSE	
              v_tariff_number = TRIM(SUBSTR(v_classification,1,10));	
              v_special_program = TRIM(SUBSTR(v_classification,11,2));	
              v_zone_status = crs.zone_status;	
              	
              --RTJ 11/30/2022	
              IF crs.tariff_type = 'BASE' AND crs.is_transfer_item = FALSE THEN   -- KK 07/21/2026 do not test bounds if ZTZ transfer
                  v_base_hts = crs.harmonized_tariff_schedule_number; 	
              	
                  --RTJ 01/17/2023	
                  v_unit_value = crs.unit_value;	
                  v_bounds_hts = preftz.get_bounds_hts(crs.part_number, v_unit_value);	
                  	
                  IF v_bounds_hts = 'MISSINGHTS' THEN	
                     v_result = 'FAIL';	
                     receipt_result = 'FAIL';	
                     	
                     INSERT INTO preftz.data_audit_messages	
                            (audit_document, audit_message, action_code, audit_reference)	
                     VALUES (p_admission_number, 'Missing bounds HTS for part ' || crs.part_number ||	
                             ' and value ' || v_unit_value, 'ADDBOUNDS', crs.receiptid);	
                             	
                  ELSIF v_bounds_hts = 'EDITBOUNDS' THEN	
                      v_result = 'FAIL';	
                      receipt_result = 'FAIL';	
                      	
                     INSERT INTO preftz.data_audit_messages	
                            (audit_document, audit_message, action_code, audit_reference)	
                     VALUES (p_admission_number, 'Overlapping bounds HTS for part ' || crs.part_number ||	
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
                          VALUES (p_admission_number, 'Invalid bounds HTS ' || v_bounds_hts ||	
                                  ' for part ' || crs.part_number || ' and value ' || v_unit_value,	
                                  'EDITBOUNDS', crs.receiptid);	
                                  	
                      ELSE	
                          v_base_hts = v_bounds_hts;	
                          v_tariff_number = TRIM(SUBSTR(v_classification,1,10));	
                          v_special_program = TRIM(SUBSTR(v_classification,11,2));	
                      END IF;	
                  END IF;  --bounds hts check	
                  --RTJ 01/17/2023	
                  	
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
                        crs.part_number, crs.receiptid, v_tariff_number, crs.country_of_origin, v_classify_date, crs.special_programs_indicator,
                        crs.country_of_cast, crs.primary_country_of_smelt, crs.secondary_country_of_smelt);
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
                          VALUES (p_admission_number, 'Invalid additional HTS ' || v_additional_tariff ||	
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
                  IF (v_zone_status = 'P') AND (v_add_hts_count = 0 ) THEN	
                      UPDATE preftz.receipts r	
                         SET privileged_date = COALESCE(r.privileged_date,r.receipt_date,v_classify_date) --NKM 09/18/2023	
                       WHERE r.receiptid = crs.receiptid;	
                  END IF;	
                  --RTJ 05/24/2021	
                  
                  
                  -- EG 3/10/2026
                  IF (v_zone_status = 'P') AND (v_add_hts_count > 0)
                  THEN	
                      UPDATE preftz.receipts r	
                         SET privileged_date = v_classify_date --actually a privileged date provided in transfer item file
                      WHERE r.receiptid = crs.receiptid;	
                      
                      RAISE NOTICE '------------------------------------------------preftz.receipts was updated with v_classify_date from transfer_ztz_archive:%,  %', v_classify_date, crs.receiptid; 
                  END IF;	
                  -- EG 3/10/2026
	              
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

-- EG 06/11/2026 strip IEEPA from those receipts on an Entry document
    RAISE NOTICE 'Removing IEEPA tariffs from those receipts...';
    WITH added_tariffs AS (
        SELECT DISTINCT rc.receiptid, rc.harmonized_tariff_schedule_number, rc.tariff_type
        from preftz.receipt_classifications rc
        where rc.tariff_type <> 'BASE'
        AND rc.receiptid = crs.receiptid
    ), target_tariffs AS (
        SELECT adt.receiptid, adt.harmonized_tariff_schedule_number, adt.tariff_type
        FROM preftz.tariff_reclassifications_for_entry tre
        JOIN added_tariffs adt ON adt.harmonized_tariff_schedule_number = tre.from_tariff_number
            AND adt.tariff_type = tre.from_tariff_type
        WHERE COALESCE(tre.to_tariff_number,'') = ''
    )
    DELETE FROM preftz.receipt_classifications rc
    USING target_tariffs tt
    WHERE tt.receiptid = rc.receiptid
        AND tt.harmonized_tariff_schedule_number = rc.harmonized_tariff_schedule_number
        AND tt.tariff_type = rc.tariff_type
    ;



  END LOOP;	

  INSERT INTO preftz.system_log (procedure_name, log_message) 	
  VALUES ('classify_receipts', 'ended: ' || p_admission_number || ' ' || v_result);	
          	
  RETURN v_result;	
	
END; 	
$BODY$;





