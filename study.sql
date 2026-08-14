/*
Thoughts for Refactoring classify_receipts

--classify_receipts

drops / creates temp table with ALL data necessary for classifying 
a receipt (receipt_classification_data ??)

drops / creates temp table #2 similar to receipt_classifications (receipt_classification_work ??)

calls calculate_receipt_classifications

if success; inserts rows from receipt_classification_work to receipt_classifications
---------------

--calculate_receipt_classifications (new function)

does same work that classify_receipts does today, 
except uses temp table receipt_classification_data for all data, 
and only inserts to receipt_classification_work

need to go through every function and proc to replace any Selects/Updates/Inserts 
to any tables other than the two temp tables above.

-- preftz.additional_tariffs -> additional tariffs original
-- preftz.additional_tariff_derivatives -> derivative tariffs, those that require content percentage (steel, alum, copper, wood)
-- preftz.additional_tariff_variable_rates -> variable rates; apply tariff based on combined ad_valorem rate
-- preftz.additional_tariff_priority -> stacking / tariff priority; removes tariffs of lower priority
-- preftz.additional_tariff_tags -> use this to group chapter99 - specifically to ID reciprocal tariffs
-- preftz.additional_tariff_exclusions -> use this to add an exclusion tariff based on the other tariffs that have been applied
-- preftz.additional_tariff_replacements -> use this to replace one or more tariffs with another based on parts.section_232_exclusion_number
-- preftz.annex_iv_section232_metals -> used to determine which type metal is flagged by hts prefix

select * FROM preftz.additional_cast_and_smelt_tariffs acst

-- call preftz.update_additional_tariffs_data();
-- call preftz.update_additional_tariff_replacements_data();
-- call preftz.update_additional_tariff_derivatives_data();
-- call preftz.update_additional_tariff_tags_data();
-- call preftz.update_additional_tariff_variable_rates_data();
-- call preftz.update_additional_tariff_exclusions_data();
-- call preftz.update_additional_tariff_replacements_data();
-- call preftz.update_additional_tariff_priority_data();
-- call preftz.update_annex_iv_section232_metals_data();


 */

select * from v2_classify_receipts

select * 
from preftz.receipt_classifications 
where receiptid in (10035);


select * 
from preftz.receipts 
where receiptid in (10035);

select distinct zone_admission_no   
from preftz.receipts 
where receiptid in (
select distinct t1.receiptid  
from preftz.receipt_classifications_v2 t1)
order by zone_admission_no




select * from preftz.e214_filing_statuses efs
order by efs.zone_admission_no desc;


select * from preftz.e214_filing_statuses efs
where efs.e214_status is not null
order by efs.zone_admission_no desc
;

--select preftz.classify_receipts('26ANT01300');
--perform  preftz.classify_receipts_v2(p_admission_number,null,null,true);

select preftz.classify_receipts_v2('2600000051',null,null,true);


with r as  
(select receiptid from preftz.receipts
where zone_admission_no = '26ANT00225')
, c as 
(
select count(*) rc 
from preftz.receipt_classifications
where receiptid in (select * from r)
)
, c2 as 
(
select count(*) rc2
from preftz.receipt_classifications_v2
where receiptid in (select * from r)
)
select * from c,c2
;


--@@@
--this one will compare results
select 
t2.* 
from preftz.receipt_classifications_v2 t1
join preftz.compare_receipt_classifications_to_v2(t1.receiptid) t2
on t1.receiptid = t2.receiptid
--where field_name not like '%unit_duty_liability%'
--where t1.created_date > '2026-07-22'
--where t1.created_date > '2026-07-30'
--where t1.receiptid =227984
order by t2.receiptid,t2.harmonized_tariff_schedule_number, t2.field_name


select 
field_name
,count(*)
from preftz.receipt_classifications_v2 t1
join preftz.compare_receipt_classifications_to_v2(t1.receiptid) t2
on t1.receiptid = t2.receiptid
group by field_name



select r.privileged_date,r.receipt_date ,* 
from preftz.receipts r
where privileged_date is null
and r.zone_status <> 'D';



select 
t2.receiptid ,t3.receiptid 
from preftz.receipt_classifications_v2 t1
join preftz.compare_receipt_classifications_to_v2(t1.receiptid) t2
on t1.receiptid = t2.receiptid
left join preftz.receipt_classifications t3
on t1.receiptid = t3.receiptid
group by t2.receiptid,t3.receiptid
order by t3.receiptid desc
--114

SELECT r.receipt_date ,r.privileged_date ,r.pre_receipt ,r.zone_admission_no ,*
FROM preftz.receipts r 
where r.receiptid in 
(
select 
t2.receiptid 
from preftz.receipt_classifications_v2 t1
join preftz.compare_receipt_classifications_to_v2(t1.receiptid) t2
on t1.receiptid = t2.receiptid
left join preftz.receipt_classifications t3
on t1.receiptid = t3.receiptid
group by t2.receiptid
)
order by r.zone_admission_no

select * 
into preftz.receipt_classifications_20260731
from preftz.receipt_classifications rc;
--3255






SELECT r.receipt_date ,r.privileged_date ,r.pre_receipt ,r.zone_admission_no ,*
--select count(*)
FROM preftz.receipts r 
JOIN preftz.receipt_classifications rc ON rc.receiptid = r.receiptid
WHERE r.privileged_date < '2026-07-24'
    AND rc.harmonized_tariff_schedule_number like '990305%'
--order by r.zone_admission_no    
;

select * from preftz.e214_filing_statuses efs
where efs.zone_admission_no in   
(SELECT r.zone_admission_no 
FROM preftz.receipts r 
JOIN preftz.receipt_classifications rc ON rc.receiptid = r.receiptid
WHERE r.privileged_date < '2026-07-24'
    AND rc.harmonized_tariff_schedule_number like '990305%')




------ berrang
[(51,)]
------ better_brakes
[(121,)]
------ enerco
[(18,)]
------ horizon_hobby
[(36,)]
------ rak
[(488,)]
------ ryder_nobull_new
[(732,)]
------ sharp
[(1,)]


update preftz.receipts
set privileged_date = '2026-07-30'
where zone_admission_no in  ('2600000081','2600000082','2600000090','2600000111')

update preftz.receipts
set privileged_date = '2026-07-29'
where zone_admission_no in  ('2600000086','2600000108','2600000099','2600000097','2600000094','2600000087')

update preftz.receipts
set privileged_date = '2026-07-28'
where zone_admission_no in  ('2600000107')

--these are different
--select preftz.classify_receipts('2600000081');
--select preftz.classify_receipts('2600000082');
--select preftz.classify_receipts('2600000087');
--select preftz.classify_receipts('2600000107');
--select preftz.classify_receipts('2600000108');
--select preftz.classify_receipts('2600000111');


select preftz.classify_receipts('2600000090');
select preftz.classify_receipts('2600000111');
select preftz.classify_receipts('2600000086');
select preftz.classify_receipts('2600000108');
select preftz.classify_receipts('2600000099');
select preftz.classify_receipts('2600000097');
select preftz.classify_receipts('2600000094');


select
t1.harmonized_tariff_schedule_number 
,t2.harmonized_tariff_schedule_number
,t1.unit_value IS NOT DISTINCT FROM t2.unit_value 
,t1.quantity1_rate IS NOT DISTINCT FROM t2.quantity1_rate
,t1.quantity2_rate IS NOT DISTINCT FROM t2.quantity2_rate
,t1.unit_duty_liability  ,t2.unit_duty_liability
--,* 
from 
(
select * from receipt_classifications 
where receiptid in
(select receiptid from preftz.receipts 
where zone_admission_no = '2600000082')
) t1
full join
(
select * from receipt_classifications_20260731 rc  
where receiptid in
(select receiptid from preftz.receipts 
where zone_admission_no = '2600000082')
)t2
on t1.receiptid = t2.receiptid
and t1.harmonized_tariff_schedule_number = t2.harmonized_tariff_schedule_number 




--this one will compare results
select 
t2.* 
from preftz.receipt_classifications_v2 t1
join preftz.compare_receipt_classifications_to_v2(t1.receiptid) t2
on t1.receiptid = t2.receiptid
--where field_name not like '%unit_duty_liability%'
--where t1.created_date > '2026-07-22'
--where t1.receiptid =252592
order by t2.receiptid,t2.harmonized_tariff_schedule_number, t2.field_name

--perform  preftz.classify_receipts_v2(p_admission_number,null,null,true);

select preftz.classify_receipts_v2('2600000133',null,null,true);

--select preftz.classify_receipts('2600000133');

select
receiptid 
,privileged_date , receipt_date
,pre_receipt
,part_number 
from preftz.receipts 
where zone_admission_no like '2600000171%'
--and receiptid in (252574,252575,252584,252592,252597,252598,252599)


select * from preftz.derivative_parts_content;

select * from preftz.part_classifications pc
where pc.part_number = '7899863'


select * from preftz.additional_tariff_derivatives
where 
;


select * from preftz.e214_filing_status_changes efsc 
where efsc.zone_admission_no like '26LZBD0079%'
order by zone_admission_no,change_id ;

select * from preftz.e214_filing_statuses efs  
where zone_admission_no like '26LZBD0079%'
order by zone_admission_no;


select privileged_date,* from tmp_receipt_classification_data;
select * from tmp_receipt_classification_work;

select
zone_admission_no
,count(*)
from preftz.receipts
where receiptid  in 
(select receiptid from preftz.receipt_classifications_v2)
group by zone_admission_no
order by zone_admission_no desc

--this one will compare results
select 
t2.* 
from preftz.receipt_classifications_v2 t1
join preftz.compare_receipt_classifications_to_v2(t1.receiptid) t2
on t1.receiptid = t2.receiptid
where t1.created_date > '2026-08-14'
order by t2.receiptid,t2.harmonized_tariff_schedule_number, t2.field_name

select count(*),now() from preftz.receipt_classifications_v2 t1;

