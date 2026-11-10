################################################################################
# Internal TLS for Core (D-077, DR-10), phase P1
#
# Spec: docs/proposals/internal-tls-nlb.md (revision 3, merged a9979c6). An internal NLB
# terminates TLS with the public *.staging certificate in front of Core :8000. The last hop
# stays plain inside the private subnets (owner's option A).
#
# Core gets its own NLB. An NLB's zonal DNS health spans every attached target group and fails
# open on empty groups, so ShuttleForge gets a separate NLB in P2 and never shares this one.
#
# Fixed settings, all deliberate (see the spec's "NLB gates"):
#   - cross-zone ON for Core's target group (owner, 2026-11-10; overrides the NLB-level off).
#     Core runs one task, and every deploy can move it to the other AZ. With cross-zone off, P1
#     measured the empty AZ's node staying in DNS for 4-6 minutes and failing after connect.
#     With it on, either node forwards to the task. The residual cost is AWS's documented
#     5-tuple collision class (client IP preservation, few targets); watch
#     TCP_Target_Reset_Count. This NLB carries only Core's group, so the shared-NLB coupling
#     that gave SF its own NLB does not apply;
#   - client IP preserved and proxy protocol v2 OFF: Core keys its rate limiter on the transport
#     peer, and uvicorn cannot parse a PPv2 header;
#   - NO target_group_health block: an empty dns_failover {} makes the provider set the count
#     to "off", which would keep the AZ without a task in DNS.
################################################################################

locals {
  internal_tls_env   = { staging = "stg", prod = "prd" }[var.environment]
  core_internal_fqdn = "core-internal.${var.environment}.${var.domain_name}"
}

resource "aws_security_group" "core_nlb" {
  name_prefix = "arclight-${var.environment}-core-nlb-"
  description = "Internal NLB in front of Core (TLS 443 to Core 8000)"
  vpc_id      = module.vpc.vpc_id

  tags = { Name = "sg-core-nlb-${var.environment}" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "core_nlb_from_sf_443" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.core_nlb.id
  source_security_group_id = module.vpc.sg_shuttleforge_id
  description              = "ShuttleForge to Core internal NLB (JWKS)"
}

resource "aws_security_group_rule" "core_nlb_from_nf_443" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.core_nlb.id
  source_security_group_id = aws_security_group.nerfherder.id
  description              = "Nerfherder to Core internal NLB (token endpoint, JWKS)"
}

resource "aws_security_group_rule" "core_nlb_to_core_8000" {
  type                     = "egress"
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  security_group_id        = aws_security_group.core_nlb.id
  source_security_group_id = module.vpc.sg_core_id
  description              = "Core internal NLB to Core (traffic and health checks)"
}

resource "aws_security_group_rule" "core_from_core_nlb_8000" {
  type                     = "ingress"
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  security_group_id        = module.vpc.sg_core_id
  source_security_group_id = aws_security_group.core_nlb.id
  description              = "Core internal NLB to Core (client IP preserved)"
}

resource "aws_lb" "core_internal" {
  name                             = "arclight-${local.internal_tls_env}-int-core"
  internal                         = true
  load_balancer_type               = "network"
  ip_address_type                  = "ipv4"
  subnets                          = module.vpc.private_app_subnet_ids
  security_groups                  = [aws_security_group.core_nlb.id]
  enable_cross_zone_load_balancing = false
  dns_record_client_routing_policy = "any_availability_zone"

  tags = { Name = "arclight-${local.internal_tls_env}-int-core" }
}

resource "aws_lb_target_group" "core_internal_8000" {
  name                              = "${local.internal_tls_env}-int-core-8000"
  port                              = 8000
  protocol                          = "TCP"
  target_type                       = "ip"
  vpc_id                            = module.vpc.vpc_id
  preserve_client_ip                = "true"
  proxy_protocol_v2                 = false
  deregistration_delay              = 30
  load_balancing_cross_zone_enabled = "true"

  health_check {
    protocol            = "HTTP"
    port                = "traffic-port"
    path                = "/ready"
    matcher             = "200"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = { Name = "${local.internal_tls_env}-int-core-8000" }
}

resource "aws_lb_listener" "core_internal_443" {
  load_balancer_arn = aws_lb.core_internal.arn
  port              = 443
  protocol          = "TLS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = data.aws_acm_certificate.staging.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.core_internal_8000.arn
  }
}

# One private zone per name, so the name resolves to the NLB inside the VPC and never to
# Cloudflare, without shadowing the public *.staging names.
resource "aws_route53_zone" "core_internal" {
  name    = local.core_internal_fqdn
  comment = "Core's internal TLS name (D-077); resolves to the internal NLB inside the VPC"

  vpc {
    vpc_id = module.vpc.vpc_id
  }

  tags = { Name = local.core_internal_fqdn }
}

resource "aws_route53_record" "core_internal" {
  zone_id = aws_route53_zone.core_internal.zone_id
  name    = local.core_internal_fqdn
  type    = "A"

  alias {
    name                   = aws_lb.core_internal.dns_name
    zone_id                = aws_lb.core_internal.zone_id
    evaluate_target_health = false
  }
}

# Pages when Core has no healthy target behind the internal NLB. Missing data is breaching:
# AWS reports the metric only while targets are registered.
resource "aws_cloudwatch_metric_alarm" "core_internal_healthy" {
  alarm_name          = "arclight-${var.environment}-core-internal-healthy-hosts"
  alarm_description   = "Core has no healthy target behind its internal NLB (D-077)"
  namespace           = "AWS/NetworkELB"
  metric_name         = "HealthyHostCount"
  statistic           = "Maximum"
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  treat_missing_data  = "breaching"
  alarm_actions       = [module.observability.alarm_topic_arn]
  ok_actions          = [module.observability.alarm_topic_arn]

  dimensions = {
    LoadBalancer = aws_lb.core_internal.arn_suffix
    TargetGroup  = aws_lb_target_group.core_internal_8000.arn_suffix
  }
}

################################################################################
# Acceptance probe (spec: "Probe family arclight-probe-staging")
#
# Terraform owns only the execution role and the log group. The task definition is
# registered by hand for each run (scripts/internal-tls-probe/), pinned to Core's live
# image digest, and deregistered afterwards. It carries no secrets and has no task role.
################################################################################

resource "aws_cloudwatch_log_group" "probe" {
  name              = "/arclight/${var.environment}/probe"
  retention_in_days = 30

  tags = { Name = "/arclight/${var.environment}/probe" }
}

resource "aws_iam_role" "probe_exec" {
  name               = "arclight-ecs-exec-probe-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json

  tags = { Name = "arclight-ecs-exec-probe-${var.environment}" }
}

resource "aws_iam_role_policy" "probe_exec" {
  name = "probe-exec"
  role = aws_iam_role.probe_exec.id

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
        Sid    = "ECRPullCore"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
        ]
        Resource = [module.ecr.repository_arns["arclight/core"]]
      },
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["${aws_cloudwatch_log_group.probe.arn}:*"]
      },
    ]
  })
}
