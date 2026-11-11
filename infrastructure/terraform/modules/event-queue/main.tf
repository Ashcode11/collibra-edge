# SQS queue with a dead-letter queue (DLQ). A message that fails processing
# max_receive_count times is moved to the DLQ instead of being retried
# forever or silently lost: operations can alert on DLQ depth and replay.

locals {
  use_kms = var.kms_key_id != null
}

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name}-dlq"
  message_retention_seconds = 1209600 # 14 days: the maximum, gives ops time to investigate
  kms_master_key_id         = var.kms_key_id
  sqs_managed_sse_enabled   = local.use_kms ? null : true
  tags                      = merge(var.tags, { Name = "${var.name}-dlq", QueueRole = "dead-letter" })
}

resource "aws_sqs_queue" "this" {
  name                       = var.name
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  kms_master_key_id          = var.kms_key_id
  sqs_managed_sse_enabled    = local.use_kms ? null : true
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })
  tags = merge(var.tags, { Name = var.name, QueueRole = "primary" })
}

# Only this queue may use the DLQ as its dead-letter target.
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.this.arn]
  })
}
