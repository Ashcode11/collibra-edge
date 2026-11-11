-- =====================================================================
-- bank_core schema (synthetic core-banking model). Run as bank_migrator.
-- Idempotent: safe to re-run. All objects are owned by bank_owner.
--
-- Comment tags used for governance demos:
--   [PII-DIRECT]   identifies a person on its own (name, NI number, email)
--   [PII-INDIRECT] identifies a person when combined (DOB, postcode)
--   [PCI]          payment-card data (masked or tokenised only here)
--   [FINANCIAL]    balances, amounts
-- =====================================================================
\set ON_ERROR_STOP on
SET ROLE bank_owner;

CREATE SCHEMA IF NOT EXISTS reference;
CREATE SCHEMA IF NOT EXISTS customer;
CREATE SCHEMA IF NOT EXISTS account;
CREATE SCHEMA IF NOT EXISTS payment;
CREATE SCHEMA IF NOT EXISTS transactions;
CREATE SCHEMA IF NOT EXISTS reporting;

COMMENT ON SCHEMA reference    IS 'Reference data: currencies, countries, branches, products. Owner: Data Management Office.';
COMMENT ON SCHEMA customer     IS 'Customer master and KYC. Contains PII. Owner: Retail Banking Operations.';
COMMENT ON SCHEMA account      IS 'Accounts and cards. Contains PII-linked and PCI data. Owner: Core Banking Platform.';
COMMENT ON SCHEMA payment      IS 'Payment orders across FPS, BACS, CHAPS, SEPA and SWIFT. Owner: Payments Operations.';
COMMENT ON SCHEMA transactions IS 'Booked ledger transactions. Owner: Core Banking Platform.';
COMMENT ON SCHEMA reporting    IS 'Derived reporting views consumed by Finance, Risk and Financial Crime.';

-- ---------------------------------------------------------------- reference
CREATE TABLE IF NOT EXISTS reference.currencies (
  currency_code  char(3)      PRIMARY KEY,
  currency_name  varchar(60)  NOT NULL,
  minor_units    smallint     NOT NULL DEFAULT 2
);
CREATE TABLE IF NOT EXISTS reference.countries (
  country_code     char(2)     PRIMARY KEY,
  country_name     varchar(80) NOT NULL,
  is_eea           boolean     NOT NULL DEFAULT false,
  is_high_risk     boolean     NOT NULL DEFAULT false
);
CREATE TABLE IF NOT EXISTS reference.branches (
  branch_code   varchar(6)  PRIMARY KEY,
  branch_name   varchar(80) NOT NULL,
  city          varchar(60) NOT NULL,
  country_code  char(2)     NOT NULL REFERENCES reference.countries,
  sort_code     char(6)     NOT NULL UNIQUE
);
CREATE TABLE IF NOT EXISTS reference.products (
  product_code   varchar(4)   PRIMARY KEY,
  product_name   varchar(80)  NOT NULL,
  product_type   varchar(10)  NOT NULL CHECK (product_type IN ('CURRENT','SAVINGS','LOAN','CARD')),
  customer_type  varchar(10)  NOT NULL CHECK (customer_type IN ('INDIVIDUAL','BUSINESS')),
  interest_rate  numeric(5,3) NOT NULL DEFAULT 0
);

