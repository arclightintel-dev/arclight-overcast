# Bandersnatch (staging): daemon client for outbound mail. It sends as one
# shared mailbox through Microsoft Graph sendMail with the client-credentials
# flow. There is no sign-in: no redirect URIs, no ID-token claims, no app
# roles. The client secret is created by the administrator and delivered to the
# Secrets Manager shell arclight/staging/bandersnatch/graph-client-secret,
# never through Terraform. The sending mailbox is never named in this
# repository.

locals {
  # Microsoft Graph application permission (app role) Mail.Send. Well-known id;
  # confirm it at plan time against the Graph service principal's appRoles
  # before the first apply.
  graph_mail_send_role_id = "b633e1c5-b582-4048-a93e-9f11b44c7e96"
}

resource "azuread_application_registration" "bandersnatch_mail" {
  display_name     = "arclight-bandersnatch-mail"
  description      = "Bandersnatch staging outbound mail through Microsoft Graph. Maintained by Arclight Overcast."
  sign_in_audience = "AzureADMyOrg"

  depends_on = [data.azuread_client_config.current]

  lifecycle {
    prevent_destroy = true
  }
}

# Declaration only: declaring a permission is not consent. Tenant-wide admin
# consent for Mail.Send would let this client send as every mailbox, so the
# administrator does NOT grant it. Sending is authorised in Exchange Online
# instead (RBAC for Applications: the "Application Mail.Send" role assigned to
# this service principal over a management scope holding only the sending
# mailbox). An Entra grant and an Exchange assignment are additive, so a later
# consent here would silently remove the mailbox restriction.
resource "azuread_application_api_access" "bandersnatch_mail_graph" {
  application_id = azuread_application_registration.bandersnatch_mail.id
  api_client_id  = data.azuread_service_principal.microsoft_graph.client_id
  role_ids       = [local.graph_mail_send_role_id]
}

# Owners are reconciled by the provider: declare exactly the real set. The
# management identity cannot add owners it does not already hold.
resource "azuread_service_principal" "bandersnatch_mail" {
  client_id                    = azuread_application_registration.bandersnatch_mail.client_id
  owners                       = [local.management_sp_object_id]
  app_role_assignment_required = false

  lifecycle {
    prevent_destroy = true
  }
}
