output "url" {
  description = "Main queue URL."
  value       = aws_sqs_queue.this.id
}

output "arn" {
  description = "Main queue ARN."
  value       = aws_sqs_queue.this.arn
}

output "dlq_url" {
  description = "Dead-letter queue URL."
  value       = aws_sqs_queue.dlq.id
}

output "dlq_arn" {
  description = "Dead-letter queue ARN."
  value       = aws_sqs_queue.dlq.arn
}
