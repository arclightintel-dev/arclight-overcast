################################################################################
# Task Definition
################################################################################

resource "aws_ecs_task_definition" "this" {
  family                   = "arclight-${var.service_name}-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = templatefile(var.task_definition_template, var.template_variables)
}

################################################################################
# Cloud Map Service Discovery
################################################################################

resource "aws_service_discovery_service" "this" {
  name = var.service_name

  dns_config {
    namespace_id = var.cloud_map_namespace_id

    dns_records {
      type = "A"
      ttl  = 10
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

################################################################################
# Security Group Rules
################################################################################

resource "aws_security_group_rule" "alb_ingress" {
  count = var.target_group_arn != null ? 1 : 0

  type                     = "ingress"
  from_port                = var.container_port
  to_port                  = var.container_port
  protocol                 = "tcp"
  security_group_id        = var.security_group_id
  source_security_group_id = var.alb_security_group_id
  description              = "ALB to ${var.service_name}"
}

resource "aws_security_group_rule" "https_egress" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = var.security_group_id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "HTTPS for ECR, secrets, logs, external APIs"
}

resource "aws_security_group_rule" "rds_egress" {
  count = var.rds_security_group_id != null ? 1 : 0

  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = var.security_group_id
  source_security_group_id = var.rds_security_group_id
  description              = "PostgreSQL to RDS"
}

################################################################################
# ECS Service
################################################################################

resource "aws_ecs_service" "this" {
  name            = "arclight-${var.service_name}-${var.environment}"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [var.security_group_id]
    assign_public_ip = false
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  health_check_grace_period_seconds = var.target_group_arn != null ? var.health_check_grace_period_seconds : null

  dynamic "load_balancer" {
    for_each = var.target_group_arn != null ? [1] : []
    content {
      target_group_arn = var.target_group_arn
      container_name   = var.service_name
      container_port   = var.container_port
    }
  }

  service_registries {
    registry_arn = aws_service_discovery_service.this.arn
  }

  depends_on = [
    aws_security_group_rule.alb_ingress,
    aws_security_group_rule.https_egress,
    aws_security_group_rule.rds_egress,
  ]
}
