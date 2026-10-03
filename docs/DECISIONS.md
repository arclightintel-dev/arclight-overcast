# Overcast Decisions (O-series)

Infrastructure decisions made within Overcast. Platform decisions (D-series) live in arclight-complex.

---

## O-001: Environment parameterization in dbbootstrap

**Date**: 2026-07-02 | **Commit**: `419cc24`

bootstrap.sql and entrypoint.sh must use an `ENVIRONMENT` variable for all role/database name suffixes. No hardcoded `_staging` or `_prod`.

**Trigger**: Prod database bootstrap created `core_staging` databases instead of `core_prod` because the SQL had hardcoded `_staging` suffixes.

**Implementation**: `ENVIRONMENT` env var injected by task definition, passed to psql via `-v env="$ENV"`. SQL uses `:'env'` interpolation with `format(%I)` for safe identifier quoting.

---

## O-002: coturn self-hosted on EC2 (D-062 implementation)

**Date**: 2026-07-08 | **Commit**: `9148a85` (implemented), `d441a5d` (rolled back)

Self-hosted coturn on EC2 t3.micro with Elastic IP, per-environment. Twilio rejected because media relay metadata is an unnecessary external surface.

**Historical status at `d441a5d`**: Rolled back after 4 failed apply cycles due to unspec'd OS/package/systemd interactions; specification was required before reimplementation. This is not the current wiring status: `terraform/envs/staging/main.tf:934` at `5c3a93c` wires the coturn module. The July 10 deployment snapshot records subsequent deployment; this documentation reconciliation does not reverify it live.

---

## O-003: Podbay controller on Fargate, not EC2

**Date**: 2026-07-08 | **Commit**: `56acd3e`

INFRASTRUCTURE_SPEC originally said Podbay controller runs on EC2 capacity provider. Amended to Fargate. The controller is a stateless FastAPI service (JWT validation, session management, ecs:RunTask calls) — no host-level access needed. awsvpc networking provides identical VPC connectivity regardless of capacity provider.

**Impact**: Uses existing `ecs-service-fargate` module. No new module needed.

---

## O-004: CI/CD hybrid ownership model

**Date**: 2026-07-02 | **Commit**: `4380e48`

4 workflows per D-059:
- `terraform-plan.yml` (on PR) — plan + PR comment
- `terraform-apply.yml` (on push to main) — auto-apply staging
- `deploy-service.yml` (workflow_dispatch) — manual service deploy
- `build-and-push-image.yml` (workflow_dispatch) — Overcast-owned images only (dbbootstrap)

Module repos own build/test. Overcast owns deploy. The original restriction on cross-repo workflow triggers was extended by O-009's `repository_dispatch` deployment path.

---

## O-005: ALB Cloudflare-only restriction on staging

**Date**: 2026-07-02 | **Commit**: `7a9f6e0`

Staging ALB restricted to Cloudflare IPv4 (15 CIDRs) + IPv6 (7 CIDRs). Previously open to 0.0.0.0/0.

**Trigger**: D-059 §9 staging hardening. ACM certs are CT-logged, making `*.staging.arclight-complex.net` hostnames discoverable. ALB restriction is the compensating control.

---

## O-006: Shared vs per-environment resource split

**Date**: 2026-07-02 | **Commit**: `7772f36`

Account-level resources (ECR repos, GitHub OIDC provider, CloudTrail, budget) are owned by staging's Terraform state. Prod references them via data sources and skips creation (`create_oidc_provider = false`, `create_cloudtrail = false`, `create_budget = false`).

**Rationale**: Single AWS account. Creating duplicates would fail (OIDC provider, ECR repos) or waste money (second CloudTrail trail).

---

## O-007: RDS managed secret lacks host/port

**Date**: 2026-07-02 | **Commit**: `9993d0c`

`manage_master_user_password = true` stores only `username` and `password` in the managed secret — NOT `host`, `port`, or `dbname`. The `:host::` JSON key extraction syntax fails.

**Fix**: PGHOST and PGPORT injected as environment variables from `module.rds.instance_address`, not extracted from the secret.

---

## O-008: dbbootstrap image tag convention

**Date**: 2026-07-02

dbbootstrap image uses fixed version tags (v1, v5). NOT git SHA tags. ECR immutable tags mean wasted tags (v2-v4 during CRLF/AL2023 debugging) are permanent.

Image recorded on 2026-07-02: `arclight/dbbootstrap:v5` (parameterized for multi-environment).

---

## O-009: Self-serve deploy pipeline via repository_dispatch

**Date**: 2026-07-10 | **Commits**: `8a6b777` (pipeline), `5ebb25c` (env-context fix), `d1c9b7f` (ignore_changes)

`deploy-service.yml` supports both `workflow_dispatch` (manual) and `repository_dispatch` (cross-repo, type `deploy-service`). Module repos self-serve deploys: push image to their ECR repo, then fire one dispatch call. The workflow verifies the image, registers a new task def revision, updates the ECS service, waits for stability, and health-checks through the Cloudflare Access gate.

