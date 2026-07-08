--DROP FUNCTION IF EXISTS preftz.create_receipt_classifications(character varying, DATE, integer);
CREATE OR REPLACE FUNCTION preftz.generate_tmp_receipt_classification_data (
    p_admission_number character varying,	
    p_classify_date DATE DEFAULT NULL::date,
    p_receiptid integer DEFAULT NULL::integer
)
RETURNS character varying
LANGUAGE plpgsql
AS $function$

--Change Log: 
--EG Original 6/24/2024

DECLARE
     v_result             VARCHAR(10);  --PASS or FAIL	
     crs                  RECORD;
     v_zone_admission_no  VARCHAR(10);
     v_skip_added_tariffs BOOLEAN DEFAULT false;
     v_add_hts_count      INTEGER; 
     before_messageid     INTEGER;	
     after_messageid      INTEGER;
     v_privileged_date    DATE;

    v_steel_poured_in_us          BOOLEAN;
    v_cast_smelt_in_us            BOOLEAN;
    v_steel_poured_in_uk          BOOLEAN;
    v_cast_smelt_in_uk            BOOLEAN;

    v_301_exclusion              VARCHAR(10);
    v_232_exclusion              VARCHAR(10);
    v_chapter98_override         VARCHAR(10);
    v_used_for_production_or_repair  BOOLEAN DEFAULT FALSE;
    v_exclusion_tariffs           VARCHAR(10)[] DEFAULT '{}'::VARCHAR(10)[];

    v_aluminum_percentage         DOUBLE PRECISION;
    v_steel_percentage            DOUBLE PRECISION;
    v_copper_percentage           DOUBLE PRECISION;

    v_unit_net_weight                      NUMERIC DEFAULT NULL;
    v_steel_content_weight                 NUMERIC DEFAULT NULL;
    v_aluminum_content_weight              NUMERIC DEFAULT NULL;
    v_copper_content_weight                NUMERIC DEFAULT NULL;

    v_moto_exclusion                       VARCHAR DEFAULT NULL;
    v_is_usmca_special_treatment           BOOLEAN;
    v_is_agricultural_or_industrial        BOOLEAN;
    v_percent_us_content                   NUMERIC DEFAULT NULL;

    v_receipt_value                        DOUBLE PRECISION;



