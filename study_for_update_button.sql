
select * into  preftz.fed_receipts_copy
from preftz.fed_receipts fr

select * from preftz.fed_receipts fr
where receiptid = 12134

select fr.conveyanceid ,* from preftz.receipts fr
where receiptid = 12134

select preftz.compare_fed_receipt(12134);


select * from preftz.receipt_cast_and_smelt; 
select * from preftz.receipt_melt_and_pour; 
select * from preftz.receipt_derivative_content;
select * from preftz.receipt_case_numbers;
select * from preftz.import_licenses;
select * from preftz.receipt_percentage_value;
select * from preftz.user_references where table_name = 'receipts'
and tableid  = 12134;
select * from preftz.conveyances;


            SELECT * --count(*)
            FROM preftz.fed_receipts fr
            JOIN preftz.receipts r
              ON r.receiptid = fr.receiptid

--exeptions in receipts             
    export_date date,
    gross_weight double precision,
    charges double precision,
    cloned_from_receiptid integer,
    kit_receiptid integer,               --receiptid kit part found in kit_receipts
              
    
--make sure your query from fed_receipts filters on fed_status = 'UPDATE' and temporary_deposit <> true (or Y?) and we can filter out zone-to-zone too

select * from preftz.fed_receipts fr
where preftz.compare_fed_receipt(fr.receiptid) = 'PASS'


call preftz.audit_fed_receipts();

select
sl.procedure_name 
,sl.log_message 
--,sl.details 
,log_date
,(log_date AT TIME ZONE 'UTC') AT TIME ZONE 'America/New_York'
--delete 
from preftz.system_log sl 
where sl.procedure_name like '%audit_fed_receipts%'
--where sl.procedure_name like '%receipts%'
--where sl.procedure_name like '%create_e214%'
--where sl.procedure_name like '%link_receipts_to_conveyances_by_inbond%'
and sl.log_message like 'MARKED AS DUPLICATE%'
order by sl.logid desc;

select fr.conveyanceid ,* 
from preftz.receipts fr
where receiptid = 217195

select fr.conveyanceid ,* 
from preftz.fed_receipts fr
where receiptid = 221597

select c.inbond_number, c.zone_admission_no , *  
FROM preftz.conveyances c
where c.inbond_number = '710456586'
order by c.inbond_number,c.zone_admission_no  ;

select fr.conveyanceid ,* 
from preftz.receipts fr
where fr.conveyanceid = 348


710456586



SELECT string_agg(
           fr.receiptid::text,
           ',' ORDER BY fr.receiptid
       ) AS receiptids
FROM preftz.fed_receipts fr
where preftz.compare_fed_receipt(fr.receiptid) = 'PASS'


SELECT
    'audit_fed_receipts',
    'PASS RECEIPT IDS: ' ||
    COALESCE(
        string_agg(
            fr.receiptid::text,
            ',' ORDER BY fr.receiptid
        ),
        'NONE'
    )
FROM preftz.fed_receipts fr
WHERE preftz.compare_fed_receipt(fr.receiptid) = 'PASS'
AND fr.fed_status = 'UPDATE'
AND COALESCE(fr.temporary_deposit,'N') = 'N'
AND COALESCE(fr.zone_to_zone_transfer,'N') = 'N'

select preftz.compare_fed_receipt(12134);

