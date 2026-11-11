terraform {
  required_version = ">= 1.11" # write-only attributes
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.7, < 4.0" # ephemeral random_password
    }
  }
}
