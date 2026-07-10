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
      values   = [
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
        Sid      = "PassRole"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
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
# Per-service ECR push roles
################################################################################

locals {
  ecr_push_roles = {
    core = {
      repo_name = "arclight-core"
      ecr_repos = ["arclight/core"]
    }
    shuttleforge = {
      repo_name = "arclight-shuttleforge"
      ecr_repos = ["arclight/shuttleforge"]
    }
    podbay = {
      repo_name = "arclight-podbay"
      ecr_repos = ["arclight/podbay", "arclight/podbay-workspace-browser"]
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
      values   = ["repo:${var.github_org}/${each.value.repo_name}:ref:refs/heads/main"]
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
