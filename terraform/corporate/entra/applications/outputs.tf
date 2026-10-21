output "tenant_id" {
  description = "Corporate Microsoft Entra tenant."
  value       = local.tenant_id
}

output "core_staging_issuer" {
  description = "Tenant-bound OIDC issuer for Core's broker (broker-bind --issuer-url)."
  value       = "https://login.microsoftonline.com/${local.tenant_id}/v2.0"
}

output "core_staging_client_id" {
  description = "Application (client) ID for Core staging (broker-bind --client-id)."
  value       = azuread_application_registration.core_staging.client_id
}

output "core_staging_application_object_id" {
  description = "Directory object ID of the Core staging application registration."
  value       = azuread_application_registration.core_staging.object_id
}

output "core_staging_service_principal_object_id" {
  description = "Directory object ID of the Core staging enterprise application."
  value       = azuread_service_principal.core_staging.object_id
}

output "backstage_client_id" {
  description = "Application (client) ID for Backstage (PODBAY_OIDC_CLIENT_ID)."
  value       = azuread_application_registration.backstage.client_id
}

output "backstage_application_object_id" {
  description = "Directory object ID of the Backstage application registration."
  value       = azuread_application_registration.backstage.object_id
}

output "backstage_service_principal_object_id" {
  description = "Directory object ID of the Backstage enterprise application (resourceId for app-role assignments)."
  value       = azuread_service_principal.backstage.object_id
}

output "backstage_app_role_ids" {
  description = "Backstage app role IDs by role value (appRoleId for app-role assignments)."
  value       = { for key, role in azuread_application_app_role.backstage : key => role.role_id }
}
