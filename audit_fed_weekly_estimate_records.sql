-- PROCEDURE: preftz.audit_fed_weekly_estimate_records()

-- DROP PROCEDURE IF EXISTS  preftz.audit_fed_weekly_estimate_records();

CREATE OR REPLACE PROCEDURE preftz.audit_fed_weekly_estimate_records(
	)
LANGUAGE 'plpgsql'
AS $BODY$
    	
--CHANGE LOG 
-- EG 07/14/2026 Prevent bad chapter99 code with len > 10 going into batch delete and crash
-- KK 07/13/2026 Trim all chapter99 hts numbers in case a space accidentally got inserted
-- KK 03/03/2026 Remove validate_classification from chapter99 tariffs.
-- NO 01/13/2026 added release document number handling
-- MH 7/3/2025 changed id column for delete
-- MH 5/29/2025 added process estimate updates 
-- MH 3/20/2025  added coalesce for invalid part number msg
-- MH 3/13/2025 added additional_tariff_exceptions table for invalid additonal hts	
-- MH 02/12/2025B added part number to insert into weekly estimate records	
-- MH 02/12/2025 added ftz setting ESTIMATE INCLUDE PART and added v_duplicate_part_msg and v_invalid_part_msg 	
-- MH 10/28/2024 moved update add hts = {} to before delete  	
-- MH 10/22/2024 added audit of HTS Number is present as an additional HTS Number  	
-- KK 10/02/2024 if privileged date is missing, use oldest priv date from on-hand receipts, else use lowest priv date from HTS ref   	
-- MH 8/6/2024 added TRIM for additional hts number and call to preftz.batch_process_delete_records for duplicate records   	
-- MH 4/24/2024 added update if additional hts are emtpy    	
-- MH 2/6/2024 changed mid_code to id_code on archive table   	
-- MH 1/31/2023 fixed typo    	
-- MH 12/13/2023 added id to insert from fed tables    	
-- MH 12/7/2023 removed require date    	
-- MH 8/31/2023 original    	
    	
DECLARE    	
  v_table_name           VARCHAR(50) = 'fed_weekly_estimate_records';    	
  v_update_count         INTEGER;    	
  v_update_estimate_count  INTEGER;  
  rs                     RECORD;    	
      	
    	
  v_duplicate_msg   VARCHAR = 'Bypassed due to duplicate Release document, HTS Number. Check HTS/MID/COO and additional HTS Numbers'; 	
  v_duplicate_part_msg   VARCHAR = 'Bypassed due to duplicate Release document, HTS Number. Check HTS/MID/COO/PART and additional HTS Numbers'; 	
  v_missing_hts_msg      VARCHAR = 'HTS Number is missing';    	
  v_invalid_hts_msg      VARCHAR = 'HTS Number is invalid';    	
  v_invalid_adhts_msg      VARCHAR = 'Additional HTS Number is invalid';    	
  v_missing_coo_msg      VARCHAR = 'Country of Origin is missing';    	
  v_missing_qty_msg       VARCHAR = 'Quantity is either missing or equal to zero';    	
  v_negative_qty_msg     VARCHAR = 'Quantity is negative';    	
  v_missing_value_msg       VARCHAR = 'Value is missing';    	
  v_negative_value_msg      VARCHAR = 'Value is negative';    	
  v_missing_priv_for_msg     VARCHAR = 'Privileged Foreign is missing';    	
 -- v_missing_priv_date_msg      VARCHAR = 'Privileged Date is missing.';    	
  v_missing_mid_msg   VARCHAR = 'Manufacturer Mid Code is missing';    	
  v_missing_doc_msg   VARCHAR = 'Cargo Release Document is missing';    	
  v_invalid_doc_msg   VARCHAR = 'Cargo Release Document is missing';   	
  v_duplicate_add_hts_msg   VARCHAR = 'HTS Number is present as an additional HTS Number';    	
  v_classification      VARCHAR(12);    	
  v_duplicate_ids   INTEGER[];   	
  v_ftz_setting  VARCHAR; 	
  v_invalid_part_msg     VARCHAR = 'Part Number is not in parts list'; 	
