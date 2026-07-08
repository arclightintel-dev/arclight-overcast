# Overcast Constitution

SSOT map, invariants, and non-negotiable rules. Invariants are earned from failures.

## Invariants

### INV-001: Environment parameterization

All SQL, scripts, task definitions, and bootstrap artifacts must use an `ENVIRONMENT` variable for environment-specific identifiers (database names, role names, secret paths). No hardcoded `_staging` or `_prod`.

**Earned**: `419cc24` — dbbootstrap created `core_staging` databases on the prod RDS instance. Four databases with wrong names, wrong role names, wrong DATABASE_URL secrets. Required full re-bootstrap.

### INV-002: LF line endings for shell scripts

`.gitattributes` enforces `*.sh text eol=lf`, `*.sql text eol=lf`, `Dockerfile text eol=lf`. Shell scripts in Docker images must have Unix line endings.

**Earned**: CRLF in `entrypoint.sh` caused shell `case` patterns to include invisible `\r` characters. ECS RunTask command overrides passed clean strings (`verify-service`), but the case patterns matched `verify-service\r` — so the `*)` catch-all triggered (exit code 2). Debugged as a CRLF issue, then discovered it wasn't CRLF at all — the real issue was environment parameterization. The CRLF fix was applied anyway as defense-in-depth.

### INV-003: Immutable ECR tags are permanent

ECR repositories use `image_tag_mutability = "IMMUTABLE"`. Once a tag is pushed, it cannot be overwritten. Wasted tags (v2, v3, v4 burned during debugging) are permanent. Build correctly before pushing.

### INV-004: Secrets Manager shells only

Terraform creates `aws_secretsmanager_secret` resources (shells). Never create `aws_secretsmanager_secret_version` — that puts secret values in Terraform state. Values are populated out-of-band by operators via `aws secretsmanager put-secret-value`.

### INV-005: Spec before implement

Never implement a new infrastructure module from assumptions. Spec the following before writing code:
- What OS and why (package availability)
- What packages, from what repos, installed how
- What systemd units are created, what user they run as
- What config files, what ownership/permissions, what paths
- What the bootstrap sequence is (first boot vs steady state)
- What the failure modes are

**Earned**: `d441a5d` — coturn module failed through 4 apply-fix cycles (AL2023 EPEL incompatible, Ubuntu awscli missing, TURNSERVER_ENABLED not set, ExecStartPre permission denied). Each assumption was wrong. A 10-minute research agent would have found all issues before writing code.

### INV-006: aws_instance vs aws_launch_template user_data

`aws_instance.user_data` expects plain text — Terraform handles base64 encoding internally. `aws_launch_template.user_data` requires `base64encode()`. Using `base64encode()` on `aws_instance` double-encodes, breaking cloud-init.

## SSOT map

| Domain | Source of truth | Location |
|--------|----------------|----------|
| Infrastructure architecture | D-056 + INFRASTRUCTURE_SPEC | arclight-complex |
| Overcast scope | D-058, charter-overcast.md | arclight-complex |
| Environment topology | D-059 | arclight-complex |
| TURN server design | D-062 | arclight-complex |
| Terraform state (staging) | S3 backend | arclight-terraform-state/staging/ |
| Terraform state (prod) | S3 backend | arclight-terraform-state/prod/ |
| Secret values | AWS Secrets Manager | Never in git or Terraform state |
| Overcast decisions | O-series | docs/DECISIONS.md (this repo) |
| Phase status | docs/PROJECT_STATE.md | This repo |
| Module boundaries | docs/CHARTER.md | This repo (reference copy) |