--trf 
/*
--trf 
4707	2026-08-14 15:18:48.940 -0400

--chest
5889	2026-08-14 09:06:37.125 -0400

--georgia
1334	2026-08-14 09:08:10.599 -0400

--neosho
489	2026-08-13 09:28:35.806 -0400


--dayton
1471	2026-08-12 12:09:28.350 -0400
 
*/

delete from preftz.receipt_classifications_v2 
where receiptid in 
(select t1.receiptid  
from preftz.receipt_classifications_v2 t1
left join preftz.receipt_classifications t2
on t1.receiptid = t2.receiptid
where t2.receiptid is null);  


select * 
--delete 
from preftz.receipt_classifications_v2 t1
order by created_date desc;

select preftz.classify_receipts_v2(null,null,289670,true);
select preftz.classify_receipts_v2('26LZBD0079',null,null,true);

select count(*),now() from preftz.receipt_classifications_v2 t1;

select preftz.classify_receipts('2600000188');


select * 
--delete 
from preftz.receipt_classifications_v2 t1
where t1.receiptid  = 371832
order by harmonized_tariff_schedule_number;
--order by created_date desc;


select * 
from preftz.receipt_classifications t1
where t1.receiptid  = 371832
order by harmonized_tariff_schedule_number;

SELECT * FROM preftz.compare_receipt_tariffs(252592);


select r.privileged_date,r.receipt_date,r.zone_admission_no  
,* 
from preftz.receipts r
where r.receiptid in (371832)
--where r.zone_admission_no > '' and r.privileged_date is null
--where r.zone_admission_no = '2600000188'


26LZBD0079

select 
efs.has_pre_receipts
,efs.data_updated_after_create 
,* 
from preftz.e214_filing_statuses efs
--where efs.concur_status is null 
order by efs.zone_admission_no desc;



select r.privileged_date,r.receipt_date ,* 
FROM preftz.archived_updated_receipts r 
where r.receiptid in (371832)

select r.privileged_date,r.receipt_date ,* 
FROM preftz.deleted_pre_receipts r 
where r.receiptid in (371832)


select * 
--delete 
from preftz.receipt_classifications t1
where t1.receiptid in 
(select  receiptid
FROM preftz.deleted_pre_receipts r) 

select *
--delete
from preftz.receipt_classifications_v2 t1
where t1.receiptid in 
(select  receiptid
FROM preftz.deleted_pre_receipts r) 



select preftz.get_transfer_itemid_from_ztz_receiptid(281348);
select * from preftz.transfer_ztz_archive t  WHERE 
transfer_itemid = (select preftz.get_transfer_itemid_from_ztz_receiptid(281348));

select * from 
preftz.derivative_parts_content dpc 
where dpc.part_number = '15MIS_C-DCR-0026'


select count(*)
from preftz.e214_filing_statuses efs
where efs.e214_date::text like '2026-07%'


--$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

receiptid|harmonized_tariff_schedule_number|special_programs_indicator|unit_value|tariff_type|distinct_tariff_line_indicator|primary_tariff|quantity1_rate|quantity2_rate|unit_duty_liability|
---------+---------------------------------+--------------------------+----------+-----------+------------------------------+--------------+--------------+--------------+-------------------+
   284598|99038803                         |                          |       0.0|SECTION301 |                              |              |              |              |               1.61|
   284598|99038190                         |                          |     2.576|SECTION232 |                              |              |     0.4953312|              |              1.288|
   284598|7315110005                       |                          |     3.864|BASE       |                              |              |     0.7429968|              |                0.0|

--select * from preftz.classify_receipts_v2('26BERR0020',null,10035);
--select * from preftz.classify_receipts_v2('26BERR0020','2025-03-03');

select * from preftz.classify_receipts_v2(null,null,281351,true);

select preftz.classify_receipts_v2('26ANT00864',null,null,false);

select preftz.classify_receipts_v2('26ANT01128',null,null,true);


--chest 281312
--georg 59022 local 46865
select preftz.generate_tmp_receipt_classification_data(null,null,281348);


select preftz.generate_tmp_receipt_classification_data(null,null,281312);

select preftz.generate_tmp_receipt_classification_data(null,null,46865);--g

select preftz.generate_tmp_receipt_classification_data(null,null,284598); --c


SELECT preftz.validate_classification ('8413919099', null, 'CN', '2025-07-28');
SELECT preftz.validate_classification ('8413919010', null, 'CN', '2025-07-28');


SELECT * FROM preftz.part_classifications o	
where part_number = '15MIS_C-WPI-0001'	



select preftz.generate_tmp_receipt_classification_work();

select privileged_date,* from tmp_receipt_classification_data;
--31
select * from tmp_receipt_classification_work;

select preftz.create_receipt_classifications('23BWGA0101');
select preftz.calculate_receipt_classifications();     


select preftz.create_receipt_classifications('26NB000266');
select preftz.classify_receipts_v2('26NB000266',null,null,true);

select preftz.create_receipt_classifications('26NB000136');
select preftz.calculate_receipt_classifications();     

select preftz.classify_receipts_v2('26NB000136',null,null,true);



select preftz.classify_receipts_v2(null,'2025-06-30',284598,true);

select preftz.classify_receipts_v2(null,null,284598,true);

select preftz.classify_receipts_v2(null,null,284652,true);

select preftz.classify_receipts_v2('26BWMI0069',null,null,true);

select preftz.generate_tmp_receipt_classification_data(null,null,284652); --c
--temp tables

select
zone_status
,new_zone_status
,privileged_date
,classification_date
,* 
from tmp_receipt_classification_data

select * from tmp_receipt_classification_work
--where receiptid = 210455;



--15MIS_C-SMO-0119        

select preftz.classify_receipts('26BWMI0069');

select preftz.classify_receipts_v3('26BWMI0069');
--26BWMI0069
558	     15MIS_C-DCH-0297	0.995	0.0	1900-01-01 00:00:01.000	2025-06-29 23:59:59.000	0.0
13934	15MIS_C-DCH-0297	0.4	    0.0	2025-06-30 00:00:00.000	9999-12-31 23:59:59.000	0.0

select * 
--delete
from preftz.receipt_classifications 
where receiptid in (284598)
order by harmonized_tariff_schedule_number ;

284598	2026-07-22 10:40:46.123	99038803		0.0	SECTION301
284598	2026-07-22 10:40:46.123	99038190		2.576	SECTION232
284598	2026-07-22 10:40:46.123	7315110005		3.864	BASE




select 
* 
from tmp_receipt_classification_work
where receiptid in (284652)--(284598)
order by harmonized_tariff_schedule_number ;


select * 
from preftz.receipt_classifications_v2 t1
where receiptid in (284652)--(284598)
order by created_date desc;

select * 
             FROM preftz.transfer_ztz_archive t 
             WHERE transfer_itemid =
               (SELECT get_transfer_itemid_from_ztz_receiptid as transfer_itemid 
               FROM preftz.get_transfer_itemid_from_ztz_receiptid(284652))
             AND t.privileged_date IS NOT NULL;



--temp tables
select * from tmp_receipt_classification_data
--where receiptid = 210455;
--31

select * from tmp_receipt_classification_work
where receiptid = 503258;
--77



select * 
--delete 
from preftz.data_audit_messages   
order by messageid desc



select 
* 
--delete 
from preftz.receipt_classifications_v2 t1
order by created_date desc;

select 
t2.* 
from preftz.receipt_classifications_v2 t1
join preftz.compare_receipt_classifications_to_v2(t1.receiptid) t2
on t1.receiptid = t2.receiptid
--where t1.receiptid  >= 342902 and t1.receiptid  <= 342999

--temp tables
select * from tmp_receipt_classification_data
--where receiptid = 210455;
--31

select * from tmp_receipt_classification_work
where receiptid = 210455;
--77


select count(*) from preftz.part_bounds

select * from preftz.part_bounds

select * FROM preftz.derivative_parts_content
where part_number  = '15MIS_C-DCH-0297';
select * FROM preftz.receipt_derivative_content rdc;
select * from preftz.parts_extension; 
select * FROM preftz.receipt_percentage_value ;

select * FROM preftz.additional_cast_and_smelt_tariffs acst
where acst.additional_tariff_number  = '99038869';

select * FROM preftz.tariff_reclassifications_for_entry
where from_tariff_number  in 
('99030124','99030132','','99030133','99030125')
;

select * FROM preftz.harmonized_tariff_schedule_reference htsr
where tariff_number  = '99038869'--'99037901'

select * FROM preftz.tariff_reclassifications_for_entry
where from_tariff_number  in 
('99038869','99030132','','99030133','99030125','99030163','99030269','99030120')
;

284170
284171

select * from preftz.additional_tariffs t
where t.additional_tariff_number  = '99038869'--'99037901'

select * from preftz.additional_tariffs t
where t.tariff_prefix  like '9903%'--'99037901'


select * from preftz.additional_tariff_derivatives  t
where t.additional_tariff_number  = '99038869'--'99037901'

select * from preftz.additional_tariff_exclusions
where tariff_number  = '99038869'--'99037901'

select * from preftz.additional_tariff_tags t 
where t.additional_tariff_number  = '99038869'--'99037901'


select * FROM preftz.annex_iv_section232_metals; --?

select * FROM preftz.derivative_parts_content
order by part_number  


select count(*) FROM preftz.receipt_derivative_content rdc;
select * FROM preftz.annex_iv_section232_metals; --?
select count(*) from preftz.parts_extension; 
select count(*) FROM preftz.receipt_percentage_value ; --? no to ALL clients


select * 
from preftz.receipt_classifications_v2
where receiptid in (59022)
order by harmonized_tariff_schedule_number ;


select * from preftz.calculate_receipt_classifications();


select 
*
--delete 
from preftz.data_audit_messages;

select 
* 
from tmp_receipt_classification_work
where receiptid in (204373)
order by harmonized_tariff_schedule_number ;

select * 
from preftz.receipt_classifications 
where receiptid in (59022)
order by harmonized_tariff_schedule_number ;

