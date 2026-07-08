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




