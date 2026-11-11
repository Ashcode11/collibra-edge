# IAM role that lets ONE Kubernetes service account read ONLY the listed
# secrets: the "IAM Roles for Service Accounts" (IRSA) pattern used when
# Collibra Edge runs on EKS and reads credentials from Secrets Manager.
#
# Least privilege:
#   - GetSecretValue/DescribeSecret on explicit secret ARNs (no wildcards)
#   - kms:Decrypt only when called *via* Secrets Manager in this region
#   - trust limited to one namespace:serviceaccount on one OIDC provider

data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_host}:sub"
      values   = ["system:serviceaccount:${var.service_account}"]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "read_secrets" {
  statement {
    sid       = "ReadNamedSecretsOnly"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = var.secret_arns
  }
  statement {
    sid       = "DecryptOnlyViaSecretsManager"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = var.kms_key_arns
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${var.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = var.name
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600
  tags                 = var.tags
}

resource "aws_iam_policy" "this" {
  name        = "${var.name}-read-secrets"
  description = "Read-only access to explicitly listed secrets."
  policy      = data.aws_iam_policy_document.read_secrets.json
  tags        = var.tags
}

resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.this.arn
}