8708401110
99030301
99037411
99038803
99039406

select * 
from preftz.receipt_classifications_v2
where receiptid in (209200)
order by harmonized_tariff_schedule_number ;

SELECT * FROM preftz.compare_receipt_classifications_to_v2(210454);

select 
t2.* 
from preftz.receipt_classifications_v2 t1
join preftz.compare_receipt_classifications_to_v2(t1.receiptid) t2
on t1.receiptid = t2.receiptid



 with target_receipts as (
    -- change this CTE to return the sub-set of receipts you want to compare
    select receiptid from preftz.receipts 
    where receiptid in (197805)
    --where receiptid in(   select receiptid from t1   )
)
, current_tariffs as (
    select rc.receiptid, array_agg(rc.harmonized_tariff_schedule_number order by harmonized_tariff_schedule_number) as current_tariffs
    from preftz.receipt_classifications rc
    join target_receipts rr on rr.receiptid = rc.receiptid
    --where rc.tariff_type NOT IN('BASE')
    group by rc.receiptid
)
, calculated_tariffs as (
    select rc.receiptid, array_agg(rc.harmonized_tariff_schedule_number order by harmonized_tariff_schedule_number) as calculated_tariffs
    from tmp_receipt_classification_work rc
    join target_receipts rr on rr.receiptid = rc.receiptid
    --where rc.tariff_type NOT IN('BASE')
    group by rc.receiptid
)
, added_tariff_compare as (
    select rc.receiptid, efs.e214_date, r.privileged_date, r.receipt_date::date, rc.harmonized_tariff_schedule_number
        , ct.current_tariffs
        , calt.calculated_tariffs 
    from preftz.receipt_classifications rc
    join current_tariffs ct on ct.receiptid = rc.receiptid
    join calculated_tariffs calt on calt.receiptid = rc.receiptid
    join preftz.receipts r on r.receiptid = rc.receiptid
    left join preftz.e214_filing_statuses efs on efs.zone_admission_no = r.zone_admission_no
    where rc.tariff_type = 'BASE'
    )
    , compare_with_diff as (
    SELECT atc.*, array(SELECT unnest(atc.calculated_tariffs) EXCEPT SELECT unnest(atc.current_tariffs)) as added_tariffs,
        array(SELECT unnest(atc.current_tariffs) EXCEPT SELECT unnest(atc.calculated_tariffs)) as removed_tariffs
    from added_tariff_compare atc
)
select d.*
from compare_with_diff d;

--$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

select * from preftz.check_current_calculated_tariffs(210455);

select * from preftz.receipts r
where r.receiptid = 281348


select 
r.zone_admission_no 
--,r.* 
,c.*
from 
preftz.receipts r
left join preftz.check_current_calculated_tariffs(r.receiptid) c
on c.receiptid = r.receiptid
where r.zone_admission_no
in
(
select efs.zone_admission_no  from preftz.e214_filing_statuses efs
where efs.e214_status is not null
--and efs.zone_admission_no like '26ANT0089_'
and efs.zone_admission_no like '26BWGA00__'
order by efs.zone_admission_no desc
)
order by r.zone_admission_no desc
;

select max(c)
from 
(
select zone_admission_no , count(*) c
from preftz.receipts
where zone_admission_no is not null
--and privileged_date::text like '2026%'
group by zone_admission_no
order by c desc
) x

select count(*) c
from preftz.receipts r
where r.zone_admission_no
in
(
select efs.zone_admission_no  from preftz.e214_filing_statuses efs
where efs.e214_status is not null
--and efs.zone_admission_no like '26ANT0089_'
and efs.zone_admission_no like '26BWGA00__'
order by efs.zone_admission_no desc
)



--'26ANT01128' 99030303
--26ANT00750  26ANT00659 
--26ANT00495


select * from preftz.e214_filing_statuses efs
where efs.e214_status is not null
order by efs.zone_admission_no desc
;

--drop function preftz.check_current_calculated_tariffs;

CREATE OR REPLACE FUNCTION preftz.check_current_calculated_tariffs(p_receiptid int) 
RETURNS TABLE (
    receiptid int4 ,
	e214_date date ,
	privileged_date date ,
	receipt_date date ,
	hts varchar(10) ,
	current_tariffs _varchar ,
	calculated_tariffs _varchar ,
	added_tariffs _varchar ,
	removed_tariffs _varchar 
)
LANGUAGE plpgsql 
AS $BODY$
BEGIN

   PERFORM * from preftz.classify_receipts_v2(null,null,p_receiptid);

    RETURN QUERY
 with target_receipts as (
    -- change this CTE to return the sub-set of receipts you want to compare
    select r.receiptid from preftz.receipts r
    where r.receiptid = p_receiptid
    --where receiptid in(   select receiptid from t1   )
)
, current_tariffs as (
    select rc.receiptid, array_agg(rc.harmonized_tariff_schedule_number order by rc.harmonized_tariff_schedule_number) as current_tariffs
    from preftz.receipt_classifications rc
    join target_receipts rr on rr.receiptid = rc.receiptid
    --where rc.tariff_type NOT IN('BASE')
    group by rc.receiptid
)
, calculated_tariffs as (
    select rc.receiptid, array_agg(rc.harmonized_tariff_schedule_number order by rc.harmonized_tariff_schedule_number) as calculated_tariffs
    from tmp_receipt_classification_work rc
    join target_receipts rr on rr.receiptid = rc.receiptid
    --where rc.tariff_type NOT IN('BASE')
    group by rc.receiptid
)
, added_tariff_compare as (
    select rc.receiptid, efs.e214_date, r.privileged_date, r.receipt_date::date, rc.harmonized_tariff_schedule_number hts
        , ct.current_tariffs
        , calt.calculated_tariffs 
    from preftz.receipt_classifications rc
    join current_tariffs ct on ct.receiptid = rc.receiptid
    join calculated_tariffs calt on calt.receiptid = rc.receiptid
    join preftz.receipts r on r.receiptid = rc.receiptid
    left join preftz.e214_filing_statuses efs on efs.zone_admission_no = r.zone_admission_no
    where rc.tariff_type = 'BASE'
    )
    , compare_with_diff as (
    SELECT atc.*, array(SELECT unnest(atc.calculated_tariffs) EXCEPT SELECT unnest(atc.current_tariffs)) as added_tariffs,
        array(SELECT unnest(atc.current_tariffs) EXCEPT SELECT unnest(atc.calculated_tariffs)) as removed_tariffs
    from added_tariff_compare atc
)
select d.*
from compare_with_diff d;

END;
$BODY$;




where (cardinality(added_tariffs) > 0 or cardinality(removed_tariffs) > 0)
  


--@@@
-- Compare what we calculate as additional tariffs with what's actually in RC
with target_receipts as (
    -- change this CTE to return the sub-set of receipts you want to compare
    select receiptid from preftz.receipts 
    where receiptid in (19551)
    --where receiptid in(   select receiptid from t1   )
), current_tariffs as (
    select rc.receiptid, array_agg(rc.harmonized_tariff_schedule_number) as current_tariffs
    from preftz.receipt_classifications rc
    join target_receipts rr on rr.receiptid = rc.receiptid
    --where rc.tariff_type NOT IN('BASE')
    group by rc.receiptid
), part_tariffs as (
    select r.receiptid, array_agg(pc.harmonized_tariff_schedule_number) as part_hts
    from preftz.receipts r
    join target_receipts tr on tr.receiptid = r.receiptid
    join preftz.part_classifications pc on pc.part_number = r.part_number
        and pc.tariff_type NOT IN('SCRAP','DUTY9')
    group by r.receiptid
), base_hts_diff as (
    select rc.receiptid, rc.harmonized_tariff_schedule_number, pc.harmonized_tariff_schedule_number,
        case when rc.harmonized_tariff_schedule_number <> pc.harmonized_tariff_schedule_number then
            'base HTS changed ' || rc.harmonized_tariff_schedule_number || ' -> ' || pc.harmonized_tariff_schedule_number
            else '' end as hts_diff
    from preftz.receipts r
    join preftz.receipt_classifications rc on rc.receiptid = r.receiptid
        and rc.tariff_type = 'BASE'
    join target_receipts tr on tr.receiptid = r.receiptid
    join preftz.part_classifications pc on pc.part_number = r.part_number
        and pc.tariff_type = 'BASE'
), added_tariff_compare as (
    select rc.receiptid, efs.e214_date, r.privileged_date, r.receipt_date::date, rc.harmonized_tariff_schedule_number,
        preftz.get_all_additional_tariffs(r.part_number, rc.receiptid, rc.harmonized_tariff_schedule_number, r.country_of_origin,
        coalesce(r.privileged_date, r.receipt_date::date)
        --r.receipt_date::date
        , p.special_programs_indicator,
        cs.country_of_cast, cs.primary_country_of_smelt, cs.secondary_country_of_smelt) || pt.part_hts as calculated_tariffs
        , ct.current_tariffs, bhd.hts_diff
    from preftz.receipt_classifications rc
    join current_tariffs ct on ct.receiptid = rc.receiptid
    join preftz.receipts r on r.receiptid = rc.receiptid
    join preftz.parts p on p.part_number = r.part_number
    join part_tariffs pt on pt.receiptid = rc.receiptid
    left join base_hts_diff bhd on bhd.receiptid = rc.receiptid
    left join preftz.receipt_cast_and_smelt cs on cs.receiptid = rc.receiptid
    left join preftz.e214_filing_statuses efs on efs.zone_admission_no = r.zone_admission_no
    where rc.tariff_type = 'BASE'
), compare_with_diff as (
    SELECT atc.*, array(SELECT unnest(atc.calculated_tariffs) EXCEPT SELECT unnest(atc.current_tariffs)) as added_tariffs,
        array(SELECT unnest(atc.current_tariffs) EXCEPT SELECT unnest(atc.calculated_tariffs)) as removed_tariffs
    from added_tariff_compare atc
)
select d.*
from compare_with_diff d;


