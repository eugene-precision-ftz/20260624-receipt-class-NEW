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



