################################################################################
# Nerfherder (O-013 under D-072, staging only): wiring for NF's accepted manifest
#
# Inputs: arclight-nerfherder docs/DEPLOYMENT_MANIFEST.md at cf5b228 (final for every rendered
# value) and Overcast's 2026-10-29 confirmations (nine items). NF egresses only through
# ShuttleForge (NERFHERDER_EGRESS_MODE=sf_required); nothing calls NF except one-off probe tasks
# in its own group. Service at desired count 0: applying this starts nothing.
################################################################################

locals {
  nf_name = "nerfherder"
  # Base revisions name a digest that cannot exist, as for ShuttleForge: deploys register copies
  # with the real digest, and a stray scale-up of a Terraform revision fails to pull.
  nf_image_unset = "${module.ecr.repository_urls["arclight/nerfherder"]}@sha256:${format("%064d", 0)}"
  nf_log_group   = "/arclight/${var.environment}/nerfherder"
  nf_bucket      = "arclight-${var.environment}-nerfherder-artifacts"
  # Non-secret Core service-client id (Core tranche E, 2026-10-21).
  nf_core_client_id = "svc_Z4lnTjH5BuMAHpG6U4S2tTvb"

  nf_secret_database_url      = module.secrets.secret_arns["arclight/${var.environment}/nerfherder/database-url"]
  nf_secret_core_client       = module.secrets.secret_arns["arclight/${var.environment}/nerfherder/core-client-secret"]
  nf_database_ssl_environment = [{ name = "NERFHERDER_DATABASE_SSL_MODE", value = "require" }]
  nf_s3_environment = [
    { name = "NERFHERDER_S3_BUCKET", value = local.nf_bucket },
    { name = "NERFHERDER_S3_REGION", value = var.aws_region },
    { name = "NERFHERDER_S3_ENDPOINT_URL", value = "" },
    { name = "NERFHERDER_S3_ACCESS_KEY", value = "" },
    { name = "NERFHERDER_S3_SECRET_KEY", value = "" },
  ]
}

################################################################################
# Network: NF's group and every path it uses
################################################################################

resource "aws_security_group" "nerfherder" {
  name_prefix = "arclight-${var.environment}-nerfherder-"
  description = "Nerfherder Fargate tasks"
  vpc_id      = module.vpc.vpc_id

  tags = { Name = "sg-nerfherder-${var.environment}" }
}

# The Fargate module adds 443 egress (secrets, ECR, logs, S3) and 5432 to RDS for this group;
# the RDS side admits it through module.rds app_security_group_ids.

resource "aws_security_group_rule" "nf_to_core" {
  type                     = "egress"
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  security_group_id        = aws_security_group.nerfherder.id
  source_security_group_id = module.vpc.sg_core_id
  description              = "Nerfherder to Core token endpoint"
}

resource "aws_security_group_rule" "core_from_nf" {
  type                     = "ingress"
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  security_group_id        = module.vpc.sg_core_id
  source_security_group_id = aws_security_group.nerfherder.id
  description              = "Nerfherder to Core token endpoint"
}

# O-1, rescoped to Nerfherder (2026-10-29): lease API 9000, dataplane 9050, mitm 9100.
resource "aws_security_group_rule" "nf_to_sf" {
  for_each = toset(["9000", "9050", "9100"])

  type                     = "egress"
  from_port                = tonumber(each.key)
  to_port                  = tonumber(each.key)
  protocol                 = "tcp"
  security_group_id        = aws_security_group.nerfherder.id
  source_security_group_id = module.vpc.sg_shuttleforge_id
  description              = "Nerfherder to ShuttleForge ${each.key}"
}

resource "aws_security_group_rule" "sf_from_nf" {
  for_each = toset(["9000", "9050", "9100"])

  type                     = "ingress"
  from_port                = tonumber(each.key)
  to_port                  = tonumber(each.key)
  protocol                 = "tcp"
  security_group_id        = module.vpc.sg_shuttleforge_id
  source_security_group_id = aws_security_group.nerfherder.id
  description              = "Nerfherder to ShuttleForge ${each.key} (O-1)"
}

# NF's post-deploy check reads /ready/detail, and nothing else can reach NF: a one-off probe task
# in this group calls the service on 8100.
resource "aws_security_group_rule" "nf_probe_self" {
  type              = "ingress"
  from_port         = 8100
  to_port           = 8100
  protocol          = "tcp"
  security_group_id = aws_security_group.nerfherder.id
  self              = true
  description       = "Post-deploy probe tasks in this group"
}

resource "aws_security_group_rule" "nf_probe_self_egress" {
  type              = "egress"
  from_port         = 8100
  to_port           = 8100
  protocol          = "tcp"
  security_group_id = aws_security_group.nerfherder.id
  self              = true
  description       = "Post-deploy probe tasks in this group"
}

