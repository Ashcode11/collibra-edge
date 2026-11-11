-- =====================================================================
-- bank_core bootstrap: roles and database-level privileges.
-- Run as the superuser. Idempotent. Passwords are read from environment
-- variables (injected from Kubernetes Secrets) with \getenv, so they never
-- appear on a command line. Re-running after a Secret changes ROTATES it.
-- =====================================================================
\set ON_ERROR_STOP on
\getenv migrator_pw PG_MIGRATOR_PASSWORD
\getenv app_pw      PG_APP_PASSWORD
\getenv ingest_pw   PG_INGEST_PASSWORD
\getenv profile_pw  PG_PROFILE_PASSWORD

-- ALTER ROLE ... PASSWORD would otherwise be written in clear text to the
-- server log, because the server runs with log_statement = 'ddl'.
SET log_statement = 'none';

DO $$
DECLARE r text;
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'bank_owner') THEN
    CREATE ROLE bank_owner NOLOGIN;
  END IF;
  FOREACH r IN ARRAY ARRAY['bank_migrator','bank_app','collibra_ingest','collibra_profile'] LOOP
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = r) THEN
      EXECUTE format('CREATE ROLE %I LOGIN', r);
    END IF;
  END LOOP;
END $$;

ALTER ROLE bank_migrator    LOGIN PASSWORD :'migrator_pw';
ALTER ROLE bank_app         LOGIN PASSWORD :'app_pw'      CONNECTION LIMIT 20;
ALTER ROLE collibra_ingest  LOGIN PASSWORD :'ingest_pw'   CONNECTION LIMIT 5;
ALTER ROLE collibra_profile LOGIN PASSWORD :'profile_pw'  CONNECTION LIMIT 5;

RESET log_statement;

-- The migrator acts as the owner role only when it explicitly SETs it.
GRANT bank_owner TO bank_migrator;

-- Guard rails for the governance service accounts:
--  * every transaction is read-only, even if a grant is later widened by mistake
--  * long scans are cut off, and abandoned sessions are closed
ALTER ROLE collibra_ingest  SET default_transaction_read_only = on;
ALTER ROLE collibra_profile SET default_transaction_read_only = on;
ALTER ROLE collibra_ingest  SET statement_timeout = '5min';
ALTER ROLE collibra_profile SET statement_timeout = '15min';
ALTER ROLE collibra_ingest  SET idle_in_transaction_session_timeout = '2min';
ALTER ROLE collibra_profile SET idle_in_transaction_session_timeout = '2min';

-- Database-level access: nobody connects unless explicitly granted.
REVOKE ALL ON DATABASE bank_core FROM PUBLIC;
GRANT CONNECT ON DATABASE bank_core TO bank_migrator, bank_app, collibra_ingest, collibra_profile;
GRANT CREATE  ON DATABASE bank_core TO bank_owner;           -- may create schemas
-- REVOKE ALL above also removed PUBLIC's default TEMPORARY privilege.
-- Only the owner (used by migrations/data generation) gets it back.
GRANT TEMPORARY ON DATABASE bank_core TO bank_owner;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
