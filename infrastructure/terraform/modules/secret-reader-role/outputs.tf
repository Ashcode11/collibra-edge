output "role_arn" {
  description = "Role ARN (annotate the service account with eks.amazonaws.com/role-arn)."
  value       = aws_iam_role.this.arn
}

output "policy_json" {
  description = "Rendered permissions policy, for review."
  value       = data.aws_iam_policy_document.read_secrets.json
}
