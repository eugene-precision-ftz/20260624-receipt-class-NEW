DROP PROCEDURE IF EXISTS preftz.audit_fed_receipts(); 	
DROP PROCEDURE IF EXISTS preftz.audit_fed_receipts(INTEGER); 	
DROP PROCEDURE IF EXISTS preftz.audit_fed_receipts(BOOLEAN); 	
 	
CREATE OR REPLACE PROCEDURE preftz.audit_fed_receipts(IN p_use_selected_receipts boolean DEFAULT false) 	
 LANGUAGE plpgsql 	
AS $BODY$ 	
 	
--Change Log: 	
-- KK 07/03/2026 add USMCA special treatments, allow capture of percentage of value is US content.
-- EG 07/06/2026 some issues fixed
-- MH 07/02/2026 allow UN (Unknown) for country of cast	
-- EG 6/10/2026 auto delete pre-receipts DEV-257 	
-- EG 4/7/2026 auto delete pre-receipts DEV-257 	
-- KK 05/11/2026 Fix cast and smelt reporting to reflect new Section232 prefixes. 	
-- KK 04/23/2026 Account for duplicate key receipt in receipt_derivative_content with upsert. 	
-- CL 04/22/2026 Allow defaults by part for melt/pour and cast/smelt. 	
-- KK 04/14/2026 Allow defaults by part for Aluminum, Steel, and Copper content weights. 	
-- KK 04/06/2026 CSMS # 68253075 - GUIDANCE: Section 232 Duties on Imports of Aluminum, Steel, and Copper 	
-- KK 01/13/2026 Add ability to process a batch of receipts from fed_receipts. 	
-- NO 12/03/2025 Added optional param to audit single receipt by receiptid, guard clause to exit if not found and checks throughout to support 	
-- KK 08/01/2025 Logic for SECTION232 Copper derivatives zone entry. 	
-- KK 07/18/2025 Create new part_number(s) where we have a new lot in fed_receipts. 	
-- KK 05/23/2025 create temp views for cast/smelt and melt/pour reporting and don't flag 0% derivatives. 	
-- KK 05/09/2025 Cast/Smelt and Melt/Pour reporting should NOT include derivatives that have zero percent aluminum or steel. 	
-- KK 05/02/2025 Fix derivative percentage audit; allow temp deposit, domestic, z2z, pre-receipt to process. 	
-- KK 04/23/2025 SECTION232 Steel and aluminum derivatives. Derivative percentage changes. 	
-- KK 04/22/2025 SECTION232 Steel and aluminum derivatives. Changes to fix cast and smelt for new derivatives. 	
-- KK 04/17/2025 SECTION232 Steel and aluminum derivatives 	
-- KK 11/19/2024 - remove audits for countervailing and antidumping 	
-- KK 11/14/2024 allow user to input license number and country of cast, even if not required 	
-- MH 10/22/2024 delete currently present user references 	
-- KK 08/20/2024 Changes to allow Kit conversion to part and versioning of Kit BOM. 	
--NKM 05/21/2024 Added missing criteria to check for duplicate transaction_reference (previous receipts) 	
--Mh 5/2/2024 added kitting receipt missing code ( copied from test environments that had the complete code) 	
--NKM 04/08/2024 Added receipt_date as build_date to kit_builds 	
--NKM 03/25/2024 Added domestic kit receipts 	
--               Added fed_status of 'AUDITING' to distinguish between unprocessed records and records currently being processed 	
--NKM 02/12/2024 Added kit logic - kits not eligible for receipts 	
--NKM 12/18/2023 Corrected criterion for requiring a proxy on ZTZ receipts 	
--NKM 11/07/2023 Added COALESCE to country_of_origin in reversal logic 	
--NKM 09/18/2023 Changed privileged_date to match receipt_date 	
--JMM 07/11/2023 Fixed unknow pre_receipt and changed to fr.pre_receipt at line 660 	
--NKM 06/28/2023 Allow for zone-to-zone pre-receipts 	
--MH 5/4/2023 type on secondary 	
--NKM 04/21/2023 Added aluminum cast & smelt fields 	
--               Fixed loophole for domestic goods in MID code audit 	
--RTJ 01/19/2023 Added unit_assist 	
--NKM 10/03/2022 Standardized criteria for editing 214 data and added use of update_e214_after_create 	
--NKM 08/25/2022 Added UPPER conversion to inbonds 	
--NKM 07/12/2022 Added roundoff error protections using v_tol 	
--NKM 05/31/2022 Link conveyance to current admission if it has receipts but no admission number 	
--NKM 05/04/2022 Bugfix - copy pre_receipt field to receipts table 	
--NKM 05/03/2022 Added phase 1 of pre_receipt logic - pre_receipts do not create inventory_items 	
--NKM 04/27/2022 Bugfix - fixed re-enabled AD/CVD error logic 	
--NKM 04/10/2022 BOL proxy required on ZTZ receipts when option 'ZTZ MATCH ON PROXY' is 'YES' 	
--NKM 03/30/2022 Removed MID code audit for zone-to-zone 	
--NKM 03/18/2022 Reworked zone-to-zone handling 	
--               Moved query that strips conveyanceid and admission_no from all domestic receipts from process_receipt_updates to audit_fed_receipts 	
--               Added invalid MID code audit 	
--               Moved audit of AD/CV numbers to function audit_case_number 	
--               and added call to query_case_numbers 	
--NKM 02/17/2022 Added clearing import_license_type at start of procedure 	
--NKM 02/02/2022 Added import license logic 	
--RTJ 11/08/2021 add zone_to_zone_transfer field to fed_receipts to handle edits to ZTZ transfers 	
--               and simple ZTZ receipts from non-PREFTZ systems 	
 	
--RTJ 11/01/2021 add checks and updates of e214 statuses 	
--NKM 10/20/2021 corrected typo in error message 	
--NKM 09/01/2021 revised process for receipt updates 	
--RTJ 08/12/2021 update inbond number from ZTZ log for ZTZ transfers 	
--NKM 08/09/2021 now removes non-alphanumeric characters from fed BOL, HBOL, and in-bond numbers 	
--RTJ 08/08/2021 Use inbond as BOL proxy for ZTZ transfers 	
--               Add country of export for ZTZ transfers 	
--               Add audit for missing receipt date 	
 	
--RTJ 08/08/2021 add handling for temporary deposits 	
--               + move temporary deposit errors to temporary_deposit_feed_errors table 	
--               + do not allow temporary deposit receipts to create inventory 	
 	
--RTJ 07/29/2021 add transferid to ztz_feed_errors table 	
 	
--RTJ 07/19/2021 include changes for zone-to-zone transfers 	
--               + errors are reported in ztz_feed_errors table 	
--               + records are added to the appropriate tables in the audit_ztz_feeds procedure 	
--               + records are deleted from the fed_receipts table in the audit_ztz_feeds procedure 	
--               + part numbers are found in the fed_parts table 	
--               + receipt quantities must be > zero; zone status must be provided 	
 	
--NKM 06/24/2021 Added inbond_number to receipts feed 	
--RTJ 05/05/2021 Pull audits for legitimacy of receipt corrections to separate procedure 	
--RTJ 04/10/2021 Audit for correct case number prefix 	
--RTJ 04/05/2021 Query new case numbers in ACE 	
--RTJ 04/03/2021 Add rate end date for AD/CVD case numbers 	
--RTJ 03/31/2021 Add handling for AD/CVD case numbers 	
--RTJ 03/31/2021 Add ftz_setting RECEIPT LINKING to handle automatic/manual linking of 	
--               receipts to conveyances 	
 	
--RTJ 03/11/2021 Insert missing MID codes into fed_vendors 	
--RTJ 03/03/2021 Removed audit for US country of origin on foreign receipt 	
--RTJ 02/16/2021 Add function to verify_country_code (and pull from master table) 	
--RTJ 02/15/2021 Removed 30 day receipt date audit 	
 	
--RTJ 01/24/2021 Do not default zone status to domestic 	
--               Refined error messages 	
--               added fed_record_identifier to feed_errors table 	
 	
--NKM 12/16/2020 Consolidated and expanded cleanup of varchar fields 	
--RTJ 11/18/2020 Query master manufacturer data for missing MID codes 	
 	
--RTJ 11/13/2020 Add logic for handling receipt corrections 	
--               Use variables for audit messages for ease of reference 	
--               Set empty user reference fields to null 	
 	
DECLARE 	
  rvrs                       RECORD; 	
  v_min_rcpt_id              INTEGER; 	
  v_min_rvrs_id              INTEGER; 	
  v_receipt_qty              NUMERIC; 	
  v_reversal_qty             NUMERIC; 	
  dprs                       RECORD; 	
  ccrs                       RECORD; --NKM 04/21/2023 	
 	
  --RTJ 11/13/2020 	
  v_table_name               VARCHAR(50) = 'fed_receipts'; 	
  v_update_count             INTEGER; 	
  v_kit_update_count         INTEGER; 	
  v_duplicate_msg            VARCHAR = 'Bypassed due to duplicate Transaction Reference'; 	
  v_missing_part_msg         VARCHAR = 'Part Number is missing'; 	
  v_invalid_part_msg         VARCHAR = 'Part Number is not in parts list'; 	
  v_foreign_kit_msg          VARCHAR = 'Kits may only be received as domestic - to receive kits in foreign status enter receipts for each component and then build the kit'; 	
  v_ztz_kit_msg              VARCHAR = 'Kits may not be received in a zone-to-zone transfer - to receive these goods enter receipts for each component and then build the kit'; 	
  v_td_kit_msg               VARCHAR = 'Kits may not be received as a temporary deposit - to receive these goods as a temporary deposit enter receipts for each component'; 	
  v_missing_qty_msg          VARCHAR = 'Receipt quantity is missing'; 	
  v_negative_qty_msg         VARCHAR = 'Correction receipt cannot have negative quantity'; 	
  v_invalid_kit_qty_msg      VARCHAR = 'Kits may only be received in positive integer quantities'; --NKM 03/25/2024 	
  v_invalid_status_msg       VARCHAR = 'Zone Status must be D, N, P or Z'; 	
  v_invalid_coo_msg          VARCHAR = 'Missing or invalid Country Of Origin'; 	
  --v_coo_mismatch_msg       VARCHAR = 'US country of origin on foreign status receipt';  --RTJ 03/03/2021 	
  v_missing_mid_msg          VARCHAR = 'Manufacturer is missing or not in vendor list'; 	
  v_invalid_mid_msg          VARCHAR = 'Manufacturer is neither a known vendor nor a valid MID code'; --NKM 03/18/2022 	
  v_receipt_date_audit       NUMERIC = 30; 	
  --v_invalid_rcpt_dt_msg      VARCHAR = 'Receipt Date is missing or older than 30 days'; 	
  v_invalid_rcpt_dt_msg      VARCHAR = 'Receipt Date is missing'; 	
  v_invalid_price_msg        VARCHAR = 'Unit Price is missing, zero or negative'; 	
  v_missing_proxy_msg        VARCHAR = 'Missing conveyance information (BOL/HBOL or proxy)'; 	
  v_missing_inbond_msg       VARCHAR = 'Missing in-bond number - enter NONE for no in-bond'; 	
  v_invalid_inbond_msg       VARCHAR = 'Invalid in-bond number format'; 	
  urs                        RECORD; 	
  --RTJ 11/13/2020 	
 	
  crs                        RECORD;  --RTJ 03/31/2021 	
  v_case_msg                 VARCHAR;  --RTJ 04/05/2021 	
  -- KK 11/19/2024 - remove audits for countervailing and antidumping 	
  --  v_domestic_ad_case_msg     VARCHAR = 'Domestic goods do not require antidumping case numbers';  --NKM 03/25/2024 	
  --  v_domestic_cv_case_msg     VARCHAR = 'Domestic goods do not require countervailing case numbers';  --NKM 03/25/2024 	
  v_case_error               BOOLEAN;  --RTJ 04/05/2021 	
--NKM 02/25/2022  v_case_suffix_needed       VARCHAR = 'Case Number suffix required';  --RTJ 04/05/2021 	
--NKM 02/25/2022  v_inactive_case            VARCHAR = 'Case Number is not currently active';  --RTJ 04/05/2021 	
--NKM 02/25/2022  v_invalid_case             VARCHAR = 'Case Number is invalid';  --RTJ 04/05/2021 	
--NKM 02/25/2022  v_waiting_case             VARCHAR = 'Waiting for Case Number response from ABI';  --RTJ 04/05/2021 	
--NKM 02/25/2022  v_invalid_case_prefix_a    VARCHAR = 'Antidumping Case Number must begin with A';  --RTJ 04/10/2021 	
--NKM 02/25/2022  v_invalid_case_prefix_c    VARCHAR = 'Countervailing Case Number must begin with C';  --RTJ 04/10/2021 	
  v_ztz_require_proxy        BOOLEAN; --NKM 04/10/2022 	
  v_require_inbonds          BOOLEAN; --NKM 06/24/2021 	
 	
  --RTJ 07/19/2021 	
  v_ztz_negative_qty_msg     VARCHAR = 'ZTZ transfer quantity must be greater than zero'; 	
  v_ztz_missing_part_msg     VARCHAR = 'Part Number is missing from the ZTZ transfer data'; 	
  v_ztz_invalid_coe_msg      VARCHAR = 'Invalid Country Of Export';  --RTJ 08/06/2021 	
  v_ztz_missing_proxy_msg    VARCHAR = 'A BOL proxy is required to match this receipt to a transfer record'; --NKM 04/10/2022 	
  --RTJ 07/19/2021 	
 	
  v_pre_negative_qty_msg     VARCHAR = 'Pre-receipt quantity must be greater than zero'; --NKM 05/03/2022 	
 	
  v_temporary_deposit_msg    VARCHAR = 'Temporary Deposit receipt held since: ';  --RTJ 08/04/2021 	
  v_concurred_e214_msg       VARCHAR = 'Zone Admission Number is for a concurred e214';  --RTJ 11/01/2021 	
  v_missing_ztz_inbond_msg   VARCHAR = 'Missing in-bond number for zone-to-zone transfer';  --RTJ 11/08/2021 	
  v_missing_alu_license_msg  VARCHAR = 'An aluminum import license is required for these goods'; --NKM 02/02/2022 	
  v_missing_stl_license_msg  VARCHAR = 'A steel import license is required for these goods'; --NKM 02/02/2022 	
  v_unknown_license_msg      VARCHAR = 'A license is not expected for this receipt - contact support if a license is required'; --NKM 03/18/2022 	
 	
  conrs                      RECORD;  --NKM 05/31/2022 	
  v_current_admission_no     VARCHAR(10) DEFAULT NULL; 	
  v_update_admission_no      VARCHAR(10) DEFAULT NULL; 	
 	
  v_tol                      DOUBLE PRECISION DEFAULT preftz.get_ftz_setting('ROUNDOFF TOLERANCE'); --NKM 07/12/2022 	
  v_invalid_assist_msg       VARCHAR = 'Unit Assist is negative';  --RTJ 01/19/2023 	
  v_domestic_assist_msg      VARCHAR = 'Domestic goods may not have a unit assist';  --NKM 03/25/2024 	
 	
  v_valid_country            VARCHAR(5); --NKM 04/21/2023 consolidated auditing of all country code fields 	
 	
  v_unexpected_cast_and_smelt_msg  VARCHAR = 'Cast and Smelt data is not required for this part'; 	
  v_missing_cast_msg         VARCHAR = 'Missing Country of Cast'; 	
  v_missing_1smelt_msg       VARCHAR = 'Missing Primary Country of Smelt (Enter a valid 2-character ISO country code or N/A)'; 	
  v_missing_2smelt_msg       VARCHAR = 'Missing Secondary Country of Smelt (Enter a valid 2-character ISO country code or N/A)'; 	
  v_incomplete_smelt_msg     VARCHAR = 'The Primary and Secondary Countres of Smelt are required when the Country of Cast is entered'; 	
  v_invalid_cast_msg         VARCHAR = 'Invalid Country of Cast'; 	
  v_invalid_1smelt_msg       VARCHAR = 'Invalid Primary Country of Smelt (Enter a valid 2-character ISO country code or N/A)'; 	
  v_invalid_2smelt_msg       VARCHAR = 'Invalid Secondary Country of Smelt (Enter a valid 2-character ISO country code or N/A)'; 	
  v_invalid_na_1smelt_msg    VARCHAR = 'The Primary Country of Smelt may not be N/A unless the Secondary Country of Smelt is also N/A'; 	
 	
  v_invalid_kit_date_msg     VARCHAR = 'The receipt date is greater than the date this Kit Part was removed.'; 	
  v_steel_percent_msg        VARCHAR = 'Steel percentage is required for SECTION232 derivatives'; 	
  v_alu_percent_msg          VARCHAR = 'Aluminum percentage is required for SECTION232 derivatives'; 	
  v_copper_percent_msg       VARCHAR = 'Copper percentage is required for SECTION232 derivatives'; 	
  v_missing_melt_msg         VARCHAR = 'Missing Country of Melt.'; 	
  v_missing_pour_msg         VARCHAR = 'Missing Country of Pour'; 	
  v_invalid_melt_msg         VARCHAR = 'Invalid Country of Melt.'; 	
  v_invalid_pour_msg         VARCHAR = 'Invalid Country of Pour'; 	
   	
  v_e214status_msg           VARCHAR = 'Actual receipt could not be linked because pre-receipts exist on an unauthorized admission'; 	
  v_pre_receipt_msg          VARCHAR = 'PRE-receipts already were removed for this BOL_proxy'; 	
  v_pre_receipt_mix_msg      VARCHAR = 'PRE-receipts mixed with receipts on the same feed'; 	
  v_pre_receipt_mix_msg_2    VARCHAR = 'Not proccessed PRE-receipts exist for incoming receipts'; 	
  v_pre_receipt_mix_msg_3    VARCHAR = 'Receipts exist for incoming PRE-receipts'; 	
  v_pre_receipt_filed_msg    VARCHAR = 'Cannot add pre-receipt for already FILED/AUTHORIZED e214 with same BOL_proxy #'; 	

  v_usmca_percent_us_value_msg VARCHAR = 'USMCA Percent U.S. Value must be between 0 - 100; Enter in whole number percentage.';
   	
 	
  v_total_count              INTEGER; -- NO 12/04/2025 	
   	
  v_concur_status     VARCHAR(26); 	
  v_count             INTEGER; 	
  v_conveyanceid      INTEGER; 	
  v_e214_status       VARCHAR(26); 	
  v_zone_admission_no VARCHAR(10); 	
  v_inbond_number     VARCHAR(12);  	
   	
   	
 	
