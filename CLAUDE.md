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
| SELECTIVE | `docs/handoff/*.md` | Historical handoffs (latest 2026-10-03); `docs/PROJECT_STATE.md` supersedes them |
| SELECTIVE | `docs/service_registry.md` | Corporate identity, provider connections, vault custody and migration status |
| SELECTIVE | `docs/V1_ROADMAP.md` | When planning work or checking phase status |
| SELECTIVE | `docs/CHARTER.md` | When scope questions arise |
| SELECTIVE | `docs/ARCHITECTURE.md` | When modifying modules or adding infrastructure |
| SELECTIVE | `docs/DEVELOPMENT.md` | When running Terraform commands |
| REFERENCE | arclight-complex `platform/DECISIONS.md`, `platform/specs/TESTING_PROTOCOLS.md` | Platform decisions and test rules; read only, with `git show` at a pinned SHA (last alignment: `48c1715`) |
| REFERENCE | `docs/platform-interface/INFRASTRUCTURE_SPEC.md` | Historical copy of the June 2026 D-056 spec draft. D-056 is parked for v1; not current guidance |
| REFERENCE | `docs/runbooks/*.md` | Operational procedures |

## Scope (D-058)

Overcast owns:
- AWS infrastructure provisioning (VPC, ECS, RDS, ALB, ECR, IAM, Secrets Manager, CloudWatch)
- All environment infrastructure. v1 has one platform environment, staging ("v1: staging is production", D-059 §9). D-056's production topology is parked (owner ruling 2026-11-09): `terraform/envs/prod` keeps only the substrate Backstage runs on (O-012, O-016) and is not a production environment awaiting apply
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

## Corporate and Core integration status

The user selected Entra as the workforce IdP and `ansanalytics.com` as the primary corporate domain. The administrator-owned Entra management bootstrap and dedicated corporate state were verified on 2026-09-30, and the applications root created the Core staging and Backstage registrations on 2026-10-21 (O-014); Cloudflare connections and the future GitHub migration remain separate work. Corporate roots are isolated from staging/prod and have validation-only CI. See the service registry for identifiers, permission limits and evidence dates; do not treat an old observation as a current connectivity check.

Core runs on staging (S-054 / D-076 live 2026-11-02; trusted proxies narrowed to the ALB subnets 2026-11-10); `docs/PROJECT_STATE.md` has the live revision and the platform-alignment record. The completed Core 7G/7F review acknowledges the four-counter 7G contract only. No Overcast sweep caller was found; human/MFA authorization still blocks unattended dispatch. The reviewed 7F custody design remains NO-GO, and the historical Phase 6A memo is withdrawn as implementation guidance. No resolver, STS/IAM mechanism or weaker guarantee was selected. SF consumer analysis waits for B2. The [review receipt](docs/platform-interface/module-feedback/core-phase7-integration-response.md) records exact pins and owner prerequisites.

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
- `terraform-plan.yml` plans staging on pull requests (read-only role, summary-only output). `terraform-apply.yml` is broken (DR-1): staging applies are run locally by an administrator, after `scripts/plan_guard.py`
- Service deploys are manual `workflow_dispatch` via `deploy-service.yml`
- No auto-deploy to staging while it carries operational material (D-059 §8)
- The prod root (Backstage's substrate only) is applied by an administrator; no prod Terraform role exists (removed by O-016)

### Boot order (TESTING_PROTOCOLS §9)
Database → Core → ShuttleForge → Nerfherder. Podbay is deferred to v2 (D-071) and its Overcast infrastructure was removed (O-011). Services depend on Core JWKS being available.

### RDS managed password
`manage_master_user_password = true`. The managed secret contains only `username` and `password` — NOT `host`, `port`, or `dbname`. PGHOST/PGPORT must be injected as environment variables from Terraform outputs.

### Spec before implement
Never implement a new infrastructure module from assumptions. Spec the OS, package manager, systemd units, user context, config paths, and bootstrap sequence first. **Earned**: coturn module failed through 4 apply-fix cycles because every assumption about AL2023/Ubuntu/systemd was wrong.

## Repo structure

```
terraform/
  modules/          — reusable Terraform modules (vpc, alb, ecs-cluster, etc.)
  corporate/        — isolated corporate state and Entra management bootstrap
  envs/
    staging/        — the v1 platform environment (main.tf, shuttleforge.tf, nerfherder.tf, variables.tf, outputs.tf, backend.tf)
    prod/           — parked for v1: only the VPC, NAT, endpoints, ALB and alarm topic Backstage runs on (O-016)
    backstage/      — Backstage host on the prod VPC and ALB (O-012), separate state
services/
  core/             — Core task definition template + tfvars example
  shuttleforge/     — ShuttleForge task definition template + tfvars example
  nerfherder/       — Nerfherder task definition template
  dbbootstrap/      — Database bootstrap image (Dockerfile, SQL, entrypoint)
docs/
  runbooks/         — Operational procedures
  platform-interface/ — Cross-repo communications and specs
.github/workflows/  — CI/CD pipelines
```

## Platform references

These documents live in arclight-complex and govern Overcast's behavior (aligned against `48c1715` on 2026-11-10; the full record is in `docs/PROJECT_STATE.md`):
- **D-056**: Production infrastructure spec. **Parked for v1** (owner ruling 2026-11-09); a production deployment after v1 starts again from it
- **D-058**: Overcast scope expansion (frontend, domains, all environments)
- **D-059**: Environment topology + CI/CD lifecycle. §8: no auto-deploy to staging while it carries operational material. §9: v1 staging is production; the hold on real material lifted once V-1 completed (2026-10-24)
- **D-071**: Podbay deferred to v2. **D-072**: Nerfherder enabled on staging only
- **D-070 / D-073**: the Core scope grant is the only admission; provisioned rows are never authority (ShuttleForge's `operator_token` interim, D-073 §4)
- **D-074**: token lifetime L = 900 s, JWKS cache C = 1 h; an edge gate such as Cloudflare Access is defense in depth only (§6)
- **D-075**: CloudTrail log protection (applied as O-015). **D-076**: Core's `operator` principal type retired
- **D-062**: coturn. No current consumer (Podbay deferred) and removed from Overcast (O-011)
- **TESTING_PROTOCOLS §3**: `/ready` 200/503; deploy verification uses `/ready` and the running image digest and never presents a credential
- **charter-overcast.md**: Boundary charter (normative copy in arclight-complex)
- **Platform Operations Model**: Rollback policy, alarm delivery, operational posture

## Terraform commands

```bash
# Staging
cd terraform/envs/staging
C:\Tools\terraform.exe init
C:\Tools\terraform.exe plan
C:\Tools\terraform.exe apply

# Prod root: Backstage's substrate only (no platform production in v1, O-016); administrator-applied
cd terraform/envs/prod
C:\Tools\terraform.exe plan
C:\Tools\terraform.exe apply
```

Terraform is at `C:\Tools\terraform.exe`. AWS CLI is at `C:\Program Files\Amazon\AWSCLIV2\aws.exe`. Neither is in PATH for Bash — use full paths or PowerShell.

## AWS account

- Account: 650880817826
- Region: us-east-1
- State bucket: arclight-terraform-state (S3, per-env state keys)
- Platform service domain: arclight-complex.net (Cloudflare); corporate primary domain: ansanalytics.com (separate DNS connection)
- Current repository owner: arclightintel-dev; future enterprise/org migration remains pending
