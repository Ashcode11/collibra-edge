-- =====================================================================
-- Object privileges. Run as the superuser AFTER the schema exists.
-- Idempotent. Default privileges make sure tables created later
-- inherit the same model without anyone remembering to grant.
-- =====================================================================
\set ON_ERROR_STOP on

-- ---------- bank_app: the application ----------
GRANT USAGE ON SCHEMA reference, customer, account, payment, transactions TO bank_app;
GRANT SELECT ON ALL TABLES IN SCHEMA reference, customer, account TO bank_app;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA payment, transactions TO bank_app;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA payment, transactions TO bank_app;

-- ---------- collibra_ingest: METADATA ONLY ----------
-- Schema USAGE lets the role see object names and column definitions via
-- pg_catalog (what the PostgreSQL JDBC driver's DatabaseMetaData reads).
-- No table privileges, so it can NOT read a single customer row.
GRANT USAGE ON SCHEMA reference, customer, account, payment, transactions, reporting TO collibra_ingest;

-- ---------- collibra_profile: read rows for profiling / classification ----------
GRANT USAGE  ON SCHEMA reference, customer, account, payment, transactions, reporting TO collibra_profile;
GRANT SELECT ON ALL TABLES IN SCHEMA reference, customer, account, payment, transactions, reporting TO collibra_profile;

-- ---------- future objects created by bank_owner ----------
ALTER DEFAULT PRIVILEGES FOR ROLE bank_owner IN SCHEMA reference, customer, account, payment, transactions, reporting
  GRANT SELECT ON TABLES TO collibra_profile;
ALTER DEFAULT PRIVILEGES FOR ROLE bank_owner IN SCHEMA reference, customer, account
  GRANT SELECT ON TABLES TO bank_app;
ALTER DEFAULT PRIVILEGES FOR ROLE bank_owner IN SCHEMA payment, transactions
  GRANT SELECT, INSERT, UPDATE ON TABLES TO bank_app;
