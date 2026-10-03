# Entra management bootstrap

Status: initial backend, identity, approved Graph permission grant, and certificate-authenticated API reads verified on 2026-09-30. User requested an Entra management API identity and Terraform ownership. Tenant: `27564b9c-b516-4bc4-9aa5-5692a38a1116`. Verified administrator: `john@arclightlabs.io`. Default verified corporate domain: `ansanalytics.com`. Existing-application imports and automation-authenticated writes remain subsequent work.

## First delivery

Use Microsoft Graph through HashiCorp's `azuread` provider. Azure resource subscriptions are a different management surface and are not required for directory administration. The first delivery creates a single-tenant automation application, its enterprise application (service principal), an administrator owner, a public certificate credential, and a declaration requesting `Application.ReadWrite.OwnedBy` on Microsoft Graph.

This application permission allows automation to create applications and manage applications/service principals it owns. It also allows application/service-principal inventory. It does not grant user, group, directory-role, Conditional Access, or Azure subscription administration. Expand authority when a specific management operation requires it. No directory-wide write permission or permanent administrative directory role is part of this bootstrap.

The administrator grants the declared Graph application permission separately. Merely declaring API access is not consent. Terraform does not give the automation identity permission to grant itself additional Graph authority.

## Ownership and authentication

`terraform/corporate/entra/bootstrap/` owns the automation identity. Run this root using the named human administrator's Azure CLI session. Keep the bootstrap identity/credential boundary under human administration; subsequent application configuration belongs in a separate root authenticated as the automation identity. Give that identity ownership of both an existing app registration and its service principal before importing either into an automation-managed root. Do not import the whole tenant indiscriminately.

Local bootstrap uses the official Azure CLI, tenant-bound interactive login with `--allow-no-subscriptions`. Local unattended Graph access uses an RSA certificate: generate the private key outside Terraform, protect the encrypted PFX and its Windows DPAPI-protected password in the operator's private local directory, and pass credentials only in process memory/environment. Terraform receives the public certificate and its fixed validity dates. No private key, password, token, `tls_private_key`, or application-password resource may enter HCL or state.

PowerShell 7 on Windows supplies the .NET certificate and DPAPI facilities; no service, systemd unit, or persistent background process is installed. Azure CLI is installed from Microsoft's official Windows package into the user's Arclight tools directory. Credential files stay outside the repository. The initial certificate lifetime is 180 days. Rotation creates another certificate, validates it, then retires the old credential; expiration never justifies bypassing user authentication.

GitHub OIDC is a later execution connection after the enterprise/repository/environment and reviewer policy are known. Do not trust an unconfirmed future repository or add tenant write authority to pull-request jobs.

## State and execution

Use a dedicated corporate S3 state bucket, separate from `arclight-terraform-state`: the current staging deploy roles can access that entire existing bucket. A new key alone would not isolate corporate identity state. Provisioned bucket: `arclight-corporate-terraform-state-650880817826`, region `us-east-1`, native S3 locking, key `entra/bootstrap/terraform.tfstate`, encryption and versioning enabled, public access blocked. Bucket bootstrap and access must be verified before an authenticated Terraform plan. AWS backend authentication is independent of Entra authentication.

Corporate changes must not trigger staging deployment. The working configuration includes credential-free format/validate CI and mocked Entra boundary tests for the corporate roots, and excludes corporate paths from existing staging workflow filters. No automatic corporate apply is enabled. This describes source configuration; a hosted CI run was not verified by the 2026-10-03 documentation update.

## Execution sequence and failures

1. Prepare and validate configuration and local tooling.
2. Authenticate the named administrator to the exact tenant. Verify `/me` and organization/domain data. Stop on an account or tenant mismatch.
3. Inspect existing applications for the intended name. Reconcile/import an existing match instead of creating duplicates.
4. Generate the local credential and configure only its public certificate, fixed dates, and administrator object ID as Terraform inputs.
5. Establish the dedicated state backend. Review the saved plan: only the new management application and its explicit dependent resources may change.
6. Apply the reviewed plan, grant the one declared Graph permission as an administrator, and verify certificate-authenticated Graph access.
7. Inventory candidate SSO integrations. Add owned, individually imported objects to subsequent Terraform configuration and test each connection.

Authentication or consent failures leave the connection pending. A successful Terraform validate is syntax/schema evidence, not a live tenant plan. A created application without consent is not a functioning management connection. If provisioning partially succeeds, inspect remote state and import/reconcile before retrying. Never replace existing corporate SSO or DNS as a side effect of bootstrap.

## References

- [Microsoft Graph application management](https://learn.microsoft.com/en-us/graph/tutorial-applications-basics)
- [Graph permission definitions](https://learn.microsoft.com/en-us/graph/permissions-reference#applicationreadwriteownedby)
- [HashiCorp azuread provider](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs)
- [Azure CLI authentication](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/guides/azure_cli)
- [Certificate authentication](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/guides/service_principal_client_certificate)
