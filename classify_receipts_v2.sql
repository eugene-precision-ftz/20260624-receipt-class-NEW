DROP FUNCTION IF EXISTS preftz.classify_receipts_v2(
    character varying,
    date,
    integer,
    boolean
);


CREATE OR REPLACE FUNCTION preftz.classify_receipts_v2 (
    p_admission_number character varying,	
    p_classify_date DATE DEFAULT NULL::date,
    p_receiptid integer DEFAULT NULL::integer,
    p_update_flag boolean DEFAULT false
)
RETURNS character varying
LANGUAGE plpgsql
AS $function$

--Change Log: 
--EG Original 6/24/2024

DECLARE
     v_result             VARCHAR(10);  --PASS or FAIL	
BEGIN
    -- Log start
    INSERT INTO preftz.system_log(procedure_name, log_message, details)
    VALUES ('classify_receipts_v2', 'started', NOW());

    v_result := 'PASS';

    IF p_admission_number IS NULL AND p_receiptid IS NULL THEN
        v_result := 'FAIL';
    
        INSERT INTO preftz.system_log(procedure_name, log_message, details)
        VALUES (
            'classify_receipts_v2',
            'failed: p_admission_number and p_receiptid are both null',
            now()
        );
    
        RETURN v_result;
    END IF;


    IF p_admission_number IS NOT NULL 
    THEN
        v_result := preftz.generate_tmp_receipt_classification_data(p_admission_number, p_classify_date, p_receiptid);
    END IF;

    IF p_admission_number IS NULL AND p_receiptid IS NOT NULL
    THEN
        v_result := preftz.generate_tmp_receipt_classification_data(NULL, p_classify_date, p_receiptid);
    END IF;

    IF COALESCE(v_result, 'FAIL') <> 'PASS' THEN
        v_result := 'FAIL';
    
        INSERT INTO preftz.system_log
            (procedure_name, log_message, details)
        VALUES
            (
                'classify_receipts_v2',
                'generate_tmp_receipt_classification_data failed',
                NOW()
            );
    
        RETURN v_result;
    END IF;


    RAISE NOTICE 'tmp_receipt_classification_data rows: %',   (SELECT COUNT(*) FROM tmp_receipt_classification_data);
    RAISE NOTICE 'tmp_receipt_classification_data receipts: %', (SELECT COUNT(DISTINCT receiptid) FROM tmp_receipt_classification_data);

    v_result := preftz.generate_tmp_receipt_classification_work();     

    RAISE NOTICE 'tmp_receipt_classification_work rows: %', (SELECT COUNT(*) FROM tmp_receipt_classification_work);
    RAISE NOTICE 'tmp_receipt_classification_work receipts: %', (SELECT COUNT(DISTINCT receiptid) FROM tmp_receipt_classification_work);


    if (v_result = 'PASS')
    THEN
    --delete from preftz.receipt_classifications_v2 for the receipts in this admission number 
    --and insert new records from tmp_receipt_classification_work
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

    END IF;--if (v_result = 'PASS')          

/*
    if (p_update_flag AND v_result = 'PASS')
    THEN
        
            WITH receipt_updates AS
        (
            SELECT
                tmp.receiptid,
                MAX(tmp.new_zone_status) AS new_zone_status,
                MAX(tmp.privileged_date) AS privileged_date
            FROM tmp_receipt_classification_data tmp
            GROUP BY tmp.receiptid
        )
        UPDATE preftz.receipts r
        SET
            zone_status = u.new_zone_status,
            privileged_date =
                CASE
                    WHEN u.new_zone_status = 'P'
                        THEN u.privileged_date
                    ELSE r.privileged_date
                END
        FROM receipt_updates u
        WHERE r.receiptid = u.receiptid;
        
        WITH receipt_updates AS
        (
            SELECT
                tmp.receiptid,
                MAX(tmp.new_zone_status) AS new_zone_status
            FROM tmp_receipt_classification_data tmp
            GROUP BY tmp.receiptid
        )
        UPDATE preftz.inventory_items ii
        SET zone_status = u.new_zone_status
        FROM receipt_updates u
        WHERE ii.receiptid = u.receiptid;

      ---!!!!  delete and  insert  into receipt_classifications table

        DELETE FROM preftz.receipt_classifications rc
        USING (
            SELECT DISTINCT receiptid
            FROM tmp_receipt_classification_work
        ) w
        WHERE rc.receiptid = w.receiptid;

          INSERT INTO preftz.receipt_classifications
          (
              receiptid,
--              created_date,
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
--              created_date,
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


    END IF;--if (p_update_flag AND v_result = 'PASS')
*/

    -- Log finish
    INSERT INTO preftz.system_log(procedure_name, log_message, details)
    VALUES ('classify_receipts_v2' , 'ended: ' || COALESCE(p_admission_number, '') || ' ' || v_result, now());

    RETURN v_result;

END;
$function$;

