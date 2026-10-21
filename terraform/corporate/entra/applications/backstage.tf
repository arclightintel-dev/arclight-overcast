# Backstage (prototype platform application, O-012): confidential Web client
# with PKCE S256, direct Entra relying party. App roles are declared here and
# assigned to users by the administrator; Backstage maps the `roles` claim on
# its side. The client secret is created by the administrator and delivered to
# the Backstage Secrets Manager shell, never through Terraform.

locals {
  backstage_roles = {
    ops = {
      display_name = "Ops"
      description  = "Operations: day-to-day analyst work."
    }
    operator = {
      display_name = "Operator"
      description  = "Operator: runs collection operations."
    }
    dev = {
      display_name = "Dev"
      description  = "Developer: diagnostics and configuration."
    }
    admin = {
      display_name = "Admin"
      description  = "Administrator: user and settings management."
    }
  }
}

resource "azuread_application_registration" "backstage" {
  display_name     = "arclight-backstage"
  description      = "Backstage analyst application sign-in through Microsoft Entra ID. Maintained by Arclight Overcast."
  sign_in_audience = "AzureADMyOrg"

  depends_on = [data.azuread_client_config.current]

  lifecycle {
    prevent_destroy = true
  }
}

resource "azuread_application_redirect_uris" "backstage_web" {
  application_id = azuread_application_registration.backstage.id
  type           = "Web"
  redirect_uris  = ["https://backstage.arclight-complex.net/auth/callback"]
}

# Backstage reads `email` (and the standard `name`) from the ID token.
resource "azuread_application_optional_claims" "backstage" {
  application_id = azuread_application_registration.backstage.id

  id_token {
    name = "email"
  }
}

resource "azuread_application_app_role" "backstage" {
  for_each = local.backstage_roles

  application_id       = azuread_application_registration.backstage.id
  role_id              = uuidv5("url", "https://backstage.arclight-complex.net/app-roles/${each.key}")
  allowed_member_types = ["User"]
  display_name         = each.value.display_name
  description          = each.value.description
  value                = each.key
}

resource "azuread_application_api_access" "backstage_graph" {
  application_id = azuread_application_registration.backstage.id
  api_client_id  = data.azuread_service_principal.microsoft_graph.client_id
  scope_ids      = local.graph_oidc_scope_ids
}

# Only users assigned an app role may sign in (the administrator assigns the
# owner to `admin` first, then the analysts). Owners are reconciled by the
# provider: declare exactly the real set.
resource "azuread_service_principal" "backstage" {
  client_id                    = azuread_application_registration.backstage.client_id
  owners                       = [local.management_sp_object_id]
  app_role_assignment_required = true

  lifecycle {
    prevent_destroy = true
  }
}
