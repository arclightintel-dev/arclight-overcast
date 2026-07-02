################################################################################
# Security Group
################################################################################

resource "aws_security_group" "alb" {
  name_prefix = "arclight-${var.environment}-alb-"
  description = "ALB public access"
  vpc_id      = var.vpc_id

  tags = { Name = "arclight-${var.environment}-alb" }
}

resource "aws_security_group_rule" "alb_http_ingress" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  security_group_id = aws_security_group.alb.id
  cidr_blocks       = var.allowed_ingress_cidrs
  description       = "HTTP"
}

resource "aws_security_group_rule" "alb_https_ingress" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.alb.id
  cidr_blocks       = var.allowed_ingress_cidrs
  description       = "HTTPS"
}

resource "aws_security_group_rule" "alb_http_ingress_ipv6" {
  count = length(var.allowed_ingress_ipv6_cidrs) > 0 ? 1 : 0

  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  security_group_id = aws_security_group.alb.id
  ipv6_cidr_blocks  = var.allowed_ingress_ipv6_cidrs
  description       = "HTTP IPv6"
}

resource "aws_security_group_rule" "alb_https_ingress_ipv6" {
  count = length(var.allowed_ingress_ipv6_cidrs) > 0 ? 1 : 0

  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.alb.id
  ipv6_cidr_blocks  = var.allowed_ingress_ipv6_cidrs
  description       = "HTTPS IPv6"
}

resource "aws_security_group_rule" "alb_to_service" {
  for_each = var.services

  type                     = "egress"
  from_port                = each.value.port
  to_port                  = each.value.port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.alb.id
  source_security_group_id = var.service_security_group_ids[each.key]
}

################################################################################
# ALB
################################################################################

resource "aws_lb" "this" {
  name               = "arclight-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids
  idle_timeout       = 3600

  tags = { Name = "arclight-${var.environment}" }
}

################################################################################
# Listeners
################################################################################

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

################################################################################
# Target Groups
################################################################################

resource "aws_lb_target_group" "this" {
  for_each = var.services

  name        = "arclight-${var.environment}-${each.key}"
  port        = each.value.port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = each.value.health_check_path
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = { Name = "arclight-${var.environment}-${each.key}" }
}

################################################################################
# Listener Rules (host-based routing)
################################################################################

resource "aws_lb_listener_rule" "host_routing" {
  for_each = var.services

  listener_arn = aws_lb_listener.https.arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.key].arn
  }

  condition {
    host_header {
      values = ["${each.key}.${var.domain_name}"]
    }
  }
}
