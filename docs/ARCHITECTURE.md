# Architecture

## Terraform module structure

15 modules in `terraform/modules/`:

| Module | Purpose | Status |
|--------|---------|--------|
| `vpc` | VPC, 6 subnets, IGW, NAT GW, VPC endpoints, placeholder SGs | Active |
| `ecr` | 6 ECR repositories, lifecycle policies, immutable tags | Active |
| `ecs-cluster` | ECS cluster, Cloud Map namespace | Active |
| `ecs-service-fargate` | Generic Fargate service (task def, service, Cloud Map, SG rules) | Active (Core) |
| `ecs-service-ec2` | Generic EC2-backed service | Stub only |
| `ecs-ec2-capacity-provider` | EC2 ASG, launch template, capacity provider, managed scaling | Active |
| `rds-postgres` | PostgreSQL instance, managed password, SGs | Active |
| `alb` | ALB, listeners, target groups, host routing, Cloudflare CIDR restriction | Active |
| `secrets` | Secrets Manager shells, SSM parameters, per-service execution roles | Active |
| `observability` | CloudWatch log groups, alarms, SNS, CloudTrail (conditional), budget (conditional) | Active |
| `iam-github-oidc` | GitHub OIDC provider (conditional), Overcast terraform role, per-service ECR push roles | Active |
| `coturn` | coturn TURN server (EC2, EIP, SG) | Exists but NOT WIRED — needs spec |
| `acm` | ACM certificate management | Stub only |
| `route53` | Route 53 DNS | Stub only (Cloudflare used instead) |
| `s3` | S3 buckets | Stub only |

## Environment layout

```
terraform/envs/
  staging/          — full environment, Core deployed, Podbay substrate live
    main.tf         — ~835 lines, 10 module calls + root resources
    variables.tf    — 16 variables
    outputs.tf      — ~20 outputs
    backend.tf      — S3 backend at staging/terraform.tfstate
    terraform.tfvars — gitignored, real values
  prod/             — substrate only, no services
    main.tf         — ~508 lines, 9 module calls (no ECR, no Core service)
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
| `terraform-plan.yml` | PR touching `terraform/**` | Validate + plan, post to PR |
| `terraform-apply.yml` | Push to main touching `terraform/**` | Auto-apply staging |
| `deploy-service.yml` | Manual (workflow_dispatch) | Update ECS service with new image tag |
| `build-and-push-image.yml` | Manual (workflow_dispatch) | Build Overcast-owned images (dbbootstrap) |

All workflows use GitHub OIDC — no long-lived AWS credentials.