--where (cardinality(added_tariffs) > 0 or cardinality(removed_tariffs) > 0)

select * 
from preftz.receipt_classifications_v2 t1
where t1.receiptid  = 227894
order by created_date desc;

8532290040		0.64	BASE
99030301		0.0	ADDITIONAL
99038801		0.0	SECTION301


select * 
from preftz.receipt_classifications t1
where t1.receiptid  = 227894;

8532290040		0.64	BASE
99038801		0.0	SECTION301
99030531		0.0	SECTION301 -- incoorect 

select * from preftz.additional_tariffs t
where t.additional_tariff_number = '99030531'


select * 
from preftz.reclassified_receipts rr 





select * 
from preftz.receipt_classifications t1
join tmp_receipt_classification_work t2
on t1.receiptid = t2.receiptid
and t1.harmonized_tariff_schedule_number  = t2.harmonized_tariff_schedule_number 

select * from preftz.receipt_percentage_value


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
order by log_date desc;



select * from preftz.transfer_ztz_archive

select * from preftz.part_classifications

select * from preftz.part_classifications
where tariff_type  <> 'BASE'

select count(*) from preftz.part_classifications
where tariff_type  <> 'BASE'


select part_number 
from preftz.part_classifications
group by part_number
having count(*) > 1;
--0


SELECT r.receiptid, r.part_number, r.zone_status, r.country_of_origin, 	
                     r.unit_price, pc.harmonized_tariff_schedule_number, p.special_programs_indicator,	
                     pc.split_fixed_unit_value, pc.split_value_percentage, tt.value_reported,	
                     pc.tariff_type, pc.distinct_tariff_line_indicator, pc.primary_tariff,	
                     pc.quantity1_conversion_rate quantity1_rate, --RTJ 11/23/2020	
                     pc.quantity2_conversion_rate quantity2_rate, --RTJ 11/23/2020	
                     rcn.antidumping_case_number, rcn.countervailing_case_number,  --RTJ 03/30/2021	
                     rcs.country_of_cast, rcs.primary_country_of_smelt, rcs.secondary_country_of_smelt, --NKM 04/21/2023	
                     q.harmonized_tariff_schedule_number override_tariff,  --RTJ 11/30/2022	
                     preftz.get_receipt_value(r.receiptid) unit_value  --RTJ 01/20/2023	
                     ,r.privileged_date -- EG 06/11/2026
                     --into preftz.yg_receipt_tmp1
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
               WHERE r.zone_admission_no = '26ANT00864'	
                 AND pc.tariff_type <> 'SCRAP'
               ORDER BY r.receiptid, CASE pc.tariff_type WHEN 'BASE' THEN 0 ELSE 9 end
;	

210454

select * from preftz.receipts 
where part_number in
(select part_number from preftz.part_classifications
where tariff_type  <> 'BASE')


            WITH derivatives AS (
                SELECT DISTINCT additional_tariff_number, tariff_type, 
                    LEFT(LOWER(notes), 10) = 'iron_steel' AS is_steel_derivative,
                    LEFT(LOWER(notes), 9) = 'aluminum_' AS is_aluminum_derivative,
                    LEFT(LOWER(notes), 6) = 'copper' AS is_copper_derivative,
                    false AS is_non_content
                FROM preftz.additional_tariff_derivatives
            )
            SELECT rc.harmonized_tariff_schedule_number, COALESCE(dpc.aluminum_percentage,1.0) AS aluminum_percentage, 
                    COALESCE(dpc.steel_percentage,1.0) AS steel_percentage, 
                    COALESCE(dpc.copper_percentage,1.0) AS copper_percentage, pc_base.quantity1_rate as base_qty1,
                    rc.tariff_type, d.is_steel_derivative, d.is_aluminum_derivative, d.is_copper_derivative
            FROM 
            (select t1.receiptid, t1.part_number, t1.privileged_date as receipt_date 
            from tmp_receipt_classification_data t1
            group by t1.receiptid, t1.part_number, t1.privileged_date
            ) r --preftz.receipts r
            JOIN tmp_receipt_classification_work rc ON r.receiptid = rc.receiptid
--            JOIN preftz.part_classifications pc_base ON r.part_number = pc_base.part_number AND pc_base.tariff_type = 'BASE'
            join tmp_receipt_classification_data pc_base
            ON r.receiptid = pc_base.receiptid AND pc_base.tariff_type = 'BASE'
            LEFT JOIN derivatives d ON d.additional_tariff_number = rc.harmonized_tariff_schedule_number
                AND d.tariff_type = rc.tariff_type
            LEFT JOIN preftz.derivative_parts_content dpc ON dpc.part_number = r.part_number
                AND r.receipt_date BETWEEN dpc.start_date AND dpc.end_date
            WHERE r.receiptid = 204373
                AND (rc.tariff_type = 'BASE'
                    OR rc.harmonized_tariff_schedule_number = d.additional_tariff_number)
            ORDER BY CASE 
                WHEN rc.tariff_type = 'BASE' THEN 9 
                WHEN rc.harmonized_tariff_schedule_number = '99037802' THEN 5 -- KK copper hts for non-content instead of applying to BASE
                ELSE 0 END


select * from tmp_receipt_classification_data
where receiptid = 204373;
--60
select * from tmp_receipt_classification_data
where part_number = '1000-0166-0'

select * from tmp_receipt_classification_data
where receiptid = 204373;

WITH derivatives AS (
        SELECT DISTINCT additional_tariff_number, tariff_type, 
            LEFT(LOWER(notes), 10) = 'iron_steel' AS is_steel_derivative,
            LEFT(LOWER(notes), 9) = 'aluminum_' AS is_aluminum_derivative,
			LEFT(LOWER(notes), 6) = 'copper' AS is_copper_derivative,
            false AS is_non_content
        FROM preftz.additional_tariff_derivatives
        -- KK 09/09/2025 removed 99030125, so we don't get false positive when NOT a derivative
    )
    SELECT COUNT(d.additional_tariff_number) FILTER (WHERE d.is_steel_derivative IS TRUE) AS cnt_steel,
        COUNT(d.additional_tariff_number) FILTER (WHERE d.is_aluminum_derivative IS TRUE) AS cnt_aluminum,
        COUNT(d.additional_tariff_number) FILTER (WHERE d.is_copper_derivative IS TRUE) AS cnt_copper,
        COALESCE(dpc.aluminum_percentage,1.0), COALESCE(dpc.steel_percentage,1.0), 
        COALESCE(dpc.copper_percentage,1.0), rc_base.unit_value
    --INTO v_steel_cnt, v_aluminum_cnt, v_copper_cnt, v_aluminum_percentage, v_steel_percentage, v_copper_percentage, v_base_unit_value
    FROM 
       (select t1.receiptid, t1.part_number, t1.privileged_date as receipt_date 
        from tmp_receipt_classification_data t1
        group by t1.receiptid, t1.part_number, t1.privileged_date
        ) r --preftz.receipts r
--    preftz.receipts r
    JOIN tmp_receipt_classification_work rc ON r.receiptid = rc.receiptid
    JOIN tmp_receipt_classification_work rc_base ON r.receiptid = rc_base.receiptid 
        AND rc_base.tariff_type = 'BASE'
    JOIN derivatives d ON d.additional_tariff_number = rc.harmonized_tariff_schedule_number
        AND d.tariff_type = rc.tariff_type
    LEFT JOIN preftz.derivative_parts_content dpc ON dpc.part_number = r.part_number
        AND r.receipt_date BETWEEN dpc.start_date AND dpc.end_date
    --WHERE r.receiptid = 204373
    GROUP BY dpc.aluminum_percentage, dpc.steel_percentage, dpc.copper_percentage, rc_base.unit_value;

select * from tmp_receipt_classification_work;

-------------------------------------------------------

SELECT * FROM preftz.compare_receipt_classifications_to_v2(12345);

