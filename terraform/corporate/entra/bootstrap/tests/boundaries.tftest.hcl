# Every provider operation is mocked. These tests prove local guards and the
# declared permission boundary, not Microsoft consent or certificate validity.
mock_provider "azuread" {
  mock_data "azuread_client_config" {
    defaults = {
      tenant_id = "27564b9c-b516-4bc4-9aa5-5692a38a1116"
      object_id = "11111111-1111-4111-8111-111111111111"
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
      app_role_ids = {
        "Application.ReadWrite.OwnedBy" = "44444444-4444-4444-8444-444444444444"
        "Application.ReadWrite.All"     = "55555555-5555-4555-8555-555555555555"
        "Directory.ReadWrite.All"       = "66666666-6666-4666-8666-666666666666"
      }
    }
  }
}

variables {
  admin_object_id = "11111111-1111-4111-8111-111111111111"
  # Deliberately inert input used only by the mock provider.
  certificate_pem        = "-----BEGIN CERTIFICATE-----\nZmFrZQ==\n-----END CERTIFICATE-----"
  certificate_start_date = "2026-09-30T00:00:00Z"
  certificate_end_date   = "2027-03-29T00:00:00Z"
}

run "owned_application_boundary" {
  command = plan

  assert {
    condition     = azuread_application_registration.management.sign_in_audience == "AzureADMyOrg"
    error_message = "Management must remain a single-tenant application."
  }

  assert {
    condition     = azuread_application_api_access.microsoft_graph.role_ids == toset(["44444444-4444-4444-8444-444444444444"])
    error_message = "Management must request only Application.ReadWrite.OwnedBy, even when broader Graph roles are available."
  }

  assert {
    condition     = azuread_application_owner.administrator.owner_object_id == var.admin_object_id && azuread_service_principal.management.owners == toset([var.admin_object_id])
    error_message = "The verified human administrator must own the application and service principal."
  }
}

run "reject_other_tenant" {
  command = plan

  override_data {
    target = data.azuread_client_config.current
    values = {
      tenant_id = "22222222-2222-4222-8222-222222222222"
      object_id = "11111111-1111-4111-8111-111111111111"
    }
  }

  expect_failures = [data.azuread_client_config.current]
}

run "reject_other_principal" {
  command = plan

  override_data {
    target = data.azuread_client_config.current
    values = {
      tenant_id = "27564b9c-b516-4bc4-9aa5-5692a38a1116"
      object_id = "22222222-2222-4222-8222-222222222222"
    }
  }

  expect_failures = [data.azuread_client_config.current]
}

run "reject_private_key_material" {
  command = plan

  variables {
    certificate_pem = "-----BEGIN CERTIFICATE-----\n-----BEGIN PRIVATE KEY-----\n-----END PRIVATE KEY-----\n-----END CERTIFICATE-----"
  }

  expect_failures = [var.certificate_pem]
}

run "reject_reversed_certificate_dates" {
  command = plan

  variables {
    certificate_end_date = "2026-09-29T00:00:00Z"
  }

  expect_failures = [var.certificate_end_date]
}
