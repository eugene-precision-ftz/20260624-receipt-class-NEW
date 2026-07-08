CREATE OR REPLACE PROCEDURE preftz.calculate_duty_liability (p_receiptid INTEGER)
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
                rc.unit_value value_of_goods, preftz.get_receipt_value(r.receiptid) line_value, --RTJ 01/21/2023
                rc.tariff_type, COALESCE(r.privileged_date, current_date) classification_date,
                rcbase.harmonized_tariff_schedule_number AS base_hts, tvr.minimum_rate,
                usv.usmca_value
            FROM preftz.receipts r
            INNER JOIN preftz.receipt_classifications rc ON r.receiptid = rc.receiptid
            INNER JOIN preftz.receipt_classifications rcbase ON r.receiptid = rcbase.receiptid
                AND rcbase.tariff_type = 'BASE'
            LEFT JOIN preftz.additional_tariff_variable_rates tvr 
                ON tvr.tariff_number = rc.harmonized_tariff_schedule_number
            LEFT JOIN (
                SELECT receiptid, '99038220' as tariff_number,  -- Non-us-value
                    CASE WHEN percent_us_value >= 0.4 THEN 0.6::NUMERIC ELSE 1.0::NUMERIC - percent_us_value END AS usmca_value
                FROM preftz.receipt_percentage_value
                UNION
                SELECT receiptid, '99038221' as tariff_number,  -- US value
                    CASE WHEN percent_us_value >= 0.4 THEN 0.4::NUMERIC ELSE percent_us_value::NUMERIC END AS usmca_value
                FROM preftz.receipt_percentage_value
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
    
        UPDATE preftz.receipt_classifications rc
            SET unit_duty_liability = v_duty_specific + v_duty_ad_valorem + v_duty_other
        WHERE rc.receiptid = p_receiptid
            AND rc.harmonized_tariff_schedule_number = rs.harmonized_tariff_schedule_number;
                
        --set BASE rates to zero if using an overriding tariff type
        IF rs.tariff_type IN ('OVERRIDE','MTB') THEN
            UPDATE preftz.receipt_classifications rc
                SET unit_duty_liability = 0
            WHERE rc.receiptid = p_receiptid
                AND rc.tariff_type NOT IN ('OVERRIDE','MTB');  --RTJ 11/30/2022
        END IF;
            
    END LOOP;    

END; 
$$;


