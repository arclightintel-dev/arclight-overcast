# Project State

> Updated: 2026-10-05 | Source baseline: `00c93d8` (PR #6 merged) | Working branch: `chore/cleanup-2026-10-05`
>
> Checkout cleanup and read-only observations only. Corporate access evidence is dated 2026-09-30; the Core review is dated 2026-10-01. On 2026-10-05 the only live calls were read-only AWS IAM/Organizations reads and a fresh Entra Graph credential read (see below); no deployment, apply or provider configuration changed.

## Current handoff

Start with the [2026-10-03 handoff](handoff/2026-10-03-handoff.md), [service registry](service_registry.md), and [Core 7G/7F review receipt](platform-interface/module-feedback/core-phase7-integration-response.md). The July deployment snapshot below is retained as history, not current operational acceptance.

| Workstream | Disposition | Remaining work / owner |
|---|---|---|
| Corporate Entra management | Initial bootstrap complete as observed 2026-09-30 | Overcast + administrator: choose specific existing applications for ownership/import and verify automation writes. Current permission does not grant general directory administration. |
| Cloudflare connections | Incomplete | Overcast + administrator: resolve hosting inventory permissions, account/domain ownership and Entra Access/dashboard connections; reconcile existing Terraform adoption work. |
| GitHub enterprise transition | Deferred | Owner: supply enterprise/org identifiers and account model. Current repositories and deployment trust remain the active source. |
| Shared deployment vault | Recommendation only | Owner + Overcast: choose custody, consumer permissions and rotation/recovery. AWS Secrets Manager is recommended in the registry; no migration is complete. |
| Core 7G review | GO for source-contract acknowledgment; NO-GO for unattended dispatch | Inventory found no Overcast caller/scheduler in inspected repository paths. Core + Complex must select the unattended authority model before Overcast implements a caller. |
| Core 7F/B2 custody | NO-GO under the reviewed design | Core + Complex own enforcement/completion amendments; Overcast supplied infrastructure options. SF consumer work remains deferred until B2. |
| Deployment model / CI debt | Open; July runtime claims not refreshed | Overcast: resume deployment-model scoping after the corporate connection work; verify actual CI behavior before asserting a repair or current failure. |

The bounded 7G/7F investigation was delivered and acknowledged by Complex in the coordination task. The locally available platform record at `745ec876` still says the response is pending; a committed receipt update was not verified. This difference concerns publication of the receipt, not reopening the completed investigation or accepting a custody mechanism.

## Checkout cleanup and observations — 2026-10-05

- PR #6 is merged at `00c93d8`; its Terraform Corporate Validate checks passed. The **Cloudflare Pages** check (project `arclight-labs`, account CF-01) failed on both the PR and the merge commit. The project builds this repository on push; its logs are only reachable from the Cloudflare dashboard, which the current API tokens cannot list (403). Cause not established. Record under the Cloudflare hosting connection in the [service registry](service_registry.md).
- The July Cloudflare adoption stash was moved unchanged to branch `cloudflare-adoption` (commit `3d2e57c`, pushed). It is **not** for merge: the provider needs `CLOUDFLARE_API_TOKEN` at plan time, the ALB hostname is hardcoded, and the Access policy is not adopted. The stash entry itself is left for the operator to drop after confirming the branch.
- Six fully merged local branches (`claude-dev-worskspaces`, `coturn-reimpl`, `docs/drift-reconciliation`, `fix/ecs-taskdef-json-churn`, `podbay-controller-wiring`, `v2`) and five merged remote twins are candidates for deletion by the operator. `origin/gh-pages` (the GitHub Pages site, separate lineage) and `origin/claude/gh-pages-work-4gdos8` (PR #5) are not.
- PR #5's account documentation was folded into [DEVELOPMENT.md](DEVELOPMENT.md) after read-only IAM corroboration. Deviations found: `john-admin` has a direct `AdministratorAccess` attachment in addition to group membership; `sam-admin` has no MFA device; `arclight-dev` (no keys, no policies, never signed in, since 2026-06-23) is the owner's personal console account per the owner on 2026-10-05. Operator decisions, not Terraform-managed.
- A fresh Graph read by codex astra on 2026-10-05 confirmed one certificate, zero secrets and the single original Graph grant on the Entra management application.
- `terraform fmt -check` reports four pre-existing unformatted files under `terraform/` on `main` (`envs/staging/main.tf`, `envs/staging/variables.tf`, `modules/coturn/main.tf`, `modules/iam-github-oidc/main.tf`). Left untouched here because any `terraform/**` change on `main` triggers the broken auto-apply workflow; fold into the deployment-model work.
- `demo/` (earlier React+Vite landing page plus four third-party black-hole shader clones under `demo/eval`) was archived out of the repository on 2026-10-05 to `C:\Projects\_archiverclight-overcast-demo` with its untracked content and local edits intact; history retains the tracked files. The live website is the `gh-pages` branch, built by Cloudflare Pages project `arclight-labs` (production branch `gh-pages`); its failing checks on `main` are preview builds of a branch with no site, to be disabled in the Pages dashboard.

## Next actions

1. This delivery includes the earlier corporate Terraform, scripts, CI and registry changes alongside the governance handoff. The user subsequently requested push and merge to `main`; inspect Git/PR status when resuming rather than treating the handoff's pre-publication working-tree inventory as current. Publishing source does not apply the corporate configuration again.
2. Continue the user's corporate priority: finish the selected Entra application connections and Cloudflare inventory/federation/Terraform adoption. Reuse the established management identity; do not repeat its already completed consent grant merely to reconnect.
3. Keep 7G scheduling blocked on Core/Complex's authority decision and separately authorized rollout evidence. Keep 7F blocked on the custody amendment; do not start a parallel SF task before B2.
4. Carry deployment-model/CI debt forward without opportunistic workflow changes. Repository migration, new privileges, secret migration, DNS/SSO changes and operational deployment are not outcomes of this documentation task.

## Corporate management evidence — 2026-09-30

The user requested Microsoft Entra management access and Terraform ownership before further infrastructure work. Azure CLI/Graph access is verified for `ANS Analytics LLC`, tenant `27564b9c-b516-4bc4-9aa5-5692a38a1116`, administrator `john@arclightlabs.io`, default domain `ansanalytics.com`. Entra supersedes the historical Google Workspace workforce-IdP direction below.

The dedicated corporate Terraform backend and management identity were provisioned under `terraform/corporate/`; authenticated post-apply plans returned no changes on that date. The user-approved `Application.ReadWrite.OwnedBy` grant was verified, and a certificate-authenticated application session successfully read 7 application registrations and 364 service principals. Existing Core applications and staging/prod infrastructure were outside this bootstrap; automation ownership/imports and writes to existing applications remain subsequent work. See [service registry](service_registry.md), [design](specs/entra-management.md), and [runbook](runbooks/manage-entra.md) for dated evidence and scope. The deployment snapshot below has not been refreshed by this identity or documentation work.

## Historical deployment snapshot — 2026-07-10

Recorded phase: Phase 5 (Podbay Deploy), in progress at `5f74a55`. All live-state language, image tags, resource counts and external blockers in this section describe that July session. Recheck the relevant service before relying on them operationally. The Google Workspace workforce-IdP direction is superseded by Entra; the old Core Phase 6A custody guidance is withdrawn below and in its source memo.

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

### July next actions (historical)

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
- Core Phase 6A SM backend — July response memorialized; its authorization/invalidation guidance is now withdrawn by the [7G/7F receipt](platform-interface/module-feedback/core-phase7-integration-response.md). 7F remains NO-GO.
- Platform Operations Model — ratified, Overcast aligned
