# Every provider operation is mocked. These tests prove the declared shapes and
# the caller boundary, not Microsoft consent, sign-in, or the certificate.
mock_provider "azuread" {
  mock_data "azuread_client_config" {
    defaults = {
      tenant_id = "27564b9c-b516-4bc4-9aa5-5692a38a1116"
      object_id = "4c5c3d64-2425-494f-b3f9-fec7253e842a"
      client_id = "0027ad40-c6ab-4166-b010-6b9d378b1772"
    }
  }

  mock_data "azuread_application_published_app_ids" {
    defaults = {
      result = {
        MicrosoftGraph = "00000003-0000-0000-c000-000000000000"
      }
    }
  }

  mock_data "azuread_service_principal" {
    defaults = {
      client_id = "00000003-0000-0000-c000-000000000000"
      oauth2_permission_scope_ids = {
        "openid"             = "aaaaaaaa-0000-4000-8000-000000000001"
        "email"              = "aaaaaaaa-0000-4000-8000-000000000002"
        "profile"            = "aaaaaaaa-0000-4000-8000-000000000003"
        "User.Read"          = "aaaaaaaa-0000-4000-8000-000000000004"
        "Directory.Read.All" = "aaaaaaaa-0000-4000-8000-000000000005"
      }
    }
  }
}

run "core_staging_declaration" {
  command = plan

  assert {
    condition     = azuread_application_registration.core_staging.sign_in_audience == "AzureADMyOrg"
    error_message = "Core staging must remain a single-tenant application."
  }

  assert {
    condition     = azuread_application_redirect_uris.core_staging_web.redirect_uris == toset(["https://core.staging.arclight-complex.net/auth/callback"])
    error_message = "Core staging must register exactly CORE_BASE_URL + /auth/callback."
  }

  assert {
    condition     = [for claim in azuread_application_optional_claims.core_staging.id_token : claim.name] == ["email", "amr"]
    error_message = "Core needs the email claim (403 without it) and the amr claim (direct MFA verification) in the ID token."
  }

  assert {
    condition     = azuread_application_api_access.core_staging_graph.scope_ids == toset(["aaaaaaaa-0000-4000-8000-000000000001", "aaaaaaaa-0000-4000-8000-000000000002", "aaaaaaaa-0000-4000-8000-000000000003"])
    error_message = "Core staging must request only openid, email and profile on Microsoft Graph, even when broader scopes are available."
  }

  assert {
    condition     = azuread_service_principal.core_staging.owners == toset(["4c5c3d64-2425-494f-b3f9-fec7253e842a"])
    error_message = "The management service principal must be the declared owner of the Core staging enterprise application."
  }
}

run "backstage_declaration" {
  command = plan

  assert {
    condition     = azuread_application_registration.backstage.sign_in_audience == "AzureADMyOrg"
    error_message = "Backstage must remain a single-tenant application."
  }

  assert {
    condition     = azuread_application_redirect_uris.backstage_web.redirect_uris == toset(["https://backstage.arclight-complex.net/auth/callback"])
    error_message = "Backstage must register exactly its public origin + /auth/callback."
  }

  assert {
    condition     = [for claim in azuread_application_optional_claims.backstage.id_token : claim.name] == ["email"]
    error_message = "Backstage needs the email claim in the ID token and nothing else beyond the standard set."
  }

  assert {
    condition     = keys(azuread_application_app_role.backstage) == ["admin", "dev", "operator", "ops"]
    error_message = "Backstage must declare exactly the ops, operator, dev and admin app roles."
  }

  assert {
    condition     = alltrue([for role in azuread_application_app_role.backstage : role.allowed_member_types == toset(["User"])])
    error_message = "Backstage app roles are assignable to users only."
  }

  assert {
    condition     = azuread_application_api_access.backstage_graph.scope_ids == toset(["aaaaaaaa-0000-4000-8000-000000000001", "aaaaaaaa-0000-4000-8000-000000000002", "aaaaaaaa-0000-4000-8000-000000000003"])
    error_message = "Backstage must request only openid, email and profile on Microsoft Graph."
  }

  assert {
    condition     = azuread_service_principal.backstage.app_role_assignment_required == true && azuread_service_principal.backstage.owners == toset(["4c5c3d64-2425-494f-b3f9-fec7253e842a"])
    error_message = "Backstage must require app-role assignment for sign-in and be owned by the management service principal."
  }
}

run "reject_other_tenant" {
  command = plan

  override_data {
    target = data.azuread_client_config.current
    values = {
      tenant_id = "22222222-2222-4222-8222-222222222222"
      object_id = "4c5c3d64-2425-494f-b3f9-fec7253e842a"
    }
  }

  expect_failures = [data.azuread_client_config.current]
}

run "reject_human_administrator" {
  command = plan

  override_data {
    target = data.azuread_client_config.current
    values = {
      tenant_id = "27564b9c-b516-4bc4-9aa5-5692a38a1116"
      object_id = "bf345fac-567a-4d8f-9883-6f1879935718"
    }
  }

  expect_failures = [data.azuread_client_config.current]
}
