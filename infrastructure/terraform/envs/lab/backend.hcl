# Partial backend configuration (no secrets: credentials come from scripts/tf.sh).
# Used by: scripts/tf.sh lab init   (adds -backend-config=backend.hcl)
bucket       = "cel-lab-euw2-tfstate"
key          = "lab/terraform.tfstate"
region       = "eu-west-2"
encrypt      = true
use_lockfile = true # S3-native state locking (Terraform >= 1.10); no DynamoDB table needed

use_path_style              = true
skip_credentials_validation = true
skip_requesting_account_id  = true
skip_metadata_api_check     = true
skip_region_validation      = true
endpoints = {
  s3  = "http://localhost:4566"
  sts = "http://localhost:4566"
}
