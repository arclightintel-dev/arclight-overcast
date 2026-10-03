output "tenant_id" {
  description = "Corporate Microsoft Entra tenant."
  value       = local.tenant_id
}

output "application_client_id" {
  description = "Client ID for the certificate-authenticated management connection."
  value       = azuread_application_registration.management.client_id
}

output "application_object_id" {
  description = "Directory object ID of the management application registration."
  value       = azuread_application_registration.management.object_id
}

output "service_principal_object_id" {
  description = "Directory object ID of the management enterprise application."
  value       = azuread_service_principal.management.object_id
}

output "requested_graph_application_permission" {
  description = "Requested Graph application permission. This output is not proof of admin consent."
  value       = "Application.ReadWrite.OwnedBy"
}
