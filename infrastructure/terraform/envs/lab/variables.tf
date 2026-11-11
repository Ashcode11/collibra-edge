variable "environment" {
  description = "Environment name used in resource names and tags."
  type        = string
  validation {
    condition     = contains(["lab", "dev", "uat"], var.environment)
    error_message = "This lab only defines lab, dev and uat environments (never prod)."
  }
}

variable "region" {
  description = "AWS region emulated by Floci."
  type        = string
  default     = "eu-west-2"
}

variable "region_short" {
  description = "Short region code used in names (eu-west-2 => euw2)."
  type        = string
  default     = "euw2"
}

variable "aws_endpoint" {
  description = "Floci AWS endpoint. Must be local: this lab never targets real AWS."
  type        = string
  default     = "http://localhost:4566" # hostname (not IP) so S3 Control can prefix the account ID
  validation {
    condition     = can(regex("^http://(127\\.0\\.0\\.1|localhost|host\\.k3d\\.internal):[0-9]+$", var.aws_endpoint))
    error_message = "aws_endpoint must be a local Floci URL (127.0.0.1, localhost or host.k3d.internal)."
  }
}

variable "floci_account_id" {
  description = "Account ID Floci reports. Used as an allow-list guard."
  type        = string
  default     = "000000000000"
}

variable "owner" {
  description = "Owning team (tag)."
  type        = string
  default     = "data-platform-engineering"
}

variable "cost_centre" {
  description = "Cost centre (tag). Illustrative."
  type        = string
  default     = "CC-DATA-0420"
}
