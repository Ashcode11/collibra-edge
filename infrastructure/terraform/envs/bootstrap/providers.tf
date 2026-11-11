# --------------------------------------------------------------------------
# AWS provider pointed at Floci. Identical in every stack.
# Guard rails against ever touching real AWS:
#   1. every service endpoint is local (validated in variables.tf)
#   2. allowed_account_ids: Floci always reports 000000000000; a real
#      account would fail here before any resource call is made
#   3. scripts/tf.sh hides ~/.aws and injects dummy credentials
# --------------------------------------------------------------------------
provider "aws" {
  region              = var.region
  allowed_account_ids = [var.floci_account_id]

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  s3_use_path_style           = true

  endpoints {
    iam            = var.aws_endpoint
    kms            = var.aws_endpoint
    logs           = var.aws_endpoint
    s3             = var.aws_endpoint
    s3control      = var.aws_endpoint
    secretsmanager = var.aws_endpoint
    sqs            = var.aws_endpoint
    ssm            = var.aws_endpoint
    sts            = var.aws_endpoint
  }

  default_tags {
    tags = local.common_tags
  }
}
