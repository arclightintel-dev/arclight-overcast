# Instance target on the prod ALB. The prod ALB module's own target groups are type "ip"
# (Fargate); this one is "instance" because the app runs on host networking. The health
# check needs Backstage's /health exemption from its Host check (spec H3): until that
# lands the target is unhealthy by design.
resource "aws_lb_target_group" "host" {
  name                 = local.name
  port                 = 8430
  protocol             = "HTTP"
  target_type          = "instance"
  vpc_id               = data.aws_vpc.prod.id
  deregistration_delay = 30

  health_check {
    path                = "/health"
    port                = "traffic-port"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group_attachment" "host" {
  target_group_arn = aws_lb_target_group.host.arn
  target_id        = aws_instance.host.id
  port             = 8430
}

resource "aws_lb_listener_rule" "host" {
  listener_arn = data.aws_lb_listener.https.arn
  priority     = var.listener_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.host.arn
  }

  condition {
    host_header {
      values = [local.public_host]
    }
  }
}
