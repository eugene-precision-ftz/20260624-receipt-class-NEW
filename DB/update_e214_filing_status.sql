-- PROCEDURE: preftz.update_e214_filing_status(character varying, character varying, timestamp without time zone, character varying, integer, integer)

-- DROP PROCEDURE IF EXISTS preftz.update_e214_filing_status(character varying, character varying, timestamp without time zone, character varying, integer, integer);

CREATE OR REPLACE PROCEDURE preftz.update_e214_filing_status(
	IN p_admission_number character varying,
	IN p_disposition_code character varying,
	IN p_response_date timestamp without time zone,
	IN p_error_code character varying,
	IN p_batchid integer,
	IN p_abi_fileid integer)
LANGUAGE 'plpgsql'
AS $BODY$

--CHANGE LOG: 
-- KK 08/01/2026 Change the way we handle privileged_date so that it reflects e214 filing; Added upd_classification_date for that purpose.
--MH 7/28/2025 added pre_receipt_status to handle pre-receipts audit trail
--NKM 04/11/2024 Added status codes '1T' and '1U' for SEIZED and SENT TO GENERAL ORDER respectively
-- JMM 12/06/2023 Added 214 response codes
--MH 2/28/2023 Added call to send procedure email if unexpected response from abi
--NKM 02/09/2023 Added status code '1G'
--NKM 11/08/2022 Added filing of goods acceptable message when a 214 is AUTHORIZED
--NKM 11/07/2022 Fixed typo and added placeholder for BD disposition message
--NKM 10/03/2022 Added has_pre-receipts and physical_arrival_status to e214_filing_statuses
--               Added reset of e214 filing status when data_updated_after_create = 'Y'
--NKM 08/30/2022 Added use of procedure_name to identify Acceptance messages
--               Added system_error to prevent user actions when unexpected inputs are encountered (will require support intervention)
--               Moved temporary_deposit_status = 'Y' from Acceptance to Authorization
--RTJ 08/08/2021 Add handling for temporary deposits
--RTJ 07/08/2021 Add call to preftz.remove_deleted_214_data for BH response
--               Pull data back from inventory_items_hold for rejected e214 delete  
--               Add delete_status to e214_filing_statuses table
--               Updated handling of B3/B7 disposition codes
--RTJ 06/20/2021 Add currently_filed field; update to Y when accepted or authorized;
--               update to N when deleted 
--NKM 05/17/2021 Now resets PAC status when a concurrence is posted
--NKM 02/03/2021 Expanded filing status variables to varchar(20) to match table

DECLARE
  v_e214_status                        VARCHAR(20);
  v_document_status                    VARCHAR(20);
  v_census_status                      VARCHAR(10);
  v_concur_status                      VARCHAR(10);
  v_general_order_status               VARCHAR(30);
  v_other_status                       VARCHAR(3);
  v_post_admission_correction_status   VARCHAR(20);
  v_last_response_date                 TIMESTAMP;
  upd_e214_status                      VARCHAR(20);
  upd_document_status                  VARCHAR(20);
  upd_census_status                    VARCHAR(10);
  upd_concur_status                    VARCHAR(10);
  upd_general_order_status             VARCHAR(30);
  upd_other_status                     VARCHAR(3);
  upd_post_admission_correction_status VARCHAR(20);
  upd_last_response_date               TIMESTAMP;
  v_currently_filed                    CHAR(1);  --RTJ 06/20/2021
  upd_currently_filed                  CHAR(1);  --RTJ 06/20/2021
  v_delete_status                      VARCHAR(10);  --RTJ 07/08/2021
  upd_delete_status                    VARCHAR(10);  --RTJ 07/08/2021
  v_temporary_deposit_status           VARCHAR(10);  --RTJ 08/04/2021
  upd_temporary_deposit_status         VARCHAR(10);  --RTJ 08/04/2021
  v_temporary_deposit                  CHAR(1);  --RTJ 08/04/2021
  upd_temporary_deposit                CHAR(1);  --RTJ 08/04/2021
  v_unexpected_branch                  BOOLEAN DEFAULT FALSE; --NKM 08/30/2022
  v_procedure_name                     VARCHAR(63); --NKM 08/30/2022
  v_update_after_create                VARCHAR(1);  --NKM 10/03/2022
  v_physical_arrival_status            VARCHAR(10); --NKM 10/03/2022
  v_data_updated_after_create          BOOLEAN;     --NKM 10/03/2022
  v_accept_status                      VARCHAR(20); --NKM 11/08/2022
  upd_accept_status                    VARCHAR(20); --NKM 11/08/2022
  v_pre_receipt_status				   VARCHAR(20); -- MH 7/28/2025
  upd_pre_receipt_status			   VARCHAR(20); -- MH 7/28/2025
  v_classification_date                DATE; -- KK 08/01/2026
  upd_classification_date              DATE; -- KK 08/01/2026

