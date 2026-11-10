# Overcast V1 Roadmap

> **Goal**: The v1 services (Core, ShuttleForge, Nerfherder) deployed to staging with CI/CD,
> developer access, and operational readiness. Staging is v1's only platform environment
> ("v1: staging is production", D-059 §9). There is **no production environment in v1**
> (owner ruling 2026-11-09; D-056 parked), and Podbay is deferred to v2 (D-071).
>
> **Governing decisions**: D-056 (production spec, parked for v1), D-058 (scope expansion),
> D-059 (environment topology + CI/CD lifecycle), D-071 (Podbay to v2), D-072 (Nerfherder, staging only).
> Aligned with arclight-complex `48c1715` on 2026-11-10. Current status lives in `PROJECT_STATE.md`.

---

## Phase 0: Foundation Substrate — COMPLETE

Infrastructure substrate for staging. All AWS resources provisioned, database
bootstrap verified, secrets shells created.

| Deliverable | Status |
|-------------|--------|
| VPC (10.0.0.0/16, 6 subnets, NAT GW, VPC endpoints) | Done |
| ECS cluster (Fargate + EC2 capacity providers; the EC2 provider was removed with Podbay, O-011) | Done |
| RDS PostgreSQL (managed password, 4 databases bootstrapped) | Done |
| ALB (HTTPS, host-based routing, idle_timeout=3600) | Done |
| ECR (6 repositories, immutable tags, lifecycle policies; 4 platform repositories since the two Podbay repositories were deleted, O-011) | Done |
| Secrets Manager (17 shells) + SSM parameters | Done |
| Observability (CloudWatch, CloudTrail, SNS, budget alarm) | Done |
| IAM GitHub OIDC (split roles: Overcast terraform + per-service ECR push) | Done |
| EC2 capacity provider (ASG desired=0, Podbay-ready) | Done; removed 2026-10-21 (O-011) |
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
| terraform-plan.yml (PR comment) | Done 2026-10-23 (DR-1b plan side): read-only plan role, Terraform 1.15.6, summary-only output | — |
| terraform-apply.yml (auto-apply staging) | BROKEN — non-functional (DR-1) | Deployment model rework |
| Test CI/CD workflows end-to-end | Partial — deploy-service.yml verified end-to-end; plan works; apply broken | Deployment model rework |
| Merge v2 branch to main | Done | — |
| IAM Identity Center setup | Pending | Entra federation (Entra superseded Google Workspace; see `service_registry.md`) |
| ~~Google Workspace as identity source~~ | Superseded by Entra | — |
| Developer permission sets (staging read/debug) | Pending | Identity Center |
| GitHub environment protection rules (staging) | Pending | — |
| Deployment model definition (GitHub / AWS / Terraform) | Open (DR-1) | Definitive model before more ad-hoc CI fixes |

> **CI auto-apply is broken** — `terraform-apply.yml` does not run (DR-1 in PROJECT_STATE "Known debt"). Staging applies are run locally by an administrator after `scripts/plan_guard.py` until the deployment-model rework. The plan side works on pull requests since 2026-10-23. The self-serve deploy pipeline (`deploy-service.yml`, `repository_dispatch`) is unaffected — Done and operational.

**Governing decision**: D-059 positions 2 (manual deploy trigger), 3 (hybrid CI/CD),
4 (SSO + GitHub OIDC)

---

## Phase 3: Production Environment — PARKED (no production environment in v1)

> Owner ruling 2026-11-09: no production environment in v1; D-056's production topology is
> parked, not implemented. O-016 (2026-11-09) reduced `terraform/envs/prod` to the VPC, NAT,
> endpoints, ALB and alarm topic that Backstage runs on (O-012), and removed the prod RDS
> (final snapshot `arclight-prod-final-fcf44ee8`), ECS cluster, secrets, roles and dbbootstrap
> tasks. A production deployment after v1 starts again from D-056, not from this table, which is
> retained as July 2026 history.

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

## Phase 4: ShuttleForge Deploy (staging)

Second service. PostgreSQL support landed in ShuttleForge (SF.9, 2026-09-30); the gates are in
PROJECT_STATE (G1-G4).

| Deliverable | Status | Blocked on |
|-------------|--------|------------|
| ShuttleForge task definition template (containerDefinitions) | Done | — |
| ShuttleForge service wired in staging (`shuttleforge.tf`, desired count 0) | Done (G1, 2026-10-29) | — |
| ShuttleForge secrets populated | Done (G2 and SfValues, 2026-10-29); `core-client-secret` stays empty | — |
| ShuttleForge image pushed to ECR | Pending (G3) | SF's reviewed SF.11 execution plan; first image is the line release current then (r6 at present) |
| ShuttleForge SG rules and the Core JWKS pair on 8000 | Done (G1) | — |
| Cloud Map service registration (shuttleforge.staging.internal...) | Done (G1) | — |
| Template DNS fix (.arclight.local → .internal.arclight-complex.net) | Done (O-4) | — |
| Staging verification | Pending (G4) | G3; first admission under the DR-18 allowance |
| ~~Prod deployment~~ | Not in v1 (no production environment) | — |

## Phase 4b: Nerfherder Deploy (staging only, D-072 / O-013)

| Deliverable | Status | Blocked on |
|-------------|--------|------------|
| N-G1: wiring (service at 0, bootstrap/migrate families, bucket, push role) | Done 2026-11-09; follow-up (PR #65) 2026-11-10 | — |
| N-G2: dbbootstrap `v1-4a9ce79`, `nerfherder_app_staging`, runtime and migration URLs | Done 2026-11-10 | — |
| N-G3: first image, migration, `nf-app-role` re-run | Pending | NF's image push |
| N-G4: service to 1, in-VPC readiness probe | Pending | N-G3; useful only once ShuttleForge serves leases |

---

## Phase 5: Podbay Deploy — DEFERRED TO V2 (D-071); Overcast substrate removed (O-011, 2026-10-21)

> Podbay is deferred to v2 by D-071: no Podbay deployment, image build, integration gate or smoke test is a v1 target. Overcast removed the Podbay substrate, coturn and both Podbay ECR repositories on 2026-10-21 (O-011); the `podbay_staging` database and role were left in place. The table is retained as history.

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

- [ ] Core, ShuttleForge and Nerfherder running on staging (the v1 topology, TESTING_PROTOCOLS; Podbay deferred to v2, D-071)
- ~~Core and ShuttleForge running on production~~ — not a v1 criterion: no production environment in v1 (owner ruling 2026-11-09)
- [ ] CI/CD: image push → manual deploy trigger → verified rollout
- [ ] IAM Identity Center: developers can access AWS via SSO
- [ ] All secrets documented with rotation procedures
- [ ] All runbooks tested against real deployments
- [ ] Staging hardening under D-059 §6 (staging is production in v1): CloudTrail log protection applied (D-075 / O-015), V-1 restore drill completed 2026-10-24; production hardening moves with D-056 to after v1
- [ ] Frontend deployed (if frontend module exists)
- [ ] Cost baseline established and budget alarms tuned

---

## Timeline

> July 2026 estimate, retained as history. Its dependencies (Google Workspace, ShuttleForge PostgreSQL
> support, Podbay Phase 2, a production phase) are superseded; the current sequence is in PROJECT_STATE.

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
