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

select preftz.classify_receipts_v2('26BWGA0080',null,null,true);


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

--this one will compare results
select 
t2.* 
from preftz.receipt_classifications_v2 t1
join preftz.compare_receipt_classifications_to_v2(t1.receiptid) t2
on t1.receiptid = t2.receiptid
--where t1.created_date > '2026-07-08'
--where t1.receiptid =281351 --chest
order by t2.receiptid,t2.harmonized_tariff_schedule_number, t2.field_name 

select count(*) from preftz.receipt_classifications_v2 t1;

--anatolia
--233

--chest 3549
--issues !!!!!! 
--281348, 281351 281350 

--georgia 853
--ok

select 
* 
--delete 
from preftz.receipt_classifications_v2 t1
order by created_date desc;

select * 
from preftz.receipt_classifications_v2 t1
where t1.receiptid  = 281348
order by created_date desc;

select * 
from preftz.receipt_classifications t1
where t1.receiptid  = 281348;

select r.privileged_date,r.receipt_date ,* 
from preftz.receipts r
where r.receiptid in (281348, 281351, 281350)

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
select preftz.generate_tmp_receipt_classification_data(null,null,278132); --c



select preftz.generate_tmp_receipt_classification_work();

select privileged_date,* from tmp_receipt_classification_data;
--31
select * from tmp_receipt_classification_work;

receiptid|created_date           |harmonized_tariff_schedule_number|special_programs_indicator|unit_value|tariff_type|distinct_tariff_line_indicator|primary_tariff|quantity1_rate|quantity2_rate|unit_duty_liability|
---------+-----------------------+---------------------------------+--------------------------+----------+-----------+------------------------------+--------------+--------------+--------------+-------------------+
   281348|2026-07-09 10:42:22.690|99038803                         |                          |       0.0|SECTION301 |                              |              |              |              |             3.6525|
   281348|2026-07-09 10:42:22.690|99038190                         |                          |  14.53695|SECTION232 |                              |              |     1.9858608|              |           7.268475|
   281348|2026-07-09 10:42:22.690|7315110005                       |                          |   0.07305|BASE       |                              |              |     0.0099792|              |                0.0|

select preftz.create_receipt_classifications('23BWGA0101');
select preftz.calculate_receipt_classifications();     


select preftz.create_receipt_classifications('26NB000266');
select preftz.classify_receipts_v2('26NB000266',null,null,true);

select preftz.create_receipt_classifications('26NB000136');
select preftz.calculate_receipt_classifications();     

select preftz.classify_receipts_v2('26NB000136',null,null,true);



select preftz.classify_receipts_v2(null,null,210455,true);
select preftz.classify_receipts_v2('26ANT00864',null,null,true);

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
where receiptid = 210455;
--31
select * from tmp_receipt_classification_work
where receiptid = 210455;
--77


select count(*) from preftz.part_bounds

select * from preftz.part_bounds

select * FROM preftz.derivative_parts_content
select * FROM preftz.receipt_derivative_content rdc;
select * from preftz.parts_extension; 
select * FROM preftz.receipt_percentage_value ;

select * FROM preftz.additional_cast_and_smelt_tariffs acst
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
    where receiptid in (281348)
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
  



-- Compare what we calculate as additional tariffs with what's actually in RC
with target_receipts as (
    -- change this CTE to return the sub-set of receipts you want to compare
    select receiptid from preftz.receipts 
    where receiptid in (59022)
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
        coalesce(r.privileged_date, r.receipt_date::date), p.special_programs_indicator,
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