-- ---------------------------------------------------------------- customer
CREATE TABLE IF NOT EXISTS customer.customers (
  customer_id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  customer_number            varchar(12)  NOT NULL UNIQUE,
  customer_type              varchar(10)  NOT NULL CHECK (customer_type IN ('INDIVIDUAL','BUSINESS')),
  title                      varchar(10),
  first_name                 varchar(60),
  last_name                  varchar(60),
  legal_name                 varchar(120),
  date_of_birth              date,
  national_insurance_number  char(9) UNIQUE,
  email                      varchar(120) NOT NULL,
  mobile_phone               varchar(20),
  nationality_code           char(2)      REFERENCES reference.countries,
  kyc_status                 varchar(10)  NOT NULL CHECK (kyc_status IN ('VERIFIED','PENDING','EXPIRED')),
  risk_rating                varchar(6)   NOT NULL CHECK (risk_rating IN ('LOW','MEDIUM','HIGH')),
  is_pep                     boolean      NOT NULL DEFAULT false,
  segment                    varchar(10)  NOT NULL,
  home_branch_code           varchar(6)   NOT NULL REFERENCES reference.branches,
  onboarded_at               timestamptz  NOT NULL,
  updated_at                 timestamptz  NOT NULL DEFAULT now(),
  CONSTRAINT person_or_company CHECK (
    (customer_type = 'INDIVIDUAL' AND last_name IS NOT NULL) OR
    (customer_type = 'BUSINESS'   AND legal_name IS NOT NULL))
);
CREATE TABLE IF NOT EXISTS customer.addresses (
  address_id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  customer_id   bigint      NOT NULL REFERENCES customer.customers ON DELETE CASCADE,
  address_type  varchar(15) NOT NULL CHECK (address_type IN ('RESIDENTIAL','CORRESPONDENCE','REGISTERED')),
  line_1        varchar(100) NOT NULL,
  line_2        varchar(100),
  city          varchar(60)  NOT NULL,
  postcode      varchar(10)  NOT NULL,
  country_code  char(2)      NOT NULL REFERENCES reference.countries,
  valid_from    date         NOT NULL,
  valid_to      date
);
CREATE TABLE IF NOT EXISTS customer.kyc_checks (
  kyc_check_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  customer_id      bigint      NOT NULL REFERENCES customer.customers ON DELETE CASCADE,
  check_type       varchar(20) NOT NULL CHECK (check_type IN ('PASSPORT','DRIVING_LICENCE','COMPANY_REGISTRY','SANCTIONS_SCREENING')),
  document_number  varchar(20),
  outcome          varchar(6)  NOT NULL CHECK (outcome IN ('PASS','REFER','FAIL')),
  checked_at       timestamptz NOT NULL,
  checked_by       varchar(40) NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_addresses_customer ON customer.addresses (customer_id);
CREATE INDEX IF NOT EXISTS ix_kyc_customer       ON customer.kyc_checks (customer_id);

-- ---------------------------------------------------------------- account
CREATE TABLE IF NOT EXISTS account.accounts (
  account_id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  account_number     char(8)       NOT NULL,
  sort_code          char(6)       NOT NULL,
  iban               varchar(34)   NOT NULL UNIQUE,
  customer_id        bigint        NOT NULL REFERENCES customer.customers,
  product_code       varchar(4)    NOT NULL REFERENCES reference.products,
  currency_code      char(3)       NOT NULL REFERENCES reference.currencies,
  status             varchar(8)    NOT NULL CHECK (status IN ('ACTIVE','DORMANT','CLOSED','FROZEN')),
  opened_on          date          NOT NULL,
  closed_on          date,
  current_balance    numeric(18,2) NOT NULL,
  available_balance  numeric(18,2) NOT NULL,
  overdraft_limit    numeric(18,2) NOT NULL DEFAULT 0,
  branch_code        varchar(6)    NOT NULL REFERENCES reference.branches,
  UNIQUE (sort_code, account_number)
);
CREATE TABLE IF NOT EXISTS account.cards (
  card_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  account_id    bigint       NOT NULL REFERENCES account.accounts,
  card_token    char(32)     NOT NULL UNIQUE,
  pan_masked    varchar(19)  NOT NULL,
  card_scheme   varchar(10)  NOT NULL CHECK (card_scheme IN ('VISA','MASTERCARD')),
  card_type     varchar(6)   NOT NULL CHECK (card_type IN ('DEBIT','CREDIT')),
  expiry_month  smallint     NOT NULL CHECK (expiry_month BETWEEN 1 AND 12),
  expiry_year   smallint     NOT NULL,
  status        varchar(8)   NOT NULL CHECK (status IN ('ACTIVE','BLOCKED','EXPIRED')),
  issued_on     date         NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_accounts_customer ON account.accounts (customer_id);
CREATE INDEX IF NOT EXISTS ix_cards_account     ON account.cards (account_id);

-- ---------------------------------------------------------------- payment
CREATE TABLE IF NOT EXISTS payment.payments (
  payment_id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  end_to_end_id       uuid          NOT NULL UNIQUE,
  debtor_account_id   bigint        NOT NULL REFERENCES account.accounts,
  creditor_name       varchar(120)  NOT NULL,
  creditor_iban       varchar(34)   NOT NULL,
  creditor_country    char(2)       NOT NULL REFERENCES reference.countries,
  amount              numeric(18,2) NOT NULL CHECK (amount > 0),
  currency_code       char(3)       NOT NULL REFERENCES reference.currencies,
  scheme              varchar(8)    NOT NULL CHECK (scheme IN ('FPS','BACS','CHAPS','SEPA_CT','SWIFT')),
  purpose_code        char(4)       NOT NULL,
  channel             varchar(8)    NOT NULL CHECK (channel IN ('MOBILE','ONLINE','BRANCH','API')),
  status              varchar(10)   NOT NULL CHECK (status IN ('INITIATED','SCREENING','SETTLED','REJECTED','RETURNED')),
  sanctions_hit       boolean       NOT NULL DEFAULT false,
  initiated_at        timestamptz   NOT NULL,
  settled_at          timestamptz
);
CREATE INDEX IF NOT EXISTS ix_payments_debtor    ON payment.payments (debtor_account_id);
CREATE INDEX IF NOT EXISTS ix_payments_initiated ON payment.payments (initiated_at);

-- ---------------------------------------------------------------- transactions
CREATE TABLE IF NOT EXISTS transactions.transactions (
  transaction_id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  account_id              bigint        NOT NULL REFERENCES account.accounts,
  payment_id              bigint        REFERENCES payment.payments,
  card_id                 bigint        REFERENCES account.cards,
  booking_date            date          NOT NULL,
  value_date              date          NOT NULL,
  direction               char(2)       NOT NULL CHECK (direction IN ('DR','CR')),
  amount                  numeric(18,2) NOT NULL CHECK (amount > 0),
  currency_code           char(3)       NOT NULL REFERENCES reference.currencies,
  channel                 varchar(12)   NOT NULL,
  merchant_name           varchar(80),
  merchant_category_code  char(4),
  description             varchar(140)
);
CREATE INDEX IF NOT EXISTS ix_txn_account_date ON transactions.transactions (account_id, booking_date);
CREATE INDEX IF NOT EXISTS ix_txn_payment      ON transactions.transactions (payment_id) WHERE payment_id IS NOT NULL;

-- ---------------------------------------------------------------- comments
COMMENT ON TABLE customer.customers  IS 'Customer master record, one row per legal party. Golden source for customer identity.';
COMMENT ON COLUMN customer.customers.customer_number           IS 'Business key shown to customers and staff.';
COMMENT ON COLUMN customer.customers.first_name                IS '[PII-DIRECT] Given name.';
COMMENT ON COLUMN customer.customers.last_name                 IS '[PII-DIRECT] Family name.';
COMMENT ON COLUMN customer.customers.legal_name                IS 'Registered company name (business customers only).';
COMMENT ON COLUMN customer.customers.date_of_birth             IS '[PII-INDIRECT] Date of birth.';
COMMENT ON COLUMN customer.customers.national_insurance_number IS '[PII-DIRECT] UK National Insurance number. Synthetic: always QQ prefix (never issued).';
COMMENT ON COLUMN customer.customers.email                     IS '[PII-DIRECT] Contact email. Synthetic: example.com / example.org only.';
COMMENT ON COLUMN customer.customers.mobile_phone              IS '[PII-DIRECT] Mobile number. Synthetic: Ofcom drama range 07700 900xxx.';
COMMENT ON COLUMN customer.customers.is_pep                    IS 'Politically Exposed Person flag (AML enhanced due diligence).';
COMMENT ON COLUMN customer.customers.risk_rating               IS 'Customer AML risk rating.';
COMMENT ON TABLE customer.addresses  IS 'Customer addresses with validity periods.';
COMMENT ON COLUMN customer.addresses.line_1   IS '[PII-DIRECT] First address line.';
COMMENT ON COLUMN customer.addresses.postcode IS '[PII-INDIRECT] Postal code.';
COMMENT ON TABLE customer.kyc_checks IS 'Know-Your-Customer verification and sanctions screening results.';
COMMENT ON COLUMN customer.kyc_checks.document_number IS '[PII-DIRECT] Identity document number. Synthetic: SYN prefix.';
COMMENT ON TABLE account.accounts IS 'Customer accounts across current, savings, loan and card products.';
COMMENT ON COLUMN account.accounts.iban            IS '[PII-INDIRECT] International Bank Account Number. Synthetic bank code SYNT.';
COMMENT ON COLUMN account.accounts.account_number  IS '[PII-INDIRECT] Domestic account number.';
COMMENT ON COLUMN account.accounts.current_balance IS '[FINANCIAL] Ledger balance in account currency.';
COMMENT ON TABLE account.cards IS 'Payment cards. Full PANs are never stored: token + masked PAN only (PCI DSS scope reduction).';
COMMENT ON COLUMN account.cards.pan_masked IS '[PCI] Masked primary account number (first 6 / last 4).';
COMMENT ON COLUMN account.cards.card_token IS '[PCI] Vault token that replaces the PAN.';
COMMENT ON TABLE payment.payments IS 'Outbound payment orders. One row per instruction.';
COMMENT ON COLUMN payment.payments.end_to_end_id IS 'Unique end-to-end transaction reference (UETR).';
COMMENT ON COLUMN payment.payments.creditor_name IS '[PII-DIRECT] Beneficiary name.';
COMMENT ON COLUMN payment.payments.creditor_iban IS '[PII-INDIRECT] Beneficiary IBAN.';
COMMENT ON COLUMN payment.payments.amount        IS '[FINANCIAL] Instructed amount.';
COMMENT ON COLUMN payment.payments.sanctions_hit IS 'True if sanctions screening raised a potential match.';
COMMENT ON TABLE transactions.transactions IS 'Booked ledger entries (debits and credits) per account.';
COMMENT ON COLUMN transactions.transactions.amount IS '[FINANCIAL] Absolute amount; see direction.';
