# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

arclight-overcast is the AWS deployment substrate for the Arclight platform. **Modules own what runs. Overcast owns where it runs.** This is not a service, not an API, not a module — it is infrastructure-as-code (Terraform) that provisions and manages the AWS environment where Arclight services deploy.

## Session start protocol

| Priority | Document | When to read |
|----------|----------|-------------|
| ALWAYS | This file (CLAUDE.md) | Every session |
| ALWAYS | `docs/PROJECT_STATE.md` | Every session — current phase, blockers, next actions |
| ALWAYS | `docs/CONSTITUTION.md` | Every session — invariants and non-negotiable rules |
| ALWAYS | `docs/DECISIONS.md` | Every session — check for recent O-series decisions |
| SELECTIVE | `docs/V1_ROADMAP.md` | When planning work or checking phase status |
| SELECTIVE | `docs/CHARTER.md` | When scope questions arise |
| SELECTIVE | `docs/ARCHITECTURE.md` | When modifying modules or adding infrastructure |
| SELECTIVE | `docs/DEVELOPMENT.md` | When running Terraform commands |
| REFERENCE | `docs/platform-interface/INFRASTRUCTURE_SPEC.md` | Platform-level architecture (from arclight-complex) |
| REFERENCE | `docs/runbooks/*.md` | Operational procedures |

## Scope (D-058)

Overcast owns:
- AWS infrastructure provisioning (VPC, ECS, RDS, ALB, ECR, IAM, Secrets Manager, CloudWatch)
- All environment infrastructure (staging, production)
- Deployment automation (CI/CD deploy workflows — module repos own build/test)
- Developer access provisioning (IAM Identity Center, OIDC trust policies)
- Domain management (Cloudflare DNS, ACM certificates, SSL/TLS)
- Frontend web application deployment
- Operational runbooks and observability

## What Overcast must NOT become

- A module (no API, no seam contracts, no domain nouns)
- A god-layer (no orchestration of module behavior)
- A monorepo (Dockerfiles stay in module repos)
- A secrets store (structure and permissions only — never write secret values into Terraform state)
- A shadow platform spec

## Key rules (earned from real work)

### Secrets: shells only
Terraform creates `aws_secretsmanager_secret` resources (shells). Never create `aws_secretsmanager_secret_version`. Values are populated out-of-band by operators. Secret values never enter Terraform state.

### Environment parameterization
All SQL, scripts, and task definitions must use an `ENVIRONMENT` variable — never hardcode `_staging` or `_prod`. **Earned**: dbbootstrap created `core_staging` databases on the prod RDS because `bootstrap.sql` had hardcoded `_staging` suffixes.

### Image tags
Use `v1-<git-sha-short>` format. The `v` prefix is required — ECR lifecycle policies only rotate images with tags starting with `v`. ECR has immutable tags — you cannot overwrite a tag once pushed. Wasted tags are permanent.

### Line endings
`.gitattributes` enforces `*.sh text eol=lf`. **Earned**: CRLF in `entrypoint.sh` caused shell `case` statement patterns to include `\r`, so command overrides via ECS RunTask didn't match any case branch (exit code 2).

### Deploy model
- `terraform-apply.yml` auto-applies staging infrastructure on merge to main
- Service deploys are manual `workflow_dispatch` via `deploy-service.yml`
- No auto-deploy to staging while it carries operational material (D-059 §8)
- Prod infrastructure changes are operator-applied (admin credentials) — OIDC role lacks infra provisioning permissions

### Boot order (D-056 §9)
Core → ShuttleForge → Podbay. Services depend on Core JWKS being available.

### RDS managed password
`manage_master_user_password = true`. The managed secret contains only `username` and `password` — NOT `host`, `port`, or `dbname`. PGHOST/PGPORT must be injected as environment variables from Terraform outputs.

### Spec before implement
Never implement a new infrastructure module from assumptions. Spec the OS, package manager, systemd units, user context, config paths, and bootstrap sequence first. **Earned**: coturn module failed through 4 apply-fix cycles because every assumption about AL2023/Ubuntu/systemd was wrong.

## Repo structure

```
terraform/
  modules/          — reusable Terraform modules (vpc, alb, ecs-cluster, etc.)
  envs/
    staging/        — staging environment root (main.tf, variables.tf, outputs.tf, backend.tf)
    prod/           — production environment root (same structure)
services/
  core/             — Core task definition template + tfvars example
  shuttleforge/     — ShuttleForge task definition template
  podbay/           — Podbay controller + workspace task definition templates
  dbbootstrap/      — Database bootstrap image (Dockerfile, SQL, entrypoint)
docs/
  runbooks/         — Operational procedures
  platform-interface/ — Cross-repo communications and specs
.github/workflows/  — CI/CD pipelines
```

## Platform references

These documents live in arclight-complex and govern Overcast's behavior:
- **D-056**: Production infrastructure spec (architecture, topology, security)
- **D-058**: Overcast scope expansion (frontend, domains, all environments)
- **D-059**: Environment topology + CI/CD lifecycle (8 positions + staging hardening §9)
- **D-062**: coturn self-hosted EC2, per-environment
- **charter-overcast.md**: Boundary charter (normative copy in arclight-complex)
- **Platform Operations Model**: Rollback policy, alarm delivery, operational posture

## Terraform commands

```bash
# Staging
cd terraform/envs/staging
C:\Tools\terraform.exe init
C:\Tools\terraform.exe plan
C:\Tools\terraform.exe apply

# Prod (manual only — no CI/CD for prod infra)
cd terraform/envs/prod
C:\Tools\terraform.exe plan
C:\Tools\terraform.exe apply
```

Terraform is at `C:\Tools\terraform.exe`. AWS CLI is at `C:\Program Files\Amazon\AWSCLIV2\aws.exe`. Neither is in PATH for Bash — use full paths or PowerShell.

## AWS account

- Account: 650880817826
- Region: us-east-1
- State bucket: arclight-terraform-state (S3, per-env state keys)
- Domain: arclight-complex.net (Cloudflare)
- GitHub org: arclight-intel
