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


