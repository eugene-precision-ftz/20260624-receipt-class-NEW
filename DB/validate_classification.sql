CREATE OR REPLACE FUNCTION preftz.validate_classification (p_tariff_number VARCHAR(12), 
                                                           p_special_program VARCHAR(2), 
                                                           p_country VARCHAR(2), 
                                                           p_date TIMESTAMP)
  RETURNS VARCHAR(12)
AS $$

--Change Log:
--KK  06/14/2024 Increased p_tariff_number to 12 to match the length from fed_parts table. The 
--               dots (XXXX.XX.XXXX) should be removed before calling this function.
--RTJ 01/17/2023 Added value_edit_code, value_low_bounds, value_high_bounds to harmonized_tariff_schedule_reference
--               Added pga_code_array to harmonized_tariff_schedule_reference
--NKM 02/02/2022 Added miscellaneous_permit_license_indicator to harmonized_tariff_schedule_reference
--RTJ 08/02/2021 handle extra space in SPI field on master table
--RTJ 10/21/2020 Add capacity to pull from master tables if HTS/SPI is not in local table

DECLARE
  v_valid_tariff     VARCHAR(12) = 'AUDIT';
  v_tariff_number    VARCHAR(10) = NULL;
  v_begin_date       DATE;
  v_local_spi_codes  VARCHAR(60);
  v_user_description VARCHAR(45);
  hrs                RECORD;
  i                  INTEGER;
  
