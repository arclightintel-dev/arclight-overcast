# Bandersnatch admin interface (O-020; the application's docs/admin-api.md). Backstage's
# Settings section calls it. The path stays inside AWS: this interface endpoint, PrivateLink, an
# internal NLB in staging, the Bandersnatch task's port 8082. The host's egress gains exactly
# one rule, 443 to this endpoint's group; nothing reaches the internet or Cloudflare (D-078 §5:
# source traffic never leaves AWS directly, so no general egress is opened for this).
#
# One endpoint, in the host's subnet: the host is a single instance, and an endpoint in another
# zone would still be reachable. The name resolves only inside the prod VPC, through a private
# zone for that one name, as for Core's internal name in staging; the public *.staging names are
# not shadowed. Created only once the staging root has published the service.

locals {
  bsn_admin      = var.bandersnatch_admin_service_name != ""
  bsn_admin_fqdn = "bandersnatch-admin.staging.${var.domain_name}"
}

resource "aws_security_group" "bsn_admin_endpoint" {
  count = local.bsn_admin ? 1 : 0

  name        = "${local.name}-bsn-admin-endpoint"
  description = "Bandersnatch admin interface endpoint: the Backstage host only"
  vpc_id      = data.aws_vpc.prod.id

  tags = { Name = "${local.name}-bsn-admin-endpoint" }
}

resource "aws_vpc_security_group_ingress_rule" "bsn_admin_endpoint_from_host" {
  count = local.bsn_admin ? 1 : 0

  security_group_id            = aws_security_group.bsn_admin_endpoint[0].id
  referenced_security_group_id = aws_security_group.host.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "Backstage host to the Bandersnatch admin interface"
}

# The Portal's containers share the host's group but not this path: the host firewall lets their
# bridge reach only the source proxies (host/backstage-firewall.sh).
resource "aws_vpc_security_group_egress_rule" "host_to_bsn_admin" {
  count = local.bsn_admin ? 1 : 0

  security_group_id            = aws_security_group.host.id
  referenced_security_group_id = aws_security_group.bsn_admin_endpoint[0].id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "Bandersnatch admin interface (PrivateLink endpoint)"
}

resource "aws_vpc_endpoint" "bsn_admin" {
  count = local.bsn_admin ? 1 : 0

  vpc_id              = data.aws_vpc.prod.id
  service_name        = var.bandersnatch_admin_service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [data.aws_subnet.host.id]
  security_group_ids  = [aws_security_group.bsn_admin_endpoint[0].id]
  private_dns_enabled = false
  ip_address_type     = "ipv4"

  tags = { Name = "${local.name}-bsn-admin" }
}

resource "aws_route53_zone" "bsn_admin" {
  count = local.bsn_admin ? 1 : 0

  name    = local.bsn_admin_fqdn
  comment = "Bandersnatch admin interface (O-020); resolves to the PrivateLink endpoint inside the prod VPC only"

  vpc {
    vpc_id = data.aws_vpc.prod.id
  }

  tags = { Name = local.bsn_admin_fqdn }
}

resource "aws_route53_record" "bsn_admin" {
  count = local.bsn_admin ? 1 : 0

  zone_id = aws_route53_zone.bsn_admin[0].zone_id
  name    = local.bsn_admin_fqdn
  type    = "A"

  alias {
    name                   = aws_vpc_endpoint.bsn_admin[0].dns_entry[0].dns_name
    zone_id                = aws_vpc_endpoint.bsn_admin[0].dns_entry[0].hosted_zone_id
    evaluate_target_health = false
  }
}
