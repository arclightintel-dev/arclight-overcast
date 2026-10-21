################################################################################
# Host instance role
################################################################################

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "host" {
  name               = "${local.name}-host"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

# Session Manager and Run Command. Also grants Parameter Store reads, so no separate SSM
# statement is needed for the host scripts.
resource "aws_iam_role_policy_attachment" "host_ssm" {
  role       = aws_iam_role.host.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "host" {
  name = "backstage-host"
  role = aws_iam_role.host.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "BackstageSecrets"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = ["arn:aws:secretsmanager:${var.aws_region}:${local.account_id}:secret:arclight/backstage/${var.environment}/*"]
      },
      {
        Sid       = "SecretsKMS"
        Effect    = "Allow"
        Action    = ["kms:Decrypt"]
        Resource  = ["*"]
        Condition = { StringEquals = { "kms:ViaService" = "secretsmanager.${var.aws_region}.amazonaws.com" } }
      },
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = ["*"]
      },
      {
        Sid      = "ECRPull"
        Effect   = "Allow"
        Action   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"]
        Resource = local.ecr_repository_arns
      },
      {
        Sid      = "ContainerLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
        Resource = flatten([for g in aws_cloudwatch_log_group.this : [g.arn, "${g.arn}:*"]])
      },
      {
        Sid       = "PublishMetrics"
        Effect    = "Allow"
        Action    = ["cloudwatch:PutMetricData"]
        Resource  = ["*"]
        Condition = { StringEquals = { "cloudwatch:namespace" = ["Arclight/Backstage", "CWAgent"] } }
      },
      {
        Sid      = "ReadRequestCount"
        Effect   = "Allow"
        Action   = ["cloudwatch:GetMetricStatistics"]
        Resource = ["*"]
      },
      {
        Sid      = "LitestreamBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [aws_s3_bucket.this["litestream"].arn]
      },
      {
        Sid      = "LitestreamObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["${aws_s3_bucket.this["litestream"].arn}/*"]
      },
      {
        Sid      = "ReadMigrationAndDeployBuckets"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.this["migration"].arn, aws_s3_bucket.this["deploy"].arn]
      },
      {
        Sid      = "ReadMigrationAndDeployObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${aws_s3_bucket.this["migration"].arn}/*", "${aws_s3_bucket.this["deploy"].arn}/*"]
      },
    ]
  })
}

resource "aws_iam_instance_profile" "host" {
  name = "${local.name}-host"
  role = aws_iam_role.host.name
}

################################################################################
# GitHub Actions: Backstage image push (Backstage repository, main only; B3)
################################################################################

data "aws_iam_policy_document" "push_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.backstage_repository}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "push" {
  name               = "${local.name}-ecr-push"
  assume_role_policy = data.aws_iam_policy_document.push_trust.json
}

resource "aws_iam_role_policy" "push" {
  name = "ecr-push-and-bundle"
  role = aws_iam_role.push.id

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
          "ecr:DescribeImages",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
        ]
        Resource = local.ecr_repository_arns
      },
      {
        Sid      = "DeployBundle"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = ["${aws_s3_bucket.this["deploy"].arn}/*"]
      },
    ]
  })
}

################################################################################
# GitHub Actions: deploy over SSM (Overcast repository, GitHub environment "backstage")
################################################################################

data "aws_iam_policy_document" "deploy_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # The GitHub environment "backstage" is restricted to the main branch (README); this
    # role can run any command as root on the host, so it trusts nothing else.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/arclight-overcast:environment:backstage"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name               = "${local.name}-deploy"
  assume_role_policy = data.aws_iam_policy_document.deploy_trust.json
}

resource "aws_iam_role_policy" "deploy" {
  name = "deploy-over-ssm"
  role = aws_iam_role.deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RunDeployCommand"
        Effect = "Allow"
        Action = ["ssm:SendCommand"]
        Resource = [
          aws_instance.host.arn,
          "arn:aws:ssm:${var.aws_region}::document/AWS-RunShellScript",
        ]
      },
      {
        Sid      = "FollowCommand"
        Effect   = "Allow"
        Action   = ["ssm:GetCommandInvocation", "ssm:ListCommandInvocations", "ssm:DescribeInstanceInformation"]
        Resource = ["*"]
      },
      {
        Sid      = "FindHost"
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = ["*"]
      },
      {
        Sid      = "WakeHost"
        Effect   = "Allow"
        Action   = ["ec2:StartInstances"]
        Resource = [aws_instance.host.arn]
      },
      {
        Sid      = "VerifyImages"
        Effect   = "Allow"
        Action   = ["ecr:DescribeImages"]
        Resource = local.ecr_repository_arns
      },
      {
        Sid      = "ReadBundleList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.this["deploy"].arn]
      },
      {
        Sid      = "ReadBundle"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${aws_s3_bucket.this["deploy"].arn}/*"]
      },
    ]
  })
}
