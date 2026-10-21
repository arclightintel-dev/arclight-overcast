# Arclight Core staging: Microsoft identity broker (confidential Web client,
# authorization code, no PKCE). Core binds its broker row to this client ID and
# the tenant-specific issuer through its own broker-bind command; the client
# secret is created by the administrator and delivered to the Secrets Manager
# shell arclight/staging/core/oidc-microsoft-client-secret, never through
# Terraform.

resource "azuread_application_registration" "core_staging" {
  display_name     = "arclight-core-staging"
  description      = "Arclight Core staging operator sign-in through Microsoft Entra ID. Maintained by Arclight Overcast."
  sign_in_audience = "AzureADMyOrg"

  depends_on = [data.azuread_client_config.current]

  lifecycle {
    prevent_destroy = true
  }
}

resource "azuread_application_redirect_uris" "core_staging_web" {
  application_id = azuread_application_registration.core_staging.id
  type           = "Web"
  redirect_uris  = ["https://core.staging.arclight-complex.net/auth/callback"]
}

# Core requires `email` in the ID token (403 without it) and reads `amr` to
# establish direct MFA verification (accepted value: mfa). Both are optional
# claims for an OIDC v2.0 application.
resource "azuread_application_optional_claims" "core_staging" {
  application_id = azuread_application_registration.core_staging.id

  id_token {
    name = "email"
  }

  id_token {
    name = "amr"
  }
}

resource "azuread_application_api_access" "core_staging_graph" {
  application_id = azuread_application_registration.core_staging.id
  api_client_id  = data.azuread_service_principal.microsoft_graph.client_id
  scope_ids      = local.graph_oidc_scope_ids
}

# Owners are reconciled by the provider: declare exactly the real set. The
# management identity cannot add owners it does not already hold.
resource "azuread_service_principal" "core_staging" {
  client_id                    = azuread_application_registration.core_staging.client_id
  owners                       = [local.management_sp_object_id]
  app_role_assignment_required = false

  lifecycle {
    prevent_destroy = true
  }
}
