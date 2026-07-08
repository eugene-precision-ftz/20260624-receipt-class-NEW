CREATE OR REPLACE FUNCTION preftz.generate_tmp_receipt_classification_work(
    )
    RETURNS character varying	
    LANGUAGE 'plpgsql'	
    COST 100	
    VOLATILE PARALLEL UNSAFE	
AS $BODY$	
	
--Change Log:
	
DECLARE	
  v_result            VARCHAR(10);  --PASS or FAIL
  receipt_result      VARCHAR(10);  --PASS or FAIL
  crs                 RECORD;	

   v_classification    VARCHAR(12);	
   v_tariff_number     VARCHAR(10);	
   v_special_program   VARCHAR(2);	
   v_zone_status       VARCHAR(1);
   v_base_hts          VARCHAR(10);
   v_bounds_hts        VARCHAR(10);
   v_unit_value        DOUBLE PRECISION;
   v_sec301_hts        VARCHAR(10);
   v_added_tariffs     VARCHAR;
   v_count             INTEGER;
   v_position          INTEGER;
   v_additional_status VARCHAR(1);
   v_additional_tariff VARCHAR(10);
   v_tariff_type       VARCHAR(15);

--   i                   INTEGER;	
--   derivative_rs       RECORD;  -- KK 04/17/2025	

  
BEGIN	
  INSERT INTO preftz.system_log (procedure_name, log_message) 	
  VALUES ('generate_tmp_receipt_classification_work', 'started');	

  v_result = 'PASS';	

    DROP TABLE IF EXISTS tmp_receipt_classification_work;

    CREATE TEMPORARY TABLE tmp_receipt_classification_work (
        receiptid int4 NOT NULL,
        created_date timestamp DEFAULT now(),
        harmonized_tariff_schedule_number varchar(10) NOT NULL,
        special_programs_indicator varchar(2) NULL,
        unit_value float8 NULL,
        tariff_type varchar(15) NULL,
        distinct_tariff_line_indicator char(1) NULL,
        primary_tariff char(1) NULL,
        quantity1_rate float8 NULL,
        quantity2_rate float8 NULL,
        unit_duty_liability float8 NULL,
        CONSTRAINT receipt_classifications_pkey PRIMARY KEY (receiptid, harmonized_tariff_schedule_number)
    )
    ON COMMIT PRESERVE ROWS
    ;


              FOR crs IN 
              (
                 SELECT 
                 trc.receiptid
                ,trc.admission_number
                ,trc.skip_added_tariffs
                ,trc.part_number
                ,trc.zone_status
                ,trc.country_of_origin
                ,trc.unit_price
                ,trc.harmonized_tariff_schedule_number
                ,trc.special_programs_indicator
                ,trc.split_fixed_unit_value
                ,trc.split_value_percentage
                ,trc.value_reported
                ,trc.tariff_type
                ,trc.distinct_tariff_line_indicator
                ,trc.primary_tariff
                ,trc.quantity1_rate
                ,trc.quantity2_rate
                ,trc.antidumping_case_number
                ,trc.countervailing_case_number
                ,trc.country_of_cast
                ,trc.primary_country_of_smelt
                ,trc.secondary_country_of_smelt
                ,trc.override_tariff
                ,trc.unit_value
                ,trc.privileged_date
                 FROM tmp_receipt_classification_data trc
                 --where receiptid in (210455,210454,210456)
                -- ORDER BY trc.receiptid,trc.id
                 ORDER BY trc.receiptid, CASE trc.tariff_type WHEN 'BASE' THEN 0 ELSE 9 END)  
                 --FOR UPDATE
                 LOOP

