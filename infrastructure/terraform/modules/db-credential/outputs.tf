output "arn" {
  description = "Secret ARN."
  value       = aws_secretsmanager_secret.this.arn
}

output "name" {
  description = "Secret name."
  value       = aws_secretsmanager_secret.this.name
}

output "edge_vault_reference" {
  description = "How a Collibra Edge AWS Secrets Manager vault key would reference this secret."
  value = {
    secret_name    = aws_secretsmanager_secret.this.name
    username_field = "/username"
    password_field = "/password"
  }
}
