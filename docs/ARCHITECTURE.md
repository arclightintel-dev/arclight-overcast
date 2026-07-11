# Architecture

## Terraform module structure

15 modules in `terraform/modules/`:

| Module | Purpose | Status |
|--------|---------|--------|
| `vpc` | VPC, 8 subnets (public/app/db/workspace ×2 AZ), IGW, NAT GW, VPC endpoints (endpoint SG includes workspace CIDRs), placeholder SGs | Active |
| `ecr` | 6 ECR repositories, lifecycle policies, immutable tags | Active |
| `ecs-cluster` | ECS cluster, Cloud Map namespace | Active |
| `ecs-service-fargate` | Generic Fargate service (task def, service, Cloud Map, SG rules); `lifecycle { ignore_changes = [task_definition] }` so out-of-band deploys aren't reverted | Active (Core, Podbay) |
| `ecs-service-ec2` | Generic EC2-backed service | Stub only |
| `ecs-ec2-capacity-provider` | EC2 ASG, launch template, capacity provider, managed scaling | Active |
| `rds-postgres` | PostgreSQL instance, managed password, SGs | Active |
| `alb` | ALB, listeners, target groups, host routing, Cloudflare CIDR restriction | Active |
| `secrets` | Secrets Manager shells, SSM parameters, per-service execution roles | Active |
| `observability` | CloudWatch log groups, alarms, SNS, CloudTrail (conditional), budget (conditional) | Active |
| `iam-github-oidc` | GitHub OIDC provider (conditional), Overcast terraform role, per-service ECR push roles | Active |
| `coturn` | coturn TURN server (EC2, EIP, SG, templatefile user-data, denied/allowed-peer-ip) | Active — wired in staging (D-062) |
| `acm` | ACM certificate management | Stub only |
| `route53` | Route 53 DNS | Stub only (Cloudflare used instead) |
| `s3` | S3 buckets | Stub only |

## Environment layout

```
terraform/envs/
  staging/          — full environment: Core + Podbay controller live, coturn live, Podbay workspace substrate
    main.tf         — ~955 lines, 12 module calls + root resources
    variables.tf    — 17 variables
    outputs.tf      — 24 outputs
    backend.tf      — S3 backend at staging/terraform.tfstate
    terraform.tfvars — gitignored, real values
  prod/             — substrate only, no services
    main.tf         — ~508 lines, 8 module calls (no ECR, no Core/Podbay service, no coturn)
    variables.tf    — prod defaults (multi-AZ, larger instances)
    backend.tf      — S3 backend at prod/terraform.tfstate
```

## Shared vs per-environment resources

| Resource | Owner | Prod access |
|----------|-------|-------------|
| ECR repositories | Staging state | Data source |
| GitHub OIDC provider | Staging state | Data source |
| CloudTrail | Staging state | Skipped (`create_cloudtrail = false`) |
| Budget alarm | Staging state | Skipped (`create_budget = false`) |
| S3 state bucket | Outside Terraform | Shared |
| Everything else | Per-environment | Own resources |

## State management

- Backend: S3 (`arclight-terraform-state` bucket)
- Locking: `use_lockfile = true` (native Terraform lockfile, not DynamoDB)
- Encryption: SSE enabled
- State keys: `staging/terraform.tfstate`, `prod/terraform.tfstate`

## Service templates

Each service has templates in `services/{name}/`:
- `task-definition.json.tpl` — containerDefinitions array, rendered via `templatefile()` at the root module level (not inside the service module — templatefile resolves paths relative to the calling module)
- `service.tfvars.example` — example variable values

## CI/CD workflows

| Workflow | Trigger | What it does |
|----------|---------|-------------|
| `terraform-plan.yml` | PR touching `terraform/**` | Validate + plan, post to PR — **currently broken** (see below) |
| `terraform-apply.yml` | Push to main touching `terraform/**` | Auto-apply staging — **currently broken** (see below) |
| `deploy-service.yml` | `workflow_dispatch` (manual) + `repository_dispatch` (type `deploy-service`, cross-repo self-serve — O-009) | Register new task-def revision + update ECS service with new image tag |
| `build-and-push-image.yml` | Manual (`workflow_dispatch`) | Fallback build of Overcast-owned images (dbbootstrap); module repos own their own build/test/push |

All workflows use GitHub OIDC — no long-lived AWS credentials.

**CI status (2026-07-11):** `terraform-plan.yml` and `terraform-apply.yml` are broken. CI pins Terraform `~> 1.5`, which rejects the cross-variable `validation` block in `terraform/modules/iam-github-oidc/variables.tf` (`oidc_provider_arn` references `var.create_oidc_provider` — requires Terraform ≥ 1.9), and `terraform.tfvars` is gitignored so CI lacks required vars (`core_image_tag` has no default). All applies this session were run manually with admin credentials. Deploy-model rework is scoped next session (O-009, `docs/handoff/2026-07-10-handoff.md`). See DEVELOPMENT.md for the working (manual) apply path.
