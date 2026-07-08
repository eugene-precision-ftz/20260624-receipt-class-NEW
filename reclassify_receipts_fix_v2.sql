-- DROP PROCEDURE preftz.reclassify_receipts_fix_v2(bool);

CREATE OR REPLACE PROCEDURE preftz.reclassify_receipts_fix_v2(IN p_split_receipts boolean)
 LANGUAGE plpgsql
AS $procedure$
-- KK 03/23/2026 use table tariff_reclassifications_for_entry to strip IEEPA tariffs from those receipts that are on an Entry
-- KK 11/11/2025 change to allow an override HTS to handle BW receipts that had a Primary HTS change since it had been classified last.
-- KK 10/07/2025 create archive table
-- This is a fix template for identifying the receipts that need to be reclassified. You will change the rs query so that
-- it returns the necessary columns, and it will reclassify each receipt.

DECLARE
    v_proc_name VARCHAR(50) DEFAULT 'reclassify_receipts_fix_v2';
    rs                     RECORD;
    v_new_receiptid        INTEGER;
    v_now                  TIMESTAMP;
    v_result_1             VARCHAR(10);  --PASS or FAIL
    v_result_2             VARCHAR(10);  --PASS or FAIL    

    v_zone_status          VARCHAR(1);
    v_new_zone_status      VARCHAR(1);

