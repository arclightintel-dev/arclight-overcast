# Host security group: inbound only from the prod ALB; outbound only to the proxies, the
# AWS endpoints, Entra sign-in and the Anthropic API (O-012 item 2). The VPC resolver,
# the Amazon Time Sync Service and instance metadata are not filtered by security groups.
# All rules are standalone resources (never inline), so adding a proxy changes one rule.

resource "aws_security_group" "host" {
  name        = "${local.name}-host"
  description = "Backstage host: ALB in; proxies, AWS endpoints, Entra and Anthropic out"
  vpc_id      = data.aws_vpc.prod.id

  tags = { Name = "${local.name}-host" }
}

resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  security_group_id            = aws_security_group.host.id
  referenced_security_group_id = data.aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 8430
  to_port                      = 8430
  description                  = "Backstage app from the prod ALB"
}

resource "aws_vpc_security_group_egress_rule" "proxy" {
  for_each = toset(var.proxy_endpoints)

  security_group_id = aws_security_group.host.id
  cidr_ipv4         = "${split(":", each.value)[0]}/32"
  ip_protocol       = "tcp"
  from_port         = tonumber(split(":", each.value)[1])
  to_port           = tonumber(split(":", each.value)[1])
  description       = "Source proxy ${each.value}"
}

resource "aws_vpc_security_group_egress_rule" "s3" {
  security_group_id = aws_security_group.host.id
  prefix_list_id    = data.aws_vpc_endpoint.s3.prefix_list_id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "S3 gateway endpoint (ECR layers, Litestream, bundles, migration)"
}

resource "aws_vpc_security_group_egress_rule" "vpc_endpoints" {
  security_group_id            = aws_security_group.host.id
  referenced_security_group_id = data.aws_security_group.vpce.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "Interface endpoints (ECR, Logs, Secrets Manager, SSM, CloudWatch)"
}

resource "aws_vpc_security_group_egress_rule" "entra" {
  for_each = toset(var.entra_cidrs)

  security_group_id = aws_security_group.host.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "Entra sign-in (login.microsoftonline.com)"
}

resource "aws_vpc_security_group_egress_rule" "anthropic" {
  for_each = toset(var.anthropic_cidrs)

  security_group_id = aws_security_group.host.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "Anthropic API (Engine categorization)"
}

# OW-7: package installation. True only on an apply that creates or replaces the instance.
resource "aws_vpc_security_group_egress_rule" "maintenance" {
  for_each = var.maintenance_egress ? toset(["80", "443"]) : toset([])

  security_group_id = aws_security_group.host.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  description       = "Maintenance window: packages and downloads"
}

# Attached to the prod ALB's security group, which has no inline rules, so the prod root
# never removes it.
resource "aws_vpc_security_group_egress_rule" "alb_to_host" {
  security_group_id            = data.aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.host.id
  ip_protocol                  = "tcp"
  from_port                    = 8430
  to_port                      = 8430
  description                  = "Prod ALB to the Backstage host"
}
