-- =====================================================================
-- Deterministic synthetic CRM data. RAND(seed) per row => identical data
-- on every rebuild. Re-running replaces data.
-- contacts 4,600 (4,000 linked to bank_core customers + 600 prospects)
-- interactions ~14,000 | complaints ~900 | campaigns 6 | responses ~18,000
-- =====================================================================
USE crm;
SET SESSION cte_max_recursion_depth = 50000;
SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE campaign_responses;
TRUNCATE TABLE marketing_campaigns;
TRUNCATE TABLE complaints;
TRUNCATE TABLE interactions;
TRUNCATE TABLE contacts;
SET FOREIGN_KEY_CHECKS = 1;

-- ------------------------------------------------------------------ contacts
INSERT INTO contacts (customer_number, full_name, email, phone, date_of_birth, lifecycle_stage,
                      marketing_consent, consent_updated_at, created_at, updated_at)
WITH RECURSIVE seq (g) AS (SELECT 1 UNION ALL SELECT g + 1 FROM seq WHERE g < 4600)
SELECT
  IF(g <= 4000, CONCAT('C', LPAD(g, 9, '0')), NULL),
  CONCAT(ELT(1 + FLOOR(RAND(g * 7919 + 1) * 12), 'Oliver','Amelia','Mohammed','Olivia','Noah','Isla',
                                                 'Arjun','Ava','Leo','Mia','Yusuf','Sophia'), ' ',
         ELT(1 + FLOOR(RAND(g * 7919 + 2) * 12), 'Smith','Jones','Patel','Williams','Taylor','Khan',
                                                 'Brown','Davies','Evans','Wilson','Singh','Thomas')),
  CONCAT('contact', g, '@', IF(g <= 4000, 'example.com', 'example.net')),
  CONCAT('+447700900', LPAD(g MOD 1000, 3, '0')),
  IF(RAND(g * 7919 + 3) < 0.7, DATE_ADD('1945-01-01', INTERVAL FLOOR(RAND(g * 7919 + 4) * 22000) DAY), NULL),
  CASE WHEN g > 4000 THEN 'PROSPECT' WHEN RAND(g * 7919 + 5) < 0.08 THEN 'LAPSED' ELSE 'CUSTOMER' END,
  RAND(g * 7919 + 6) < 0.42,
  DATE_ADD('2024-01-01', INTERVAL FLOOR(RAND(g * 7919 + 7) * 1000) DAY),
  DATE_ADD('2015-01-01', INTERVAL FLOOR(RAND(g * 7919 + 8) * 4000) DAY),
  DATE_ADD('2024-01-01', INTERVAL FLOOR(RAND(g * 7919 + 7) * 1000) DAY)   -- fixed, not NOW(): reproducible
FROM seq;

-- ------------------------------------------------------------------ interactions
INSERT INTO interactions (contact_id, channel, topic, agent_id, notes, occurred_at)
WITH RECURSIVE seq (g) AS (SELECT 1 UNION ALL SELECT g + 1 FROM seq WHERE g < 14000)
SELECT
  1 + FLOOR(RAND(g * 104729 + 1) * 4600),
  ELT(1 + FLOOR(RAND(g * 104729 + 2) * 5), 'PHONE','EMAIL','CHAT','BRANCH','SOCIAL'),
  ELT(1 + FLOOR(RAND(g * 104729 + 3) * 8), 'Card lost','Payment query','Overdraft','Fraud concern',
      'Address change','Mortgage enquiry','App login','Fee dispute'),
  CONCAT('AGT', LPAD(1 + FLOOR(RAND(g * 104729 + 4) * 120), 4, '0')),
  -- some notes deliberately contain synthetic PII, as real agent notes often do
  CASE WHEN RAND(g * 104729 + 5) < 0.15
       THEN CONCAT('Customer called from +447700900', LPAD(g MOD 1000, 3, '0'), ', verified DOB and postcode.')
       WHEN RAND(g * 104729 + 5) < 0.25
       THEN CONCAT('Asked to email statements to contact', g MOD 4600, '@example.com')
       ELSE 'Resolved at first contact.' END,
  DATE_ADD('2025-11-01', INTERVAL FLOOR(RAND(g * 104729 + 6) * 365 * 24) HOUR)