CREATE OR REPLACE FUNCTION preftz.compare_receipt_classifications_to_v2 (
    p_receiptid integer
)
RETURNS TABLE (
    receiptid integer,
    harmonized_tariff_schedule_number varchar(10),
    field_name text,
    current_value text,
    v2_value text,
    difference_type text
)
LANGUAGE plpgsql
AS $function$
BEGIN

    RETURN QUERY
    WITH compared_rows AS (
        SELECT
            COALESCE(t.receiptid, v.receiptid) AS receiptid,
            COALESCE(
                t.harmonized_tariff_schedule_number,
                v.harmonized_tariff_schedule_number
            ) AS harmonized_tariff_schedule_number,

            t.receiptid AS current_receiptid,
            v.receiptid AS v2_receiptid,

            t.special_programs_indicator AS current_special_programs_indicator,
            v.special_programs_indicator AS v2_special_programs_indicator,

            t.unit_value AS current_unit_value,
            v.unit_value AS v2_unit_value,

            t.tariff_type AS current_tariff_type,
            v.tariff_type AS v2_tariff_type,

            t.distinct_tariff_line_indicator AS current_distinct_tariff_line_indicator,
            v.distinct_tariff_line_indicator AS v2_distinct_tariff_line_indicator,

            t.primary_tariff AS current_primary_tariff,
            v.primary_tariff AS v2_primary_tariff,

            t.quantity1_rate AS current_quantity1_rate,
            v.quantity1_rate AS v2_quantity1_rate,

            t.quantity2_rate AS current_quantity2_rate,
            v.quantity2_rate AS v2_quantity2_rate,

            t.unit_duty_liability AS current_unit_duty_liability,
            v.unit_duty_liability AS v2_unit_duty_liability

        FROM preftz.receipt_classifications t
        FULL OUTER JOIN preftz.receipt_classifications_v2 v
            ON v.receiptid = t.receiptid
           AND v.harmonized_tariff_schedule_number = t.harmonized_tariff_schedule_number
        WHERE COALESCE(t.receiptid, v.receiptid) = p_receiptid
    )

    SELECT
        c.receiptid,
        c.harmonized_tariff_schedule_number,
        d.field_name,
        d.current_value,
        d.v2_value,
        d.difference_type
    FROM compared_rows c
    CROSS JOIN LATERAL (
        VALUES
            (
                'ROW_STATUS',
                CASE WHEN c.current_receiptid IS NULL THEN NULL ELSE 'EXISTS' END,
                CASE WHEN c.v2_receiptid IS NULL THEN NULL ELSE 'EXISTS' END,
                CASE
                    WHEN c.current_receiptid IS NULL THEN 'MISSING_IN_CURRENT'
                    WHEN c.v2_receiptid IS NULL THEN 'MISSING_IN_V2'
                    ELSE 'MATCH'
                END
            ),
            (
                'special_programs_indicator',
                c.current_special_programs_indicator::text,
                c.v2_special_programs_indicator::text,
                CASE WHEN c.current_special_programs_indicator IS DISTINCT FROM c.v2_special_programs_indicator THEN 'DIFFERENT' ELSE 'MATCH' END
            ),
            (
                'unit_value',
                c.current_unit_value::text,
                c.v2_unit_value::text,
                CASE WHEN c.current_unit_value IS DISTINCT FROM c.v2_unit_value THEN 'DIFFERENT' ELSE 'MATCH' END
            ),
            (
                'tariff_type',
                c.current_tariff_type::text,
                c.v2_tariff_type::text,
                CASE WHEN c.current_tariff_type IS DISTINCT FROM c.v2_tariff_type THEN 'DIFFERENT' ELSE 'MATCH' END
            ),
            (
                'distinct_tariff_line_indicator',
                c.current_distinct_tariff_line_indicator::text,
                c.v2_distinct_tariff_line_indicator::text,
                CASE WHEN c.current_distinct_tariff_line_indicator IS DISTINCT FROM c.v2_distinct_tariff_line_indicator THEN 'DIFFERENT' ELSE 'MATCH' END
            ),
            (
                'primary_tariff',
                c.current_primary_tariff::text,
                c.v2_primary_tariff::text,
                CASE WHEN c.current_primary_tariff IS DISTINCT FROM c.v2_primary_tariff THEN 'DIFFERENT' ELSE 'MATCH' END
            ),
            (
                'quantity1_rate',
                c.current_quantity1_rate::text,
                c.v2_quantity1_rate::text,
                CASE WHEN c.current_quantity1_rate IS DISTINCT FROM c.v2_quantity1_rate THEN 'DIFFERENT' ELSE 'MATCH' END
            ),
            (
                'quantity2_rate',
                c.current_quantity2_rate::text,
                c.v2_quantity2_rate::text,
                CASE WHEN c.current_quantity2_rate IS DISTINCT FROM c.v2_quantity2_rate THEN 'DIFFERENT' ELSE 'MATCH' END
            ),
            (
                'unit_duty_liability',
                c.current_unit_duty_liability::text,
                c.v2_unit_duty_liability::text,
                CASE WHEN c.current_unit_duty_liability IS DISTINCT FROM c.v2_unit_duty_liability THEN 'DIFFERENT' ELSE 'MATCH' END
            )
    ) AS d(field_name, current_value, v2_value, difference_type)
    WHERE d.difference_type <> 'MATCH'
    ORDER BY
        c.receiptid,
        c.harmonized_tariff_schedule_number,
        d.field_name;

END;
$function$;



////////////////////////////////////////////////////////////


select 
wer.hts_number 
   ,wer.chapter99_hts_numbers 
   ,wer.country_of_origin 
   ,wer.manufacturer_id_code
   ,coalesce(wer.privileged_foreign,false)
   ,*
from preftz.weekly_estimate_records wer 
where wer.release_documentid = 0
and wer.manufacturer_id_code  like '%MYAVATEC315SIM%'
order by country_of_origin, hts_number


select 
wer.hts_number 
   ,wer.chapter99_hts_numbers 
   ,wer.country_of_origin 
   ,wer.manufacturer_id_code
   ,coalesce(wer.privileged_foreign,false)
   ,count(*)
from preftz.weekly_estimate_records wer 
where wer.release_documentid = 0
and wer.manufacturer_id_code  like '%MYAVATEC315SIM%'
group by  
wer.hts_number 
   ,wer.chapter99_hts_numbers 
   ,wer.country_of_origin 
   ,wer.manufacturer_id_code
   ,coalesce(wer.privileged_foreign,false)
having count(*) > 1
order by country_of_origin, hts_number
--734


select
zone_status
,manufacturer_mid_code
,* 
from preftz.receipts
where 
zone_status <> 'D'
and manufacturer_mid_code  
in
(
select 
   wer.manufacturer_id_code
from preftz.weekly_estimate_records wer 
where wer.release_documentid = 0
group by  
wer.hts_number 
   ,wer.chapter99_hts_numbers 
   ,wer.country_of_origin 
   ,wer.manufacturer_id_code
   ,coalesce(wer.privileged_foreign,false)
having count(*) > 1
)


8504504000	{99030301}	TW	HKABRLLC10TSI
8504508000	{99030301}	JP	HKABRLLC10TSI
8504508000	{99030301}	KR	HKABRLLC10TSI
8504508000	{99030301}	MY	HKABRLLC10TSI
8504508000	{99030301}	TW	HKABRLLC10TSI
8504508000	{99030301}	VN	HKABRLLC10TSI
8529104040	{99030301}	TW	HKABRLLC10TSI


select
zone_status
,pre_receipt
,preftz.check_receipt_against_template(receiptid )
,country_of_origin 
,manufacturer_mid_code
,* 
from preftz.receipts
where 
zone_status <> 'D'
and manufacturer_mid_code  like '%MYAVATEC315SIM%'
and preftz.check_receipt_against_template(receiptid) = 'FAIL'
--and country_of_origin = 'TW'

select * 
FROM preftz.archived_updated_receipts ftf
where 
manufacturer_mid_code  = 'MYAVATEC315SIM'

select * from preftz.receipt_classifications rc
where rc.receiptid  in  (217456,245140,245145)


select 
wer.hts_number 
   ,wer.chapter99_hts_numbers 
   ,wer.country_of_origin 
   ,wer.manufacturer_id_code
   ,coalesce(wer.privileged_foreign,false)
   ,*
from preftz.weekly_estimate_records wer 
where wer.release_documentid = 0
and wer.manufacturer_id_code  like '%MYAVATEC315SIM%'
order by country_of_origin, hts_number


8517620090	{99030303}	MY
8536610000	{99030301}	MY
8543704500	{99030301}	MY
8543709860	{99030301}	MY
8544700000	{99030301}	MY


add_template_for_receipt

select  coalesce(preftz.get_ftz_setting('ADD TO CARGO TEMPLATE ON CONCUR'),'NO')

select
sl.procedure_name 
,sl.log_message 
--,sl.details 
,log_date
,(log_date AT TIME ZONE 'UTC') AT TIME ZONE 'America/New_York'
--delete 
from preftz.system_log sl 
where sl.procedure_name like '%add_template_for_receipt%'
--where sl.procedure_name like '%receipts%'
--where sl.procedure_name like '%create_e214%'
--where sl.procedure_name like '%link_receipts_to_conveyances_by_inbond%'
--and sl.log_message like 'MARKED AS DUPLICATE%'
order by sl.logid desc;


select check_receipt_against_template


-------------------------------------------------


select
zone_status
,pre_receipt
,country_of_origin 
,manufacturer_mid_code
,* 
from preftz.receipts
where 
zone_status <> 'D'
and manufacturer_mid_code  like '%CNHANGRA22HAN%'
--and preftz.check_receipt_against_template(receiptid) = 'FAIL'
--and country_of_origin = 'TW'

select * from archived_release_documents ard
where ard.release_document_number  = 'NRT-0729226-4'
--1060
--986

select * from release_documents ard
where ard.release_document_number  = 'NRT-0729226-4'
--1305


with
shipments as (
select 'cur' as tab, * from shipments
    union
    select 'wk' as tab,* from weekly_shipments
    union
    select 'ar' as tab,* from archived_shipments
)
select * from shipments
where release_documentid  = 1319

select * from inventory_items ii


with demands as (
select 'cur' as tab, * from demands
    union
    select 'wk' as tab,* from weekly_demands
    union
    select 'ar' as tab,* from archived_demands
),
links as (
select 'cur' as tab,* from demands_items_links
    union
    select 'wk' as tab,* from weekly_demands_items_links
    union
    select 'ar' as tab,* from archived_demands_items_links
),
shipments as (
select 'cur' as tab, * from shipments
    union
    select 'wk' as tab,* from weekly_shipments
    union
    select 'ar' as tab,* from archived_shipments
)
select d.production_issueid,* from inventory_items ii 
join links l on ii.itemid = l.itemid
join demands d on l.demandid = d.demandid
left join shipments s on d.shipmentid = s.shipmentid
where release_documentid  = 1060
and ii.zone_status <> 'D'
and ii.part_number in 
(select
distinct part_number
from preftz.receipts
where 
zone_status <> 'D'
and manufacturer_mid_code  like '%CNHANGRA22HAN%'
)

--15 

select * from preftz.shipments_items_links sil



select * from preftz.archived_shipments_items_links sil
where sil.entry_summary_lineid  in 
(select entry_summary_lineid 
from preftz.archived_entry_summary_lines aesl
where release_documentid  = 1319)

select * 
from preftz.entry_summary_lines aesl
where release_documentid  = 1319

-3126101

select * from preftz.weekly_shipments ws 
where shipmentid = -3126101

select * from preftz.shipments_items_links sil
where shipmentid = -3126101

select * from preftz.archived_shipments_items_links sil
where shipmentid = -3126101

select * from preftz.weekly_shipments_items_links sil
where shipmentid in ( 1943913 ,  1815489)

select * from preftz.archived_shipments_items_links sil
where shipmentid = 1798589




select * from preftz.weekly_shipments_items_links wsil
where wsil.itemid = 3164465