BEGIN    	
    --Log Entry for procedure start    	
    INSERT INTO preftz.system_log (procedure_name,log_message)     	
        VALUES ('audit_fed_weekly_estimate_records','started');    	
    	
    INSERT INTO preftz.system_log (procedure_name, log_message)    	
    SELECT 'audit_fed_weekly_estimate_records', 'RECORD COUNT ' || TO_CHAR(COUNT(*),'999999')     	
      FROM preftz.fed_weekly_estimate_records;    	
    	
    --Delete records from feed_error for fed_balances    	
   DELETE from preftz.feed_errors    	
   WHERE table_name = v_table_name;   	
    	
    	
 Select get_ftz_setting 	
 into v_ftz_setting 	
 from preftz.get_ftz_setting('ESTIMATE INCLUDE PART'); 	
    	
    	
  -- MH 4/24/2024 remove any possible empty arrays   	
  UPDATE preftz.fed_weekly_estimate_records   	
  SET chapter99_hts_numbers = '{}'  	
  where chapter99_hts_numbers IN( '{"\"\""}','{""}');
  --COMMIT;    	
      	
    	
    --Delete duplicate records from fed table   	
 -- BEGIN MH 8/6/2024   	
 
    SELECT ARRAY(
    select fed_weekly_estimate_recordid from preftz.fed_weekly_estimate_records where fed_status = 'DUPLICATE'
    -- EG 07/14/2026
    and 
    fed_weekly_estimate_recordid not in
    (
       select fed_weekly_estimate_recordid from
       (
          select
          fed_weekly_estimate_recordid
          ,unnest(chapter99_hts_numbers)chapter99_hts_numbers  
          from preftz.fed_weekly_estimate_records
       ) t1
       where length(chapter99_hts_numbers)  > 10
    )
    -- EG 07/14/2026
    )   	
    into v_duplicate_ids;  
 
 raise notice 'dups ids %',v_duplicate_ids;
 CALL preftz.batch_process_delete_records('fed_weekly_estimate_records',v_duplicate_ids,'0');   	
  --  DELETE FROM preftz.fed_weekly_estimate_records WHERE fed_status = 'DUPLICATE';   	
  --  only delete records that have been successfully added to deleted table   	
   DELETE FROM preftz.fed_weekly_estimate_records where fed_weekly_estimate_recordid IN(    	
   SELECT fw.fed_weekly_estimate_recordid FROM     	
   preftz.fed_weekly_estimate_records  fw    	
   JOIN preftz.deleted_weekly_estimate_records dw on fw.fed_weekly_estimate_recordid = dw.fed_weekly_estimate_recordid   -- MH 7/3/2025   	
   WHERE fw.fed_status = 'DUPLICATE');   	
   GET DIAGNOSTICS v_update_count = ROW_COUNT;    	
  --END  MH 8/6/2024    	
    INSERT INTO preftz.system_log (procedure_name, log_message)     	
    VALUES ('audit_fed_weekly_estimate_records', 'PREVIOUS DUPLICATES ' || TO_CHAR(v_update_count,'999999'));    	
    	
    --reset fed status to NEW    	
    UPDATE preftz.fed_weekly_estimate_records SET fed_status = 'NEW';     	
        	
    --Capitalize, remove spaces, and/or set '' to NULL     	
    UPDATE preftz.fed_weekly_estimate_records    	
       SET     	
      		hts_number = NULLIF(TRIM(hts_number),''),    	
          country_of_origin= NULLIF(TRIM(country_of_origin),''),    	
   			  current_hts_number = NULLIF(TRIM(current_hts_number),''),    	
      	  manufacturer_id_code = NULLIF(TRIM(manufacturer_id_code),''),
          release_document_number = NULLIF(TRIM(release_document_number),'');
   
    -- NO 01/13/2026 Lookup release_documentid from release_document_number if only number is provided
    UPDATE preftz.fed_weekly_estimate_records fb
       SET release_documentid = rd.release_documentid
      FROM preftz.release_documents rd
     WHERE fb.release_document_number = rd.release_document_number
       AND fb.release_documentid IS NULL
       AND fb.release_document_number IS NOT NULL;
   	
    -- Default privileged date from receipts or HTS reference table, if missing - KK 10/02/2024   	
    WITH receipt_priv_dates AS (   	
        SELECT rc.harmonized_tariff_schedule_number, r.country_of_origin, r.manufacturer_mid_code,    	
            MIN(r.privileged_date) AS privileged_date   	
        FROM preftz.inventory_items ii   	
        JOIN preftz.receipt_classifications rc ON rc.receiptid = ii.receiptid   	
            AND rc.tariff_type = 'BASE'   	
        JOIN preftz.receipts r ON r.receiptid = rc.receiptid   	
        WHERE ii.quantity_on_hand > 0   	
        GROUP BY rc.harmonized_tariff_schedule_number, country_of_origin, manufacturer_mid_code   	
    ),   	
    priv_date_updates AS (   	
        SELECT wer.fed_weekly_estimate_recordid, htsr.record_begin_effective_date, rpd.privileged_date   	
        FROM preftz.fed_weekly_estimate_records wer   	
        JOIN preftz.release_documents rd ON rd.release_documentid = wer.release_documentid   	
        JOIN preftz.harmonized_tariff_schedule_reference htsr ON htsr.tariff_number = wer.hts_number   	
            AND htsr.record_begin_effective_date <= COALESCE(wer.privileged_date,rd.entry_summary_date)   	
            AND htsr.record_end_effective_date > COALESCE(wer.privileged_date,rd.entry_summary_date)   	
        LEFT JOIN receipt_priv_dates rpd ON rpd.harmonized_tariff_schedule_number = wer.hts_number    	
            AND rpd.country_of_origin = wer.country_of_origin   	
            AND rpd.manufacturer_mid_code = wer.manufacturer_id_code   	
        WHERE wer.privileged_foreign IS TRUE   	
            AND wer.privileged_date IS NULL   	
    )   	
    UPDATE preftz.fed_weekly_estimate_records fwer   	
    SET privileged_date = COALESCE(pdu.privileged_date, pdu.record_begin_effective_date, NULL)   	
    FROM priv_date_updates pdu   	
    WHERE fwer.fed_weekly_estimate_recordid = pdu.fed_weekly_estimate_recordid;   	
   	
    -- KK 07/13/2026 Trim all chapter99 hts numbers in case a space accidentally got inserted
    WITH trimmed_chap99s AS (
      SELECT fed_weekly_estimate_recordid,
        ARRAY(
            SELECT TRIM(hts) FROM unnest(chapter99_hts_numbers) AS hts
        ) AS trimmed_chap99_array
      FROM preftz.fed_weekly_estimate_records
    )
    UPDATE preftz.fed_weekly_estimate_records wer 
    SET chapter99_hts_numbers = tc99.trimmed_chap99_array
    FROM trimmed_chap99s tc99
    WHERE tc99.fed_weekly_estimate_recordid = wer.fed_weekly_estimate_recordid
    ;

    --COMMIT;  
	
  --check for correction records (regular_receipts)	
    UPDATE preftz.fed_weekly_estimate_records fr	
       SET fed_status = 'UPDATE'	
      FROM preftz.weekly_estimate_records r	
     WHERE fr.fed_weekly_estimate_recordid = r.weekly_estimate_recordid	
       AND fr.fed_status IN('NEW','DUPLICATE');	
    GET DIAGNOSTICS v_update_estimate_count = ROW_COUNT;

 	
   -- BEGIN AUDITS   	
    	
    	
