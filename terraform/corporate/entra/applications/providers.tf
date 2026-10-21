locals {
  tenant_id               = "27564b9c-b516-4bc4-9aa5-5692a38a1116"
  management_client_id    = "0027ad40-c6ab-4166-b010-6b9d378b1772"
  management_sp_object_id = "4c5c3d64-2425-494f-b3f9-fec7253e842a"
}

# Automation root. Certificate authentication only: the PFX path and its
# process-only password arrive through ARM_CLIENT_CERTIFICATE_PATH and
# ARM_CLIENT_CERTIFICATE_PASSWORD (docs/runbooks/manage-entra.md). Tenant and
# client are pinned here so the environment cannot point this root at another
# identity. A client ID is a public identifier, not a credential.
provider "azuread" {
  tenant_id = local.tenant_id
  client_id = local.management_client_id
  use_cli   = false
  use_msi   = false
  use_oidc  = false
}

data "azuread_client_config" "current" {
  lifecycle {
    postcondition {
      condition     = self.tenant_id == local.tenant_id
      error_message = "Applications root must authenticate to the Arclight corporate tenant."
    }
    postcondition {
      condition     = self.object_id == local.management_sp_object_id
      error_message = "Applications root must run as the arclight-overcast-entra-management service principal through certificate authentication, never as a human administrator."
    }
  }
}

data "azuread_application_published_app_ids" "well_known" {}

data "azuread_service_principal" "microsoft_graph" {
  client_id = data.azuread_application_published_app_ids.well_known.result.MicrosoftGraph
}

locals {
  # The three OpenID Connect scopes both applications request. Delegated
  # permissions on Microsoft Graph; admin consent is a separate administrator
  # step outside this state.
  graph_oidc_scope_ids = [
    data.azuread_service_principal.microsoft_graph.oauth2_permission_scope_ids["openid"],
    data.azuread_service_principal.microsoft_graph.oauth2_permission_scope_ids["email"],
    data.azuread_service_principal.microsoft_graph.oauth2_permission_scope_ids["profile"],
  ]
}
