locals {
  tenant_id = "27564b9c-b516-4bc4-9aa5-5692a38a1116"
}

# Bootstrap belongs to the human administrator. Clear ARM_CLIENT_* credential
# variables before running: provider environment credentials can precede CLI auth.
provider "azuread" {
  tenant_id = local.tenant_id
  use_cli   = true
  use_msi   = false
  use_oidc  = false
}

data "azuread_client_config" "current" {
  lifecycle {
    postcondition {
      condition     = self.tenant_id == local.tenant_id
      error_message = "Bootstrap must authenticate to the Arclight corporate tenant."
    }
    postcondition {
      condition     = self.object_id == var.admin_object_id
      error_message = "Bootstrap must run as the independently verified human administrator. Clear ARM_CLIENT_* credentials and use that administrator's Azure CLI login."
    }
  }
}

data "azuread_application_published_app_ids" "well_known" {}

data "azuread_service_principal" "microsoft_graph" {
  client_id = data.azuread_application_published_app_ids.well_known.result.MicrosoftGraph
}
