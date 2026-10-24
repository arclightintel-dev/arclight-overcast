################################################################################
# GitHub OIDC Provider
################################################################################

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = { Name = "github-actions" }
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.oidc_provider_arn
}

################################################################################
# Overcast-only Terraform role (infra deploy)
################################################################################

data "aws_iam_policy_document" "overcast_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_org}/arclight-overcast:ref:refs/heads/main",
        "repo:${var.github_org}/arclight-overcast:environment:${var.environment}",
      ]
    }
  }
}

resource "aws_iam_role" "overcast_terraform" {
  name               = "arclight-overcast-terraform-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.overcast_trust.json

  tags = { Name = "arclight-overcast-terraform-${var.environment}" }
}

resource "aws_iam_role_policy" "overcast_terraform_state" {
  name = "terraform-state"
  role = aws_iam_role.overcast_terraform.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3State"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
        ]
        Resource = [
          var.terraform_state_bucket_arn,
          "${var.terraform_state_bucket_arn}/*",
        ]
      },
      {
        Sid    = "DynamoDBLegacy"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
        ]
        Resource = ["arn:aws:dynamodb:${var.aws_region}:${var.aws_account_id}:table/arclight-terraform-locks"]
      },
    ]
  })
}

resource "aws_iam_role_policy" "overcast_terraform_deploy" {
  name = "ecs-deploy"
  role = aws_iam_role.overcast_terraform.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECSClusterScoped"
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "ecs:ListTasks",
          "ecs:DescribeTasks",
          "ecs:RunTask",
        ]
        Resource = ["*"]
        Condition = {
          ArnEquals = {
            "ecs:cluster" = var.ecs_cluster_arn
          }
        }
      },
      {
        Sid    = "ECSTaskDefinitions"
        Effect = "Allow"
        Action = [
          "ecs:RegisterTaskDefinition",
          "ecs:DeregisterTaskDefinition",
          "ecs:DescribeTaskDefinition",
        ]
        Resource = ["*"]
      },
      {
        Sid    = "ECRVerifyImage"
        Effect = "Allow"
        Action = [
          "ecr:DescribeImages",
          "ecr:BatchGetImage",
        ]
        Resource = [for arn in values(var.ecr_repository_arns) : arn]
      },
      {
        Sid    = "PassRole"
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = [
          "arn:aws:iam::${var.aws_account_id}:role/arclight-ecs-*-${var.environment}",
          "arn:aws:iam::${var.aws_account_id}:role/arclight-*-task-role-${var.environment}",
        ]
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      },
    ]
  })
}

################################################################################
# Read-only plan role for pull requests (DR-1b)
################################################################################

# Pull-request runs present the subject repo:<org>/arclight-overcast:pull_request, which the
# Terraform role above must never trust: anyone who can open a pull request can change the
# workflow in it. This role can read, not write, and cannot read object contents, image
# layers, log events or secret values. Fork pull requests receive no OIDC token.
locals {
  state_object_arn = "${var.terraform_state_bucket_arn}/${var.environment}/terraform.tfstate"
}

data "aws_iam_policy_document" "overcast_plan_trust" {
  count = var.create_plan_role ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/arclight-overcast:pull_request"]
    }
  }
}

resource "aws_iam_role" "overcast_plan" {
  count = var.create_plan_role ? 1 : 0

  name               = "arclight-overcast-terraform-plan-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.overcast_plan_trust[0].json

  tags = { Name = "arclight-overcast-terraform-plan-${var.environment}" }
}

resource "aws_iam_role_policy_attachment" "overcast_plan_read" {
  count = var.create_plan_role ? 1 : 0

  role       = aws_iam_role.overcast_plan[0].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "overcast_plan_guardrails" {
  count = var.create_plan_role ? 1 : 0

  name = "plan-guardrails"
  role = aws_iam_role.overcast_plan[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid         = "NoObjectContentsButState"
        Effect      = "Deny"
        Action      = ["s3:GetObject", "s3:GetObjectVersion"]
        NotResource = [local.state_object_arn]
      },
      {
        Sid      = "NoImageLayers"
        Effect   = "Deny"
        Action   = ["ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"]
        Resource = ["*"]
      },
      {
        Sid    = "NoLogEvents"
        Effect = "Deny"
        Action = [
          "logs:GetLogEvents",
          "logs:FilterLogEvents",
          "logs:StartQuery",
          "logs:GetQueryResults",
          "logs:StartLiveTail",
          "logs:GetLogRecord",
        ]
        Resource = ["*"]
      },
      {
        Sid      = "NoSecretValues"
        Effect   = "Deny"
        Action   = ["kms:Decrypt", "secretsmanager:GetSecretValue"]
        Resource = ["*"]
      },
    ]
  })
}

resource "aws_iam_role_policy" "overcast_plan_state" {
  count = var.create_plan_role ? 1 : 0

  name = "plan-state"
  role = aws_iam_role.overcast_plan[0].id

  # Read the state; write only the backend's lock file (use_lockfile).
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StateList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [var.terraform_state_bucket_arn]
      },
      {
        Sid      = "StateLock"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = ["${local.state_object_arn}.tflock"]
      },
    ]
  })
}

################################################################################
# Per-service ECR push roles
################################################################################

locals {
  # refs: branches whose GitHub Actions runs may assume the push role. ShuttleForge
  # builds v1 images from its release line v1-operate (SF-D-0252), not main.
  ecr_push_roles = {
    core = {
      repo_name = "arclight-core"
      ecr_repos = ["arclight/core"]
      refs      = ["main"]
    }
    shuttleforge = {
      repo_name = "arclight-shuttleforge"
      ecr_repos = ["arclight/shuttleforge"]
      refs      = ["main", "v1-operate"]
    }
  }
}

data "aws_iam_policy_document" "ecr_push_trust" {
  for_each = local.ecr_push_roles

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for ref in each.value.refs : "repo:${var.github_org}/${each.value.repo_name}:ref:refs/heads/${ref}"]
    }
  }
}

resource "aws_iam_role" "ecr_push" {
  for_each = local.ecr_push_roles

  name               = "arclight-${each.key}-ecr-push-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.ecr_push_trust[each.key].json

  tags = { Name = "arclight-${each.key}-ecr-push-${var.environment}" }
}

resource "aws_iam_role_policy" "ecr_push" {
  for_each = local.ecr_push_roles

  name = "ecr-push"
  role = aws_iam_role.ecr_push[each.key].id

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
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
        ]
        Resource = [for repo in each.value.ecr_repos : var.ecr_repository_arns[repo]]
      },
    ]
  })
}
