################################################################################
# Secrets Manager — service secret shells (no values, never in state)
################################################################################

locals {
  service_secrets = {
    "arclight/${var.environment}/core/database-url"                   = "Core PostgreSQL connection string"
    "arclight/${var.environment}/core/signing-key-encryption-key"     = "Core Fernet signing key"
    "arclight/${var.environment}/core/admin-bootstrap-secret"         = "Core admin bootstrap token"
    "arclight/${var.environment}/core/oidc-client-secret"             = "Core OIDC client secret"
    "arclight/${var.environment}/shuttleforge/db-url"                 = "ShuttleForge PostgreSQL connection string"
    "arclight/${var.environment}/shuttleforge/kek-ring-b64"           = "ShuttleForge AES-256-GCM key ring"
    "arclight/${var.environment}/shuttleforge/listener-auth-hmac-key" = "ShuttleForge listener HMAC key"
    "arclight/${var.environment}/shuttleforge/lease-hmac-key"         = "ShuttleForge lease HMAC key"
    "arclight/${var.environment}/shuttleforge/operator-token"         = "ShuttleForge operator token"
    "arclight/${var.environment}/podbay/database-url"                 = "Podbay PostgreSQL connection string"
    "arclight/${var.environment}/nerfherder/database-url"             = "Nerfherder PostgreSQL connection string"
  }

  services = ["core", "shuttleforge", "podbay"]

  ecr_repo_map = {
    core         = "arclight/core"
    shuttleforge = "arclight/shuttleforge"
    podbay       = "arclight/podbay"
  }
}

resource "aws_secretsmanager_secret" "service" {
  for_each = local.service_secrets

  name        = each.key
  description = each.value

  tags = { Name = each.key }
}

################################################################################
# SSM Parameters — non-secret service discovery
################################################################################

locals {
  ssm_parameters = {
    "/arclight/${var.environment}/core/base-url"             = "https://core.${var.environment}.${var.domain_name}"
    "/arclight/${var.environment}/core/internal-url"         = "http://core.${var.private_dns_namespace}:8000"
    "/arclight/${var.environment}/core/jwks-url"             = "http://core.${var.private_dns_namespace}:8000/.well-known/jwks.json"
    "/arclight/${var.environment}/core/token-url"            = "http://core.${var.private_dns_namespace}:8000/oauth/token"
    "/arclight/${var.environment}/podbay/public-url"         = "https://podbay.${var.environment}.${var.domain_name}"
    "/arclight/${var.environment}/podbay/internal-url"       = "http://podbay.${var.private_dns_namespace}:8099"
    "/arclight/${var.environment}/shuttleforge/public-url"   = "https://shuttleforge.${var.environment}.${var.domain_name}"
    "/arclight/${var.environment}/shuttleforge/internal-url" = "http://shuttleforge.${var.private_dns_namespace}:9000"
  }
}

resource "aws_ssm_parameter" "this" {
  for_each = local.ssm_parameters

  name  = each.key
  type  = "String"
  value = each.value

  tags = { Name = each.key }
}

################################################################################
# Per-service ECS execution roles
################################################################################

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_exec" {
  for_each = toset(local.services)

  name               = "arclight-ecs-exec-${each.key}-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json

  tags = { Name = "arclight-ecs-exec-${each.key}-${var.environment}" }
}

resource "aws_iam_role_policy" "ecs_exec_secrets" {
  for_each = toset(local.services)

  name = "secrets-access"
  role = aws_iam_role.ecs_exec[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsAccess"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:arclight/${var.environment}/${each.key}/*"
        ]
      },
      {
        Sid      = "KMSDecrypt"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = ["*"]
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${var.aws_region}.amazonaws.com"
          }
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "ecs_exec_ecr" {
  for_each = toset(local.services)

  name = "ecr-pull"
  role = aws_iam_role.ecs_exec[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = ["*"]
      },
      {
        Sid    = "ECRPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
        ]
        Resource = [var.ecr_repository_arns[local.ecr_repo_map[each.key]]]
      },
    ]
  })
}

resource "aws_iam_role_policy" "ecs_exec_logs" {
  for_each = toset(local.services)

  name = "cloudwatch-logs"
  role = aws_iam_role.ecs_exec[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = ["arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/arclight/${var.environment}/${each.key}:*"]
      },
    ]
  })
}
