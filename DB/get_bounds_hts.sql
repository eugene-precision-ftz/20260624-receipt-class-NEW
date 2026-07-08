CREATE OR REPLACE FUNCTION preftz.get_bounds_hts(p_part_number VARCHAR(50), p_unit_value DOUBLE PRECISION)
  RETURNS VARCHAR(10)
AS $$

--RTJ 01/17/2023 set up to include finding tariff numbers for both value-driven and non-value-driven classifications
--               returns MISSINGHTS if bounds required and none has been set up
--               returns EDITBOUNDS if bounds required and too many are set up

DECLARE
  v_base_tariff       VARCHAR(10);
  v_tariff_number     VARCHAR(10);
  v_edit_code         VARCHAR(3);
  v_low_bounds        DOUBLE PRECISION;
  v_high_bounds       DOUBLE PRECISION;
  
BEGIN
  --INSERT INTO preftz.system_log (procedure_name, log_message) 
  --VALUES ('get_bounds_hts', 'part/price: ' || p_part_number || ' / ' || p_unit_value);
  
  SELECT pc.harmonized_tariff_schedule_number 
    INTO v_base_tariff 
    FROM preftz.part_classifications pc 
   WHERE pc.part_number = p_part_number 
   AND pc.tariff_type = 'BASE';
   
  SELECT hts.value_edit_code, hts.value_low_bounds, hts.value_high_bounds
    INTO v_edit_code, v_low_bounds, v_high_bounds
    FROM preftz.harmonized_tariff_schedule_reference hts
   WHERE hts.tariff_number = v_base_tariff
     AND hts.record_begin_effective_date <= current_date
     AND hts.record_end_effective_date >= current_date
     AND COALESCE(hts.special_programs_indicator,'') = '';
     
  IF v_edit_code IS NULL THEN  --no bounds audit for this HTS
      v_tariff_number = v_base_tariff;
  ELSE
      v_tariff_number = NULL;
      
      IF preftz.price_within_bounds(v_edit_code, p_unit_value, v_low_bounds, v_high_bounds) = TRUE THEN  --value fits within base HTS range
          v_tariff_number = v_base_tariff;
      ELSE
          SELECT pb.tariff_number
            INTO v_tariff_number
            FROM preftz.part_bounds pb
           WHERE pb.part_number = p_part_number
             AND preftz.price_within_bounds(pb.value_edit_code, p_unit_value, pb.value_low_bounds, pb.value_high_bounds) = TRUE;
      END IF;
     
      IF v_tariff_number IS NULL THEN
          v_tariff_number = 'MISSINGHTS';
      ELSE
          IF (SELECT COUNT(*)
                FROM preftz.part_bounds pb
               WHERE pb.part_number = p_part_number
                 AND preftz.price_within_bounds
                      (pb.value_edit_code, p_unit_value, pb.value_low_bounds, pb.value_high_bounds) = TRUE) > 1 THEN
              v_tariff_number = 'EDITBOUNDS';
          END IF;
      END IF;
  END IF;

  --INSERT INTO preftz.system_log (procedure_name, log_message) 
  --VALUES ('get_bounds_hts', 'tariff_number: ' || v_tariff_number);

  RETURN v_tariff_number;

END; $$
LANGUAGE plpgsql;