BEGIN

    CREATE TABLE IF NOT EXISTS preftz.reclassified_receipts (
        receiptid INTEGER,
        classify_date DATE,
        comment TEXT,
        modified_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (receiptid, modified_time)
    );

    SELECT CURRENT_TIMESTAMP
    INTO v_now;

    FOR rs IN
        -- CREATE TABLE preftz.selected_receipts_to_reclassify (
        --     receiptid INTEGER PRIMARY KEY,
        --     override_hts VARCHAR(10)
        -- );
        -- query to feed the reclassification
      WITH receipt_item_links AS (
            -- handle part_number changes
            SELECT receiptid, MAX(itemid) AS itemid
            FROM preftz.inventory_items
            GROUP BY receiptid
        )
        SELECT 
           r.receiptid
        , COALESCE(r.privileged_date, r.receipt_date::DATE) AS classify_date
        , COALESCE(ii.quantity_received,0) as quantity_received
        , COALESCE(ii.quantity_on_hand,0) as quantity_on_hand 
        , NULLIF(TRIM(rtr.override_hts),'') AS override_hts
        FROM preftz.receipts r
        JOIN preftz.selected_receipts_to_reclassify rtr ON rtr.receiptid = r.receiptid
        left JOIN receipt_item_links ril ON ril.receiptid = r.receiptid
        left JOIN preftz.inventory_items ii ON ii.itemid = ril.itemid
        -- LEFT JOIN preftz.e214_filing_statuses efs ON efs.zone_admission_no = r.zone_admission_no
    LOOP
        RAISE NOTICE 'processing: % for % and hts %', rs.receiptid, rs.classify_date, rs.override_hts;

        IF p_split_receipts IS TRUE THEN
        /*
            IF rs.quantity_on_hand <= 0 THEN
                INSERT INTO preftz.reclassified_receipts (receiptid, classify_date, comment, modified_time)
                VALUES (rs.receiptid, rs.classify_date, 'No Inventory, not reclassified: ' || rs.receiptid, v_now);
                RAISE NOTICE '    No Inventory, not reclassified: %', rs.receiptid;
                RETURN;
            END IF;

            IF rs.quantity_received <> rs.quantity_on_hand THEN
                v_new_receiptid = preftz.split_receipt(rs.receiptid);
                RAISE NOTICE '    split: % to %', rs.receiptid, v_new_receiptid;

                v_result = preftz.reclassify_receipt_by_date(v_new_receiptid, rs.classify_date, rs.override_hts);

                INSERT INTO preftz.reclassified_receipts (receiptid, classify_date, comment, modified_time)
                VALUES (v_new_receiptid, rs.classify_date, 'split from ' || rs.receiptid || ' ' || 
                    v_result, v_now);
                RAISE NOTICE '    reclassified: %', v_new_receiptid;
            ELSE
                -- Archive it KK 10/07/2025
                INSERT INTO preftz.archived_receipt_classifications
                    (receiptid, harmonized_tariff_schedule_number, special_programs_indicator, 
                    unit_value, tariff_type, distinct_tariff_line_indicator, primary_tariff, quantity1_rate, 
                    quantity2_rate, unit_duty_liability, archived_date)
                SELECT receiptid, harmonized_tariff_schedule_number, special_programs_indicator, 
                    unit_value, tariff_type, distinct_tariff_line_indicator, primary_tariff, quantity1_rate, 
                    quantity2_rate, unit_duty_liability, v_now
                FROM preftz.receipt_classifications
                WHERE receiptid = rs.receiptid;

                v_result = preftz.reclassify_receipt_by_date(rs.receiptid, rs.classify_date, rs.override_hts);

                INSERT INTO preftz.reclassified_receipts (receiptid, classify_date, comment, modified_time)
                VALUES (rs.receiptid, rs.classify_date, v_result, v_now);
                RAISE NOTICE '    reclassified: %', rs.receiptid;
            END IF;
        */
        ELSE --IF p_split_receipts IS FALSE

            -- Archive it KK 10/07/2025
            INSERT INTO preftz.archived_receipt_classifications
                (receiptid, harmonized_tariff_schedule_number, special_programs_indicator, 
                unit_value, tariff_type, distinct_tariff_line_indicator, primary_tariff, quantity1_rate, 
                quantity2_rate, unit_duty_liability, archived_date)
            SELECT receiptid, harmonized_tariff_schedule_number, special_programs_indicator, 
                unit_value, tariff_type, distinct_tariff_line_indicator, primary_tariff, quantity1_rate, 
                quantity2_rate, unit_duty_liability, v_now
            FROM preftz.receipt_classifications
            WHERE receiptid = rs.receiptid;

            --v_result = preftz.reclassify_receipt_by_date(rs.receiptid, rs.classify_date, rs.override_hts);

            v_result_1 :=  preftz.generate_tmp_receipt_classification_data 
            (
             null -- p_admission_number character varying,	
            ,null --p_classify_date DATE DEFAULT NULL::date,
            ,rs.receiptid
            );

            v_result_2 := preftz.generate_tmp_receipt_classification_work();

    if (v_result_1 = 'PASS' AND v_result_2 = 'PASS')
    THEN
    --delete from preftz.receipt_classifications_v2 for the receipts in this admission number 
    --and insert new records from tmp_receipt_classification_data
        DELETE FROM preftz.receipt_classifications rc
        USING (
            SELECT DISTINCT receiptid
            FROM tmp_receipt_classification_work
        ) w
        WHERE rc.receiptid = w.receiptid;

          INSERT INTO preftz.receipt_classifications
          (
              receiptid,
              --created_date,
              harmonized_tariff_schedule_number,
              special_programs_indicator,
              unit_value,
              tariff_type,
              distinct_tariff_line_indicator,
              primary_tariff,
              quantity1_rate,
              quantity2_rate,
              unit_duty_liability
          )
          SELECT
              receiptid,
              --created_date,
              harmonized_tariff_schedule_number,
              special_programs_indicator,
              unit_value,
              tariff_type,
              distinct_tariff_line_indicator,
              primary_tariff,
              quantity1_rate,
              quantity2_rate,
              unit_duty_liability
          FROM tmp_receipt_classification_work;       

          select coalesce(tmp.new_zone_status, ' ') , coalesce(tmp.zone_status, ' ') 
          INTO v_new_zone_status, v_zone_status
          FROM tmp_receipt_classification_data tmp
          where tmp.receiptid = rs.receiptid;

          IF (v_new_zone_status IS DISTINCT FROM v_zone_status)
          THEN
                      UPDATE preftz.receipts r	
                         SET zone_status = v_new_zone_status	
                       WHERE r.receiptid = rs.receiptid;	
                       	
                      UPDATE preftz.inventory_items ii	
                         SET zone_status = v_new_zone_status	
                       WHERE ii.receiptid = rs.receiptid;	
          END IF;	

          IF (v_new_zone_status = 'P')
          THEN
                      UPDATE preftz.receipts r	
                         SET privileged_date = tmp.privileged_date
                         FROM tmp_receipt_classification_data tmp
                      WHERE tmp.receiptid = rs.receiptid
                      AND r.receiptid = tmp.receiptid;	
          END IF;	

                  	
                --   --RTJ 05/24/2021	
                --   IF (v_zone_status = 'P') AND (v_add_hts_count = 0 ) THEN	
                --       UPDATE preftz.receipts r	
                --          SET privileged_date = COALESCE(r.privileged_date,r.receipt_date,v_classify_date) --NKM 09/18/2023	
                --        WHERE r.receiptid = crs.receiptid;	
                --   END IF;	
                --   --RTJ 05/24/2021	
                  
                  
                --   -- EG 3/10/2026
                --   IF (v_zone_status = 'P') AND (v_add_hts_count > 0)
                --   THEN	
                --       UPDATE preftz.receipts r	
                --          SET privileged_date = v_classify_date --actually a privileged date provided in transfer item file
                --       WHERE r.receiptid = crs.receiptid;	
                      
                --       RAISE NOTICE '------------------------------------------------preftz.receipts was updated with v_classify_date from transfer_ztz_archive:%,  %', v_classify_date, crs.receiptid; 
                --   END IF;	
                --   -- EG 3/10/2026

            INSERT INTO preftz.reclassified_receipts (receiptid, classify_date, comment, modified_time)
            VALUES (rs.receiptid, rs.classify_date, v_result_1 || ' no split', v_now);
            RAISE NOTICE '    reclassified: %', rs.receiptid;
            
           ELSE
                INSERT INTO preftz.reclassified_receipts 
                    (receiptid, classify_date, comment, modified_time)
                VALUES 
                    (
                        rs.receiptid, 
                        rs.classify_date, 
                        'FAILED no split: generate data=' || COALESCE(v_result_1, 'NULL') ||
                        ', generate work=' || COALESCE(v_result_2, 'NULL'),
                        v_now
                    );
            
                RAISE NOTICE  '    failed: %, data %, work %',  rs.receiptid, v_result_1, v_result_2;
            END IF;--(v_result_1 = 'PASS' AND v_result_2 = 'PASS')
            
        END IF;--IF p_split_receipts IS TRUE 

    END LOOP;