**Boundary**: Modules own build/push (their repo, their OIDC push role). Overcast owns deploy (registers task def, updates service). This extends O-004's hybrid ownership — the pipeline is the mechanism.

**Terraform coexistence**: The `ecs-service-fargate` module uses `lifecycle { ignore_changes = [task_definition] }` on `aws_ecs_service` so `terraform apply` does not revert pipeline-deployed images. Terraform still owns `container_definitions` (secret ARNs, roles, env, log config); cpu/memory/secret changes register a new revision the next deploy picks up as its base. Conditional `ignore_changes` is impossible (lifecycle takes only literals) — always-ignore is correct because every service is CI/CD-deployed.

**Auth (open platform decision, deferred to arclight-complex)**: Cross-repo dispatch currently requires a token with dispatch access to arclight-overcast. Recommended: an org-wide GitHub App. Health checks use a Cloudflare Access service token (GitHub secrets `CF_ACCESS_CLIENT_ID`/`CF_ACCESS_CLIENT_SECRET`).

**Gotchas (earned)**: GitHub `env` context is invalid in job `name:`/`environment:` keys — using it silently fails workflow compilation and registers zero triggers (the tell: workflow name renders as the file path). `repository_dispatch` needs a nested JSON payload, not `gh -f` bracket keys. Secrets set via PowerShell pipe carry trailing whitespace.

**Prod**: staging only. Prod deploys remain operator-applied per D-059 §6 until a manual-approval gate is added.

**Auto-apply status (debt, 2026-07-10)**: The *auto-apply* half of the CI/CD model — `terraform-apply.yml` (auto-apply staging on merge, per O-004) — is currently NON-FUNCTIONAL: CI's pinned Terraform (`~> 1.5`) rejects a cross-variable `validation` block, and `core_image_tag` has no default while `terraform.tfvars` is gitignored, leaving CI no value to plan with. Applies this session were run manually with admin credentials. A definitive deployment / staging / CI model is being scoped next session and the fix lands with that rework — tracked debt, not a ratified O-decision.

**Evidence qualification, 2026-10-03**: The preceding paragraph preserves the July failure report. The workflows still contain the version constraint and staging input requirements, but the resolved CI version and present failure status were not tested in this documentation update. Do not infer the exact installed Terraform version from the constraint alone. The deployment-model repair remains open; corporate path exclusions are not that repair.

---

## O-010: Separate corporate identity bootstrap and state

**Decision / execution date**: 2026-09-30 | **Recorded here**: 2026-10-03 | **Authority**: User-directed Entra management setup and explicit approval of the single Graph grant.

Corporate identity configuration lives under `terraform/corporate/`, outside staging/prod roots. Its backend is `arclight-corporate-terraform-state-650880817826`, with distinct `state/terraform.tfstate` and `entra/bootstrap/terraform.tfstate` keys. This adds a corporate boundary to O-006; it does not move existing shared deployment resources or grant staging roles access to corporate state.

The bootstrap identity remains administrator-owned and human-administered. Terraform stores only its public certificate and declares `Application.ReadWrite.OwnedBy`; administrator consent is separate and was granted after user approval. Private certificate material and passwords stay outside the repository/state. Later automation-managed application configuration belongs in a separate root with deliberately assigned ownership and individually reviewed imports. The bootstrap does not grant user/group/role/Conditional Access or subscription administration.

Corporate CI performs validation and mocked boundary tests without credentials or backend access. Existing staging plan/apply workflows exclude corporate paths; no corporate auto-apply is enabled. These are source properties, not evidence of a hosted CI run.

**Evidence**: September 30 provisioning, authenticated no-change plans and certificate-authenticated inventory reads are recorded in the [service registry](service_registry.md). No live check or additional apply occurred during this documentation update. See the [management design](specs/entra-management.md) and [runbook](runbooks/manage-entra.md).

## Core coordination disposition — not a new mechanism decision

**Review date**: 2026-10-01 | **Recorded here**: 2026-10-03.

The [7G/7F receipt](platform-interface/module-feedback/core-phase7-integration-response.md) records GO for the 7G source-contract acknowledgment, NO-GO for unattended scheduling and NO-GO for the reviewed 7F custody design. The historical [Phase 6A response](platform-interface/module-feedback/core-phase6a-sm-backend-response.md) is withdrawn as implementation guidance: startup execution-role access and version labels do not establish the promised runtime grant enforcement.

Core owns custody semantics and truthful completion/retry; Complex owns contract amendments; Overcast owns an agreed infrastructure realization; SF owns eventual B2 consumption. No resolver, STS/IAM mutation, duplication/deletion mechanism, new privilege or weaker staleness guarantee is selected. SF analysis remains deferred until B2, and 7F is separate from B1 and 7G. Source acknowledgment does not authorize migration, deployment or scheduling.
