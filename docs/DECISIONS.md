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

## O-011: Podbay removed from staging

**Decision**: Owner, 2026-10-21, relayed first through Core's deploy-plan coordination and then confirmed directly to Overcast. | **Recorded**: 2026-10-21.

Podbay support is withdrawn. Overcast stops the Podbay controller immediately and removes Podbay's staging infrastructure through a reviewed Terraform change, with final snapshots taken before any data is deleted.

**Executed 2026-10-21**: `aws ecs update-service --cluster arclight-staging --service arclight-podbay-staging --desired-count 0` at 17:27:18Z; `services-stable` confirmed desired 0 / running 0 at 17:27:19Z. Previous revision `arclight-podbay-staging:9`. No Terraform changed; `var.podbay_desired_count` still defaults to 1, so **a `terraform apply` of the staging root before the removal change lands would restart the controller**. Operators must not apply staging until O-011's removal PR is merged or must pass `-var podbay_desired_count=0`.

**Removal scope (staging root, `terraform/envs/staging/main.tf` at `9dea289`)**: `module.podbay_service` (l.884), workspace task definition and roles (l.634–700), controller task role and policies (l.701–826), security-group rules between Podbay and Core and for workspaces (l.564–632, 790–809, 947), the S3 export bucket and its configuration (l.827–883), `module.coturn` (l.934, D-062), `dbbootstrap_podbay_pw` (l.252), the Podbay entries in the secrets module and ECR list, the workspace subnets if nothing else uses them, and the EC2 capacity provider (l.159, 229) if no other EC2-backed workload is planned. Prod has no Podbay services; its substrate entries are removed in the same change set.

**Data disposition (owner, 2026-10-21)**: snapshot, then delete. A final RDS snapshot before the `podbay_staging` database and role are dropped; the S3 export bucket's object listing recorded and contents copied or deliberately abandoned before the bucket is destroyed; secret shells deleted with the standard recovery window.

**Platform record**: D-062 (coturn) and the Podbay sections of D-056 / INFRASTRUCTURE_SPEC are Complex-owned. Overcast removes the implementation; the platform decision that retires them is the owner's to route through Complex. Core will disable Podbay principals and clients on staging Core separately.

**Process (owner ruling, 2026-10-21)**: no spec/plan/review cycle; the data is staging-only with no retention value, so no snapshot or archive is kept. The removal is one Terraform change bundled with Core's deploy prerequisites (`CORE_TRUSTED_PROXY_CIDRS` from the Cloudflare locals, ECS container check on `/health`, 30 s target-group deregistration delay, NF/SF `core-client-secret` shells), reviewed by plan output and applied by the owner (DR-1). Applied 2026-10-21 (staging 6/6/74 after the ECR pre-step, prod 7/6/31); receipt in PROJECT_STATE. The `podbay_staging` database and role are left in place (harmless; the bootstrap image still creates them for new environments).

## O-012: Overcast hosts Backstage as a prototype platform application

**Decision**: Owner, 2026-10-21, in answer to Overcast's hosting response. | **Recorded**: 2026-10-21.