################################################################################
# Secrets (shells only, INV-004) and logs
################################################################################

resource "aws_secretsmanager_secret" "nf_migration_database_url" {
  name        = "arclight/${var.environment}/nerfherder/migration-database-url"
  description = "Nerfherder PostgreSQL connection string, schema owner (migrate family)"

  tags = { Name = "arclight/${var.environment}/nerfherder/migration-database-url" }
}

resource "aws_secretsmanager_secret" "dbbootstrap_nf_app_pw" {
  name        = "arclight/${var.environment}/dbbootstrap/nerfherder-app-db-password"
  description = "Bootstrap password for the DML-only nerfherder_app_staging role (nf-app-role mode)"
}

resource "aws_cloudwatch_log_group" "nerfherder" {
  name              = local.nf_log_group
  retention_in_days = 30

  tags = { Name = local.nf_log_group }
}

################################################################################
# Artifact and evidence bucket: no expiration or transition (manifest M:205-206; artifact keys
# share no prefix a rule could exempt). Only incomplete multipart uploads are cleaned up.
################################################################################

resource "aws_s3_bucket" "nerfherder" {
  bucket = local.nf_bucket

  tags = { Name = local.nf_bucket }
}

resource "aws_s3_bucket_public_access_block" "nerfherder" {
  bucket                  = aws_s3_bucket.nerfherder.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "nerfherder" {
  bucket = aws_s3_bucket.nerfherder.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "nerfherder" {
  bucket = aws_s3_bucket.nerfherder.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "nerfherder" {
  bucket = aws_s3_bucket.nerfherder.id
  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "nerfherder" {
  bucket = aws_s3_bucket.nerfherder.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "TLSOnly"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.nerfherder.arn, "${aws_s3_bucket.nerfherder.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  })
}

################################################################################
# Roles: runtime execution (service, bootstrap), migrate execution, and the S3 task role
################################################################################

resource "aws_iam_role" "nf_exec" {
  name               = "arclight-ecs-exec-nerfherder-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json

  tags = { Name = "arclight-ecs-exec-nerfherder-${var.environment}" }
}

resource "aws_iam_role" "nf_migrate_exec" {
  name               = "arclight-ecs-exec-nerfherder-migrate-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json

  tags = { Name = "arclight-ecs-exec-nerfherder-migrate-${var.environment}" }
}

resource "aws_iam_role" "nf_task" {
  name               = "arclight-ecs-task-nerfherder-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json

  tags = { Name = "arclight-ecs-task-nerfherder-${var.environment}" }
}

locals {
  nf_exec_common = [
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
      Resource = [module.ecr.repository_arns["arclight/nerfherder"]]
    },
    {
      Sid      = "Logs"
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = ["${aws_cloudwatch_log_group.nerfherder.arn}:*"]
    },
  ]
}

resource "aws_iam_role_policy" "nf_exec" {
  name = "runtime-exec"
  role = aws_iam_role.nf_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid      = "RuntimeSecrets"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [local.nf_secret_database_url, local.nf_secret_core_client]
      },
    ], local.nf_exec_common)
  })
}

resource "aws_iam_role_policy" "nf_migrate_exec" {
  name = "migrate-exec"
  role = aws_iam_role.nf_migrate_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid      = "SchemaOwnerUrl"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.nf_migration_database_url.arn]
      },
    ], local.nf_exec_common)
  })
}

# Manifest M:95-97: ListBucket on the bucket with no s3:prefix condition, objects on bucket/*.
resource "aws_iam_role_policy" "nf_task_s3" {
  name = "artifact-bucket"
  role = aws_iam_role.nf_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "List"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.nerfherder.arn]
      },
      {
        Sid      = "Objects"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["${aws_s3_bucket.nerfherder.arn}/*"]
      },
    ]
  })
}

################################################################################
# Service: singleton, stop before start (O-2), internal only (no ALB)
################################################################################

module "nerfherder_service" {
  source = "../../modules/ecs-service-fargate"

  service_name           = local.nf_name
  environment            = var.environment
  cluster_id             = module.ecs_cluster.cluster_id
  cluster_name           = module.ecs_cluster.cluster_name
  subnet_ids             = module.vpc.private_app_subnet_ids
  security_group_id      = aws_security_group.nerfherder.id
  alb_security_group_id  = module.alb.alb_security_group_id
  rds_security_group_id  = module.rds.rds_security_group_id
  cloud_map_namespace_id = module.ecs_cluster.cloud_map_namespace_id
  container_port         = 8100
  desired_count          = var.nerfherder_desired_count
  cpu                    = 1024
  memory                 = 2048
  execution_role_arn     = aws_iam_role.nf_exec.arn
  task_role_arn          = aws_iam_role.nf_task.arn

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  container_definitions = templatefile("${path.module}/../../../services/nerfherder/task-definition.json.tpl", {
    environment                   = var.environment
    image                         = local.nf_image_unset
    namespace                     = local.sf_namespace
    region                        = var.aws_region
    log_group                     = local.nf_log_group
    bucket                        = local.nf_bucket
    core_client_id                = local.nf_core_client_id
    secret_arn_database_url       = local.nf_secret_database_url
    secret_arn_core_client_secret = local.nf_secret_core_client
  })
}

