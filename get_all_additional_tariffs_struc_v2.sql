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