BEGIN
    -- Log start
    INSERT INTO preftz.system_log(procedure_name, log_message, details)
    VALUES ('generate_tmp_receipt_classification_data', 'started', NOW());

            -- IF (SELECT direct_delivery_indicator FROM preftz.ftz_reference) = 'N' 
            -- THEN

    v_result := 'PASS';

    v_zone_admission_no := p_admission_number;

    DROP TABLE IF EXISTS tmp_receipt_classification_data;

    CREATE TEMPORARY TABLE tmp_receipt_classification_data (
        id serial4 PRIMARY KEY,
        receiptid int4 NULL,
        created_date timestamp DEFAULT now(),
        admission_number character varying,
        skip_added_tariffs   BOOLEAN DEFAULT false,

        part_number varchar(50) NULL,
        zone_status varchar(1) NULL,
        country_of_origin char(2) NULL,
        unit_price float8 NULL,
        harmonized_tariff_schedule_number varchar(10) NULL,
        special_programs_indicator char(2) NULL,
        split_fixed_unit_value float8 NULL,
        split_value_percentage float8 NULL,
        value_reported varchar(5) NULL,
        tariff_type varchar(15) NULL,
        distinct_tariff_line_indicator char(1) NULL,
        primary_tariff char(1) NULL,
        quantity1_rate float8 NULL,
        quantity2_rate float8 NULL,
        antidumping_case_number varchar(13) NULL,
        countervailing_case_number varchar(13) NULL,
        country_of_cast varchar(3) NULL,
        primary_country_of_smelt varchar(3) NULL,
        secondary_country_of_smelt varchar(3) NULL,
        override_tariff varchar(10) NULL,
        unit_value float8 NULL,
        privileged_date date NULL,
        new_zone_status varchar(1) NULL,

        steel_poured_in_us          BOOLEAN NULL,
        cast_smelt_in_us            BOOLEAN NULL,
        steel_poured_in_uk          BOOLEAN NULL,
        cast_smelt_in_uk            BOOLEAN NULL,

        v301_exclusion               VARCHAR(10) NULL,
        v232_exclusion               VARCHAR(10) NULL,
        chapter98_override          VARCHAR(10) NULL,
        used_for_production_or_repair  BOOLEAN DEFAULT FALSE,
        exclusion_tariffs            VARCHAR(10)[] DEFAULT '{}'::VARCHAR(10)[],

        aluminum_percentage         DOUBLE PRECISION NULL,
        steel_percentage            DOUBLE PRECISION NULL,
        copper_percentage           DOUBLE PRECISION NULL,

        unit_net_weight             NUMERIC DEFAULT NULL,
        steel_content_weight        NUMERIC DEFAULT NULL,
        aluminum_content_weight     NUMERIC DEFAULT NULL,
        copper_content_weight       NUMERIC DEFAULT NULL,

        moto_exclusion                VARCHAR DEFAULT NULL,
        is_usmca_special_treatment    BOOLEAN NULL,
        is_agricultural_or_industrial BOOLEAN NULL,
        percent_us_content            NUMERIC DEFAULT NULL,

        receipt_value                 DOUBLE PRECISION NULL
    ) 
    ON COMMIT PRESERVE ROWS
    ;

    CREATE INDEX tmp_receipt_classification_data_receiptid_idx ON tmp_receipt_classification_data(receiptid);

    if p_receiptid IS NOT NULL THEN
       v_zone_admission_no := null;
       SELECT r.zone_admission_no
       INTO v_zone_admission_no
       FROM preftz.receipts r
       WHERE r.receiptid = p_receiptid;	
    end if;

     SELECT COALESCE(MAX(messageid),0) INTO before_messageid FROM preftz.data_audit_messages;	
  	
    --  INSERT INTO preftz.data_audit_messages (audit_document, audit_message)	
    --  SELECT DISTINCT trc.admission_number, 'Missing classification for part ' || trc.part_number	
    --    FROM tmp_receipt_classification_data trc	
    --          LEFT JOIN preftz.parts p	
    --                 ON trc.part_number = p.part_number	
    --          LEFT JOIN preftz.part_classifications pc	
    --                 ON p.part_number = pc.part_number	
    --   WHERE pc.harmonized_tariff_schedule_number IS NULL;	

       INSERT INTO preftz.data_audit_messages (audit_document, audit_message)
       SELECT DISTINCT
              r.zone_admission_no,
              'Missing classification for part ' || r.part_number
       FROM preftz.receipts r
       LEFT JOIN preftz.parts p
         ON p.part_number = r.part_number
       LEFT JOIN preftz.part_classifications pc
         ON pc.part_number = p.part_number
        AND pc.tariff_type <> 'SCRAP'
       WHERE r.zone_admission_no = v_zone_admission_no
         AND (p_receiptid IS NULL OR r.receiptid = p_receiptid)
         AND pc.harmonized_tariff_schedule_number IS NULL;
        	
     SELECT COALESCE(MAX(messageid),0) INTO after_messageid FROM preftz.data_audit_messages;

     IF after_messageid > before_messageid 
     THEN
        v_result := 'FAIL';

        INSERT INTO preftz.system_log(procedure_name, log_message, details)
        VALUES ('generate_tmp_receipt_classification_data', 'finished with validation failure', now());

        RETURN v_result;

      END IF;



    SELECT COALESCE(bypass_added_tariffs, false) 	
    INTO v_skip_added_tariffs	
    FROM preftz.e214_filing_statuses	
    WHERE zone_admission_no = v_zone_admission_no;	
    

    INSERT INTO tmp_receipt_classification_data 
    (
     receiptid
    ,admission_number
    ,skip_added_tariffs
    ,part_number
    ,zone_status
    ,country_of_origin
    ,unit_price
    ,harmonized_tariff_schedule_number
    ,special_programs_indicator
    ,split_fixed_unit_value
    ,split_value_percentage
    ,value_reported
    ,tariff_type
    ,distinct_tariff_line_indicator
    ,primary_tariff
    ,quantity1_rate
    ,quantity2_rate
    ,antidumping_case_number
    ,countervailing_case_number
    ,country_of_cast
    ,primary_country_of_smelt
    ,secondary_country_of_smelt
    ,override_tariff
    ,unit_value
    ,privileged_date
   )
    SELECT 
     r.receiptid
    ,r.zone_admission_no
    ,v_skip_added_tariffs
    ,r.part_number
    ,r.zone_status
    ,r.country_of_origin
    ,r.unit_price
    ,pc.harmonized_tariff_schedule_number
    ,p.special_programs_indicator
    ,pc.split_fixed_unit_value
    ,pc.split_value_percentage
    ,tt.value_reported
    ,pc.tariff_type
    ,pc.distinct_tariff_line_indicator
    ,pc.primary_tariff
    ,pc.quantity1_conversion_rate quantity1_rate
    ,pc.quantity2_conversion_rate quantity2_rate
    ,rcn.antidumping_case_number
    ,rcn.countervailing_case_number
    ,rcs.country_of_cast
    ,rcs.primary_country_of_smelt
    ,rcs.secondary_country_of_smelt
    ,q.harmonized_tariff_schedule_number override_tariff
    ,preftz.get_receipt_value(r.receiptid) unit_value
    ,COALESCE(r.privileged_date, r.receipt_date, CURRENT_DATE)
                    FROM preftz.receipts r 	
                     INNER JOIN preftz.parts p 	
                             ON r.part_number = p.part_number	
                     INNER JOIN preftz.part_classifications pc	
                             ON p.part_number = pc.part_number	
                     INNER JOIN prehts.tariff_types tt	
                             ON pc.tariff_type = tt.tariff_type	
                      LEFT JOIN preftz.receipt_case_numbers rcn 
                             ON r.receiptid = rcn.receiptid	
                      LEFT JOIN (SELECT o.part_number, o.harmonized_tariff_schedule_number 
                                   FROM preftz.part_classifications o	
                                  WHERE o.tariff_type IN ('OVERRIDE','MTB')) q	
                             ON r.part_number = q.part_number	
                      LEFT JOIN preftz.receipt_cast_and_smelt rcs
                             ON r.receiptid = rcs.receiptid	
               WHERE r.zone_admission_no = v_zone_admission_no	
                 AND pc.tariff_type <> 'SCRAP'
               ORDER BY r.receiptid, CASE pc.tariff_type WHEN 'BASE' THEN 0 ELSE 9 end
               ;

    if p_receiptid IS NOT NULL 
    THEN
      DELETE FROM tmp_receipt_classification_data
      WHERE receiptid <> p_receiptid;
    end if;

   -- may be overridden by privileged date from transfer item file if additional tariffs are present.


      IF p_classify_date IS NOT NULL THEN
        update tmp_receipt_classification_data
        set privileged_date = p_classify_date
        ;
      END IF;



    /* 
     
    --this can be used instead of loop if loop will not have any new logic added in future. 
    --But loop is used to make it more readable and easy to maintain. 

      UPDATE tmp_receipt_classification_data trc
      SET privileged_date = t.privileged_date
      FROM preftz.transfer_ztz_archive t
      WHERE t.transfer_itemid = (
          SELECT x.get_transfer_itemid_from_ztz_receiptid
          FROM preftz.get_transfer_itemid_from_ztz_receiptid(trc.receiptid) x
      )
      AND t.privileged_date IS NOT NULL;
      */

              FOR crs IN 
                 SELECT trc.receiptid, trc.part_number, trc.privileged_date
                 FROM tmp_receipt_classification_data trc
                 GROUP BY trc.receiptid, trc.part_number, trc.privileged_date
                 ORDER BY trc.receiptid, trc.part_number, trc.privileged_date
                 LOOP
                    v_privileged_date := crs.privileged_date;

                    --this will be > 0 ONLY if we have privileged date provided in transfer item file for this receipt. 
                    SELECT 
                    count(*)
                    into v_add_hts_count
                    FROM preftz.transfer_ztz_archive t 
                    WHERE transfer_itemid =
                      (
                       SELECT get_transfer_itemid_from_ztz_receiptid as transfer_itemid 
                       FROM preftz.get_transfer_itemid_from_ztz_receiptid(crs.receiptid)
                      )
                    AND t.privileged_date IS NOT NULL;
                    
                    
                    IF (v_add_hts_count > 0 ) --transfer archive has privileged date for this receipt
                    THEN
                    -- get a privileged date provided in transfer item file
                          SELECT  t.privileged_date 
                          INTO v_privileged_date
                          FROM preftz.transfer_ztz_archive t 
                          WHERE 
                           transfer_itemid =
                           (
                              SELECT get_transfer_itemid_from_ztz_receiptid as transfer_itemid 
                              FROM preftz.get_transfer_itemid_from_ztz_receiptid(crs.receiptid)
                           );

                          UPDATE tmp_receipt_classification_data
                          SET privileged_date = v_privileged_date
                          where receiptid = crs.receiptid;
                    END IF;

                    --used in get_all_additional_tariffs_struc_v2
                    -- Is melted and poured in US

                    SELECT EXISTS (
                        SELECT receiptid
                        FROM preftz.receipt_melt_and_pour
                        WHERE receiptid = crs.receiptid
                            AND country_of_melt = 'US' 
                            AND country_of_pour = 'US'
                    )
                    INTO v_steel_poured_in_us;
                
                    -- Is cast and smelt in US
                    SELECT EXISTS (
                        SELECT receiptid
                        FROM preftz.receipt_cast_and_smelt
                        WHERE receiptid = crs.receiptid
                            AND country_of_cast = 'US' 
                            AND primary_country_of_smelt = 'US'
                    )
                    INTO v_cast_smelt_in_us;
                
                    -- Is melted and poured in GB
                    SELECT EXISTS (
                        SELECT receiptid
                        FROM preftz.receipt_melt_and_pour
                        WHERE receiptid = crs.receiptid
                            AND country_of_melt = 'GB' 
                            AND country_of_pour = 'GB'
                    )
                    INTO v_steel_poured_in_uk;
                
                    -- Is cast and smelt in GB
                    SELECT EXISTS (
                        SELECT receiptid
                        FROM preftz.receipt_cast_and_smelt
                        WHERE receiptid = crs.receiptid
                            AND country_of_cast = 'GB' 
                            AND primary_country_of_smelt = 'GB'
                    )
                    INTO v_cast_smelt_in_uk;

                    update tmp_receipt_classification_data
                    set 
                        steel_poured_in_us = v_steel_poured_in_us,
                        cast_smelt_in_us = v_cast_smelt_in_us,
                        steel_poured_in_uk = v_steel_poured_in_uk,
                        cast_smelt_in_uk = v_cast_smelt_in_uk
                    where receiptid = crs.receiptid;                    

                   --used in get_added_tariffs_struc_v2
                   SELECT p.section_232_exclusion_number, pc301.harmonized_tariff_schedule_number, 
                       pc98.harmonized_tariff_schedule_number, COALESCE(pe.used_for_production_or_repair,false),
                       COALESCE(pe.chapter99_exclusion_tariffs, '{}'::VARCHAR[])
                   INTO v_232_exclusion, v_301_exclusion, v_chapter98_override, v_used_for_production_or_repair, v_exclusion_tariffs
                   FROM preftz.parts p
                   LEFT JOIN preftz.part_classifications pc301 ON pc301.part_number = p.part_number
                       AND pc301.tariff_type = 'EXCLUSION301'
                   LEFT JOIN preftz.part_classifications pc98 ON pc98.part_number = p.part_number
                       AND pc98.tariff_type = 'OVERRIDE'
                   LEFT JOIN preftz.parts_extension pe ON pe.part_number = p.part_number
                   WHERE p.part_number = crs.part_number;

                    update tmp_receipt_classification_data
                    set 
                        v301_exclusion = v_301_exclusion,
                        v232_exclusion = v_232_exclusion,
                        chapter98_override = v_chapter98_override,
                        used_for_production_or_repair = v_used_for_production_or_repair,
                        exclusion_tariffs = v_exclusion_tariffs
                    where receiptid = crs.receiptid;


                    -- used in get_added_derivative_tariffs_struc_v2
                     SELECT aluminum_percentage, steel_percentage, copper_percentage
                     INTO v_aluminum_percentage, v_steel_percentage, v_copper_percentage
                     FROM preftz.derivative_parts_content
                     WHERE part_number = crs.part_number
                     AND v_privileged_date BETWEEN start_date AND end_date;

                     UPDATE tmp_receipt_classification_data
                     SET
                         aluminum_percentage = v_aluminum_percentage,
                         steel_percentage = v_steel_percentage,
                         copper_percentage = v_copper_percentage
                     WHERE receiptid = crs.receiptid;                     


                     --used in filter_section232_tariffs_struc_v2
                     SELECT rdc.steel_content_weight, rdc.aluminum_content_weight, rdc.copper_content_weight, rdc.unit_net_weight
                     INTO v_steel_content_weight, v_aluminum_content_weight, v_copper_content_weight, v_unit_net_weight
                     FROM preftz.receipt_derivative_content rdc 
                     WHERE rdc.receiptid = crs.receiptid;

                     UPDATE tmp_receipt_classification_data
                     SET
                         steel_content_weight = v_steel_content_weight,
                         aluminum_content_weight = v_aluminum_content_weight,
                         copper_content_weight = v_copper_content_weight,
                         unit_net_weight = v_unit_net_weight
                     WHERE receiptid = crs.receiptid;


                     --used in filter_section232_tariffs_struc_v2
                     SELECT '99038213'::varchar AS moto_exclusion
                     INTO v_moto_exclusion
                     FROM preftz.parts_extension pe
                     WHERE pe.part_number = crs.part_number
                     AND '99038213' = ANY(COALESCE(pe.chapter99_exclusion_tariffs, '{}'::VARCHAR[]));

                     -- AND is this product eligible for special tariff treatment under USMCA
                     SELECT EXISTS ( 
                       SELECT part_number
                       FROM preftz.parts_extension pe
                       WHERE pe.part_number = crs.part_number
                       AND pe.is_usmca_special_treatment = true)
                     INTO v_is_usmca_special_treatment;

                     -- AND is this product used exclusively for manufacturing agricultural equipment
                     SELECT EXISTS (  
                      SELECT part_number
                      FROM preftz.parts_extension pe
                      WHERE pe.part_number = crs.part_number
                      AND pe.is_agricultural_or_industrial = true)
                      INTO v_is_agricultural_or_industrial;

                      -- get content
                      SELECT COALESCE(percent_us_value, 0.0)
                      INTO v_percent_us_content
                      FROM preftz.receipt_percentage_value 
                      WHERE receiptid = crs.receiptid;

                     UPDATE tmp_receipt_classification_data
                     SET
                         moto_exclusion                  = v_moto_exclusion
                         ,is_usmca_special_treatment     = v_is_usmca_special_treatment
                         ,is_agricultural_or_industrial  = v_is_agricultural_or_industrial
                         ,percent_us_content             = v_percent_us_content
                     WHERE receiptid = crs.receiptid;

                    --used in calculate_duty_liability_v2
                      SELECT preftz.get_receipt_value(crs.receiptid)
                      INTO v_receipt_value;

                     UPDATE tmp_receipt_classification_data
                     SET
                         receipt_value    = v_receipt_value
                     WHERE receiptid = crs.receiptid;

                END LOOP;

