resource "azuread_application_registration" "management" {
  display_name     = "arclight-overcast-entra-management"
  description      = "Corporate application management maintained by Arclight Overcast."
  sign_in_audience = "AzureADMyOrg"

  depends_on = [data.azuread_client_config.current]

  lifecycle {
    prevent_destroy = true
  }
}

resource "azuread_application_owner" "administrator" {
  application_id  = azuread_application_registration.management.id
  owner_object_id = var.admin_object_id
}

resource "azuread_service_principal" "management" {
  client_id = azuread_application_registration.management.client_id
  owners    = [var.admin_object_id]

  lifecycle {
    prevent_destroy = true
  }
}

resource "azuread_application_certificate" "management" {
  application_id = azuread_application_registration.management.id
  type           = "AsymmetricX509Cert"
  encoding       = "pem"
  value          = var.certificate_pem
  start_date     = var.certificate_start_date
  end_date       = var.certificate_end_date

  lifecycle {
    create_before_destroy = true
  }
}

# This declares the requested permission; it does not grant admin consent.
# Consent remains a separate administrator operation outside this state.
resource "azuread_application_api_access" "microsoft_graph" {
  application_id = azuread_application_registration.management.id
  api_client_id  = data.azuread_service_principal.microsoft_graph.client_id
  role_ids = [
    data.azuread_service_principal.microsoft_graph.app_role_ids["Application.ReadWrite.OwnedBy"]
  ]
}