select * from preftz.archived_shipments_items_links sil
where itemid = 3164465

where shipmentid = -3126101

select * from preftz.archived_shipments_items_links sil
where sil.entry_summary_lineid  in 
(select entry_summary_lineid 
from preftz.entry_summary_lines aesl
where release_documentid  = 1305)

select * from preftz.inventory_items ii
where ii.itemid = 3163541

select * from preftz.receipts 
where receiptid  = 234897


select * from preftz.inventory_items ii 
where ii.itemid in 
(select sil.itemid  from preftz.archived_shipments_items_links sil
where sil.entry_summary_lineid  in 
(select entry_summary_lineid 
from preftz.archived_entry_summary_lines aesl
where release_documentid  = 1060))

--$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

with
shipments as (
select 'cur' as tab, * from shipments
    union
    select 'wk' as tab,* from weekly_shipments
    union
    select 'ar' as tab,* from archived_shipments
)
select
*
--sum(quantity_shipped) 
from shipments
where release_documentid  = 1319

select 
*
--sum(wsil.quantity_linked)
from preftz.weekly_shipments_items_links wsil
where wsil.shipmentid  in
(
select shipmentid from weekly_shipments
where release_documentid  = 1319
)
--22

select *  from preftz.inventory_items
where itemid = 2849823

select *  from preftz.receipts
where receiptid = -9999


with
shipments as (
select 'cur' as tab, * from shipments
    union
    select 'wk' as tab,* from weekly_shipments
    union
    select 'ar' as tab,* from archived_shipments
)
select * from shipments
where release_documentid  = 1319


select * from preftz.weekly_shipments_items_links wsil
where wsil.itemid = 3164465
union all
select * from preftz.archived_shipments_items_links sil
where itemid = 3164465



with
shipments as (
select 'cur' as tab, * from preftz.shipments
    union
    select 'wk' as tab,* from preftz.weekly_shipments
    union
    select 'ar' as tab,* from preftz.archived_shipments
)
select * from shipments
where shipmentid 
in 
(select wsil.shipmentid  from preftz.weekly_shipments_items_links wsil
where wsil.itemid --= 40072
in (select itemid  from preftz.inventory_items
where receiptid in 
(select
distinct receiptid  
from preftz.tmp_EG_ztz_1
where ztz_priv_date <> r_priv_date)
and quantity_on_hand < quantity_received
)
union 
select shipmentid from preftz.archived_shipments_items_links sil
where itemid --= 40072
in (select itemid  from preftz.inventory_items
where receiptid in 
(select
distinct receiptid  
from preftz.tmp_EG_ztz_1
where ztz_priv_date <> r_priv_date)
and quantity_on_hand < quantity_received
)
);


select * from preftz.inventory_items
--select * from preftz.receipts
where receiptid in 
(select
distinct receiptid  
from preftz.tmp_EG_ztz_1
where ztz_priv_date <> r_priv_date)
and quantity_on_hand < quantity_received
--and quantity_on_hand = 0
order by receiptid 

select itemid  from preftz.inventory_items
where receiptid in 
(select
distinct receiptid  
from preftz.tmp_EG_ztz_1
where ztz_priv_date <> r_priv_date)
and quantity_on_hand < quantity_received
--and quantity_on_hand = 0
order by receiptid 


40348


--99038803

select * from preftz.receipt_classifications rc
where rc.receiptid  in  (285776)


select
distinct part_number
from preftz.receipts
where 
zone_status <> 'D'
and manufacturer_mid_code  like '%CNHANGRA22HAN%'

select * 
from preftz.entry_summary_lines esl

select * 
from preftz.archived_entry_summary_lines aesl
where release_documentid  = 1319

select * 
from preftz.archived_entry_summary_lines_classifications aeslc 
where release_documentid  = 1060



--create_entry_summary_lines
--1060
--986


--chest

LINE #	Error	Notes
001	Missing	99038803 in es and cr
089	Missing	99038193 no es , ok cr 221798  221810  221772 221823

576	Missing	99038803 no es, no cr ZTZ reclassify has an exclusion 99038869 exclude 99038803 283567 

582	Missing	99038803 no es, no cr ZTZ same 283586 283204
594	Missing	99038803 no es, no cr ZTZ 283205
601	Missing	99038803 no es, no cr ZTZ 283593



--geo
Line	Error	Notes
001	Missing	99038803 in es and cr 
050	Missing	99030306, 99038202 no es, no cr ZTZ 63785
051	Missing	99030306, 99038202 no es, EMPTY cr
053	Missing	99030306, 99038202 no es, no cr ZTZ 63808
054	Missing	99030306, 99038202 no es, EMPTY cr
119	Missing	99030301 no es, no cr ztz 63675 63655  63678  63631 63667 63672 63654
120	Missing	99030301 no es, no cr ZTZ 63640
161	Missing	99030301 no es, no cr ZTZ 63775
162	Missing	99030301 no es, EMPTY cr
226	Missing	99030301, 99037411, 99039406 no es, no cr ZTZ 63609
449	Missing	99030301 no es, no cr ZTZ 63980 63989
450	Missing	99030301 no es, no cr ZTZ 63951 63953
479	Missing	99030301 no es, no cr ZTZ 63858

--chest



LINE	Error	Notes
001	Missing Tariff	99038803 not missed
672	Missing Tariff	99030531 rid 285776
673	Missing Tariff	99030531 rid 287026

99039406		0.0	SECTION232
99037411		0.0	SECTION232
8511400000		13.71	BASE
99038869		0.0	EXCLUSION301

{99030531} missing


select
aeslc.harmonized_tariff_schedule_number
,aeslc.tariff_type 
,* 
from preftz.archived_entry_summary_lines aesl
join preftz.archived_entry_summary_lines_classifications aeslc
on aesl.entry_summary_lineid = aeslc.entry_summary_lineid
where release_documentid  = 1062--986 
and aesl.entry_summary_line_number  = '001'


select * from preftz.

select 
r.privileged_date 
,r.receipt_date
,r.zone_to_zone_transfer 
,rc.* 
from preftz.receipts r 
left join  preftz.receipt_classifications rc
on r.receiptid = rc.receiptid
where r.receiptid  in  
(
select 
ii.receiptid  
from preftz.archived_entry_summary_lines aesl
--join preftz.archived_entry_summary_lines_classifications aeslc
--on aesl.entry_summary_lineid = aeslc.entry_summary_lineid
join 
(
select * from preftz.archived_shipments_items_links
--where entry_summary_lineid  = 1271283
union all
select * from preftz.weekly_shipments_items_links
--where entry_summary_lineid  = 1271283
)sil
on sil.entry_summary_lineid  = aesl.entry_summary_lineid
join preftz.inventory_items ii
on ii.itemid  = sil.itemid 
where release_documentid  = 1062 
and aesl.entry_summary_line_number  = '672'
)


select 
ii.* 
from preftz.archived_entry_summary_lines aesl
--join preftz.archived_entry_summary_lines_classifications aeslc
--on aesl.entry_summary_lineid = aeslc.entry_summary_lineid
join preftz.archived_shipments_items_links sil
on sil.entry_summary_lineid  = aesl.entry_summary_lineid
join preftz.inventory_items ii
on ii.itemid  = sil.itemid 
where release_documentid  = 1062 
and aesl.entry_summary_line_number  = '001'


select * from preftz.inventory_items ii 
where ii.itemid in 
(select sil.itemid  from preftz.archived_shipments_items_links sil
where sil.entry_summary_lineid  in 
(select entry_summary_lineid 
from preftz.archived_entry_summary_lines aesl
where release_documentid  = 1062))

select * from preftz.inventory_items ii 
where ii.itemid in 
(
select sil.itemid  from preftz.weekly_shipments_items_links sil
where sil.entry_summary_lineid  in 



(select entry_summary_lineid 
from preftz.entry_summary_lines aesl
where release_documentid  = 1319)
)



select * from preftz.additional_tariffs t 
where t.additional_tariff_number 
in
(
--'99030301'
'99038869'
--,'99038803'
)
order by additional_tariff_number

--2025-05-30
select * from preftz.additional_tariff_derivatives atd  
where additional_tariff_number 
in
(
'99038869'
--'99038193'
--,'99038803'
)
order by additional_tariff_number


select * from preftz.additional_tariff_replacements atr
where atr.tariff_number = '99038869' 

select * from preftz.additional_tariff_exclusions ate 

select * from preftz.additional_tariff_exceptions ate

select * from preftz.additional_tariff_tags att
where att.additional_tariff_number  = '99038869'

select * from preftz.additional_tariff_variable_rates atvr 
where atvr.exclusion_tariff    = '99038869'

select * from preftz.tariff_reclassifications_for_entry
where from_tariff_number  = '99038869' 

select * from preftz.added_tariffs
where from_tariff_number  = '99038869' 


added_tariffs




2026-07-20 00:00:00.000

select * from preftz.transfer_ztz_archive
where transfer_itemid in (
select * from preftz.get_transfer_itemid_from_ztz_receiptid(63852)
)
order by created_date desc;

--2026-01-05

2025-12-11	2026-07-13 00:00:00.000	Y	283567	8511400000
2025-12-11	2026-07-13 00:00:00.000	Y	283567	99039406
2025-12-11	2026-07-13 00:00:00.000	Y	283567	99037411

99038869

select * FROM preftz.tariff_reclassifications_for_entry tre



