# Bandersnatch (staging): the admin interface Backstage calls (O-020). An API
# only: no sign-in, no redirect, no secret. One app role, bandersnatch.admin,
# assignable to applications only. arclight-backstage requests it; the
# administrator grants admin consent once, which assigns the role to Backstage's
# service principal and to nothing else. Assignment is required, so Entra issues
# a token for this API to no other client. The interface itself also checks the
# caller's id (azp) and refuses tokens issued for a signed-in user.

resource "azuread_application_registration" "bandersnatch_admin" {
  display_name                   = "arclight-bandersnatch-admin"
  description                    = "Bandersnatch staging admin interface, called by Backstage with app-only tokens. Maintained by Arclight Overcast."
  sign_in_audience               = "AzureADMyOrg"
  requested_access_token_version = 2

  depends_on = [data.azuread_client_config.current]

  lifecycle {
    prevent_destroy = true
  }
}

# The scope Backstage asks for: api://<client id>/.default.
resource "azuread_application_identifier_uri" "bandersnatch_admin" {
  application_id = azuread_application_registration.bandersnatch_admin.id
  identifier_uri = "api://${azuread_application_registration.bandersnatch_admin.client_id}"
}

resource "azuread_application_app_role" "bandersnatch_admin" {
  application_id       = azuread_application_registration.bandersnatch_admin.id
  role_id              = uuidv5("url", "https://arclight-complex.net/bandersnatch/admin/app-roles/bandersnatch.admin")
  allowed_member_types = ["Application"]
  display_name         = "Bandersnatch administration"
  description          = "Calls the Bandersnatch admin interface for the platform's administrators (Backstage only)."
  value                = "bandersnatch.admin"
}

resource "azuread_service_principal" "bandersnatch_admin" {
  client_id                    = azuread_application_registration.bandersnatch_admin.client_id
  owners                       = [local.management_sp_object_id]
  app_role_assignment_required = true

  lifecycle {
    prevent_destroy = true
  }
}

# Backstage requests the role (an application permission). Requesting grants
# nothing: the administrator's admin consent is the assignment.
resource "azuread_application_api_access" "backstage_bandersnatch_admin" {
  application_id = azuread_application_registration.backstage.id
  api_client_id  = azuread_application_registration.bandersnatch_admin.client_id
  role_ids       = [azuread_application_app_role.bandersnatch_admin.role_id]
}

output "bandersnatch_admin_client_id" {
  description = "Application (client) ID of the Bandersnatch admin interface: the token audience (staging tfvars bandersnatch_admin_audience; Backstage's scope api://<id>/.default)."
  value       = azuread_application_registration.bandersnatch_admin.client_id
}

output "bandersnatch_admin_service_principal_object_id" {
  description = "Directory object ID of the admin interface's enterprise application (resourceId of Backstage's assignment)."
  value       = azuread_service_principal.bandersnatch_admin.object_id
}

output "bandersnatch_admin_role_id" {
  description = "App role ID of bandersnatch.admin (appRoleId of Backstage's assignment)."
  value       = azuread_application_app_role.bandersnatch_admin.role_id
}
