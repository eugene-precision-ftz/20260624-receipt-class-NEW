-- preftz.receipt_classifications definition

-- Drop table

-- DROP TABLE preftz.receipt_classifications;

CREATE TABLE IF NOT EXISTS preftz.receipt_classifications_v2 (
	receiptid int4 NOT NULL,
	created_date timestamp DEFAULT now(),
	harmonized_tariff_schedule_number varchar(10) NOT NULL,
	special_programs_indicator varchar(2) NULL,
	unit_value float8 NULL,
	tariff_type varchar(15) NULL,
	distinct_tariff_line_indicator bpchar(1) NULL,
	primary_tariff bpchar(1) NULL,
	quantity1_rate float8 NULL,
	quantity2_rate float8 NULL,
	unit_duty_liability float8 NULL,
	CONSTRAINT receipt_classifications2_pkey PRIMARY KEY (receiptid, harmonized_tariff_schedule_number)
);
CREATE INDEX IF NOT EXISTS rc2_hts_number ON preftz.receipt_classifications_v2 USING btree (harmonized_tariff_schedule_number);
CREATE INDEX IF NOT EXISTS rc2_receipt_id ON preftz.receipt_classifications_v2 USING btree (receiptid);-- PROCEDURE: preftz.calculate_derivative_duty_liability_v2(integer)

