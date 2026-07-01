terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "staging"
      Project     = "arclight"
      ManagedBy   = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

################################################################################
# ACM Certificate (requested in Phase 0A preflight)
################################################################################

data "aws_acm_certificate" "staging" {
  domain      = "*.staging.${var.domain_name}"
  statuses    = ["ISSUED"]
  most_recent = true
}

################################################################################
# Modules
################################################################################

module "vpc" {
  source = "../../modules/vpc"

  environment = var.environment
  vpc_cidr    = var.vpc_cidr
}

module "ecr" {
  source = "../../modules/ecr"

  environment = var.environment
}

module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  environment           = var.environment
  cluster_name          = "arclight-${var.environment}"
  private_dns_namespace = "${var.environment}.internal.${var.domain_name}"
  vpc_id                = module.vpc.vpc_id
}

module "rds" {
  source = "../../modules/rds-postgres"

  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  private_db_subnet_ids = module.vpc.private_db_subnet_ids
  instance_class        = var.rds_instance_class
  allocated_storage     = var.rds_allocated_storage
  app_security_group_ids = [
    module.vpc.sg_core_id,
    module.vpc.sg_shuttleforge_id,
    module.vpc.sg_podbay_controller_id,
    module.vpc.sg_dbbootstrap_id,
  ]
}

module "alb" {
  source = "../../modules/alb"

  environment       = var.environment
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  certificate_arn   = data.aws_acm_certificate.staging.arn
  domain_name       = "staging.${var.domain_name}"

  service_security_group_ids = {
    core         = module.vpc.sg_core_id
    shuttleforge = module.vpc.sg_shuttleforge_id
    podbay       = module.vpc.sg_podbay_controller_id
  }
}

module "secrets" {
  source = "../../modules/secrets"

  environment           = var.environment
  aws_region            = var.aws_region
  aws_account_id        = data.aws_caller_identity.current.account_id
  domain_name           = var.domain_name
  private_dns_namespace = "${var.environment}.internal.${var.domain_name}"
  ecr_repository_arns   = module.ecr.repository_arns
}

module "observability" {
  source = "../../modules/observability"

  environment      = var.environment
  aws_account_id   = data.aws_caller_identity.current.account_id
  aws_region       = var.aws_region
  alarm_email      = var.alarm_email
  alb_arn_suffix   = module.alb.alb_arn_suffix
  rds_instance_id  = "arclight-${var.environment}"
  ecs_cluster_name = module.ecs_cluster.cluster_name
}

module "ec2_capacity" {
  source = "../../modules/ecs-ec2-capacity-provider"

  environment        = var.environment
  cluster_name       = module.ecs_cluster.cluster_name
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_app_subnet_ids
  instance_type      = var.podbay_ec2_instance_type
  desired_capacity   = var.podbay_ec2_desired_capacity
}

module "iam_github_oidc" {
  source = "../../modules/iam-github-oidc"

  environment                = var.environment
  github_org                 = var.github_org
  github_repos               = var.github_repos
  ecr_repository_arns        = module.ecr.repository_arns
  ecs_cluster_arn            = module.ecs_cluster.cluster_arn
  terraform_state_bucket_arn = "arn:aws:s3:::arclight-terraform-state"
  aws_region                 = var.aws_region
  aws_account_id             = data.aws_caller_identity.current.account_id
}

################################################################################
# Core Service (Phase 1)
################################################################################

module "core_service" {
  source = "../../modules/ecs-service-fargate"

  service_name           = "core"
  environment            = var.environment
  cluster_id             = module.ecs_cluster.cluster_id
  cluster_name           = module.ecs_cluster.cluster_name
  subnet_ids             = module.vpc.private_app_subnet_ids
  security_group_id      = module.vpc.sg_core_id
  alb_security_group_id  = module.alb.alb_security_group_id
  rds_security_group_id  = module.rds.rds_security_group_id
  cloud_map_namespace_id = module.ecs_cluster.cloud_map_namespace_id
  target_group_arn       = module.alb.target_group_arns["core"]
  container_port         = 8000
  desired_count          = var.core_desired_count
  cpu                    = 256
  memory                 = 512
  execution_role_arn     = module.secrets.execution_role_arns["core"]