/*
    -- KK 03/23/2026 strip IEEPA from those receipts on an Entry document
    RAISE NOTICE 'Removing IEEPA tariffs from those receipts...';
    WITH added_tariffs AS (
        SELECT DISTINCT rc.receiptid, rc.harmonized_tariff_schedule_number, rc.tariff_type
        from preftz.receipt_classifications rc
        join preftz.selected_receipts_to_reclassify srtr on srtr.receiptid = rc.receiptid
        where rc.tariff_type <> 'BASE'
    ), target_tariffs AS (
        SELECT adt.receiptid, adt.harmonized_tariff_schedule_number, adt.tariff_type
        FROM preftz.tariff_reclassifications_for_entry tre
        JOIN added_tariffs adt ON adt.harmonized_tariff_schedule_number = tre.from_tariff_number
            AND adt.tariff_type = tre.from_tariff_type
        WHERE COALESCE(tre.to_tariff_number,'') = ''
    )
    DELETE FROM preftz.receipt_classifications rc
    USING target_tariffs tt
    WHERE tt.receiptid = rc.receiptid
        AND tt.harmonized_tariff_schedule_number = rc.harmonized_tariff_schedule_number
        AND tt.tariff_type = rc.tariff_type
    ;
*/
    
--    DELETE FROM preftz.selected_receipts_to_reclassify;

END;
$procedure$
;
