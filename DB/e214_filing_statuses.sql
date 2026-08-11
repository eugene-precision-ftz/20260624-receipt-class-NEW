--Change Log: 
-- KK 08/01/2026 Change the way we handle privileged_date so that it reflects e214 filing; Added classification_date for that purpose.
-- KK 05/06/2026 added timestamps for e214_status and concur_status changes, and trigger update.
--MH 7/30/2025 added ptt_status	
--MH 7/29/2025 added pre_receipt_status	
-- KK 05/07/2025 added flag bypass_added_tariffs to bypass adding any additional tariffs. 	
--NKM 10/30/2023 added field crossdock_created 	
--NKM 03/15/2023 added field pga_required 	
--JMM 01/24/2023 added field notifications 	
--NKM 11/08/2022 added accept_status 	
--NKM 10/03/2022 added has_pre_receipts and physical_arrival_status 	
--NKM 08/30/2022 add system_error 	
--RTJ 08/08/2021 add temporary_deposit_status and temporary_deposit flag 	
--RTJ 07/09/2021 add delete_status 	
 	
CREATE TABLE IF NOT EXISTS preftz.e214_filing_statuses ( 	
    zone_admission_no varchar(10) primary key, 	
    e214_date date, 	
    e214_status varchar(20),  -- CREATED, FILED, ACCEPTED, REJECTED, AUTHORIZED, DELETED 	
    document_status varchar(20),  -- PAPERLESS, DOCUMENTS REQUIRED 	
    census_status varchar(10),  -- blank or WARNING 	
    concur_status varchar(10),  -- FILED, ACCEPTED, POSTED, REJECTED 	
    general_order_status varchar(30),  -- PENDING ELIGIBLE GENERAL ORDER, ORDERED TO GENERAL ORDER 	
    other_status varchar(3),  --disposition code of any other message except 1C 	
    last_response_date timestamp, 	
    data_updated_after_create char(1) default 'N', 	
    post_admission_correction_status varchar(20),  --FILED, ACCEPTED, APPROVED, DECLINED  	
    create_status varchar(20),  --PASS or FAIL 	
    email_flag varchar(50), 	
    currently_filed char(1) default 'N', 	
    delete_status varchar(10),  --FILED, ACCEPTED, REJECTED, DELETED 	
    temporary_deposit_status varchar(10), --CREATED, FILED, ACCEPTED, REJECTED, AUTHORIZED, DELETED 	
    temporary_deposit char(1) default 'N', 	
    system_error boolean default false, 	
    has_pre_receipts boolean, 	
    physical_arrival_status varchar(10), 	
    accept_status varchar(20), 	
    notifications varchar(50), --field for CBP and other notifications such as PGA required 	
    pga_required boolean, 	
    crossdock_created boolean, 	
    bypass_added_tariffs boolean default false,	
    pre_receipt_status VARCHAR(20) ,
    ptt_status VARCHAR(10),
    e214_status_changed_at timestamp,
    concur_status_changed_at timestamp,
    classification_date DATE  -- KK 08/01/2026
); 	
--MH 7/1/2021 adding trigger  	
CREATE OR REPLACE TRIGGER notify_order_event 	
    AFTER UPDATE  	
    ON preftz.e214_filing_statuses 	
    FOR EACH ROW 	
    EXECUTE FUNCTION preftz.notify_event(); 	

-- KK 05/06/2026
CREATE OR REPLACE TRIGGER trg_e214_status_changed
    BEFORE UPDATE OF e214_status, concur_status
    ON preftz.e214_filing_statuses
    FOR EACH ROW
    EXECUTE FUNCTION preftz.e214_status_change_trigger();


