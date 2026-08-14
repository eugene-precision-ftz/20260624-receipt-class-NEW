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
-- KK 07/30/2026 Handle EXCLUSION301 - remove any of the older CN Section301 tariffs, but not the new forced labor version
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
    v_exlusion_tariffs           VARCHAR(10)[] DEFAULT '{}'::VARCHAR(10)[];
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
         INTO v_232_exclusion, v_301_exclusion, v_chapter98_override, v_used_for_production_or_repair, v_exlusion_tariffs
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

    -- KK 07/30/2026 Handle EXCLUSION301 - remove any of the older CN Section301 tariffs, but not the new forced labor version
    IF COALESCE(v_301_exclusion,'') <> '' AND p_country = 'CN' THEN
        IF EXISTS (
            SELECT 1 FROM UNNEST(v_tariffs) as a
            WHERE a.tariff_number IN(
                SELECT additional_tariff_number FROM preftz.additional_tariff_tags
                WHERE tag_name = 'exclusion301_exclude'
            )
        )
        THEN
            RAISE NOTICE '%', 'removing section301 tariff because EXCLUSION301 exists in part_classifications';
            SELECT ARRAY_AGG((a.tariff_number, a.assigned_status, a.tariff_type)::preftz.t_added_tariff)
            INTO v_tariffs
			FROM UNNEST(v_tariffs) as a
			WHERE a.tariff_number NOT IN(
                SELECT additional_tariff_number FROM preftz.additional_tariff_tags 
				WHERE tag_name = 'exclusion301_exclude'
			);
        END IF;
    END IF;

    -- Replace any tariffs with their exclusion tariff if necessary (preftz.additional_tariff_replacements)
    IF CARDINALITY(v_exlusion_tariffs) > 0 THEN
        FOR trs IN
            WITH added AS (
                SELECT UNNEST(v_tariffs) AS tariff_struc
            ), replacements AS (
                SELECT atr.tariff_number, atr.assigned_status, atr.tariff_type, 
                    UNNEST(atr.replaceable_tariffs) as tariff_to_replace
                FROM preftz.additional_tariff_replacements atr
                WHERE atr.tariff_number = ANY(v_exlusion_tariffs)
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
    IF CARDINALITY(v_exlusion_tariffs) > 0 THEN
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
                trs.additional_tariff_number, v_232_exclusion, v_exlusion_tariffs;
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
                trs.additional_tariff_number, v_232_exclusion, v_exlusion_tariffs;
            v_tariffs = v_tariffs || (trs.additional_tariff_number, trs.assigned_status, trs.tariff_type)::preftz.t_added_tariff;
        END LOOP;
    END IF;
    
    -- Remove any duplicates
    SELECT ARRAY_AGG(DISTINCT tariff_struc) INTO v_tariffs FROM (SELECT UNNEST(v_tariffs) AS tariff_struc) a;
    RAISE NOTICE 'after get_added_tariffs_struc: %', v_tariffs;

    RETURN v_tariffs;

END; $$
LANGUAGE plpgsql;




