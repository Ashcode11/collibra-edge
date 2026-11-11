locals {
  # ------------------------------------------------------------------ naming
  # Convention: <org>-<env>-<region>-<component>, e.g. cel-lab-euw2-landing
  #   org     cel   (Collibra Edge Lab)
  #   env     lab | dev | uat
  #   region  euw2  (eu-west-2, London)
  # Secrets use path style:  cel/<env>/<system>/<login>
  prefix        = "cel-${var.environment}"
  name          = "${local.prefix}-${var.region_short}"
  secret_prefix = "cel/${var.environment}"

  common_tags = {
    Project     = "collibra-edge-lab"
    Environment = var.environment
    Owner       = var.owner
    CostCentre  = var.cost_centre
    ManagedBy   = "terraform"
    Stack       = "lab"
    Repository  = "collibra-edge-enterprise-lab"
  }

  # ------------------------------------------------------------------ databases
  # In-cluster DNS names of the Phase 4 databases.
  databases = {
    bank-core-pg = { engine = "postgres", host = "bank-core-pg.data.svc.cluster.local", port = 5432, dbname = "bank_core" }
    crm-mysql    = { engine = "mysql", host = "crm-mysql.data.svc.cluster.local", port = 3306, dbname = "crm" }
  }

  # Credentials Terraform owns. Superusers (postgres, root) are deliberately
  # NOT here: they are break-glass accounts held outside the pipeline.
  #   consumer   who uses it (drives the Collibra Edge IAM policy)
  #   k8s_secret the Kubernetes Secret it is synced into (namespace data)
  #   extra      additional "namespace/secret" targets, space-separated
  #              (AWS tag values may not contain commas)
  db_credentials = {
    "bank-core-pg/bank_migrator"    = { db = "bank-core-pg", username = "bank_migrator", consumer = "platform", k8s_secret = "pg-migrator", purpose = "Schema migrations (SET ROLE bank_owner)" }
    "bank-core-pg/bank_app"         = { db = "bank-core-pg", username = "bank_app", consumer = "application", k8s_secret = "pg-app", purpose = "Core banking application", extra = "bank-apps/payments-api-db" }
    "bank-core-pg/collibra_ingest"  = { db = "bank-core-pg", username = "collibra_ingest", consumer = "collibra-edge", k8s_secret = "pg-collibra-ingest", purpose = "Collibra Edge Catalog JDBC ingestion (metadata only)" }
    "bank-core-pg/collibra_profile" = { db = "bank-core-pg", username = "collibra_profile", consumer = "collibra-edge", k8s_secret = "pg-collibra-profile", purpose = "Collibra Edge profiling and classification (read-only)" }
    "crm-mysql/crm_app"             = { db = "crm-mysql", username = "crm_app", consumer = "application", k8s_secret = "mysql-crm-app", purpose = "CRM application" }
    "crm-mysql/collibra_ingest"     = { db = "crm-mysql", username = "collibra_ingest", consumer = "collibra-edge", k8s_secret = "mysql-collibra-ingest", purpose = "Collibra Edge Catalog JDBC ingestion (metadata only)" }
  }
}
