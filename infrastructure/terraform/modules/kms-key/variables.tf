variable "name" {
  description = "Key purpose name; becomes alias/<name>."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,62}$", var.name))
    error_message = "name must be lower-case letters, digits and hyphens (3-63 chars)."
  }
}

variable "description" {
  description = "Human-readable purpose of the key."
  type        = string
}

variable "deletion_window_in_days" {
  description = "Waiting period before a scheduled deletion takes effect (AWS allows 7-30)."
  type        = number
  default     = 30
  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30."
  }
}

variable "tags" {
  description = "Extra tags for this key."
  type        = map(string)
  default     = {}
}
