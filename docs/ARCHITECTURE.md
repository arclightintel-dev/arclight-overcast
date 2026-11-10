# Architecture

## Terraform module structure

13 modules in `terraform/modules/`:

| Module | Purpose | Status |
|--------|---------|--------|
| `vpc` | VPC, 6 subnets (public/app/db ×2 AZ), IGW, NAT GW, VPC endpoints (S3 gateway; ECR API/DKR and Logs interfaces), service SGs | Active |
| `ecr` | ECR repositories (staging owns the four platform repositories; the Backstage root owns its three), lifecycle policies, immutable tags | Active |
| `ecs-cluster` | ECS cluster, Cloud Map namespace | Active |
| `ecs-service-fargate` | Generic Fargate service (task def, service, Cloud Map, SG rules); `lifecycle { ignore_changes = [task_definition] }` so out-of-band deploys aren't reverted | Active (Core, ShuttleForge, Nerfherder) |
| `ecs-service-ec2` | Generic EC2-backed service | Stub only |
| `rds-postgres` | PostgreSQL instance, managed password, SGs | Active |
| `alb` | ALB, listeners, target groups, host routing, Cloudflare CIDR restriction | Active |
| `secrets` | Secrets Manager shells, SSM parameters, per-service execution roles | Active |
| `observability` | CloudWatch log groups, alarms, SNS, CloudTrail (conditional), budget (conditional) | Active |
| `iam-github-oidc` | GitHub OIDC provider (conditional), Overcast terraform role, per-service ECR push roles | Active |
| `acm` | ACM certificate management | Stub only |
| `route53` | Route 53 DNS | Stub only (Cloudflare used instead) |
| `s3` | S3 buckets | Stub only |

## Environment layout

```
terraform/envs/
  staging/          — the v1 platform environment ("v1: staging is production", D-059 §9): Core live;
                      ShuttleForge and Nerfherder wired at desired count 0 (Podbay and coturn removed, O-011)
    main.tf         — 568 lines, 9 module calls + root resources
    shuttleforge.tf — ShuttleForge service, migrate family, secrets and roles (1 module call)
    nerfherder.tf   — Nerfherder service, bootstrap/migrate families, bucket and roles (O-013; 1 module call)
    variables.tf    — 14 variables
    outputs.tf      — 15 outputs
    backend.tf      — S3 backend at staging/terraform.tfstate
    terraform.tfvars — gitignored, real values
  prod/             — parked for v1 (no production environment, owner ruling 2026-11-09): reduced by O-016
                      to what Backstage runs on
    main.tf         — 93 lines, 3 module calls (vpc with NAT and the five one-AZ interface endpoints of
                      O-012 / OW-6, alb, observability with the alarm topic and the ALB 5xx alarm)
    variables.tf    — 7 variables
    backend.tf      — S3 backend at prod/terraform.tfstate
  backstage/        — Backstage host on the prod VPC and ALB (O-012); owner-applied, excluded from CI apply
    *.tf            — one EC2 Docker host, its data volume, IAM, buckets, secrets shells, SSM
                      parameters, target group and listener rule on the prod ALB, idle-stop
    host/, templates/ — first-boot user data and the host's scripts and systemd units
    backend.tf      — S3 backend at backstage/terraform.tfstate
```

## Shared vs per-environment resources

| Resource | Owner | Prod access |
|----------|-------|-------------|
| ECR repositories | Staging state (Backstage's three: Backstage state, O-012) | Data source |
| GitHub OIDC provider | Staging state | Data source |
| CloudTrail | Staging state | Skipped (`create_cloudtrail = false`) |
| Budget alarm | Staging state | Skipped (`create_budget = false`) |
| S3 state bucket | Outside Terraform | Shared |
| Everything else | Per-environment | Own resources |

## State management

- Backend: S3 (`arclight-terraform-state` bucket)
- Locking: `use_lockfile = true` (native Terraform lockfile, not DynamoDB)
- Encryption: SSE enabled
- State keys: `staging/terraform.tfstate`, `prod/terraform.tfstate`, `backstage/terraform.tfstate`

## Service templates

Each service has templates in `services/{name}/`:
- `task-definition.json.tpl` — containerDefinitions array, rendered via `templatefile()` at the root module level (not inside the service module — templatefile resolves paths relative to the calling module)
- `service.tfvars.example` — example variable values

## CI/CD workflows

| Workflow | Trigger | What it does |
|----------|---------|-------------|
| `terraform-plan.yml` | PR touching `terraform/**` | Validate + plan staging with the read-only plan role; summary-only PR comment (the repository is public). Works since 2026-10-23 (DR-1b plan side) |
| `terraform-apply.yml` | Push to main touching `terraform/**` | Auto-apply staging — **broken** (DR-1; see below) |
| `deploy-service.yml` | `workflow_dispatch` (manual) + `repository_dispatch` (type `deploy-service`, cross-repo self-serve — O-009) | Register a task-definition revision pinned by digest (O-3), update the ECS service, verify `/ready` and the running digest |
| `build-and-push-image.yml` | Manual (`workflow_dispatch`) | Fallback build of Overcast-owned images (dbbootstrap). Cannot push today (DR-17a); module repos own their own build/test/push |
| `deploy-backstage.yml` | Manual (`workflow_dispatch`) | Backstage release deploy over SSM (O-012) |
| `terraform-backstage-validate.yml`, `terraform-corporate-validate.yml` | PR | Validation only for the Backstage and corporate roots |

All workflows use GitHub OIDC — no long-lived AWS credentials.

**CI status (2026-11-10):** plan works on pull requests (Terraform 1.15.6, read-only role). `terraform-apply.yml` is still broken (DR-1: it uses the old role, pins Terraform `~> 1.5` and has no variables), so staging applies are run locally by an administrator after `scripts/plan_guard.py`. See DEVELOPMENT.md for the working apply path.
