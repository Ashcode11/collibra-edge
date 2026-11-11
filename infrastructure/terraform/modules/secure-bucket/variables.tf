variable "name" {
  description = "Globally unique bucket name."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.name))
    error_message = "Bucket names must be 3-63 chars of lower-case letters, digits, dots and hyphens."
  }
}

variable "kms_key_arn" {
  description = "CMK used for default SSE-KMS encryption."
  type        = string
}

variable "noncurrent_version_expiration_days" {
  description = "Delete non-current object versions after this many days."
  type        = number
  default     = 90
}

variable "force_destroy" {
  description = "Allow destroying a non-empty bucket. Keep false outside labs."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Extra tags for this bucket."
  type        = map(string)
  default     = {}
}