IF v_ftz_setting = 'YES' THEN 	
-- invalid part msg -- MH 2/12/2025 	
 	
INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
      SELECT  v_table_name,fs.fed_weekly_estimate_recordid, 'part_number', v_invalid_part_msg, fs.part_number, 	
           fs.part_number 	
       FROM preftz.fed_weekly_estimate_records fs 	
    LEFT JOIN preftz.release_documents rd on fs.release_documentid = rd.release_documentid 	
           LEFT JOIN preftz.parts p 	
                  ON fs.part_number = p.part_number 	
           LEFT JOIN preftz.kit_parts kp 	
                  ON fs.part_number = kp.part_number --NKM 02/12/2024 	
                 AND (kp.removed_date IS NULL OR kp.removed_date > COALESCE(rd.release_date,CURRENT_DATE))  	
     WHERE fs.fed_status IN ('NEW','ERROR','UPDATE') 	
       AND COALESCE(fs.part_number,'') <> '' -- MH 3/20/2025  	
       AND p.part_number IS NULL 	
       AND p.part_number IS NULL AND kp.part_number IS NULL; --NKM 02/12/2024 	
 	
 	
END IF; 	
IF v_ftz_setting = 'NO' THEN -- MH 2/12/2025 	
--bypass duplicates (previously fed)   	
 	
 INSERT INTO preftz.feed_errors     	
   (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)    	
 SELECT v_table_name, fb.fed_weekly_estimate_recordid, 'hts_number', v_duplicate_msg,     	
    fb.hts_number || '/' || fb.country_of_origin ||  '/' ||  fb.manufacturer_id_code   	
    || '/' || array_to_string(ARRAY( SELECT unnest(fb.chapter99_hts_numbers)), ','::text),fb.release_documentid    	
   FROM preftz.fed_weekly_estimate_records fb    	
    INNER JOIN preftz.weekly_estimate_records b    	
    ON fb.hts_number = b.hts_number    	
   AND fb.country_of_origin = b.country_of_origin    	
   AND fb.manufacturer_id_code = b.manufacturer_id_code    	
   AND fb.release_documentid = b.release_documentid   	
   WHERE fb.fed_status <> 'UPDATE' 
   and preftz.array_sort (fb.chapter99_hts_numbers) = preftz.array_sort (b.chapter99_hts_numbers);    	
 	
 INSERT INTO preftz.feed_errors     	
   (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)    	
  SELECT v_table_name,fb.fed_weekly_estimate_recordid, 'hts_number', v_duplicate_msg,     	
    fb.hts_number || '/' || fb.country_of_origin ||  '/' ||  fb.manufacturer_id_code   	
    || '/' || array_to_string(ARRAY( SELECT unnest(fb.chapter99_hts_numbers)), ','::text), fb.release_documentid    	
   FROM preftz.fed_weekly_estimate_records fb    	
    INNER JOIN preftz.archived_estimate_records b    	
 ON fb.hts_number = b.hts_number    	
   AND fb.country_of_origin = b.country_of_origin    	
   AND fb.manufacturer_id_code = b.manufacturer_id_code    	
   AND fb.release_documentid = b.release_documentid   	
    WHERE fb.fed_status <> 'UPDATE'
	and preftz.array_sort (fb.chapter99_hts_numbers) = preftz.array_sort (b.chapter99_hts_numbers);  	
  	
