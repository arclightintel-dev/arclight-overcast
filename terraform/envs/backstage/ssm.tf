# Non-secret values the host reads at run time. Changing one never replaces the instance
# (user-data carries only per-instance constants); the host picks it up on the next
# firewall run, busy publication or deploy.
locals {
  parameters = {
    "ecr-registry"       = local.ecr_registry
    "alb-subnet-cidrs"   = join(",", local.alb_subnet_cidrs)
    "litestream-bucket"  = aws_s3_bucket.this["litestream"].bucket
    "deploy-bucket"      = aws_s3_bucket.this["deploy"].bucket
    "oidc-client-id"     = var.backstage_oidc_client_id
    "public-host"        = local.public_host
    "proxy-endpoints"    = join(" ", var.proxy_endpoints)
    "entra-cidrs"        = join(" ", var.entra_cidrs)
    "anthropic-cidrs"    = join(" ", var.anthropic_cidrs)
    "busy-grace-seconds" = tostring(var.busy_grace_seconds)
    "tg-arn-suffix"      = aws_lb_target_group.host.arn_suffix
    "alb-arn-suffix"     = data.aws_lb.prod.arn_suffix
  }
}

resource "aws_ssm_parameter" "this" {
  for_each = local.parameters

  name  = "${local.ssm_prefix}/${each.key}"
  type  = "String"
  value = each.value
}
