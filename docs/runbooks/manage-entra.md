# Manage the corporate Entra tenant

Tenant `27564b9c-b516-4bc4-9aa5-5692a38a1116` is **ANS Analytics LLC**. The administrator is `john@arclightlabs.io` (object `bf345fac-567a-4d8f-9883-6f1879935718`). Authenticated Graph reads on 2026-09-30 confirmed Global Administrator membership, verified domains `ANSAnalytics.onmicrosoft.com`, `ansanalytics.com`, and `arclightlabs.io`, with `ansanalytics.com` the default.

The [design](../specs/entra-management.md) defines the permission and state boundaries. The [service registry](../service_registry.md) records current connection status. The bootstrap root owns only the new management identity; existing Core/Backstage/other enterprise applications require individual inspection and import before Terraform manages them.

## Local tools and administrator login

PowerShell 7 and Azure CLI 2.90.0 are available locally. The portable Azure CLI is at `C:\Users\jkcos\.arclight\tools\azure-cli-2.90.0\bin\az.cmd`; add that directory to the current process PATH before using Terraform. Do not change system PATH merely to run this root.

```powershell
$env:PATH = 'C:\Users\jkcos\.arclight\tools\azure-cli-2.90.0\bin;' + $env:PATH
az login --tenant 27564b9c-b516-4bc4-9aa5-5692a38a1116 --allow-no-subscriptions --use-device-code
az account show --query '{tenant:tenantId,account:user.name}'
```

Use the tenant-level account if no Azure resource subscriptions are available. For Graph queries containing `&` on Windows, call the bundled Python entry point directly to avoid `az.cmd` interpreting the ampersand as a shell separator:

```powershell
$azPython = 'C:\Users\jkcos\.arclight\tools\azure-cli-2.90.0\python.exe'
& $azPython -m azure.cli rest --method GET --url 'https://graph.microsoft.com/v1.0/me?$select=id,displayName,userPrincipalName'
& $azPython -m azure.cli rest --method GET --url 'https://graph.microsoft.com/v1.0/organization?$select=id,displayName,verifiedDomains'
```

Before a bootstrap plan, remove service-principal credentials and OIDC configuration from that process environment. `use_cli = true` alone does not prevent other credential sources taking precedence. Verify the returned tenant/account and use the verified administrator object ID. The root additionally checks the provider's tenant/object ID before application creation.

## Certificate and state preparation

Run `scripts/entra/New-ManagementCertificate.ps1` with the verified administrator object ID and a **new directory outside the repository**. It creates a 3072-bit RSA certificate, an encrypted PFX, a password protected by Windows DPAPI for the current user, and a public-only `terraform-inputs.json`. The directory permits only the current Windows user and SYSTEM. No credential is printed.

The initial credential directory is `C:\Users\jkcos\.arclight\entra\27564b9c-b516-4bc4-9aa5-5692a38a1116\certificates\20260930`. Its certificate expires on `2027-03-29T14:50:32Z`. The password file is bound to this Windows user; copying it to another machine does not provide recovery. An administrator can issue a replacement certificate if this machine is lost. Do not put the private PFX/password in Terraform inputs or state.

Create the dedicated corporate backend using [the state bootstrap instructions](../../terraform/corporate/state/README.md). That root imports the new bucket and manages encryption, versioning, ownership, public-access blocking, and TLS enforcement. Verify bucket ownership and protection before initializing the Entra backend. Existing staging deployment roles have broad access to the old state bucket; they receive no new grant to this one.

Run [the Entra bootstrap root](../../terraform/corporate/entra/bootstrap/README.md) with the external public-only input file. Save and inspect the plan before applying it. The initial plan should create one management registration, one administrator ownership link, one service principal, one public certificate credential, and one API-permission declaration. It must not modify existing applications, domains, users, groups, or SSO policies.

## Grant and verify API access

The requested Graph permission is **Application.ReadWrite.OwnedBy**, app-role ID `18a4783c-866b-4cc7-a460-3d5e5662c884`. Declaring it in Terraform does not grant it. After the bootstrap apply, an administrator grants this exact application permission to the new service principal. Verify the app's client/object IDs and requested permission first. Keep this grant outside the automation-managed state so the runtime identity does not need permission to grant itself more authority.

The initial grant was completed on 2026-09-30 at 15:22 UTC after explicit user approval. A fresh read verified exactly that one Graph application permission. The subsequent certificate-authenticated `AppOnly` session successfully read all 7 application registrations and 364 service principals. Do not grant the permission again merely to reconnect; authenticate with the existing certificate. The registry records the assignment ID for inspection or revocation.

For direct management, import the official `Microsoft.Graph.Authentication` PowerShell module and connect with the private certificate. This example never prints the password or an access token:

```powershell
Import-Module 'C:\Users\jkcos\.arclight\tools\Microsoft.Graph.Authentication\2.41.0\Microsoft.Graph.Authentication.psd1'
$credentialDirectory = 'C:\Users\jkcos\.arclight\entra\27564b9c-b516-4bc4-9aa5-5692a38a1116\certificates\20260930'
$securePassword = Get-Content (Join-Path $credentialDirectory 'password.dpapi') -Raw | ConvertTo-SecureString
$certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new(
    (Join-Path $credentialDirectory 'management.pfx'), $securePassword,
    [Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet)
$clientId = '0027ad40-c6ab-4166-b010-6b9d378b1772' # Verify against bootstrap outputs after any replacement.
Connect-MgGraph -TenantId '27564b9c-b516-4bc4-9aa5-5692a38a1116' -ClientId $clientId -Certificate $certificate -ContextScope Process -NoWelcome
Get-MgContext | Select-Object TenantId,ClientId,AuthType
Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/applications?$select=id,appId,displayName'
# Keep the certificate alive during the session, including token refreshes.
# At the end: Disconnect-MgGraph; $certificate.Dispose()
```

For a later automation-managed Terraform root, use provider certificate authentication through `ARM_TENANT_ID`, `ARM_CLIENT_ID`, `ARM_CLIENT_CERTIFICATE_PATH`, and the process-only `ARM_CLIENT_CERTIFICATE_PASSWORD`, with CLI/OIDC/MSI authentication disabled. Never persist the password as a user/system environment variable or in a tracked file. AWS backend authentication remains a separate requirement.

The initial Graph grant permits app/SP listing and management of owned application objects. It grants no group/user/role/Conditional Access administration. Existing applications need ownership of both registration and service principal assigned to automation before import. A broader operation requires its own explicit permission design.

## Rotation and recovery

Add a **second** certificate resource with a distinct address and a new local credential directory. Apply that addition, verify Graph and Terraform authentication with the new credential, then retire the old certificate in a separate apply. Replacing the single certificate resource with `create_before_destroy` cannot provide a test between creation and removal.

The named administrator can disable the management service principal or revoke its Graph app-role grant to stop automation. Preserve a working administrator recovery path. Do not remove corporate domains or change user login policy to recover this application credential.