ELSE -- include part number in duplicate logic -- MH 2/12/2025 	
 	
 INSERT INTO preftz.feed_errors     	
   (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)    	
 SELECT v_table_name, fb.fed_weekly_estimate_recordid, 'hts_number', v_duplicate_part_msg,     	
    fb.hts_number || '/' || fb.country_of_origin ||  '/' ||  fb.manufacturer_id_code || '/' || COALESCE(fb.part_number,'')  	
    || '/' || array_to_string(ARRAY( SELECT unnest(fb.chapter99_hts_numbers)), ','::text),fb.release_documentid    	
  FROM preftz.fed_weekly_estimate_records fb    	
    INNER JOIN preftz.weekly_estimate_records b    	
    ON fb.hts_number = b.hts_number    	
   AND fb.country_of_origin = b.country_of_origin    	
   AND fb.manufacturer_id_code = b.manufacturer_id_code   	
   AND fb.part_number = b.part_number 	
   AND fb.release_documentid = b.release_documentid   	
   WHERE fb.fed_status <> 'UPDATE'
   and preftz.array_sort (fb.chapter99_hts_numbers) = preftz.array_sort (b.chapter99_hts_numbers);    	
 	
 INSERT INTO preftz.feed_errors     	
   (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)    	
  SELECT v_table_name,fb.fed_weekly_estimate_recordid, 'hts_number', v_duplicate_part_msg,     	
    fb.hts_number || '/' || fb.country_of_origin ||  '/' ||  fb.manufacturer_id_code || '/' || COALESCE(fb.part_number,'')   	
    || '/' || array_to_string(ARRAY( SELECT unnest(fb.chapter99_hts_numbers)), ','::text), fb.release_documentid    	
    FROM preftz.fed_weekly_estimate_records fb    	
    INNER JOIN preftz.archived_estimate_records b    	
 ON fb.hts_number = b.hts_number    	
   AND fb.country_of_origin = b.country_of_origin    	
   AND fb.manufacturer_id_code = b.manufacturer_id_code   	
   AND fb.part_number = b.part_number 	
   AND fb.release_documentid = b.release_documentid   	
    WHERE fb.fed_status <> 'UPDATE'
	and preftz.array_sort (fb.chapter99_hts_numbers) = preftz.array_sort (b.chapter99_hts_numbers);  	
 	
 	