-- Link from Entry summary lines or archived to items on a specific line
-- No aggregation with derivative_line - individual items and shipments
WITH all_shipments_items_links AS (
    SELECT 'shipments_items_links' AS tab, *, NULL::INTEGER AS entry_summary_lines_workid FROM preftz.shipments_items_links
    UNION SELECT 'weekly_shipments_items_links' AS tab, * FROM preftz.weekly_shipments_items_links
    UNION SELECT 'archived_shipments_items_links' AS tab, * FROM preftz.archived_shipments_items_links
), all_shipments AS (
    SELECT 'shipments' AS tab, * FROM preftz.shipments
    UNION SELECT 'weekly_shipments' AS tab, * FROM preftz.weekly_shipments
    UNION SELECT 'archived_shipments' AS tab, * FROM preftz.archived_shipments
), all_entry_summary_lines AS (
    select 'entry_summary_lines' as tab, esl.* , COALESCE(dl.primary_lineid,
        esl.entry_summary_lineid) as linked_lineid, COALESCE(dl.derivative_line,'') as derivative_line
    from preftz.entry_summary_lines esl
    left join preftz.entry_summary_derivative_links dl on dl.secondary_lineid = esl.entry_summary_lineid
    union
    select 'archived_entry_summary_lines' as tab, esl.* , COALESCE(dl.primary_lineid,
        esl.entry_summary_lineid) as linked_lineid, COALESCE(dl.derivative_line,'') as derivative_line
    from preftz.archived_entry_summary_lines esl
    left join preftz.archived_entry_summary_derivative_links dl on dl.secondary_lineid = esl.entry_summary_lineid
)
select esl.release_documentid, esl.entry_summary_line_number, esl.harmonized_tariff_schedule_number, esl.zone_status,
    esl.privileged_date, esl.country_of_origin, esl.manufacturer_mid_code, esl.value_of_goods, esl.derivative_line
    --, eslc.*
    --, sil.shipmentid, sil.quantity_linked
    , array_agg(distinct shipmentid) as shipmentids
    , ii.itemid, ii.receiptid, ii.part_number, ii.quantity_received, ii.quantity_on_hand
from all_entry_summary_lines esl
join all_shipments_items_links sil on sil.entry_summary_lineid = esl.linked_lineid
join preftz.inventory_items ii on ii.itemid = sil.itemid
where esl.release_documentid = 1062
    and esl.entry_summary_line_number in('001','672')
group by esl.release_documentid, esl.entry_summary_line_number, esl.harmonized_tariff_schedule_number, esl.zone_status,
    esl.privileged_date, esl.country_of_origin, esl.manufacturer_mid_code, esl.value_of_goods, esl.derivative_line
    , ii.itemid, ii.receiptid, ii.part_number, ii.quantity_received, ii.quantity_on_hand
order by esl.entry_summary_line_number;
;


---------------------------------
--@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ 1
--@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
--@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
--@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
--@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

select * 
into preftz.receipts_20260806
from preftz.receipts;
--39839


select * 
into preftz.tmp_EG_ztz_1_20260813
from preftz.tmp_EG_ztz_1;

select * 
from preftz.receipts r
where r.zone_to_zone_transfer = 'Y'
and r.receipt_date > '2026-01-01' 

--drop table preftz.tmp_EG_ztz_1;

select
r.receiptid 
,r.receipt_date
,r.privileged_date r_priv_date 
,t1.privileged_date ztz_priv_date
,t1.ztz_base_tariffs 
,t1.ztz_additional_tariffs
into tmp_EG_ztz_1
--,* 
from preftz.receipts r
join preftz.transfer_ztz_archive t1
on t1.transfer_itemid = preftz.get_transfer_itemid_from_ztz_receiptid(r.receiptid )
where r.zone_to_zone_transfer = 'Y'
and r.receipt_date > '2026-01-01';
--g 2207 
--ch 2479 2479 3146 3627 20m

delete from preftz.tmp_EG_ztz_1
where ztz_priv_date is null;
--g 1590
--ch 1035 1508

select * from preftz.tmp_EG_ztz_1;
--g 617 g
--ch 1444 18251 2119

select * 
from preftz.tmp_EG_ztz_1 t
--, preftz.compare_receipt_tariffs(t.receiptid)
--where ztz_priv_date is distinct from r_priv_date
--where ztz_priv_date <> r_priv_date;
where ztz_priv_date = r_priv_date;
--order by t.receiptid ;
--where ztz_priv_date = r_priv_date;
--g 239 g all from 2026-07-20 00:00:00.000
--ch 2

select t.receiptid , ztz_priv_date, t.r_priv_date
,t.ztz_additional_tariffs
,t1.added_tariffs
,t1.removed_tariffs
from preftz.tmp_EG_ztz_1 t
, preftz.compare_receipt_tariffs(t.receiptid) t1
where ztz_priv_date <> r_priv_date
and t.receiptid in
(select receiptid from preftz.inventory_items
where receiptid in 
(select
distinct receiptid  
from preftz.tmp_EG_ztz_1
where ztz_priv_date <> r_priv_date
)
and quantity_on_hand < quantity_received
and quantity_on_hand > 0
)
order by t.receiptid ;


select t.receiptid , ztz_priv_date, t.r_priv_date
,t.ztz_additional_tariffs
,t1.added_tariffs
,t1.removed_tariffs
from preftz.tmp_EG_ztz_1 t
, preftz.compare_receipt_tariffs(t.receiptid) t1
where ztz_priv_date = r_priv_date
and t.receiptid in
(select receiptid from preftz.inventory_items
where receiptid in 
(select
distinct receiptid  
from preftz.tmp_EG_ztz_1
where ztz_priv_date = r_priv_date
)
--and quantity_on_hand < quantity_received
)
order by t.receiptid ;

select * FROM preftz.tariff_reclassifications_for_entry
where from_tariff_number  in 
('99038869','99030132','','99030133','99030125','99030163','99030269','99030120')
;

284170
284171



select * from preftz.inventory_items
--select * from preftz.receipts
where receiptid in
(
63638
,63884
,63885
,63887
,63888
,63889
,63891
,63897
,63898
,63900
,64156
)



select t.receiptid , ztz_priv_date, t.r_priv_date 
,t.ztz_additional_tariffs
,t1.added_tariffs
,t1.removed_tariffs
from preftz.tmp_EG_ztz_1 t
, preftz.compare_receipt_tariffs(t.receiptid) t1
where t.receiptid in
(
63609
,63620
,63631
,63637
,63640
,63654
,63655
,63672
,63707
,63721
,63722
,63726
,63730
,63756
,63775
,63785
,63790
,63808
,63809
,63812
,63821
,63858
,63951
,63953
,63989
)
order by t.receiptid ;


SELECT * FROM preftz.compare_receipt_tariffs(63989);

SELECT * FROM preftz.tariff_reclassifications_for_entry
order by from_tariff_number ;
99030163
99030269



select * 
FROM preftz.tmp_EG_ztz_1 t
WHERE  t.ztz_priv_date IS DISTINCT FROM t.r_priv_date
  AND EXISTS
  (
      SELECT 1
      FROM preftz.inventory_items ii
      WHERE ii.receiptid = t.receiptid
        AND ii.quantity_on_hand = ii.quantity_received
  )
order by receiptid ;

select * into preftz.receipts_20260813 from preftz.receipts r;
--39968

UPDATE preftz.receipts r
SET privileged_date = t.ztz_priv_date
FROM preftz.tmp_EG_ztz_1 t
WHERE t.receiptid = r.receiptid
  AND t.ztz_priv_date IS DISTINCT FROM t.r_priv_date
  AND EXISTS
  (
      SELECT 1
      FROM preftz.inventory_items ii
      WHERE ii.receiptid = t.receiptid
        AND ii.quantity_on_hand < ii.quantity_received
        AND ii.quantity_on_hand > 0
  )
and r.privileged_date <> t.ztz_priv_date
  ;





Line	Error	Notes
001	Missing	99038803 in es and cr 

050	Missing	99030306, 99038202 no es, no cr ZTZ 63785
051	Missing	99030306, 99038202 no es, EMPTY cr
053	Missing	99030306, 99038202 no es, no cr ZTZ 63808
054	Missing	99030306, 99038202 no es, EMPTY cr
119	Missing	99030301 no es, no cr ztz 63675 63655  63678  63631 63667 63672 63654
120	Missing	99030301 no es, no cr ZTZ 63640
161	Missing	99030301 no es, no cr ZTZ 63775
162	Missing	99030301 no es, EMPTY cr
226	Missing	99030301, 99037411, 99039406 no es, no cr ZTZ 63609
449	Missing	99030301 no es, no cr ZTZ 63980 63989
450	Missing	99030301 no es, no cr ZTZ 63951 63953
479	Missing	99030301 no es, no cr ZTZ 63858



select * from preftz.inventory_items
--select * from preftz.receipts
where receiptid in 
(select
distinct receiptid  
from preftz.tmp_EG_ztz_1
where ztz_priv_date <> r_priv_date)
--and quantity_on_hand = quantity_received
and quantity_on_hand < quantity_received
--and quantity_on_hand = 0
order by receiptid 
--239  not depleted = 200, 38 part, 9 -  0 zero 

select * from preftz.receipts
where zone_admission_no  = '26BWGA0081'
--240

select * from preftz.receipts
where receiptid = 277713


select 
efs.has_pre_receipts
,efs.data_updated_after_create 
,* 
from preftz.e214_filing_statuses efs
--where efs.concur_status is null 
order by efs.zone_admission_no desc;



select
* 
from preftz.tmp_EG_ztz_1
,preftz.check_ztz_hts_2(receiptid)
where r_priv_date is not null
order by receiptid 


select * from preftz.inventory_items
--select * from preftz.receipts
where receiptid in 
(select
distinct receiptid  
from preftz.tmp_EG_ztz_1
,preftz.check_ztz_hts_2(receiptid)
where r_priv_date is not null)
order by receiptid


insert into preftz.selected_receipts_to_reclassify (receiptid)
select receiptid from preftz.tmp_EG_ztz_1
where receiptid in
(
63609
,63620
,63631
,63637
,63640
,63654
,63655
,63672
,63707
,63721
,63722
,63726
,63730
,63756
,63775
,63785
,63790
,63808
,63809
,63812
,63821
,63858
,63951
,63953
,63989
)


select * from preftz.selected_receipts_to_reclassify

call preftz.reclassify_receipts_fix(false);--4m

--------------------------------------------------------

285771
285773
285774
286936
286937
286950
286964
286967
287041
287057

