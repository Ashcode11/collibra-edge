-- =====================================================================
-- Deterministic synthetic data generator for bank_core.
-- Same seed => identical data on every rebuild. Re-running replaces data.
-- Run as bank_migrator. Volumes (approx.):
--   customers 5,000 | addresses 6,000 | kyc_checks 9,500 | accounts 8,000
--   cards 4,000 | payments 40,000 | transactions ~150,000
--
-- Nothing here is real:
--   NI numbers  QQnnnnnnC   (QQ prefix is never issued by HMRC)
--   emails      @example.com / @example.org (RFC 2606 reserved)
--   phones      +44 7700 900xxx (Ofcom drama range)
--   IBANs       GBkk SYNT ... (fictitious bank code; check digits valid)
--   cards       token + masked PAN in the 400000 test BIN, never a full PAN
-- =====================================================================
\set ON_ERROR_STOP on
SET ROLE bank_owner;
SET max_parallel_workers_per_gather = 0;   -- single-threaded => deterministic order
SELECT setseed(0.4242);

TRUNCATE transactions.transactions, payment.payments, account.cards, account.accounts,
         customer.kyc_checks, customer.addresses, customer.customers RESTART IDENTITY;

-- Valid-checksum synthetic GB IBAN: GB + check + SYNT + sort code + account number
CREATE OR REPLACE FUNCTION pg_temp.gb_iban(sort_code text, acct text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  -- S=28 Y=34 N=23 T=29, G=16 B=11 ; check = 98 - (BBAN||'GB00' as digits) mod 97
  SELECT 'GB' || lpad((98 - (('28342329' || sort_code || acct || '161100')::numeric % 97))::text, 2, '0')
         || 'SYNT' || sort_code || acct
$$;

-- ------------------------------------------------------------------ customers
WITH base AS (
  SELECT g,
         random() r_type, random() r_fn, random() r_ln, random() r_dob, random() r_nat,
         random() r_kyc, random() r_risk, random() r_pep, random() r_seg, random() r_br,
         random() r_on, random() r_title
  FROM generate_series(1, 5000) g
), names AS (
  SELECT b.*,
    (ARRAY['Oliver','Amelia','Mohammed','Olivia','Noah','Isla','Arjun','Ava','Leo','Mia','Yusuf','Sophia',
           'Harry','Grace','Kwame','Freya','Hiroshi','Priya','Jack','Zara','Luca','Chloe','Daniel','Aisha',
           'Ethan','Emily','Mateusz','Ella','Ravi','Lily','Thomas','Nia','Samuel','Hannah','Chen','Fatima'])
      [1 + floor(r_fn * 36)::int] AS fn,
    (ARRAY['Smith','Jones','Patel','Williams','Taylor','Khan','Brown','Davies','Evans','Wilson','Singh','Thomas',
           'Johnson','Roberts','Ahmed','Walker','Wright','Robinson','Thompson','White','Hughes','Edwards','Green',
           'Nowak','Okafor','Tanaka','Murphy','Campbell','Kaur','Hussain','Clarke','Lewis','Ali','Wood','Hall','Chen'])
      [1 + floor(r_ln * 36)::int] AS ln,
    (ARRAY['Northwind','Contoso','Fabrikam','Tailspin','Litware','Adventure Works','Proseware','Woodgrove',
           'Coho Vineyard','Alpine Ski','Blue Yonder','Wide World Importers'])[1 + floor(r_fn * 12)::int] AS co
  FROM base b
)
INSERT INTO customer.customers (customer_number, customer_type, title, first_name, last_name, legal_name,
  date_of_birth, national_insurance_number, email, mobile_phone, nationality_code, kyc_status, risk_rating,
  is_pep, segment, home_branch_code, onboarded_at, updated_at)
SELECT
  'C' || lpad(g::text, 9, '0'),
  CASE WHEN r_type < 0.9 THEN 'INDIVIDUAL' ELSE 'BUSINESS' END,
  CASE WHEN r_type < 0.9 THEN (ARRAY['Mr','Ms','Mrs','Dr','Mx'])[1 + floor(r_title * 5)::int] END,
  CASE WHEN r_type < 0.9 THEN fn END,
  CASE WHEN r_type < 0.9 THEN ln END,
  CASE WHEN r_type >= 0.9 THEN co || ' ' || (ARRAY['Ltd','Holdings Ltd','LLP','Group plc'])[1 + (g % 4)] || ' ' || g END,
  CASE WHEN r_type < 0.9 THEN date '1940-01-01' + floor(r_dob * 23000)::int END,
  CASE WHEN r_type < 0.9 THEN 'QQ' || lpad(g::text, 6, '0') || (ARRAY['A','B','C','D'])[1 + (g % 4)] END,
  CASE WHEN r_type < 0.9 THEN lower(fn || '.' || ln || g || '@example.com')
       ELSE 'finance' || g || '@example.org' END,
  '+447700900' || lpad((g % 1000)::text, 3, '0'),
  CASE WHEN r_nat < 0.75 THEN 'GB'
       ELSE (ARRAY['IE','FR','DE','PL','IN','US','JP','SG','ES','IT','AE','NL'])[1 + floor((r_nat - 0.75) * 4 * 12)::int] END,
  CASE WHEN r_kyc < 0.92 THEN 'VERIFIED' WHEN r_kyc < 0.97 THEN 'PENDING' ELSE 'EXPIRED' END,
  CASE WHEN r_risk < 0.80 THEN 'LOW' WHEN r_risk < 0.96 THEN 'MEDIUM' ELSE 'HIGH' END,
  r_pep < 0.01,
  CASE WHEN r_type < 0.9 THEN CASE WHEN r_seg < 0.85 THEN 'RETAIL' ELSE 'PREMIER' END
       ELSE CASE WHEN r_seg < 0.80 THEN 'SME' ELSE 'CORPORATE' END END,
  CASE WHEN r_type >= 0.9 AND r_seg >= 0.80 THEN 'CORP01'
       ELSE (ARRAY['LDN001','LDN002','MAN001','BHM001','EDI001','GLA001','LDS001','BRS001','CDF001','BEL001','DIG001'])[1 + floor(r_br * 11)::int] END,
  timestamptz '2005-01-01 00:00:00+00' + r_on * interval '7600 days',
  timestamptz '2005-01-01 00:00:00+00' + r_on * interval '7600 days'   -- fixed, not now(): reproducible
FROM names;

-- ------------------------------------------------------------------ addresses
INSERT INTO customer.addresses (customer_id, address_type, line_1, line_2, city, postcode, country_code, valid_from)
SELECT c.customer_id,
       CASE WHEN c.customer_type = 'BUSINESS' THEN 'REGISTERED' ELSE 'RESIDENTIAL' END,
       (1 + floor(random() * 240)::int) || ' ' ||
         (ARRAY['High Street','Station Road','Church Lane','Victoria Road','Park Avenue','Mill Lane','King Street',
                'Queen Street','The Crescent','Manor Road','Green Lane','Albert Road'])[1 + floor(random() * 12)::int],
       CASE WHEN random() < 0.2 THEN 'Flat ' || (1 + floor(random() * 40)::int) END,
       br.city,
       (ARRAY['EC2V','E14','M3','B3','EH2','G1','LS1','BS1','CF10','BT1'])[1 + floor(random() * 10)::int]
         || ' ' || (1 + floor(random() * 9)::int) || chr(65 + floor(random() * 26)::int) || chr(65 + floor(random() * 26)::int),
       'GB',
       c.onboarded_at::date
FROM customer.customers c
JOIN reference.branches br ON br.branch_code = c.home_branch_code;

INSERT INTO customer.addresses (customer_id, address_type, line_1, city, postcode, country_code, valid_from)
SELECT customer_id, 'CORRESPONDENCE', 'PO Box ' || (100 + customer_id), 'London',
       'EC1A ' || (1 + customer_id % 9) || 'BB', 'GB', onboarded_at::date + 30
FROM customer.customers
WHERE customer_id % 5 = 0;

-- ------------------------------------------------------------------ KYC checks
INSERT INTO customer.kyc_checks (customer_id, check_type, document_number, outcome, checked_at, checked_by)
SELECT c.customer_id,
       CASE WHEN c.customer_type = 'BUSINESS' THEN 'COMPANY_REGISTRY'
            WHEN c.customer_id % 3 = 0 THEN 'DRIVING_LICENCE' ELSE 'PASSPORT' END,
       'SYN' || lpad((c.customer_id * 37 % 1000000)::text, 9, '0'),
       CASE WHEN c.kyc_status = 'VERIFIED' THEN 'PASS' WHEN c.kyc_status = 'PENDING' THEN 'REFER' ELSE 'PASS' END,
       c.onboarded_at + interval '2 hours',
       'kyc-service'
FROM customer.customers c;

INSERT INTO customer.kyc_checks (customer_id, check_type, outcome, checked_at, checked_by)
SELECT c.customer_id, 'SANCTIONS_SCREENING',
       CASE WHEN c.risk_rating = 'HIGH' AND c.customer_id % 7 = 0 THEN 'REFER' ELSE 'PASS' END,
       timestamptz '2026-10-01 02:00:00+00',
       'screening-batch'
FROM customer.customers c
WHERE c.customer_id % 11 <> 0;     -- ~9% not yet screened in the latest batch (a data-quality talking point)

-- ------------------------------------------------------------------ accounts
WITH plan AS (
  SELECT c.customer_id, c.customer_type, c.segment, c.home_branch_code, c.onboarded_at, s.n,
         abs(hashint4(c.customer_id::int)::bigint) AS h
  FROM customer.customers c
  CROSS JOIN LATERAL generate_series(1,
       CASE WHEN abs(hashint4(c.customer_id::int)::bigint) % 10 < 5 THEN 1
            WHEN abs(hashint4(c.customer_id::int)::bigint) % 10 < 9 THEN 2 ELSE 3 END) AS s(n)
), numbered AS (
  SELECT p.*, br.sort_code,
         lpad((20000000 + row_number() OVER (ORDER BY p.customer_id, p.n))::text, 8, '0') AS acct,
         random() r_ccy, random() r_status, random() r_bal, random() r_open
  FROM plan p JOIN reference.branches br ON br.branch_code = p.home_branch_code
), typed AS (
  SELECT n.*,
    CASE WHEN customer_type = 'BUSINESS' THEN (CASE WHEN n = 1 THEN 'BC01' ELSE 'BS01' END)
         WHEN n = 1 THEN (CASE WHEN segment = 'PREMIER' THEN 'CA02' ELSE 'CA01' END)
         ELSE (ARRAY['SA01','SA02','CC01','LN01'])[1 + (h / 7 + n) % 4] END AS product_code
  FROM numbered n
)
INSERT INTO account.accounts (account_number, sort_code, iban, customer_id, product_code, currency_code, status,
  opened_on, closed_on, current_balance, available_balance, overdraft_limit, branch_code)
SELECT acct, sort_code, pg_temp.gb_iban(sort_code, acct), customer_id, product_code,
       CASE WHEN r_ccy < 0.95 OR product_code IN ('LN01','CC01') THEN 'GBP' WHEN r_ccy < 0.98 THEN 'EUR' ELSE 'USD' END,
       st.status,
       (onboarded_at + r_open * interval '400 days')::date,
       CASE WHEN st.status = 'CLOSED' THEN date '2026-06-30' END,
       bal.b, bal.b,
       CASE product_code WHEN 'CA01' THEN 500 WHEN 'CA02' THEN 2500 WHEN 'BC01' THEN 10000 ELSE 0 END,
       home_branch_code
FROM typed
CROSS JOIN LATERAL (SELECT CASE WHEN r_status < 0.90 THEN 'ACTIVE' WHEN r_status < 0.96 THEN 'DORMANT'
                                WHEN r_status < 0.99 THEN 'CLOSED' ELSE 'FROZEN' END AS status) st
CROSS JOIN LATERAL (SELECT round((
          CASE WHEN st.status = 'CLOSED' THEN 0
               WHEN product_code = 'LN01' THEN -(1000 + r_bal * 24000)
               WHEN product_code = 'CC01' THEN -(r_bal * 4000)
               WHEN product_code IN ('BC01','BS01') THEN exp(6 + r_bal * 7)
               WHEN product_code IN ('SA01','SA02') THEN exp(4 + r_bal * 7)
               ELSE exp(2 + r_bal * 7) - 300 END)::numeric, 2) AS b) bal;

-- ------------------------------------------------------------------ cards
INSERT INTO account.cards (account_id, card_token, pan_masked, card_scheme, card_type, expiry_month, expiry_year, status, issued_on)
SELECT a.account_id,
       md5('card-' || a.account_id),
       '400000******' || lpad((a.account_id * 7 % 10000)::text, 4, '0'),
       CASE WHEN a.account_id % 3 = 0 THEN 'MASTERCARD' ELSE 'VISA' END,
       CASE WHEN a.product_code = 'CC01' THEN 'CREDIT' ELSE 'DEBIT' END,
       1 + (a.account_id % 12)::int,
       2027 + (a.account_id % 4)::int,
       CASE WHEN a.status = 'ACTIVE' THEN 'ACTIVE' ELSE 'BLOCKED' END,
       a.opened_on + 7
FROM account.accounts a
WHERE a.product_code = 'CC01'
   OR (a.product_code IN ('CA01','CA02','BC01') AND a.account_id % 5 <> 0);

-- ------------------------------------------------------------------ payments
WITH n AS (SELECT max(account_id) AS max_acct FROM account.accounts),
base AS (
  SELECT g, random() r_acct, random() r_scheme, random() r_amt, random() r_status, random() r_ts,
         random() r_name, random() r_ch, random() r_purp, random() r_cty
  FROM generate_series(1, 40000) g
), s AS (
  SELECT b.*, 1 + floor(r_acct * n.max_acct)::bigint AS debtor,
         CASE WHEN r_scheme < 0.60 THEN 'FPS' WHEN r_scheme < 0.80 THEN 'BACS' WHEN r_scheme < 0.85 THEN 'CHAPS'
              WHEN r_scheme < 0.95 THEN 'SEPA_CT' ELSE 'SWIFT' END AS scheme
  FROM base b CROSS JOIN n
)
INSERT INTO payment.payments (end_to_end_id, debtor_account_id, creditor_name, creditor_iban, creditor_country, amount,
  currency_code, scheme, purpose_code, channel, status, sanctions_hit, initiated_at, settled_at)
SELECT
  md5('uetr-' || g)::uuid,
  debtor,
  CASE WHEN r_name < 0.6
       THEN (ARRAY['A','J','M','S','R','K','P','L'])[1 + floor(r_name * 13)::int] || '. ' ||
            (ARRAY['Smith','Patel','Jones','Khan','Brown','Taylor','Murphy','Singh','Okafor','Nowak'])[1 + (g % 10)]
       ELSE (ARRAY['British Gas Synthetic','Thames Water Synthetic','HMRC Synthetic','Council Tax Synthetic',
                   'Landlord Lettings Ltd','Acme Supplies Ltd','Global Freight GmbH','Pacific Traders Pte'])[1 + (g % 8)] END,
  CASE WHEN scheme IN ('FPS','BACS','CHAPS')
       THEN pg_temp.gb_iban('99' || lpad((g % 9999)::text, 4, '0'), lpad((30000000 + g)::text, 8, '0'))
       ELSE cty.code || '00SYNT' || lpad(g::text, 14, '0') END,     -- check digits 00 never occur in a real IBAN
  cty.code,
  round((CASE WHEN scheme = 'CHAPS' THEN exp(9 + r_amt * 4) ELSE exp(2 + r_amt * 7.5) END)::numeric, 2),
  CASE WHEN scheme = 'SEPA_CT' THEN 'EUR' WHEN scheme = 'SWIFT' THEN (CASE WHEN g % 2 = 0 THEN 'USD' ELSE 'EUR' END) ELSE 'GBP' END,
  scheme,
  (ARRAY['SALA','SUPP','RENT','TAXS','GDDS','OTHR','PENS','LOAN'])[1 + floor(r_purp * 8)::int],
  CASE WHEN r_ch < 0.55 THEN 'MOBILE' WHEN r_ch < 0.85 THEN 'ONLINE' WHEN r_ch < 0.90 THEN 'BRANCH' ELSE 'API' END,
  st.status,
  st.status = 'REJECTED' AND g % 6 = 0,
  ts.initiated,
  CASE WHEN st.status IN ('SETTLED','RETURNED') THEN
       ts.initiated + CASE scheme WHEN 'FPS' THEN interval '8 seconds' WHEN 'BACS' THEN interval '2 days'
                                  WHEN 'CHAPS' THEN interval '40 minutes' ELSE interval '1 day' END END
FROM s
CROSS JOIN LATERAL (SELECT CASE WHEN scheme IN ('FPS','BACS','CHAPS') THEN 'GB'
                                WHEN scheme = 'SEPA_CT' THEN (ARRAY['DE','FR','IE','NL','ES','IT'])[1 + floor(r_cty * 6)::int]
                                WHEN r_cty < 0.06 THEN (ARRAY['XA','XB'])[1 + (g % 2)]
                                ELSE (ARRAY['US','SG','JP','IN','AE','CH'])[1 + floor(r_cty * 6)::int] END AS code) cty
CROSS JOIN LATERAL (SELECT CASE WHEN r_status < 0.93 THEN 'SETTLED' WHEN r_status < 0.96 THEN 'REJECTED'
                                WHEN r_status < 0.97 THEN 'RETURNED' WHEN r_status < 0.98 THEN 'SCREENING'
                                ELSE 'INITIATED' END AS status) st
CROSS JOIN LATERAL (SELECT timestamptz '2025-11-01 00:00:00+00' + r_ts * interval '365 days' AS initiated) ts;

-- ------------------------------------------------------------------ transactions
-- 1) Debits for settled/returned payments (links ledger -> payment: lineage + reconciliation)
INSERT INTO transactions.transactions (account_id, payment_id, booking_date, value_date, direction, amount,
  currency_code, channel, description)
