variable "name" {
  description = "Queue name. The DLQ is named <name>-dlq."
  type        = string
}

variable "kms_key_id" {
  description = "CMK for SSE-KMS. If null, SQS-managed encryption (SSE-SQS) is used."
  type        = string
  default     = null
}

variable "max_receive_count" {
  description = "Deliveries before a message moves to the DLQ."
  type        = number
  default     = 5
}

variable "visibility_timeout_seconds" {
  description = "How long a received message is hidden from other consumers."
  type        = number
  default     = 60
}

variable "message_retention_seconds" {
  description = "Retention on the main queue (default 4 days)."
  type        = number
  default     = 345600
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}
