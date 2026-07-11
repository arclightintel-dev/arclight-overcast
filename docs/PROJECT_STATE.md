# Project State

> Updated: 2026-07-10 | HEAD: `5f74a55` on `main`

## Current phase: Phase 5 (Podbay Deploy) — IN PROGRESS

### Phase summary

| Phase | Status | Key milestone |
|-------|--------|---------------|
| Phase 0 (Foundation) | COMPLETE | 158 staging resources, 4 databases bootstrapped |
| Phase 1 (Core Deploy) | COMPLETE | Core live at core.staging.arclight-complex.net |
| Phase 2 (CI/CD) | COMPLETE | 4 workflows, v2 merged to main |
| Phase 3 (Prod Environment) | COMPLETE | 139 prod resources, databases bootstrapped |
| D-059 §9 (Staging Hardening) | COMPLETE | All 7 items |
| Phase 5 (Podbay Deploy) | IN PROGRESS | coturn + controller (v2-phase2-fix3) + workspace task def (v1-fix2, rev 14) LIVE, all checks green; Podbay-side container startup retry blocks E2E (not infra) |
| Phase 4 (ShuttleForge) | BLOCKED | PostgreSQL support in arclight-shuttleforge |

### Known debt — CI auto-apply (terraform-apply.yml) is NON-FUNCTIONAL

> D-059's auto-apply-staging-on-merge model does not run. **Every `terraform apply` this session was performed manually with admin credentials (john-admin) from local.** This must be fixed before CI-driven deploys work.

Two independent causes:

1. **Cross-variable `validation` block.** A variable `validation` block references another variable (`terraform/modules/iam-github-oidc/variables.tf` — `create_oidc_provider || oidc_provider_arn != null`). CI's pinned Terraform (`~> 1.5`, set in `terraform-apply.yml`) rejects it → *"Invalid reference in variable validation"*. Local 1.15.6 allows it, so plans are clean locally and the breakage surfaces only in CI.
2. **No image tag for CI to plan with.** `core_image_tag` has no `default` (`terraform/envs/staging/variables.tf`) and `terraform.tfvars` is gitignored, so CI has no value to supply and the plan fails on the missing required variable.

The fix is folded into the deployment-model rework (see Next actions), not patched ad hoc.

### What's live on AWS

**Staging:**
- Core running (image v2-8c2f8c8, 19 tables, asset_backend ok, 4 asset tables, 6 asset permissions, SEAM-012 present, 2 platform owners, 3 IdP brokers)
- Podbay controller LIVE on Fargate (image v2-phase2-fix3, reachable at podbay.staging.arclight-complex.net, all ready checks green: database, jwks_cache, substrate_adapter ECSAdapter, connection_registry, seed_data, recipe_available)
- Podbay workspace substrate (task def revision 14 on image v1-fix2 — image carries Podbay's supervisord entrypoint fix, task-def template normalized to stop perpetual JSON plan churn; earlier v1-fix1 fixed a chown bug over the original v1-initial; SG rules, execution role, controller task role, S3 export bucket, managed scaling)
- coturn TURN server LIVE (EIP 52.72.36.174, G4/G5 smoke passed, dedicated workspace subnets 10.0.30.0/24 + 10.0.31.0/24, allowed-peer-ip for workspace subnets, denied-peer-ip for all internal)
- Cloudflare Access gate live on *.staging.arclight-complex.net (one-time PIN IdP + service token for automation)
- Self-serve deploy pipeline live (deploy-service.yml — workflow_dispatch + repository_dispatch cross-repo)
- ALB restricted to Cloudflare CIDRs
- CloudTrail with deny-delete bucket policy

**Prod:**
- Substrate only — no services deployed
- RDS multi-AZ, ALB Cloudflare-restricted
- Databases bootstrapped, secrets shells created

### Deploy pipeline (CI/CD)

- `deploy-service.yml` supports both `workflow_dispatch` (manual) and `repository_dispatch` (cross-repo, module-triggered)
- Module repos self-serve deploys: push image to ECR, then fire `repository_dispatch` to Overcast
- OIDC trust allows `ref:main` + `environment:staging`
- Deploy role has `ecr:DescribeImages` + `PassRole` for both the execution and task roles
- Post-deploy health check authenticates through the Cloudflare Access service token
- `ecs-service-fargate` module sets `lifecycle { ignore_changes = [task_definition] }` so `terraform apply` does not revert pipeline-deployed images

### Blockers

| Item | Blocked on | Owner |
|------|-----------|-------|
| Podbay E2E integration smoke | Podbay-side workspace container startup — v1-fix2 supervisord fix shipped, retrying launch; not an infra blocker | Podbay |
| ShuttleForge deploy | PostgreSQL support in arclight-shuttleforge | ShuttleForge |
| IAM Identity Center | Google Workspace subscription | Owner (manual) |

### Next actions (priority order)

1. **Deployment model definition (scoping)** — next-session research brief across GitHub + AWS + Terraform to define a definitive deployment / staging / CI model, *before* any more ad-hoc CI fixes.
2. **Cloudflare Terraform transfer** — codify Cloudflare into Terraform; stashed work from a parallel session at `stash@{0}`. Highest-value infrastructure-unification item.
3. **Fix terraform-apply.yml** — repair CI auto-apply (both causes in "Known debt" above) as part of the deployment-model rework, not as a standalone patch.

Waiting on external owners (tracked in Blockers): Podbay E2E (Podbay-side workspace-container startup), ShuttleForge PostgreSQL support, IAM Identity Center (Google Workspace).

### Infrastructure notes

- EIP quota increased to 10
- CF Access service token (expires 2027-07-09) for automated staging checks
- OIDC trust fixed (arclightintel-dev)
- Dedicated workspace subnets added to VPC (10.0.30.0/24, 10.0.31.0/24)

### Open items from arclight-complex

- Infrastructure unification scoping (research complete, implementation pending)
- Core Phase 6A SM backend — response memorialized, awaiting 6A5
- Platform Operations Model — ratified, Overcast aligned
