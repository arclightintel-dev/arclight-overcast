################################################################################
# SF.11 Stage B fixture upstream (spec: docs/proposals/sf-stage-b-fixture-upstream.md, rev 2,
# approved 2026-11-11, PR #93)
#
# A TCP accept-and-close listener for ShuttleForge's single fixture endpoint. SF's health checker
# connects and closes about every 60 s; nothing else uses it. It lives from B1 through B4, and is
# torn down by setting sf_fixture_upstream_enabled = false, before Stage C's first live write.
################################################################################

locals {
  fx_enabled   = var.sf_fixture_upstream_enabled
  fx_name      = "fixture-upstream"
  fx_port      = 8080
  fx_log_group = "/arclight/${var.environment}/${local.fx_name}"
  # Overcast's own dbbootstrap image (postgres:16-alpine, busybox), pinned by digest (v1-9264f1a).
  fx_image = "${module.ecr.repository_urls["arclight/dbbootstrap"]}@sha256:5d05a32b5bde13c47b7eecef4da206dc78324feea732e10606c7ae1e69ba4147"
}

resource "aws_security_group" "fixture_upstream" {
  count = local.fx_enabled ? 1 : 0

  name_prefix = "arclight-${var.environment}-fixture-upstream-"
  description = "SF Stage B fixture upstream listener (TCP 8080 from ShuttleForge only)"
  vpc_id      = module.vpc.vpc_id

  tags = { Name = "arclight-${var.environment}-fixture-upstream" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "fx_from_sf" {
  count = local.fx_enabled ? 1 : 0

  type                     = "ingress"
  from_port                = local.fx_port
  to_port                  = local.fx_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.fixture_upstream[0].id
  source_security_group_id = module.vpc.sg_shuttleforge_id
  description              = "ShuttleForge health probe to the fixture listener"
}

# Image pull and logs only. The VPC-endpoint group already admits 443 from the private app subnets.
resource "aws_security_group_rule" "fx_to_vpce_443" {
  count = local.fx_enabled ? 1 : 0

  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.fixture_upstream[0].id
  source_security_group_id = module.vpc.sg_vpc_endpoints_id
  description              = "Fixture listener to interface endpoints (ECR, logs)"
}

resource "aws_security_group_rule" "fx_to_s3_443" {
  count = local.fx_enabled ? 1 : 0

  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.fixture_upstream[0].id
  prefix_list_ids   = [module.vpc.s3_prefix_list_id]
  description       = "Fixture listener to S3 through the gateway endpoint (image layers)"
}

resource "aws_cloudwatch_log_group" "fixture_upstream" {
  count = local.fx_enabled ? 1 : 0

  name              = local.fx_log_group
  retention_in_days = 7

  tags = { Name = local.fx_log_group }
}

resource "aws_iam_role" "fx_exec" {
  count = local.fx_enabled ? 1 : 0

  name               = "arclight-ecs-exec-fixture-upstream-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json

  tags = { Name = "arclight-ecs-exec-fixture-upstream-${var.environment}" }
}

resource "aws_iam_role_policy" "fx_exec" {
  count = local.fx_enabled ? 1 : 0

  name = "fixture-exec"
  role = aws_iam_role.fx_exec[0].id

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
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["${aws_cloudwatch_log_group.fixture_upstream[0].arn}:*"]
      },
    ]
  })
}

module "fixture_upstream_service" {
  source = "../../modules/ecs-service-fargate"
  count  = local.fx_enabled ? 1 : 0

  service_name           = local.fx_name
  environment            = var.environment
  cluster_id             = module.ecs_cluster.cluster_id
  cluster_name           = module.ecs_cluster.cluster_name
  subnet_ids             = module.vpc.private_app_subnet_ids
  security_group_id      = aws_security_group.fixture_upstream[0].id
  alb_security_group_id  = module.alb.alb_security_group_id
  cloud_map_namespace_id = module.ecs_cluster.cloud_map_namespace_id
  container_port         = local.fx_port
  desired_count          = 1
  cpu                    = 256
  memory                 = 512
  execution_role_arn     = aws_iam_role.fx_exec[0].arn

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  # busybox nc persistent server mode: the parent keeps the listening socket and each accepted
  # connection runs `true` and closes, so there is no accept gap and no client can hold the port.
  container_definitions = jsonencode([
    {
      name       = local.fx_name
      image      = local.fx_image
      essential  = true
      entryPoint = ["sh", "-c"]
      command    = ["exec busybox nc -ll -p ${local.fx_port} -e /bin/busybox true"]
      portMappings = [
        { containerPort = local.fx_port, protocol = "tcp" },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = local.fx_log_group
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = local.fx_name
        }
      }
    }
  ])

  depends_on = [aws_cloudwatch_log_group.fixture_upstream, aws_iam_role_policy.fx_exec]
}
