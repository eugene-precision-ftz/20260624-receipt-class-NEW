CREATE OR REPLACE PROCEDURE preftz.calculate_derivative_quantity (p_receiptid INTEGER)
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
        FROM preftz.receipt_classifications rc
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
            SELECT rc.harmonized_tariff_schedule_number, COALESCE(dpc.aluminum_percentage,1.0) AS aluminum_percentage, 
                    COALESCE(dpc.steel_percentage,1.0) AS steel_percentage, 
                    COALESCE(dpc.copper_percentage,1.0) AS copper_percentage, pc_base.quantity1_conversion_rate as base_qty1,
                    rc.tariff_type, d.is_steel_derivative, d.is_aluminum_derivative, d.is_copper_derivative
            FROM preftz.receipts r
            JOIN preftz.receipt_classifications rc ON r.receiptid = rc.receiptid
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

            UPDATE preftz.receipt_classifications rc
            SET quantity1_rate = v_qty1
            WHERE rc.receiptid = p_receiptid
                AND rc.harmonized_tariff_schedule_number = rs.harmonized_tariff_schedule_number;
        END LOOP;
    END IF;

END; 
$$;



