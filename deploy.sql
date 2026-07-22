-- preftz.receipt_classifications definition

-- Drop table

-- DROP TABLE preftz.receipt_classifications;

CREATE TABLE IF NOT EXISTS preftz.receipt_classifications_v2 (
	receiptid int4 NOT NULL,
	created_date timestamp DEFAULT now(),
	harmonized_tariff_schedule_number varchar(10) NOT NULL,
	special_programs_indicator varchar(2) NULL,
	unit_value float8 NULL,
	tariff_type varchar(15) NULL,
	distinct_tariff_line_indicator bpchar(1) NULL,
	primary_tariff bpchar(1) NULL,
	quantity1_rate float8 NULL,
	quantity2_rate float8 NULL,
	unit_duty_liability float8 NULL,
	CONSTRAINT receipt_classifications2_pkey PRIMARY KEY (receiptid, harmonized_tariff_schedule_number)
);
CREATE INDEX IF NOT EXISTS rc2_hts_number ON preftz.receipt_classifications_v2 USING btree (harmonized_tariff_schedule_number);
CREATE INDEX IF NOT EXISTS rc2_receipt_id ON preftz.receipt_classifications_v2 USING btree (receiptid);-- PROCEDURE: preftz.calculate_derivative_duty_liability_v2(integer)

-- PROCEDURE: preftz.calculate_derivative_duty_liability_v2(integer)

-- DROP PROCEDURE IF EXISTS preftz.calculate_derivative_duty_liability_v2(integer);

CREATE OR REPLACE PROCEDURE preftz.calculate_derivative_duty_liability_v2(
	IN p_receiptid integer)
LANGUAGE 'plpgsql'
AS $BODY$