END IF; 	
    	
UPDATE preftz.fed_weekly_estimate_records fb    	
   SET fed_status = 'DUPLICATE'    	
  FROM preftz.feed_errors fe    	
 WHERE fe.table_name = v_table_name    	
   AND fe.tableid = fb.fed_weekly_estimate_recordid;    	
  	
  	
IF v_ftz_setting = 'NO' THEN -- MH 2/12/2025 	
    --duplicate hts/coo/mid/id (current feed) - keep first only    	
 INSERT INTO preftz.feed_errors     	
   (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)    	
  SELECT  v_table_name, MIN(fb.fed_weekly_estimate_recordid) ,'hts_number',v_duplicate_msg,    	
 fb.hts_number || '/' ||  fb.country_of_origin || '/' || fb.manufacturer_id_code,fb.release_documentid    	
  FROM preftz.fed_weekly_estimate_records fb    	
    WHERE fb.fed_status = 'NEW'    	
  AND fb.hts_number IS NOT NULL     	
  AND fb.country_of_origin IS NOT NULL     	
  AND fb.manufacturer_id_code IS NOT NULL     	
  AND fb.release_documentid IS NOT NULL     	
    GROUP BY fb.hts_number,fb.country_of_origin,fb.manufacturer_id_code,fb.release_documentid    	
    HAVING COUNT(*) > 1;    	
ELSE -- include part number 	
   --duplicate hts/coo/mid/id/part (current feed) - keep first only  -- MH 2/12/2025   	
 INSERT INTO preftz.feed_errors     	
   (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)    	
  SELECT  v_table_name, MIN(fb.fed_weekly_estimate_recordid) ,'hts_number',v_duplicate_part_msg,    	
 fb.hts_number || '/' ||  fb.country_of_origin || '/' || fb.manufacturer_id_code || '/' || fb.part_number, 	
 fb.release_documentid    	
   FROM preftz.fed_weekly_estimate_records fb    	
    WHERE fb.fed_status = 'NEW'    	
  AND fb.hts_number IS NOT NULL     	
  AND fb.country_of_origin IS NOT NULL     	
  AND fb.manufacturer_id_code IS NOT NULL  	
  AND fb.part_number IS NOT NULL  	
  AND fb.release_documentid IS NOT NULL     	
    GROUP BY fb.hts_number,fb.country_of_origin,fb.manufacturer_id_code,fb.release_documentid,fb.part_number    	
    HAVING COUNT(*) > 1;    	
 	
END IF; 	
    	
UPDATE preftz.fed_weekly_estimate_records fb    	
SET fed_status = 'DUPLICATE'    	
FROM preftz.feed_errors fe    	
WHERE fe.table_name = v_table_name    	
AND fb.fed_status = 'NEW'    	
AND fe.tableid = fb.fed_weekly_estimate_recordid;    	
    	