  task_definition_template = "${path.module}/../../services/core/task-definition.json.tpl"
  template_variables = {
    environment                = var.environment
    image                      = "${module.ecr.repository_urls["arclight/core"]}:${var.core_image_tag}"
    domain                     = "staging.${var.domain_name}"
    region                     = var.aws_region
    log_group                  = "/arclight/${var.environment}/core"
    secret_arn_database_url    = module.secrets.core_database_url_secret_arn
    secret_arn_signing_key     = module.secrets.secret_arns["arclight/${var.environment}/core/signing-key-encryption-key"]
    secret_arn_admin_bootstrap = module.secrets.secret_arns["arclight/${var.environment}/core/admin-bootstrap-secret"]
    secret_arn_oidc_google     = module.secrets.secret_arns["arclight/${var.environment}/core/oidc-google-client-secret"]
    secret_arn_oidc_microsoft  = module.secrets.secret_arns["arclight/${var.environment}/core/oidc-microsoft-client-secret"]
    secret_arn_oidc_github     = module.secrets.secret_arns["arclight/${var.environment}/core/oidc-github-client-secret"]
  }
}

################################################################################
# Capacity Provider Association (sole owner)
################################################################################

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = module.ecs_cluster.cluster_name
  capacity_providers = ["FARGATE", "FARGATE_SPOT", module.ec2_capacity.capacity_provider_name]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

################################################################################
# DB Bootstrap — temporary secret shells (no version, operator-populated)
################################################################################

resource "aws_secretsmanager_secret" "dbbootstrap_core_pw" {
  name        = "arclight/${var.environment}/dbbootstrap/core-db-password"
  description = "Temporary bootstrap password for core_staging DB role"
}

resource "aws_secretsmanager_secret" "dbbootstrap_sf_pw" {
  name        = "arclight/${var.environment}/dbbootstrap/shuttleforge-db-password"
  description = "Temporary bootstrap password for shuttleforge_staging DB role"
}

resource "aws_secretsmanager_secret" "dbbootstrap_podbay_pw" {
  name        = "arclight/${var.environment}/dbbootstrap/podbay-db-password"
  description = "Temporary bootstrap password for podbay_staging DB role"
}

resource "aws_secretsmanager_secret" "dbbootstrap_nf_pw" {
  name        = "arclight/${var.environment}/dbbootstrap/nerfherder-db-password"
  description = "Temporary bootstrap password for nerfherder_staging DB role"
}

################################################################################
# DB Bootstrap — SG egress rules (standalone, not inline)
################################################################################

resource "aws_security_group_rule" "dbbootstrap_https_egress" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = module.vpc.sg_dbbootstrap_id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "HTTPS for ECR pull, secrets injection, log delivery"
}

resource "aws_security_group_rule" "dbbootstrap_to_rds" {
  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.vpc.sg_dbbootstrap_id
  source_security_group_id = module.rds.rds_security_group_id
  description              = "PostgreSQL to RDS"
}

################################################################################
# DB Bootstrap — execution role
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