Backstage (the owner's bootstrapped analyst application; repository `arclightintel-dev/podbay`, a legacy name unrelated to the removed Podbay platform substrate) is hosted by Overcast on AWS as a **prototype platform application**, not a module and not a separate tenant. The owner's rulings:

1. **Same account, not walled off.** Backstage lives in the existing account `650880817826`, in the existing prod VPC behind the existing prod ALB (which already holds the `*.arclight-complex.net` certificate and runs nothing). A separate Terraform root `terraform/envs/backstage/` references the prod VPC and ALB through data sources, so Backstage changes never touch the prod root's state. D-059 position 5's account-separation trigger is acknowledged and consciously deferred by the owner.
2. **Egress is enforced by proxy, not by a firewall product.** The app's own proxy rule is primary; the host's security group permits egress only to the proxy provider, the Anthropic API, Entra and AWS endpoints. ShuttleForge is the intended enforcement point once it is deployed: Backstage's proxy setting moves to SF's lease API and the host's egress narrows to SF's security group. Backstage becomes SF's first consumer.
3. **Windows installers signed with Azure Trusted Signing; macOS out of scope.**
4. **Identity**: direct Entra ID in tenant `27564b9c-b516-4bc4-9aa5-5692a38a1116` with app roles for ops/operator/dev/admin. *Amended 2026-10-21 by O-014: a new registration `arclight-backstage` is created by the applications root rather than reusing the existing Dex-era `backstage` registration (owner confirmation to both Overcast and Backstage).* Core-brokered login is not available in v1 (Core is not an OpenID provider).
5. **Backups**: Litestream continuous replication to S3 plus weekly EBS snapshots with 30-day retention.
6. **Cost posture**: smallest host that serves three analysts (`t3.large` to start), idle-stop with scheduled start, wake-on-request later if wanted. No new VPC, NAT or load balancer. *Amended 2026-10-21 (manifest receipt OW-2): `t3.xlarge` with a Portal concurrency cap of 3 and unlimited credits, because each Portal container is capped at 2 CPUs and 2 GiB and the 12.7 GB corpus needs page cache; the idle-stop posture is unchanged.*
7. **Cutover window is open now.** Overcast starts as soon as Backstage delivers its deployment manifest; the host is specified inside the implementation PR rather than in a separate spec cycle (owner's ruling on ceremony, as for O-011).

**Platform record**: Complex is to be told that Backstage is hosted as a prototype application outside the module charter; no D-series decision is required for Overcast to proceed on the owner's direction.

**Implementation note (2026-10-21).** Backstage's deployment manifest was accepted with changes and its app-change spec, reviewed by Overcast, was signed by the owner (Backstage `aws/hosting` `fcc39ec`). Owner decisions recorded since: OW-2 `t3.xlarge` with a Portal cap of 3 (amends item 6); OW-6 five interface endpoints in one AZ, owned by the prod root, which makes them every prod workload's only path to Secrets Manager, SSM and CloudWatch metrics until a second AZ is added; D16 idle-stop never stops a running job or an open Portal; D19 no Cloudflare Access gate in v1; D15 the PC stays as warm standby for 14 days; **D14a the Desktop installer ships unsigned first**, signing following once Trusted Signing validation clears, which amends item 3's timing and supersedes the hosting response's condition that installers be signed before the download link appears. The Backstage root (`terraform/envs/backstage`) owns its three ECR repositories, an exception to O-006 because nothing else uses them. Reviewed before implementation by Astra and an Opus internal review (both GO-WITH-CHANGES, reconciled).

**Owner decision (2026-10-23): always on.** Asked how the host starts after an idle-stop, the owner chose always-on ("Just do always on") over a wake-on-login front door or a Kubernetes cluster. `idle_stop_enabled` now defaults to `false`; the idle alarm, busy publisher and weekday 07:00 start stay in place, so turning idle-stop back on is one variable. Cost: the `t3.xlarge` runs 730 hours a month (about $121 on demand, plus unlimited-credit charges if CPU stays above baseline) instead of working hours only. D16 still governs if idle-stop returns.

## O-013: Nerfherder staging wiring under D-072

**Authority**: platform decision D-072 "Nerfherder Staging Deployment Enabled (staging only)", ratified by the platform owner 2026-10-21, `arclight-complex@020ef5d` (`platform/DECISIONS.md` l.1445-1455). | **Recorded**: 2026-10-21, as D-072 paragraph 2 requires before anything is scheduled.

Overcast will provision Nerfherder on **staging only**, exactly D-072's list and nothing more:

- a security group with egress to Core (port 8000) and to ShuttleForge (lease API 9000 and proxy ports 9050/9100), with the matching ingress rules on the Core and ShuttleForge groups;
- an execution role and a task role (S3 access through IAM, no static keys);
- a log group `/arclight/staging/nerfherder`;
- an ECS task template with `desired_count` 1, stop-then-start deployment (`deployment_minimum_healthy_percent` 0 / `maximum_percent` 100, obligation O-2 on the Fargate module) and `stopTimeout` of at least 35 seconds;
- an OIDC push role scoped to repository `arclightintel-dev/arclight-nerfherder`, branch `main`;
- a dedicated artifact bucket;
- the secret shells Nerfherder names: `arclight/staging/nerfherder/database-url` (exists; runtime, new DML-only role `nerfherder_app_staging`), `arclight/staging/nerfherder/migration-database-url` (owner role `nerfherder_staging`), `arclight/staging/nerfherder/core-client-secret` (exists);
- one-off task families for migrations and bootstrap.

**Out of scope (D-072 paragraph 3)**: production; any new seam or contract; more than one replica; Podbay integration (Podbay withdrawn, O-011).

**Preconditions carried (D-072 paragraph 4)**: D-059 section 9 in full (no real source registration, provider credential or live collection plugin on staging until the section 6 postures hold; the staging restore drill, R3, remains the open posture; **completed 2026-10-24 as V-1**, see `docs/runbooks/restore-rds.md`); Nerfherder's own constraints (one secret-bearing `role=all` task; ShuttleForge as the required egress route, which means NF's egress is fail-closed only once SF is deployed); the platform `/ready` status-code convention for the task health check; TLS to RDS is already enforced (`rds.force_ssl` = 1).

**Sequencing (D-072 paragraph 5)**: Nerfherder's P3.5 plans are awaiting the owner's GO; NF's wiring change in this repository follows that GO; the apply is owner-authorized (DR-1). Nothing is scheduled by this record.

**Correction**: Overcast's P3.5 answer 16 cited "D-056 section 15". The deferral lived in the Overcast charter's Deferred list (amended by D-072) and in the infrastructure spec's "What NOT to Build Yet" section 15, which still lists Nerfherder and remains accurate for production. D-072 amends the charter entry only.

## O-014: Entra applications root creates the Core staging and Backstage registrations

**Decision**: Owner, 2026-10-21 (create new registrations for both applications rather than adopt the existing ones). | **Recorded**: 2026-10-21.

`terraform/corporate/entra/applications/` is the automation-authenticated root the bootstrap specification anticipated. It runs as `arclight-overcast-entra-management` through certificate authentication, refuses any other caller, and **creates** `arclight-core-staging` and `arclight-backstage` with their redirect URIs, optional ID-token claims (`email`; `amr` for Core's direct MFA verification), Backstage's four app roles with assignment required, and the delegated `openid`/`email`/`profile` Graph scopes. State key `entra/applications/terraform.tfstate`.

This supersedes, for these two applications only, O-012 item 4 ("the existing `backstage` registration") and O-010's expectation of "individually reviewed imports": creation by the owning identity needs neither an ownership transfer, which `Application.ReadWrite.OwnedBy` cannot perform, nor an import. The pre-existing `Arclight Core Staging` and Dex-era `backstage` registrations are untouched and are the administrator's to retire after Core's broker is bound and Backstage has cut over. Nothing links users to the old registrations yet (Core's personal-account link is retired under its tranche D5; Backstage's links are keyed to the Dex issuer).

Outside the root, by the administrator: client secrets straight into Secrets Manager shells (never in state), admin consent, app-role assignments (owner to `admin` first), Conditional Access, the Cloudflare Access identity provider. Service-principal owners are declared exactly and reconciled by the provider; the runbook records the drift rule.

**Reviews before implementation (2026-10-21)**: Astra (codex `gpt-6-astra`, read-only) GO-WITH-CHANGES, blocking finding the `amr` claim (verified against Core `api/routes/auth.py:355-382` and Microsoft's optional-claims documentation); Opus internal review GO-WITH-CHANGES; both reconciled in the plan record.

**Applied 2026-10-21 21:24:11Z to 21:24:26Z** on the owner's go: 14 resources created, post-apply plan clean, Graph read-back matched the declared shapes; IDs in the [service registry](service_registry.md).

## O-015: CloudTrail log protection under D-075

**Authority**: platform decision D-075, ratified by the owner 2026-10-23 (recorded on arclight-complex PR #14), closing Overcast debt DR-13. | **Recorded**: 2026-10-23.

The staging-owned account trail (O-006) and its bucket implement D-075 in `terraform/modules/observability`:

1. **No expiry.** The lifecycle rule `archive-logs` replaces `expire-old-logs`: nothing is expired, current or noncurrent. Objects of at least 128 KB move to Glacier Deep Archive after `cloudtrail_archive_days` (90). Smaller objects, which is nearly every CloudTrail file (July 2026 averaged about 3.5 KB), stay in Standard. That is the S3 default (`transition_default_minimum_object_size = "all_storage_classes_128K"`), kept deliberately: Deep Archive bills each object as at least 40 KB and adds a 12-48 hour restore to every investigation. Complex was asked to align D-075 item 1's wording.
2. **Log file validation on** (digest files under `AWSLogs/<account>/CloudTrail-Digest/`).
3. **Multi-region trail**, management events.
4. **Object Lock, governance mode, 365-day default retention** (`cloudtrail_lock_days`). Enabled on the existing versioned bucket; it cannot be disabled afterwards. The default applies to new versions only, so existing versions get an explicit governance retention (runbook `cloudtrail-log-protection.md`). Lock survives storage-class transitions, and lifecycle cannot delete a locked version. On 2026-10-23 only `john-admin`, through the `Administrators` group's `AdministratorAccess`, holds `s3:BypassGovernanceRetention`; no CI, routine or task role does. No separate `PutBucketPolicy` or `PutLifecycleConfiguration` deny is added: D-075 does not require one, and governance lock covers locked versions.
5. **Staging gate.** The D-059 §6 CloudTrail no-deletion posture holds once items 1-4 are applied on staging and recorded here. V-1 gates staging independently.

The apply is targeted at `module.observability`, so the unrelated task-definition churn on the Terraform-tracked Core task definition is not applied with it.

**Applied on staging 2026-10-23 23:59:12Z to 2026-10-24 00:00:27Z** on the owner's go (relayed by Complex, confirmed first-hand in Overcast's session): 1 added (Object Lock configuration), 2 changed (trail, lifecycle), 0 destroyed; post-apply plan of the module: no changes. Verified live: `ObjectLockEnabled: Enabled`, default `GOVERNANCE` 365 days; lifecycle `archive-logs` with no expiration and `all_storage_classes_128K`; trail `IsMultiRegionTrail` and `LogFileValidationEnabled` true; first digest 00:26:56Z with no delivery error; a new log (00:57Z) carries `GOVERNANCE` until 2027-10-24T00:57Z; `us-east-2` and `ap-southeast-2` log prefixes appeared. Existing versions (120,294 listed at 00:01:31Z): explicit `GOVERNANCE` retention until 2027-10-24T00:00:00Z applied 2026-10-24 01:00:28Z to 04:39:18Z (one `PutObjectRetention` per version); 2 refused, both logs written after enablement (10-24 00:00Z and 00:05Z) whose default retention is already later (S3 refuses to shorten it); spot-checked June, both V-1 files, July, August, September, October and the digest prefix, all `GOVERNANCE` until 2027-10-24. **D-075 is complete on staging.**

## Core coordination disposition — not a new mechanism decision

**Review date**: 2026-10-01 | **Recorded here**: 2026-10-03.

The [7G/7F receipt](platform-interface/module-feedback/core-phase7-integration-response.md) records GO for the 7G source-contract acknowledgment, NO-GO for unattended scheduling and NO-GO for the reviewed 7F custody design. The historical [Phase 6A response](platform-interface/module-feedback/core-phase6a-sm-backend-response.md) is withdrawn as implementation guidance: startup execution-role access and version labels do not establish the promised runtime grant enforcement.

Core owns custody semantics and truthful completion/retry; Complex owns contract amendments; Overcast owns an agreed infrastructure realization; SF owns eventual B2 consumption. No resolver, STS/IAM mutation, duplication/deletion mechanism, new privilege or weaker staleness guarantee is selected. SF analysis remains deferred until B2, and 7F is separate from B1 and 7G. Source acknowledgment does not authorize migration, deployment or scheduling.