SELECT p.debtor_account_id, p.payment_id, p.settled_at::date, p.settled_at::date, 'DR', p.amount,
       p.currency_code, p.scheme, 'Payment to ' || p.creditor_name
FROM payment.payments p
WHERE p.status IN ('SETTLED','RETURNED');

-- 2) Card purchases
WITH c AS (SELECT array_agg(card_id ORDER BY card_id) ids, count(*) cnt FROM account.cards WHERE status = 'ACTIVE'),
base AS (SELECT g, random() r_card, random() r_m, random() r_amt, random() r_d FROM generate_series(1, 90000) g)
INSERT INTO transactions.transactions (account_id, card_id, booking_date, value_date, direction, amount, currency_code,
  channel, merchant_name, merchant_category_code, description)
SELECT cd.account_id, cd.card_id, d.booked, d.booked, 'DR',
       round((CASE m.mcc WHEN '5411' THEN 5 + r_amt * 120 WHEN '5812' THEN 8 + r_amt * 90
                         WHEN '4111' THEN 2 + r_amt * 30 WHEN '5541' THEN 20 + r_amt * 80 ELSE 5 + r_amt * 400 END)::numeric, 2),
       'GBP', 'CARD', m.name, m.mcc, 'Card purchase ' || m.name
FROM base b CROSS JOIN c
JOIN account.cards cd ON cd.card_id = c.ids[1 + floor(b.r_card * c.cnt)::int]
CROSS JOIN LATERAL (SELECT (ARRAY['Tesco Synthetic','Sainsbury Synthetic','Pret Synthetic','TfL Synthetic',
                                  'Shell Synthetic','Amazon Synthetic','Boots Synthetic','Nando Synthetic'])[1 + floor(b.r_m * 8)::int] AS name,
                           (ARRAY['5411','5411','5812','4111','5541','5999','5912','5812'])[1 + floor(b.r_m * 8)::int] AS mcc) m