resource "aws_iam_role" "ecs_exec_dbbootstrap" {
  name               = "arclight-ecs-exec-dbbootstrap-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy" "dbbootstrap_secrets" {
  name = "secrets-access"
  role = aws_iam_role.ecs_exec_dbbootstrap.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RDSMasterSecret"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [module.rds.master_user_secret_arn]
      },
      {
        Sid    = "BootstrapSecrets"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:arclight/${var.environment}/dbbootstrap/*"
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

resource "aws_iam_role_policy" "dbbootstrap_ecr" {
  name = "ecr-pull"
  role = aws_iam_role.ecs_exec_dbbootstrap.id

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
        Resource = [module.ecr.repository_arns["arclight/dbbootstrap"]]
      },
    ]
  })
}

resource "aws_iam_role_policy" "dbbootstrap_logs" {
  name = "cloudwatch-logs"
  role = aws_iam_role.ecs_exec_dbbootstrap.id

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
        Resource = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/arclight/${var.environment}/dbbootstrap:*"]
      },
    ]
  })
}

################################################################################
# DB Bootstrap — task definition
################################################################################

resource "aws_ecs_task_definition" "dbbootstrap" {
  family                   = "arclight-dbbootstrap-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_exec_dbbootstrap.arn

  container_definitions = jsonencode([
    {
      name      = "dbbootstrap"
      image     = "${module.ecr.repository_urls["arclight/dbbootstrap"]}:v1"
      essential = true

      secrets = [
        { name = "PGUSER", valueFrom = "${module.rds.master_user_secret_arn}:username::" },
        { name = "PGPASSWORD", valueFrom = "${module.rds.master_user_secret_arn}:password::" },
        { name = "CORE_PW", valueFrom = aws_secretsmanager_secret.dbbootstrap_core_pw.arn },
        { name = "SF_PW", valueFrom = aws_secretsmanager_secret.dbbootstrap_sf_pw.arn },
        { name = "PODBAY_PW", valueFrom = aws_secretsmanager_secret.dbbootstrap_podbay_pw.arn },
        { name = "NF_PW", valueFrom = aws_secretsmanager_secret.dbbootstrap_nf_pw.arn },
      ]

      environment = [
        { name = "PGHOST", value = module.rds.instance_address },
        { name = "PGPORT", value = "5432" },
        { name = "PGDATABASE", value = "postgres" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/arclight/${var.environment}/dbbootstrap"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "bootstrap"
        }
      }
    }
  ])
}

################################################################################
# DB Verify Service — execution role
################################################################################

resource "aws_iam_role" "ecs_exec_dbverify_svc" {
  name               = "arclight-ecs-exec-dbverify-svc-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy" "dbverify_svc_secrets" {
  name = "secrets-access"
  role = aws_iam_role.ecs_exec_dbverify_svc.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ServiceDBSecrets"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [
          module.secrets.core_database_url_secret_arn,
          module.secrets.shuttleforge_db_url_secret_arn,
          module.secrets.podbay_database_url_secret_arn,
          module.secrets.nerfherder_database_url_secret_arn,
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

resource "aws_iam_role_policy" "dbverify_svc_ecr" {
  name = "ecr-pull"
  role = aws_iam_role.ecs_exec_dbverify_svc.id

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
        Resource = [module.ecr.repository_arns["arclight/dbbootstrap"]]
      },
    ]
  })
}

resource "aws_iam_role_policy" "dbverify_svc_logs" {
  name = "cloudwatch-logs"
  role = aws_iam_role.ecs_exec_dbverify_svc.id

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
        Resource = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/arclight/${var.environment}/dbbootstrap:*"]
      },
    ]
  })
}

################################################################################
# DB Verify Service — task definition
################################################################################

resource "aws_ecs_task_definition" "dbverify_svc" {
  family                   = "arclight-dbverify-svc-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_exec_dbverify_svc.arn

  container_definitions = jsonencode([
    {
      name      = "dbbootstrap"
      image     = "${module.ecr.repository_urls["arclight/dbbootstrap"]}:v1"
      essential = true

      secrets = [
        { name = "CORE_DATABASE_URL", valueFrom = module.secrets.core_database_url_secret_arn },
        { name = "SF_DATABASE_URL", valueFrom = module.secrets.shuttleforge_db_url_secret_arn },
        { name = "PODBAY_DATABASE_URL", valueFrom = module.secrets.podbay_database_url_secret_arn },
        { name = "NF_DATABASE_URL", valueFrom = module.secrets.nerfherder_database_url_secret_arn },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/arclight/${var.environment}/dbbootstrap"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "verify-svc"
        }
      }
    }
  ])
}
