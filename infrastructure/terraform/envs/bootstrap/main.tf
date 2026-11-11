# --------------------------------------------------------------------------
# BOOTSTRAP stack: creates the remote-state bucket every other stack uses.
#
# Chicken-and-egg: a stack can't store its state in a bucket it hasn't
# created yet, so this tiny stack keeps LOCAL state (gitignored). In a real
# organisation the bootstrap state is then migrated into the bucket it
# created (terraform init -migrate-state) or held by the platform team.
# --------------------------------------------------------------------------
terraform {
  required_version = ">= 1.11"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.72"
    }
  }
}

locals {
  prefix = "cel-${var.environment}"
  common_tags = {
    Project     = "collibra-edge-lab"
    Environment = var.environment
    Owner       = var.owner
    CostCentre  = var.cost_centre
    ManagedBy   = "terraform"
    Stack       = "bootstrap"
  }
}

module "state_key" {
  source      = "../../modules/kms-key"
  name        = "${local.prefix}-tfstate"
  description = "Encrypts Terraform state for ${var.environment}"
}

module "state_bucket" {
  source        = "../../modules/secure-bucket"
  name          = "${local.prefix}-${var.region_short}-tfstate"
  kms_key_arn   = module.state_key.key_arn
  force_destroy = false # state is precious: refuse to delete a non-empty bucket
  tags          = { DataClassification = "confidential" }
}

output "state_bucket" {
  description = "Put this in envs/<env>/backend.hcl."
  value       = module.state_bucket.id
}

output "state_kms_key_arn" {
  description = "CMK protecting state objects."
  value       = module.state_key.key_arn
}
