# Development Guide

## Prerequisites

- Terraform >= 1.5 (located at `C:\Tools\terraform.exe`)
- AWS CLI v2 (located at `C:\Program Files\Amazon\AWSCLIV2\aws.exe`)
- Docker Desktop (for building dbbootstrap and workspace images)
- Git Bash (for shell scripts — PowerShell has pipe encoding issues with AWS CLI)

## Authentication

Current: IAM user `john-admin` with direct credentials.
Future: IAM Identity Center with Google Workspace SSO (D-059 position 4).

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

**Staging**: auto-applies on merge to main via `terraform-apply.yml`.
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

## Key gotchas

- `terraform.tfvars` is gitignored — never commit real values
- `terraform.tfvars.example` exists for reference
- AWS CLI and Terraform are not in PATH for Git Bash — use full paths
- PowerShell mangles `-var` flags — use tfvars files instead
- `templatefile()` resolves paths relative to the module that calls it, not the root
