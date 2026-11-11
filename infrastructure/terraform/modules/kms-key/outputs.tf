output "key_id" {
  description = "KMS key ID."
  value       = aws_kms_key.this.key_id
}

output "key_arn" {
  description = "KMS key ARN (use in IAM policies)."
  value       = aws_kms_key.this.arn
}

output "alias_name" {
  description = "Alias, e.g. alias/cel-lab-secrets."
  value       = aws_kms_alias.this.name
}
