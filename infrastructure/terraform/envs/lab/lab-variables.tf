# Variables specific to the lab stack (shared ones are in variables.tf).

variable "password_versions" {
  description = "Per-credential password version. Increment one to rotate it, e.g. { \"bank-core-pg/bank_app\" = 2 }."
  type        = map(number)
  default     = {}
}

variable "edge_oidc_issuer" {
  description = "EKS OIDC issuer (host/path) the Edge service account would authenticate through. ILLUSTRATIVE: the lab has no EKS cluster."
  type        = string
  default     = "oidc.eks.eu-west-2.amazonaws.com/id/EXAMPLE0000000000000000000000000"
}

variable "edge_service_account" {
  description = "namespace:serviceaccount allowed to assume the Edge secrets role."
  type        = string
  default     = "collibra-edge:edge-vault-reader"
}