################################################################################
# Migrate family (schema owner) and bootstrap family (runtime role; NF's evidence export and
# diagnostics run as command overrides of it)
################################################################################

resource "aws_ecs_task_definition" "nf_migrate" {
  family                   = "arclight-nerfherder-migrate-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = aws_iam_role.nf_migrate_exec.arn

  container_definitions = jsonencode([
    {
      name        = local.nf_name
      image       = local.nf_image_unset
      essential   = true
      command     = ["python", "-m", "nerfherder.migrate"]
      environment = concat([{ name = "ENVIRONMENT", value = var.environment }], local.nf_database_ssl_environment)
      secrets = [
        { name = "NERFHERDER_DATABASE_URL", valueFrom = aws_secretsmanager_secret.nf_migration_database_url.arn },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = local.nf_log_group
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "migrate"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "nf_bootstrap" {
  family                   = "arclight-nerfherder-bootstrap-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = aws_iam_role.nf_exec.arn
  task_role_arn            = aws_iam_role.nf_task.arn

  container_definitions = jsonencode([
    {
      name      = local.nf_name
      image     = local.nf_image_unset
      essential = true
      # Runs override this: --dry-run first; `nerfherder.evidence export` and
      # `nerfherder.diagnostics operation` also run on this family (manifest M:142-172).
      command = ["python", "-m", "nerfherder.bootstrap", "--input-env", "NERFHERDER_BOOTSTRAP_INPUT"]
      environment = concat(
        [{ name = "ENVIRONMENT", value = var.environment }],
        local.nf_database_ssl_environment,
        local.nf_s3_environment,
      )
      secrets = [
        { name = "NERFHERDER_DATABASE_URL", valueFrom = local.nf_secret_database_url },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = local.nf_log_group
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "bootstrap"
        }
      }
    }
  ])
}

################################################################################
# Database bootstrap for NF's runtime role: its own family, so the shared dbbootstrap task never
# depends on NF's shells (ECS refuses a task whose secret has no value; ShuttleForge's
# post-migration sf-app-role run must not wait on Nerfherder).
################################################################################

resource "aws_ecs_task_definition" "dbbootstrap_nf" {
  family                   = "arclight-dbbootstrap-nf-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_exec_dbbootstrap.arn

  container_definitions = jsonencode([
    {
      name = "dbbootstrap"
      # v1-4a9ce79 = services/dbbootstrap at 4a9ce79 (adds nf-app-role). An administrator
      # builds and pushes it before its first run.
      image     = "${module.ecr.repository_urls["arclight/dbbootstrap"]}:v1-4a9ce79"
      essential = true
      command   = ["nf-app-role"]

      secrets = [
        { name = "PGUSER", valueFrom = "${module.rds.master_user_secret_arn}:username::" },
        { name = "PGPASSWORD", valueFrom = "${module.rds.master_user_secret_arn}:password::" },
        { name = "NF_APP_PW", valueFrom = aws_secretsmanager_secret.dbbootstrap_nf_app_pw.arn },
        { name = "NF_OWNER_URL", valueFrom = aws_secretsmanager_secret.nf_migration_database_url.arn },
      ]

      environment = [
        { name = "PGHOST", value = module.rds.instance_address },
        { name = "PGPORT", value = "5432" },
        { name = "PGDATABASE", value = "postgres" },
        { name = "ENVIRONMENT", value = var.environment },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/arclight/${var.environment}/dbbootstrap"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "bootstrap-nf"
        }
      }
    }
  ])
}

################################################################################
# Alarm: running-task count -> the staging alarm topic (manifest M:185). Actions are enabled only
# while the service is meant to run.
################################################################################

resource "aws_cloudwatch_metric_alarm" "nf_running_tasks" {
  alarm_name          = "arclight-${var.environment}-nerfherder-running-tasks"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "RunningTaskCount"
  namespace           = "ECS/ContainerInsights"
  period              = 300
  statistic           = "Minimum"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_description   = "Nerfherder has no running task"
  actions_enabled     = var.nerfherder_desired_count > 0
  alarm_actions       = [module.observability.alarm_topic_arn]

  dimensions = {
    ClusterName = module.ecs_cluster.cluster_name
    ServiceName = "arclight-${local.nf_name}-${var.environment}"
  }
}
