terraform {
  required_version = ">= 1.11" # ephemeral resources + write-only attributes

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.72"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }

  # Remote state in the bucket created by envs/bootstrap.
  # Settings live in backend.hcl (partial configuration).
  backend "s3" {}
}
