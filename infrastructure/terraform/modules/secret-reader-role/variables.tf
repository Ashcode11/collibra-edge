variable "name" {
  description = "Role name."
  type        = string
}

variable "secret_arns" {
  description = "Secrets the role may read."
  type        = list(string)
}

variable "kms_key_arns" {
  description = "CMKs protecting those secrets."
  type        = list(string)
}

variable "region" {
  description = "AWS region (for the kms:ViaService condition)."
  type        = string
}

variable "oidc_provider_arn" {
  description = "EKS cluster OIDC provider ARN. In this lab it is an illustrative placeholder: there is no EKS cluster."
  type        = string
}

variable "oidc_provider_host" {
  description = "OIDC issuer host/path without https://, e.g. oidc.eks.eu-west-2.amazonaws.com/id/EXAMPLE."
  type        = string
}

variable "service_account" {
  description = "Kubernetes service account allowed to assume the role, as namespace:name."
  type        = string
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}
