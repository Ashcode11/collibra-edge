# --------------------------------------------------------------------------
# LAB stack: cloud-side resources around the Collibra Edge lab, on Floci.
#
#   KMS        cel-lab-secrets, cel-lab-storage      (customer-managed keys)
#   S3         landing, lineage-sql, metadata-exports (secure-bucket module)
#   SQS        ingestion-events, dq-alerts (+ DLQs)   (event-queue module)
#   Secrets    6 DB credentials in Edge vault format  (db-credential module)
#   SSM        non-secret DB connection parameters
#   IAM        IRSA-style read role for Collibra Edge (secret-reader-role)
#   Logs       audit log group with retention
# --------------------------------------------------------------------------

# ------------------------------------------------------------------ KMS
module "kms_secrets" {
  source      = "../../modules/kms-key"
  name        = "${local.prefix}-secrets"
  description = "Encrypts database credentials in Secrets Manager (${var.environment})"
}

module "kms_storage" {
  source      = "../../modules/kms-key"
  name        = "${local.prefix}-storage"
  description = "Encrypts S3 objects and SQS messages (${var.environment})"
}

# ------------------------------------------------------------------ S3
locals {
  buckets = {
    landing          = { classification = "confidential", purpose = "Inbound partner files (e.g. payment scheme reports) before loading" }
    lineage-sql      = { classification = "internal", purpose = "SQL/DDL files for Collibra Technical Lineage (SqlDirectory-style shared storage)" }
    metadata-exports = { classification = "internal", purpose = "Exports from the data catalog for downstream reporting" }
  }
}

module "bucket" {
  source        = "../../modules/secure-bucket"
  for_each      = local.buckets
  name          = "${local.name}-${each.key}"
  kms_key_arn   = module.kms_storage.key_arn
  force_destroy = true # lab only: allows terraform destroy with objects inside
  tags = {
    DataClassification = each.value.classification
    Purpose            = each.value.purpose
  }
}

# Publish the reporting-view DDL so a lineage tool has SQL to parse.
resource "aws_s3_object" "lineage_sql" {
  for_each = {
    "bank_core/02_views.sql"  = "${path.root}/../../../../database/schemas/postgres/02_views.sql"
    "bank_core/01_schema.sql" = "${path.root}/../../../../database/schemas/postgres/01_schema.sql"
  }
  bucket       = module.bucket["lineage-sql"].id
  key          = each.key
  source       = each.value
  source_hash  = filemd5(each.value) # re-upload when the file changes (etag != md5 under SSE-KMS)
  content_type = "application/sql"
}

# ------------------------------------------------------------------ SQS
module "queue" {
  source     = "../../modules/event-queue"
  for_each   = toset(["ingestion-events", "dq-alerts"])
  name       = "${local.name}-${each.key}"
  kms_key_id = module.kms_storage.key_arn
}

# ------------------------------------------------------------------ Secrets
module "db_credential" {
  source   = "../../modules/db-credential"
  for_each = local.db_credentials

  name        = "${local.secret_prefix}/${each.key}"
  description = each.value.purpose
  engine      = local.databases[each.value.db].engine
  host        = local.databases[each.value.db].host
  port        = local.databases[each.value.db].port
  dbname      = local.databases[each.value.db].dbname
  username    = each.value.username
  kms_key_id  = module.kms_secrets.key_arn

  password_version        = lookup(var.password_versions, each.key, 1)
  recovery_window_in_days = 0 # lab: allow immediate re-creation. Production: 7-30.

  tags = merge({
    Consumer           = each.value.consumer
    Database           = each.value.db
    "k8s-secret"       = each.value.k8s_secret
    "k8s-namespace"    = "data"
    DataClassification = "restricted"
    }, lookup(each.value, "extra", null) == null ? {} : {
    "k8s-extra-targets" = each.value.extra
  })
}

# ------------------------------------------------------------------ SSM (non-secret config)
resource "aws_ssm_parameter" "db" {
  for_each = merge([
    for db, cfg in local.databases : {
      "${db}/host"   = cfg.host
      "${db}/port"   = tostring(cfg.port)
      "${db}/dbname" = cfg.dbname
      "${db}/engine" = cfg.engine
    }
  ]...)
  name  = "/${local.secret_prefix}/${each.key}"
  type  = "String"
  value = each.value
}

# ------------------------------------------------------------------ IAM for Collibra Edge
module "edge_secret_reader" {
  source = "../../modules/secret-reader-role"
  name   = "${local.prefix}-collibra-edge-secrets"
  region = var.region
  secret_arns = [
    for k, m in module.db_credential : m.arn if local.db_credentials[k].consumer == "collibra-edge"
  ]
  kms_key_arns       = [module.kms_secrets.key_arn]
  oidc_provider_arn  = "arn:aws:iam::${var.floci_account_id}:oidc-provider/${var.edge_oidc_issuer}"
  oidc_provider_host = var.edge_oidc_issuer
  service_account    = var.edge_service_account
}

# ------------------------------------------------------------------ Logs
resource "aws_cloudwatch_log_group" "edge_audit" {
  name              = "/${local.secret_prefix}/collibra-edge/audit"
  retention_in_days = 400 # > 1 year, typical minimum for regulated audit trails
}