select 
* 
from preftz.archived_entry_summary_lines aesl
--join preftz.archived_entry_summary_lines_classifications aeslc
--on aesl.entry_summary_lineid = aeslc.entry_summary_lineid
join preftz.archived_shipments_items_links sil
on sil.entry_summary_lineid  = aesl.entry_summary_lineid
join preftz.inventory_items ii
on ii.itemid  = sil.itemid 
--where release_documentid  = 1062 and aesl.entry_summary_line_number  = '001'
--where ii.receiptid = 286950
where ii.receiptid in 
(285771 --chest
,285773
,285774
,286936
,286937
,286964
,287041
,287057
)
--geo
--(64494
--,64666
--,64710
--,64520
--,64492
--,64493
--,64691
--)

select *  from preftz.release_documents rd

select *  from preftz.archived_release_documents rd
where rd.release_documentid = 1062

NRT-0729226-4

select *  from preftz.archived_release_documents rd
where rd.release_documentid in (986,1019)

NRT-0723226-0
NRT-0730226-1

select
r.privileged_date 
,zone_to_zone_transfer
,r.zone_admission_no 
,x.*
from preftz.receipts r
,preftz.compare_receipt_tariffs(r.receiptid) x
where r.privileged_date > '2026-08-01'



select
r.privileged_date 
,zone_to_zone_transfer  
,x.*
from preftz.receipts r
,preftz.compare_receipt_tariffs(r.receiptid) x
where r.privileged_date > '2026-07-23'
and r.zone_status <> 'D'
and (x.added_tariffs > '{}' or x.removed_tariffs > '{}')


select
r.privileged_date 
,zone_to_zone_transfer  
,x.*
from preftz.receipts r
,preftz.compare_receipt_tariffs(r.receiptid) x
where r.privileged_date between '2026-06-01' and '2026-07-23' 
and (x.added_tariffs > '{}' or x.removed_tariffs > '{}')

--@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ 2
--@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ 2
--@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ 2
--@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ 2
--@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ 2

--drop table preftz.tmp_eg1

select
x.receiptid 
into preftz.tmp_eg1
from preftz.receipts r
,preftz.compare_receipt_tariffs(r.receiptid) x
where r.privileged_date > '2026-07-23'
and (x.added_tariffs > '{}' or x.removed_tariffs > '{}')


select
r.privileged_date 
,r.zone_admission_no 
,zone_to_zone_transfer  
,x.*
from preftz.receipts r
,preftz.compare_receipt_tariffs(r.receiptid) x
where r.receiptid in (select * from preftz.tmp_eg1)


select * from 
preftz.receipts ii 
where ii.receiptid in
(select distinct receiptid  from preftz.tmp_eg1
--where receiptid = 286950
)

select * from 
preftz.inventory_items ii 
where ii.receiptid in 
(select distinct receiptid  from preftz.tmp_eg1
)
and ii.quantity_on_hand = ii.quantity_received
and ii.quantity_on_hand > 0
--ch 129/geo 51 / trf 28

select * from preftz.weekly_shipments_items_links wsil
where wsil.itemid in
(select ii.itemid  from 
preftz.inventory_items ii 
where ii.receiptid in 
(select distinct receiptid  from preftz.tmp_eg1
)
--and ii.quantity_on_hand < ii.quantity_received
--and ii.quantity_on_hand = 0
)

select *  from 
preftz.inventory_items ii 
where ii.itemid in (244732,244749)

insert into preftz.selected_receipts_to_reclassify (receiptid)
select 244732 union all
select 244749 union all
select 286290 union all
select 286969 union all
select 286971 union all
select 286914 union all
select 286963


select * 
into preftz.receipt_classifications_20260810
from preftz.receipt_classifications

insert into preftz.selected_receipts_to_reclassify (receiptid)
select
receiptid
from 
preftz.inventory_items ii 
where ii.receiptid in 
(select * from preftz.tmp_eg1)
and ii.quantity_on_hand = ii.quantity_received

select * from preftz.selected_receipts_to_reclassify

286950
286967

call preftz.reclassify_receipts_fix(false);--4m



---
select * from preftz.check_ztz_hts_2(278073)

select preftz.check_ztz_hts_2

--georgia
1. all have priv date set incorectly on receipts->so classification is correct in our table 
but if client used incorrect priv date it may looks like incorrect  


Line	Error	Notes
001	Missing	99038803 in es and cr 

050	Missing	99030306, 99038202 no es, no cr ZTZ 63785
051	Missing	99030306, 99038202 no es, EMPTY cr
053	Missing	99030306, 99038202 no es, no cr ZTZ 63808
054	Missing	99030306, 99038202 no es, EMPTY cr
119	Missing	99030301 no es, no cr ztz 63675 63655  63678  63631 63667 63672 63654
120	Missing	99030301 no es, no cr ZTZ 63640
161	Missing	99030301 no es, no cr ZTZ 63775
162	Missing	99030301 no es, EMPTY cr
226	Missing	99030301, 99037411, 99039406 no es, no cr ZTZ 63609
449	Missing	99030301 no es, no cr ZTZ 63980 63989
450	Missing	99030301 no es, no cr ZTZ 63951 63953
479	Missing	99030301 no es, no cr ZTZ 63858

--how many have invent and fully depleted
--and in the weekly table  



63640
2026-02-17

8708915000
99037411
99038803
99039406

select preftz.classify_receipts_v2(null,'2025-12-30',63858,true);

select preftz.generate_tmp_receipt_classification_data(null,null,284652); --c
--temp tables
select * from tmp_receipt_classification_data
--where receiptid = 210455;
--31

select * from tmp_receipt_classification_work

where receiptid = 210455;





--chest

LINE #	Error	Notes
001	Missing	99038803 in es and cr - no issues
089	Missing	99038193 no es , ok cr 221798  221810  221772 221823 - missed in ES but present on classify receipts
--these are ZTZ 
576	Missing	99038803 no es, no cr ZTZ reclassify has an exclusion 99038869 exclude 99038803 283567 
582	Missing	99038803 no es, no cr ZTZ same 283586 283204
594	Missing	99038803 no es, no cr ZTZ 283205
601	Missing	99038803 no es, no cr ZTZ 283593


---



    WITH r AS (
        select
             rc.receiptid 
            ,rc.harmonized_tariff_schedule_number::varchar AS harmonized_tariff_schedule_number
        FROM preftz.receipt_classifications rc
        --WHERE rc.receiptid = p_receiptid
    ),
    t AS (
        select
             tza.receiptid 
            ,unnest(tza.ztz_additional_tariffs)::varchar AS harmonized_tariff_schedule_number
        FROM preftz.tmp_EG_ztz_1 tza
        --WHERE tza.transfer_itemid = preftz.get_transfer_itemid_from_ztz_receiptid(p_receiptid)
        UNION ALL
        select
            tza.receiptid
            ,tza.ztz_base_tariffs::varchar AS harmonized_tariff_schedule_number
        FROM preftz.tmp_EG_ztz_1 tza
        --WHERE tza.transfer_itemid = preftz.get_transfer_itemid_from_ztz_receiptid(p_receiptid)
    )
    SELECT 
        t.receiptid ,
        r.harmonized_tariff_schedule_number AS receipt_hts,
        t.harmonized_tariff_schedule_number AS ztz_hts
    FROM r
    FULL JOIN t 
      on t.receiptid = r.receiptid  and 
      r.harmonized_tariff_schedule_number = t.harmonized_tariff_schedule_number 
    WHERE r.harmonized_tariff_schedule_number IS NULL
       OR t.harmonized_tariff_schedule_number IS NULL
    ORDER BY COALESCE(r.harmonized_tariff_schedule_number, t.harmonized_tariff_schedule_number);


    DROP FUNCTION preftz.check_ztz_hts;

CREATE OR REPLACE FUNCTION preftz.check_ztz_hts_2(p_receiptid int) 
RETURNS TABLE (
    receipt_hts varchar,
    ztz_hts varchar
)
LANGUAGE plpgsql 
AS $BODY$
BEGIN

    RETURN QUERY
    WITH r AS (
        select
        --     rc.receiptid 
--            ,
        rc.harmonized_tariff_schedule_number::varchar AS harmonized_tariff_schedule_number
        FROM preftz.receipt_classifications rc
        WHERE rc.receiptid = p_receiptid
    ),
    t AS (
        select
          --   tza.receiptid 
        --    ,
        unnest(tza.ztz_additional_tariffs)::varchar AS harmonized_tariff_schedule_number
        FROM preftz.tmp_EG_ztz_1 tza
        WHERE tza.receiptid = p_receiptid
        UNION ALL
        select
            --tza.receiptid
            --,
        tza.ztz_base_tariffs::varchar AS harmonized_tariff_schedule_number
        FROM preftz.tmp_EG_ztz_1 tza
        WHERE tza.receiptid = p_receiptid
    )
    SELECT 
        --t.receiptid ,
        r.harmonized_tariff_schedule_number AS receipt_hts,
        t.harmonized_tariff_schedule_number AS ztz_hts
    FROM r
    FULL JOIN t 
      --on t.receiptid = r.receiptid  and 
      on r.harmonized_tariff_schedule_number = t.harmonized_tariff_schedule_number 
    WHERE r.harmonized_tariff_schedule_number IS NULL
       OR t.harmonized_tariff_schedule_number IS NULL
    ORDER BY COALESCE(r.harmonized_tariff_schedule_number, t.harmonized_tariff_schedule_number);


END;
$BODY$;





;



select * from preftz.transfer_ztz_archive
where transfer_itemid in (
select * from preftz.get_transfer_itemid_from_ztz_receiptid(63675)
)
order by created_date desc;

2026-01-05
99038803



select * from preftz.receipt_classifications rc
where rc.receiptid  in  (63675)

select * from preftz.transfer_ztz_archive
where transfer_itemid in (
select * from preftz.get_transfer_itemid_from_ztz_receiptid(63852)
)
order by created_date desc;
