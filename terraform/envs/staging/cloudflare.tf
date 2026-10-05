################################################################################
# Cloudflare — Account 1 ("Arclightintel@gmail.com's Account")
#
# Adopts the EXISTING, manually-created Cloudflare config for
# arclight-complex.net by import — zero behavior change on first apply.
#
# Auth: provider reads CLOUDFLARE_API_TOKEN from the environment.
#       Token is never stored in this repo or in Terraform state.
#       Local token file (out of repo): %USERPROFILE%\.arclight\cloudflare_api_token
#
# Single (default) provider: Terraform manages only Account 1 resources.
# The Account 2 zones (arclightlabs.io, arclightintel.com, nerfherder.io)
# are being consolidated onto Account 1 out-of-band; they join this config
# AFTER they move, so no provider alias is needed.
#
# IDs below are Cloudflare identifiers (not secrets) — safe in code.
################################################################################

provider "cloudflare" {
  # api_token sourced from CLOUDFLARE_API_TOKEN env var
}

locals {
  cloudflare_account_id = "76088d2d8df3d24e8808c3d26aeea51e"
  cf_zone_arclight_net  = "0f8d0f55f4873252390ed99f611f3f1a"

  # ALB hostname the staging service records point at (matches module.alb output)
  staging_alb_hostname = "arclight-staging-2144643595.us-east-1.elb.amazonaws.com"

  # Emails allowed through the staging Access gate
  access_allowed_emails = ["jkcostie@gmail.com"]
}

################################################################################
# DNS — staging service records (CNAME -> ALB, proxied)
#
# NOTE: the two ACM validation CNAMEs in this zone are intentionally NOT
# managed here — AWS ACM owns their lifecycle (renewal), and Terraform
# fighting that would risk cert issuance.
################################################################################

resource "cloudflare_record" "core_staging" {
  zone_id = local.cf_zone_arclight_net
  name    = "core.staging"
  type    = "CNAME"
  content = local.staging_alb_hostname
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "podbay_staging" {
  zone_id = local.cf_zone_arclight_net
  name    = "podbay.staging"
  type    = "CNAME"
  content = local.staging_alb_hostname
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "shuttleforge_staging" {
  zone_id = local.cf_zone_arclight_net
  name    = "shuttleforge.staging"
  type    = "CNAME"
  content = local.staging_alb_hostname
  proxied = true
  ttl     = 1
}

################################################################################
# Cloudflare Access — staging gate (D-059 §9)
#
# Account-scoped self-hosted application protecting *.staging with a single
# allow policy. IdP is the built-in one-time PIN (not a managed resource).
################################################################################

resource "cloudflare_zero_trust_access_application" "staging_gate" {
  account_id                = local.cloudflare_account_id
  name                      = "*"
  domain                    = "*.staging.arclight-complex.net"
  type                      = "self_hosted"
  session_duration          = "24h"
  auto_redirect_to_identity = false
}

# NOTE: the "Team" allow policy (email=jkcostie@gmail.com, precedence 1) is
# live and unaffected — it stays attached to the app. It is intentionally NOT
# managed here yet: provider v4.52 moved Access policies to the "reusable"
# model (standalone policy referenced via the app's `policies` list), and the
# correct HCL + import ID for the existing app-attached policy is best emitted
# by cf-terraforming rather than hand-written. Follow-up change adopts it.
#   Live policy id: f51a0cb1-8e90-4aa9-91bc-657a954531e1

################################################################################
# Zone settings — DEFERRED to a separate, reviewed hardening change.
#
# cloudflare_zone_settings_override does NOT support `import`, and folding it
# into this clean adoption muddied the plan. It lands as its own change that
# hardens the two gaps found in discovery:
#   always_use_https : off  -> on
#   min_tls_version  : 1.0  -> 1.2
# Current live values (reference): ssl=strict, tls_1_3=on,
# automatic_https_rewrites=on, opportunistic_encryption=on,
# security_level=medium, always_use_https=off, min_tls_version=1.0.
################################################################################

################################################################################
# Import blocks — adopt existing resources (Terraform 1.5+).
# Applied at `terraform apply`; `terraform plan` previews them without
# mutating state. After a clean adopt, these blocks can be removed.
################################################################################

import {
  to = cloudflare_record.core_staging
  id = "0f8d0f55f4873252390ed99f611f3f1a/d01b70eda5c963d2f5ba83c1f02e5440"
}

import {
  to = cloudflare_record.podbay_staging
  id = "0f8d0f55f4873252390ed99f611f3f1a/df91cce6ded2195e532f098d59ecc711"
}

import {
  to = cloudflare_record.shuttleforge_staging
  id = "0f8d0f55f4873252390ed99f611f3f1a/676641b279617d26301aa261ac82e53c"
}

import {
  to = cloudflare_zero_trust_access_application.staging_gate
  id = "76088d2d8df3d24e8808c3d26aeea51e/a378347b-e740-4d07-877b-892268ed395b"
}

################################################################################
# Outputs
################################################################################

output "cloudflare_staging_gate_aud" {
  description = "Access application AUD tag for the staging gate"
  value       = cloudflare_zero_trust_access_application.staging_gate.aud
}