--CHANGE LOG:
-- KK 02/26/2026 Put IEEPA tariffs back, until CBP has a chance to implement.
-- KK 02/24/2026 Remove IEEPA tariffs and implement new Section122 tariffs.
-- KK 12/03/2025 Do nothing if this receipt has no derivative tariffs
-- KK 10/02/2025 refactor to only calculate BASE percentage, based on the actual applied derivative tariffs.
-- KK 09/09/2025 change initial query to ensure we aren't applying derivative logic on a product where the stacking logic has
--               removed the derivative tariff. For example: An auto-part that is also a derivative - auto-part will take priority.
-- MH 9/8/2025 added coalesce false
-- KK 08/18/2025 non-metal content of an article is subject to Reciprocal tariffs under HTS 9903.01.25 (CSMS# 65236645 & 65236374)
-- KK 08/01/2025 Logic for SECTION232 Copper derivatives zone entry.
-- KK 04/23/2025 SECTION232 Steel and aluminum derivatives. Derivative percentage changes.
-- KK 04/17/2025 SECTION232 Steel and aluminum derivatives

DECLARE
    rs                      RECORD;
    v_computation_code      CHAR(1);
    v_rate_specific         DOUBLE PRECISION;
    v_rate_ad_valorem       DOUBLE PRECISION; 
    v_rate_other            DOUBLE PRECISION;
    v_duty_specific         DOUBLE PRECISION;
    v_duty_ad_valorem       DOUBLE PRECISION;
    v_duty_other            DOUBLE PRECISION;
    v_duty_1                DOUBLE PRECISION;
    v_duty_2                DOUBLE PRECISION;
    v_value                 DOUBLE PRECISION;
    v_derivative_tariffs    VARCHAR[];
    v_aluminum_percentage   NUMERIC;
    v_steel_percentage      NUMERIC;
    v_steel_cnt             INTEGER DEFAULT 0;
    v_aluminum_cnt          INTEGER DEFAULT 0;
    v_base_percentage       NUMERIC;
    v_base_unit_value       NUMERIC;
    v_copper_percentage     NUMERIC;
    v_copper_cnt            INTEGER DEFAULT 0;

BEGIN

    -- KK 12/03/2025 Do nothing if this receipt has no derivative tariffs
    IF NOT EXISTS (
        WITH derivatives AS (
            SELECT DISTINCT additional_tariff_number, tariff_type
            FROM preftz.additional_tariff_derivatives
        )
        SELECT 1
        FROM tmp_receipt_classification_work rc
        JOIN derivatives d ON d.additional_tariff_number = rc.harmonized_tariff_schedule_number
            AND d.tariff_type = rc.tariff_type
        WHERE rc.receiptid = p_receiptid
    )
    THEN
        -- Do nothing if there are no derivative additional tariffs
        RETURN;
    END IF;

    -- make sure we have derivatives and get percentages
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
        COALESCE(r.aluminum_percentage,1.0), COALESCE(r.steel_percentage,1.0), 
        COALESCE(r.copper_percentage,1.0), rc_base.unit_value
    INTO v_steel_cnt, v_aluminum_cnt, v_copper_cnt, v_aluminum_percentage, v_steel_percentage, v_copper_percentage, v_base_unit_value
    FROM 
    --preftz.receipts r
        (
        select t1.receiptid, t1.part_number,
        t1.aluminum_percentage, t1.steel_percentage, t1.copper_percentage
        from tmp_receipt_classification_data t1
        group by t1.receiptid, t1.part_number
        ,t1.aluminum_percentage, t1.steel_percentage, t1.copper_percentage
        ) r
    JOIN tmp_receipt_classification_work rc ON r.receiptid = rc.receiptid
    JOIN tmp_receipt_classification_work rc_base ON r.receiptid = rc_base.receiptid 
        AND rc_base.tariff_type = 'BASE'
    JOIN derivatives d ON d.additional_tariff_number = rc.harmonized_tariff_schedule_number
        AND d.tariff_type = rc.tariff_type
    
--    LEFT JOIN preftz.derivative_parts_content dpc ON dpc.part_number = r.part_number
--        AND r.receipt_date BETWEEN dpc.start_date AND dpc.end_date

    WHERE r.receiptid = p_receiptid
    GROUP BY r.aluminum_percentage, r.steel_percentage, r.copper_percentage, rc_base.unit_value;

    -- ONLY subtract those percentages that we have applied a tariff; Do not rely on what's in derivative_parts_content!
    v_base_percentage = 1.0;
    IF v_steel_cnt > 0 THEN 
        v_base_percentage = v_base_percentage - v_steel_percentage;
    END IF;
    IF v_aluminum_cnt > 0 THEN 
        v_base_percentage = v_base_percentage - v_aluminum_percentage;
    END IF;
    IF v_copper_cnt > 0 THEN 
        v_base_percentage = v_base_percentage - v_copper_percentage;
    END IF;

    -- TODO: Need hard-stop if percentage totals isn't between 0 - 100
    -- 
    -- loop and update all Derivative tariffs and BASE tariff
    IF v_steel_cnt + v_aluminum_cnt + v_copper_cnt > 0 THEN
        FOR rs IN
            WITH derivatives AS (
                SELECT DISTINCT additional_tariff_number, tariff_type, 
                    LEFT(LOWER(notes), 10) = 'iron_steel' AS is_steel_derivative,
                    LEFT(LOWER(notes), 9) = 'aluminum_' AS is_aluminum_derivative,
        			LEFT(LOWER(notes), 6) = 'copper' AS is_copper_derivative,
                    false AS is_non_content
                FROM preftz.additional_tariff_derivatives
                UNION ALL
                SELECT tt.additional_tariff_number, 'ADDITIONAL' AS tariff_type,
                    false AS is_steel_derivative,
                    false AS is_aluminum_derivative,
                    false AS is_copper_derivative,
                    true AS is_non_content
                FROM preftz.additional_tariff_tags tt
                WHERE tt.tag_name IN('section122', 'reciprocal')
            )
            SELECT rc.harmonized_tariff_schedule_number, rc.special_programs_indicator, 
                    rc.quantity1_rate quantity1, rc.quantity2_rate quantity2, rc.tariff_type, 
                    --COALESCE(r.privileged_date, r.receipt_date, current_date) classification_date,
                    r.receipt_date classification_date,
                    d.is_steel_derivative, d.is_aluminum_derivative, d.is_copper_derivative, COALESCE(d.is_non_content,false) as is_non_content -- MH 9/8/2025 added coalesce false
            FROM 
             (select t1.receiptid, t1.part_number, t1.privileged_date as receipt_date 
             from tmp_receipt_classification_data t1
             group by t1.receiptid, t1.part_number, t1.privileged_date
             ) r
            --preftz.receipts r
            JOIN tmp_receipt_classification_work rc ON r.receiptid = rc.receiptid
            LEFT JOIN derivatives d ON d.additional_tariff_number = rc.harmonized_tariff_schedule_number
            WHERE r.receiptid = p_receiptid
                AND (rc.tariff_type = 'BASE'
                    OR d.additional_tariff_number IS NOT NULL)  -- KK 09/09/2025
            ORDER BY CASE rc.tariff_type WHEN 'BASE' THEN 9 ELSE 0 END
        LOOP
            SELECT h.duty_computation_code, h.column_1_rate_specific, h.column_1_rate_ad_valorem,
                    h.column_1_rate_other
            INTO v_computation_code, v_rate_specific, v_rate_ad_valorem, v_rate_other
            FROM preftz.harmonized_tariff_schedule_reference h
            WHERE h.tariff_number = rs.harmonized_tariff_schedule_number
                AND COALESCE(h.special_programs_indicator,'') = COALESCE(rs.special_programs_indicator,'')
                AND h.record_begin_effective_date <= rs.classification_date
                AND h.record_end_effective_date >= rs.classification_date;

            IF rs.tariff_type <> 'BASE' THEN
                IF rs.is_steel_derivative = true THEN
                    v_value = ROUND((v_base_unit_value * v_steel_percentage)::NUMERIC, 10);
                ELSIF rs.is_aluminum_derivative = true THEN
                    v_value = ROUND((v_base_unit_value * v_aluminum_percentage)::NUMERIC, 10);
                ELSIF rs.is_copper_derivative = true AND rs.harmonized_tariff_schedule_number = '99037801' THEN
                    -- 99037801 copper content 
                    v_value = ROUND((v_base_unit_value * v_copper_percentage)::NUMERIC, 10);
                ELSIF rs.is_copper_derivative = true AND rs.harmonized_tariff_schedule_number = '99037802' THEN
                    -- 99037802 apply non-copper content here, instead of on BASE
                    v_value = ROUND((v_base_unit_value * v_base_percentage)::NUMERIC, 10);
                ELSIF rs.is_non_content = true THEN
                    -- non-metal content of an article reported on a separate line 
                    -- is subject to Reciprocal tariffs under HTS 9903.01.25
                    v_value = ROUND((v_base_unit_value * v_base_percentage)::NUMERIC, 10);
                    -- RAISE NOTICE 'base: %, unit_val: %, val: %', v_base_percentage, v_base_unit_value, v_value;
                END IF;
            ELSE
                -- This is BASE and we can assume it's the last.
                IF v_copper_cnt > 0 THEN
                    v_value = '0.0'::NUMERIC;
                ELSE
                    v_value = ROUND((v_base_unit_value * v_base_percentage)::NUMERIC, 10);
                END IF;
            END IF;

            CASE v_computation_code
            WHEN '0' THEN  --no duty
                v_duty_specific = 0;
                v_duty_ad_valorem = 0;
                v_duty_other = 0;

            WHEN '1' THEN  --Q1*specific
                v_duty_specific = rs.quantity1 * v_rate_specific;
                v_duty_ad_valorem = 0;
                v_duty_other = 0;

            WHEN '2' THEN  --Q2*specific
                v_duty_specific = rs.quantity2 * v_rate_specific;
                v_duty_ad_valorem = 0;
                v_duty_other = 0;

            WHEN '3' THEN  --Q1*specific + Q2*other
                v_duty_specific = rs.quantity1 * v_rate_specific;
                v_duty_ad_valorem = 0;
                v_duty_other = rs.quantity2 * v_rate_other;

            WHEN '4' THEN  --Q1*specific + advalorem
                v_duty_specific = rs.quantity1 * v_rate_specific;
                v_duty_ad_valorem = v_value * v_rate_ad_valorem;
                v_duty_other = 0;

            WHEN '5' THEN  --Q2*specific + advalorem
                v_duty_specific = rs.quantity2 * v_rate_specific;
                v_duty_ad_valorem = v_value * v_rate_ad_valorem;
                v_duty_other = 0;

            WHEN '6' THEN --Q1*specific + Q2*other + advalorem
                v_duty_specific = rs.quantity1 * v_rate_specific;
                v_duty_ad_valorem = v_value * v_rate_ad_valorem;
                v_duty_other = rs.quantity2 * v_rate_other;

            WHEN '7' THEN  --advalorem
                v_duty_specific = 0;
                v_duty_ad_valorem = v_value * v_rate_ad_valorem;
                v_duty_other = 0;

            WHEN '9' THEN  --sets
                v_duty_specific = 0;
                v_duty_ad_valorem = 0;
                v_duty_other = 0;

            WHEN 'K' THEN  --sugar
                v_duty_specific = 0;
                v_duty_ad_valorem = 0;
                v_duty_1 = rs.quantity1 * (v_rate_specific - (v_rate_ad_valorem * (100 - rs.quantity2)));
                v_duty_2 = rs.quantity1 * v_rate_other;
                IF v_duty_1 > v_duty_2 THEN
                    v_duty_other = v_duty_1;
                ELSE
                    v_duty_other = v_duty_2;
                END IF;
                
            WHEN 'X' THEN  --as per tariff schedule
                IF v_rate_specific = 0 AND v_rate_ad_valorem = 0 AND v_rate_other = 0 THEN
                    v_duty_specific = 0;
                    v_duty_ad_valorem = 0;
                    v_duty_other = 0;
                ELSE
                    --will need additional logic here to handle specific scenarios
                    --use the extreme given duty rates to raise awareness
                    v_duty_specific = rs.quantity1 * v_rate_specific;
                    v_duty_ad_valorem = v_value * v_rate_ad_valorem;
                    v_duty_other = 0;
                END IF;
            ELSE
            END CASE;
            -- RAISE NOTICE 'v_value: % , is_non_content: %', v_value, rs.is_non_content;
            UPDATE tmp_receipt_classification_work rc
            SET unit_duty_liability = v_duty_specific + v_duty_ad_valorem + v_duty_other,
                unit_value = CASE WHEN rs.is_non_content THEN 0 ELSE v_value END
            WHERE rc.receiptid = p_receiptid
                AND rc.harmonized_tariff_schedule_number = rs.harmonized_tariff_schedule_number;
             
        END LOOP;  -- Loop thru tmp_receipt_classification_work
    END IF; -- IF Derivatives
END; 
$BODY$;



CREATE OR REPLACE PROCEDURE preftz.calculate_derivative_quantity_v2 (p_receiptid INTEGER)
LANGUAGE plpgsql
AS $$

--CHANGE LOG:
-- KK 11/21/2025 fix Base quantity1 calculation
-- KK 08/20/2025 update quantity1_rate based on derivative percentage
DECLARE
    rs                      RECORD;
    v_derivative_tariffs    VARCHAR[];
    v_base_percentage       NUMERIC;
    v_qty1                  NUMERIC;
    v_base_qty1             NUMERIC;
    v_is_copper             BOOLEAN DEFAULT FALSE;

BEGIN
    IF EXISTS (
        WITH derivatives AS (
            SELECT DISTINCT additional_tariff_number, tariff_type
            FROM preftz.additional_tariff_derivatives
        )
        SELECT 1
        FROM tmp_receipt_classification_work rc
        JOIN derivatives d ON d.additional_tariff_number = rc.harmonized_tariff_schedule_number
            AND d.tariff_type = rc.tariff_type
        WHERE rc.receiptid = p_receiptid
    )
    THEN
        v_base_percentage = 1.0;
        FOR rs IN
            WITH derivatives AS (
                SELECT DISTINCT additional_tariff_number, tariff_type, 
                    LEFT(LOWER(notes), 10) = 'iron_steel' AS is_steel_derivative,
                    LEFT(LOWER(notes), 9) = 'aluminum_' AS is_aluminum_derivative,
                    LEFT(LOWER(notes), 6) = 'copper' AS is_copper_derivative,
                    false AS is_non_content
                FROM preftz.additional_tariff_derivatives
            )
            SELECT rc.harmonized_tariff_schedule_number, COALESCE(r.aluminum_percentage,1.0) AS aluminum_percentage, 
                    COALESCE(r.steel_percentage,1.0) AS steel_percentage, 
                    COALESCE(r.copper_percentage,1.0) AS copper_percentage, pc_base.quantity1_rate as base_qty1,
                    rc.tariff_type, d.is_steel_derivative, d.is_aluminum_derivative, d.is_copper_derivative
            FROM 
            --preftz.receipts r
              (
              select t1.receiptid, t1.part_number,
              t1.aluminum_percentage, t1.steel_percentage, t1.copper_percentage
              from tmp_receipt_classification_data t1
              group by t1.receiptid, t1.part_number
              ,t1.aluminum_percentage, t1.steel_percentage, t1.copper_percentage
              ) r

            JOIN tmp_receipt_classification_work rc ON r.receiptid = rc.receiptid

--            JOIN preftz.part_classifications pc_base ON r.part_number = pc_base.part_number AND pc_base.tariff_type = 'BASE'
            join tmp_receipt_classification_data pc_base
            ON r.receiptid = pc_base.receiptid AND pc_base.tariff_type = 'BASE'

            LEFT JOIN derivatives d ON d.additional_tariff_number = rc.harmonized_tariff_schedule_number
                AND d.tariff_type = rc.tariff_type
            
--            LEFT JOIN preftz.derivative_parts_content dpc ON dpc.part_number = r.part_number
--                AND r.receipt_date BETWEEN dpc.start_date AND dpc.end_date

            WHERE r.receiptid = p_receiptid
                AND (rc.tariff_type = 'BASE'
                    OR rc.harmonized_tariff_schedule_number = d.additional_tariff_number)
            ORDER BY CASE 
                WHEN rc.tariff_type = 'BASE' THEN 9 
                WHEN rc.harmonized_tariff_schedule_number = '99037802' THEN 5 -- KK copper hts for non-content instead of applying to BASE
                ELSE 0 END

/*
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
                    COALESCE(dpc.copper_percentage,1.0) AS copper_percentage, pc_base.quantity1_conversion_rate as base_qty1,
                    rc.tariff_type, d.is_steel_derivative, d.is_aluminum_derivative, d.is_copper_derivative
            FROM preftz.receipts r
            JOIN tmp_receipt_classification_work rc ON r.receiptid = rc.receiptid
            JOIN preftz.part_classifications pc_base ON r.part_number = pc_base.part_number 
                AND pc_base.tariff_type = 'BASE'
            LEFT JOIN derivatives d ON d.additional_tariff_number = rc.harmonized_tariff_schedule_number
                AND d.tariff_type = rc.tariff_type
            LEFT JOIN preftz.derivative_parts_content dpc ON dpc.part_number = r.part_number
                AND r.receipt_date BETWEEN dpc.start_date AND dpc.end_date
            WHERE r.receiptid = p_receiptid
                AND (rc.tariff_type = 'BASE'
                    OR rc.harmonized_tariff_schedule_number = d.additional_tariff_number)
            ORDER BY CASE 
                WHEN rc.tariff_type = 'BASE' THEN 9 
                WHEN rc.harmonized_tariff_schedule_number = '99037802' THEN 5 -- KK copper hts for non-content instead of applying to BASE
                ELSE 0 END
*/                
        LOOP
            IF rs.tariff_type <> 'BASE' THEN
                IF rs.is_steel_derivative = true THEN
                    v_base_percentage = v_base_percentage - rs.steel_percentage;
                    v_qty1 = rs.base_qty1 * rs.steel_percentage;
                ELSIF rs.is_aluminum_derivative = true THEN
                    v_base_percentage = v_base_percentage - rs.aluminum_percentage;
                    v_qty1 = rs.base_qty1 * rs.aluminum_percentage;
                ELSIF rs.is_copper_derivative = true AND rs.harmonized_tariff_schedule_number = '99037801' THEN
                    v_base_percentage = v_base_percentage - rs.copper_percentage;
                    -- 99037801 copper content 
                    v_qty1 = rs.base_qty1 * rs.copper_percentage;
                ELSIF rs.is_copper_derivative = true AND rs.harmonized_tariff_schedule_number = '99037802' THEN
                    -- 99037802 apply non-copper content here, instead of on BASE
                    v_is_copper = TRUE;
                    v_qty1 = rs.base_qty1 * v_base_percentage;
                END IF;
            ELSE
                IF v_is_copper = TRUE THEN
                    v_qty1 = '0.0'::NUMERIC;
                ELSE
                    v_qty1 = rs.base_qty1 * v_base_percentage;
                END IF;
            END IF;

            UPDATE tmp_receipt_classification_work rc
            SET quantity1_rate = v_qty1
            WHERE rc.receiptid = p_receiptid
                AND rc.harmonized_tariff_schedule_number = rs.harmonized_tariff_schedule_number;
        END LOOP;
    END IF;

END; 
$$;



CREATE OR REPLACE PROCEDURE preftz.calculate_duty_liability_v2 (p_receiptid INTEGER)
LANGUAGE plpgsql
AS $$

--CHANGE LOG:
-- KK 06/10/2026 CSMS # 68855869 - Calculate USMCA agreement rates as defined 99038220 and 99038221
-- KK 08/08/2025 Implement variable rate tariffs (minimum tariff) as defined by CSMS # 65807735 AnnexII.
--RTJ 01/21/2023 added unit_assist/dutiable fees
--RTJ 11/30/2022 allow OVERRIDE HTS to override all other duties associated with this receipt
--RTJ 09/05/2022 add duty computation code 9
--RTJ 07/26/2021 removed references to SCRAP (not applicable to receipt classifications)
--RTJ 07/12/2021 created to calculate duty liability for a specified receipt
--DOES NOT HANDLE duty computation codes A, B, C, D, E, F, J, and non-zero X

DECLARE
  rs                  RECORD;
  v_computation_code  CHAR(1);
  v_rate_specific     DOUBLE PRECISION;
  v_rate_ad_valorem   DOUBLE PRECISION; 
  v_rate_other        DOUBLE PRECISION;
  v_duty_specific     DOUBLE PRECISION;
  v_duty_ad_valorem   DOUBLE PRECISION;
  v_duty_other        DOUBLE PRECISION;
  v_duty_1            DOUBLE PRECISION;
  v_duty_2            DOUBLE PRECISION;
  v_value             DOUBLE PRECISION;
  v_base_total_rate   DOUBLE PRECISION DEFAULT 0;
  
BEGIN
    FOR rs IN
            SELECT rc.harmonized_tariff_schedule_number, rc.special_programs_indicator, 
                rc.quantity1_rate quantity1, rc.quantity2_rate quantity2, 
                rc.unit_value value_of_goods

                --, preftz.get_receipt_value(r.receiptid) line_value, --RTJ 01/21/2023
                ,r.receipt_value line_value,

                rc.tariff_type

                --, COALESCE(r.privileged_date, current_date) classification_date
                ,r.receipt_date classification_date

                ,rcbase.harmonized_tariff_schedule_number AS base_hts, tvr.minimum_rate,
                usv.usmca_value
            FROM --preftz.receipts r
             (select t1.receiptid, t1.receipt_value, t1.privileged_date as receipt_date 
             from tmp_receipt_classification_data t1
             group by t1.receiptid, t1.receipt_value, t1.privileged_date
             ) r
            INNER JOIN tmp_receipt_classification_work rc ON r.receiptid = rc.receiptid
            INNER JOIN tmp_receipt_classification_work rcbase ON r.receiptid = rcbase.receiptid
                AND rcbase.tariff_type = 'BASE'
            LEFT JOIN preftz.additional_tariff_variable_rates tvr 
                ON tvr.tariff_number = rc.harmonized_tariff_schedule_number

            -- LEFT JOIN (
            --     SELECT receiptid, '99038220' as tariff_number,  -- Non-us-value
            --         CASE WHEN percent_us_value >= 0.4 THEN 0.6::NUMERIC ELSE 1.0::NUMERIC - percent_us_value END AS usmca_value
            --     FROM preftz.receipt_percentage_value
            --     UNION
            --     SELECT receiptid, '99038221' as tariff_number,  -- US value
            --         CASE WHEN percent_us_value >= 0.4 THEN 0.4::NUMERIC ELSE percent_us_value::NUMERIC END AS usmca_value
            --     FROM preftz.receipt_percentage_value
            -- ) usv ON usv.receiptid = r.receiptid

            LEFT JOIN (
                SELECT receiptid, '99038220' as tariff_number,  -- Non-us-value
                    CASE WHEN percent_us_value >= 0.4 THEN 0.6::NUMERIC ELSE 1.0::NUMERIC - percent_us_value END AS usmca_value
                FROM 
                   (select
                   receiptid, percent_us_content percent_us_value
                   from tmp_receipt_classification_data
                   where percent_us_content is not null
                   group by receiptid, percent_us_content
                   ) t1
                UNION
                SELECT receiptid, '99038221' as tariff_number,  -- US value
                    CASE WHEN percent_us_value >= 0.4 THEN 0.4::NUMERIC ELSE percent_us_value::NUMERIC END AS usmca_value
                FROM 
                (select
                receiptid, percent_us_content percent_us_value
                from tmp_receipt_classification_data
                where percent_us_content is not null
                group by receiptid, percent_us_content
                ) t2
            ) usv ON usv.receiptid = r.receiptid
            
                AND usv.tariff_number = rc.harmonized_tariff_schedule_number   -- KK 06/10/2026 CSMS # 68855869
            WHERE r.receiptid = p_receiptid
            ORDER BY CASE rc.tariff_type WHEN 'BASE' THEN 0 WHEN 'OVERRIDE' THEN 9 WHEN 'MTB' THEN 9  --RTJ 11/30/2022
                ELSE 5 END
    LOOP
        SELECT h.duty_computation_code, h.column_1_rate_specific, h.column_1_rate_ad_valorem,
                h.column_1_rate_other
            INTO v_computation_code, v_rate_specific, v_rate_ad_valorem, v_rate_other
            FROM preftz.harmonized_tariff_schedule_reference h
        WHERE h.tariff_number = rs.harmonized_tariff_schedule_number
            AND COALESCE(h.special_programs_indicator,'') = COALESCE(rs.special_programs_indicator,'')
            AND h.record_begin_effective_date <= rs.classification_date
            AND h.record_end_effective_date >= rs.classification_date;
            
        -- KK 08/08/2025 variable rate tariffs 
        IF rs.minimum_rate IS NOT NULL THEN
            -- If we get here, then we have a HTS that has a variable rate.
            -- As of 2025-08-07 this only effects comp code 7 (v_rate_ad_valorem)
            IF v_base_total_rate < rs.minimum_rate THEN
                v_rate_ad_valorem = rs.minimum_rate - v_base_total_rate::NUMERIC;
                RAISE NOTICE 'variable rate adjusted for receipt: %; tariff: %; rate: %', p_receiptid, 
                    rs.harmonized_tariff_schedule_number, v_rate_ad_valorem;
            END IF;
        END IF;
            
        IF rs.tariff_type = 'BASE' THEN
            v_value = rs.value_of_goods;
            v_base_total_rate = v_rate_specific + v_rate_ad_valorem;
        ELSE
            v_value = rs.line_value;
        END IF;

        -- KK 06/10/2026 USMCA rates changes value that tariff is calculated on
        IF rs.usmca_value IS NOT NULL THEN
            v_value = ROUND((v_value * rs.usmca_value)::NUMERIC, 10);
        END IF;
        
        CASE v_computation_code
            WHEN '0' THEN  --no duty
                v_duty_specific = 0;
                v_duty_ad_valorem = 0;
                v_duty_other = 0;
    
            WHEN '1' THEN  --Q1*specific
                v_duty_specific = rs.quantity1 * v_rate_specific;
                v_duty_ad_valorem = 0;
                v_duty_other = 0;
    
            WHEN '2' THEN  --Q2*specific
                v_duty_specific = rs.quantity2 * v_rate_specific;
                v_duty_ad_valorem = 0;
                v_duty_other = 0;
    
            WHEN '3' THEN  --Q1*specific + Q2*other
                v_duty_specific = rs.quantity1 * v_rate_specific;
                v_duty_ad_valorem = 0;
                v_duty_other = rs.quantity2 * v_rate_other;
    
            WHEN '4' THEN  --Q1*specific + advalorem
                v_duty_specific = rs.quantity1 * v_rate_specific;
                v_duty_ad_valorem = v_value * v_rate_ad_valorem;
                v_duty_other = 0;
    
            WHEN '5' THEN  --Q2*specific + advalorem
                v_duty_specific = rs.quantity2 * v_rate_specific;
                v_duty_ad_valorem = v_value * v_rate_ad_valorem;
                v_duty_other = 0;
    
            WHEN '6' THEN --Q1*specific + Q2*other + advalorem
                v_duty_specific = rs.quantity1 * v_rate_specific;
                v_duty_ad_valorem = v_value * v_rate_ad_valorem;
                v_duty_other = rs.quantity2 * v_rate_other;
    
            WHEN '7' THEN  --advalorem
                v_duty_specific = 0;
                v_duty_ad_valorem = v_value * v_rate_ad_valorem;
                v_duty_other = 0;
    
            WHEN '9' THEN  --sets
                v_duty_specific = 0;
                v_duty_ad_valorem = 0;
                v_duty_other = 0;
    
            WHEN 'K' THEN  --sugar
                v_duty_specific = 0;
                v_duty_ad_valorem = 0;
                v_duty_1 = rs.quantity1 * (v_rate_specific - (v_rate_ad_valorem * (100 - rs.quantity2)));
                v_duty_2 = rs.quantity1 * v_rate_other;
                IF v_duty_1 > v_duty_2 THEN
                    v_duty_other = v_duty_1;
                ELSE
                    v_duty_other = v_duty_2;
                END IF;
                
            WHEN 'X' THEN  --as per tariff schedule
                IF v_rate_specific = 0 AND v_rate_ad_valorem = 0 AND v_rate_other = 0 THEN
                    v_duty_specific = 0;
                    v_duty_ad_valorem = 0;
                    v_duty_other = 0;
                ELSE
                    --will need additional logic here to handle specific scenarios
                    --use the extreme given duty rates to raise awareness
                    v_duty_specific = rs.quantity1 * v_rate_specific;
                    v_duty_ad_valorem = v_value * v_rate_ad_valorem;
                    v_duty_other = 0;
                END IF;
            ELSE
        END CASE;
    
        UPDATE tmp_receipt_classification_work rc
            SET unit_duty_liability = v_duty_specific + v_duty_ad_valorem + v_duty_other
        WHERE rc.receiptid = p_receiptid
            AND rc.harmonized_tariff_schedule_number = rs.harmonized_tariff_schedule_number;
                
        --set BASE rates to zero if using an overriding tariff type
        IF rs.tariff_type IN ('OVERRIDE','MTB') THEN
            UPDATE tmp_receipt_classification_work rc
                SET unit_duty_liability = 0
            WHERE rc.receiptid = p_receiptid
                AND rc.tariff_type NOT IN ('OVERRIDE','MTB');  --RTJ 11/30/2022
        END IF;
            
    END LOOP;    

END; 
$$;


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

        receipt_value                 DOUBLE PRECISION NULL,
        override_hts                  BOOLEAN NULL

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

-----------------------------------------------------------------------------------------------------------   

              FOR crs IN 
                 SELECT trc.receiptid, trc.part_number, trc.privileged_date
                 FROM tmp_receipt_classification_data trc
                 GROUP BY trc.receiptid, trc.part_number, trc.privileged_date
                 ORDER BY trc.receiptid, trc.part_number, trc.privileged_date
                 LOOP
                    v_privileged_date := crs.privileged_date;

                    v_301_exclusion := NULL;
                    v_232_exclusion := NULL;
                    v_chapter98_override := NULL;
                    v_used_for_production_or_repair := FALSE;
                    v_exclusion_tariffs := '{}'::VARCHAR(10)[];
                    
                    v_aluminum_percentage := NULL;
                    v_steel_percentage := NULL;
                    v_copper_percentage := NULL;
                    
                    v_unit_net_weight := NULL;
                    v_steel_content_weight := NULL;
                    v_aluminum_content_weight := NULL;
                    v_copper_content_weight := NULL;
                    
                    v_moto_exclusion := NULL;
                    v_is_usmca_special_treatment := FALSE;
                    v_is_agricultural_or_industrial := FALSE;
                    v_percent_us_content := NULL;
                    
                    v_receipt_value := NULL;                    

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
                    
                    
                    IF (v_add_hts_count > 0 AND p_classify_date IS NULL) --transfer archive has privileged date for this receipt
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
                     --AND date '2026-07-01' BETWEEN start_date AND end_date;
                     


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
    VALUES ('generate_tmp_receipt_classification_data', 'ended: ' || v_result, now());

    RETURN v_result;

EXCEPTION WHEN OTHERS THEN
    
    INSERT INTO preftz.system_log(procedure_name, log_message, details)
    VALUES ('generate_tmp_receipt_classification_data', 'ERROR: ' || SQLERRM, now());
    RAISE;
END;
$function$;

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
    VALUES ('classify_receipts_v2' , 'ended: '|| v_result, now());

    RETURN v_result;

EXCEPTION WHEN OTHERS THEN
    
    INSERT INTO preftz.system_log(procedure_name, log_message, details)
    VALUES ('classify_receipts_v2', 'ERROR: ' || SQLERRM, now());
    RAISE;
END;
$function$;

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
                ,trc.override_hts
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

                  IF (crs.override_hts IS NOT TRUE)-- USE this section if not using an old HTS
                  THEN 

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

                END IF; --IF (crs.override_hts IS NOT TRUE)-- USE this section if not using an old HTS
                  	
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




-- DROP FUNCTION IF EXISTS preftz.filter_additional_tariffs_by_priority;
DROP FUNCTION IF EXISTS preftz.filter_additional_tariffs_struc_v2;

CREATE OR REPLACE FUNCTION preftz.filter_additional_tariffs_struc_v2 (
    p_added_tariffs preftz.t_added_tariff[],
    p_base_tariff VARCHAR(10),
    p_date TIMESTAMP,
    p_special_programs_indicator CHAR(2),
    p_country VARCHAR(2)
)
RETURNS preftz.t_added_tariff[]
AS $$

--Change Log:
-- KK 06/19/2026 Do not allow two Section122 tariffs to be applied.
-- KK 04/06/2026 CSMS # 68253075 - GUIDANCE: Section 232 Duties on Imports of Aluminum, Steel, and Copper
-- KK 02/26/2026 Put IEEPA tariffs back, until CBP has a chance to implement.
-- KK 02/24/2026 Remove IEEPA tariffs and implement new Section122 tariffs.
-- KK 12/09/2025 Add logic to remove any reciprocal tariff if the reciprocal exclusion is applied, and not a derivative.
-- KK 11/11/2025 Refactor logic for applying additional tariffs and implement logic for recent CBP guidance.

-- This function replaces filter_additional_tariffs

DECLARE
    v_count                                INTEGER;
    v_position                             INTEGER;
    rs                                     RECORD;
    v_filtered_tariffs                     preftz.t_added_tariff[] DEFAULT '{}'::preftz.t_added_tariff[];
    v_prioritized_tariffs                  preftz.t_added_tariff[] DEFAULT '{}'::preftz.t_added_tariff[];
  
BEGIN
    IF p_added_tariffs IS NOT NULL AND CARDINALITY(p_added_tariffs) > 0 THEN
        v_filtered_tariffs = '{}'::preftz.t_added_tariff[] || p_added_tariffs;

        -- Variable Rates
        -- Remove variable rate tariff IF no exclusion and IF rate is greater than minimum KK 08/08/2025
        FOR rs IN 
            WITH ft AS (
                SELECT UNNEST(p_added_tariffs) AS s_tariff
            )
            SELECT DISTINCT tvr.tariff_number, ft.s_tariff
            FROM preftz.additional_tariff_variable_rates tvr
            JOIN ft ON (ft.s_tariff).tariff_number = tvr.tariff_number
            JOIN preftz.harmonized_tariff_schedule_reference h ON h.tariff_number = p_base_tariff
                AND COALESCE(h.special_programs_indicator,'') = COALESCE(p_special_programs_indicator,'')
                AND h.record_begin_effective_date <= p_date
                AND h.record_end_effective_date >= p_date
            WHERE COALESCE(tvr.exclusion_tariff, '') = ''  -- variable rate tariff should be removed if no exclusion
                AND (h.column_1_rate_specific + h.column_1_rate_ad_valorem) >= tvr.minimum_rate  -- base rate exceeds minimum
        LOOP
            RAISE NOTICE 'removing variable rate tariff: %', rs.tariff_number;
            v_filtered_tariffs = ARRAY_REMOVE(v_filtered_tariffs, rs.s_tariff);
        END LOOP;

        -- Replace variable rate tariff with it's exclusion IF rate is greater than minimum KK 08/08/2025
        FOR rs IN 
            WITH ft AS (
                SELECT UNNEST(p_added_tariffs) AS s_tariff
            )
            SELECT ft.s_tariff, tvr.exclusion_tariff, tvr.minimum_rate 
            FROM preftz.additional_tariff_variable_rates tvr
            JOIN ft ON (ft.s_tariff).tariff_number = tvr.tariff_number
            JOIN preftz.harmonized_tariff_schedule_reference h ON h.tariff_number = p_base_tariff
                AND COALESCE(h.special_programs_indicator,'') = COALESCE(p_special_programs_indicator,'')
                AND h.record_begin_effective_date <= p_date
                AND h.record_end_effective_date >= p_date
            WHERE COALESCE(tvr.exclusion_tariff, '') <> ''  -- variable tariff replaced with an exclusion tariff
                AND (h.column_1_rate_specific + h.column_1_rate_ad_valorem) >= tvr.minimum_rate  -- base rate exceeds minimum
        LOOP
            RAISE NOTICE 'swapping variable rate tariff % for %', (rs.s_tariff).tariff_number, rs.exclusion_tariff;
            v_filtered_tariffs = v_filtered_tariffs || (rs.exclusion_tariff, (rs.s_tariff).assigned_status, (rs.s_tariff).tariff_type)::preftz.t_added_tariff;
            v_filtered_tariffs = ARRAY_REMOVE(v_filtered_tariffs, rs.s_tariff);
        END LOOP;

        -- Stacking logic
        WITH additional_tariffs as (
            SELECT UNNEST(v_filtered_tariffs) as s_tariff
        ), added_tariff_priorities AS (
            SELECT wt.s_tariff, atp.priority
            FROM additional_tariffs wt
            LEFT JOIN preftz.additional_tariff_priority atp ON atp.tariff_number = (wt.s_tariff).tariff_number
                AND current_date BETWEEN atp.start_date AND atp.end_date
        ), highest_priority AS (
            SELECT MIN(priority) AS top_priority
            FROM added_tariff_priorities
        )
        SELECT ARRAY_AGG(atp.s_tariff)
        INTO v_prioritized_tariffs
        FROM added_tariff_priorities atp
        WHERE atp.priority = (SELECT top_priority FROM highest_priority)
            OR atp.priority IS NULL;  -- keep only those tariffs with highest priority or NULL priority


        v_filtered_tariffs = v_prioritized_tariffs;

        -- Add any Exclusions if applicable
        -- Note: this is where the Section122 exclusion 99030306 is applied based on the other tariffs at this point
        FOR rs IN 
            WITH additional_tariffs as (
                SELECT UNNEST(v_filtered_tariffs) as s_tariff
            )
            SELECT DISTINCT ex.tariff_number, ex.assigned_status, ex.tariff_type, adt.s_tariff
            FROM additional_tariffs adt
            JOIN preftz.additional_tariff_exclusions ex ON (adt.s_tariff).tariff_number = ANY(ex.exclusion_tariff_list)
                AND (ex.country_of_origin = p_country OR ex.country_of_origin = 'ALL')
                AND NOT p_country LIKE ANY(COALESCE(ex.exception_countries,'{}'::TEXT[]))
                AND p_date BETWEEN ex.start_date AND ex.end_date
        LOOP
            RAISE NOTICE 'adding exclusion tariff % for %', rs.tariff_number, (rs.s_tariff).tariff_number;
            v_filtered_tariffs = v_filtered_tariffs || (rs.tariff_number, rs.assigned_status, rs.tariff_type)::preftz.t_added_tariff;
        END LOOP;

        -- KK 02/24/2026 Remove IEEPA tariffs and implement new Section122 tariffs.
        -- If the section122 Exclusion has been added then remove any of the section122 tariff if this is not a derivative.
        IF EXISTS (
            WITH additional_tariffs as (
                SELECT UNNEST(v_filtered_tariffs) as s_tariff
            )
            SELECT 1 FROM additional_tariffs adt
            WHERE (adt.s_tariff).tariff_number IN (
                -- contains the section122 exclusion
                SELECT additional_tariff_number FROM preftz.additional_tariff_tags WHERE tag_name = 'section122_exclusion'
            )
            AND NOT EXISTS (
                -- not a derivative
                SELECT 1 FROM additional_tariffs adt
                WHERE (adt.s_tariff).tariff_number IN (
                    SELECT DISTINCT additional_tariff_number FROM preftz.additional_tariff_derivatives
                    WHERE p_date BETWEEN start_date AND end_date  -- KK 04/06/2026
                )
            )
        )
        THEN
            WITH additional_tariffs as (
                SELECT UNNEST(v_filtered_tariffs) as s_tariff
            )
            SELECT ARRAY_AGG(adt.s_tariff)
            INTO v_filtered_tariffs
            FROM additional_tariffs adt
            WHERE (adt.s_tariff).tariff_number NOT IN (
                SELECT additional_tariff_number FROM preftz.additional_tariff_tags WHERE tag_name = 'section122'
            );
        END IF;

        -- KK 02/26/2026 Put IEEPA tariffs back, until CBP has a chance to implement.
        IF EXISTS (
            WITH additional_tariffs as (
                SELECT UNNEST(v_filtered_tariffs) as s_tariff
            )
            SELECT 1 FROM additional_tariffs adt
            WHERE (adt.s_tariff).tariff_number IN (
                -- contains the reciprocal exclusion
                SELECT additional_tariff_number FROM preftz.additional_tariff_tags WHERE tag_name = 'reciprocal_exclusion'
            )
            AND NOT EXISTS (
                -- not a derivative
                SELECT 1 FROM additional_tariffs adt
                WHERE (adt.s_tariff).tariff_number IN (
                    SELECT DISTINCT additional_tariff_number FROM preftz.additional_tariff_derivatives
                )
            )
        )
        THEN
            WITH additional_tariffs as (
                SELECT UNNEST(v_filtered_tariffs) as s_tariff
            )
            SELECT ARRAY_AGG(adt.s_tariff)
            INTO v_filtered_tariffs
            FROM additional_tariffs adt
            WHERE (adt.s_tariff).tariff_number NOT IN (
                SELECT additional_tariff_number FROM preftz.additional_tariff_tags WHERE tag_name = 'reciprocal'
            );
        END IF;

		-- Do not allow multiple Section122 Exclusions
		IF (
			SELECT COUNT(a.tariff_number) > 1
			FROM UNNEST(v_filtered_tariffs) as a
			WHERE a.tariff_number IN(
				SELECT additional_tariff_number
				FROM preftz.additional_tariff_tags 
				WHERE tag_name = 'section122_exclusion'
			)
		) THEN
			RAISE NOTICE 'too many Section122 Exclusions, using only highest number.';
			WITH all_others AS (
				SELECT (a.tariff_number, a.assigned_status, a.tariff_type)::preftz.t_added_tariff as added_tariff
				FROM UNNEST(v_filtered_tariffs) as a
				WHERE a.tariff_number NOT IN(
					select additional_tariff_number
					FROM preftz.additional_tariff_tags 
					WHERE tag_name = 'section122_exclusion'
				)
			), section122_exclusions AS (
				SELECT (a.tariff_number, a.assigned_status, a.tariff_type)::preftz.t_added_tariff as added_tariff
				FROM UNNEST(v_filtered_tariffs) as a
				WHERE a.tariff_number IN(
					select additional_tariff_number
					FROM preftz.additional_tariff_tags 
					WHERE tag_name = 'section122_exclusion'
				)
				ORDER BY a.tariff_number DESC
				LIMIT 1
			), new_added_tariffs AS (
				SELECT added_tariff FROM section122_exclusions
				UNION
				SELECT added_tariff FROM all_others
			)
			SELECT ARRAY_AGG(added_tariff) FROM new_added_tariffs INTO v_filtered_tariffs;
		END IF;

        RAISE NOTICE 'after filter: %', v_filtered_tariffs;
    END IF;

    RETURN v_filtered_tariffs;
END; $$
LANGUAGE plpgsql;




-- DROP FUNCTION preftz.filter_section232_tariffs_struc_v2(preftz._t_added_tariff, varchar, int4, varchar, varchar, timestamp, bool, bool, bool, bool);

CREATE OR REPLACE FUNCTION preftz.filter_section232_tariffs_struc_v2(
    p_added_tariffs preftz.t_added_tariff[], 
    p_part_number character varying, 
    p_receiptid integer, 
    p_country character varying, 
    p_base_tariff character varying, 
    p_date timestamp without time zone, 
    p_steel_poured_in_us boolean DEFAULT false, 
    p_cast_smelt_in_us boolean DEFAULT false, 
    p_steel_poured_in_uk boolean DEFAULT false, 
    p_cast_smelt_in_uk boolean DEFAULT false)
RETURNS preftz.t_added_tariff[]
LANGUAGE plpgsql
AS $function$

--Change Log:
-- KK 06/10/2026 CSMS # 68855869 Further Adjusting the Tariff Regimes for Imports of Aluminum, Steel, and Copper
-- EG 06/08/2026 function get_section232_updated_count will check if these tarif needs to be processed in here 
-- KK 05/07/2026 CSMS # 68554727 Technical Corrections to Section 232 Duties on Imports of Aluminum, Steel, and Copper
-- KK 04/06/2026 CSMS # 68253075 - GUIDANCE: Section 232 Duties on Imports of Aluminum, Steel, and Copper
--
-- NOTES: 
-- Section122 exclusion is applied in another function via additional_tariff_exclusions
-- Most of these 232 tariffs are applied in get_added_tariffs_struc because they are in table additional_tariffs and applied 
    -- by those rules. The majority of this function logic is determining whether those tariffs should stay applied
    -- or be removed (based on additional rules).

DECLARE
    v_filtered_tariffs                     preftz.t_added_tariff[] DEFAULT '{}'::preftz.t_added_tariff[];
    v_more_tariffs                         preftz.t_added_tariff[] DEFAULT '{}'::preftz.t_added_tariff[];
    v_moto_exclusion                       VARCHAR DEFAULT NULL;
    rs                                     RECORD;
    v_metal_weight                         NUMERIC DEFAULT NULL;
    v_unit_net_weight                      NUMERIC DEFAULT NULL;
    v_steel_content_weight                 NUMERIC DEFAULT NULL;
    v_aluminum_content_weight              NUMERIC DEFAULT NULL;
    v_copper_content_weight                NUMERIC DEFAULT NULL;
    v_metal_content_percentage             NUMERIC DEFAULT NULL;
    v_percent_us_content                   NUMERIC DEFAULT NULL;

    v_is_usmca_special_treatment           BOOLEAN;
    v_is_agricultural_or_industrial        BOOLEAN;

  
BEGIN
    v_filtered_tariffs = '{}'::preftz.t_added_tariff[] || p_added_tariffs; -- EG 06/08/2026
    
IF p_added_tariffs IS NOT NULL AND CARDINALITY(p_added_tariffs) > 0 
    AND preftz.get_section232_updated_count(p_added_tariffs) > 0  -- EG 06/08/2026
THEN
        v_filtered_tariffs = '{}'::preftz.t_added_tariff[] || p_added_tariffs;

        -- Establish metal weight
        -- We have defined weights in receipt_derivative_content; if no row assume 100% no exclusion
        -- make sure we have non-null >0 unit_net_weight

        -- SELECT rdc.steel_content_weight, rdc.aluminum_content_weight, rdc.copper_content_weight, rdc.unit_net_weight
        -- INTO v_steel_content_weight, v_aluminum_content_weight, v_copper_content_weight, v_unit_net_weight
        -- FROM preftz.receipt_derivative_content rdc 
        -- WHERE rdc.receiptid = p_receiptid;

    SELECT steel_content_weight, aluminum_content_weight, copper_content_weight, unit_net_weight
    INTO v_steel_content_weight, v_aluminum_content_weight, v_copper_content_weight, v_unit_net_weight
    FROM tmp_receipt_classification_data
    WHERE receiptid = p_receiptid;



        -- Determine cumulative weight and percentage
        -- if we have valid unit_net_weight and we have a row in receipt_derivative_content we can proceed with calculation
        IF v_unit_net_weight IS NOT NULL AND v_unit_net_weight > 0 AND v_steel_content_weight IS NOT NULL THEN
            v_metal_weight = 0.0;
            FOR rs IN
                SELECT a.tag_name, 
                    CASE WHEN a.tag_name IN('steel','steel_derivative') THEN v_steel_content_weight ELSE
                        CASE WHEN a.tag_name IN('aluminum','aluminum_derivative') THEN v_aluminum_content_weight ELSE
                            CASE WHEN a.tag_name IN('copper') THEN v_copper_content_weight END 
                        END 
                    END AS weight
                FROM preftz.annex_iv_section232_metals a
                WHERE a.tariff_prefix = SUBSTR(p_base_tariff,1,LENGTH(a.tariff_prefix))
            LOOP
                -- Only sum the weight if the type of metal is indicated by Annex IV table
                v_metal_weight = v_metal_weight + rs.weight;
            END LOOP;
            
            v_metal_content_percentage = v_metal_weight / v_unit_net_weight;
            RAISE NOTICE 'cumulative_weight: %, unit_net_weight: %, percent: %', v_metal_weight, v_unit_net_weight, v_metal_content_percentage;
        ELSE
            -- either we don't have valid unit_net_weight or we don't have a row in receipt_derivative_content
            v_metal_weight = NULL;
            v_metal_content_percentage = 100.0; -- no exclusion for percentage
        END IF;

        -- KK 05/07/2026 If there is NO metal content, then remove all new Section232 and replace with 99038201
        IF v_metal_weight = 0.0 THEN
            -- remove ALL new Section232
            SELECT ARRAY(
                SELECT UNNEST(v_filtered_tariffs) 
                EXCEPT 
                SELECT ROW(tt.additional_tariff_number, 'P', 'SECTION232')::preftz.t_added_tariff AS section232_updates
                FROM preftz.additional_tariff_tags tt
                WHERE tt.tag_name LIKE 'section232_update%'
            ) AS res
            INTO v_filtered_tariffs;
            -- now add 99038201 exclusion
            v_filtered_tariffs = v_filtered_tariffs || '(99038201,P,SECTION232)'::preftz.t_added_tariff;
            RAISE NOTICE 'No metal content, replaced all section232_udpate with 99038201';
        END IF;

        -- If 99038203 is present, then see if we need to remove it or keep it based on metal percentage.
        IF '(99038203,P,SECTION232)'::preftz.t_added_tariff = ANY(v_filtered_tariffs) THEN
            IF v_metal_content_percentage < 0.15 THEN
                -- remove all other new section232_update tariffs
                RAISE NOTICE ' ---- Got an exclusion below 15 percent weight threshold! ---';
                -- remove all other of the new SECTION232 updated tariffs
                SELECT ARRAY(
                    SELECT UNNEST(v_filtered_tariffs) 
                    EXCEPT 
                    SELECT ROW(tt.additional_tariff_number, 'P', 'SECTION232')::preftz.t_added_tariff AS section232_updates
                    FROM preftz.additional_tariff_tags tt
                    WHERE tt.tag_name = 'section232_update'
                ) AS res
                INTO v_filtered_tariffs;
                -- remove the motorcycle exclusion as well, since we will assume this one takes precedence
                v_filtered_tariffs = ARRAY_REMOVE(v_filtered_tariffs, '(99038213,P,SECTION232)'::preftz.t_added_tariff);
            ELSE
                -- exceeds 15% so remove exclusion
                v_filtered_tariffs = ARRAY_REMOVE(v_filtered_tariffs, '(99038203,P,SECTION232)'::preftz.t_added_tariff);
            END IF;
        END IF;

        -- determine if motorcycle exclusion is present in the added tariffs and if it is claimed in parts_extension 9903.82.13
        IF '(99038213,P,SECTION232)'::preftz.t_added_tariff = ANY(v_filtered_tariffs) THEN
            -- see if claiming exclusion in parts_extension

            -- SELECT '99038213'::varchar AS moto_exclusion
            -- INTO v_moto_exclusion
            -- FROM preftz.parts_extension pe
            -- WHERE pe.part_number = p_part_number
            --     AND '99038213' = ANY(COALESCE(pe.chapter99_exclusion_tariffs, '{}'::VARCHAR[]));

            SELECT moto_exclusion
            INTO v_moto_exclusion
            FROM tmp_receipt_classification_data
            WHERE receiptid = p_receiptid;

            IF v_moto_exclusion IS NULL THEN
                -- remove the exclusion since they didn't claim it in parts_extension table
                v_filtered_tariffs = ARRAY_REMOVE(v_filtered_tariffs, '(99038213,P,SECTION232)'::preftz.t_added_tariff);
            ELSE
                RAISE NOTICE 'Using Motorcycle Exclusion 99038213';
                -- remove all other of the new SECTION232 updated tariffs
                SELECT ARRAY(
                    SELECT UNNEST(v_filtered_tariffs) 
                    EXCEPT 
                    SELECT ROW(tt.additional_tariff_number, 'P', 'SECTION232')::preftz.t_added_tariff AS section232_updates
                    FROM preftz.additional_tariff_tags tt
                    WHERE tt.tag_name = 'section232_update'
                ) AS res
                INTO v_filtered_tariffs;

            END IF;
        END IF;

        -- determine cast/smelt melt/pour in US 9903.82.06, 9903.82.07, and 9903.82.08 
        IF EXISTS (
            SELECT a.tariff_number
            FROM (SELECT (UNNEST(v_filtered_tariffs)).tariff_number) a
            WHERE a.tariff_number IN (
                SELECT tt.additional_tariff_number
                FROM preftz.additional_tariff_tags tt
                WHERE tt.tag_name = 'section232_cast_smelt_melt_pour_us'
            )
        )
        THEN
            -- RAISE NOTICE 'Found Section232 cast-smelt-melt-pour in US';
            IF NOT (p_cast_smelt_in_us OR p_steel_poured_in_us) THEN
                -- RAISE NOTICE 'Removing Section232 cast-smelt-melt-pour in US';
                SELECT ARRAY(
                        SELECT UNNEST(v_filtered_tariffs) 
                        EXCEPT 
                        SELECT ROW(tt.additional_tariff_number, 'P', 'SECTION232')::preftz.t_added_tariff AS section232_updates
                        FROM preftz.additional_tariff_tags tt
                        WHERE tt.tag_name = 'section232_cast_smelt_melt_pour_us'
                    ) AS res
                INTO v_filtered_tariffs;
            ELSE
                RAISE NOTICE 'Using Section232 cast-smelt-melt-pour in US';
                -- remove others
                SELECT ARRAY(
                        SELECT UNNEST(v_filtered_tariffs) 
                        EXCEPT 
                        SELECT ROW(tt.additional_tariff_number, 'P', 'SECTION232')::preftz.t_added_tariff AS section232_updates
                        FROM preftz.additional_tariff_tags tt
                        WHERE tt.tag_name = 'section232_update'
                            AND tt.additional_tariff_number NOT IN (
                                SELECT additional_tariff_number FROM preftz.additional_tariff_tags
                                WHERE tag_name = 'section232_cast_smelt_melt_pour_us'
                            )
                    ) AS res
                INTO v_filtered_tariffs;
            END IF;
        END IF;

        -- determine cast/smelt melt/pour in UK 9903.82.04 , 9903.82.05 
        IF EXISTS (
            SELECT a.tariff_number
            FROM (SELECT (UNNEST(v_filtered_tariffs)).tariff_number) a
            WHERE a.tariff_number IN (
                SELECT tt.additional_tariff_number
                FROM preftz.additional_tariff_tags tt
                WHERE tt.tag_name = 'section232_cast_smelt_melt_pour_gb'
            )
        )
        THEN
            -- RAISE NOTICE 'Found Section232 cast-smelt-melt-pour in GB';
            IF NOT (p_cast_smelt_in_uk OR p_steel_poured_in_uk) THEN
                -- RAISE NOTICE 'Removing Section232 cast-smelt-melt-pour in GB';
                SELECT ARRAY(
                        SELECT UNNEST(v_filtered_tariffs) 
                        EXCEPT 
                        SELECT ROW(tt.additional_tariff_number, 'P', 'SECTION232')::preftz.t_added_tariff AS section232_updates
                        FROM preftz.additional_tariff_tags tt
                        WHERE tt.tag_name = 'section232_cast_smelt_melt_pour_gb'
                    ) AS res
                INTO v_filtered_tariffs;
            ELSE
                RAISE NOTICE 'Using Section232 cast-smelt-melt-pour in GB';
                -- remove others
                SELECT ARRAY(
                        SELECT UNNEST(v_filtered_tariffs) 
                        EXCEPT 
                        SELECT ROW(tt.additional_tariff_number, 'P', 'SECTION232')::preftz.t_added_tariff AS section232_updates
                        FROM preftz.additional_tariff_tags tt
                        WHERE tt.tag_name = 'section232_update'
                            AND tt.additional_tariff_number NOT IN (
                                SELECT additional_tariff_number FROM preftz.additional_tariff_tags
                                WHERE tag_name = 'section232_cast_smelt_melt_pour_gb'
                            )
                    ) AS res
                INTO v_filtered_tariffs;
            END IF;
        END IF;

        -- KK 06/10/2026 CSMS # 68855869 - handle United States-Mexico-Canada Agreement (USMCA)
        -- 9903.82.20 and 9903.82.21
        -- Note: 9903.82.20 will already be in array if prefix and Coo match
            SELECT is_usmca_special_treatment
            INTO v_is_usmca_special_treatment
            FROM tmp_receipt_classification_data
            WHERE receiptid = p_receiptid;

        IF EXISTS ( 
            SELECT a.tariff_number
            FROM (SELECT (UNNEST(v_filtered_tariffs)).tariff_number) a
            WHERE a.tariff_number IN (
                SELECT tt.additional_tariff_number
                FROM preftz.additional_tariff_tags tt
                WHERE tt.tag_name = 'section232_update_usmca'
            )
        ) 
        -- AND is this product eligible for special tariff treatment under USMCA
        -- AND EXISTS (  
        --     SELECT part_number
        --     FROM preftz.parts_extension pe
        --     WHERE pe.part_number = p_part_number
        --         AND pe.is_usmca_special_treatment = true
        -- ) 
        AND v_is_usmca_special_treatment
        AND NOT EXISTS (  -- AND we DO NOT already have an exclusion
            SELECT a.tariff_number
            FROM (SELECT (UNNEST(v_filtered_tariffs)).tariff_number) a  -- does HTS prefix match
            WHERE a.tariff_number IN (
                SELECT tt.additional_tariff_number
                FROM preftz.additional_tariff_tags tt
                WHERE tt.tag_name = 'section232_update_exclusion'
            )
        )
        THEN
            -- get content
            -- SELECT COALESCE(percent_us_value, 0.0)
            -- INTO v_percent_us_content
            -- FROM preftz.receipt_percentage_value 
            -- WHERE receiptid = p_receiptid;

            SELECT percent_us_content
            INTO v_percent_us_content
            FROM tmp_receipt_classification_data
            WHERE receiptid = p_receiptid;

            IF v_percent_us_content > 0.0 THEN
                -- add 99038221 (US content)
                v_filtered_tariffs = v_filtered_tariffs || '(99038221,P,SECTION232)'::preftz.t_added_tariff;
                -- remove any other new Section232
                SELECT ARRAY(
                        SELECT UNNEST(v_filtered_tariffs) 
                        EXCEPT 
                        SELECT ROW(tt.additional_tariff_number, 'P', 'SECTION232')::preftz.t_added_tariff AS section232_updates
                        FROM preftz.additional_tariff_tags tt
                        WHERE tt.tag_name = 'section232_update'
                            AND tt.additional_tariff_number NOT IN (
                                SELECT additional_tariff_number FROM preftz.additional_tariff_tags
                                WHERE tag_name = 'section232_update_usmca'
                            )
                    ) AS res
                INTO v_filtered_tariffs;
            ELSE
                -- treat this as if not USMCA since we don't have any US content
                SELECT ARRAY(
                        SELECT UNNEST(v_filtered_tariffs) 
                        EXCEPT 
                        SELECT ROW(tt.additional_tariff_number, 'P', 'SECTION232')::preftz.t_added_tariff AS section232_updates
                        FROM preftz.additional_tariff_tags tt
                        WHERE tt.tag_name = 'section232_update_usmca'
                    ) AS res
                INTO v_filtered_tariffs;
            END IF;
        ELSE
            -- RAISE NOTICE 'Removing Section232 for USMCA';
            SELECT ARRAY(
                    SELECT UNNEST(v_filtered_tariffs) 
                    EXCEPT 
                    SELECT ROW(tt.additional_tariff_number, 'P', 'SECTION232')::preftz.t_added_tariff AS section232_updates
                    FROM preftz.additional_tariff_tags tt
                    WHERE tt.tag_name = 'section232_update_usmca'
                ) AS res
            INTO v_filtered_tariffs;
        END IF;


        -- KK 06/10/2026 CSMS # 68855869 - handle used for manufacturing of agricultural or industrial
        -- 9903.82.23, 9903.82.24 and 9903.82.25, 9903.82.26
        -- Note: 9903.82.23 might have been removed based on section232_cast_smelt_melt_pour_us

            SELECT is_agricultural_or_industrial
            INTO v_is_agricultural_or_industrial
            FROM tmp_receipt_classification_data
            WHERE receiptid = p_receiptid;

        IF EXISTS ( 
            SELECT a.tariff_number
            FROM (SELECT (UNNEST(v_filtered_tariffs)).tariff_number) a  -- does HTS prefix match
            WHERE a.tariff_number IN (
                SELECT tt.additional_tariff_number
                FROM preftz.additional_tariff_tags tt
                WHERE tt.tag_name IN('section232_update_ag','section232_update_ag_exclusion')
            )
        ) 
        -- AND is this product used exclusively for manufacturing agricultural equipment
        -- AND EXISTS (  
        --     SELECT part_number
        --     FROM preftz.parts_extension pe
        --     WHERE pe.part_number = p_part_number
        --         AND pe.is_agricultural_or_industrial = true
        -- ) 
        AND v_is_agricultural_or_industrial
        AND NOT EXISTS (  -- AND we DO NOT already have an exclusion
            SELECT a.tariff_number
            FROM (SELECT (UNNEST(v_filtered_tariffs)).tariff_number) a  -- does HTS prefix match
            WHERE a.tariff_number IN (
                SELECT tt.additional_tariff_number
                FROM preftz.additional_tariff_tags tt
                WHERE tt.tag_name = 'section232_update_exclusion'
            )
        )
        THEN
            RAISE NOTICE 'Using Section232 used for manufacturing of agricultural or industrial';
            -- remove others
            -- first if 99038223 is still in the list, remove 99038225 (because 99038223 for cast/smelt in US and applied above)
            IF '(99038223,P,SECTION232)'::preftz.t_added_tariff = ANY(v_filtered_tariffs) THEN
                v_filtered_tariffs = ARRAY_REMOVE(v_filtered_tariffs, '(99038225,P,SECTION232)'::preftz.t_added_tariff);
            END IF;
            -- remove any other new Section232
            SELECT ARRAY(
                    SELECT UNNEST(v_filtered_tariffs) 
                    EXCEPT 
                    SELECT ROW(tt.additional_tariff_number, 'P', 'SECTION232')::preftz.t_added_tariff AS section232_updates
                    FROM preftz.additional_tariff_tags tt
                    WHERE tt.tag_name = 'section232_update'
                        AND tt.additional_tariff_number NOT IN (
                            SELECT additional_tariff_number FROM preftz.additional_tariff_tags
                            WHERE tag_name IN('section232_update_ag','section232_update_ag_exclusion')
                        )
                ) AS res
            INTO v_filtered_tariffs;
        ELSE
            -- RAISE NOTICE 'Removing Section232 for manufacturing of agricultural use';
            SELECT ARRAY(
                    SELECT UNNEST(v_filtered_tariffs) 
                    EXCEPT 
                    SELECT ROW(tt.additional_tariff_number, 'P', 'SECTION232')::preftz.t_added_tariff AS section232_updates
                    FROM preftz.additional_tariff_tags tt
                    WHERE tt.tag_name IN('section232_update_ag','section232_update_ag_exclusion')
                ) AS res
            INTO v_filtered_tariffs;
        END IF;


        -- If using any of the section232 exclusions, add section122 since we are excluded from section232
        IF EXISTS (
            WITH added_tariffs AS (
                SELECT UNNEST(v_filtered_tariffs) AS added_tariff
            ), exclusions_232 AS (
                SELECT (att.additional_tariff_number, 'P', 'SECTION232')::preftz.t_added_tariff AS exclusion_tariff
                FROM preftz.additional_tariff_tags att
                WHERE tag_name = 'section232_update_exclusion'
            )
            SELECT 1
            FROM added_tariffs t
            JOIN exclusions_232 e ON e.exclusion_tariff = t.added_tariff
        )
        THEN
                -- NOTE: leaving out exclusion_tariff_prefixes because derivatives are in the excluded list
                SELECT ARRAY_AGG(DISTINCT ROW(a.additional_tariff_number, a.assigned_status, a.tariff_type)::preftz.t_added_tariff)
                INTO v_more_tariffs
                FROM preftz.additional_tariffs a
                JOIN preftz.additional_tariff_tags t ON t.additional_tariff_number = a.additional_tariff_number
                    AND t.tag_name = 'section122'   -- section122 tariffs only (should not include exclusion tariffs)
                WHERE a.tariff_prefix = SUBSTR(p_base_tariff,1,LENGTH(a.tariff_prefix))
                    AND (a.country_of_origin = p_country OR a.country_of_origin = 'ALL')
                    AND NOT p_country LIKE ANY(COALESCE(a.exception_countries,'{}'::TEXT[]))
                    AND a.start_date <= DATE_TRUNC('day',p_date)
                    AND a.end_date >= DATE_TRUNC('day',p_date);

                v_filtered_tariffs = v_filtered_tariffs || v_more_tariffs;
        END IF;

        RAISE NOTICE 'after filter_section232: %', v_filtered_tariffs;

    END IF;

    RETURN v_filtered_tariffs;
END; $function$
;



--DROP FUNCTION IF EXISTS preftz.get_added_derivative_tariffs_struc(varchar, integer, varchar, varchar, TIMESTAMP);
DROP FUNCTION IF EXISTS preftz.get_added_derivative_tariffs_struc_v2(varchar, integer, varchar, varchar, TIMESTAMP, BOOLEAN, BOOLEAN);

CREATE OR REPLACE FUNCTION preftz.get_added_derivative_tariffs_struc_v2 (
    p_part_number VARCHAR(50),
    p_receiptid INTEGER,
    p_country VARCHAR(2),
    p_base_tariff VARCHAR(10),
    p_date TIMESTAMP,
    p_steel_poured_in_us BOOLEAN DEFAULT FALSE,
    p_cast_smelt_in_us BOOLEAN DEFAULT FALSE
)
RETURNS preftz.t_added_tariff[]
AS $$

--Change Log:
-- KK 04/06/2026 CSMS # 68253075 - GUIDANCE: Section 232 Duties on Imports of Aluminum, Steel, and Copper
-- KK 02/26/2026 Put IEEPA tariffs back, until CBP has a chance to implement.
-- KK 02/24/2026 Remove IEEPA tariffs and implement new Section122 tariffs.
-- KK 01/14/2026 Default those parts with missing content percentages as 100% derivative.
-- KK 01/05/2026 Fix copper non-content when derivative is 100% copper (it should not get 99037802).
-- KK 11/11/2025 Refactor logic for applying additional tariffs and implement logic for recent CBP guidance.
-- 
-- This function replaces get_added_derivative_tariffs

DECLARE
    drs                           RECORD;
    v_aluminum_percentage         DOUBLE PRECISION;
    v_steel_percentage            DOUBLE PRECISION;
    v_copper_percentage           DOUBLE PRECISION;
    v_calculated_non_content      DOUBLE PRECISION;
    v_tariffs                     preftz.t_added_tariff[] DEFAULT '{}'::preftz.t_added_tariff[];
    v_is_derivative_hts           BOOLEAN DEFAULT false;
    v_missing_content_category    VARCHAR DEFAULT '';

BEGIN

    -- SELECT aluminum_percentage, steel_percentage, copper_percentage
    -- INTO v_aluminum_percentage, v_steel_percentage, v_copper_percentage
    -- FROM preftz.derivative_parts_content
    -- WHERE part_number = p_part_number
    --     AND p_date BETWEEN start_date AND end_date;

    SELECT aluminum_percentage, steel_percentage, copper_percentage
    INTO v_aluminum_percentage, v_steel_percentage, v_copper_percentage
    FROM tmp_receipt_classification_data
    WHERE receiptid = p_receiptid;


    -- Part is missing content percentages, so treat it as 100% derivative.
    IF v_aluminum_percentage IS NULL OR v_steel_percentage IS NULL OR v_copper_percentage IS NULL THEN
        SELECT LOWER(LEFT(a.notes,4)) AS category
        INTO v_missing_content_category
        FROM preftz.additional_tariff_derivatives a
        WHERE a.tariff_prefix = SUBSTR(p_base_tariff,1,LENGTH(a.tariff_prefix))
            AND NOT p_base_tariff LIKE ANY(COALESCE(a.exception_tariff_prefixes,'{}'::TEXT[]))
            AND (a.country_of_origin = p_country OR a.country_of_origin = 'ALL')
            AND NOT p_country LIKE ANY(COALESCE(a.exception_countries,'{}'::TEXT[]))
            AND p_date BETWEEN a.start_date AND a.end_date
            AND a.steel_poured_in_us = p_steel_poured_in_us
            AND a.cast_and_smelt_in_us = p_cast_smelt_in_us
        LIMIT 1;
        IF v_missing_content_category = 'alum' THEN
            v_aluminum_percentage = 1.0;
            v_steel_percentage = 0.0;
            v_copper_percentage = 0.0;
        ELSIF v_missing_content_category = 'iron' THEN
            v_aluminum_percentage = 0.0;
            v_steel_percentage = 1.0;
            v_copper_percentage = 0.0;
        ELSIF v_missing_content_category = 'copp' THEN
            v_aluminum_percentage = 0.0;
            v_steel_percentage = 0.0;
            v_copper_percentage = 1.0;
        END IF;
    END IF;

    v_calculated_non_content = 1.0;

    FOR drs IN
        SELECT a.additional_tariff_number, a.assigned_status, a.tariff_type, LOWER(LEFT(a.notes,4)) AS category
        FROM preftz.additional_tariff_derivatives a
        WHERE a.tariff_prefix = SUBSTR(p_base_tariff,1,LENGTH(a.tariff_prefix))
            AND NOT p_base_tariff LIKE ANY(COALESCE(a.exception_tariff_prefixes,'{}'::TEXT[]))
            AND (a.country_of_origin = p_country OR a.country_of_origin = 'ALL')
            AND NOT p_country LIKE ANY(COALESCE(a.exception_countries,'{}'::TEXT[]))
            AND p_date BETWEEN a.start_date AND a.end_date
            AND a.steel_poured_in_us = p_steel_poured_in_us
            AND a.cast_and_smelt_in_us = p_cast_smelt_in_us
    LOOP
        v_is_derivative_hts = true;
        RAISE NOTICE '%, steel %, alum %, copp %', p_part_number, v_steel_percentage, v_aluminum_percentage, v_copper_percentage;
        RAISE NOTICE 'derivative: %, %', drs.additional_tariff_number, drs.category;

        IF drs.category = 'iron' AND v_steel_percentage > 0 THEN
            v_tariffs = v_tariffs || (drs.additional_tariff_number, drs.assigned_status, drs.tariff_type)::preftz.t_added_tariff;
            v_calculated_non_content = v_calculated_non_content - v_steel_percentage;
        
        ELSIF drs.category = 'alum' AND v_aluminum_percentage > 0 THEN
            v_tariffs = v_tariffs || (drs.additional_tariff_number, drs.assigned_status, drs.tariff_type)::preftz.t_added_tariff;
            v_calculated_non_content = v_calculated_non_content - v_aluminum_percentage;

        ELSIF drs.category = 'copp' THEN  -- copper
            -- We will get a match for both 99037801 and 99037802 from derivatives table
            IF v_copper_percentage > 0 AND drs.additional_tariff_number = '99037801' THEN
                -- only apply 99037801 if v_copper_percentage > 0%
                v_tariffs = v_tariffs || (drs.additional_tariff_number, drs.assigned_status, drs.tariff_type)::preftz.t_added_tariff;
                v_calculated_non_content = v_calculated_non_content - v_copper_percentage;
            ELSIF v_copper_percentage < 1 AND drs.additional_tariff_number = '99037802' THEN
                -- always apply 99037802 representing non-copper content
                v_tariffs = v_tariffs || (drs.additional_tariff_number, drs.assigned_status, drs.tariff_type)::preftz.t_added_tariff;
            END IF;
        
        ELSIF drs.category NOT IN('iron','alum','copp') THEN
            -- Unexpected derivative category (any new derivative category needs logic implemented here)
            -- RAISE NOTICE 'WARNING unexpected derivative category: %; ', drs.category;
            RAISE EXCEPTION USING ERRCODE = 'PF003', MESSAGE = 'Unexpected derivative category: ' || drs.category || '. Unable to add derivative tariff.';
        END IF;
    END LOOP;

    -- If no tariffs found but either melt/pour or cast/smelt in US - then derivative didn't qualify for US exclusion tariff.
    -- Note: aluminum cast/smelt in US doesn't apply to all potential derivatives
    IF CARDINALITY(v_tariffs) = 0 AND (p_steel_poured_in_us = true OR p_cast_smelt_in_us = true) THEN
        RAISE NOTICE 'poured and/or cast in US';
        FOR drs IN
            SELECT a.additional_tariff_number, a.assigned_status, a.tariff_type
            FROM preftz.additional_tariff_derivatives a
            WHERE a.tariff_prefix = SUBSTR(p_base_tariff,1,LENGTH(a.tariff_prefix))
                AND NOT p_base_tariff LIKE ANY(COALESCE(a.exception_tariff_prefixes,'{}'::TEXT[]))
                AND (a.country_of_origin = p_country OR a.country_of_origin = 'ALL')
                AND NOT p_country LIKE ANY(COALESCE(a.exception_countries,'{}'::TEXT[]))
                AND p_date BETWEEN a.start_date AND a.end_date
                AND a.steel_poured_in_us = false
                AND a.cast_and_smelt_in_us = false
        LOOP
            v_is_derivative_hts = true;
            v_tariffs = v_tariffs || (drs.additional_tariff_number, drs.assigned_status, drs.tariff_type)::preftz.t_added_tariff;
        END LOOP;
    END IF;

    -- If we are treating this as a derivative and there is non-metal content then it may be subject to section122 tariff
    IF v_is_derivative_hts AND preftz.isrelgt0(v_calculated_non_content, NULL, NULL) THEN
        -- NOTE: leaving out exclusion_tariff_prefixes because derivatives are in the excluded list
        FOR drs IN
            SELECT DISTINCT a.additional_tariff_number, a.assigned_status, a.tariff_type
            FROM preftz.additional_tariffs a
            JOIN preftz.additional_tariff_tags t ON t.additional_tariff_number = a.additional_tariff_number
                AND t.tag_name = 'section122'   -- section122 tariffs only (should not include exclusion tariffs)
            WHERE a.tariff_prefix = SUBSTR(p_base_tariff,1,LENGTH(a.tariff_prefix))
                AND (a.country_of_origin = p_country OR a.country_of_origin = 'ALL')
                AND NOT p_country LIKE ANY(COALESCE(a.exception_countries,'{}'::TEXT[]))
                AND a.start_date <= DATE_TRUNC('day',p_date)
                AND a.end_date >= DATE_TRUNC('day',p_date)
        LOOP
            RAISE NOTICE 'derivative non-metal content subject to %; non-content: %', drs.additional_tariff_number, v_calculated_non_content;
            v_tariffs = v_tariffs || (drs.additional_tariff_number, drs.assigned_status, drs.tariff_type)::preftz.t_added_tariff;
        END LOOP;
    END IF;

    -- KK 02/26/2026 Put IEEPA tariffs back, until CBP has a chance to implement.
    -- If we are treating this as a derivative and there is non-metal content then it may be subject to reciprocal tariff
    IF v_is_derivative_hts AND preftz.isrelgt0(v_calculated_non_content, NULL, NULL) THEN
        -- NOTE: leaving out exclusion_tariff_prefixes because derivatives are in the excluded list
        FOR drs IN
            SELECT DISTINCT a.additional_tariff_number, a.assigned_status, a.tariff_type
            FROM preftz.additional_tariffs a
            JOIN preftz.additional_tariff_tags t ON t.additional_tariff_number = a.additional_tariff_number
                AND t.tag_name = 'reciprocal'   -- Reciprocal tariffs only (should not include exclusion tariffs)
            WHERE a.tariff_prefix = SUBSTR(p_base_tariff,1,LENGTH(a.tariff_prefix))
                AND (a.country_of_origin = p_country OR a.country_of_origin = 'ALL')
                AND NOT p_country LIKE ANY(COALESCE(a.exception_countries,'{}'::TEXT[]))
                AND a.start_date <= DATE_TRUNC('day',p_date)
                AND a.end_date >= DATE_TRUNC('day',p_date)
        LOOP
            RAISE NOTICE 'derivative non-metal content subject to %; non-content: %', drs.additional_tariff_number, v_calculated_non_content;
            v_tariffs = v_tariffs || (drs.additional_tariff_number, drs.assigned_status, drs.tariff_type)::preftz.t_added_tariff;
        END LOOP;
    END IF;

    IF CARDINALITY(v_tariffs) = 0 AND v_is_derivative_hts THEN 
        RAISE NOTICE 'Derivative HTS being treated as if it were not a derivative because of defined percentages.';
    END IF;

    RAISE NOTICE 'after get_added_derivative_tariffs_struc: %', v_tariffs;

    RETURN v_tariffs;
END; $$
LANGUAGE plpgsql;


DROP FUNCTION IF EXISTS preftz.get_added_tariffs_struc_v2;

CREATE OR REPLACE FUNCTION preftz.get_added_tariffs_struc_v2 (
    p_part_number VARCHAR(50), 
    p_country VARCHAR(2), 
    p_base_tariff VARCHAR(10),
    p_date DATE
)
RETURNS preftz.t_added_tariff[]
AS $$

--Change Log:
-- KK 02/26/2026 Put IEEPA tariffs back, until CBP has a chance to implement.
-- KK 02/24/2026 Remove IEEPA tariffs and implement new Section122 tariffs.
-- KK 01/14/2026 Only add the reciprocal to those that have exclusions for ALL Section232 tariffs.
-- KK 01/05/2026 change Raise Notice.
-- KK 11/11/2025 Refactor logic for applying additional tariffs and implement logic for recent CBP guidance.
-- 
-- This function replaces get_added_tariffs

DECLARE
    v_301_exclusion              VARCHAR(10);
    v_232_exclusion              VARCHAR(10);
    trs                          RECORD;
    v_tariffs                    preftz.t_added_tariff[] DEFAULT '{}'::preftz.t_added_tariff[];
    v_chapter98_override         VARCHAR(10);
    v_used_for_production_or_repair  BOOLEAN DEFAULT FALSE;
    v_exclusion_tariffs           VARCHAR(10)[] DEFAULT '{}'::VARCHAR(10)[];
    v_all_232_excluded           BOOLEAN DEFAULT FALSE;
  
BEGIN

/*
    SELECT p.section_232_exclusion_number, pc301.harmonized_tariff_schedule_number, 
        pc98.harmonized_tariff_schedule_number, COALESCE(pe.used_for_production_or_repair,false),
        COALESCE(pe.chapter99_exclusion_tariffs, '{}'::VARCHAR[])
    INTO v_232_exclusion, v_301_exclusion, v_chapter98_override, v_used_for_production_or_repair, v_exlusion_tariffs
    FROM preftz.parts p
    LEFT JOIN preftz.part_classifications pc301 ON pc301.part_number = p.part_number
        AND pc301.tariff_type = 'EXCLUSION301'
    LEFT JOIN preftz.part_classifications pc98 ON pc98.part_number = p.part_number
        AND pc98.tariff_type = 'OVERRIDE'
    LEFT JOIN preftz.parts_extension pe ON pe.part_number = p.part_number
    WHERE p.part_number = p_part_number;
*/    

         SELECT v232_exclusion, v301_exclusion, chapter98_override, used_for_production_or_repair, exclusion_tariffs
         INTO v_232_exclusion, v_301_exclusion, v_chapter98_override, v_used_for_production_or_repair, v_exclusion_tariffs
            FROM tmp_receipt_classification_data trcd
            WHERE trcd.part_number = p_part_number
         GROUP BY v232_exclusion, v301_exclusion, chapter98_override, used_for_production_or_repair, exclusion_tariffs;

    FOR trs IN (
        SELECT a.additional_tariff_number, a.assigned_status, a.tariff_type
        FROM preftz.additional_tariffs a
        WHERE a.tariff_prefix = SUBSTR(p_base_tariff,1,LENGTH(a.tariff_prefix))
            AND NOT p_base_tariff LIKE ANY(COALESCE(a.exception_tariff_prefixes,'{}'::TEXT[]))
            AND (a.country_of_origin = p_country OR a.country_of_origin = 'ALL')
            AND NOT p_country LIKE ANY(COALESCE(a.exception_countries,'{}'::TEXT[]))
            AND a.start_date <= DATE_TRUNC('day',p_date)
            AND a.end_date >= DATE_TRUNC('day',p_date)
            AND a.used_for_production_or_repair = v_used_for_production_or_repair
    )
    LOOP
        IF trs.tariff_type = 'SECTION232' THEN
            IF COALESCE(v_232_exclusion,'') = '' THEN
                v_tariffs = v_tariffs || (trs.additional_tariff_number, trs.assigned_status, trs.tariff_type)::preftz.t_added_tariff;
            ELSE
                RAISE NOTICE '232 Exclusion: %, excluded %', v_232_exclusion, trs.additional_tariff_number;
            END IF;
        ELSIF trs.tariff_type = 'SECTION301' THEN
            IF COALESCE(v_301_exclusion,'') = '' THEN
                v_tariffs = v_tariffs || (trs.additional_tariff_number, trs.assigned_status, trs.tariff_type)::preftz.t_added_tariff;
            ELSE
                RAISE NOTICE '301 Exclusion: %, excluded %', v_301_exclusion, trs.additional_tariff_number;
            END IF;
        ELSIF trs.tariff_type = 'ADDITIONAL' THEN
            -- This effectively DISABLES adding 99030133 from additional_tariffs table.
            -- We could remove 99030133 from additional_tariffs, but will keep for now until this logic get's deployed everywhere.
            IF trs.additional_tariff_number NOT IN('99030133') THEN
                v_tariffs = v_tariffs || (trs.additional_tariff_number, trs.assigned_status, trs.tariff_type)::preftz.t_added_tariff;    
            END IF;
        ELSE
            v_tariffs = v_tariffs || (trs.additional_tariff_number, trs.assigned_status, trs.tariff_type)::preftz.t_added_tariff;
        END IF;
    END LOOP;

    -- Replace any tariffs with their exclusion tariff if necessary (preftz.additional_tariff_replacements)
    IF CARDINALITY(v_exclusion_tariffs) > 0 THEN
        FOR trs IN
            WITH added AS (
                SELECT UNNEST(v_tariffs) AS tariff_struc
            ), replacements AS (
                SELECT atr.tariff_number, atr.assigned_status, atr.tariff_type, 
                    UNNEST(atr.replaceable_tariffs) as tariff_to_replace
                FROM preftz.additional_tariff_replacements atr
                WHERE atr.tariff_number = ANY(v_exclusion_tariffs)
                    AND p_date BETWEEN atr.start_date AND atr.end_date
            )
            SELECT r.tariff_number, r.assigned_status, r.tariff_type, a.tariff_struc
            FROM replacements r
            JOIN added a ON (a.tariff_struc).tariff_number = tariff_to_replace
        LOOP
            v_tariffs = ARRAY_REPLACE(v_tariffs, trs.tariff_struc, 
            (trs.tariff_number, trs.assigned_status, trs.tariff_type)::preftz.t_added_tariff);
            RAISE NOTICE 'replaced % with %', (trs.tariff_struc).tariff_number, trs.tariff_number;
        END LOOP;
    END IF;

    -- If using replacement tariff exclusions, then check if all SECTION232 are excluded.
    IF CARDINALITY(v_exclusion_tariffs) > 0 THEN
        SELECT NOT EXISTS (
            WITH added AS (
                SELECT UNNEST(v_tariffs) AS tariff_struc
            )
            SELECT 1 FROM added a
            WHERE (a.tariff_struc).tariff_number NOT IN (
                SELECT DISTINCT tariff_number FROM preftz.additional_tariff_replacements
            )
            AND (a.tariff_struc).tariff_type = 'SECTION232'
        )
        INTO v_all_232_excluded;
    END IF;

    -- If using a SECTION232 Exclusion or replacing with exclusion tariff, then make sure section122 tariff is applied
    IF COALESCE(v_232_exclusion,'') <> '' OR v_all_232_excluded THEN
        -- NOTE: leaving out column exception_tariff_prefixes from the WHERE clause, otherwise SECTION232 would be excluded
        FOR trs IN
            SELECT a.additional_tariff_number, a.assigned_status, a.tariff_type
            FROM preftz.additional_tariffs a
            JOIN preftz.additional_tariff_tags t ON t.additional_tariff_number = a.additional_tariff_number
                AND t.tag_name = 'section122'   -- section122 tariffs only (should not include exclusion tariffs)
            WHERE a.tariff_prefix = SUBSTR(p_base_tariff,1,LENGTH(a.tariff_prefix))
                AND (a.country_of_origin = p_country OR a.country_of_origin = 'ALL')
                AND NOT p_country LIKE ANY(COALESCE(a.exception_countries,'{}'::TEXT[]))
                AND a.start_date <= DATE_TRUNC('day',p_date)
                AND a.end_date >= DATE_TRUNC('day',p_date)
        LOOP
            RAISE NOTICE 'add section122 % because of Section232 Exclusion % or Exclusion tariffs %', 
                trs.additional_tariff_number, v_232_exclusion, v_exclusion_tariffs;
            v_tariffs = v_tariffs || (trs.additional_tariff_number, trs.assigned_status, trs.tariff_type)::preftz.t_added_tariff;
        END LOOP;
    END IF;

    -- KK 02/26/2026 Put IEEPA tariffs back, until CBP has a chance to implement.
    -- If using a SECTION232 Exclusion or replacing with exclusion tariff, then make sure reciprocal tariff is applied
    IF COALESCE(v_232_exclusion,'') <> '' OR v_all_232_excluded THEN
        -- NOTE: leaving out column exception_tariff_prefixes from the WHERE clause, otherwise SECTION232 would be excluded
        FOR trs IN
            SELECT a.additional_tariff_number, a.assigned_status, a.tariff_type
            FROM preftz.additional_tariffs a
            JOIN preftz.additional_tariff_tags t ON t.additional_tariff_number = a.additional_tariff_number
                AND t.tag_name = 'reciprocal'   -- Reciprocal tariffs only (should not include exclusion tariffs)
            WHERE a.tariff_prefix = SUBSTR(p_base_tariff,1,LENGTH(a.tariff_prefix))
                AND (a.country_of_origin = p_country OR a.country_of_origin = 'ALL')
                AND NOT p_country LIKE ANY(COALESCE(a.exception_countries,'{}'::TEXT[]))
                AND a.start_date <= DATE_TRUNC('day',p_date)
                AND a.end_date >= DATE_TRUNC('day',p_date)
        LOOP
            RAISE NOTICE 'add reciprocal % because of Section232 Exclusion % or Exclusion tariffs %', 
                trs.additional_tariff_number, v_232_exclusion, v_exclusion_tariffs;
            v_tariffs = v_tariffs || (trs.additional_tariff_number, trs.assigned_status, trs.tariff_type)::preftz.t_added_tariff;
        END LOOP;
    END IF;
    
    -- Remove any duplicates
    SELECT ARRAY_AGG(DISTINCT tariff_struc) INTO v_tariffs FROM (SELECT UNNEST(v_tariffs) AS tariff_struc) a;
    RAISE NOTICE 'after get_added_tariffs_struc: %', v_tariffs;

    RETURN v_tariffs;

END; $$
LANGUAGE plpgsql;


DROP FUNCTION IF EXISTS preftz.get_all_additional_tariffs_string_v2;

CREATE OR REPLACE FUNCTION  preftz.get_all_additional_tariffs_string_v2 (
    p_part_number VARCHAR(50),
    p_receiptid INTEGER,
    p_base_tariff VARCHAR(10), 
    p_country VARCHAR(2), 
    p_date DATE DEFAULT CURRENT_DATE,
    p_special_programs_indicator CHAR(2) DEFAULT '  ',
    p_country_of_cast VARCHAR(3) DEFAULT NULL,
    p_primary_country_of_smelt VARCHAR(3) DEFAULT NULL,
    p_secondary_country_of_smelt VARCHAR(3) DEFAULT NULL
)
RETURNS VARCHAR
AS $$

--CHANGE LOG:
-- KK 11/11/2025 Refactor logic for applying additional tariffs and implement logic for recent CBP guidance.
--
-- This function conbines functions: get_added_tariffs, 
--    cast & smelt tariffs (classify_receipts), get_added_derivative_tariffs, filter_additional_tariffs
--
-- It returns additional tariffs in legacy VARCHAR format: 26 char string... [tariff,10][assigned_status,1][tariff_type,15].

DECLARE
    v_additional_tariffs       preftz.t_added_tariff[];
    v_hts_array                VARCHAR[] DEFAULT '{}'::VARCHAR[];
    v_added_tariff_string      VARCHAR DEFAULT '';

BEGIN
    v_additional_tariffs = preftz.get_all_additional_tariffs_struc_v2(p_part_number, p_receiptid, p_base_tariff, p_country, 
        p_date, p_special_programs_indicator, p_country_of_cast, p_primary_country_of_smelt, p_secondary_country_of_smelt);
    
    -- RAISE NOTICE 'additional tariffs before converting to string: %', v_additional_tariffs;

    -- transform array of preftz.t_added_tariff types into array of varchar tariff numbers
    IF CARDINALITY(v_additional_tariffs) > 0 THEN
        SELECT STRING_AGG(CONCAT(preftz.spacefill(t.tariff_number,10),
                    preftz.spacefill(t.assigned_status,1),
                    preftz.spacefill(t.tariff_type,15)),'')
        INTO v_added_tariff_string
        FROM UNNEST(v_additional_tariffs) as t;
    END IF;

    RETURN v_added_tariff_string;
END;
$$
LANGUAGE 'plpgsql';

DROP FUNCTION IF EXISTS preftz.get_all_additional_tariffs_struc_v2;

CREATE OR REPLACE FUNCTION  preftz.get_all_additional_tariffs_struc_v2 (
    p_part_number VARCHAR(50),
    p_receiptid INTEGER,
    p_base_tariff VARCHAR(10), 
    p_country VARCHAR(2), 
    p_date DATE DEFAULT CURRENT_DATE,
    p_special_programs_indicator CHAR(2) DEFAULT '  ',
    p_country_of_cast VARCHAR(3) DEFAULT NULL,
    p_primary_country_of_smelt VARCHAR(3) DEFAULT NULL,
    p_secondary_country_of_smelt VARCHAR(3) DEFAULT NULL
)
RETURNS preftz.t_added_tariff[]
AS $$

--CHANGE LOG:
-- KK 04/06/2026 CSMS # 68253075 - GUIDANCE: Section 232 Duties on Imports of Aluminum, Steel, and Copper
-- KK 11/11/2025 Refactor logic for applying additional tariffs and implement logic for recent CBP guidance.

-- This function conbines functions: get_added_tariffs, 
--    cast & smelt tariffs (classify_receipts), get_added_derivative_tariffs, filter_additional_tariffs
--
-- It returns additional tariffs as an array of composite type preftz.t_added_tariff (see preftz.create_preftz.types).
--
-- Tables involved in getting Added Tariffs:
-- prehts.additional_tariffs_master -> additional tariffs original
-- prehts.additional_tariff_derivatives_master -> derivative tariffs, those that require content percentage (steel, alum, copper, wood)
-- prehts.additional_tariff_variable_rates_master -> variable rates; apply tariff based on combined ad_valorem rate
-- prehts.additional_tariff_priority_master -> stacking / tariff priority; removes tariffs of lower priority
-- prehts.additional_tariff_tags_master -> use this to group chapter99 - specifically to ID reciprocal tariffs
-- prehts.additional_tariff_exclusions_master -> use this to add an exclusion tariff based on the other tariffs that have been applied
-- prehts.additional_tariff_replacements_master -> use this to replace one or more tariffs with another based on parts.section_232_exclusion_number
-- prehts.annex_iv_section232_metals_master -> used to determine which type metal is flagged by hts prefix

DECLARE
    v_func_name            VARCHAR(50) DEFAULT 'get_all_additional_tariffs_struc';
    csrs                   RECORD;
    v_tariffs              preftz.t_added_tariff[];
    v_deriv_tariffs        preftz.t_added_tariff[];
    v_steel_poured_in_us          BOOLEAN;
    v_cast_smelt_in_us            BOOLEAN;
    v_steel_poured_in_uk          BOOLEAN;
    v_cast_smelt_in_uk            BOOLEAN;

BEGIN

         select  trcd.steel_poured_in_us, trcd.cast_smelt_in_us, trcd.steel_poured_in_uk, trcd.cast_smelt_in_uk
         into v_steel_poured_in_us, v_cast_smelt_in_us, v_steel_poured_in_uk, v_cast_smelt_in_uk
         from tmp_receipt_classification_data trcd
         where trcd.receiptid = p_receiptid;

/* to remove
    -- Is melted and poured in US
    SELECT EXISTS (
        SELECT receiptid
        FROM preftz.receipt_melt_and_pour
        WHERE receiptid = p_receiptid
            AND country_of_melt = 'US' 
            AND country_of_pour = 'US'
    )
    INTO v_steel_poured_in_us;

    -- Is cast and smelt in US
    SELECT EXISTS (
        SELECT receiptid
        FROM preftz.receipt_cast_and_smelt
        WHERE receiptid = p_receiptid
            AND country_of_cast = 'US' 
            AND primary_country_of_smelt = 'US'
    )
    INTO v_cast_smelt_in_us;

    -- Is melted and poured in GB
    SELECT EXISTS (
        SELECT receiptid
        FROM preftz.receipt_melt_and_pour
        WHERE receiptid = p_receiptid
            AND country_of_melt = 'GB' 
            AND country_of_pour = 'GB'
    )
    INTO v_steel_poured_in_uk;

    -- Is cast and smelt in GB
    SELECT EXISTS (
        SELECT receiptid
        FROM preftz.receipt_cast_and_smelt
        WHERE receiptid = p_receiptid
            AND country_of_cast = 'GB' 
            AND primary_country_of_smelt = 'GB'
    )
    INTO v_cast_smelt_in_uk;
*/


    -- append additional_tariffs
    v_tariffs = v_tariffs || preftz.get_added_tariffs_struc_v2(p_part_number, p_country, p_base_tariff, p_date);


    -- append cast & smelt tariffs
    FOR csrs IN (
        SELECT acst.additional_tariff_number, acst.assigned_status, acst.tariff_type
        FROM preftz.additional_cast_and_smelt_tariffs acst	
        WHERE p_date BETWEEN acst.start_date AND acst.end_date	
            AND p_base_tariff LIKE acst.tariff_prefix || '%'	
            AND (   acst.country_of_origin = p_country
                OR acst.country_of_cast = p_country_of_cast	
                OR acst.primary_country_of_smelt = p_primary_country_of_smelt	
                OR acst.secondary_country_of_smelt = p_secondary_country_of_smelt)
    )
    LOOP
        v_tariffs = v_tariffs || (csrs.additional_tariff_number, csrs.assigned_status, csrs.tariff_type)::preftz.t_added_tariff;
    END LOOP;


    -- append derivative tariffs from additional_tariff_derivatives
    v_deriv_tariffs = preftz.get_added_derivative_tariffs_struc_v2(p_part_number, p_receiptid, p_country, p_base_tariff, p_date, 
        v_steel_poured_in_us, v_cast_smelt_in_us);
    v_tariffs = ARRAY(SELECT DISTINCT UNNEST(v_tariffs || v_deriv_tariffs));

    -- KK 04/06/2026 CSMS # 68253075 - GUIDANCE: Section 232 Duties on Imports of Aluminum, Steel, and Copper
    v_tariffs = preftz.filter_section232_tariffs_struc_v2(v_tariffs, p_part_number, p_receiptid, p_country, p_base_tariff, p_date, 
        v_steel_poured_in_us, v_cast_smelt_in_us, v_steel_poured_in_uk, v_cast_smelt_in_uk);

    
    -- filter the array; variable rate tariffs, stacking logic, and exclusion tariffs
    v_tariffs = preftz.filter_additional_tariffs_struc_v2(v_tariffs, p_base_tariff, p_date, p_special_programs_indicator, p_country);


    RETURN v_tariffs;

END;
$$
LANGUAGE 'plpgsql';


