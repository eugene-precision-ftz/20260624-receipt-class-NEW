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

