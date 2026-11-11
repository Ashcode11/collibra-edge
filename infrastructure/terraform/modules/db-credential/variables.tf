variable "name" {
  description = "Secret name (path-style), e.g. cel/lab/bank-core-pg/collibra_ingest."
  type        = string
}

variable "description" {
  description = "What the credential is for."
  type        = string
}

variable "engine" {
  description = "Database engine."
  type        = string
  validation {
    condition     = contains(["postgres", "mysql"], var.engine)
    error_message = "engine must be postgres or mysql."
  }
}

variable "host" {
  description = "Database host (cluster DNS name)."
  type        = string
}

variable "port" {
  description = "Database port."
  type        = number
}

variable "dbname" {
  description = "Database / schema name."
  type        = string
}

variable "username" {
  description = "Login name."
  type        = string
}

variable "kms_key_id" {
  description = "CMK that encrypts the secret."
  type        = string
}

variable "password_version" {
  description = "Increment to generate and store a new password (rotation)."
  type        = number
  default     = 1
}

variable "password_length" {
  description = "Generated password length."
  type        = number
  default     = 32
}

variable "recovery_window_in_days" {
  description = "Days a deleted secret can be restored (0 = delete immediately; lab only)."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Extra tags (e.g. consumer, k8s-secret)."
  type        = map(string)
  default     = {}
}
