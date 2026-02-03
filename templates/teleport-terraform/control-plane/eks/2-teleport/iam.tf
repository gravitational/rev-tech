##################################################################################
# IAM CONFIGURATION FOR IRSA
##################################################################################

# Data source for current AWS account

data "aws_caller_identity" "current" {}

# IAM policy for Teleport auth service - update for multipart uploads
resource "aws_iam_policy" "teleport_auth" {
  name        = "${var.proxy_address}-auth-policy"
  description = "IAM policy for Teleport auth service"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:ConditionCheckItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeStream",
          "dynamodb:DescribeTable",
          "dynamodb:DescribeTimeToLive",
          "dynamodb:GetItem",
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:UpdateItem",
          "dynamodb:UpdateTimeToLive"
        ]
        Resource = [
          aws_dynamodb_table.teleport_backend.arn,
          "${aws_dynamodb_table.teleport_backend.arn}/stream/*",
          "${aws_dynamodb_table.teleport_backend.arn}/index/*",
          aws_dynamodb_table.teleport_events.arn,
          "${aws_dynamodb_table.teleport_events.arn}/stream/*",
          "${aws_dynamodb_table.teleport_events.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:ListBucketVersions",
          "s3:GetBucketVersioning",
          "s3:ListBucketMultipartUploads"
        ]
        Resource = [
          aws_s3_bucket.session_recordings.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts"
        ]
        Resource = [
          "${aws_s3_bucket.session_recordings.arn}/*"
        ]
      }
    ]
  })
}

# Get EKS cluster OIDC provider
data "aws_iam_openid_connect_provider" "eks" {
  arn = data.terraform_remote_state.eks.outputs.oidc_provider_arn
}

# IAM role for Teleport auth service

resource "aws_iam_role" "teleport_auth" {
  name = "${var.proxy_address}-auth-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.eks.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(data.aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "${replace(data.aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = [
              "system:serviceaccount:${kubernetes_namespace.teleport_cluster.metadata[0].name}:teleport-cluster",
              "system:serviceaccount:${kubernetes_namespace.teleport_cluster.metadata[0].name}:teleport-cluster-proxy"
            ]
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "teleport_auth" {
  role       = aws_iam_role.teleport_auth.name
  policy_arn = aws_iam_policy.teleport_auth.arn
}

## ===================== CERT-MANAGER IAM RESOURCES =====================

# Needed for cert-manager IAM policy
data "aws_route53_zone" "teleport" {
  count = var.domain_name != "" ? 1 : 0
  name  = var.domain_name
}
resource "aws_iam_policy" "cert_manager_route53" {
  count       = var.domain_name != "" ? 1 : 0
  name        = "${var.proxy_address}-cert-manager-route53"
  description = "Policy for cert-manager to manage Route53 records"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListHostedZonesByName",
          "route53:ListResourceRecordSets",
          "route53:GetChange"
        ]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = ["route53:ChangeResourceRecordSets"]
        Resource = [
          "arn:aws:route53:::hostedzone/${data.aws_route53_zone.teleport[0].zone_id}"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "cert_manager" {
  count = var.domain_name != "" ? 1 : 0
  name  = "${var.proxy_address}-cert-manager"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.eks.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(data.aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
            "${replace(data.aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:cert-manager:cert-manager"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cert_manager_route53" {
  count      = var.domain_name != "" ? 1 : 0
  role       = aws_iam_role.cert_manager[0].name
  policy_arn = aws_iam_policy.cert_manager_route53[0].arn
}
