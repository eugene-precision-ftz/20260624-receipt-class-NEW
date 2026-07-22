--DROP FUNCTION IF EXISTS preftz.classify_receipts_v2();
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

     IF v_result = 'FAIL'
     THEN
        INSERT INTO preftz.system_log(procedure_name, log_message, details)
        VALUES ('classify_receipts_v2', 'finished generate_tmp_receipt_classification_data with failure', now());
        RETURN v_result;
      END IF;


RAISE NOTICE 'tmp_receipt_classification_data rows: %',
    (SELECT COUNT(*) FROM tmp_receipt_classification_data);

RAISE NOTICE 'tmp_receipt_classification_data receipts: %',
    (SELECT COUNT(DISTINCT receiptid) FROM tmp_receipt_classification_data);

    v_result := preftz.generate_tmp_receipt_classification_work();     

RAISE NOTICE 'tmp_receipt_classification_work rows: %',
    (SELECT COUNT(*) FROM tmp_receipt_classification_work);

RAISE NOTICE 'tmp_receipt_classification_work receipts: %',
    (SELECT COUNT(DISTINCT receiptid) FROM tmp_receipt_classification_work);    

    if (p_update_flag AND v_result = 'PASS')
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

           END IF;--if (p_update_flag AND v_result = 'PASS')


    -- Log finish
    INSERT INTO preftz.system_log(procedure_name, log_message, details)
    VALUES ('classify_receipts_v2' , 'ended: ' || p_admission_number || ' ' || v_result, now());

    RETURN v_result;


EXCEPTION WHEN OTHERS THEN
    
    INSERT INTO preftz.system_log(procedure_name, log_message, details)
    VALUES ('classify_receipts_v2', 'ERROR: ' || SQLERRM, now());
    RAISE;
END;
$function$;