--hts_number -- v_missing_hts_msg    	
    	
INSERT INTO preftz.feed_errors     	
  (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)    	
SELECT v_table_name,fb.fed_weekly_estimate_recordid, 'hts_number', v_missing_hts_msg,     	
fb.hts_number,fb.hts_number    	
  FROM preftz.fed_weekly_estimate_records fb    	
 WHERE fb.fed_status IN('NEW','UPDATE') 	
   AND COALESCE(fb.hts_number,'') = '';    	
    	
--country of origin -- v_missing_coo_msg    	
    	
INSERT INTO preftz.feed_errors     	
  (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)    	
SELECT v_table_name,fb.fed_weekly_estimate_recordid, 'country_of_origin', v_missing_coo_msg,     	
fb.country_of_origin,fb.country_of_origin    	
  FROM preftz.fed_weekly_estimate_records fb    	
 WHERE fb.fed_status IN('NEW','UPDATE')   	
   AND COALESCE(fb.country_of_origin,'') = '';    	
    	
--ftz_line_item_quantity MISSING    	
    	
INSERT INTO preftz.feed_errors     	
  (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)    	
SELECT v_table_name,    	
fb.fed_weekly_estimate_recordid, 'ftz_line_item_quantity', v_missing_qty_msg,     	
fb.ftz_line_item_quantity,fb.ftz_line_item_quantity    	
FROM  preftz.fed_weekly_estimate_records fb    	
WHERE fb.fed_status IN('NEW','UPDATE')     	
AND COALESCE(fb.ftz_line_item_quantity,0) = 0;    	
    	
--ftz_line_item_quantity NEGATIVE     	
    	
INSERT INTO preftz.feed_errors     	
  (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)    	
SELECT v_table_name,    	
fb.fed_weekly_estimate_recordid, 'ftz_line_item_quantity', v_negative_qty_msg,     	
fb.ftz_line_item_quantity,fb.ftz_line_item_quantity    	
FROM  preftz.fed_weekly_estimate_records fb    	
WHERE fb.fed_status  IN ('NEW','UPDATE')     	
AND COALESCE(fb.ftz_line_item_quantity,0) < 0;    	
    	
 -- line_item_value MISSING       	
INSERT INTO preftz.feed_errors     	
(table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)    	
SELECT v_table_name,    	
fb.fed_weekly_estimate_recordid, 'line_item_value', v_missing_value_msg,    	
fb.line_item_value,fb.line_item_value    	
FROM  preftz.fed_weekly_estimate_records fb    	
WHERE fb.fed_status IN('NEW','UPDATE')     	
AND COALESCE(fb.line_item_value,0) = 0;    	
    	
 -- line_item_value NEGATIVE     	
   INSERT INTO preftz.feed_errors     	
  (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)    	
SELECT v_table_name,    	
fb.fed_weekly_estimate_recordid, 'line_item_value', v_negative_value_msg,    	
fb.line_item_value,fb.line_item_value    	
FROM  preftz.fed_weekly_estimate_records fb    	
WHERE fb.fed_status IN ('NEW','UPDATE')      	
AND COALESCE(fb.line_item_value,0) < 0;    	
    	
-- privileged_foreign MISSING    	
INSERT INTO preftz.feed_errors     	
  (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)    	
SELECT  v_table_name,    	
fb.fed_weekly_estimate_recordid, 'line_item_value', v_missing_priv_for_msg,    	
fb.privileged_foreign,fb.privileged_foreign    	
FROM preftz.fed_weekly_estimate_records fb    	
WHERE fb.fed_status IN('NEW','UPDATE')   	
AND fb.privileged_foreign IS NOT TRUE  AND fb.privileged_foreign IS NOT FALSE;    	
    	
-- privileged_date MISSING     	
--INSERT INTO preftz.feed_errors     	
--  (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)    	
--SELECT v_table_name,    	
--fb.fed_weekly_estimate_recordid, 'privileged_date', v_missing_priv_date_msg,    	
--fb.privileged_date,fb.privileged_date    	
--FROM   preftz.fed_weekly_estimate_records fb    	
--WHERE fb.fed_status = 'NEW'    	
--AND fb.privileged_foreign = true    	
--AND fb.privileged_date IS NULL;    	

