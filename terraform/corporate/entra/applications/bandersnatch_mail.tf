# Bandersnatch (staging): daemon client for outbound mail. It sends as one
# shared mailbox through Microsoft Graph sendMail with the client-credentials
# flow. There is no sign-in: no redirect URIs, no ID-token claims, no app
# roles. The client secret is created by the administrator and delivered to the
# Secrets Manager shell arclight/staging/bandersnatch/graph-client-secret,
# never through Terraform. The sending mailbox is never named in this
# repository.
#
# There is deliberately no Microsoft Graph permission on this registration.
# Sending is authorised by an Exchange Online RBAC for Applications assignment
# (the "Application Mail.Send" role) scoped to the one sending mailbox, made by
# the administrator. Entra grants and Exchange assignments are additive, so a
# tenant-wide Mail.Send grant would widen this client to every mailbox; with
# nothing declared here there is nothing to consent to.

resource "azuread_application_registration" "bandersnatch_mail" {
  display_name     = "arclight-bandersnatch-mail"
  description      = "Bandersnatch staging outbound mail through Microsoft Graph. Maintained by Arclight Overcast."
  sign_in_audience = "AzureADMyOrg"

  depends_on = [data.azuread_client_config.current]

  lifecycle {
    prevent_destroy = true
  }
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
