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

**Status**: Module exists at `terraform/modules/coturn/` but is NOT WIRED. Rolled back after 4 failed apply cycles due to unspec'd OS/package/systemd interactions. Needs proper spec before reimplementation.

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

Module repos own build/test. Overcast owns deploy. No cross-repo workflow triggers.

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

Current image: `arclight/dbbootstrap:v5` (parameterized for multi-environment).