BEGIN
    --Confirm validity of HTS for date range
    --check local table
    IF EXISTS (SELECT 'x' 
                 FROM preftz.harmonized_tariff_schedule_reference h
                WHERE h.tariff_number = p_tariff_number
                  AND h.record_begin_effective_date <= p_date
                  AND h.record_end_effective_date >= p_date)  THEN
        
        v_valid_tariff = 'PASS';
  
    ELSE
        --if not in the local table, check the master table
        SELECT hb.tariff_number, hb.record_begin_effective_date
          INTO v_tariff_number, v_begin_date
          FROM prehts.harmonized_tariff_schedule_base hb
         WHERE hb.tariff_number = p_tariff_number
           AND hb.record_begin_effective_date <= p_date
           AND hb.record_end_effective_date >= p_date;
                      
        IF v_tariff_number IS NOT NULL THEN
            
            --if in master table, it is possible that the end date has been extended
            --so record the spi codes/user descrption being used by this local database then
            --clear the local table for this hts/begin date to allow it to repopulate
            
            v_local_spi_codes = '';
            
            FOR hrs IN SELECT hr.special_programs_indicator
                         FROM preftz.harmonized_tariff_schedule_reference hr
                        WHERE hr.tariff_number = p_tariff_number
                          AND hr.record_begin_effective_date = v_begin_date
                          AND COALESCE(hr.special_programs_indicator,'') <> ''
            LOOP
                v_local_spi_codes = v_local_spi_codes || preftz.spacefill(hrs.special_programs_indicator,2);
            END LOOP;
            
            SELECT hr.user_description
              INTO v_user_description
              FROM preftz.harmonized_tariff_schedule_reference hr
             WHERE hr.tariff_number = p_tariff_number
               AND hr.record_begin_effective_date = v_begin_date
               AND COALESCE(hr.special_programs_indicator,'') = '';
                  
            DELETE FROM preftz.harmonized_tariff_schedule_reference hr
                  WHERE hr.tariff_number = p_tariff_number
                    AND hr.record_begin_effective_date = v_begin_date;
                    
            INSERT INTO preftz.harmonized_tariff_schedule_reference
                       (tariff_number, record_begin_effective_date, record_end_effective_date,
                        special_programs_indicator, unit_1, unit_2, commodity_description,
                        duty_computation_code, column_1_rate_specific, column_1_rate_ad_valorem,
                        column_1_rate_other, user_description, miscellaneous_permit_license_indicator, --NKM 02/02/2022
                        value_edit_code, value_low_bounds, value_high_bounds, pga_code_array)  --RTJ 01/17/2023
                 SELECT hb.tariff_number, hb.record_begin_effective_date, hb.record_end_effective_date,
                        hr.special_programs_indicator, hb.unit_1, hb.unit_2, hb.commodity_description,
                        hb.duty_computation_code, hr.rate_specific, hr.rate_ad_valorem, hr.rate_other,
                        v_user_description, hb.miscellaneous_permit_license_indicator, --NKM 02/02/2022
                        hb.value_edit_code, hb.value_low_bounds, hb.value_high_bounds, pga.pga_code_array  --RTJ 01/17/2023
                   FROM prehts.harmonized_tariff_schedule_base hb
                        INNER JOIN prehts.harmonized_tariff_schedule_rates hr
                                ON hb.tariff_number = hr.tariff_number
                               AND hb.record_begin_effective_date = hr.record_begin_effective_date
                               AND COALESCE(hr.special_programs_indicator,'') = ''
                         LEFT JOIN prehts.tariff_number_pga_codes pga  --RTJ 01/17/2023
                                ON hb.tariff_number = pga.tariff_number
                               AND hb.record_begin_effective_date = pga.record_begin_effective_date
                  WHERE hb.tariff_number = p_tariff_number
                    AND hb.record_begin_effective_date <= p_date
                    AND hb.record_end_effective_date >= p_date;
                    
            IF v_local_spi_codes <> ''
            THEN
                FOR i IN 1 .. LENGTH(v_local_spi_codes) BY 2
                LOOP
                    INSERT INTO preftz.harmonized_tariff_schedule_reference
                           (tariff_number, record_begin_effective_date, record_end_effective_date,
                            special_programs_indicator, unit_1, unit_2, commodity_description,
                            duty_computation_code, column_1_rate_specific, column_1_rate_ad_valorem,
                            column_1_rate_other, user_description, miscellaneous_permit_license_indicator, --NKM 02/02/2022
                            value_edit_code, value_low_bounds, value_high_bounds, pga_code_array)  --RTJ 01/17/2023
                     SELECT hb.tariff_number, hb.record_begin_effective_date, hb.record_end_effective_date,
                            hr.special_programs_indicator, hb.unit_1, hb.unit_2, hb.commodity_description,
                            hb.duty_computation_code, hr.rate_specific, hr.rate_ad_valorem, hr.rate_other,
                            v_user_description, hb.miscellaneous_permit_license_indicator, --NKM 02/02/2022
                            hb.value_edit_code, hb.value_low_bounds, hb.value_high_bounds, pga.pga_code_array  --RTJ 01/17/2023
                       FROM prehts.harmonized_tariff_schedule_base hb
                            INNER JOIN prehts.harmonized_tariff_schedule_rates hr
                                    ON hb.tariff_number = hr.tariff_number
                                   AND hb.record_begin_effective_date = hr.record_begin_effective_date
                                   AND TRIM(hr.special_programs_indicator) = TRIM(SUBSTR(v_local_spi_codes,i,2))
                             LEFT JOIN prehts.tariff_number_pga_codes pga  --RTJ 01/17/2023
                                    ON hb.tariff_number = pga.tariff_number
                                   AND hb.record_begin_effective_date = pga.record_begin_effective_date
                      WHERE hb.tariff_number = p_tariff_number
                        AND hb.record_begin_effective_date <= p_date
                        AND hb.record_end_effective_date >= p_date;
                END LOOP;
            END IF;

            v_valid_tariff = 'PASS';

        ELSE
            v_valid_tariff = 'FAIL';
        END IF;
    END IF;

    --Confirm validity of SPI code for HTS
    --This will need to be updated when we incorporate expanded SPI logic
    --check local table
    IF v_valid_tariff <> 'FAIL' AND COALESCE(p_special_program,'') <> '' THEN
        IF EXISTS (SELECT 'x' 
                     FROM preftz.harmonized_tariff_schedule_reference h
                    WHERE h.tariff_number = p_tariff_number
                      AND h.special_programs_indicator = p_special_program
                      AND h.record_begin_effective_date <= p_date
                      AND h.record_end_effective_date >= p_date)  THEN
                      
            v_valid_tariff = 'PASS';
            
        ELSE
            --if not in the local table, check the master table
            IF EXISTS (SELECT 'x'
                         FROM prehts.harmonized_tariff_schedule_rates hr
                        WHERE hr.tariff_number = p_tariff_number
                          AND TRIM(hr.special_programs_indicator) = p_special_program  --RTJ 08/02/2021
                          AND hr.record_begin_effective_date <= p_date
                          AND hr.record_end_effective_date >= p_date)  THEN
                              
                INSERT INTO preftz.harmonized_tariff_schedule_reference
                           (tariff_number, record_begin_effective_date, record_end_effective_date,
                            special_programs_indicator, unit_1, unit_2, commodity_description,
                            duty_computation_code, column_1_rate_specific, column_1_rate_ad_valorem,
                            column_1_rate_other, miscellaneous_permit_license_indicator, --NKM 02/02/2022
                            value_edit_code, value_low_bounds, value_high_bounds, pga_code_array)  --RTJ 01/17/2023
                     SELECT hb.tariff_number, hb.record_begin_effective_date, hb.record_end_effective_date,
                            TRIM(hr.special_programs_indicator), hb.unit_1, hb.unit_2, hb.commodity_description,  --RTJ 08/02/2021
                            hb.duty_computation_code, hr.rate_specific, hr.rate_ad_valorem, hr.rate_other,
                            hb.miscellaneous_permit_license_indicator, --NKM 02/02/2022
                            hb.value_edit_code, hb.value_low_bounds, hb.value_high_bounds, pga.pga_code_array  --RTJ 01/17/2023
                       FROM prehts.harmonized_tariff_schedule_base hb
                            INNER JOIN prehts.harmonized_tariff_schedule_rates hr
                                    ON hb.tariff_number = hr.tariff_number
                                   AND hb.record_begin_effective_date = hr.record_begin_effective_date
                                   AND hr.special_programs_indicator = p_special_program
                             LEFT JOIN prehts.tariff_number_pga_codes pga  --RTJ 01/17/2023
                                    ON hb.tariff_number = pga.tariff_number
                                   AND hb.record_begin_effective_date = pga.record_begin_effective_date
                      WHERE hb.tariff_number = p_tariff_number
                        AND hb.record_begin_effective_date <= p_date
                        AND hb.record_end_effective_date >= p_date; 
    
                v_valid_tariff = 'PASS';
    
            ELSE
                v_valid_tariff = 'FAIL';
            END IF;
        END IF;
    END IF;

    IF v_valid_tariff = 'PASS' THEN
        v_valid_tariff = preftz.spacefill(p_tariff_number,10) || preftz.spacefill(COALESCE(p_special_program,''),2);
    END IF;

  RETURN v_valid_tariff;

END; $$
LANGUAGE plpgsql;


