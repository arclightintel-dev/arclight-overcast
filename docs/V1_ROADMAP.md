# Overcast V1 Roadmap

> **Goal**: All Arclight services deployed to staging and production with CI/CD,
> developer access, and operational readiness. Completing all phases = V1.
>
> **Governing decisions**: D-056 (infrastructure spec), D-058 (scope expansion),
> D-059 (environment topology + CI/CD lifecycle)

---

## Phase 0: Foundation Substrate — COMPLETE

Infrastructure substrate for staging. All AWS resources provisioned, database
bootstrap verified, secrets shells created.

| Deliverable | Status |
|-------------|--------|
| VPC (10.0.0.0/16, 6 subnets, NAT GW, VPC endpoints) | Done |
| ECS cluster (Fargate + EC2 capacity providers) | Done |
| RDS PostgreSQL (managed password, 4 databases bootstrapped) | Done |
| ALB (HTTPS, host-based routing, idle_timeout=3600) | Done |
| ECR (6 repositories, immutable tags, lifecycle policies) | Done |
| Secrets Manager (17 shells) + SSM parameters | Done |
| Observability (CloudWatch, CloudTrail, SNS, budget alarm) | Done |
| IAM GitHub OIDC (split roles: Overcast terraform + per-service ECR push) | Done |
| EC2 capacity provider (ASG desired=0, Podbay-ready) | Done |
| Cloudflare DNS (staging CNAMEs, Full Strict, Advanced Certificate) | Done |
| ACM certificates (*.arclight-complex.net + *.staging.arclight-complex.net) | Done |

**Commits**: `ac6dcc7` (initial), `f2e62f9` (review fixes), `699aec1` (runbook hardening)

---

## Phase 1: Core Deploy — COMPLETE

First service live on staging. Authentication working, platform owners onboarded.

| Deliverable | Status |
|-------------|--------|
| ecs-service-fargate module (generic, reusable) | Done |
| Core task definition template (containerDefinitions, python health check) | Done |
| Core service wired in staging main.tf | Done |
| Core image pushed to ECR (v1-bfdf2ea) | Done |
| All 6 Core secrets populated | Done |
| Alembic migrations run (on container startup) | Done |
| 3 IdP brokers activated (Google, Microsoft, GitHub) | Done |
| 2 platform owners onboarded | Done |
| Phase 1D verification: 9/9 PASS | Done |

**Commits**: `390f192` (module + wiring), `fb4877e` (templatefile fix), `9993d0c` (RDS secret fix)

---

## Phase 2: CI/CD + Developer Access

Deployment automation and team onboarding infrastructure. Must complete before
first external developer joins.

| Deliverable | Status | Blocked on |
|-------------|--------|------------|
| deploy-service.yml (workflow_dispatch + repository_dispatch) | Done and operational | — |
| Self-serve deploy pipeline (cross-repo repository_dispatch, module-triggered) | Done | — |
| terraform-plan.yml (PR comment) | BROKEN — same validation-block cause as apply (CI `~> 1.5` rejects cross-var validation) | See PROJECT_STATE "Known debt" |
| terraform-apply.yml (auto-apply staging) | BROKEN — non-functional | See PROJECT_STATE "Known debt" |
| Test CI/CD workflows end-to-end | Partial — deploy-service.yml verified end-to-end; terraform plan/apply broken | Deployment model rework |
| Merge v2 branch to main | Done | — |
| IAM Identity Center setup | Pending | Google Workspace account |
| Google Workspace as identity source | Pending | Workspace subscription |
| Developer permission sets (staging read/debug, prod read-only) | Pending | Identity Center |
| GitHub environment protection rules (staging, prod) | Pending | — |
| Deployment model definition (GitHub / AWS / Terraform) | Scoping next session | Definitive model before more ad-hoc CI fixes |

> **CI auto-apply is currently broken** — `terraform-apply.yml` does not run (see PROJECT_STATE "Known debt": a cross-variable `validation` block is rejected by the CI-pinned Terraform, and `core_image_tag` has no default while `terraform.tfvars` is gitignored). Applies are manual with admin creds until the deployment-model rework. The self-serve deploy pipeline (`deploy-service.yml`, `repository_dispatch`) is unaffected — Done and operational.

**Governing decision**: D-059 positions 2 (manual deploy trigger), 3 (hybrid CI/CD),
4 (SSO + GitHub OIDC)

---

## Phase 3: Production Environment

Production infrastructure with day-one hardening. Mirrors staging topology with
stricter security, larger instances, and operational safeguards.

| Deliverable | Status | Blocked on |
|-------------|--------|------------|
| terraform/envs/prod/ (full environment) | Done | — |
| Prod ACM certificate (*.arclight-complex.net — existing) | Done | — |
| Prod ALB restricted to Cloudflare IP ranges | Done | — |
| Prod RDS (multi-AZ, enhanced backups) | Done | — |
| Prod deletion protection (RDS + ALB + CloudTrail S3) | Done | — |
| CloudTrail log protection (bucket policy DenyLogDeletion) | Done (Object Lock deferred to Phase 6 — cross-state ownership) | — |
| AWS Backup (cross-region, automated) | Deferred to Phase 6 | — |
| Prod Cloudflare CNAMEs (core., podbay., shuttleforge.) | Pending | First prod service deploy |
| terraform-apply.yml prod gate (manual approval) | Deferred to Phase 6 (OIDC role lacks infra permissions) | — |
| Prod deployment runbook | Pending | — |
| Prod database bootstrap (4 databases verified) | Done | — |