CROSS JOIN LATERAL (SELECT date '2025-11-01' + floor(b.r_d * 365)::int AS booked) d;

-- 3) Monthly salary credits into individual current accounts
INSERT INTO transactions.transactions (account_id, booking_date, value_date, direction, amount, currency_code, channel, description)
SELECT a.account_id, m.d, m.d, 'CR',
       round((1800 + (abs(hashint4(a.account_id::int)::bigint) % 4200))::numeric, 2),
       'GBP', 'BACS', 'Salary ' || to_char(m.d, 'Mon YYYY')
FROM account.accounts a
JOIN customer.customers c ON c.customer_id = a.customer_id AND c.customer_type = 'INDIVIDUAL'
CROSS JOIN LATERAL (SELECT (date '2025-11-25' + (k || ' months')::interval)::date AS d FROM generate_series(0, 11) k) m
WHERE a.product_code IN ('CA01','CA02') AND a.status = 'ACTIVE' AND a.account_id % 3 <> 0;

ANALYZE;

-- Summary (printed in the Job log)
SELECT 'customers' AS table_name, count(*) FROM customer.customers
UNION ALL SELECT 'addresses', count(*) FROM customer.addresses
UNION ALL SELECT 'kyc_checks', count(*) FROM customer.kyc_checks
UNION ALL SELECT 'accounts', count(*) FROM account.accounts
UNION ALL SELECT 'cards', count(*) FROM account.cards
UNION ALL SELECT 'payments', count(*) FROM payment.payments
UNION ALL SELECT 'transactions', count(*) FROM transactions.transactions;
