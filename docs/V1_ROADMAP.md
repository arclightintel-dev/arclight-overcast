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
| deploy-service.yml (workflow_dispatch) | Done | — |
| terraform-plan.yml (PR comment) | Done | — |
| terraform-apply.yml (auto-apply staging) | Done | — |
| Test CI/CD workflows end-to-end | Pending | Merge v2 → main |
| Merge v2 branch to main | Pending | CI/CD verification |
| IAM Identity Center setup | Pending | Google Workspace account |
| Google Workspace as identity source | Pending | Workspace subscription |
| Developer permission sets (staging read/debug, prod read-only) | Pending | Identity Center |
| GitHub environment protection rules (staging, prod) | Pending | — |

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
| ecs-service-ec2 module (generic, for EC2-backed tasks) | Pending | — |
| Podbay controller task definition template | Pending | — |
| Podbay controller wired in staging (Fargate) | Pending | — |
| Podbay workspace task definition template | Pending | Podbay Phase 2 spec |
| Workspace SG rules (ingress from controller, egress to ShuttleForge only) | Pending | — |
| EC2 ASG scale to desired=1 | Pending | Podbay ready to deploy |
| Template DNS fix (.arclight.local → .internal.arclight-complex.net) | Pending | — |
| Staging verification | Pending | — |
| Prod deployment | Pending | Phase 3 |

**Blocked on**: Podbay Phase 2 spec locked, ecs-service-ec2 module
**Deployment model**: ECS on EC2 via RunTask (not EKS) — scoped in Podbay deployment response

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