FROM seq;

-- ------------------------------------------------------------------ complaints
INSERT INTO complaints (complaint_ref, contact_id, product_area, category, received_at, resolved_at,
                        outcome, redress_amount, referred_to_fos)
WITH RECURSIVE seq (g) AS (SELECT 1 UNION ALL SELECT g + 1 FROM seq WHERE g < 900),
c AS (
  SELECT g, RAND(g * 15485863 + 1) r_out,
         DATE_ADD('2025-11-01', INTERVAL FLOOR(RAND(g * 15485863 + 2) * 365) DAY) AS received
  FROM seq
)
SELECT
  CONCAT('CMP-2026-', LPAD(g, 5, '0')),
  1 + FLOOR(RAND(g * 15485863 + 3) * 4000),
  ELT(1 + FLOOR(RAND(g * 15485863 + 4) * 6), 'CURRENT_ACCOUNT','SAVINGS','CARDS','PAYMENTS','LOANS','DIGITAL'),
  ELT(1 + FLOOR(RAND(g * 15485863 + 5) * 6), 'Charges and fees','Service delay','Fraud and scams',
      'Account closure','Incorrect information','App outage'),
  received,
  IF(r_out < 0.88, DATE_ADD(received, INTERVAL 1 + FLOOR(RAND(g * 15485863 + 6) * 55) DAY), NULL),
  CASE WHEN r_out < 0.35 THEN 'UPHELD' WHEN r_out < 0.75 THEN 'NOT_UPHELD'
       WHEN r_out < 0.88 THEN 'PARTIALLY_UPHELD' ELSE 'OPEN' END,
  IF(r_out < 0.35 OR (r_out >= 0.75 AND r_out < 0.88), ROUND(25 + RAND(g * 15485863 + 7) * 475, 2), 0),
  RAND(g * 15485863 + 8) < 0.04
FROM c;

-- ------------------------------------------------------------------ campaigns + responses
INSERT INTO marketing_campaigns (campaign_code, name, channel, starts_on, ends_on) VALUES
  ('SAV-SPRING26','Spring Savings Boost','EMAIL','2026-03-01','2026-04-30'),
  ('CC-BALXFER26','Credit Card Balance Transfer','APP','2026-02-01','2026-03-31'),
  ('PREM-UPG26','Premier Upgrade','EMAIL','2026-05-01','2026-06-30'),
  ('ISA-SEASON26','ISA Season','POST','2026-01-15','2026-04-05'),
  ('APP-ADOPT26','Mobile App Adoption','SMS','2026-06-01','2026-08-31'),
  ('LOAN-SUMMER26','Summer Personal Loan','EMAIL','2026-07-01','2026-08-31');

INSERT INTO campaign_responses (campaign_id, contact_id, response, responded_at)
WITH RECURSIVE seq (g) AS (SELECT 1 UNION ALL SELECT g + 1 FROM seq WHERE g < 18000)
SELECT
  1 + FLOOR(RAND(g * 32452843 + 1) * 6),
  1 + FLOOR(RAND(g * 32452843 + 2) * 4600),
  ELT(1 + FLOOR(RAND(g * 32452843 + 3) * 10), 'SENT','SENT','SENT','SENT','OPENED','OPENED','OPENED',
      'CLICKED','CONVERTED','UNSUBSCRIBED'),
  DATE_ADD('2026-01-15', INTERVAL FLOOR(RAND(g * 32452843 + 4) * 220) DAY)
FROM seq;

ANALYZE TABLE contacts, interactions, complaints, marketing_campaigns, campaign_responses;

SELECT 'contacts' AS table_name, COUNT(*) AS row_count FROM contacts
UNION ALL SELECT 'interactions', COUNT(*) FROM interactions
UNION ALL SELECT 'complaints', COUNT(*) FROM complaints
UNION ALL SELECT 'marketing_campaigns', COUNT(*) FROM marketing_campaigns
UNION ALL SELECT 'campaign_responses', COUNT(*) FROM campaign_responses;