-- NO 01/14/2026 ADD AUDIT FOR RELEASE DOCUMENT STATUS, CANNOT BE FILED, SHOULD BE CREATED (estimate_status)
    	
-- manufacturer_id_code MISSING    	
INSERT INTO preftz.feed_errors     	
  (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)    	
SELECT v_table_name,    	
fb.fed_weekly_estimate_recordid, 'line_item_value', v_missing_mid_msg,    	
fb.manufacturer_id_code,fb.manufacturer_id_code
FROM  preftz.fed_weekly_estimate_records fb
WHERE fb.fed_status IN('NEW','UPDATE')
AND COALESCE(fb.manufacturer_id_code,'') = '';

-- release_documentid MISSING -- NO 01/13/2026 updated to check both id and number
INSERT INTO preftz.feed_errors
(table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)
SELECT v_table_name,
fb.fed_weekly_estimate_recordid, 'release_documentid', v_missing_doc_msg,
COALESCE(fb.release_documentid::text, fb.release_document_number, 'NULL'),
COALESCE(fb.release_documentid::text, fb.release_document_number, 'NULL')
FROM  preftz.fed_weekly_estimate_records fb
WHERE fb.fed_status IN ('NEW','UPDATE')	
AND COALESCE(fb.release_documentid,0) = 0
AND COALESCE(fb.release_document_number,'') = '';

-- release_document not found -- NO 01/14/2026 catch when document number or id provided but doesn't exist
INSERT INTO preftz.feed_errors
(table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)
SELECT v_table_name,
fb.fed_weekly_estimate_recordid, 'release_documentid', 'Release Document not found with specified ID or document number',
COALESCE(fb.release_documentid::text, fb.release_document_number, 'NULL'),
COALESCE(fb.release_documentid::text, fb.release_document_number, 'NULL')
FROM  preftz.fed_weekly_estimate_records fb
LEFT JOIN preftz.release_documents rd ON fb.release_documentid = rd.release_documentid
WHERE fb.fed_status IN ('NEW','UPDATE')
AND (fb.release_documentid IS NOT NULL OR COALESCE(fb.release_document_number,'') <> '')
AND rd.release_documentid IS NULL;

-- release_documentid invalid
INSERT INTO preftz.feed_errors
(table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)
SELECT v_table_name,
fb.fed_weekly_estimate_recordid, 'release_documentid', v_invalid_doc_msg,    	
fb.release_documentid,fb.release_documentid    	
FROM  preftz.fed_weekly_estimate_records fb    	
JOIN preftz.release_documents  rd on fb.release_documentid = rd.release_documentid    	
WHERE fb.fed_status  IN ('NEW','UPDATE')     	
AND (rd.entry_type_code <> '06' OR rd.estimate_status <> 'CREATED');    	
    	

-- add mid codes if not present    	
INSERT INTO preftz.fed_vendors(vendor_code,manufacturer_id_code)    	
SELECT fb.manufacturer_id_code,fb.manufacturer_id_code    	
from preftz.fed_weekly_estimate_records fb    	
LEFT JOIN preftz.manufacturer_identification_codes mid ON fb.manufacturer_id_code = mid.manufacturer_id_code    	
where mid.manufacturer_id_code is null;    	
GET DIAGNOSTICS v_update_count = ROW_COUNT;    	
    	
If v_update_count > 0 THEN    	
CALL preftz.audit_fed_vendors();    	
END If;    	
    	
 --- v_duplicate_add_hts_msg  hts is present in additional hts numbers  	
INSERT INTO preftz.feed_errors     	
(table_name, tableid, field_name,error_type,      	
 error_key_value, fed_record_identifier)  	
   	
