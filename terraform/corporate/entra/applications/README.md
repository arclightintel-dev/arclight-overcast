# Corporate Entra applications

This root creates and owns the Microsoft Entra app registrations that Arclight applications use for sign-in, in tenant `27564b9c-b516-4bc4-9aa5-5692a38a1116`: `arclight-core-staging` (Core's Microsoft broker) and `arclight-backstage` (the Backstage prototype application, O-012). It declares redirect URIs, optional ID-token claims, app roles and the three OpenID Connect delegated scopes on Microsoft Graph. It creates no client secrets, certificates, consent grants, role assignments or Conditional Access policies.

It runs only as the automation identity `arclight-overcast-entra-management` through certificate authentication (`ARM_TENANT_ID`, `ARM_CLIENT_ID`, `ARM_CLIENT_CERTIFICATE_PATH`, process-only `ARM_CLIENT_CERTIFICATE_PASSWORD`); the provider's client-config checks reject the tenant mismatch and any caller other than that service principal, including the human administrator. Registrations created here are owned by that identity by construction. Service-principal owners are reconciled by the provider: the declared set is the real set, and an owner added by hand is removed by the next apply unless it is added to the configuration first.

The pre-existing `Arclight Core Staging` and `backstage` registrations are outside this root; the administrator retires them after the applications have moved. See [the management specification](../../../../docs/specs/entra-management.md) and [the runbook](../../../../docs/runbooks/manage-entra.md) for the apply procedure, secret delivery, consent and role assignment.

## Local validation

These commands need no tenant or AWS credentials and do not initialize remote state:

```powershell
terraform -chdir=terraform/corporate/entra/applications fmt -check
terraform -chdir=terraform/corporate/entra/applications init -backend=false -input=false -lockfile=readonly
terraform -chdir=terraform/corporate/entra/applications validate
terraform -chdir=terraform/corporate/entra/applications test
```

The mock tests check the declared shapes (single tenant, exact redirect URIs, claims, roles, scopes, owners, assignment requirement) and the caller boundary. They do not test live authorization, consent or sign-in. Generate the dependency lock file for both platforms before the read-only initialization: `terraform -chdir=terraform/corporate/entra/applications providers lock -platform=windows_amd64 -platform=linux_amd64`.

## State and inputs

Backend: the corporate bucket with key `entra/applications/terraform.tfstate`; copy `backend.hcl.example` outside the repository and pass it with `-backend-config`. There are no input variables. Outputs carry the client IDs, object IDs, the tenant-bound issuer and the Backstage app-role IDs that Core's broker-bind, Backstage's configuration and the administrator's role assignments consume.
