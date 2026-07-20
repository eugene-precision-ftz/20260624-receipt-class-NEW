--DROP FUNCTION IF EXISTS preftz.compare_fed_receipt(integer);

CREATE OR REPLACE FUNCTION preftz.compare_fed_receipt(
    p_receiptid integer
)
RETURNS varchar
LANGUAGE plpgsql
STABLE
AS $function$

--Change Log: 	
-- EG 07/16/2026 Compare fed_receipts columns with all other tables to know if anything chaged during front end UPDATE 


DECLARE
    v_receipt_result             varchar(20) DEFAULT 'FAIL';
    v_conveyance_result          varchar(20) DEFAULT 'FAIL';
    v_cast_smelt_result          varchar(20) DEFAULT 'FAIL';
    v_melt_pour_result           varchar(20) DEFAULT 'FAIL';
    v_derivative_content_result  varchar(20) DEFAULT 'FAIL';
    v_percentage_value_result    varchar(20) DEFAULT 'FAIL';
    v_case_number_result         varchar(20) DEFAULT 'FAIL';
    v_import_license_result      varchar(20) DEFAULT 'FAIL';
    v_user_reference_result      varchar(20) DEFAULT 'FAIL';

    v_result                     varchar(10);
BEGIN
    /*
     * Required comparison:
     * fed_receipts to receipts.
     */
    SELECT
        CASE
            WHEN EXISTS
            (
                SELECT 1
                FROM preftz.fed_receipts fr
                JOIN preftz.receipts r
                  ON r.receiptid = fr.receiptid
                WHERE fr.receiptid = p_receiptid

                  AND COALESCE(fr.part_number, '') =
                      COALESCE(r.part_number, '')

                  AND COALESCE(fr.receipt_date::text, '') =
                      COALESCE(r.receipt_date::text, '')

                  AND COALESCE(fr.quantity::text, '') =
                      COALESCE(r.quantity::text, '')

                  AND COALESCE(fr.unit_price::text, '') =
                      COALESCE(r.unit_price::text, '')

                  AND COALESCE(fr.manufacturer_mid_code, '') =
                      COALESCE(r.manufacturer_mid_code, '')

                  AND COALESCE(fr.country_of_origin::text, '') =
                      COALESCE(r.country_of_origin::text, '')

                  AND COALESCE(fr.bill_of_lading_proxy, '') =
                      COALESCE(r.bill_of_lading_proxy, '')

                  AND COALESCE(fr.commercial_invoice_number, '') =
                      COALESCE(r.commercial_invoice_number, '')

                  AND COALESCE(fr.transaction_reference, '') =
                      COALESCE(r.transaction_reference, '')

                  AND COALESCE(fr.zone_admission_no, '') =
                      COALESCE(r.zone_admission_no, '')

                  AND COALESCE(fr.zone_status, '') =
                      COALESCE(r.zone_status, '')

                  AND COALESCE(fr.foreign_unit_price::text, '') =
                      COALESCE(r.foreign_unit_price::text, '')

                  AND COALESCE(fr.currency_code, '') =
                      COALESCE(r.currency_code, '')

                  AND COALESCE(fr.currency_exchange_rate::text, '') =
                      COALESCE(r.currency_exchange_rate::text, '')

                  AND COALESCE(fr.conveyanceid::text, '') =
                      COALESCE(r.conveyanceid::text, '')

                  AND COALESCE(fr.country_of_export::text, '') =
                      COALESCE(r.country_of_export::text, '')

                  --AND COALESCE(fr.zone_to_zone_transfer::text, '') =
                  --    COALESCE(r.zone_to_zone_transfer::text, '')

                  AND COALESCE(fr.inbond_number, '') =
                      COALESCE(r.inbond_number, '')

                  AND COALESCE(fr.pre_receipt::text, '') =
                      COALESCE(r.pre_receipt::text, '')

                  AND COALESCE(fr.unit_assist::text, '') =
                      COALESCE(r.unit_assist::text, '')

                  AND COALESCE(fr.container, '') =
                      COALESCE(r.container, '')
            )
            THEN 'PASS_MATCH'
            ELSE 'FAIL'
        END
    INTO v_receipt_result;

    /*
     * fed_receipts to conveyances.
     */
    SELECT
        CASE
            WHEN c.conveyanceid IS NULL THEN
                CASE
                    WHEN fr.conveyanceid IS NULL

                     AND COALESCE(
                             BTRIM(fr.bill_of_lading_airwaybill),
                             ''
                         ) = ''

                     AND COALESCE(
                             BTRIM(fr.house_bill),
                             ''
                         ) = ''

                     AND COALESCE(
                             BTRIM(fr.house_bill_partial_indicator),
                             ''
                         ) = ''

                    THEN
                        'PASS_NOT_FOUND'
                    ELSE
                        'FAIL'
                END

            WHEN
                    COALESCE(fr.bill_of_lading_airwaybill, '') =
                    COALESCE(c.bill_of_lading_airwaybill, '')

                AND COALESCE(fr.house_bill, '') =
                    COALESCE(c.house_bill, '')

                AND COALESCE(fr.house_bill_partial_indicator, '') =
                    COALESCE(c.house_bill_partial_indicator, '')

            THEN
                'PASS_MATCH'

            ELSE
                'FAIL'
        END
    INTO v_conveyance_result
    FROM preftz.fed_receipts fr
    LEFT JOIN preftz.conveyances c
      ON c.conveyanceid = fr.conveyanceid
    WHERE fr.receiptid = p_receiptid;

    v_conveyance_result :=
        COALESCE(v_conveyance_result, 'FAIL');

    /*
     * fed_receipts to receipt_cast_and_smelt.
     */
    SELECT
        CASE
            WHEN rcs.receiptid IS NULL THEN
                CASE
                    WHEN COALESCE(
                             BTRIM(fr.country_of_cast),
                             ''
                         ) = ''

                     AND COALESCE(
                             BTRIM(fr.primary_country_of_smelt),
                             ''
                         ) = ''

                     AND COALESCE(
                             BTRIM(fr.secondary_country_of_smelt),
                             ''
                         ) = ''
                    THEN
                        'PASS_NOT_FOUND'
                    ELSE
                        'FAIL'
                END

            WHEN
                    COALESCE(fr.country_of_cast, '') =
                    COALESCE(rcs.country_of_cast, '')

                AND COALESCE(fr.primary_country_of_smelt, '') =
                    COALESCE(rcs.primary_country_of_smelt, '')

                AND COALESCE(fr.secondary_country_of_smelt, '') =
                    COALESCE(rcs.secondary_country_of_smelt, '')
            THEN
                'PASS_MATCH'

            ELSE
                'FAIL'
        END
    INTO v_cast_smelt_result
    FROM preftz.fed_receipts fr
    LEFT JOIN preftz.receipt_cast_and_smelt rcs
      ON rcs.receiptid = fr.receiptid
    WHERE fr.receiptid = p_receiptid;

    v_cast_smelt_result :=
        COALESCE(v_cast_smelt_result, 'FAIL');

    /*
     * fed_receipts to receipt_melt_and_pour.
     */
    SELECT
        CASE
            WHEN rmp.receiptid IS NULL THEN
                CASE
                    WHEN COALESCE(
                             BTRIM(fr.country_of_melt),
                             ''
                         ) = ''

                     AND COALESCE(
                             BTRIM(fr.country_of_pour),
                             ''
                         ) = ''
                    THEN
                        'PASS_NOT_FOUND'
                    ELSE
                        'FAIL'
                END

            WHEN
                    COALESCE(fr.country_of_melt, '') =
                    COALESCE(rmp.country_of_melt, '')

                AND COALESCE(fr.country_of_pour, '') =
                    COALESCE(rmp.country_of_pour, '')
            THEN
                'PASS_MATCH'

            ELSE
                'FAIL'
        END
    INTO v_melt_pour_result
    FROM preftz.fed_receipts fr
    LEFT JOIN preftz.receipt_melt_and_pour rmp
      ON rmp.receiptid = fr.receiptid
    WHERE fr.receiptid = p_receiptid;

    v_melt_pour_result :=
        COALESCE(v_melt_pour_result, 'FAIL');

    /*
     * fed_receipts to receipt_derivative_content.
     */
    SELECT
        CASE
            WHEN rdc.receiptid IS NULL THEN
                CASE
                    WHEN COALESCE(
                             fr.steel_content_weight,
                             0::double precision
                         ) = 0::double precision

                     AND COALESCE(
                             fr.aluminum_content_weight,
                             0::double precision
                         ) = 0::double precision

                     AND COALESCE(
                             fr.copper_content_weight,
                             0::double precision
                         ) = 0::double precision
                    THEN
                        'PASS_NOT_FOUND'
                    ELSE
                        'FAIL'
                END

            WHEN
                    COALESCE(
                        fr.steel_content_weight,
                        0::double precision
                    ) =
                    COALESCE(
                        rdc.steel_content_weight,
                        0::double precision
                    )

                AND COALESCE(
                        fr.aluminum_content_weight,
                        0::double precision
                    ) =
                    COALESCE(
                        rdc.aluminum_content_weight,
                        0::double precision
                    )

                AND COALESCE(
                        fr.copper_content_weight,
                        0::double precision
                    ) =
                    COALESCE(
                        rdc.copper_content_weight,
                        0::double precision
                    )
            THEN
                'PASS_MATCH'

            ELSE
                'FAIL'
        END
    INTO v_derivative_content_result
    FROM preftz.fed_receipts fr
    LEFT JOIN preftz.receipt_derivative_content rdc
      ON rdc.receiptid = fr.receiptid
    WHERE fr.receiptid = p_receiptid;

    v_derivative_content_result :=
        COALESCE(v_derivative_content_result, 'FAIL');

    /*
     * fed_receipts to receipt_percentage_value.
     */
    SELECT
        CASE
            WHEN rpv.receiptid IS NULL THEN
                CASE
                    WHEN COALESCE(
                             fr.usmca_percent_us_value,
                             0::double precision
                         ) = 0::double precision
                    THEN
                        'PASS_NOT_FOUND'
                    ELSE
                        'FAIL'
                END

            WHEN
                COALESCE(
                    fr.usmca_percent_us_value,
                    0::double precision
                ) =
                COALESCE(
                    rpv.percent_us_value,
                    0::double precision
                )
            THEN
                'PASS_MATCH'

            ELSE
                'FAIL'
        END
    INTO v_percentage_value_result
    FROM preftz.fed_receipts fr
    LEFT JOIN preftz.receipt_percentage_value rpv
      ON rpv.receiptid = fr.receiptid
    WHERE fr.receiptid = p_receiptid;

    v_percentage_value_result :=
        COALESCE(v_percentage_value_result, 'FAIL');

    /*
     * fed_receipts to receipt_case_numbers.
     */
    SELECT
        CASE
            WHEN rcn.receiptid IS NULL THEN
                CASE
                    WHEN COALESCE(
                             BTRIM(fr.antidumping_case_number),
                             ''
                         ) = ''

                     AND COALESCE(
                             BTRIM(fr.countervailing_case_number),
                             ''
                         ) = ''
                    THEN
                        'PASS_NOT_FOUND'
                    ELSE
                        'FAIL'
                END

            WHEN
                    COALESCE(fr.antidumping_case_number, '') =
                    COALESCE(rcn.antidumping_case_number, '')

                AND COALESCE(fr.countervailing_case_number, '') =
                    COALESCE(rcn.countervailing_case_number, '')
            THEN
                'PASS_MATCH'

            ELSE
                'FAIL'
        END
    INTO v_case_number_result
    FROM preftz.fed_receipts fr
    LEFT JOIN preftz.receipt_case_numbers rcn
      ON rcn.receiptid = fr.receiptid
    WHERE fr.receiptid = p_receiptid;

    v_case_number_result :=
        COALESCE(v_case_number_result, 'FAIL');

    /*
     * fed_receipts to import_licenses.
     */
    SELECT
        CASE
            WHEN il.receiptid IS NULL THEN
                CASE
                    WHEN COALESCE(
                             BTRIM(fr.import_license_type),
                             ''
                         ) = ''

                     AND COALESCE(
                             BTRIM(fr.import_license_number),
                             ''
                         ) = ''
                    THEN
                        'PASS_NOT_FOUND'
                    ELSE
                        'FAIL'
                END

            WHEN
                    COALESCE(fr.import_license_type, '') =
                    COALESCE(il.import_license_type, '')

                AND COALESCE(fr.import_license_number, '') =
                    COALESCE(il.import_license_number, '')
            THEN
                'PASS_MATCH'

            ELSE
                'FAIL'
        END
    INTO v_import_license_result
    FROM preftz.fed_receipts fr
    LEFT JOIN preftz.import_licenses il
      ON il.receiptid = fr.receiptid
    WHERE fr.receiptid = p_receiptid;

    v_import_license_result :=
        COALESCE(v_import_license_result, 'FAIL');

    /*
     * fed_receipts to user_references.
     */
    SELECT
        CASE
            WHEN ur.tableid IS NULL THEN
                CASE
                    WHEN COALESCE(
                             BTRIM(fr.user_reference1),
                             ''
                         ) = ''

                     AND COALESCE(
                             BTRIM(fr.user_reference2),
                             ''
                         ) = ''

                     AND COALESCE(
                             BTRIM(fr.user_reference3),
                             ''
                         ) = ''

                     AND COALESCE(
                             BTRIM(fr.user_reference4),
                             ''
                         ) = ''

                     AND COALESCE(
                             BTRIM(fr.user_reference5),
                             ''
                         ) = ''
                    THEN
                        'PASS_NOT_FOUND'
                    ELSE
                        'FAIL'
                END

            WHEN
                    COALESCE(fr.user_reference1, '') =
                    COALESCE(ur.user_reference1, '')

                AND COALESCE(fr.user_reference2, '') =
                    COALESCE(ur.user_reference2, '')

                AND COALESCE(fr.user_reference3, '') =
                    COALESCE(ur.user_reference3, '')

                AND COALESCE(fr.user_reference4, '') =
                    COALESCE(ur.user_reference4, '')

                AND COALESCE(fr.user_reference5, '') =
                    COALESCE(ur.user_reference5, '')
            THEN
                'PASS_MATCH'

            ELSE
                'FAIL'
        END
    INTO v_user_reference_result
    FROM preftz.fed_receipts fr
    LEFT JOIN preftz.user_references ur
      ON ur.tableid = fr.receiptid
     AND ur.table_name = 'receipts'
    WHERE fr.receiptid = p_receiptid;

    v_user_reference_result :=
        COALESCE(v_user_reference_result, 'FAIL');

    /*
     * Optional tables pass when their status is either:
     *   PASS_MATCH
     *   PASS_NOT_FOUND
     */
    IF v_receipt_result = 'PASS_MATCH'

       AND v_conveyance_result IN (
           'PASS_MATCH',
           'PASS_NOT_FOUND'
       )

       AND v_cast_smelt_result IN (
           'PASS_MATCH',
           'PASS_NOT_FOUND'
       )

       AND v_melt_pour_result IN (
           'PASS_MATCH',
           'PASS_NOT_FOUND'
       )

       AND v_derivative_content_result IN (
           'PASS_MATCH',
           'PASS_NOT_FOUND'
       )

       AND v_percentage_value_result IN (
           'PASS_MATCH',
           'PASS_NOT_FOUND'
       )

       AND v_case_number_result IN (
           'PASS_MATCH',
           'PASS_NOT_FOUND'
       )

       AND v_import_license_result IN (
           'PASS_MATCH',
           'PASS_NOT_FOUND'
       )

       AND v_user_reference_result IN (
           'PASS_MATCH',
           'PASS_NOT_FOUND'
       )
    THEN
        v_result := 'PASS';
    ELSE
        v_result := 'FAIL';
    END IF;

    RAISE NOTICE
        E'compare_fed_receipt receiptid: %\n'
        '  receipt_result:            %\n'
        '  conveyance_result:         %\n'
        '  cast_smelt_result:         %\n'
        '  melt_pour_result:          %\n'
        '  derivative_content_result: %\n'
        '  percentage_value_result:   %\n'
        '  case_number_result:        %\n'
        '  import_license_result:     %\n'
        '  user_reference_result:     %\n'
        '  final_result:              %',
        p_receiptid,
        v_receipt_result,
        v_conveyance_result,
        v_cast_smelt_result,
        v_melt_pour_result,
        v_derivative_content_result,
        v_percentage_value_result,
        v_case_number_result,
        v_import_license_result,
        v_user_reference_result,
        v_result;

    RETURN v_result;
END;

$function$;