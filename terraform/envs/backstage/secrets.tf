# Secret shells only (INV-004): values are written by the owner with put-secret-value from a
# process variable (no trailing newline), never through Terraform. The host renders them at
# start and deploy (host/backstage-render-secrets.sh).
locals {
  secrets = {
    "cookie-key"                = "Backstage PODBAY_COOKIE_KEY: the existing 32-byte base64 key, copied from the PC (never regenerated; it decrypts proxy passwords and site cookies)"
    "oidc-client-secret"        = "Backstage PODBAY_OIDC_CLIENT_SECRET for the arclight-backstage Entra registration"
    "anthropic-api-key"         = "Backstage Engine PODBAY_ANTHROPIC_API_KEY (Engine only)"
    "categorization-capability" = "Backstage categorization capability token shared by the app and the Engine (32 or more characters)"
  }
}

resource "aws_secretsmanager_secret" "this" {
  for_each = local.secrets

  name        = "arclight/backstage/${var.environment}/${each.key}"
  description = each.value
}
