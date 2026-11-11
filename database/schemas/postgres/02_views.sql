-- =====================================================================
-- Reporting views. They exist to give technical lineage something real
-- to trace: each view derives from several base tables, e.g.
--   customers + accounts + kyc_checks -> reporting.v_customer_360
-- Run as bank_migrator. Idempotent (CREATE OR REPLACE).
-- =====================================================================
\set ON_ERROR_STOP on
SET ROLE bank_owner;

CREATE OR REPLACE VIEW reporting.v_customer_360 AS
SELECT c.customer_id,
       c.customer_number,
       c.customer_type,
       coalesce(c.legal_name, c.first_name || ' ' || c.last_name) AS display_name,
       c.segment,
       c.risk_rating,
       c.is_pep,
       c.kyc_status,
       b.branch_name                                              AS home_branch,
       count(a.account_id)                                        AS account_count,
       coalesce(sum(a.current_balance) FILTER (WHERE a.currency_code = 'GBP'), 0) AS total_gbp_balance,
       (SELECT k.outcome FROM customer.kyc_checks k
         WHERE k.customer_id = c.customer_id
         ORDER BY k.checked_at DESC LIMIT 1)                      AS latest_kyc_outcome
FROM customer.customers c
JOIN reference.branches b ON b.branch_code = c.home_branch_code
LEFT JOIN account.accounts a ON a.customer_id = c.customer_id AND a.status <> 'CLOSED'
GROUP BY c.customer_id, b.branch_name;
COMMENT ON VIEW reporting.v_customer_360 IS 'Single customer view for relationship managers. Derived from customer.customers, account.accounts, customer.kyc_checks, reference.branches.';

CREATE OR REPLACE VIEW reporting.v_daily_payment_volumes AS
SELECT date_trunc('day', p.initiated_at)::date AS payment_date,
       p.scheme,
       p.currency_code,
       p.status,
       count(*)                                AS payment_count,
       sum(p.amount)                           AS total_amount
FROM payment.payments p
GROUP BY 1, 2, 3, 4;
COMMENT ON VIEW reporting.v_daily_payment_volumes IS 'Daily payment volumes by scheme, currency and status. Feeds Finance and Treasury MI.';

CREATE OR REPLACE VIEW reporting.v_aml_high_risk_payments AS
SELECT p.payment_id,
       p.end_to_end_id,
       c.customer_number,
       c.risk_rating,
       c.is_pep,
       p.amount,
       p.currency_code,
       p.scheme,
       p.creditor_country,
       cc.is_high_risk AS creditor_country_high_risk,
       p.sanctions_hit,
       p.status,
       p.initiated_at
FROM payment.payments p
JOIN account.accounts a    ON a.account_id = p.debtor_account_id
JOIN customer.customers c  ON c.customer_id = a.customer_id
JOIN reference.countries cc ON cc.country_code = p.creditor_country
WHERE p.sanctions_hit
   OR cc.is_high_risk
   OR (c.risk_rating = 'HIGH' AND p.amount >= 10000)
   OR (c.is_pep AND p.amount >= 5000);
COMMENT ON VIEW reporting.v_aml_high_risk_payments IS 'Payments meeting Financial Crime alert criteria. Consumed by the AML case-management system.';

CREATE OR REPLACE VIEW reporting.v_account_monthly_activity AS
SELECT t.account_id,
       date_trunc('month', t.booking_date)::date              AS month,
       count(*)                                               AS txn_count,
       sum(t.amount) FILTER (WHERE t.direction = 'CR')        AS credits,
       sum(t.amount) FILTER (WHERE t.direction = 'DR')        AS debits
FROM transactions.transactions t
GROUP BY 1, 2;
COMMENT ON VIEW reporting.v_account_monthly_activity IS 'Monthly credits/debits per account. Derived from transactions.transactions.';
