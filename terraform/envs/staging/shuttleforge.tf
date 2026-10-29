################################################################################
# ShuttleForge (Phase 1.5): staging substrate for O-2..O-4 and the Core JWKS path
#
# Inputs: arclight-shuttleforge docs/DEPLOYMENT_MANIFEST.md rev 3 (d031251, accepted
# 2026-10-21) and SF's 2026-10-29 answers relayed by Complex (secret bindings, health
# check, migrate command). O-1 (ingress on 9000/9050/9100 from Nerfherder) lands with
# Nerfherder's wiring: no Nerfherder security group exists yet.
################################################################################

locals {
  # Terraform registers the base revisions only. Deploys go through deploy-service.yml,
  # which copies the latest ACTIVE revision and swaps in repo@sha256 (O-3); the migrate
  # family is registered the same way before each run. The base therefore names a digest
  # that cannot exist, so a stray scale-up of a Terraform revision fails to pull instead
  # of running an unreviewed image, and Terraform never churns on image changes.
  sf_image_unset = "${module.ecr.repository_urls["arclight/shuttleforge"]}@sha256:${format("%064d", 0)}"

  # Same expression as module.ecs_cluster and module.secrets (the SSM jwks-url parameter).
  sf_namespace = "${var.environment}.internal.${var.domain_name}"
}

################################################################################
# Serving service: singleton, stop before start (O-2), base revision only (O-3)
#
# No SHUTTLEFORGE_POLICY_YAML_B64 yet: the image then installs its shipped
# deny-by-default policy (no leases granted). The reviewed staging policy comes from
# the SF operator; how it is delivered is open while this repository is public (DR-14).
################################################################################

module "shuttleforge_service" {
  source = "../../modules/ecs-service-fargate"

  service_name           = "shuttleforge"
  environment            = var.environment
  cluster_id             = module.ecs_cluster.cluster_id
  cluster_name           = module.ecs_cluster.cluster_name
  subnet_ids             = module.vpc.private_app_subnet_ids
  security_group_id      = module.vpc.sg_shuttleforge_id
  alb_security_group_id  = module.alb.alb_security_group_id
  rds_security_group_id  = module.rds.rds_security_group_id
  cloud_map_namespace_id = module.ecs_cluster.cloud_map_namespace_id
  target_group_arn       = module.alb.target_group_arns["shuttleforge"]
  container_port         = 9000
  desired_count          = var.shuttleforge_desired_count
  cpu                    = 1024
  memory                 = 2048
  execution_role_arn     = module.secrets.execution_role_arns["shuttleforge"]

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  # Manifest: at least 110 s plus one 30 s probe interval.
  health_check_grace_period_seconds = 150

  container_definitions = templatefile("${path.module}/../../../services/shuttleforge/task-definition.json.tpl", {
    environment               = var.environment
    image                     = local.sf_image_unset
    namespace                 = local.sf_namespace
    region                    = var.aws_region
    log_group                 = "/arclight/${var.environment}/shuttleforge"
    secret_arn_db_url         = module.secrets.shuttleforge_db_url_secret_arn
    secret_arn_kek_ring       = module.secrets.secret_arns["arclight/${var.environment}/shuttleforge/kek-ring-b64"]
    secret_arn_listener_hmac  = module.secrets.secret_arns["arclight/${var.environment}/shuttleforge/listener-auth-hmac-key"]
    secret_arn_lease_hmac     = module.secrets.secret_arns["arclight/${var.environment}/shuttleforge/lease-hmac-key"]
    secret_arn_operator_token = module.secrets.secret_arns["arclight/${var.environment}/shuttleforge/operator-token"]
  })
}

################################################################################
# Migrate-only family (O-4): run as a one-off before each serving deploy
################################################################################

resource "aws_ecs_task_definition" "sf_migrate" {
  family                   = "arclight-shuttleforge-migrate-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_exec_sf_migrate.arn

  container_definitions = jsonencode([
    {
      name      = "shuttleforge"
      image     = local.sf_image_unset
      essential = true
      # The image ENTRYPOINT (scripts/entrypoint.sh) stays; exactly one argument.
      command = ["--migrate-only"]

      environment = [
        { name = "SHUTTLEFORGE_DB_EXPECTED_NAME", value = "shuttleforge_${var.environment}" },
        { name = "SHUTTLEFORGE_DB_TLS_MODE", value = "require" },
      ]

      secrets = [
        { name = "SHUTTLEFORGE_DB_URL", valueFrom = aws_secretsmanager_secret.sf_db_url_migration.arn },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/arclight/${var.environment}/shuttleforge"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "migrate"
        }
      }
    }
  ])
}

################################################################################
# Secrets: the schema-owner URL for the migrate-only task (shell only, INV-004)
################################################################################

resource "aws_secretsmanager_secret" "sf_db_url_migration" {
  name        = "arclight/${var.environment}/shuttleforge/db-url-migration"
  description = "ShuttleForge PostgreSQL connection string, schema owner (migrate-only task)"

  tags = { Name = "arclight/${var.environment}/shuttleforge/db-url-migration" }
}

# The serving execution role reads arclight/<env>/shuttleforge/*, which would include
# the schema-owner URL. SF: never bind it to the serving task; this makes that structural.
resource "aws_iam_role_policy" "sf_exec_no_migration_url" {
  name = "deny-migration-url"
  role = element(split("/", module.secrets.execution_role_arns["shuttleforge"]), 1)

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "NoSchemaOwnerUrl"
        Effect   = "Deny"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.sf_db_url_migration.arn]
      },
    ]
  })
}

################################################################################
# Security group pair: ShuttleForge -> Core JWKS on 8000
#
# SF's only Core traffic is GET /.well-known/jwks.json. Under D-074 section 3 SF refuses
# every Core JWT after 1 h without a JWKS refresh, so this path must stay stable.
################################################################################

resource "aws_security_group_rule" "core_from_sf" {
  type                     = "ingress"
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  security_group_id        = module.vpc.sg_core_id
  source_security_group_id = module.vpc.sg_shuttleforge_id
  description              = "ShuttleForge to Core JWKS"
}

resource "aws_security_group_rule" "sf_to_core" {
  type                     = "egress"
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  security_group_id        = module.vpc.sg_shuttleforge_id
  source_security_group_id = module.vpc.sg_core_id
  description              = "ShuttleForge to Core JWKS"
}

################################################################################
# Migrate-only execution role: the schema-owner URL and nothing else
################################################################################

resource "aws_iam_role" "ecs_exec_sf_migrate" {
  name               = "arclight-ecs-exec-shuttleforge-migrate-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json

  tags = { Name = "arclight-ecs-exec-shuttleforge-migrate-${var.environment}" }
}

resource "aws_iam_role_policy" "sf_migrate_exec" {
  name = "migrate-exec"
  role = aws_iam_role.ecs_exec_sf_migrate.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SchemaOwnerUrl"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.sf_db_url_migration.arn]
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
        Resource = [module.ecr.repository_arns["arclight/shuttleforge"]]
      },
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/arclight/${var.environment}/shuttleforge:*"]
      },
    ]
  })
}
