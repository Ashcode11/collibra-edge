output "buckets" {
  description = "Bucket names by purpose."
  value       = { for k, m in module.bucket : k => m.id }
}

output "queues" {
  description = "Queue and DLQ URLs."
  value       = { for k, m in module.queue : k => { url = m.url, dlq_url = m.dlq_url } }
}

output "kms_aliases" {
  description = "Customer-managed key aliases."
  value       = { secrets = module.kms_secrets.alias_name, storage = module.kms_storage.alias_name }
}

output "db_secret_names" {
  description = "Secrets Manager names by credential."
  value       = { for k, m in module.db_credential : k => m.name }
}

output "collibra_edge_vault_references" {
  description = "What you would enter in a Collibra Edge JDBC connection using an AWS Secrets Manager vault (Value Type = Vault Key)."
  value = {
    for k, m in module.db_credential : k => m.edge_vault_reference
    if local.db_credentials[k].consumer == "collibra-edge"
  }
}

output "collibra_edge_role_arn" {
  description = "IRSA role ARN for the Edge service account (illustrative)."
  value       = module.edge_secret_reader.role_arn
}