**Governing decision**: D-059 positions 5 (same account, separate TF state),
6 (non-negotiable prod hardening)

---

## Phase 4: ShuttleForge Deploy

Second service. Depends on arclight-shuttleforge adding PostgreSQL support.

| Deliverable | Status | Blocked on |
|-------------|--------|------------|
| ShuttleForge task definition template (containerDefinitions) | Pending | — |
| ShuttleForge service wired in staging main.tf | Pending | — |
| ShuttleForge secrets populated | Pending | — |
| ShuttleForge image pushed to ECR | Pending | PostgreSQL support in repo |
| ShuttleForge SG rules (ingress from ALB, egress to RDS) | Pending | — |
| Cloud Map service registration (shuttleforge.staging.internal...) | Pending | — |
| Template DNS fix (.arclight.local → .internal.arclight-complex.net) | Pending | — |
| Staging verification | Pending | — |
| Prod deployment | Pending | Phase 3 |

**Blocked on**: arclight-shuttleforge PostgreSQL support (code change in that repo)

---

## Phase 5: Podbay Deploy

Third service. Controller on Fargate, workspace containers on EC2 capacity provider.

| Deliverable | Status | Blocked on |
|-------------|--------|------------|
| Workspace task definition (EC2, 1024/2048, SYS_ADMIN) | Done | — |
| Workspace execution role (ECR pull + logs) | Done | — |
| Workspace SG rules (controller→workspace 9222/9280/8080) | Done | — |
| Controller SG egress to workspace | Done | — |
| Controller task role (RunTask + S3 + PassRole) | Done | — |
| S3 export bucket (versioned, encrypted, 30-day lifecycle) | Done | — |
| EC2 managed scaling (auto-scale from 0 on RunTask) | Done | — |
| Dedicated workspace subnets (10.0.30.0/24, 10.0.31.0/24) | Done | — |
| coturn TURN server (D-062) | Done | — |
| Podbay controller wired in staging (Fargate) | Done | — |
| Podbay controller task definition template | Done | — |
| Template DNS fix (.arclight.local → .internal.arclight-complex.net) | Pending | — |
| Staging verification | Pending | — |
| Prod deployment | Pending | Phase 3 |

**Deployment model**: Controller on Fargate (INFRASTRUCTURE_SPEC amended), workspaces on EC2 via RunTask with capacityProviderStrategy (not EKS)
**Podbay Batch 5 substrate**: workspace infrastructure live, TURN server live, Podbay controller live
**Status**: All Phase 5 infrastructure deliverables Done (coturn, Podbay controller v2-phase2-fix3, workspace task def v1-fix2, dedicated workspace subnets). Phase 5 is effectively complete pending Podbay's workspace-container startup fix and E2E smoke — both Podbay-side, not infra.

---

## Phase 6: Frontend + Operational Maturity

Frontend deployment, operational tooling, and V1 polish.

| Deliverable | Status | Blocked on |
|-------------|--------|------------|
| Frontend hosting (S3 + CloudFront or Fargate) | Pending | Frontend module exists |
| All domain management consolidated in Overcast | Pending | — |
| VPC endpoints for Secrets Manager, SSM, KMS | Pending | NAT cost justification |
| CloudTrail alerting (EventBridge → SNS) | Pending | — |
| Update stale runbooks (deploy-service, rotate-secrets) | Pending | — |
| Update stale module stub comments | Pending | — |
| ECS Exec for debugging (task role + SSM) | Pending | — |
| Monitoring: service-level alarms, /ready synthetics | Pending | Services deployed |
| Cost optimization review | Pending | All services running |

---

## V1 Exit Criteria

All of the following must be true:

- [ ] Core, ShuttleForge, and Podbay running on staging
- [ ] Core and ShuttleForge running on production (Podbay prod = stretch)
- [ ] CI/CD: image push → manual deploy trigger → verified rollout
- [ ] IAM Identity Center: developers can access AWS via SSO
- [ ] All secrets documented with rotation procedures
- [ ] All runbooks tested against real deployments
- [ ] Prod hardening: deletion protection, backups, ALB origin restriction, CloudTrail protection
- [ ] Frontend deployed (if frontend module exists)
- [ ] Cost baseline established and budget alarms tuned

---

## Timeline

| Phase | Estimate | Dependencies |
|-------|----------|-------------|
| Phase 0 | Done | — |
| Phase 1 | Done | — |
| Phase 2 | 1-2 days | Google Workspace subscription for Identity Center |
| Phase 3 | 2-3 days | — |
| Phase 4 | 1-2 days | arclight-shuttleforge PostgreSQL support |
| Phase 5 | 2-3 days | Podbay Phase 2 spec, ecs-service-ec2 module |
| Phase 6 | 2-3 days | Frontend module, all services deployed |
| **Total remaining** | **~10-14 days of Overcast work** | Module repos are the critical path |