select  v_table_name, wer.fed_weekly_estimate_recordid, 'chapter99_hts_numbers', v_duplicate_add_hts_msg,  	
wer.chapter99_hts_numbers, wer.hts_number  	
from preftz.fed_weekly_estimate_records wer  	
where hts_number = ANY(wer.chapter99_hts_numbers);  	
  	
    	
-- classify hts numbers    	
INSERT INTO preftz.feed_errors     	
(table_name, tableid, field_name,error_type,      	
 error_key_value, fed_record_identifier)    	
SElect v_table_name, fb.fed_weekly_estimate_recordid ,'hts_number',v_invalid_hts_msg,    	
  fb.hts_number || '/' ||  fb.country_of_origin, hts.tariff_number    	
from preftz.fed_weekly_estimate_records fb    	
LEFT JOIN preftz.harmonized_tariff_schedule_reference hts ON fb.hts_number = hts.tariff_number    	
where hts.tariff_number is null and COALESCE(fb.hts_number,'') <> ''    	
AND preftz.validate_classification(fb.hts_number,'',fb.country_of_origin, CURRENT_DATE) = 'FAIL';    	
    	
    	
    	
-- validate other hts numbers
-- KK 03/03/2026 Remove validate_classification from chapter99 tariffs.
INSERT INTO preftz.feed_errors
    (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier)
SELECT v_table_name,hts.fed_weekly_estimate_recordid ,'chapter99_hts_numbers',v_invalid_adhts_msg,
    hts.hts_number || '/' ||  hts.country_of_origin, hts.hts_number
FROM (
    select DISTINCT unnest(fb.chapter99_hts_numbers) as hts_number, fb.country_of_origin, fb.fed_weekly_estimate_recordid
    from preftz.fed_weekly_estimate_records fb
    WHERE fb.fed_status in('NEW','UPDATE')
) hts
WHERE NOT hts.hts_number ~ '^([0-9]{8}|[0-9]{10})$';
-- END AUDITS
       	
    --Update status to ERROR    	
    UPDATE preftz.fed_weekly_estimate_records fb    	
       SET fed_status = 'ERROR'    	
      FROM preftz.feed_errors fe    	
     WHERE fe.table_name = v_table_name    	
       AND fe.tableid = fb.fed_weekly_estimate_recordid    	
       AND fb.fed_status <> 'DUPLICATE';    	
    	
    --COMMIT;  
	
	IF EXISTS(select 'x' from preftz.fed_weekly_estimate_records where fed_status = 'UPDATE') THEN
		CALL preftz.process_estimate_updates();
	END IF;
        	
    --Insert all non-error records to production tables    	
    INSERT INTO preftz.weekly_estimate_records    	
          (weekly_estimate_recordid,release_documentid, hts_number, chapter99_hts_numbers, country_of_origin,     	
   ftz_line_item_quantity, line_item_value, privileged_foreign, privileged_date, current_hts_number, manufacturer_id_code,part_number)    	
    	
    SELECT fb.fed_weekly_estimate_recordid, fb.release_documentid, fb.hts_number, fb.chapter99_hts_numbers, fb.country_of_origin, fb.ftz_line_item_quantity,     	
fb.line_item_value, fb.privileged_foreign, fb.privileged_date, fb.current_hts_number, fb.manufacturer_id_code  ,fb.part_number  	
     FROM preftz.fed_weekly_estimate_records fb    	
     WHERE fb.fed_status = 'NEW';    	
        	
    --record statistics    	
    INSERT INTO preftz.system_log (procedure_name, log_message)     	
    SELECT 'audit_fed_weekly_estimate_records',     	
           (CASE fed_status     	
                 WHEN 'NEW' THEN 'IMPORTED'    	
                 ELSE fed_status    	
                 END) || TO_CHAR(COUNT(*),'999999')     	
      FROM preftz.fed_weekly_estimate_records    	
     GROUP BY fed_status;    	
        	
    --Delete finished records from prod table    	
    DELETE FROM preftz.fed_weekly_estimate_records WHERE fed_status in('NEW','UPDATE');    	
        	
    --log procedure finish    	
    INSERT INTO preftz.system_log (procedure_name, log_message)     	
    VALUES ('audit_fed_weekly_estimate_records', 'finished');    	
        	
END;    	
$BODY$;




