# Development Guide

## Prerequisites

- Terraform >= 1.5 (located at `C:\Tools\terraform.exe`)
- AWS CLI v2 (located at `C:\Program Files\Amazon\AWSCLIV2\aws.exe`)
- Docker Desktop (for building dbbootstrap and workspace images)
- Git Bash (for shell scripts — PowerShell has pipe encoding issues with AWS CLI)

## Authentication

AWS account `650880817826` is the management account of AWS Organization
`o-626c11uior`; the organization's management email is `arclightintel@gmail.com`.
Console sign-in for IAM users: `https://650880817826.signin.aws.amazon.com/console`.
No account alias is set. The account display name was not verified from the CLI.

Root user: recovery and account-level settings only. Credentials live in the
password manager, never in this repo. Root MFA is enabled. IAM users can only
see billing if root has turned on "IAM user and role access to Billing
information" (root → Account → Edit → Activate IAM Access); this setting was
not inspected.

IAM inventory observed 2026-10-05 (read-only `iam list-*`/`get-*` calls as
`john-admin`; re-verify before relying on it):

| IAM user | Created | Access | MFA | Permissions |
|---|---|---|---|---|
| `john-admin` | 2026-06-23 | Console + one active access key | Yes | `Administrators` group **and** a direct `AdministratorAccess` attachment |
| `sam-admin` | 2026-09-28 | Console only, no access keys | **No** | `Administrators` group + direct `IAMUserChangePassword` |
| `arclight-dev` | 2026-06-23 | Console profile, no access keys, never signed in | No | None (no groups, no policies) |

The `Administrators` group carries `AdministratorAccess`,
`AWSManagementConsoleAdministratorAccess` and
`AWSManagementConsoleBasicUserAccess`.

Intended practice: grant or revoke admin by changing group membership, not by
attaching policies to users, and require MFA on every admin user. The
inventory above shows two deviations (the direct attachment on `john-admin`,
no MFA device on `sam-admin`) and one orphan (`arclight-dev`). Resolving them
is an operator decision, not something Terraform manages today.

Future: IAM Identity Center federated to Microsoft Entra ID (D-059 position 4,
Entra superseded the earlier Google Workspace direction) replaces these IAM
users. No Identity Center instance has been located yet; see the
[service registry](service_registry.md).

## Running Terraform

```bash
# Always from the environment directory
cd terraform/envs/staging

# Initialize (required after adding modules or first clone)
C:\Tools\terraform.exe init

# Plan (read-only, shows what would change)
C:\Tools\terraform.exe plan

# Apply (creates/modifies resources)
C:\Tools\terraform.exe apply

# Format all files
C:\Tools\terraform.exe fmt -recursive terraform/
```

**Staging**: the working path is **manual apply with admin credentials** from `terraform/envs/staging`. The intended CI auto-apply (`terraform-apply.yml` on merge to main) is **currently broken** — see [CI status](#ci-status) below. Every apply this session was run manually.
**Prod**: manual operator apply only. OIDC role lacks infra provisioning permissions.

## Adding a new Terraform module

1. Create `terraform/modules/{name}/main.tf`, `variables.tf`, `outputs.tf`
2. Wire in `terraform/envs/staging/main.tf` as a module call
3. Run `terraform init` (installs new module)
4. Run `terraform validate` and `terraform plan`
5. Verify staging plan shows 0 unintended changes to existing resources

## Adding a new service

1. Create `services/{name}/task-definition.json.tpl` (containerDefinitions only — top-level attributes are Terraform resource fields)
2. Render template via `templatefile()` at the root module level in `staging/main.tf`
3. Wire into `ecs-service-fargate` module (for Fargate services) or as a root-level `aws_ecs_task_definition` (for RunTask one-offs)

## Building images

```bash
# In Git Bash (not PowerShell — pipe issues with ECR login)
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin 650880817826.dkr.ecr.us-east-1.amazonaws.com

docker build -t arclight/{name}:v1-$(git rev-parse --short HEAD) .
docker tag arclight/{name}:v1-... 650880817826.dkr.ecr.us-east-1.amazonaws.com/arclight/{name}:v1-...
docker push 650880817826.dkr.ecr.us-east-1.amazonaws.com/arclight/{name}:v1-...
```

## Deploying a service

Service image deploys are separate from infrastructure applies. `ecs-service-fargate` sets
`lifecycle { ignore_changes = [task_definition] }`, so a `terraform apply` does **not** revert a
running service to the tfvars-pinned image — deploys advance the service out-of-band via
`deploy-service.yml`, which registers a new task-definition revision and updates the service.

`deploy-service.yml` has two triggers:

- **`workflow_dispatch`** — manual run from the Actions tab (inputs: `module`, `environment`, `image_tag`).
- **`repository_dispatch`** (type `deploy-service`) — cross-repo self-serve. Module repos fire a
  `repository_dispatch` at Overcast to deploy their own image after a successful build (O-009). A
  Cloudflare Access service token is provisioned for automation.

Because the service ignores `task_definition`, keep the tfvars image tag pinned to a real, existing
tag (never `latest` — ECR tags are immutable and lifecycle policies only rotate `v`-prefixed tags).

## CI status

**As of 2026-07-11, `terraform-plan.yml` and `terraform-apply.yml` are broken.** Do not rely on CI
auto-apply — apply manually with admin credentials. Two independent causes:

1. **Terraform version.** CI pins `terraform_version: '~> 1.5'`. `terraform/modules/iam-github-oidc/variables.tf`
   uses a cross-variable `validation` block (`oidc_provider_arn`'s validation references
   `var.create_oidc_provider`), which requires Terraform ≥ 1.9. Under 1.5 the config is rejected.
2. **Missing variables.** `terraform.tfvars` is gitignored, and required variables have no defaults
   (e.g. `core_image_tag`), so CI has no values to plan/apply with.

A deployment-model rework is scoped for next session (see DECISIONS O-009 and
`docs/handoff/2026-07-10-handoff.md`). Until then: **manual apply is the working path**, and service
deploys go through `deploy-service.yml` (above).

## Key gotchas

- `terraform.tfvars` is gitignored — never commit real values
- `terraform.tfvars.example` exists for reference
- AWS CLI and Terraform are not in PATH for Git Bash — use full paths
- PowerShell mangles `-var` flags — use tfvars files instead
- `templatefile()` resolves paths relative to the module that calls it, not the root
