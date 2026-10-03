# Corporate Entra bootstrap

This root creates `arclight-overcast-entra-management` in tenant `27564b9c-b516-4bc4-9aa5-5692a38a1116`. Its Graph request is limited to `Application.ReadWrite.OwnedBy`. Admin consent is a separate step; this root creates no consent grants, directory-role assignments, private keys, or application passwords.

Run the bootstrap as `john@arclightlabs.io` through a tenant-bound Azure CLI session. Supply the independently verified administrator object ID and public certificate inputs generated outside the repository. The provider's client-config checks reject a tenant or object-ID mismatch. Clear service-principal environment credentials before execution: `use_cli = true` alone does not override `ARM_CLIENT_*` authentication. The bootstrap identity must not manage its own bootstrap state.

Follow [the management specification](../../../../docs/specs/entra-management.md) before a live run. Reconcile an existing application of the same name before creating anything. The human administrator owns the registration and enterprise application. Existing SSO applications are outside this root.

## Local validation

These commands need no tenant or AWS credentials and do not initialize remote state:

```powershell
terraform -chdir=terraform/corporate/entra/bootstrap fmt -check
terraform -chdir=terraform/corporate/entra/bootstrap init -backend=false -input=false -lockfile=readonly
terraform -chdir=terraform/corporate/entra/bootstrap validate
terraform -chdir=terraform/corporate/entra/bootstrap test
```

The mock tests check tenant/principal mismatches, the declared permission boundary, and invalid public-certificate inputs. They do not test live authorization or certificate validity. CI runs format, backend-free initialization, validation, and these mock tests without cloud credentials.

## State and inputs

Provision and verify the dedicated corporate state bucket before backend initialization. The shared staging bucket is not suitable because staging deployment roles can access its contents. `backend.hcl.example` is a partial-backend example, not evidence the bucket exists. Copy it outside the repository and use it with `-backend-config`.

Inputs are `admin_object_id`, `certificate_pem`, `certificate_start_date`, and `certificate_end_date`. The local credential script writes them to an external `terraform-inputs.json`; pass its full path with `-var-file`. The certificate dates must come from the actual certificate. Terraform stores the public certificate in state; the encrypted PFX and its password remain outside Terraform.

Use the operator runbook for authenticated initialization, saved-plan review, apply, consent, and connection verification. A syntax validation pass does not establish tenant access or grant permission. For rotation, stage a second certificate resource, apply and verify it, then retire the old credential separately. Replacing this root's single certificate resource in one apply does not provide that verification interval.

## Scope

Application creation and management of explicitly owned applications/service principals are the first supported operations. User, group, Conditional Access, administrative-role, and Azure subscription management require separately scoped additions. Future application imports belong in a separate automation-authenticated root. GitHub OIDC and automatic corporate apply are not configured here.
