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