BEGIN

  SELECT procedure_name INTO v_procedure_name FROM preftz.abi_requests WHERE batchid = p_batchid; --NKM 09/05/2022

  SELECT s.e214_status, s.document_status, s.census_status, s.concur_status,
         s.general_order_status, s.other_status, s.last_response_date,
         s.post_admission_correction_status, s.currently_filed,  --RTJ 06/20/2021
         s.delete_status, s.temporary_deposit_status, s.temporary_deposit, --RTJ 07/08/2021/RTJ 08/04/2021
         s.data_updated_after_create, s.accept_status, --NKM 10/03/2022 --NKM 11/08/2022
		 s.pre_receipt_status, s.classification_date  -- KK 08/01/2026
    INTO v_e214_status, v_document_status, v_census_status, v_concur_status,
         v_general_order_status, v_other_status, v_last_response_date,
         v_post_admission_correction_status, v_currently_filed,  --RTJ 06/20/2021
         v_delete_status, v_temporary_deposit_status, v_temporary_deposit,  --RTJ 07/08/2021/RTJ 08/04/2021
         v_data_updated_after_create, v_accept_status ,--NKM 10/03/2022 --NKM 11/08/2022
		 v_pre_receipt_status, -- MH 7/28/2025
         v_classification_date -- KK 08/01/2026
    FROM preftz.e214_filing_statuses s
   WHERE s.zone_admission_no = p_admission_number;
   
  upd_e214_status = v_e214_status;
  upd_document_status = v_document_status;
  upd_census_status = v_census_status;
  upd_concur_status = v_concur_status;
  upd_general_order_status = v_general_order_status;
  upd_other_status = v_other_status;
  upd_post_admission_correction_status = v_post_admission_correction_status;
  upd_last_response_date = v_last_response_date;
  upd_currently_filed = v_currently_filed;  --RTJ 06/20/2021
  upd_delete_status = v_delete_status;  --RTJ 07/08/2021
  upd_temporary_deposit_status = v_temporary_deposit_status;  --RTJ 08/04/2021
  upd_temporary_deposit = v_temporary_deposit;  --RTJ 08/04/2021
  upd_accept_status = v_accept_status;  --NKM 11/08/2022
  upd_pre_receipt_status = v_pre_receipt_status; -- MH 7/28/2025
  upd_classification_date = v_classification_date; -- KK 08/01/2026
   
  CASE p_disposition_code
  
  WHEN 'B1' THEN --FT Data Accepted

      CASE v_procedure_name --NKM 09/05/2022
      WHEN 'file_e214' THEN
          IF v_e214_status = 'FILED' THEN
              upd_e214_status = 'ACCEPTED';
			  IF v_pre_receipt_status = 'FILED' THEN
			   	upd_pre_receipt_status = 'ACCEPTED';
			  END IF;
              --upd_temporary_deposit = 'N';  --RTJ 08/04/2021 --NKM 08/30/2022
          ELSIF v_temporary_deposit_status = 'FILED' THEN  --RTJ 08/04/2021
              upd_temporary_deposit_status = 'ACCEPTED';
              --upd_temporary_deposit = 'Y'; --NKM 08/30/2022
          ELSIF v_e214_status IN('AUTHORIZED','ACCEPTED') OR v_temporary_deposit_status IN('AUTHORIZED','ACCEPTED') THEN
              --do nothing
          ELSE 
              v_unexpected_branch = TRUE; --NKM 08/30/2022
          END IF;

      WHEN 'delete_e214' THEN
          IF v_delete_status = 'FILED' THEN
              upd_delete_status = 'ACCEPTED';
			   IF v_pre_receipt_status = 'FILED' THEN
			   	upd_pre_receipt_status = 'DELETE_ACCEPTED';
			  END IF;
          ELSIF v_delete_status IN('DELETED','ACCEPTED') THEN
              --do nothing
          ELSE
              v_unexpected_branch = TRUE; --NKM 08/30/2022
          END IF;
      ELSE
          v_unexpected_branch = TRUE; --NKM 08/30/2022
      END CASE; --procedure_name

  WHEN 'B2' THEN --FT Data Accepted with Warnings

      CASE v_procedure_name
      WHEN 'file_e214' THEN
          IF v_e214_status = 'FILED' THEN
              upd_e214_status = 'ACCEPTED';
			   IF v_pre_receipt_status = 'FILED' THEN
			   	upd_pre_receipt_status = 'ACCEPTED';
			  END IF;
              --upd_temporary_deposit = 'N';  --RTJ 08/04/2021 --NKM 08/30/2022
          ELSIF v_temporary_deposit_status = 'FILED' THEN  --RTJ 08/04/2021
              upd_temporary_deposit_status = 'ACCEPTED';
              --upd_temporary_deposit = 'Y'; --NKM 08/30/2022
          ELSIF v_e214_status IN('AUTHORIZED','ACCEPTED') OR v_temporary_deposit_status IN('AUTHORIZED','ACCEPTED') THEN
              --do nothing
          ELSE
              v_unexpected_branch = TRUE; --NKM 08/30/2022
          END IF;

      WHEN 'delete_e214' THEN
          IF v_delete_status = 'FILED' THEN
              upd_delete_status = 'ACCEPTED';
			   IF v_pre_receipt_status = 'FILED' THEN
			   	upd_pre_receipt_status = 'DELETED';
			  END IF;
          ELSIF v_delete_status IN('DELETED','ACCEPTED') THEN
              --do nothing
          ELSE
              v_unexpected_branch = TRUE; --NKM 08/30/2022
          END IF;
      ELSE
          v_unexpected_branch = TRUE; --NKM 08/30/2022
      END CASE; --procedure_name

      upd_census_status = 'WARNING';
      
  WHEN 'B3' THEN  --FT data rejected

      CASE v_procedure_name
      WHEN 'file_e214' THEN
          IF v_e214_status = 'FILED' THEN
              upd_e214_status = 'REJECTED';
			   IF v_pre_receipt_status = 'FILED' THEN
			   	upd_pre_receipt_status = 'REJECTED';
			  END IF;
          ELSIF v_temporary_deposit_status = 'FILED' THEN  --RTJ 08/04/2021
              upd_temporary_deposit_status = 'REJECTED';
          ELSIF v_e214_status = 'REJECTED' OR v_temporary_deposit_status = 'REJECTED' THEN
              --do nothing
          ELSE
              v_unexpected_branch = TRUE; --NKM 08/30/2022
          END IF;

      WHEN 'delete_e214' THEN
          IF v_delete_status = 'FILED' THEN  --RTJ 07/08/2021
              upd_delete_status = 'REJECTED';
			   IF v_pre_receipt_status = 'FILED' THEN
			   	upd_pre_receipt_status = 'REJECTED';
			  END IF;
    
              INSERT INTO preftz.inventory_items
                    (itemid, part_number, quantity_received, quantity_on_hand, receipt_date, receiptid,
                     zone_status, adjustid, latest_shipment_date)
              SELECT h.itemid, h.part_number, h.quantity_received, h.quantity_on_hand, h.receipt_date, 
                     h.receiptid, h.zone_status, h.adjustid, h.latest_shipment_date
                FROM preftz.inventory_items_hold h
               WHERE h.zone_admission_no = p_admission_number;
               
              DELETE FROM preftz.inventory_items_hold h
               WHERE h.zone_admission_no = p_admission_number;
          ELSE
              v_unexpected_branch = TRUE; --NKM 08/30/2022
          END IF;

      ELSE 
          v_unexpected_branch = TRUE; --NKM 08/30/2022
      END CASE; --procedure_name
      
  WHEN 'B4' THEN
  
      upd_document_status = 'PAPERLESS';

  WHEN 'B5' THEN
  
      upd_document_status = 'DOCUMENTS REQUIRED';

  WHEN 'B6' THEN --FZ data accepted
      CASE v_procedure_name
      WHEN 'file_e214_post_admission_correction_request' THEN
          IF v_post_admission_correction_status = 'FILED' THEN
              upd_post_admission_correction_status = 'ACCEPTED';
			   IF v_pre_receipt_status = 'FILED' THEN
			   	upd_pre_receipt_status = 'ACCEPTED';
			  END IF;
          ELSIF v_post_admission_correction_status IN('ACCEPTED','AUTHORIZED') THEN
              --no nothing
          ELSE
              v_unexpected_branch = TRUE; --NKM 08/30/2022
          END IF;

      WHEN 'concur_e214' THEN
          IF v_concur_status = 'FILED' THEN
              upd_concur_status = 'ACCEPTED';
			   IF v_pre_receipt_status = 'FILED' THEN
			   	upd_pre_receipt_status = 'ACCEPTED';
			  END IF;
          ELSIF v_concur_status IN('ACCEPTED','POSTED') THEN
              --no nothing
          ELSE
              v_unexpected_branch = TRUE; --NKM 08/30/2022
          END IF;
      WHEN 'accept_e214' THEN --NKM 11/08/2022
          IF v_accept_status = 'FILED' THEN
              upd_accept_status = 'MSG RECEIVED';
          ELSIF v_accept_status = 'MSG RECEIVED' THEN
              --no nothing
          ELSE
              v_unexpected_branch = TRUE;
          END IF;
      ELSE 
          v_unexpected_branch = TRUE; --NKM 08/30/2022
      END CASE; --procedure_name

  WHEN 'B7' THEN  --FZ data rejected
      CASE v_procedure_name
      WHEN 'file_e214_post_admission_correction_request' THEN
          IF v_post_admission_correction_status = 'FILED' THEN
              upd_post_admission_correction_status = 'REJECTED';
			   IF v_pre_receipt_status = 'FILED' THEN
			   	upd_pre_receipt_status = 'REJECTED';
			  END IF;
          ELSIF v_post_admission_correction_status = 'REJECTED' THEN
              --no nothing
          ELSE
              v_unexpected_branch = TRUE; --NKM 08/30/2022
          END IF;

      WHEN 'concur_e214' THEN
          IF v_concur_status = 'FILED' THEN
              upd_concur_status = 'REJECTED';
			   IF v_pre_receipt_status = 'FILED' THEN
			   	upd_pre_receipt_status = 'REJECTED';
			  END IF;
          ELSIF v_concur_status = 'REJECTED' THEN
              --no nothing
          ELSE
              v_unexpected_branch = TRUE; --NKM 08/30/2022
          END IF;
      WHEN 'accept_e214' THEN --NKM 11/08/2022
          IF v_accept_status = 'FILED' THEN
              upd_accept_status = 'REJECTED';
			   IF v_pre_receipt_status = 'FILED' THEN
			   	upd_pre_receipt_status = 'REJECTED';
			  END IF;
          ELSIF v_accept_status = 'REJECTED' THEN
              --no nothing
          ELSE
              v_unexpected_branch = TRUE;
          END IF;
      ELSE 
          v_unexpected_branch = TRUE; --NKM 08/30/2022
      END CASE; --procedure_name
      
  WHEN 'B8' THEN --Admission Concurrence
 
      IF v_procedure_name = 'concur_e214' THEN
          IF v_concur_status IN('FILED','ACCEPTED') THEN
              upd_concur_status = 'POSTED';
              upd_post_admission_correction_status = NULL; --NKM 05/17/21
			   IF v_pre_receipt_status IN('FILED','ACCEPTED') THEN
			   	upd_pre_receipt_status = 'POSTED';
			  END IF;
          ELSIF v_concur_status = 'POSTED' THEN
              --no nothing
          ELSE
              v_unexpected_branch = TRUE; --NKM 08/30/2022
          END IF;
      ELSE
         v_unexpected_branch = TRUE; --NKM 08/30/2022
      END IF;
 
  WHEN 'BD' THEN --Goods Acceptable to Zone --NKM 11/07/2022
      IF v_accept_status IN('FILED','MSG RECEIVED') THEN --NKM 11/08/2022
          upd_accept_status = 'CONFIRMED';
		 IF v_pre_receipt_status IN('FILED','MSG RECEIVED') THEN
		  upd_pre_receipt_status = 'CONFIRMED';
		 END IF;
      ELSIF v_accept_status = 'CONFIRMED' THEN
          --no nothing
      ELSE
          v_unexpected_branch = TRUE;
      END IF;

  WHEN 'BF' THEN --Admission Authorized

      IF v_procedure_name = 'file_e214' THEN
          IF v_e214_status IN('FILED','ACCEPTED') THEN
              upd_e214_status = 'AUTHORIZED';
              upd_classification_date = CURRENT_DATE;  -- KK 08/01/2026
              upd_temporary_deposit = 'N';  --RTJ 08/04/2021
              upd_currently_filed = 'Y';  --RTJ 06/20/2021
			  IF v_pre_receipt_status IN('FILED','ACCEPTED') THEN
				  upd_pre_receipt_status = 'AUTHORIZED';
			  END IF;
          ELSIF v_temporary_deposit_status IN('FILED','ACCEPTED') THEN  --RTJ 08/04/2021
              upd_temporary_deposit_status = 'AUTHORIZED';
              upd_temporary_deposit = 'Y';
              upd_currently_filed = 'Y';  --RTJ 06/20/2021
          ELSIF (v_e214_status = 'AUTHORIZED' AND v_temporary_deposit='N')
             OR (v_temporary_deposit_status = 'AUTHORIZED' AND v_temporary_deposit='Y') THEN
              --do nothing
          ELSE
              v_unexpected_branch = TRUE; --NKM 08/30/2022
              --NOTE: this includes (v_temporary_deposit_status = 'AUTHORIZED' AND v_e214_status IS NULL)
          END IF;
      ELSE
         v_unexpected_branch = TRUE; --NKM 08/30/2022
      END IF;

  WHEN 'BH' THEN --Admission Deleted
  
      IF v_procedure_name = 'delete_e214' THEN
          IF v_delete_status IN('FILED','ACCEPTED') THEN
    
              CALL preftz.remove_deleted_214_data(p_admission_number);
              
              upd_e214_status = 'DELETED';
              upd_document_status = NULL;
              upd_census_status = NULL;
              upd_concur_status = NULL;
              upd_general_order_status = NULL;
              upd_other_status = NULL;
              upd_post_admission_correction_status = NULL;
              upd_currently_filed = 'N';
              upd_delete_status = 'DELETED';  --RTJ 07/08/2021
              upd_temporary_deposit_status = NULL;  --RTJ 08/04/2021
              upd_temporary_deposit = 'N';  --RTJ 08/04/2021
			   IF v_pre_receipt_status IN('FILED','ACCEPTED') THEN
				  upd_pre_receipt_status = 'DELETED';
			  END IF;
    
          ELSIF v_delete_status = 'DELETED' THEN
              --do nothing
          ELSE
              v_unexpected_branch = TRUE; --NKM 08/30/2022
          END IF;
      ELSE
          v_unexpected_branch = TRUE; --NKM 08/30/2022
      END IF;
                
  WHEN '1R' THEN --Pending GO
  
      IF v_general_order_status IS NULL
      OR v_general_order_status NOT IN('ORDERED TO GENERAL ORDER','SENT TO GENERAL ORDER','SEIZED')
      THEN
          upd_general_order_status = 'PENDING ELIGIBLE GENERAL ORDER';
      END IF;
      
  WHEN '1S' THEN --Ordered to GO
  
      IF v_general_order_status IS NULL
      OR v_general_order_status NOT IN('SENT TO GENERAL ORDER','SEIZED')
      THEN
          upd_general_order_status = 'ORDERED TO GENERAL ORDER';
      END IF;
      
  WHEN '1U' THEN --Sent to GO --will supercede any other GO status
  
      upd_general_order_status = 'SENT TO GENERAL ORDER';
      
  WHEN '1T' THEN --Seized --will supercede any other GO status
  
      upd_general_order_status = 'SEIZED';
      
  WHEN 'JAP' THEN --PAC Approved
  
      IF v_post_admission_correction_status IN('FILED','ACCEPTED') THEN
          upd_post_admission_correction_status = 'APPROVED';
          upd_concur_status = NULL;  --an approved PAC results in the 214 being unconcurred
		   IF v_pre_receipt_status IN('FILED','ACCEPTED') THEN
				  upd_pre_receipt_status = 'APPROVED';
		   END IF;
      ELSE
          v_unexpected_branch = TRUE; --NKM 08/30/2022
      END IF;
      
  WHEN 'JDE' THEN --PAC Rejected
  
      IF v_post_admission_correction_status IN('FILED','ACCEPTED') THEN
          upd_post_admission_correction_status = 'DECLINED';
		   IF v_pre_receipt_status IN('FILED','ACCEPTED') THEN
				  upd_pre_receipt_status = 'DECLINED';
			  END IF;
      ELSE
          v_unexpected_branch = TRUE; --NKM 08/30/2022
      END IF;
      
  WHEN '19','1C','1D','1G','1J','1K','1L','4E','50','54','55','95', '93','89' THEN --Other known responses

      --no e214 update needed
      IF v_other_status IS NULL
      OR v_other_status IN ('19','1C','1D','1G','1J','1K','1L','4E','50','54','55','95','93','89') THEN --same list as above (will not replace an unknown response)
          upd_other_status = p_disposition_code;
      END IF;
      
  ELSE --Other unknown responses

      --response not handled
      v_unexpected_branch = TRUE; --NKM 08/30/2022
      upd_other_status = p_disposition_code; --unknown response always overrides
          
  END CASE;
  
  IF p_response_date > v_last_response_date OR v_last_response_date IS NULL THEN
      upd_last_response_date = p_response_date;
  END IF;

  
  UPDATE preftz.e214_filing_statuses
     SET e214_status = upd_e214_status,
         document_status = upd_document_status,
         census_status = upd_census_status,
         concur_status = upd_concur_status,
         general_order_status = upd_general_order_status,
         other_status = upd_other_status,
         last_response_date = upd_last_response_date,
         post_admission_correction_status = upd_post_admission_correction_status,
         currently_filed = upd_currently_filed,  --RTJ 06/20/2021
         delete_status = upd_delete_status,  --RTJ 07/08/2021
         temporary_deposit_status = upd_temporary_deposit_status,  --RTJ 08/04/2021
         temporary_deposit = upd_temporary_deposit,  --RTJ 08/04/2021
         physical_arrival_status = preftz.get_arrival_status(p_admission_number), --NKM 10/03/2022 --NKM 11/07/2022
         accept_status = upd_accept_status, --NKM 11/08/2022
		 pre_receipt_status = upd_pre_receipt_status, -- MH 7/28/2025
         classification_date = COALESCE(classification_date, upd_classification_date)  -- KK 08/01/2025 only overwrite if date already null
   WHERE zone_admission_no = p_admission_number;

   IF v_data_updated_after_create IS TRUE THEN --NKM 10/03/2022 reset status if necesssary due to data update --NKM 11/07/2022
       CALL preftz.update_e214_after_create(p_admission_number);
   END IF;

   --NKM 11/08/2022 File goods acceptable message if status is PENDING and 214 has been authorized
   IF upd_accept_status = 'PENDING' AND upd_e214_status = 'AUTHORIZED' THEN
       CALL preftz.accept_e214(p_admission_number);
   END IF;

   --NKM 09/05/2022 - Hold further processing of admission due to unexpected input (error)
   IF v_unexpected_branch THEN --NKM 08/30/2022
       INSERT INTO preftz.user_logs (title, body, details)
       VALUES ('Unexpected e214 response received from ABI - Please contact support',
               'Error processing ABI resonse to admission ' || COALESCE(p_admission_number,''),
               'File ID ' || COALESCE(p_abi_fileid,0));
  --MH 2/28/2023
CALL preftz.send_procedure_email('UNEXPECTED_ABI_RESPONSE','ADMIN');
-- end MH 2/28/2023
       UPDATE preftz.e214_filing_statuses
          SET system_error = TRUE --NKM 08/30/2022
        WHERE zone_admission_no = p_admission_number;
   END IF;

END;
$BODY$;



