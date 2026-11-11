# Customer-managed KMS key with automatic rotation and a friendly alias.
# Why a CMK instead of AWS-managed keys: the bank controls the key policy,
# can audit every use in CloudTrail and can revoke access (crypto-shredding).

resource "aws_kms_key" "this" {
  description             = var.description
  enable_key_rotation     = true
  deletion_window_in_days = var.deletion_window_in_days
  tags                    = merge(var.tags, { Name = var.name })
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name}"
  target_key_id = aws_kms_key.this.key_id
}