--RAISE NOTICE 'XXXXXXXXXXXXXXXXXXXX----------------------------------------- crs.tariff_type: %  ,  crs.receiptid: % '
--, crs.tariff_type, crs.receiptid ;

    

      IF crs.zone_status <> 'D'	
      THEN	
          receipt_result = 'PASS';	
          	
          SELECT preftz.validate_classification 	
                (crs.harmonized_tariff_schedule_number, crs.special_programs_indicator, crs.country_of_origin, 	
                 crs.privileged_date)	
            INTO v_classification;	
	
          IF v_classification = 'FAIL' THEN	
              v_result = 'FAIL';	
              receipt_result = 'FAIL';	
              	
              INSERT INTO preftz.data_audit_messages 	
                     (audit_document, audit_message)	
              VALUES (crs.admission_number, 'Invalid HTS ' || crs.harmonized_tariff_schedule_number ||	
                      ' for part ' || crs.part_number);	
	
          ELSE	
              v_tariff_number = TRIM(SUBSTR(v_classification,1,10));	
              v_special_program = TRIM(SUBSTR(v_classification,11,2));	
              v_zone_status = crs.zone_status;	

--RAISE NOTICE '11111111111111----------------------------------------- crs.tariff_type: %  ,  crs.receiptid: % '
--, crs.tariff_type, crs.receiptid ;

              	
              --RTJ 11/30/2022	
              IF crs.tariff_type = 'BASE' THEN 	
                  v_base_hts = crs.harmonized_tariff_schedule_number; 	
              	
                  --RTJ 01/17/2023	
                  v_unit_value = crs.unit_value;	
                  v_bounds_hts = preftz.get_bounds_hts(crs.part_number, v_unit_value);	
                  	
                  IF v_bounds_hts = 'MISSINGHTS' THEN	
                     v_result = 'FAIL';	
                     receipt_result = 'FAIL';	
                     	
                     INSERT INTO preftz.data_audit_messages	
                            (audit_document, audit_message, action_code, audit_reference)	
                     VALUES (crs.admission_number, 'Missing bounds HTS for part ' || crs.part_number ||	
                             ' and value ' || v_unit_value, 'ADDBOUNDS', crs.receiptid);	
                             	
                  ELSIF v_bounds_hts = 'EDITBOUNDS' THEN	
                      v_result = 'FAIL';	
                      receipt_result = 'FAIL';	
                      	
                     INSERT INTO preftz.data_audit_messages	
                            (audit_document, audit_message, action_code, audit_reference)	
                     VALUES (crs.admission_number, 'Overlapping bounds HTS for part ' || crs.part_number ||	
                             ' and value ' || v_unit_value, 'EDITBOUNDS', crs.receiptid);	
                         	
                  ELSIF v_bounds_hts <> v_base_hts THEN	
                      SELECT preftz.validate_classification 	
                            (v_bounds_hts, crs.special_programs_indicator, crs.country_of_origin, 	
                             crs.privileged_date)	
                        INTO v_classification;	
            	
                      IF v_classification = 'FAIL' THEN	
                          v_result = 'FAIL';	
                          receipt_result = 'FAIL';	
                          	
                          INSERT INTO preftz.data_audit_messages 	
                                 (audit_document, audit_message, action_code, audit_reference)	
                          VALUES (crs.admission_number, 'Invalid bounds HTS ' || v_bounds_hts ||	
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
                     AND a.start_date <= crs.privileged_date	
                     AND a.end_date >= crs.privileged_date	
                     AND a.tariff_type = 'SECTION301';	
    	
              END IF;	
              --RTJ 11/30/2022	
              
              
            
              IF crs.tariff_type IN ('BASE','SPLIT','SCRAP') 
              AND crs.skip_added_tariffs = false 
              THEN 
                    -- KK 10/15/2025 Refactored additional tariff logic
                    v_added_tariffs = preftz.get_all_additional_tariffs_string_v2 
                        (
                          crs.part_number, crs.receiptid, v_tariff_number
                        , crs.country_of_origin, crs.privileged_date, crs.special_programs_indicator
                        , crs.country_of_cast, crs.primary_country_of_smelt, crs.secondary_country_of_smelt
                        );
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
                            (v_additional_tariff, NULL, crs.country_of_origin, crs.privileged_date)	
                        INTO v_classification;	
            	
                      IF v_classification = 'FAIL' THEN	
                          v_result = 'FAIL';	
                          receipt_result = 'FAIL';	
                          	
                          INSERT INTO preftz.data_audit_messages	
                                 (audit_document, audit_message)	
                          VALUES (crs.admission_number, 'Invalid additional HTS ' || v_additional_tariff ||	
                                  ' for part/coo/tariff ' || crs.part_number || '/' || crs.country_of_origin ||	
                                  '/' || v_tariff_number);	
	
                      ELSE	
                        --MH 4/16/2025	
						IF NOT EXISTS(select 'x' from tmp_receipt_classification_work
                        where receiptid = crs.receiptid 	
                        and harmonized_tariff_schedule_number =v_additional_tariff	
                        and tariff_type =  v_tariff_type) THEN	
                            INSERT INTO tmp_receipt_classification_work
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

/*
if crs.receiptid = 210455 then
RAISE NOTICE '----------------------------------------- v_sec301_hts: %  ,  crs.skip_added_tariffs: %'
, v_sec301_hts, crs.skip_added_tariffs ;
end if;
*/

--' v_tariff_number: %', v_tariff_number, '  ' crs.tariff_type: %', crs.tariff_type; 

                  IF (crs.tariff_type <> 'EXCLUSION301' OR v_sec301_hts IS NOT NULL) AND 	
                         (crs.skip_added_tariffs = false OR (crs.skip_added_tariffs = true AND crs.tariff_type = 'BASE')) THEN  -- KK 05/06/2025	
					IF NOT EXISTS(select 'x' from tmp_receipt_classification_work 
                        where receiptid = crs.receiptid 	
                        and harmonized_tariff_schedule_number =v_tariff_number
                        and tariff_type =  crs.primary_tariff) THEN	 -- MH 5/7/2025 added if not exist then add to remove failure from duplicate issue
							  INSERT INTO tmp_receipt_classification_work 
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
                  IF crs.skip_added_tariffs = true THEN
                      v_zone_status = 'N';
                  END IF;


                   UPDATE tmp_receipt_classification_data r	
                   SET new_zone_status = v_zone_status	
                   WHERE r.receiptid = crs.receiptid;	

                  
                  -- KK 08/20/2025 update quantity1_rate based on derivative percentage
                  -- This is not very efficient, need to refactor calls to these procs after hot-fix
                  -- order is IMPORTANT! calculate_derivative_quantity needs to be called before duty calculations
                  IF LENGTH(v_added_tariffs) > 0 THEN	
                      CALL preftz.calculate_derivative_quantity_v2(crs.receiptid); 	
                  END IF;

                  CALL preftz.calculate_duty_liability_v2(crs.receiptid);  --RTJ 07/12/2021	
	           
                  -- If Derivative of steel or aluminum recalculate BASE and derivative tariffs	
                  IF LENGTH(v_added_tariffs) > 0 THEN	
                      CALL preftz.calculate_derivative_duty_liability_v2(crs.receiptid);
                  END IF;	
              	
              END IF; --IF receipt_result = 'PASS' THEN
            	
          END IF;  --valid HTS	
          
      END IF;  --zone status <> 'D'	

-- EG 06/11/2026 strip IEEPA from those receipts on an Entry document
    --RAISE NOTICE 'Removing IEEPA tariffs from those receipts...';
    WITH added_tariffs AS (
        SELECT DISTINCT rc.receiptid, rc.harmonized_tariff_schedule_number, rc.tariff_type
        from tmp_receipt_classification_work rc
        where rc.tariff_type <> 'BASE'
        AND rc.receiptid = crs.receiptid
    ), target_tariffs AS (
        SELECT adt.receiptid, adt.harmonized_tariff_schedule_number, adt.tariff_type
        FROM preftz.tariff_reclassifications_for_entry tre
        JOIN added_tariffs adt ON adt.harmonized_tariff_schedule_number = tre.from_tariff_number
            AND adt.tariff_type = tre.from_tariff_type
        WHERE COALESCE(tre.to_tariff_number,'') = ''
    )
    DELETE FROM tmp_receipt_classification_work rc
    USING target_tariffs tt
    WHERE tt.receiptid = rc.receiptid
        AND tt.harmonized_tariff_schedule_number = rc.harmonized_tariff_schedule_number
        AND tt.tariff_type = rc.tariff_type
    ;

  END LOOP;	


  INSERT INTO preftz.system_log (procedure_name, log_message) 	
  VALUES ('generate_tmp_receipt_classification_work', 'ended: '|| v_result);	
          	
  RETURN v_result;	
	
END; 	
$BODY$;