BEGIN 	
    INSERT INTO preftz.system_log (procedure_name,log_message) 	
        VALUES ('audit_fed_receipts','started'); 	
 	
-- EG 4/7/2026 	
    IF (SELECT  coalesce(preftz.get_ftz_setting('AUTO CONCUR'),'NO') = 'AUTO_LINK_CONCUR')  	
    THEN  	
       CALL preftz.link_receipts_to_conveyances_by_inbond(); 	
       CALL preftz.assign_zone_admission(); 	
       CALL preftz.pre_receipts_filing(); 	
    END IF; 	
-- EG 4/7/2026 	
 	
    -- NO 12/03/2025 Create temp table to limit processing to single receipt if param provided, 	
    -- use temp table count as guard clause (specific id passed in, not found in fed_receipts) 	
    DROP TABLE IF EXISTS temp_audit_receipts; 	
 	
    CREATE TEMPORARY TABLE temp_audit_receipts(receiptid INTEGER PRIMARY KEY); 	
 	
    -- KK 01/13/2026 Add ability to process a batch of receipts from fed_receipts. 	
    IF p_use_selected_receipts IS TRUE THEN 	
      INSERT INTO temp_audit_receipts(receiptid) 	
      SELECT receiptid FROM preftz.selected_fed_receipts; 	
 	
      DELETE FROM preftz.selected_fed_receipts 	
      WHERE receiptid IN (SELECT receiptid FROM temp_audit_receipts); 	
 	
      IF (SELECT COUNT(fr.receiptid) 	
          FROM preftz.fed_receipts fr 	
          JOIN temp_audit_receipts tar ON tar.receiptid = fr.receiptid) = 0 THEN 	
        RAISE NOTICE 'Nothing to process from selected_fed_receipts, exiting.'; 	
        INSERT INTO preftz.system_log (procedure_name,log_message) 	
        VALUES ('audit_fed_receipts', 'Nothing to process from selected_fed_receipts, exiting.'); 	
        RETURN; 	
      END IF; 	
      RAISE NOTICE 'Processing receipts in selected_fed_receipts...'; 	
    ELSE 	
      INSERT INTO temp_audit_receipts 	
        SELECT receiptid FROM preftz.fed_receipts; 	
      RAISE NOTICE 'Processing all receipts in fed_receipts...'; 	
    END IF; 	
 	
    SELECT COUNT(*) INTO v_total_count FROM temp_audit_receipts; 	
 	
    IF v_total_count = 0 THEN 	
      INSERT INTO preftz.system_log (procedure_name,log_message) 	
        VALUES ('audit_fed_receipts', 'Nothing to do, exiting.'); 	
      RETURN; 	
    END IF; 	
 	
    INSERT INTO preftz.system_log (procedure_name, log_message) 	
    SELECT 'audit_fed_receipts', 'RECORD COUNT TO PROCESS ' || TO_CHAR(COUNT(*),'999999') 	
      FROM temp_audit_receipts; 	
 	
    -- ONLY DELETE ERRORS FOR RECORDS BEING PROCESSED 	
    DELETE FROM preftz.feed_errors fe 	
      USING temp_audit_receipts tar 	
      WHERE fe.table_name = v_table_name 	
        AND fe.tableid = tar.receiptid; 	
 	
    DELETE FROM preftz.ztz_feed_errors zfe 	
      USING temp_audit_receipts tar 	
      WHERE zfe.table_name = v_table_name 	
        AND zfe.tableid = tar.receiptid; 	
 	
    DELETE FROM preftz.temporary_deposit_feed_errors te 	
      USING temp_audit_receipts tar 	
      WHERE te.table_name = v_table_name 	
        AND te.tableid = tar.receiptid; 	
 	
    DELETE FROM preftz.fed_receipts 	
      WHERE fed_status = 'DUPLICATE'; 	
    GET DIAGNOSTICS v_update_count = ROW_COUNT; 	
 	
    INSERT INTO preftz.system_log (procedure_name, log_message) 	
    VALUES ('audit_fed_receipts', 'PREVIOUS DUPLICATES ' || TO_CHAR(v_update_count,'999999')); 	
 	
    UPDATE preftz.fed_receipts fe 	
      SET fed_status = 'AUDITING', 	
          import_license_type = NULL 	
      FROM temp_audit_receipts tar 	
      WHERE fe.receiptid = tar.receiptid; 	
 	
    COMMIT; 	
 	
    --NKM 12/16/2020 Consolidated and expanded cleanup varchar fields 	
    --Capitalize, remove spaces, and/or set '' to NULL as appropriate 	
    UPDATE preftz.fed_receipts fr 	
       SET part_number = NULLIF(TRIM(UPPER(part_number)),''), 	
           quantity = preftz.roundto(quantity, 0., v_tol), --NKM 07/12/2022 	
           unit_price = preftz.roundto(unit_price, 0., v_tol), --NKM 07/12/2022 	
           unit_assist = preftz.roundto(unit_assist, 0., v_tol),  --RTJ 01/19/2023 	
           manufacturer_mid_code = NULLIF(TRIM(UPPER(manufacturer_mid_code)),''), 	
           country_of_origin = NULLIF(TRIM(UPPER(country_of_origin)),''), 	
           bill_of_lading_airwaybill = NULLIF(UPPER(regexp_replace(bill_of_lading_airwaybill,'[^A-Za-z0-9]','','g')),''), 	
           house_bill = NULLIF(UPPER(regexp_replace(house_bill,'[^A-Za-z0-9]','','g')),''), 	
           house_bill_partial_indicator = NULLIF(TRIM(UPPER(house_bill_partial_indicator)),''), 	
           bill_of_lading_proxy = NULLIF(TRIM(UPPER(bill_of_lading_proxy)),''), 	
           transaction_reference = NULLIF(TRIM(UPPER(transaction_reference)),''), 	
           zone_status = NULLIF(TRIM(UPPER(zone_status)),''), 	
           foreign_unit_price = preftz.roundto(foreign_unit_price, 0., v_tol), --NKM 07/12/2022 	
           currency_code = NULLIF(TRIM(UPPER(currency_code)),''), 	
           currency_exchange_rate = preftz.roundto(currency_exchange_rate, 0., v_tol), --NKM 07/12/2022 	
           user_reference1 = NULLIF(TRIM(user_reference1),''), 	
           user_reference2 = NULLIF(TRIM(user_reference2),''), 	
           user_reference3 = NULLIF(TRIM(user_reference3),''), 	
           user_reference4 = NULLIF(TRIM(user_reference4),''), 	
           user_reference5 = NULLIF(TRIM(user_reference5),''), 	
           antidumping_case_number = NULLIF(TRIM(UPPER(antidumping_case_number)),''),  --RTJ 03/31/2021 	
           countervailing_case_number = NULLIF(TRIM(UPPER(countervailing_case_number)),''),  --RTJ 03/31/2021 	
           inbond_number = NULLIF(TRIM(UPPER(regexp_replace(inbond_number,'[^A-Za-z0-9]','','g'))),''),  --NKM 06/24/2021 --08/25/2022 	
           temporary_deposit = NULLIF(TRIM(UPPER(temporary_deposit)),''),  --RTJ 08/04/2021 	
           zone_to_zone_transfer = NULLIF(TRIM(UPPER(zone_to_zone_transfer)),''),  --RTJ 11/08/2021 	
           import_license_number = NULLIF(TRIM(UPPER(import_license_number)),''), --NKM 02/02/2022 	
           country_of_cast = NULLIF(TRIM(UPPER(country_of_cast)),''),                      --NKM 04/21/2023 	
           primary_country_of_smelt = NULLIF(TRIM(UPPER(primary_country_of_smelt)),''),    --NKM 04/21/2023 	
           secondary_country_of_smelt = NULLIF(TRIM(UPPER(secondary_country_of_smelt)),''), --NKM 04/21/2023 	
           country_of_melt = NULLIF(TRIM(UPPER(country_of_melt)),''), -- KK 04/17/2025 	
           country_of_pour = NULLIF(TRIM(UPPER(country_of_pour)),''), -- KK 04/17/2025 	
           steel_content_weight = preftz.roundto(steel_content_weight, 0., v_tol),       -- KK 04/06/2026 	
           aluminum_content_weight = preftz.roundto(aluminum_content_weight, 0., v_tol), -- KK 04/06/2026 	
           copper_content_weight = preftz.roundto(copper_content_weight, 0., v_tol),     -- KK 04/06/2026 	
           usmca_percent_us_value = preftz.roundto(usmca_percent_us_value, 0., v_tol)     -- KK 07/03/2026 
        WHERE fr.fed_status = 'AUDITING'; 	
 	
    -- update COO, MMC, ZS from parts_defaults if values are null 	
    UPDATE preftz.fed_receipts fr 	
    SET manufacturer_mid_code = pd.mmc, 	
        country_of_origin = pd.coo, 	
        zone_status = pd.zn 	
    FROM ( 	
        SELECT fr.receiptid, COALESCE(fr.country_of_origin, pd.country_of_origin) AS coo, 	
            COALESCE(fr.manufacturer_mid_code, pd.manufacturer_mid_code) AS mmc, 	
            COALESCE(fr.zone_status, pd.zone_status) AS zn 	
        FROM preftz.fed_receipts fr 	
        JOIN preftz.parts_defaults pd ON pd.part_number = fr.part_number 	
        WHERE fr.fed_status = 'AUDITING' 	
    ) pd 	
    WHERE pd.receiptid = fr.receiptid; 	
 	
    -- update cast/smelt if values are null 	
    UPDATE preftz.fed_receipts fr 	
    SET country_of_cast = pd.country_of_cast, 	
        primary_country_of_smelt = pd.primary_country_of_smelt, 	
        secondary_country_of_smelt = pd.secondary_country_of_smelt 	
    FROM ( 	
        SELECT fr.receiptid, 	
               COALESCE(fr.country_of_cast, pd.country_of_cast) country_of_cast, 	
               COALESCE(fr.primary_country_of_smelt, pd.primary_country_of_smelt) primary_country_of_smelt, 	
               COALESCE(fr.secondary_country_of_smelt, pd.secondary_country_of_smelt) secondary_country_of_smelt 	
          FROM preftz.fed_receipts fr 	
          JOIN preftz.parts_defaults pd ON pd.part_number = fr.part_number 	
         WHERE fr.fed_status = 'AUDITING' 	
           AND fr.country_of_cast IS NULL 	
           AND fr.primary_country_of_smelt IS NULL 	
           AND fr.secondary_country_of_smelt IS NULL 	
    ) pd 	
    WHERE pd.receiptid = fr.receiptid; 	
 	
    -- update melt/pour if values are null 	
    UPDATE preftz.fed_receipts fr 	
    SET country_of_melt = pd.country_of_melt, 	
        country_of_pour = pd.country_of_pour 	
    FROM ( 	
        SELECT fr.receiptid, 	
               COALESCE(fr.country_of_melt, pd.country_of_melt) country_of_melt, 	
               COALESCE(fr.country_of_pour, pd.country_of_pour) country_of_pour 	
          FROM preftz.fed_receipts fr 	
          JOIN preftz.parts_defaults pd ON pd.part_number = fr.part_number 	
         WHERE fr.fed_status = 'AUDITING' 	
           AND fr.country_of_melt IS NULL 	
           AND fr.country_of_pour IS NULL 	
    ) pd 	
    WHERE pd.receiptid = fr.receiptid; 	
 	
    -- update metal content weights from parts_defaults 	
    -- ONLY if ALL three values are null in fed table AND there are no existing values in receipt_derivative_content 	
    UPDATE preftz.fed_receipts fr 	
    SET steel_content_weight = pd.steel_content_weight, 	
        aluminum_content_weight = pd.aluminum_content_weight, 	
        copper_content_weight = pd.copper_content_weight 	
    FROM ( 	
        SELECT fr.receiptid, COALESCE(pd.steel_content_weight,0) AS steel_content_weight, 	
            COALESCE(pd.aluminum_content_weight,0) AS aluminum_content_weight, 	
            COALESCE(pd.copper_content_weight,0) AS copper_content_weight 	
        FROM preftz.fed_receipts fr 	
        JOIN preftz.parts_defaults pd ON pd.part_number = fr.part_number 	
            AND (pd.steel_content_weight IS NOT NULL 	
                OR pd.aluminum_content_weight IS NOT NULL 	
                OR pd.copper_content_weight IS NOT NULL) 	
        LEFT JOIN preftz.receipt_derivative_content rdc ON rdc.receiptid = fr.receiptid 	
        WHERE fr.fed_status = 'AUDITING' 	
            AND fr.steel_content_weight IS NULL  -- no values specified for any weights in fed table 	
            AND fr.aluminum_content_weight IS NULL 	
            AND fr.copper_content_weight IS NULL 	
            AND rdc.receiptid IS NULL  -- no existing row for this receiptid 	
    ) pd 	
    WHERE pd.receiptid = fr.receiptid; 	
 	
    COMMIT; 	
 	
    UPDATE preftz.fed_receipts 	
      SET temporary_deposit = NULL 	
        WHERE temporary_deposit <> 'Y' -- RTJ 08/04/2021 	
          AND fed_status = 'AUDITING'; -- NO 12/03/2025 	
 	
    UPDATE preftz.fed_receipts 	
      SET zone_to_zone_transfer = NULL 	
      WHERE zone_to_zone_transfer <> 'Y' --RTJ 11/08/2021 	
        AND fed_status = 'AUDITING'; -- NO 12/03/2025 	
 	
    -- KK 07/18/2025 Create new part_number(s) where we have a new lot in fed_receipts. 	
    IF EXISTS ( 	
        SELECT 'x' 	
        FROM preftz.fed_receipts fr 	
          WHERE part_number like '%$%' 	
            AND fr.fed_status = 'AUDITING' -- NO 12/03/2025 	
    ) THEN 	
        CALL preftz.create_part_for_new_lots(); 	
    END IF; 	
 	
    --RTJ 11/13/2020 	
    --check for correction records (regular_receipts) 	
    UPDATE preftz.fed_receipts fr 	
       SET fed_status = 'UPDATE' 	
      FROM preftz.receipts r 	
     WHERE fr.receiptid = r.receiptid 	
       AND fr.fed_status = 'AUDITING'; 	
    GET DIAGNOSTICS v_update_count = ROW_COUNT;  --RTJ 05/05/2021 	
 	
    --NKM 03/25/2024 	
    --check for correction records (kit_receipts) 	
    UPDATE preftz.fed_receipts fr 	
       SET fed_status = 'KIT_UPDATE' 	
      FROM preftz.kit_receipts kr 	
     WHERE fr.receiptid = kr.receiptid 	
       AND fr.fed_status = 'AUDITING'; 	
    GET DIAGNOSTICS v_kit_update_count = ROW_COUNT; 	
 	
    --RTJ 05/05/2021 Move audits for legitimacy of correction records to separate procedure 	
    IF v_update_count >= 1 OR v_kit_update_count >= 1 THEN 	
        CALL preftz.audit_receipt_corrections(); 	
    END IF; 	
    --RTJ 05/05/2021 	
 	
    --check for duplicate transaction_reference (previous receipts) 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'transaction_reference', 	
           v_duplicate_msg, fr.transaction_reference, fr.part_number 	
      FROM preftz.fed_receipts fr 	
           LEFT JOIN preftz.receipts r 	
                  ON fr.transaction_reference = r.transaction_reference 	
           LEFT JOIN preftz.kit_receipts kr 	
                  ON fr.transaction_reference = kr.transaction_reference 	
     WHERE fr.transaction_reference IS NOT NULL 	
       AND (   fr.fed_status = 'AUDITING'                                         --RTJ 11/13/2020 	
            OR (fr.fed_status = 'UPDATE' AND r.receiptid <> fr.receiptid)         --NKM 03/25/2024 	
            OR (fr.fed_status = 'KIT_UPDATE' AND kr.receiptid <> fr.receiptid))   --NKM 03/25/2024 	
       AND (r.receiptid IS NOT NULL OR kr.receiptid IS NOT NULL); --NKM 05/21/2024 	
 	
    UPDATE preftz.fed_receipts fr 	
       SET fed_status = 'DUPLICATE' 	
      FROM preftz.receipts r 	
     WHERE fr.transaction_reference = r.transaction_reference 	
       AND fr.transaction_reference IS NOT NULL 	
       AND (    fr.fed_status = 'AUDITING'                                 --RTJ 11/13/2020 	
            OR (fr.fed_status = 'UPDATE' AND r.receiptid <> fr.receiptid)); --NKM 03/25/2024 	
 	
    UPDATE preftz.fed_receipts fr 	
       SET fed_status = 'DUPLICATE' 	
      FROM preftz.kit_receipts kr 	
     WHERE fr.transaction_reference = kr.transaction_reference 	
       AND fr.transaction_reference IS NOT NULL 	
       AND (    fr.fed_status = 'AUDITING'                                 --RTJ 11/13/2020 	
            OR (fr.fed_status = 'KIT_UPDATE' AND kr.receiptid <> fr.receiptid)); --NKM 03/25/2024 	
 	
    --check for duplicate transaction_reference (same file) 	
    FOR dprs IN SELECT MIN(fr.receiptid) min_receipt_id, fr.transaction_reference 	
                  FROM preftz.fed_receipts fr 	
                 WHERE fr.fed_status = 'AUDITING'  --RTJ 05/11/2020 	
                   AND fr.transaction_reference IS NOT NULL 	
                 GROUP BY fr.transaction_reference 	
                HAVING count(*) > 1 	
    LOOP 	
        INSERT INTO preftz.feed_errors 	
               (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
         SELECT v_table_name, fr.receiptid, 'transaction_reference', 	
                v_duplicate_msg, fr.transaction_reference, fr.part_number 	
           FROM preftz.fed_receipts fr 	
          WHERE fr.transaction_reference = dprs.transaction_reference 	
            AND fr.receiptid > dprs.min_receipt_id 	
            AND fr.fed_status IN ('AUDITING', 'KIT_UPDATE', 'UPDATE');  --NO 12/03/2025 	
 	
        UPDATE preftz.fed_receipts fr 	
           SET fed_status = 'DUPLICATE' 	
         WHERE fr.transaction_reference = dprs.transaction_reference 	
           AND fr.receiptid > dprs.min_receipt_id 	
           AND fr.fed_status IN ('AUDITING', 'KIT_UPDATE', 'UPDATE');  --NO 12/03/2025 	
    END LOOP; 	
 	
    --check for reversals (exclude ztz transfers, temporary deposits, and pre_receipts) 	
    FOR rvrs IN 	
        SELECT DISTINCT fr.part_number, fr.country_of_origin, fr.unit_price, fr.manufacturer_mid_code, 	
               COALESCE(fr.bill_of_lading_airwaybill,fr.bill_of_lading_proxy,'NULL') bol, 	
               COALESCE(fr.commercial_invoice_number,'NULL') invoice, COALESCE(fr.inbond_number,'NULL') inbond, 	
               COALESCE(fr.import_license_number,'NULL') import_license, 	
               COALESCE(fr.country_of_cast,'NULL') country_of_cast,           --NKM 04/21/2023 	
               COALESCE(fr.primary_country_of_smelt,'NULL') primary_smelt,    --NKM 04/21/2023 	
               COALESCE(fr.secondary_country_of_smelt,'NULL') secondary_smelt --NKM 04/21/2023 	
          FROM preftz.fed_receipts fr 	
               INNER JOIN preftz.fed_receipts frv 	
                       ON fr.part_number = frv.part_number 	
                      AND COALESCE(fr.country_of_origin,'') = COALESCE(frv.country_of_origin,'') 	
                      AND fr.unit_price = frv.unit_price --NKM 07/12/2022 unit price must be exact for a reversal (no tolerance) 	
                      AND fr.manufacturer_mid_code = frv.manufacturer_mid_code 	
                      AND COALESCE(fr.bill_of_lading_airwaybill,fr.bill_of_lading_proxy,'NULL') = 	
                          COALESCE(frv.bill_of_lading_airwaybill,frv.bill_of_lading_proxy,'NULL') 	
                      AND COALESCE(fr.commercial_invoice_number,'NULL') = COALESCE(frv.commercial_invoice_number,'NULL') 	
                      AND COALESCE(fr.inbond_number,'NULL') = COALESCE(frv.inbond_number,'NULL') 	
                      AND COALESCE(fr.import_license_number,'NULL') = COALESCE(frv.import_license_number,'NULL') 	
                      AND COALESCE(fr.country_of_cast,'NULL') = COALESCE(frv.country_of_cast,'NULL') 	
                      AND COALESCE(fr.primary_country_of_smelt,'NULL') = COALESCE(frv.primary_country_of_smelt,'NULL') 	
                      AND COALESCE(fr.secondary_country_of_smelt,'NULL') = COALESCE(frv.secondary_country_of_smelt,'NULL') 	
         WHERE fr.fed_status = 'AUDITING'  --RTJ 11/13/2020 	
           AND frv.fed_status = 'AUDITING'  --RTJ 11/13/2020 	
           AND COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y'   --NKM 03/18/2022 	
           AND COALESCE(frv.zone_to_zone_transfer,'N') <> 'Y'   --NKM 03/18/2022 	
           AND fr.temporary_deposit IS NULL  --RTJ 08/04/2021 	
           AND frv.temporary_deposit IS NULL  --RTJ 08/04/2021 	
           AND fr.quantity > 0 --NKM 07/12/2022 assumes quantity rounded to 0 at start of procedure 	
           AND frv.quantity < 0 --NKM 07/12/2022 assumes quantity rounded to 0 at start of procedure 	
           AND fr.pre_receipt IS NOT TRUE     --NKM 05/03/2022 	
           AND frv.pre_receipt IS NOT TRUE    --NKM 05/03/2022 	
    LOOP 	
        SELECT MIN(fr.receiptid), SUM(fr.quantity) 	
          INTO v_min_rcpt_id, v_receipt_qty 	
          FROM preftz.fed_receipts fr 	
         WHERE fr.fed_status = 'AUDITING'  --RTJ 11/13/2020 	
           AND fr.part_number = rvrs.part_number 	
           AND COALESCE(fr.country_of_origin,'') = COALESCE(rvrs.country_of_origin,'') 	
           AND fr.unit_price = rvrs.unit_price 	
           AND fr.manufacturer_mid_code = rvrs.manufacturer_mid_code 	
           AND COALESCE(fr.bill_of_lading_airwaybill,fr.bill_of_lading_proxy,'NULL') = rvrs.bol 	
           AND COALESCE(fr.commercial_invoice_number,'NULL') = rvrs.invoice 	
           AND COALESCE(fr.inbond_number,'NULL') = rvrs.inbond 	
           AND COALESCE(fr.import_license_number,'NULL') = rvrs.import_license 	
           AND COALESCE(fr.country_of_cast,'NULL') = rvrs.country_of_cast 	
           AND COALESCE(fr.primary_country_of_smelt,'NULL') = rvrs.primary_smelt 	
           AND COALESCE(fr.secondary_country_of_smelt,'NULL') = rvrs.secondary_smelt 	
           AND COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y'   --NKM 03/18/2022 	
           AND fr.temporary_deposit IS NULL           --NKM 03/18/2022 	
           AND fr.quantity > 0 --NKM 07/12/2022 assumes quantity rounded to 0 at start of procedure 	
           AND fr.pre_receipt IS NOT TRUE;    --NKM 05/03/2022 	
 	
        SELECT MIN(fr.receiptid), SUM(fr.quantity) 	
          INTO v_min_rvrs_id, v_reversal_qty 	
          FROM preftz.fed_receipts fr 	
         WHERE fr.fed_status = 'AUDITING'  --RTJ 11/13/2020 	
           AND fr.part_number = rvrs.part_number 	
           AND COALESCE(fr.country_of_origin,'') = COALESCE(rvrs.country_of_origin,'') 	
           AND fr.unit_price = rvrs.unit_price 	
           AND fr.manufacturer_mid_code = rvrs.manufacturer_mid_code 	
           AND COALESCE(fr.bill_of_lading_airwaybill,fr.bill_of_lading_proxy,'NULL') = rvrs.bol 	
           AND COALESCE(fr.commercial_invoice_number,'NULL') = rvrs.invoice 	
           AND COALESCE(fr.inbond_number,'NULL') = rvrs.inbond 	
           AND COALESCE(fr.import_license_number,'NULL') = rvrs.import_license 	
           AND COALESCE(fr.country_of_cast,'NULL') = rvrs.country_of_cast 	
           AND COALESCE(fr.primary_country_of_smelt,'NULL') = rvrs.primary_smelt 	
           AND COALESCE(fr.secondary_country_of_smelt,'NULL') = rvrs.secondary_smelt 	
           AND COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y'   --NKM 03/18/2022 	
           AND fr.temporary_deposit IS NULL           --NKM 03/18/2022 	
           AND fr.quantity < 0 --NKM 07/12/2022 assumes quantity rounded to 0 at start of procedure 	
           AND fr.pre_receipt IS NOT TRUE;    --NKM 05/03/2022 	
 	
        -- where receipt = reversal, bypass all 	
        IF preftz.isequal(ABS(v_reversal_qty), v_receipt_qty, v_tol) THEN --NKM 07/12/2022 	
            UPDATE preftz.fed_receipts fr 	
               SET fed_status = 'PROCESSED' 	
             WHERE fr.fed_status = 'AUDITING'  --RTJ 11/13/2020 	
               AND fr.part_number = rvrs.part_number 	
               AND COALESCE(fr.country_of_origin,'') = COALESCE(rvrs.country_of_origin,'') 	
               AND fr.unit_price = rvrs.unit_price 	
               AND fr.manufacturer_mid_code = rvrs.manufacturer_mid_code 	
               AND COALESCE(fr.bill_of_lading_airwaybill,fr.bill_of_lading_proxy,'NULL') = rvrs.bol 	
               AND COALESCE(fr.commercial_invoice_number,'NULL') = rvrs.invoice 	
               AND COALESCE(fr.inbond_number,'NULL') = rvrs.inbond 	
               AND COALESCE(fr.import_license_number,'NULL') = rvrs.import_license 	
               AND COALESCE(fr.country_of_cast,'NULL') = rvrs.country_of_cast 	
               AND COALESCE(fr.primary_country_of_smelt,'NULL') = rvrs.primary_smelt 	
               AND COALESCE(fr.secondary_country_of_smelt,'NULL') = rvrs.secondary_smelt 	
               AND COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y'   --NKM 03/18/2022 	
               AND fr.temporary_deposit IS NULL           --NKM 03/18/2022 	
               AND fr.pre_receipt IS NOT TRUE;    --NKM 05/03/2022 	
 	
        -- where receipt > reversal, create decreased receipt, bypass all others 	
        ELSIF preftz.isgreater(v_receipt_qty, ABS(v_reversal_qty), v_tol) THEN --NKM 07/12/2022 	
            v_receipt_qty = v_receipt_qty + v_reversal_qty; 	
 	
            UPDATE preftz.fed_receipts fr 	
               SET fed_status = 'PROCESSED' 	
             WHERE fr.fed_status = 'AUDITING'  --RTJ 11/13/2020 	
               AND fr.part_number = rvrs.part_number 	
               AND COALESCE(fr.country_of_origin,'') = COALESCE(rvrs.country_of_origin,'') 	
               AND fr.unit_price = rvrs.unit_price 	
               AND fr.manufacturer_mid_code = rvrs.manufacturer_mid_code 	
               AND COALESCE(fr.bill_of_lading_airwaybill,fr.bill_of_lading_proxy,'NULL') = rvrs.bol 	
               AND COALESCE(fr.commercial_invoice_number,'NULL') = rvrs.invoice 	
               AND COALESCE(fr.inbond_number,'NULL') = rvrs.inbond 	
               AND COALESCE(fr.import_license_number,'NULL') = rvrs.import_license 	
               AND COALESCE(fr.country_of_cast,'NULL') = rvrs.country_of_cast 	
               AND COALESCE(fr.primary_country_of_smelt,'NULL') = rvrs.primary_smelt 	
               AND COALESCE(fr.secondary_country_of_smelt,'NULL') = rvrs.secondary_smelt 	
               AND COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y'   --NKM 03/18/2022 	
               AND fr.temporary_deposit IS NULL           --NKM 03/18/2022 	
               AND fr.pre_receipt IS NOT TRUE;    --NKM 05/03/2022 	
 	
            INSERT INTO preftz.fed_receipts 	
                  (part_number, receipt_date, quantity, unit_price, manufacturer_mid_code, 	
                   country_of_origin, bill_of_lading_airwaybill, house_bill, 	
                   house_bill_partial_indicator, bill_of_lading_proxy, commercial_invoice_number, 	
                   transaction_reference, zone_admission_no, zone_status, foreign_unit_price, 	
                   currency_code, currency_exchange_rate, user_reference1, user_reference2, 	
                   user_reference3, user_reference4, user_reference5, conveyanceid, 	
                   antidumping_case_number, countervailing_case_number, inbond_number,  --RTJ 03/31/2021 	
                   import_license_number, unit_assist, --NKM 02/02/2022 / RTJ 01/19/2023 	
                   country_of_cast, primary_country_of_smelt, secondary_country_of_smelt) --NKM 04/21/2023 	
            SELECT fr.part_number, fr.receipt_date, v_receipt_qty, fr.unit_price, fr.manufacturer_mid_code, 	
                   fr.country_of_origin, fr.bill_of_lading_airwaybill, fr.house_bill, 	
                   fr.house_bill_partial_indicator, fr.bill_of_lading_proxy, fr.commercial_invoice_number, 	
                   fr.transaction_reference, fr.zone_admission_no, fr.zone_status, fr.foreign_unit_price, 	
                   fr.currency_code, fr.currency_exchange_rate, fr.user_reference1, fr.user_reference2, 	
                   fr.user_reference3, fr.user_reference4, COALESCE(fr.user_reference5, 'PARTIAL REVERSAL'), 	
                   fr.conveyanceid, fr.antidumping_case_number, fr.countervailing_case_number, fr.inbond_number, --RTJ 03/31/2021 	
                   fr.import_license_number, fr.unit_assist, --NKM 02/02/2022 / RTJ 01/19/2023 	
                   fr.country_of_cast, fr.primary_country_of_smelt, fr.secondary_country_of_smelt  --NKM 04/21/2023 	
              FROM preftz.fed_receipts fr 	
             WHERE fr.receiptid = v_min_rcpt_id; 	
 	
        -- where receipt < reversal, create decreased reversal, bypass all others 	
        ELSIF preftz.isgreater(ABS(v_reversal_qty), v_receipt_qty, v_tol) THEN --NKM 07/12/2022 	
            v_reversal_qty = v_reversal_qty + v_receipt_qty; 	
 	
            UPDATE preftz.fed_receipts fr 	
               SET fed_status = 'PROCESSED' 	
             WHERE fr.fed_status = 'AUDITING'  --RTJ 11/13/2020 	
               AND fr.part_number = rvrs.part_number 	
               AND COALESCE(fr.country_of_origin,'') = COALESCE(rvrs.country_of_origin,'') 	
               AND fr.unit_price = rvrs.unit_price 	
               AND fr.manufacturer_mid_code = rvrs.manufacturer_mid_code 	
               AND COALESCE(fr.bill_of_lading_airwaybill,fr.bill_of_lading_proxy,'NULL') = rvrs.bol 	
               AND COALESCE(fr.commercial_invoice_number,'NULL') = rvrs.invoice 	
               AND COALESCE(fr.inbond_number,'NULL') = rvrs.inbond 	
               AND COALESCE(fr.import_license_number,'NULL') = rvrs.import_license 	
               AND COALESCE(fr.country_of_cast,'NULL') = rvrs.country_of_cast 	
               AND COALESCE(fr.primary_country_of_smelt,'NULL') = rvrs.primary_smelt 	
               AND COALESCE(fr.secondary_country_of_smelt,'NULL') = rvrs.secondary_smelt 	
               AND COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y'   --NKM 03/18/2022 	
               AND fr.temporary_deposit IS NULL           --NKM 03/18/2022 	
               AND fr.pre_receipt IS NOT TRUE;    --NKM 05/03/2022 	
 	
            INSERT INTO preftz.fed_receipts 	
                  (part_number, receipt_date, quantity, unit_price, manufacturer_mid_code, 	
                   country_of_origin, bill_of_lading_airwaybill, house_bill, 	
                   house_bill_partial_indicator, bill_of_lading_proxy, commercial_invoice_number, 	
                   transaction_reference, zone_admission_no, zone_status, foreign_unit_price, 	
                   currency_code, currency_exchange_rate, user_reference1, user_reference2, 	
                   user_reference3, user_reference4, user_reference5, conveyanceid, 	
                   antidumping_case_number, countervailing_case_number, inbond_number,  --RTJ 03/31/2021 	
                   import_license_number, unit_assist, --NKM 02/02/2022 / RTJ 01/19/2023 	
                   country_of_cast, primary_country_of_smelt, secondary_country_of_smelt) --NKM 04/21/2023 	
            SELECT fr.part_number, fr.receipt_date, v_reversal_qty, fr.unit_price, fr.manufacturer_mid_code, 	
                   fr.country_of_origin, fr.bill_of_lading_airwaybill, fr.house_bill, 	
                   fr.house_bill_partial_indicator, fr.bill_of_lading_proxy, fr.commercial_invoice_number, 	
                   fr.transaction_reference, fr.zone_admission_no, fr.zone_status, fr.foreign_unit_price, 	
                   fr.currency_code, fr.currency_exchange_rate, fr.user_reference1, fr.user_reference2, 	
                   fr.user_reference3, fr.user_reference4, COALESCE(fr.user_reference5, 'OVER REVERSAL'), 	
                   fr.conveyanceid, fr.antidumping_case_number, fr.countervailing_case_number, fr.inbond_number, --RTJ 03/31/2021 	
                   fr.import_license_number, unit_assist, --NKM 02/02/2022 / RTJ 01/19/2023 	
                   fr.country_of_cast, fr.primary_country_of_smelt, fr.secondary_country_of_smelt  --NKM 04/21/2023 	
              FROM preftz.fed_receipts fr 	
             WHERE fr.receiptid = v_min_rvrs_id; 	
 	
        END IF; 	
    END LOOP; 	
 	
    --RTJ 11/01/2021 check for 214 in concurred status 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'receiptid', v_concurred_e214_msg, fr.zone_admission_no, fr.part_number 	
      FROM preftz.fed_receipts fr 	
           INNER JOIN preftz.e214_filing_statuses efs 	
                   ON fr.zone_admission_no = efs.zone_admission_no 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND COALESCE(efs.concur_status,'') NOT IN ('','REJECTED'); --NKM 10/03/2022 	
 	
    --update e214 filing status for all associated un-concurred 214s 	
    FOR urs IN 	
        SELECT DISTINCT fr.zone_admission_no 	
          FROM preftz.fed_receipts fr 	
               INNER JOIN preftz.e214_filing_statuses efs 	
                       ON fr.zone_admission_no = efs.zone_admission_no 	
         WHERE fr.fed_status IN ('AUDITING','UPDATE','ERROR') 	
           AND COALESCE(efs.concur_status,'') IN ('','REJECTED') --NKM 10/03/2022 	
           AND COALESCE(efs.e214_status,'') <> '' 	
    LOOP 	
        CALL preftz.update_e214_after_create(urs.zone_admission_no); --NKM 10/03/2022 	
    END LOOP; 	
    --RTJ 11/01/2021 	
 	
    --part_number 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'part_number', v_missing_part_msg, fr.part_number, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND fr.part_number IS NULL; 	
 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'part_number', 	
           CASE WHEN kp.part_number IS NULL THEN v_invalid_part_msg ELSE v_foreign_kit_msg END, 	
           fr.part_number, fr.part_number 	
      FROM preftz.fed_receipts fr 	
           LEFT JOIN preftz.parts_activation_view p   -- KK converted kits 	
                  ON fr.part_number = p.part_number 	
                 AND fr.receipt_date > p.activation_date   -- KK converted kits 	
           LEFT JOIN preftz.kit_parts kp                   --NKM 02/12/2024 	
                  ON fr.part_number = kp.part_number 	
                 AND (kp.removed_date IS NULL OR kp.removed_date > fr.receipt_date)  --KK kits at time of receipt_date 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND fr.part_number IS NOT NULL 	
       AND p.part_number IS NULL 	
       AND (kp.part_number IS NULL OR fr.zone_status <> 'D'); --NKM 03/25/2024 	
 	
 	
    -- KK 04/17/2025 - steel percentage SECTION232 requirements 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier, action_code) 	
    SELECT DISTINCT v_table_name, fr.receiptid, 'steel derivative percentage', v_steel_percent_msg, null, fr.part_number, 'PARTEXTMISS' 	
    FROM preftz.fed_receipts fr 	
    JOIN preftz.part_classifications pc ON pc.part_number = fr.part_number AND pc.tariff_type = 'BASE' 	
    JOIN preftz.additional_tariff_derivatives a 	
        ON a.tariff_prefix = SUBSTR(pc.harmonized_tariff_schedule_number,1,LENGTH(a.tariff_prefix)) 	
        AND NOT pc.harmonized_tariff_schedule_number LIKE ANY(COALESCE(a.exception_tariff_prefixes,'{}'::TEXT[])) 	
        AND (a.country_of_origin = fr.country_of_origin OR a.country_of_origin = 'ALL') 	
        AND NOT fr.country_of_origin LIKE ANY(COALESCE(a.exception_countries,'{}'::TEXT[])) 	
        AND a.tariff_type = 'SECTION232' 	
        AND CURRENT_DATE BETWEEN a.start_date AND a.end_date 	
        AND LOWER(notes) LIKE 'iron_steel%' 	
     LEFT JOIN preftz.derivative_parts_content dpc ON dpc.part_number = fr.part_number 	
        AND CURRENT_TIMESTAMP BETWEEN dpc.start_date AND dpc.end_date 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
        AND COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y'  --not required for zone_to_zone_transfer 	
        AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
        AND fr.temporary_deposit IS NULL         --not required for temporary deposit 	
        AND fr.pre_receipt IS NOT TRUE           --not required for a pre-receipt 	
        AND dpc.steel_percentage IS NULL; 	
 	
    -- KK 04/17/2025 - aluminum percentage SECTION232 requirements 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier, action_code) 	
    SELECT DISTINCT v_table_name, fr.receiptid, 'aluminum derivative percentage', v_alu_percent_msg, null, fr.part_number, 'PARTEXTMISS' 	
    FROM preftz.fed_receipts fr 	
    JOIN preftz.part_classifications pc ON pc.part_number = fr.part_number AND pc.tariff_type = 'BASE' 	
    JOIN preftz.additional_tariff_derivatives a 	
        ON a.tariff_prefix = SUBSTR(pc.harmonized_tariff_schedule_number,1,LENGTH(a.tariff_prefix)) 	
        AND NOT pc.harmonized_tariff_schedule_number LIKE ANY(COALESCE(a.exception_tariff_prefixes,'{}'::TEXT[])) 	
        AND (a.country_of_origin = fr.country_of_origin OR a.country_of_origin = 'ALL') 	
        AND NOT fr.country_of_origin LIKE ANY(COALESCE(a.exception_countries,'{}'::TEXT[])) 	
        AND a.tariff_type = 'SECTION232' 	
        AND CURRENT_DATE BETWEEN a.start_date AND a.end_date 	
        AND LOWER(notes) LIKE 'aluminum%' 	
     LEFT JOIN preftz.derivative_parts_content dpc ON dpc.part_number = fr.part_number 	
        AND CURRENT_TIMESTAMP BETWEEN dpc.start_date AND dpc.end_date 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
        AND COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y'  --not required for zone_to_zone_transfer 	
        AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
        AND fr.temporary_deposit IS NULL         --not required for temporary deposit 	
        AND fr.pre_receipt IS NOT TRUE           --not required for a pre-receipt 	
        AND dpc.aluminum_percentage IS NULL; 	
 	
    -- KK 08/01/2025 - copper percentage SECTION232 requirements 	
    INSERT INTO preftz.feed_errors 	
            (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier, action_code) 	
    SELECT DISTINCT v_table_name, fr.receiptid, 'copper derivative percentage', v_copper_percent_msg, null, fr.part_number, 'PARTEXTMISS' 	
    FROM preftz.fed_receipts fr 	
    JOIN preftz.part_classifications pc ON pc.part_number = fr.part_number AND pc.tariff_type = 'BASE' 	
    JOIN preftz.additional_tariff_derivatives a 	
        ON a.tariff_prefix = SUBSTR(pc.harmonized_tariff_schedule_number,1,LENGTH(a.tariff_prefix)) 	
        AND NOT pc.harmonized_tariff_schedule_number LIKE ANY(COALESCE(a.exception_tariff_prefixes,'{}'::TEXT[])) 	
        AND (a.country_of_origin = fr.country_of_origin OR a.country_of_origin = 'ALL') 	
        AND NOT fr.country_of_origin LIKE ANY(COALESCE(a.exception_countries,'{}'::TEXT[])) 	
        AND a.tariff_type = 'SECTION232' 	
        AND CURRENT_DATE BETWEEN a.start_date AND a.end_date 	
        AND LOWER(notes) LIKE 'copper%' 	
        LEFT JOIN preftz.derivative_parts_content dpc ON dpc.part_number = fr.part_number 	
        AND CURRENT_TIMESTAMP BETWEEN dpc.start_date AND dpc.end_date 	
        WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
        AND COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y'  --not required for zone_to_zone_transfer 	
        AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
        AND fr.temporary_deposit IS NULL         --not required for temporary deposit 	
        AND fr.pre_receipt IS NOT TRUE           --not required for a pre-receipt 	
        AND dpc.copper_percentage IS NULL; 	
 	
    --ztz kits - forbidden 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'part_number', v_ztz_kit_msg, fr.part_number, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
      JOIN preftz.kit_parts kp ON kp.part_number = fr.part_number 	
       AND (kp.removed_date IS NULL OR kp.removed_date > fr.receipt_date)  --KK kits at time of receipt_date 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND fr.zone_to_zone_transfer = 'Y'; 	
 	
    --temporary deposit kits - forbidden 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'part_number', v_td_kit_msg, fr.part_number, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
      JOIN preftz.kit_parts kp ON kp.part_number = fr.part_number 	
       AND (kp.removed_date IS NULL OR kp.removed_date > fr.receipt_date)  --KK kits at time of receipt_date 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND fr.temporary_deposit = 'Y'; 	
 	
    --quantity 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'quantity', v_missing_qty_msg, fr.quantity, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') --NKM 03/25/2024 	
       AND fr.quantity IS NULL; 	
 	
    --RTJ 07/19/2021  ztz quantity cannot be negative or zero 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'quantity', v_ztz_negative_qty_msg, fr.quantity, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status = 'AUDITING' 	
       AND COALESCE(fr.zone_to_zone_transfer,'N') = 'Y'   --NKM 03/18/2022 	
       AND fr.quantity <= 0; --NKM 07/12/2022 assumes quantity rounded to 0 at start of procedure 	
    --RTJ 07/19/2021 	
 	
    --NKM 05/03/2022  pre_receipt quantity cannot be negative or zero 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'quantity', v_pre_negative_qty_msg, fr.quantity, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status = 'AUDITING' 	
       AND fr.pre_receipt IS TRUE 	
       AND fr.quantity <= 0; --NKM 07/12/2022 assumes quantity rounded to 0 at start of procedure 	
 	
    --RTJ 11/13/2020 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'quantity', v_negative_qty_msg, fr.quantity, fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status IN ('UPDATE','KIT_UPDATE') --NKM 03/25/2024 	
       AND fr.quantity < 0; --NKM 07/12/2022 assumes quantity rounded to 0 at start of procedure 	
    --RTJ 11/13/2020 	
 	
    --quantity for kits must be a positive integer --NKM 03/25/2024 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'quantity', v_invalid_kit_qty_msg, fr.quantity, fr.part_number 	
      FROM preftz.fed_receipts fr 	
      JOIN preftz.kit_parts kp ON fr.part_number = kp.part_number 	
       AND (kp.removed_date IS NULL OR kp.removed_date > fr.receipt_date)  --KK kits at time of receipt_date 	
     WHERE fr.fed_status IN ('AUDITING','KIT_UPDATE') 	
       AND (fr.quantity <> fr.quantity::INTEGER  --true equals (no roundoff allowed) 	
            OR fr.quantity <= 0); --assumes quantity rounded to 0 at start of procedure 	
 	
    --zone_status 	
    UPDATE preftz.fed_receipts fr 	
       SET zone_status = p.zone_status 	
      FROM preftz.parts_activation_view p   -- KK converted kits 	
     WHERE fr.part_number = p.part_number 	
       AND fr.receipt_date > p.activation_date   -- KK converted kits 	
       AND fr.fed_status IN ('AUDITING','UPDATE') 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR fr.pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fr.zone_status IS NULL 	
       AND p.zone_status <> 'D'; 	
 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'zone_status', v_invalid_status_msg, fr.zone_status, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') --NKM 03/25/2024 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND COALESCE(fr.zone_status,'X') NOT IN ('D','N','P','Z'); 	
 	
    --country_of_origin 	
    UPDATE preftz.fed_receipts fr 	
       SET country_of_origin = 'US' 	
     WHERE fr.zone_status = 'D' 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fr.country_of_origin IS NULL 	
       AND fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE'); 	
 	
    --US country_of_origin (kits) --NKM 03/25/2024 	
    UPDATE preftz.fed_receipts fr 	
       SET country_of_origin = 'US' 	
      FROM preftz.kit_parts kp 	
     WHERE kp.part_number = fr.part_number 	
       AND fr.zone_status = 'D' 	
       AND (kp.removed_date IS NULL OR kp.removed_date > fr.receipt_date)  --KK kits at time of receipt_date 	
       AND fr.fed_status IN ('AUDITING','KIT_UPDATE'); 	
 	
    --Validate all country code fields (assures all valid codes are in the preftz table) NKM 04/21/2023 	
    --Ugly check for status to enable optional single query paramater, might revisit later NO 12/03/2025 	
    FOR ccrs IN SELECT country_of_origin AS country_code 	
                  FROM preftz.fed_receipts 	
                  WHERE fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') --NO 12/03/2025 	
                 UNION 	
                SELECT country_of_cast AS country_code 	
                  FROM preftz.fed_receipts 	
                  WHERE fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') --NO 12/03/2025 	
                 UNION 	
                SELECT LEFT(primary_country_of_smelt,2) AS country_code 	
                  FROM preftz.fed_receipts 	
                 WHERE primary_country_of_smelt <> 'N/A' 	
                   AND fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') --NO 12/03/2025 	
                 UNION 	
                SELECT LEFT(secondary_country_of_smelt,2) AS country_code 	
                  FROM preftz.fed_receipts 	
                 WHERE primary_country_of_smelt <> 'N/A' 	
                   AND fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') --NO 12/03/2025 	
    LOOP 	
        v_valid_country = preftz.verify_country_code(ccrs.country_code); 	
    END LOOP; 	
 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'country_of_origin', v_invalid_coo_msg, fr.country_of_origin, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
      LEFT JOIN preftz.countries c ON c.iso_country_code = fr.country_of_origin 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND c.iso_country_code IS NULL; --NKM 04/21/2023 Logic above assures all valid country codes are in the preftz table 	
 	
    --RTJ 03/03/2021 There are situations under which a US country of origin is valid for a foreign receipt 	
    --INSERT INTO preftz.feed_errors 	
    --      (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    --SELECT v_table_name, fr.receiptid, 'country_of_origin', v_coo_mismatch_msg, fr.country_of_origin, 	
    --       fr.part_number 	
    --  FROM preftz.fed_receipts fr 	
    -- WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
    --   AND fr.zone_status <> 'D' 	
    --   AND fr.country_of_origin = 'US'; 	
    --RTJ 03/03/2021 	
 	
    --manufacturer_mid_code 	
    UPDATE preftz.fed_receipts fr 	
       SET manufacturer_mid_code = v.manufacturer_id_code 	
      FROM preftz.vendors v 	
     WHERE (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fr.manufacturer_mid_code = v.vendor_code 	
       AND NOT EXISTS (SELECT 'x' FROM preftz.manufacturer_identification_codes m 	
                        WHERE fr.manufacturer_mid_code = m.manufacturer_id_code) 	
       AND fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE'); --NO 12/03/2025 	
 	
    --RTJ 11/18/2020 	
    --pull MID codes from master table where possible 	
    INSERT INTO preftz.manufacturer_identification_codes 	
          (manufacturer_id_code, firm_name, street, city, iso_country_code, zip_or_postal_code) 	
    SELECT DISTINCT micm.manufacturer_id_code, micm.firm_name, micm.street, micm.city, 	
           micm.iso_country_code, micm.zip_or_postal_code 	
      FROM preftz.fed_receipts fr 	
            LEFT JOIN preftz.manufacturer_identification_codes m 	
                   ON fr.manufacturer_mid_code = m.manufacturer_id_code 	
           INNER JOIN prehts.manufacturer_identification_codes_master micm 	
                   ON fr.manufacturer_mid_code = micm.manufacturer_id_code 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') 	
       AND m.manufacturer_id_code IS NULL; 	
    --RTJ 11/18/2020 	
 	
    --missing MID code 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'manufacturer_mid_code', v_missing_mid_msg, fr.manufacturer_mid_code, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
           LEFT JOIN preftz.manufacturer_identification_codes m 	
                  ON fr.manufacturer_mid_code = m.manufacturer_id_code 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND COALESCE(fr.zone_status,'X') <> 'D' 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND m.manufacturer_id_code IS NULL; 	
 	
    --invalid MID code 	
    --NKM 03/18/2022 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'manufacturer_mid_code', v_invalid_mid_msg, fr.manufacturer_mid_code, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
           LEFT JOIN prehts.countries_master c 	
                   ON LEFT(fr.manufacturer_mid_code,2) = c.iso_country_code 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND COALESCE(fr.zone_status,'X') <> 'D' 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fr.manufacturer_mid_code IS NOT NULL 	
       AND (c.iso_country_code IS NULL 	
            OR NOT LENGTH(fr.manufacturer_mid_code) BETWEEN 6 AND 15); 	
    --NKM 03/18/2022 	
 	
    --DOMESTIC MID code --NKM 04/21/2023 	
    UPDATE preftz.fed_receipts fr 	
       SET manufacturer_mid_code = 'DOMESTIC' --overwrite MID code to DOMESTIC if it's not a known MID code 	
      FROM preftz.fed_receipts fr2 	
           LEFT JOIN preftz.manufacturer_identification_codes m 	
                  ON fr2.manufacturer_mid_code = m.manufacturer_id_code 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') 	
       AND fr.zone_status = 'D' 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR fr.pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fr2.receiptid = fr.receiptid 	
       AND m.manufacturer_id_code IS NULL;    --No match in MID codes table 	
 	
    --DOMESTIC MID code (kits) --NKM 03/25/2024 	
    UPDATE preftz.fed_receipts fr 	
       SET manufacturer_mid_code = 'DOMESTIC' --overwrite MID code to DOMESTIC for kits with 'D' status 	
      FROM preftz.kit_parts kp 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') 	
       AND fr.zone_status = 'D' 	
       AND (kp.removed_date IS NULL OR kp.removed_date > fr.receipt_date)  --KK kits at time of receipt_date 	
       AND fr.part_number = kp.part_number; 	
 	
    --RTJ 03/11/2021 add MID to fed_vendors if begins with a valid country code 	
    INSERT INTO preftz.fed_vendors (vendor_code, manufacturer_id_code) 	
    SELECT DISTINCT fr.manufacturer_mid_code, fr.manufacturer_mid_code 	
      FROM preftz.fed_receipts fr 	
            LEFT JOIN preftz.manufacturer_identification_codes m 	
                   ON fr.manufacturer_mid_code = m.manufacturer_id_code 	
            LEFT JOIN preftz.fed_vendors v 	
                   ON fr.manufacturer_mid_code = v.manufacturer_id_code 	
           INNER JOIN prehts.countries_master c 	
                   ON LEFT(fr.manufacturer_mid_code,2) = c.iso_country_code 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND COALESCE(fr.zone_status,'X') <> 'D' 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND LENGTH(fr.manufacturer_mid_code) BETWEEN 6 AND 15 --NKM 03/18/2022 	
       AND m.manufacturer_id_code IS NULL 	
       AND v.manufacturer_id_code IS NULL; 	
    --RTJ 03/11/2021 	
 	
    --RTJ 02/15/2021 removed day-count audit until it can be included in ftz_settings 	
    --receipt_date 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'receipt_date', v_invalid_rcpt_dt_msg, fr.receipt_date, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') --RTJ 11/13/2020 	
       AND fr.receipt_date IS NULL; 	
       --AND DATE_PART('day',current_date - COALESCE(fr.receipt_date,'01/01/1900')) > v_receipt_date_audit; 	
 	
    -- make sure updated receipt_date isn't after Kit had been removed 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'receipt_date', v_invalid_kit_date_msg, fr.receipt_date, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
      JOIN preftz.kit_parts kp ON kp.part_number = fr.part_number 	
     WHERE fr.fed_status IN ('KIT_UPDATE') 	
       AND fr.receipt_date > kp.removed_date ; 	
 	
    --price 	
    UPDATE preftz.fed_receipts fr 	
       SET unit_price = foreign_unit_price * currency_exchange_rate 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND COALESCE(fr.unit_price,0) <= 0             --NKM 07/12/2022 assumes unit_price was rounded to 0 at start of procedure 	
       AND COALESCE(fr.foreign_unit_price,0) > 0      --NKM 07/12/2022 assumes foreign_unit_price was rounded to 0 at start of procedure 	
       AND COALESCE(fr.currency_exchange_rate,0) > 0; --NKM 07/12/2022 assumes currency_exchange_rate was rounded to 0 at start of procedure 	
 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'unit_price', v_invalid_price_msg, fr.unit_price, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND COALESCE(fr.unit_price,0) <= 0; --NKM 07/12/2022 assumes unit_price was rounded to 0 at start of procedure 	
 	
    --RTJ 01/19/2023  unit assist 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'unit_assist', v_invalid_assist_msg, fr.unit_assist, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND COALESCE(fr.unit_assist,0) < 0; 	
    --RTJ 01/19/2023 	
 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'unit_assist', v_domestic_assist_msg, fr.unit_assist, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') 	
       AND fr.unit_assist IS NOT NULL 	
       AND fr.zone_status = 'D'; 	
 	
    --conveyance 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'bill_of_lading_proxy', v_missing_proxy_msg, fr.bill_of_lading_proxy, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND COALESCE(fr.zone_status,'X') <> 'D' 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fr.bill_of_lading_proxy IS NULL 	
       AND fr.bill_of_lading_airwaybill IS NULL; 	
 	
    --NKM 04/10/2022 Get ztz setting 	
    v_ztz_require_proxy=((preftz.get_ftz_setting('ZTZ MATCH ON PROXY') = 'YES') IS TRUE); 	
 	
    --NKM 04/10/2022 ztz missing required proxy 	
    IF v_ztz_require_proxy THEN 	
      INSERT INTO preftz.feed_errors 	
            (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
      SELECT v_table_name, fr.receiptid, 'bill_of_lading_proxy', v_ztz_missing_proxy_msg, fr.bill_of_lading_proxy, 	
             fr.part_number 	
        FROM preftz.fed_receipts fr 	
       WHERE fr.fed_status  = 'AUDITING' 	
         AND COALESCE(fr.zone_to_zone_transfer,'N') = 'Y'   --NKM 12/18/2023 zone-to-zone receipts 	
         AND pre_receipt IS NOT TRUE                        --NKM 12/18/2023 N/A for pre-receipts 	
         AND COALESCE(fr.bill_of_lading_proxy,'') = '';     --no proxy 	
    END IF; 	
 	
 	
    --NKM 06/24/2021 Get inbond setting 	
    v_require_inbonds=((preftz.get_ftz_setting('REQUIRE INBONDS') = 'REQUIRED') IS NOT FALSE); 	
 	
    --missing in-bond --NKM 06/24/2021 	
    IF v_require_inbonds THEN 	
      INSERT INTO preftz.feed_errors 	
            (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
      SELECT v_table_name, fr.receiptid, 'inbond_number', v_missing_inbond_msg, fr.inbond_number, 	
             fr.part_number 	
        FROM preftz.fed_receipts fr 	
       WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
         AND COALESCE(fr.zone_status,'X') <> 'D' 	
         AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
         AND COALESCE(fr.bill_of_lading_proxy,'') = ''       --not needed if using a proxy NKM 03/18/2022 	
         AND COALESCE(fr.inbond_number,'') = ''; 	
    END IF; 	
 	
    --invalid in-bond format (N/A if inbond_number is NULL) --NKM 06/24/2021 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'inbond_number', v_invalid_inbond_msg, fr.inbond_number, 	
           fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND COALESCE(fr.zone_status,'X') <> 'D' 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND NOT (fr.inbond_number IS NULL 	
            OR COALESCE(fr.inbond_number,'') ~ '^NONE$'    --No In-bond 	
            OR COALESCE(fr.inbond_number,'') ~ '^[0-9]{9}$'      --CBP-assigned In-bond 	
            OR COALESCE(fr.inbond_number,'') ~ '^V[0-9A-Z]{10}$' --AMS Paperless In-bond 	
            OR(COALESCE(fr.inbond_number,'') ~ '^[0-9]{11}$' 	
               AND COALESCE(fr.inbond_number,'') = COALESCE(fr.bill_of_lading_airwaybill,fr.inbond_number,''))); --Air Waybill 	
 	
    --RTJ 03/31/2021 antidumping_case_number/countervailing_case_number 	
    --where possible, add the appropriate suffix to the case number 	
    FOR crs IN 	
        SELECT LEFT(REPLACE(q.case_number,'-',''),7) case_prefix, COUNT(*) suffix_count 	
          FROM (SELECT DISTINCT acr.case_number 	
                  FROM preftz.ad_cvd_case_reference acr 	
                 WHERE CURRENT_DATE >= acr.rate_effective_date 	
                   AND CURRENT_DATE <= acr.rate_end_date  --RTJ 04/03/2021 	
                   AND acr.case_status = 'ACTIVE') q 	
         GROUP BY LEFT(REPLACE(q.case_number,'-',''),7) 	
        HAVING COUNT(*) = 1 	
    LOOP 	
        UPDATE preftz.fed_receipts fr 	
           SET antidumping_case_number = acr.case_number 	
          FROM preftz.ad_cvd_case_reference acr 	
         WHERE (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
           AND REPLACE(fr.antidumping_case_number,'-','') = crs.case_prefix 	
           AND LEFT(REPLACE(acr.case_number,'-',''),7) = crs.case_prefix 	
           AND CURRENT_DATE >= acr.rate_effective_date 	
           AND CURRENT_DATE <= acr.rate_end_date  --RTJ 04/03/2021 	
           AND acr.case_status = 'ACTIVE' 	
           AND fr.receiptid IN (SELECT receiptid FROM temp_audit_receipts); --NO 12/04/2025 	
 	
 	
        UPDATE preftz.fed_receipts fr 	
           SET countervailing_case_number = acr.case_number 	
          FROM preftz.ad_cvd_case_reference acr 	
         WHERE (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
           AND REPLACE(fr.countervailing_case_number,'-','') = crs.case_prefix 	
           AND LEFT(REPLACE(acr.case_number,'-',''),7) = crs.case_prefix 	
           AND CURRENT_DATE >= acr.rate_effective_date 	
           AND CURRENT_DATE <= acr.rate_end_date  --RTJ 04/03/2021 	
           AND acr.case_status = 'ACTIVE' 	
           AND fr.receiptid IN (SELECT receiptid FROM temp_audit_receipts); --NO 12/04/2025 	
 	
    END LOOP; 	
 	
    --RTJ 04/05/2021 	
    FOR crs IN SELECT DISTINCT q.fed_case_number, q.case_type FROM 	
        (SELECT REPLACE(fr.antidumping_case_number,'-','') fed_case_number, 	
                'A' case_type 	
          FROM preftz.fed_receipts fr 	
         WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
           AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
           AND COALESCE(fr.zone_status,'X') <> 'D' 	
           AND COALESCE(fr.antidumping_case_number,'') <> '' 	
        UNION 	
        SELECT REPLACE(fr.countervailing_case_number,'-','') fed_case_number, 	
               'C' case_type 	
          FROM preftz.fed_receipts fr 	
         WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
           AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
           AND COALESCE(fr.zone_status,'X') <> 'D' 	
           AND COALESCE(fr.countervailing_case_number,'') <> '') q 	
    LOOP 	
 	
        --NKM 03/18/2022 	
        v_case_msg = preftz.audit_case_number(crs.fed_case_number, crs.case_type); --NKM 03/18/2022 	
        v_case_error = (v_case_msg IS NOT NULL);                                   --NKM 03/18/2022 --NKM 04/27/2022 	
 	
        IF v_case_error THEN 	
            INSERT INTO preftz.feed_errors 	
                  (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
            SELECT DISTINCT v_table_name, fr.receiptid, 'antidumping_case_number', v_case_msg, 	
                   fr.antidumping_case_number, fr.part_number 	
              FROM preftz.fed_receipts fr 	
             WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
               AND COALESCE(fr.zone_status,'X') <> 'D' 	
               AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
               AND COALESCE(fr.antidumping_case_number,'') <> '' 	
               AND REPLACE(fr.antidumping_case_number,'-','') = crs.fed_case_number; 	
 	
            INSERT INTO preftz.feed_errors 	
                  (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
            SELECT DISTINCT v_table_name, fr.receiptid, 'countervailing_case_number', v_case_msg, 	
                   fr.countervailing_case_number, fr.part_number 	
              FROM preftz.fed_receipts fr 	
             WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
               AND COALESCE(fr.zone_status,'X') <> 'D' 	
               AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
               AND COALESCE(fr.countervailing_case_number,'') <> '' 	
               AND REPLACE(fr.countervailing_case_number,'-','') = crs.fed_case_number; 	
        END IF; 	
    END LOOP; 	
 	
    -- KK 11/19/2024 - remove audits for countervailing and antidumping 	
    -- --case numbers for domestic receipts - not allowed --NKM 03/25/2024 	
    -- INSERT INTO preftz.feed_errors 	
    --       (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    -- SELECT DISTINCT v_table_name, fr.receiptid, 'antidumping_case_number', v_domestic_ad_case_msg, 	
    --        fr.antidumping_case_number, fr.part_number 	
    --   FROM preftz.fed_receipts fr 	
    --  WHERE fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') 	
    --    AND fr.zone_status = 'D' 	
    --    AND COALESCE(fr.antidumping_case_number,'') <> ''; 	
 	
    -- INSERT INTO preftz.feed_errors 	
    --       (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    -- SELECT DISTINCT v_table_name, fr.receiptid, 'countervailing_case_number', v_domestic_cv_case_msg, 	
    --        fr.countervailing_case_number, fr.part_number 	
    --   FROM preftz.fed_receipts fr 	
    --  WHERE fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') 	
    --    AND fr.zone_status = 'D' 	
    --    AND COALESCE(fr.countervailing_case_number,'') <> ''; 	
    -- --RTJ 03/31/2021/RTJ 04/05/2021 	
 	
    CALL preftz.query_case_numbers(); --NKM 03/18/2022 	
 	
    --NKM 02/02/2022 determine import_license_type - overwrites any existing value 	
    UPDATE preftz.fed_receipts fr 	
       SET import_license_type = CASE WHEN htsr.miscellaneous_permit_license_indicator = '01' THEN 'STL' 	
                                      WHEN htsr.miscellaneous_permit_license_indicator = '28' THEN 'ALU' 	
                                      ELSE NULL 	
                                      END 	
      FROM preftz.part_classifications pc, preftz.harmonized_tariff_schedule_reference htsr 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND ((COALESCE(fr.zone_status,'X') <> 'D'  --license not required for domestic goods 	
           AND fr.temporary_deposit IS NULL         --license not required for temporary deposit 	
           AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE))  --NKM 03/18/2022 --NKM 06/28/2023 	
           OR fr.import_license_number IS NOT NULL)   -- KK 11/14/2024 	
       AND pc.part_number = fr.part_number 	
       AND htsr.tariff_number = pc.harmonized_tariff_schedule_number 	
       AND pc.tariff_type = 'BASE' 	
       AND fr.receipt_date BETWEEN htsr.record_begin_effective_date AND htsr.record_end_effective_date 	
       AND htsr.miscellaneous_permit_license_indicator IN ('01','28'); 	
 	
    --NKM 02/02/2022 required import license check 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'import_license_number', 	
           CASE WHEN fr.import_license_type = 'STL' THEN v_missing_stl_license_msg 	
                WHEN fr.import_license_type = 'ALU' THEN v_missing_alu_license_msg 	
                ELSE 'license error' END, 	
           fr.import_license_number, fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND fr.import_license_number IS NULL 	
       AND COALESCE(fr.zone_status,'X') <> 'D'  --license not required for domestic goods 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fr.temporary_deposit IS NULL         --license not required for temporary deposit 	
       AND fr.import_license_type IS NOT NULL;  --a requied license type was identified 	
 	
    --NKM 02/02/2022 unexpected import license check 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'import_license_number', 	
           v_unknown_license_msg, fr.import_license_number, fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') 	
       AND fr.import_license_number IS NOT NULL     --a license number is given 	
       AND fr.import_license_type IS NULL; 	
    -- KK 11/14/2024 - allow user to input license number even if not required 	
    --    AND (COALESCE(fr.zone_status,'X') = 'D'               --license not required for domestic goods 	
    --         OR (COALESCE(fr.zone_to_zone_transfer,'N') = 'Y' AND pre_receipt IS NOT TRUE)  --NKM 03/18/2022 zone-to-zone transfer --NKM 06/28/2023 	
    --         OR fr.temporary_deposit IS NOT NULL              --license not required for temporary deposit 	
    --         OR fr.import_license_type IS NULL);              --a requied license type was not identified 	
 	
    --Aluminum cast & smelt reporting START --NKM 04/21/2023 	
    -- KK 05/23/2025 create temp views for cast/smelt and melt/pour reporting and don't flag 0% derivatives. 	
    CREATE OR REPLACE TEMPORARY VIEW cast_and_smelt_reporting_fp_view AS 	
    WITH max_date_content AS ( 	
        SELECT dpc.part_number, MAX(dpc.start_date) as max_start_date 	
        FROM preftz.derivative_parts_content dpc 	
        JOIN preftz.fed_receipts fr ON fr.part_number = dpc.part_number 	
        GROUP BY dpc.part_number 	
    ), most_recent_part_content AS ( 	
        SELECT dpc.part_number, dpc.aluminum_percentage, dpc.start_date 	
        FROM preftz.derivative_parts_content dpc 	
        JOIN max_date_content md ON md.part_number = dpc.part_number 	
            AND md.max_start_date = dpc.start_date 	
    ), parts_needing_cast_smelt AS ( 	
        -- Aluminum Products 	
        SELECT pc.part_number, pc.harmonized_tariff_schedule_number AS tariff_number, rbh.category 	
        FROM preftz.fed_receipts fr 	
        JOIN preftz.part_classifications pc ON pc.part_number = fr.part_number 	
        JOIN preftz.reporting_by_hts rbh ON pc.harmonized_tariff_schedule_number LIKE rbh.tariff_prefix || '%' 	
            AND rbh.category = 'aluminum_product' 	
            AND fr.receipt_date BETWEEN rbh.start_date AND rbh.end_date 	
        WHERE pc.tariff_type = 'BASE' 	
        UNION 	
        -- Aluminum Derivatives; Exclude those parts that are 0% aluminum 	
        SELECT pc.part_number, pc.harmonized_tariff_schedule_number AS tariff_number, rbh.category 	
        FROM preftz.fed_receipts fr 	
        JOIN preftz.part_classifications pc ON pc.part_number = fr.part_number 	
        JOIN preftz.reporting_by_hts rbh ON pc.harmonized_tariff_schedule_number LIKE rbh.tariff_prefix || '%' 	
            AND rbh.category = 'aluminum_derivative' 	
            AND fr.receipt_date BETWEEN rbh.start_date AND rbh.end_date 	
        LEFT JOIN most_recent_part_content dpc ON dpc.part_number = pc.part_number 	
        WHERE pc.tariff_type = 'BASE' 	
            AND COALESCE(dpc.aluminum_percentage,1) > 0 	
    ) 	
    SELECT part_number, tariff_number, category 	
    FROM parts_needing_cast_smelt 	
    ORDER BY part_number; 	
 	
    --cast & smelt for US goods - PER CBP filers may report 'US' and 'N/A' for products of the US --NKM 04/21/2023 	
    UPDATE preftz.fed_receipts fr 	
       SET country_of_cast = COALESCE(fr.country_of_cast,'US'), 	
           primary_country_of_smelt = COALESCE(fr.primary_country_of_smelt,'N/A'), 	
           secondary_country_of_smelt = COALESCE(fr.secondary_country_of_smelt,'N/A') 	
      FROM cast_and_smelt_reporting_fp_view csr   -- KK 05/09/2025 	
     WHERE csr.part_number = fr.part_number 	
       AND fr.fed_status IN ('AUDITING','UPDATE') 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
       AND fr.temporary_deposit IS NULL         --not required for temporary deposit 	
       AND fr.pre_receipt IS NOT TRUE           --not required for a pre-receipt 	
       AND fr.country_of_origin = 'US'; 	
 	
    --Cast and smelt details provided when they are not required 	
    -- INSERT INTO preftz.feed_errors 	
    --       (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    -- SELECT v_table_name, fr.receiptid, 'country_of_cast/primary_smelt/secondary_smelt', 	
    --        v_unexpected_cast_and_smelt_msg, CONCAT_WS('/',fr.country_of_cast,fr.primary_country_of_smelt,fr.secondary_country_of_smelt), 	
    --        fr.part_number 	
    --   FROM preftz.fed_receipts fr 	
    --   JOIN cast_and_smelt_reporting_fp_view csr ON csr.part_number = fr.part_number  -- KK 05/09/2025 	
    --  WHERE fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE') 	
    --    AND (   country_of_cast IS NOT NULL          --country of cast or smelt is given 	
    --         OR NULLIF(primary_country_of_smelt,'N/A') IS NOT NULL 	
    --         OR NULLIF(secondary_country_of_smelt,'N/A') IS NOT NULL) 	
    --    AND (   csr.tariff_number IS NULL               --not required for this HTS 	
    --         OR (COALESCE(fr.zone_to_zone_transfer,'N') = 'Y' AND pre_receipt IS NOT TRUE)  --NKM 03/18/2022 zone-to-zone transfer --NKM 06/28/2023 	
    --         OR COALESCE(fr.zone_status,'X') = 'D'   --not required for domestic goods 	
    --         OR fr.temporary_deposit = 'Y'           --not required for temporary deposit 	
    --         OR fr.pre_receipt IS TRUE);             --not required for a pre-receipt 	
 	
    --Missing country_of_cast 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'country_of_cast', 	
           v_missing_cast_msg, fr.country_of_cast, fr.part_number 	
      FROM preftz.fed_receipts fr 	
      JOIN cast_and_smelt_reporting_fp_view csr ON csr.part_number = fr.part_number  -- KK 05/09/2025 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
       AND fr.temporary_deposit IS NULL         --not required for temporary deposit 	
       AND fr.pre_receipt IS NOT TRUE           --not required for a pre-receipt 	
       AND fr.country_of_cast IS NULL; 	
 	
    --Missing primary_country_of_smelt 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'primary_country_of_smelt', 	
           v_missing_1smelt_msg, fr.primary_country_of_smelt, fr.part_number 	
      FROM preftz.fed_receipts fr 	
      JOIN cast_and_smelt_reporting_fp_view csr ON csr.part_number = fr.part_number  -- KK 05/09/2025 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
       AND fr.temporary_deposit IS NULL         --not required for temporary deposit 	
       AND fr.pre_receipt IS NOT TRUE           --not required for a pre-receipt 	
       AND fr.primary_country_of_smelt IS NULL; 	
 	
    --Missing secondary_country_of_smelt 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'secondary_country_of_smelt', 	
           v_missing_2smelt_msg, fr.secondary_country_of_smelt, fr.part_number 	
      FROM preftz.fed_receipts fr 	
      JOIN cast_and_smelt_reporting_fp_view csr ON csr.part_number = fr.part_number  -- KK 05/09/2025 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
       AND fr.temporary_deposit IS NULL         --not required for temporary deposit 	
       AND fr.pre_receipt IS NOT TRUE           --not required for a pre-receipt 	
       AND fr.secondary_country_of_smelt IS NULL; 	
 	
    --Cast data provided without smelt data 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'countries of primary_smelt/secondary_smelt', 	
           v_incomplete_smelt_msg, CONCAT_WS('/',fr.primary_country_of_smelt, fr.secondary_country_of_smelt), fr.part_number 	
      FROM preftz.fed_receipts fr 	
      JOIN cast_and_smelt_reporting_fp_view csr ON csr.part_number = fr.part_number  -- KK 05/09/2025 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
       AND fr.temporary_deposit IS NULL         --not required for temporary deposit 	
       AND fr.pre_receipt IS NOT TRUE           --not required for a pre-receipt 	
       AND fr.country_of_cast IS NOT NULL 	
       AND (fr.primary_country_of_smelt IS NULL OR fr.secondary_country_of_smelt IS NULL); 	
 	
    --Invalid country_of_cast 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'country_of_cast', 	
           v_invalid_cast_msg, fr.country_of_cast, fr.part_number 	
      FROM preftz.fed_receipts fr 	
      LEFT JOIN preftz.countries c ON c.iso_country_code = fr.country_of_cast 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
       AND fr.temporary_deposit IS NULL         --not required for temporary deposit 	
       AND fr.pre_receipt IS NOT TRUE           --not required for a pre-receipt 	
       AND fr.country_of_cast IS NOT NULL 	
    AND COALESCE(fr.country_of_cast,'') <> 'UN' --UN(unknown) is acceptable 	
       AND c.iso_country_code IS NULL; --not in preftz table (logic above assures all valid countires are in the preftz table) 	
 	
    --Invalid primary_country_of_smelt 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'primary_country_of_smelt', 	
           v_invalid_1smelt_msg, fr.primary_country_of_smelt, fr.part_number 	
      FROM preftz.fed_receipts fr 	
      LEFT JOIN preftz.countries c ON c.iso_country_code = fr.primary_country_of_smelt 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
       AND fr.temporary_deposit IS NULL         --not required for temporary deposit 	
       AND fr.pre_receipt IS NOT TRUE           --not required for a pre-receipt 	
       AND fr.primary_country_of_smelt IS NOT NULL 	
       AND COALESCE(primary_country_of_smelt,'') <> 'N/A' --N/A is acceptable 	
       AND c.iso_country_code IS NULL; --not in preftz table (logic above assures all valid countires are in the preftz table) 	
 	
    --Invalid secondary_country_of_smelt 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'secondary_country_of_smelt', 	
           v_invalid_2smelt_msg, fr.secondary_country_of_smelt, fr.part_number 	
      FROM preftz.fed_receipts fr 	
      LEFT JOIN preftz.countries c ON c.iso_country_code = fr.secondary_country_of_smelt 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
       AND fr.temporary_deposit IS NULL         --not required for temporary deposit 	
       AND fr.pre_receipt IS NOT TRUE           --not required for a pre-receipt 	
       AND fr.secondary_country_of_smelt IS NOT NULL 	
       AND COALESCE(secondary_country_of_smelt,'') <> 'N/A' --N/A is acceptable 	
       AND c.iso_country_code IS NULL; --not in preftz table (logic above assures all valid countires are in the preftz table) 	
 	
    --Invalid use of N/A for primary_country_of_smelt 	
    INSERT INTO preftz.feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'primary_country_of_smelt', 	
           v_invalid_na_1smelt_msg, fr.primary_country_of_smelt, fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fr.primary_country_of_smelt = 'N/A' 	
       AND fr.secondary_country_of_smelt <> 'N/A'; 	
 	
    --Aluminum cast & smelt reporting END --NKM 04/21/2023 	
 	
    -- KK 05/23/2025 create temp views for cast/smelt and melt/pour reporting and don't flag 0% derivatives. 	
    CREATE OR REPLACE TEMPORARY VIEW melt_and_pour_reporting_fp_view AS 	
    WITH max_date_content AS ( 	
        SELECT dpc.part_number, MAX(dpc.start_date) as max_start_date 	
        FROM preftz.derivative_parts_content dpc 	
        JOIN preftz.fed_receipts fr ON fr.part_number = dpc.part_number 	
        GROUP BY dpc.part_number 	
    ), most_recent_part_content AS ( 	
        SELECT dpc.part_number, dpc.steel_percentage, dpc.start_date 	
        FROM preftz.derivative_parts_content dpc 	
        JOIN max_date_content md ON md.part_number = dpc.part_number 	
            AND md.max_start_date = dpc.start_date 	
    ), parts_needing_melt_pour AS ( 	
        -- Iron/Steel Products 	
        SELECT pc.part_number, pc.harmonized_tariff_schedule_number, rbh.category 	
        FROM preftz.fed_receipts fr 	
        JOIN preftz.part_classifications pc ON pc.part_number = fr.part_number 	
        JOIN preftz.reporting_by_hts rbh ON pc.harmonized_tariff_schedule_number LIKE rbh.tariff_prefix || '%' 	
            AND rbh.category = 'iron_steel_product' 	
            AND fr.receipt_date BETWEEN rbh.start_date AND rbh.end_date 	
        WHERE pc.tariff_type = 'BASE' 	
        UNION 	
        -- Iron/Steel Derivatives; Exclude those parts that are 0% iron or steel 	
        SELECT pc.part_number, pc.harmonized_tariff_schedule_number, rbh.category 	
        FROM preftz.fed_receipts fr 	
        JOIN preftz.part_classifications pc ON pc.part_number = fr.part_number 	
        JOIN preftz.reporting_by_hts rbh ON pc.harmonized_tariff_schedule_number LIKE rbh.tariff_prefix || '%' 	
            AND rbh.category = 'iron_steel_derivative' 	
            AND fr.receipt_date BETWEEN rbh.start_date AND rbh.end_date 	
        LEFT JOIN most_recent_part_content dpc ON dpc.part_number = pc.part_number 	
        WHERE pc.tariff_type = 'BASE' 	
            AND COALESCE(dpc.steel_percentage,1) > 0 	
    ) 	
    SELECT * FROM parts_needing_melt_pour 	
    ORDER BY part_number; 	
 	
    -- KK 04/17/2025 - Melt and Pour - country_of_melt may be required 	
    INSERT INTO preftz.feed_errors 	
        (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT DISTINCT v_table_name, fr.receiptid, 'country_of_melt', 	
           v_missing_melt_msg, fr.country_of_melt, fr.part_number 	
    FROM preftz.fed_receipts fr 	
    JOIN melt_and_pour_reporting_fp_view csr ON csr.part_number = fr.part_number  -- KK 05/09/2025 	
    WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
        AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE) 	
        AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
        AND fr.temporary_deposit IS NULL         --not required for temporary deposit 	
        AND fr.pre_receipt IS NOT TRUE           --not required for a pre-receipt 	
        AND fr.country_of_melt IS NULL; 	
 	
    -- KK 04/17/2025 - Melt and Pour - country_of_pour may be required 	
    INSERT INTO preftz.feed_errors 	
        (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT DISTINCT v_table_name, fr.receiptid, 'country_of_pour', 	
           v_missing_pour_msg, fr.country_of_pour, fr.part_number 	
    FROM preftz.fed_receipts fr 	
    JOIN melt_and_pour_reporting_fp_view csr ON csr.part_number = fr.part_number  -- KK 05/09/2025 	
    WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
        AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE) 	
        AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
        AND fr.temporary_deposit IS NULL         --not required for temporary deposit 	
        AND fr.pre_receipt IS NOT TRUE           --not required for a pre-receipt 	
        AND fr.country_of_pour IS NULL; 	
 	
    -- KK 04/17/2025 Invalid country_of_melt 	
    INSERT INTO preftz.feed_errors 	
        (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'country_of_melt', 	
        v_invalid_melt_msg, fr.country_of_melt, fr.part_number 	
    FROM preftz.fed_receipts fr 	
    LEFT JOIN (SELECT * FROM preftz.countries UNION SELECT 'OTH', 'OTHER') c ON c.iso_country_code = fr.country_of_melt 	
    WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
        AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE) 	
        AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
        AND fr.temporary_deposit IS NULL         --not required for temporary deposit 	
        AND fr.pre_receipt IS NOT TRUE           --not required for a pre-receipt 	
        AND fr.country_of_melt IS NOT NULL 	
        AND c.iso_country_code IS NULL; --not in preftz table (logic above assures all valid countires are in the preftz table) 	
 	
    -- KK 04/17/2025 Invalid country_of_pour 	
    INSERT INTO preftz.feed_errors 	
        (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'country_of_pour', 	
        v_invalid_melt_msg, fr.country_of_pour, fr.part_number 	
    FROM preftz.fed_receipts fr 	
    LEFT JOIN (SELECT * FROM preftz.countries UNION SELECT 'OTH', 'OTHER') c ON c.iso_country_code = fr.country_of_pour 	
    WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
        AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE) 	
        AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
        AND fr.temporary_deposit IS NULL         --not required for temporary deposit 	
        AND fr.pre_receipt IS NOT TRUE           --not required for a pre-receipt 	
        AND fr.country_of_pour IS NOT NULL 	
        AND c.iso_country_code IS NULL; --not in preftz table (logic above assures all valid countires are in the preftz table) 	
    -- END Melt and Pour 	

    -- KK 07/03/2026 - Invalid Percentage of US value for USMCA column
    INSERT INTO preftz.feed_errors 	
        (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'usmca_percent_us_value', 	
        v_usmca_percent_us_value_msg, fr.usmca_percent_us_value, fr.part_number 	
    FROM preftz.fed_receipts fr
    WHERE fr.fed_status IN ('AUDITING','UPDATE') 	
        AND COALESCE(fr.zone_status,'X') <> 'D'	
        AND fr.usmca_percent_us_value IS NOT NULL
        AND (fr.usmca_percent_us_value < 0.0
          OR fr.usmca_percent_us_value > 100.0);
     	
    -- EG 4/7/2026 auto delete pre-receipts DEV-257 	
 	
            IF (SELECT direct_delivery_indicator FROM preftz.ftz_reference) = 'N'  	
            THEN 	
               	
              FOR crs IN  	
                 SELECT fr.bill_of_lading_proxy, fr.receiptid, fr.pre_receipt 	
                 FROM preftz.fed_receipts fr 	
                 WHERE  fr.fed_status IN('NEW','AUDITING')  	
                  AND COALESCE(fr.zone_admission_no,'') = '' 	
                  AND fr.conveyanceid IS NULL 	
                  AND fr.quantity > 0 	
                  AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE) 	
                  AND COALESCE(fr.zone_status,'X') <> 'D'  --not required for domestic goods 	
                  ORDER BY fr.receiptid 	
                  LOOP 	
 	
                       -- Reset per-loop variables to avoid accidental reuse 	
                       v_conveyanceid := NULL; 	
                       v_zone_admission_no := NULL; 	
                       v_concur_status := NULL; 	
                        	
                       -- check if already hs a conveyance 	
                       SELECT c.conveyanceid, c.zone_admission_no 	
                       INTO v_conveyanceid,v_zone_admission_no 	
                       FROM preftz.conveyances c 	
                       where c.inbond_number  = crs.bill_of_lading_proxy; 	
                        	
                       -- check filing statuses  	
                       SELECT COALESCE(efs.concur_status,''),COALESCE(efs.e214_status,'') 	
                       INTO v_concur_status, v_e214_status 	
                       FROM preftz.e214_filing_statuses efs 	
                       WHERE efs.zone_admission_no = v_zone_admission_no; 	
                        	
                       -- check if has pre_receipts already deleted (error condition) 	
                       select count(*) 	
                       into v_count 	
                       FROM preftz.deleted_pre_receipts ftf 	
                       where ftf.conveyanceid = v_conveyanceid; 	
                        	
                       -- check if concur status (ERROR condition)  	
                       IF  (v_conveyanceid IS NOT NULL)  	
                           AND (COALESCE(v_concur_status,'') NOT IN ('','REJECTED'))   	
                       THEN   	
                           INSERT INTO preftz.feed_errors 	
                           (table_name  , tableid,      field_name,      error_type,             error_key_value,  fed_record_identifier) 	
                           SELECT  	
                            v_table_name, crs.receiptid, 'receiptid',     v_concurred_e214_msg,   v_zone_admission_no, v_concur_status; 	
                       END IF; 	
 	
                       -- check if v_e214_status status is AUTHORIZED/FILED for existing pre-receipts   	
                       -- and we want to add more pre-receipts (ERROR condition)  	
                       IF   v_conveyanceid IS NOT NULL 	
                           AND crs.pre_receipt IS TRUE 	
                           AND v_e214_status IN ('AUTHORIZED','FILED')   	
                       THEN   	
                           INSERT INTO preftz.feed_errors 	
                           (table_name  , tableid,      field_name,      error_type,               error_key_value,  fed_record_identifier) 	
                           SELECT  	
                            v_table_name, crs.receiptid, 'receiptid',     v_pre_receipt_filed_msg,  v_zone_admission_no, v_e214_status; 	
                       END IF; 	
 	
                       -- check if v_e214_status status is not AUTHORIZED for existing pre-receipts   	
                       -- and we already received receipts (ERROR condition)  	
                       IF   v_conveyanceid IS NOT NULL 	
                           AND crs.pre_receipt IS NOT TRUE 	
                           AND v_e214_status NOT IN ('AUTHORIZED')   	
                       THEN   	
                           INSERT INTO preftz.feed_errors 	
                           (table_name  , tableid,      field_name,      error_type,             error_key_value,  fed_record_identifier) 	
                           SELECT  	
                            v_table_name, crs.receiptid, 'receiptid',     v_e214status_msg,        v_zone_admission_no, v_e214_status; 	
                       END IF; 	
                        	
                       -- check if pre-receipts were already found  and moved to deleted table  	
                       -- and we already received receipts (ERROR condition)  	
                       IF  v_count > 0 	
                       THEN   	
                           INSERT INTO preftz.feed_errors 	
                           (table_name  , tableid,      field_name,      error_type,             error_key_value,  fed_record_identifier) 	
                           SELECT  	
                            v_table_name, crs.receiptid, 'receiptid',     v_pre_receipt_msg,        v_zone_admission_no, v_count; 	
                       END IF; 	
                        	
                       -- check if pre-receipts and receipts are on the same feed (ERROR condition)  	
                        	
                       WITH t1  	
                       AS ( 	
                       SELECT  	
                       ftf.bill_of_lading_proxy 	
                       ,COALESCE(FTF.PRE_RECEIPT,FALSE) 	
                       FROM preftz.fed_receipts ftf 	
                       WHERE bill_of_lading_proxy = crs.bill_of_lading_proxy 	
                       GROUP BY  	
                       ftf.bill_of_lading_proxy 	
                       ,COALESCE(FTF.PRE_RECEIPT,FALSE) 	
                       ) 	
                       , t2 AS 	
                       ( 	
                       SELECT t1.bill_of_lading_proxy 	
                       ,COUNT(*) 	
                       FROM t1  	
                       GROUP BY  	
                       t1.bill_of_lading_proxy 	
                       HAVING COUNT(*) > 1 	
                       ) 	
                       SELECT COUNT(*)  	
                       INTO v_count 	
                       FROM t2; 	
                        	
                       IF  v_count > 0 	
                       THEN   	
                           INSERT INTO preftz.feed_errors 	
                           (table_name  , tableid,      field_name,      error_type,             error_key_value,  fed_record_identifier) 	
                           SELECT  	
                            v_table_name, crs.receiptid, 'receiptid',     v_pre_receipt_mix_msg,     v_zone_admission_no, v_count; 	
                       END IF; 	
                        	
                       -- check if pre-receipts were received but not processed , so NOT AUTHORIZED  	
                       -- and receipts should not be coming yet  (ERROR condition)  	

                       SELECT COUNT(*)  	
                       INTO v_count 	
                       FROM preftz.receipts ftf 	
                       WHERE ftf.bill_of_lading_proxy = crs.bill_of_lading_proxy 	
                       AND ftf.pre_receipt IS TRUE 
                       AND crs.pre_receipt IS NOT TRUE	
                       AND ftf.conveyanceid IS NULL; 	-- EG 07/06/2026 	
                        	
                       IF  v_count > 0 	
                       THEN   	
                           INSERT INTO preftz.feed_errors 	
                           (table_name  , tableid,      field_name,      error_type,             error_key_value,  fed_record_identifier) 	
                           SELECT  	
                            v_table_name, crs.receiptid, 'receiptid',     v_pre_receipt_mix_msg_2,     v_zone_admission_no, v_count; 	
                       END IF; 	
 	
                       -- 'Receipts exist for incoming PRE-receipts' (ERROR condition)  	
                       SELECT COUNT(*)  	
                       INTO v_count 	
                       FROM preftz.receipts ftf 	
                       WHERE ftf.bill_of_lading_proxy = crs.bill_of_lading_proxy 	
                       AND ftf.pre_receipt IS NOT TRUE 	
                       AND crs.pre_receipt IS TRUE
                       ; 	
                        	
                       IF  v_count > 0 	
                       THEN   	
                           INSERT INTO preftz.feed_errors 	
                           (table_name  , tableid,      field_name,      error_type,             error_key_value,  fed_record_identifier) 	
                           SELECT  	
                            v_table_name, crs.receiptid, 'receiptid',     v_pre_receipt_mix_msg_3,     v_zone_admission_no, v_count; 	
                       END IF; 	
                        	
                        	
                  END LOOP;     	
                  	
            END IF; -- IF (SELECT direct_delivery_indicator FROM preftz.ftz_reference) = 'N'  	
    -- EG 4/7/2026 auto delete pre-receipts DEV-257 	
     	
     	
     	
     	
     	
 	
    --set fed_status to ERROR 	
    UPDATE preftz.fed_receipts fr 	
       SET fed_status = 'ERROR' 	
      FROM preftz.feed_errors fe 	
     WHERE fe.table_name = v_table_name 	
       AND fe.tableid = fr.receiptid 	
       AND fe.error_type <> v_duplicate_msg;  --RTJ 11/13/2020 	

    -- KK 07/03/2026 - Upsert for persisting USMCA percent U.S. value
    -- We make the assumption these are entered as whole percentages (ie: 45.5 = 45.5%) - it is stored as decimal
    -- This part would also have to be flagged in preftz.parts_extension
    MERGE INTO preftz.receipt_percentage_value AS target
    USING (
        SELECT fr.receiptid, fr.usmca_percent_us_value / 100::NUMERIC AS usmca_percent_us_value
        FROM preftz.fed_receipts fr 
        WHERE fr.fed_status IN ('AUDITING','UPDATE')
          AND COALESCE(fr.zone_status,'X') <> 'D'	
          AND fr.usmca_percent_us_value IS NOT NULL
    ) AS source
    ON target.receiptid = source.receiptid
    WHEN MATCHED THEN
        UPDATE SET 
            percent_us_value = source.usmca_percent_us_value
    WHEN NOT MATCHED THEN
        INSERT (receiptid, percent_us_value)
        VALUES (source.receiptid, source.usmca_percent_us_value);
 	
    --RTJ 11/13/2020 reset conveyance link if conveyance or zone admission number data has changed on correction record 	
    UPDATE preftz.fed_receipts fr --NKM 09/01/2021 changed loop with update query into plain update query 	
       SET zone_admission_no = NULL, 	
           conveyanceid = NULL 	
      FROM preftz.receipts r 	
           LEFT JOIN preftz.conveyances c 	
                  ON r.conveyanceid = c.conveyanceid 	
           LEFT JOIN preftz.fed_conveyances fc 	
                  ON r.conveyanceid = fc.conveyanceid 	
         WHERE fr.fed_status IN('UPDATE','KIT_UPDATE') 	
           AND fr.receiptid = r.receiptid 	
           AND (   COALESCE(fr.bill_of_lading_airwaybill,'') <> 	
                   COALESCE(fc.bill_of_lading_airwaybill,c.bill_of_lading_airwaybill,'') 	
                OR COALESCE(fr.house_bill,'') <> COALESCE(fc.house_bill,c.house_bill,'') 	
                OR COALESCE(fr.bill_of_lading_proxy,'') <> COALESCE(r.bill_of_lading_proxy,'') 	
                OR COALESCE(fr.zone_admission_no,'') <> COALESCE(r.zone_admission_no,'') 	
                OR COALESCE(fr.inbond_number,'') <> COALESCE(fc.inbond_number,c.inbond_number,'')); --NKM 09/01/2021 	
 	
    COMMIT; 	
 	
    --handle conveyance linking for AUDITING record and UPDATE records with null zone_admission_no 	
    --RTJ 03/31/2021 if AUTOMATIC linking is selected assign all fed receipts 	
     	
    --EG 4/7/2026 auto delete pre-receipts DEV-257 	
    --IF (SELECT direct_delivery_indicator FROM preftz.ftz_reference) <> 'N'  	
    --THEN  	
    IF (SELECT  coalesce(preftz.get_ftz_setting('AUTO CONCUR'),'NO') = 'NO')  	
    THEN  	
     	
    IF preftz.get_ftz_setting('RECEIPT LINKING') = 'AUTOMATIC' THEN 	
        CALL preftz.assign_fed_receipts(); --NKM 06/24/2021 Updates made up to this point 	
    ELSE 	
    --if MANUAL linking is selected, ensure that each record includes a bill of lading proxy 	
        UPDATE preftz.fed_receipts fr 	
           SET bill_of_lading_proxy = COALESCE(fr.bill_of_lading_airwaybill,'NONE') || 	
                                      COALESCE(fr.house_bill,'NONE') || 	
                                      COALESCE('SPLIT'||fr.house_bill_partial_indicator,'') || --NKM 06/24/2021 added 	
                                      COALESCE(fr.inbond_number,'NULL') || --NKM 06/24/2021 'NULL' is different FROM 'NONE' 	
                                      TO_CHAR(current_date,'mmddyy') 	
         WHERE fr.fed_status = 'AUDITING' 	
           AND COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y'   --NKM 03/18/2022 	
           AND COALESCE(fr.bill_of_lading_proxy,'') = '' 	
           AND COALESCE(fr.zone_status,'') <> 'D';             --NKM 03/25/2024 	
    END IF; 	
     	
    END IF; --IF (SELECT direct_delivery_indicator FROM preftz.ftz_reference) = 'N' --EG 4/7/2026 auto delete pre-receipts DEV-257 	
 	
    --NKM 05/31/2022 Link conveyance to current admission if has linked receipts but does not already have an admission number 	
    FOR conrs IN SELECT DISTINCT c.conveyanceid 	
                   FROM preftz.conveyances c 	
                   JOIN preftz.fed_receipts fr ON fr.conveyanceid = c.conveyanceid 	
                  WHERE COALESCE(c.zone_admission_no,'') = '' 	
                  AND fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE')  --NO 12/04/2025 	
    LOOP 	
        IF v_current_admission_no IS NULL THEN 	
           v_current_admission_no = preftz.get_current_zone_admission_number(); 	
        END IF; 	
 	
        SELECT COALESCE(MAX(fr.zone_admission_no),v_current_admission_no) 	
          INTO v_update_admission_no 	
          FROM preftz.fed_receipts fr 	
         WHERE fr.conveyanceid = conrs.conveyanceid 	
           AND COALESCE(fr.zone_admission_no,'') <> '' 	
           AND fr.fed_status IN ('AUDITING','UPDATE','KIT_UPDATE'); --NO 12/04/2025 	
 	
        CALL preftz.assign_conveyances_to_214(conrs.conveyanceid, v_update_admission_no); 	
    END LOOP; 	
    --NKM 05/31/2022 	
 	
    --RTJ 11/13/2020 handle receipt corrections 	
    IF EXISTS (SELECT FROM preftz.fed_receipts WHERE fed_status = 'UPDATE') THEN --NKM 03/25/2024 	
        CALL preftz.process_receipt_updates(); 	
    END IF; 	
 	
    --NKM 03/25/2024 	
    IF EXISTS (SELECT FROM preftz.fed_receipts WHERE fed_status = 'KIT_UPDATE') THEN 	
        CALL preftz.process_kit_receipt_updates(); 	
    END IF; 	
 	
    --NKM 03/18/2022 	
    --strip 214 number and conveyance link before entering into token table if domestic 	
    UPDATE preftz.fed_receipts fr 	
       SET zone_admission_no = NULL, 	
           conveyanceid = NULL 	
     WHERE fr.zone_status = 'D' 	
       AND fr.fed_status IN('AUDITING','UPDATE','KIT_UPDATE'); --NKM 03/25/2024 	
    --NKM 03/18/2022 	
 	
    --NKM 03/25/2024 change status to KIT for received kit parts (except for pre-receipts) 	
    UPDATE preftz.fed_receipts fr 	
       SET fed_status = 'KIT' 	
      FROM preftz.kit_parts kp 	
     WHERE kp.part_number = fr.part_number 	
       AND fr.fed_status = 'AUDITING' 	
       AND (kp.removed_date IS NULL OR kp.removed_date > fr.receipt_date)  --KK kits at time of receipt_date 	
       AND fr.pre_receipt IS NOT TRUE; --pre-receipts can be kits (because kits must be domestic) 	
 	
    --insert AUDITING records to receipts table 	
    INSERT INTO preftz.receipts 	
          (receiptid, part_number, receipt_date, quantity, unit_price, manufacturer_mid_code, 	
           country_of_origin, bill_of_lading_proxy, commercial_invoice_number, transaction_reference, 	
           zone_admission_no, zone_status, foreign_unit_price, currency_code, currency_exchange_rate, 	
           privileged_date, conveyanceid, inbond_number, zone_to_zone_transfer, pre_receipt,  --RTJ 11/08/2021 NKM 05/04/2022 	
           unit_assist)  --RTJ 01/19/2023 	
    SELECT fr.receiptid, fr.part_number, fr.receipt_date, fr.quantity, fr.unit_price, fr.manufacturer_mid_code, 	
           fr.country_of_origin, fr.bill_of_lading_proxy, fr.commercial_invoice_number, fr.transaction_reference, 	
           fr.zone_admission_no, fr.zone_status, fr.foreign_unit_price, fr.currency_code, fr.currency_exchange_rate, 	
           CASE WHEN fr.zone_status = 'P' THEN fr.receipt_date ELSE NULL END, --NKM 09/18/2023 	
           fr.conveyanceid, fr.inbond_number, 'N', fr.pre_receipt, fr.unit_assist  --RTJ 11/08/2021 NKM 05/04/2022  RTJ 01/19/2023 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status = 'AUDITING' 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 --includes pre-receipt kits 	
       AND fr.temporary_deposit IS NULL  --RTJ 08/04/2021 	
       AND fr.quantity > 0; --NKM 07/12/2022 assumes quantity rounded to 0 at start of procedure 	
 	
 	
 -- MH 10/22/2024 delete currently present user references for next step will fail if present 	
 with recs as( 	
   select receiptid FROM preftz.fed_receipts fr 	
   LEFT JOIN preftz.user_references ur on ur.table_name = 'receipts' and ur.tableid = fr.receiptid 	
     WHERE fr.fed_status = 'AUDITING' 	
    AND ur.tableid is not null 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fr.temporary_deposit IS NULL  --RTJ 08/04/2021 	
       AND fr.quantity > 0 --NKM 07/12/2022 assumes quantity rounded to 0 at start of procedure 	
       AND COALESCE(fr.user_reference1,fr.user_reference2,fr.user_reference3,fr.user_reference4, 	
                    fr.user_reference5,'') <> '') 	
 delete from preftz.user_References where table_name = 'receipts' and tableid in(select receiptid from recs); 	
 	
    --insert AUDITING records to user_references table 	
    INSERT INTO preftz.user_references 	
          (table_name, tableid, user_reference1, user_reference2, user_reference3, user_reference4, 	
           user_reference5) 	
    SELECT 'receipts', fr.receiptid, fr.user_reference1, fr.user_reference2, fr.user_reference3, 	
           fr.user_reference4, fr.user_reference5 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status = 'AUDITING' 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fr.temporary_deposit IS NULL  --RTJ 08/04/2021 	
       AND fr.quantity > 0 --NKM 07/12/2022 assumes quantity rounded to 0 at start of procedure 	
       AND COALESCE(fr.user_reference1,fr.user_reference2,fr.user_reference3,fr.user_reference4, 	
                    fr.user_reference5,'') <> ''; 	
 	
    --RTJ 03/31/2021 insert AUDITING records to receipt_case_numbers table 	
    INSERT INTO preftz.receipt_case_numbers 	
          (receiptid, antidumping_case_number, countervailing_case_number) 	
    SELECT fr.receiptid, LEFT(REPLACE(fr.antidumping_case_number,'-',''),1) || '-' || 	
           SUBSTR(REPLACE(fr.antidumping_case_number,'-',''),2,3) || '-' || 	
           SUBSTR(REPLACE(fr.antidumping_case_number,'-',''),5,3) || '-' || 	
           SUBSTR(REPLACE(fr.antidumping_case_number,'-',''),8,3), 	
           LEFT(REPLACE(fr.countervailing_case_number,'-',''),1) || '-' || 	
           SUBSTR(REPLACE(fr.countervailing_case_number,'-',''),2,3) || '-' || 	
           SUBSTR(REPLACE(fr.countervailing_case_number,'-',''),5,3) || '-' || 	
           SUBSTR(REPLACE(fr.countervailing_case_number,'-',''),8,3) 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status = 'AUDITING' 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fr.temporary_deposit IS NULL  --RTJ 08/04/2021 	
       AND fr.quantity > 0 --NKM 07/12/2022 assumes quantity rounded to 0 at start of procedure 	
       AND COALESCE(fr.antidumping_case_number,fr.countervailing_case_number,'') <> ''; 	
    --RTJ 03/31/2021 	
 	
    --NKM 02/02/2022 insert AUDITING records to import_licenses 	
    INSERT INTO preftz.import_licenses (receiptid, import_license_type, import_license_number) 	
    SELECT fr.receiptid, fr.import_license_type, fr.import_license_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status = 'AUDITING' 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fr.temporary_deposit IS NULL  --RTJ 08/04/2021 	
       AND fr.quantity > 0 --NKM 07/12/2022 assumes quantity rounded to 0 at start of procedure 	
       AND fr.import_license_number IS NOT NULL; 	
 	
    --NKM 04/21/2023 insert AUDITING records to aluminum_cast_and_smelt 	
    INSERT INTO preftz.receipt_cast_and_smelt (receiptid, country_of_cast, primary_country_of_smelt, secondary_country_of_smelt) 	
    SELECT fr.receiptid, fr.country_of_cast, fr.primary_country_of_smelt, fr.secondary_country_of_smelt 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status = 'AUDITING' 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fr.temporary_deposit IS NULL  --RTJ 08/04/2021 	
       AND fr.quantity > 0 --NKM 07/12/2022 assumes quantity rounded to 0 at start of procedure 	
       AND fr.country_of_cast IS NOT NULL; --Country of cast will be null if no cast or smelt data is provided 	
 	
    -- KK 04/22/2025 insert AUDITING records to receipt_melt_and_pour 	
    INSERT INTO preftz.receipt_melt_and_pour (receiptid, country_of_melt, country_of_pour) 	
    SELECT fr.receiptid, fr.country_of_melt, fr.country_of_pour 	
    FROM preftz.fed_receipts fr 	
    WHERE fr.fed_status = 'AUDITING' 	
        AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE) 	
        AND fr.temporary_deposit IS NULL 	
        AND fr.quantity > 0 	
        AND fr.country_of_melt IS NOT NULL; 	
 	
    --insert AUDITING records to inventory_items table 	
    INSERT INTO preftz.inventory_items 	
          (part_number, quantity_received, quantity_on_hand, receipt_date, receiptid, zone_status) 	
    SELECT fr.part_number, fr.quantity, fr.quantity, fr.receipt_date, fr.receiptid, fr.zone_status 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status = 'AUDITING' 	
       AND COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y'   --NKM 03/18/2022 	
       AND fr.temporary_deposit IS NULL  --RTJ 08/04/2021 	
       AND fr.quantity > 0 --NKM 07/12/2022 assumes quantity rounded to 0 at start of procedure 	
       AND fr.pre_receipt IS NOT TRUE; 	
 	
    --insert AUDITING records to receipt_derivative_content table 	
    INSERT INTO preftz.receipt_derivative_content 	
        (receiptid, steel_content_weight, aluminum_content_weight, copper_content_weight, unit_net_weight) 	
    SELECT fr.receiptid, COALESCE(fr.steel_content_weight,0.0), 	
        COALESCE(fr.aluminum_content_weight,0.0), 	
        COALESCE(fr.copper_content_weight,0.0), 	
        COALESCE(p.unit_net_weight,0.0) 	
    FROM preftz.fed_receipts fr 	
    JOIN preftz.parts p ON p.part_number = fr.part_number 	
    WHERE fr.fed_status = 'AUDITING' 	
        AND (fr.steel_content_weight IS NOT NULL 	
            OR fr.aluminum_content_weight IS NOT NULL 	
            OR fr.copper_content_weight IS NOT NULL) 	
    ON CONFLICT (receiptid) DO UPDATE                 -- KK 04/23/2026 	
        SET steel_content_weight = EXCLUDED.steel_content_weight,  	
            aluminum_content_weight = EXCLUDED.aluminum_content_weight,  	
            copper_content_weight = EXCLUDED.copper_content_weight,  	
            unit_net_weight = EXCLUDED.unit_net_weight; 	
 	
    --kit parts START --NKM 03/25/2024 	
    --insert kit_receipts record 	
    INSERT INTO preftz.kit_receipts 	
          (receiptid, part_number, receipt_date, quantity, unit_price, commercial_invoice_number, 	
           transaction_reference, foreign_unit_price, currency_code, currency_exchange_rate) 	
    SELECT fr.receiptid, fr.part_number, fr.receipt_date, fr.quantity, fr.unit_price, fr.commercial_invoice_number, 	
           fr.transaction_reference, fr.foreign_unit_price, fr.currency_code, fr.currency_exchange_rate 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status = 'KIT'; 	
 	
    --insert KIT records to user_references table 	
    INSERT INTO preftz.user_references 	
          (table_name, tableid, user_reference1, user_reference2, user_reference3, user_reference4, 	
           user_reference5) 	
    SELECT 'kit_receipts', fr.receiptid, fr.user_reference1, fr.user_reference2, fr.user_reference3, 	
           fr.user_reference4, fr.user_reference5 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status = 'KIT'; 	
 	
    --insert kit_build event 	
    INSERT INTO preftz.kit_builds(kit_buildid, part_number, quantity_built, build_date, receiptid) --NKM 04/08/2024 	
    SELECT nextval('preftz.fed_kit_builds_kit_buildid_seq') AS kit_buildid, 	
           fr.part_number, fr.quantity, fr.receipt_date, fr.receiptid 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status = 'KIT'; 	
 	
    --update kit inventory 	
    UPDATE preftz.kit_inventory ki 	
       SET quantity_on_hand = COALESCE(ki.quantity_on_hand,0) + fr.total_quantity 	
      FROM (SELECT part_number, SUM(quantity) AS total_quantity FROM preftz.fed_receipts WHERE fed_status = 'KIT' GROUP BY part_number) fr 	
     WHERE fr.part_number = ki.part_number; 	
 	
    --insert receipts records for kit components 	
    --REFRESH MATERIALIZED VIEW preftz.exploded_kit_boms; 	
    INSERT INTO preftz.receipts 	
          (receiptid, part_number, receipt_date, quantity, unit_price, 	
           manufacturer_mid_code, country_of_origin, commercial_invoice_number, transaction_reference, 	
           zone_status, kit_receiptid) 	
    SELECT nextval('preftz.fed_receipts_receiptid_seq') AS receiptid, 	
           kb.component_part_number, fr.receipt_date, fr.quantity*kb.quantity_per_kit, 	
           CASE 	
           WHEN tot.all_priced --all components parts have a reference unit price 	
           THEN p.reference_unit_price*(fr.unit_price/tot.total_reference_unit_price) --part unit price scales by kit reference unit price 	
           WHEN tot.total_reference_unit_price = 0 --no component parts has a reference unit price 	
             OR (NOT tot.all_priced AND tot.total_reference_unit_price >= fr.unit_price) --component part reference unit prices exceed total reference unit price 	
           THEN fr.unit_price*(p.unit_net_weight/tot.total_net_weight) --unit price scales by net weight 	
           ELSE --some but not all components have a reference_unit_price (hybrid) 	
                CASE 	
                WHEN p.reference_unit_price > 0 	
                THEN p.reference_unit_price --Use unit price where it exists 	
                ELSE (fr.unit_price-tot.total_reference_unit_price)*(p.unit_net_weight/tot.unpriced_total_net_weight) --scale the balance value by weight 	
                END 	
           END AS unit_price, 	
           'DOMESTIC' AS manufacturer_mid_code, 'US' AS country_of_origin, fr.commercial_invoice_number, 	
           CONCAT('KIT RECEIPT ',fr.receiptid::TEXT,'-',kb.exploded_componentid) AS transaction_reference, 	
           fr.zone_status, fr.receiptid 	
      FROM preftz.fed_receipts fr 	
      JOIN preftz.exploded_kit_boms kb ON kb.kit_part_number = fr.part_number 	
       AND fr.receipt_date BETWEEN kb.version_start_date AND kb.version_end_date  -- KK kit versions 	
      JOIN preftz.parts_activation_view p ON p.part_number = kb.component_part_number   -- KK converted kits 	
       AND fr.receipt_date > p.activation_date    -- KK converted kits 	
      JOIN (SELECT bom.kit_part_number, SUM(parts.reference_unit_price*bom.quantity_per_kit) total_reference_unit_price, 	
                   NOT (MIN(parts.reference_unit_price)=0) AS all_priced, SUM(parts.unit_net_weight*bom.quantity_per_kit) AS total_net_weight, 	
                   SUM(parts.unit_net_weight*bom.quantity_per_kit*(parts.reference_unit_price=0)::INT) AS unpriced_total_net_weight 	
              FROM preftz.exploded_kit_boms bom 	
              JOIN preftz.fed_receipts fr1 ON fr1.part_number = bom.kit_part_number          -- KK kit versions 	
            AND fr1.receipt_date BETWEEN bom.version_start_date AND bom.version_end_date  -- KK kit versions 	
              JOIN preftz.parts_activation_view parts ON parts.part_number = bom.component_part_number   -- KK converted kits 	
               AND fr1.receipt_date > parts.activation_date   -- KK converted kits 	
             GROUP BY bom.kit_part_number) tot ON tot.kit_part_number = fr.part_number 	
     WHERE fr.fed_status = 'KIT'; 	
 	
    --insert KIT records to inventory_items table 	
    INSERT INTO preftz.inventory_items 	
          (part_number, quantity_received, quantity_on_hand, receipt_date, receiptid, zone_status) 	
    SELECT r.part_number, r.quantity, r.quantity, r.receipt_date, r.receiptid, r.zone_status 	
      FROM preftz.fed_receipts fr 	
      JOIN preftz.receipts r ON r.kit_receiptid = fr.receiptid 	
     WHERE fr.fed_status = 'KIT'; 	
 	
    --kit parts END --NKM 03/25/2024 	
 	
    --insert AUDITING negative records to fed_adjustments table 	
    INSERT INTO preftz.fed_adjustments 	
          (part_number, adjust_date, quantity_adjusted, transaction_reference, user_reference5) 	
    SELECT fr.part_number, fr.receipt_date, fr.quantity, fr.transaction_reference, fr.user_reference5 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status = 'AUDITING' 	
       AND fr.temporary_deposit IS NULL  --RTJ 08/04/2021 	
       AND fr.quantity < 0; --NKM 07/12/2022 assumes quantity rounded to 0 at start of procedure 	
 	
    --RTJ 07/19/2021 Tranfer feed errors for ztz records 	
    INSERT INTO preftz.ztz_feed_errors 	
               (table_name, tableid, field_name, error_type, error_key_value, 	
                fed_record_identifier, transferid)  --RTJ 07/29/2021 	
         SELECT table_name, tableid, field_name, error_type, error_key_value, 	
                fed_record_identifier, transferid  --RTJ 07/29/2021 	
           FROM preftz.feed_errors fe 	
                INNER JOIN preftz.fed_receipts fr ON fr.receiptid = fe.tableid 	
          WHERE (COALESCE(fr.zone_to_zone_transfer,'N') = 'Y' AND pre_receipt IS NOT TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
            AND fe.table_name = v_table_name; 	
 	
    DELETE FROM preftz.feed_errors fe 	
     USING preftz.fed_receipts fr 	
     WHERE fr.receiptid = fe.tableid 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') = 'Y' AND pre_receipt IS NOT TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fe.table_name = v_table_name; 	
 	
    INSERT INTO preftz.system_log (procedure_name, log_message) 	
    SELECT 'ztz fed_receipts', fed_status || TO_CHAR(COUNT(*),'999999') 	
      FROM preftz.fed_receipts fr 	
     WHERE (COALESCE(fr.zone_to_zone_transfer,'N') = 'Y' AND pre_receipt IS NOT TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
     GROUP BY fed_status; 	
    --RTJ 07/19/2021 	
 	
    --RTJ 08/04/2021 Tranfer feed errors for temporary deposit records 	
    INSERT INTO preftz.temporary_deposit_feed_errors 	
               (table_name, tableid, field_name, error_type, error_key_value, 	
                fed_record_identifier) 	
         SELECT table_name, tableid, field_name, error_type, error_key_value, 	
                fed_record_identifier 	
           FROM preftz.feed_errors fe 	
                INNER JOIN preftz.fed_receipts fr ON fr.receiptid = fe.tableid 	
          WHERE fr.temporary_deposit IS NOT NULL 	
            AND fe.table_name = v_table_name; 	
 	
    DELETE FROM preftz.feed_errors fe 	
     USING preftz.fed_receipts fr 	
     WHERE fr.receiptid = fe.tableid 	
       AND fr.temporary_deposit IS NOT NULL 	
       AND fe.table_name = v_table_name 	
       AND fr.receiptid IN (SELECT receiptid FROM temp_audit_receipts); 	
 	
    --add non-error temporary deposit records 	
    INSERT INTO preftz.temporary_deposit_feed_errors 	
          (table_name, tableid, field_name, error_type, error_key_value, fed_record_identifier) 	
    SELECT v_table_name, fr.receiptid, 'temporary_deposit', 	
           v_temporary_deposit_msg || COALESCE(TO_CHAR(fr.receipt_date,'mm/dd/yyyy'),''), 	
           COALESCE(fr.zone_admission_no,'') || ' ' || 	
           CASE WHEN COALESCE(fr.bill_of_lading_airwaybill,'') = '' 	
                THEN COALESCE(fr.bill_of_lading_proxy) 	
                ELSE COALESCE(fr.bill_of_lading_airwaybill,'') || COALESCE(fr.house_bill,'') 	
                END, fr.part_number 	
      FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status = 'AUDITING' 	
       AND fr.temporary_deposit IS NOT NULL; 	
 	
    INSERT INTO preftz.system_log (procedure_name, log_message) 	
    SELECT 'temporary deposit fed_receipts', 	
           CASE WHEN fed_status = 'AUDITING' THEN 'HOLDING' 	
                ELSE fed_status END || TO_CHAR(COUNT(*),'999999') 	
      FROM preftz.fed_receipts fr --NO 12/04/2025 	
     WHERE temporary_deposit IS NOT NULL 	
     AND fr.receiptid IN (SELECT receiptid FROM temp_audit_receipts) --NO 12/04/2025 	
     GROUP BY fed_status; 	
    --RTJ 08/04/2021 	
 	
    --record statistics 	
    INSERT INTO preftz.system_log (procedure_name, log_message) 	
    SELECT 'audit_fed_receipts', 	
           (CASE fed_status 	
                 WHEN 'AUDITING' THEN 'IMPORTED' 	
                 WHEN 'PROCESSED' THEN 'REVERSAL' 	
                 ELSE fed_status 	
                 END) || TO_CHAR(COUNT(*),'999999') 	
      FROM preftz.fed_receipts fr 	
     WHERE (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fr.receiptid IN (SELECT receiptid FROM temp_audit_receipts) --NO 12/04/2025 	
       AND temporary_deposit IS NULL  --RTJ 08/04/2021 	
     GROUP BY fed_status; 	
 	
    --Change status of ZTZ records to indicate they have passed audits (for use by process_fed_transfer_items) 	
    UPDATE preftz.fed_receipts fr 	
       SET fed_status = 'ZTZ' 	
     WHERE fr.fed_status = 'AUDITING' 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') = 'Y' AND pre_receipt IS NOT TRUE); --NKM 03/18/2022 --NKM 06/28/2023 	
 	
    --delete all non-ERROR records 	
    DELETE FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status IN ('PROCESSED','UPDATE','KIT','KIT_UPDATE');  --RTJ 11/13/2020 	
 	
    DELETE FROM preftz.fed_receipts fr 	
     WHERE fr.fed_status = 'AUDITING' 	
       AND (COALESCE(fr.zone_to_zone_transfer,'N') <> 'Y' OR pre_receipt IS TRUE)  --NKM 03/18/2022 --NKM 06/28/2023 	
       AND fr.temporary_deposit IS NULL;  --RTJ 08/04/2021 	
 	
    --The following are retained: 	
      --ZTZ records that have passed the audits (status = 'ZTZ') 	
      --Temporary deposit records (status = 'HOLDING') 	
 	
-- EG 4/7/2026 	
    IF (SELECT  coalesce(preftz.get_ftz_setting('AUTO CONCUR'),'NO') = 'AUTO_LINK_CONCUR')  	
    THEN  	
       CALL preftz.link_receipts_to_conveyances_by_inbond(); 	
       CALL preftz.assign_zone_admission(); 	
       CALL preftz.pre_receipts_filing(); 	
    END IF; 	
-- EG 4/7/2026 	
 	
 	
    INSERT INTO preftz.system_log (procedure_name, log_message) 	
    VALUES ('audit_fed_receipts', 'finished'); 	
END; 	
$BODY$; 	
 	
 	
 