/*                

RAISE NOTICE 'tmp_receipt_classification_data rows: %',
    (SELECT COUNT(*) FROM tmp_receipt_classification_data);

RAISE NOTICE 'tmp_receipt_classification_data receipts: %',
    (SELECT COUNT(DISTINCT receiptid) FROM tmp_receipt_classification_data);

    v_result := preftz.calculate_receipt_classifications();     

RAISE NOTICE 'tmp_receipt_classification_work rows: %',
    (SELECT COUNT(*) FROM tmp_receipt_classification_work);

RAISE NOTICE 'tmp_receipt_classification_work receipts: %',
    (SELECT COUNT(DISTINCT receiptid) FROM tmp_receipt_classification_work);    

    if p_update_flag 
    THEN
    --delete from preftz.receipt_classifications_v2 for the receipts in this admission number 
    --and insert new records from tmp_receipt_classification_data
        DELETE FROM preftz.receipt_classifications_v2 rc
        USING (
            SELECT DISTINCT receiptid
            FROM tmp_receipt_classification_work
        ) w
        WHERE rc.receiptid = w.receiptid;

          INSERT INTO preftz.receipt_classifications_v2
          (
              receiptid,
              created_date,
              harmonized_tariff_schedule_number,
              special_programs_indicator,
              unit_value,
              tariff_type,
              distinct_tariff_line_indicator,
              primary_tariff,
              quantity1_rate,
              quantity2_rate,
              unit_duty_liability
          )
          SELECT
              receiptid,
              created_date,
              harmonized_tariff_schedule_number,
              special_programs_indicator,
              unit_value,
              tariff_type,
              distinct_tariff_line_indicator,
              primary_tariff,
              quantity1_rate,
              quantity2_rate,
              unit_duty_liability
          FROM tmp_receipt_classification_work;       

    END IF;
*/    


                --   IF v_zone_status <> crs.zone_status THEN	
                --       UPDATE preftz.receipts r	
                --          SET zone_status = v_zone_status	
                --        WHERE r.receiptid = crs.receiptid;	
                       	
                --       UPDATE preftz.inventory_items ii	
                --          SET zone_status = v_zone_status	
                --        WHERE ii.receiptid = crs.receiptid;	
                --   END IF;	
                  	
                --   --RTJ 05/24/2021	
                --   IF (v_zone_status = 'P') AND (v_add_hts_count = 0 ) THEN	
                --       UPDATE preftz.receipts r	
                --          SET privileged_date = COALESCE(r.privileged_date,r.receipt_date,v_classify_date) --NKM 09/18/2023	
                --        WHERE r.receiptid = crs.receiptid;	
                --   END IF;	
                --   --RTJ 05/24/2021	
                  
                  
                --   -- EG 3/10/2026
                --   IF (v_zone_status = 'P') AND (v_add_hts_count > 0)
                --   THEN	
                --       UPDATE preftz.receipts r	
                --          SET privileged_date = v_classify_date --actually a privileged date provided in transfer item file
                --       WHERE r.receiptid = crs.receiptid;	
                      
                --       RAISE NOTICE '------------------------------------------------preftz.receipts was updated with v_classify_date from transfer_ztz_archive:%,  %', v_classify_date, crs.receiptid; 
                --   END IF;	
                --   -- EG 3/10/2026


    -- Log finish
    INSERT INTO preftz.system_log(procedure_name, log_message, details)
    VALUES ('create_receipt_classifications' , 'ended: '|| v_result, now());

    RETURN v_result;

EXCEPTION WHEN OTHERS THEN
    
    INSERT INTO preftz.system_log(procedure_name, log_message, details)
    VALUES ('create_receipt_classifications', 'ERROR: ' || SQLERRM, now());
    RAISE;
END;
$function$;

