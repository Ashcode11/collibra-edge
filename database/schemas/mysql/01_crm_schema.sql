-- =====================================================================
-- crm: a separate CRM system owned by Marketing & Customer Service.
-- It deliberately DUPLICATES customer PII from bank_core and links to it
-- only by a business key (customer_number), with no enforced foreign key
-- across systems. This is the classic "PII sprawl" a data catalog should
-- make visible. Idempotent.
-- =====================================================================
CREATE DATABASE IF NOT EXISTS crm CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE crm;

CREATE TABLE IF NOT EXISTS contacts (
  contact_id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  customer_number     VARCHAR(12)  NULL COMMENT 'Business key into bank_core.customer.customers (NULL for prospects).',
  full_name           VARCHAR(120) NOT NULL COMMENT '[PII-DIRECT] Contact name as captured by CRM.',
  email               VARCHAR(120) NOT NULL COMMENT '[PII-DIRECT] Contact email. Synthetic: example.com/example.net.',
  phone               VARCHAR(20)  NULL     COMMENT '[PII-DIRECT] Contact phone. Synthetic: Ofcom drama range.',
  date_of_birth       DATE         NULL     COMMENT '[PII-INDIRECT] Copied from onboarding; may drift from core.',
  lifecycle_stage     ENUM('PROSPECT','CUSTOMER','LAPSED') NOT NULL,
  marketing_consent   BOOLEAN      NOT NULL DEFAULT FALSE COMMENT 'UK GDPR / PECR consent for marketing.',
  consent_updated_at  DATETIME     NULL,
  created_at          DATETIME     NOT NULL,
  updated_at          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY ix_contacts_customer_number (customer_number),
  UNIQUE KEY ux_contacts_email (email)
) ENGINE=InnoDB COMMENT='CRM contact master. Overlaps with bank_core customers.';

CREATE TABLE IF NOT EXISTS interactions (
  interaction_id  BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  contact_id      BIGINT UNSIGNED NOT NULL,
  channel         ENUM('PHONE','EMAIL','CHAT','BRANCH','SOCIAL') NOT NULL,
  topic           VARCHAR(40)  NOT NULL,
  agent_id        VARCHAR(20)  NOT NULL,
  notes           VARCHAR(500) NULL COMMENT '[PII-RISK] Free text typed by agents; may contain unstructured PII.',
  occurred_at     DATETIME     NOT NULL,
  CONSTRAINT fk_interactions_contact FOREIGN KEY (contact_id) REFERENCES contacts (contact_id),
  KEY ix_interactions_contact (contact_id, occurred_at)
) ENGINE=InnoDB COMMENT='Customer service interactions across channels.';

CREATE TABLE IF NOT EXISTS complaints (
  complaint_id     BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  complaint_ref    VARCHAR(16)   NOT NULL UNIQUE,
  contact_id       BIGINT UNSIGNED NOT NULL,
  product_area     ENUM('CURRENT_ACCOUNT','SAVINGS','CARDS','PAYMENTS','LOANS','DIGITAL') NOT NULL,
  category         VARCHAR(40)   NOT NULL,
  received_at      DATETIME      NOT NULL,
  resolved_at      DATETIME      NULL,
  outcome          ENUM('UPHELD','NOT_UPHELD','PARTIALLY_UPHELD','OPEN') NOT NULL,
  redress_amount   DECIMAL(12,2) NOT NULL DEFAULT 0 COMMENT '[FINANCIAL] Compensation paid.',
  referred_to_fos  BOOLEAN       NOT NULL DEFAULT FALSE COMMENT 'Escalated to the Financial Ombudsman Service.',
  CONSTRAINT fk_complaints_contact FOREIGN KEY (contact_id) REFERENCES contacts (contact_id),
  KEY ix_complaints_received (received_at)
) ENGINE=InnoDB COMMENT='Regulatory complaints register (FCA DISP reporting source).';

CREATE TABLE IF NOT EXISTS marketing_campaigns (
  campaign_id    INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  campaign_code  VARCHAR(20)  NOT NULL UNIQUE,
  name           VARCHAR(80)  NOT NULL,
  channel        ENUM('EMAIL','SMS','APP','POST') NOT NULL,
  starts_on      DATE NOT NULL,
  ends_on        DATE NOT NULL
) ENGINE=InnoDB COMMENT='Marketing campaign definitions.';

CREATE TABLE IF NOT EXISTS campaign_responses (
  response_id    BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  campaign_id    INT UNSIGNED    NOT NULL,
  contact_id     BIGINT UNSIGNED NOT NULL,
  response       ENUM('SENT','OPENED','CLICKED','CONVERTED','UNSUBSCRIBED') NOT NULL,
  responded_at   DATETIME NOT NULL,
  CONSTRAINT fk_resp_campaign FOREIGN KEY (campaign_id) REFERENCES marketing_campaigns (campaign_id),
  CONSTRAINT fk_resp_contact  FOREIGN KEY (contact_id)  REFERENCES contacts (contact_id),
  KEY ix_resp_campaign (campaign_id)
) ENGINE=InnoDB COMMENT='Campaign delivery and response events.';

CREATE OR REPLACE VIEW v_complaints_monthly AS
SELECT DATE_FORMAT(received_at, '%Y-%m-01') AS month, product_area, outcome,
       COUNT(*) AS complaint_count, SUM(redress_amount) AS total_redress,
       SUM(referred_to_fos) AS fos_referrals
FROM complaints GROUP BY 1, 2, 3;
