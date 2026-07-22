--fed_weekly_estimate_records

cd C:\Users\gorbu\AppData\Roaming\DBeaverData\drivers\clients\postgresql\win\17

psql "postgresql://postgres:2436@localhost:5432/postgres" -c "\COPY preftz.raw_fed_weekly_estimate_records(raw_file_text) FROM 'c:\ftz\weekly_test.csv';"


select
sl.procedure_name 
,sl.log_message 
,sl.details 
,log_date
,(log_date AT TIME ZONE 'UTC') AT TIME ZONE 'America/New_York'
--delete 
from preftz.system_log sl 
--where sl.procedure_name like '%event%'
--where sl.procedure_name like '%receipts%'
--where sl.procedure_name like '%create_e214%'
--where sl.procedure_name like '%link_receipts_to_conveyances_by_inbond%'
order by sl.logid desc;


-- @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


select * 
--delete 
from preftz.raw_fed_weekly_estimate_records rfr ;

-------
CALL preftz.parse_raw_feed($$fed_weekly_estimate_records$$);

CALL preftz.audit_raw_feed($$fed_weekly_estimate_records$$);

call audit_fed_weekly_estimate_records();
-------

SELECT token.column_name
      FROM information_schema.columns token
      JOIN information_schema.columns raw_token
        ON raw_token.column_name = token.column_name
     WHERE token.table_schema='preftz'
       AND raw_token.table_schema='preftz'
       AND token.table_name=$$fed_weekly_estimate_records$$
       AND raw_token.table_name=$$raw_fed_weekly_estimate_records$$--'raw_' || p_fed_token;


SELECT regexp_split_to_table 
(
'hts_number|chapter99_hts_numbers,country_of_origin,ftz_line_item_quantity,line_item_value,privileged_foreign,privileged_date,manufacturer_id_code,current_hts_number'
,'\|');

hts_number,chapter99_hts_numbers,country_of_origin,ftz_line_item_quantity,line_item_value,privileged_foreign,privileged_date,manufacturer_id_code,current_hts_number


select * 
--delete 
from preftz.feed_errors 
where table_name like $$%weekly_estimate_records%$$ 
order by tableid ;


select * from preftz.data_audit_messages

delete from preftz.raw_fed_weekly_estimate_records rfr ;
delete from preftz.fed_weekly_estimate_records;

select * from preftz.fed_weekly_estimate_records
--where release_documentid  = 1

CALL preftz.batch_process_delete_records('fed_weekly_estimate_records','{338}','0');

SELECT ARRAY(
select fed_weekly_estimate_recordid from preftz.fed_weekly_estimate_records where fed_status = 'DUPLICATE'
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
)   	


select fed_weekly_estimate_recordid from
(
select
fed_weekly_estimate_recordid
,unnest(chapter99_hts_numbers)chapter99_hts_numbers  
from preftz.fed_weekly_estimate_records
) t1
where length(chapter99_hts_numbers)  > 10


select * from preftz.fed_weekly_estimate_records
where fed_status = 'NEW'

select * from preftz.fed_weekly_estimate_records
where fed_status = 'ERROR'

select *
--delete 
from preftz.fed_weekly_estimate_records
where fed_status = 'DUPLICATE'


select * from preftz.fed_weekly_estimate_records 


call audit_fed_weekly_estimate_records();


SQL Error [22001]: ERROR: value too long for type character varying(10)
  Where: SQL statement "UPDATE preftz.deleted_weekly_estimate_records SET chapter99_hts_numbers ='{99030306 99038191 99038801}' WHERE id  = 21;"
PL/pgSQL function add_deleted_record(character varying,integer,integer) line 602 at EXECUTE
SQL statement "select add_deleted_record from preftz.add_deleted_record(p_table_name,v_recordid, p_userid)"
PL/pgSQL function batch_process_delete_records(character varying,integer[],integer) line 28 at SQL statement
SQL statement "CALL preftz.batch_process_delete_records('fed_weekly_estimate_records',v_duplicate_ids,'0')"
PL/pgSQL function audit_fed_weekly_estimate_records() line 82 at call
