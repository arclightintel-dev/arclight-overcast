# Project State

> Updated: 2026-11-10 | Platform alignment against arclight-complex `48c1715` (section below). Each section carries its own evidence date; this file, not a handoff, is the current state.
>
> *Earlier header (2026-10-05, source baseline `00c93d8`, branch `chore/cleanup-2026-10-05`):* Checkout cleanup and read-only observations only. Corporate access evidence is dated 2026-09-30; the Core review is dated 2026-10-01. On 2026-10-05 the only live calls were read-only AWS IAM/Organizations reads and a fresh Entra Graph credential read (see below); no deployment, apply or provider configuration changed.

## Platform alignment — arclight-complex `48c1715` (2026-11-10)

Docs-only pass on Complex's request (owner-directed, all repos). The platform was read with `git show` at `48c1715`; nothing in Complex was changed. Behaviour divergences found are registered below as debt, not fixed here.

**In force for Overcast:**
- **No production environment in v1.** D-056's production topology is parked, not implemented (owner ruling 2026-11-09, Complex `platform/DECISIONS.md` l.1052). "For v1, staging is production" (D-059 §9). `terraform/envs/prod` is not a production environment awaiting apply: since O-016 it holds only the VPC, NAT, endpoints, ALB and alarm topic Backstage runs on, which Complex records at l.1054.
- **Podbay deferred to v2** (D-071): no Podbay deployment, image build, integration gate or smoke test is a v1 target. Overcast's Podbay and coturn infrastructure was removed 2026-10-21 (O-011). D-062 (coturn) has no v1 consumer.
- **Nerfherder** on staging only (D-072, O-013). **Shadowbox** is a ShuttleForge sub-module with no namespace, audience or grant of its own (D-067); Overcast provisions nothing for it.
- **Core admission** (D-070, D-073): the Core scope grant is the only admission, and provisioned rows are never authority. ShuttleForge keeps its own `operator_token` in the interim (D-073 §4, SF custody); Overcast holds only the shell.
- **Token timing** (D-074): L = 900 s, C = 1 h, JWKS refresh at least every C − L − 120 s; the §4 grant gate is lifted (Core S-054). An edge gate such as Cloudflare Access is defense in depth only (§6).
- **D-075** CloudTrail protection: applied as O-015. **D-076**: Core's `operator` principal type is retired (live with S-054, 2026-11-02). Backstage's Entra app role named `operator` is a Backstage role, unrelated.
- **SF.10 browser login** is deferred to v2 (pointer under D-068); SF operators use SF's `operator_token`.
- **D-059 §9 hold lifted** with V-1 (completed 2026-10-24, `cca961f`); §8 still forbids auto-deploy to staging while it carries operational material.
- **TESTING_PROTOCOLS §3** (amended 2026-10-29): `/ready` 200 for `ready` / `degraded`, 503 for `starting` / `unavailable`; `/ready` stays unauthenticated; deploy verification uses `/ready` and the running image digest and never presents a module credential (an edge-gate token such as Cloudflare Access is outside the rule: DR-23); ShuttleForge's fail-closed first-admission allowance (DR-18). Boot order is TESTING_PROTOCOLS §9: database, Core, ShuttleForge, Nerfherder.
- **Simplification** (Complex PR #25) is on hold per Complex's 2026-11-10 notice; not started or cited here. The hold is not recorded in Complex at `48c1715` (reported).

**Contract pins** (SHA-256 of the Git blob at `48c1715`; Overcast consumes neither file directly):

| Contract | Path | SHA-256 |
|---|---|---|
| JWT claims v0.3.0 | `platform/contracts/core/jwt-claims.schema.json` | `319269be3cb2f0803e9ea48d13c3b17fc08c831d84f8861f19a74ef4460e3676` |
| SF operation permissions v0.1.0 (published 2026-10-29; the embedded `0.1.0-candidate.2` label is provenance) | `platform/contracts/core/sf-operation-permissions.json` | `0e3d6e685db0b2602f8b913c7aaa30bda23b0e2ac88558229a5941f322ff3a9a` |

**Exceptions relied on (owner-approved):**
- The prod root stays live as Backstage's substrate: O-012 (owner 2026-10-21) and O-016 (owner 2026-11-09, "yes. go ahead. hit it"), under the no-production ruling.
- Backstage in the same account and prod VPC, deferring D-059 position 5's account-separation trigger: O-012 item 1 (owner 2026-10-21).
- ShuttleForge's `operator_token` interim: D-073 §4, custody in SF's log.

**Divergences registered:** DR-17(d) (dbbootstrap still provisions Podbay's database), DR-23 (whether the Cloudflare Access headers on deploy verification count as "a credential"; closed the same day: Complex ruled they do not). Non-platform doc drift found in passing: DR-22.

## Current handoff

This file is the current state; the handoffs under `docs/handoff/` are historical (latest 2026-10-03). Also see the [service registry](service_registry.md) and the [Core 7G/7F review receipt](platform-interface/module-feedback/core-phase7-integration-response.md). The July deployment snapshot below is retained as history, not current operational acceptance.

| Workstream | Disposition | Remaining work / owner |
|---|---|---|
| Corporate Entra management | Applications root applied 2026-10-21 21:24Z (O-014): `arclight-core-staging` and `arclight-backstage` created, read-back matched, no drift | Administrator: client secrets into the Secrets Manager shells (Core's exists; Backstage's arrives with its hosting root), admin consent, Backstage role assignments (owner to `admin` first), retire the old registrations. Core D2 applied 2026-10-21 22:43Z (broker bound to the tenant issuer, audit_id 43, rolling restart healthy); MFA by Security Defaults; Core tranche D accepted 2026-10-21 (D3 owner link, D4 Entra login with trusted `amr=mfa`); Entra login is live on staging Core. Administrator: retire `Arclight Core Staging`; Cloudflare Access must admit any additional operator (Core D7). Current permission does not grant general directory administration. |
| Cloudflare connections | Incomplete | Overcast + administrator: resolve hosting inventory permissions, account/domain ownership and Entra Access/dashboard connections; reconcile existing Terraform adoption work. |
| GitHub enterprise transition | Deferred | Owner: supply enterprise/org identifiers and account model. Current repositories and deployment trust remain the active source. |
| Shared deployment vault | Recommendation only | Owner + Overcast: choose custody, consumer permissions and rotation/recovery. AWS Secrets Manager is recommended in the registry; no migration is complete. |
| Core 7G review | GO for source-contract acknowledgment; NO-GO for unattended dispatch | Inventory found no Overcast caller/scheduler in inspected repository paths. Core + Complex must select the unattended authority model before Overcast implements a caller. |
| ShuttleForge staging deploy (Phase 1.5) | **G1 APPLIED 2026-10-29 15:59:40-15:59:50Z** (owner's "hit it"; targeted, from the branch at `d3c7f2f`; PR #59 merged as `0710b5d` after Codex review with no findings; the triggered CI apply failed at `terraform init` as usual, DR-1, nothing applied): 15 added, 1 changed, 1 destroyed; post-apply full plan shows only the known Core task-definition churn. Verified live: service `arclight-shuttleforge-staging` ACTIVE 0/0 on `:1` (0/100, grace 150), `arclight-shuttleforge-migrate-staging:1`, `arclight-dbbootstrap-staging:5` (`v1-9264f1a`, the only ACTIVE revision), Cloud Map `shuttleforge`, the 8000 pair on both groups, both new shells empty. **G2 step 1 done 16:01Z**: `arclight/dbbootstrap:v1-9264f1a` = `sha256:5d05a32b5bde13c47b7eecef4da206dc78324feea732e10606c7ae1e69ba4147`, built from `git archive 9264f1a`. **G2 complete 16:12:51Z**: the owner ran `sf-staging-secrets.ps1 -Phase Prepare` (16:05Z); `sf-app-role` task `88a438a920a54d2090183e3da3db77e1` on `:5` exit 0 (16:07:56-16:08:20Z; `shuttleforge_app_staging` created, owner-URL identity check passed, grants issued as the owner; no `alembic_version` yet); the owner ran `-Phase RuntimeUrl` (`db-url` AWSCURRENT `928c6462…`). At 16:15:52Z, on the owner's go and Complex's flag, `AWSPREVIOUS` was removed from the old owner-URL version `5d4aaaeb-3abc-4e7b-8e39-0f0ab93389d6`; now unlabelled, it is pruned by Secrets Manager in time. A routine rollback of `db-url` can no longer hand the serving task the owner credential, which lives in `db-url-migration`.

A version-stage IAM condition was not added. The serving task has no task role, so the SF process holds no AWS credentials. Binding a stage-qualified `db-url` needs RegisterTaskDefinition plus PassRole, and every holder of those can already reach `db-url-migration` (DR-17c). The runtime URL is first exercised by SF's own preflight at G4. Scope (PR #59, `feat/sf-staging-substrate`): O-2, O-3, O-4, the `db-url-migration` shell, the Core JWKS SG pair on 8000 and `dbbootstrap sf-app-role`; service at desired count 0. Owner's go 2026-10-29 for the scope and for G2-G4; the owner generates the four SF secret values (KEK ring, two HMAC keys, operator token); `core-client-secret` gets no value (SF v1 never requests a Core token) | G1: targeted staging apply (owner's go first-hand). G2:
1. An administrator builds and pushes `dbbootstrap:v1-9264f1a`.
2. The owner writes `db-url-migration`, the schema-owner URL (`postgresql+asyncpg://shuttleforge_staging:…`). The owner password lives only in the current `db-url`; the bootstrap temporary was spent in July.
3. The owner writes `dbbootstrap/shuttleforge-app-db-password`.
4. Run `sf-app-role`.
5. The owner rewrites `db-url` as the runtime URL (`shuttleforge_app_staging`).

G3:
1. SF pushes its first staging image: the line release current when SF's SF.11 execution plan is reviewed (owner addendum to SF-D-0261, 2026-11-10). That is r6 at present (`local-20261110-v1-operate-r6`, v1-operate `55a2d20`), replacing r5. The push record gives the tag, ECR `imageDigest` and media type, and the `linux/amd64` child digest if it is an index.
2. Register the migrate family on its digest.
3. Run `--migrate-only` in the dbbootstrap security group, which has no route to Core.
4. Re-run `sf-app-role`.

G4:
1. The owner writes the four SF values.
2. Register the serving revision on the digest.
3. `update-service --desired-count 1`.
4. Verify the digest and `/ready`, then flip `shuttleforge_desired_count` to 1 in Terraform.

**R3, OPEN again (2026-10-29):** at `ad2668b` an empty database reports `/ready` `degraded`. SF first answered that r5 would report `ready`, then withdrew it: TESTING_PROTOCOLS §7 Tier 2.5 and SF's locked V1-AC-032 require `degraded` with no providers.

SF proposes reading `/ready/detail`: `degraded`, every check `ok` except `snapshot` = `warn` "snapshot has no usable config or endpoint inventory", and `jwks` `ok`. That conflicted with TESTING_PROTOCOLS §3 ("deploy verification must not depend on /ready/detail").

**Settled 2026-10-29.** Complex PR #20 merged, amending §3. The owner re-ruled C7 ("keep degraded"; SF PR #34 `a3a5da8`). SF's `/ready/detail` is an intended unauthenticated probe. Overcast's four constraints were adopted: machine-evaluable, fail-closed, digest as identity, SF-only and temporary.

Implemented as `scripts/sf-first-admission.jq`, used by `deploy-service.yml` only for `shuttleforge` with `/ready` `degraded` (DR-18). **r6 pin confirmed 2026-11-10:** SF's r6 code (v1-operate `55a2d20`; `shuttleforge/api/ready.py` byte-identical to r5's `5c6d617`, read-only diff) has the same 13 checks, and SF's verbatim r6 empty-database `/ready/detail` (sha256 `a06d324b…488d6dda`, recomputed here) passes; it differs from r5's only in the JWKS cache age, which is not pinned. Earlier, **r5 pin confirmed 2026-11-10:** SF's r5 code (v1-operate `5c6d617`, `shuttleforge/api/ready.py`) has exactly the 13 pinned checks, and SF's verbatim r5 empty-database `/ready/detail` (sha256 `f154fff2…a41d36e`) passes. This was checked with a Python copy of the jq logic, because jq isn't installed locally; `deploy-service.yml` runs the jq itself. r5's strict secret formats (C6: padded single-line base64, HMAC keys differ) match how `scripts/sf-staging-secrets.ps1` generates values. G3 (first push) waits on SF's reviewed SF.11 execution plan (SF-D-0261).

**SfValues done 16:18:09-11Z** (owner): `kek-ring-b64`, both HMAC keys and `operator-token` hold one version each; `core-client-secret` stays empty. Secret values: `scripts/sf-staging-secrets.ps1` (`-Phase Prepare`, `RuntimeUrl`, `SfValues`), run by the owner. O-1 lands with Nerfherder's wiring. Open: DR-15, DR-16, DR-17. |
| ShuttleForge deployment manifest (v1 exit item 4) | Revision 3 (`d031251`) ACCEPTED 2026-10-21 | No SF-side items remain. O-5 (prod push-role trust) and O-6 (SF push role trusts `v1-operate`) are DONE: applied with PR #20 on 2026-10-21; both SF push roles re-read 2026-10-22 trust `main` and `v1-operate`. O-1..O-4 are done: O-2..O-4 (rollout variables, digest deploys, SF template refresh with the `db-url-migration` leaf and `shuttleforge_app_staging` role) applied at G1 on 2026-10-29, and O-1 (dataplane SG rules, rescoped to Nerfherder) with N-G1 on 2026-11-09; R3 (restore drill) DONE 2026-10-24 (V-1, `docs/runbooks/restore-rds.md`). SF debt #102 (staging JWKS hold) LIFTED 2026-10-23: Core declared containment complete at 01:58:52Z and SF passed the all-clear (no SF verifier ever fetched staging JWKS; fetch the key set, never pin a kid; D-074: 900 s token lifetime, 1 h JWKS cache). SF's own remaining gates: its `v1-operate` push workflow (SF debt #103). See the [rev-2 receipt and its revision-3 addendum](platform-interface/module-feedback/shuttleforge-deployment-manifest-response-rev2.md). |
| Nerfherder staging wiring (O-013 under D-072) | **N-G1 applied 2026-11-09; follow-up (PR #65) applied 2026-11-10; N-G2 complete 2026-11-10 08:52Z** (owner's go first-hand): `dbbootstrap:v1-4a9ce79` pushed, `nerfherder_app_staging` created, `database-url` is the runtime URL, owner URL only in `migration-database-url`. Service 0/0. N-G3 waits on NF's image push. Detail: [wiring proposal](proposals/nerfherder-staging-wiring.md) | D-072 (`arclight-complex@020ef5d`) lifts the deferral for staging only; O-013 records Overcast's provisioning list verbatim. Sixteen answers plus five follow-ups recorded in the [response](platform-interface/module-feedback/nerfherder-p35-onboarding-response.md). O-2 rollout variables arrive with the ShuttleForge substrate PR (2026-10-29). The restore drill (R3 / V-1) was completed 2026-10-24. |
| Core staging deploy (Phase 7 build) | **Deployed 2026-10-21**: tranches B and C executed on the owner's GO; C5 verification is Core's | B: revision 10 = Overcast's revision 8 (proxy CIDRs, `/health` container check) + image `v2-7944e79` (digest `sha256:99ddc1c9…`); B2 preflight PASS (task `150db7c49bf04cf2b4bf0432000524f0`). C: Core scaled to 0 at 21:04:21Z, snapshot `arclight-staging-pre-core-p7-20261021` available 21:07:45Z, migration task `f608b0eff8834515b6e235e4ad24a1c0` exit 0 (`p6a1_admin_asset` to `p7g1_grant_expiry_notif`, nine revisions), service on revision 10 stable at 21:12:09Z; outage about 8 minutes. `/ready` body `ready`; `/ready/detail` `degraded` on `asset_backend: warn` only. Staging `terraform.tfvars` pin moved to `v2-7944e79` (O-009). Revision 9 / `v2-c0d8ed8` burned (unpinned-dependency image, caught by the rev-9 preflight). Rollback assets: the snapshot and revision 7 (`v2-8c2f8c8`). Tranche D (Entra switch) followed once the Entra applications root was applied and was accepted 2026-10-21. Core is now on revision 17 (S-054 / D-076 and the H1b proxy narrowing; see below). See the [review](platform-interface/module-feedback/core-staging-deploy-plan-review-20261021.md). |
| Podbay removal (O-011) | **Removed 2026-10-21** (PR #18: staging 6/6/74, prod 7/6/31; see "Applied 2026-10-21" below). Platform: Podbay deferred to v2 (D-071) | No snapshot or archive kept (owner); the `podbay_staging` database and role remain (DR-17(d)). Phase 5 and the July Podbay snapshot below are historical. |
| Backstage hosting (O-012) | **CUT OVER 2026-10-25**: production data migrated (C1-C9), owner signed in as admin, backups (Litestream) live, restore drill passed; PC is warm standby until 2026-11-08 (D15). **Applied 2026-10-22**; **always on since 2026-10-23** (owner; idle-stop off, #45). Applied on the owner's go: prod VPC interface endpoints (#35, 06:08-06:09Z, 5 added); `terraform/envs/backstage` (#36) 87 added 06:09-06:10Z with maintenance egress; first boot stopped fail-closed on gid 997 (`crontab` on the Ubuntu 24.04 image), fixed and host replaced 06:24-06:25Z; Codex findings fixed in #38 (secrets before the first pull, boot-time ECR login, Portal ceiling alarm) and host replaced again 06:33-06:34Z, now `i-0888f5c2165331369` (data volume reused, not reformatted); boot verified (units, firewall chains, mount, bridge, Amazon Time Sync, Busy metric); maintenance egress closed 06:28:18Z and again 06:35:32Z after #38 (2 destroyed each), post-apply plans clean, SSM verified through the endpoints alone. GitHub environment `backstage` (main only) created; Cloudflare proxied CNAME `backstage` → prod ALB created (zone already Full (strict), WebSockets on); `categorization-capability` secret written. Backstage spec signed (`fcc39ec`); WP1, WP3, WP4 landed on `aws/hosting`, not yet pushed | Owner: OIDC client secret, the PC's cookie key and the Anthropic key into their shells; admin consent and the owner's `admin` role on `arclight-backstage`; Cloudflare dashboard: check Bot Fight Mode (token cannot read bot or WAF settings). Backstage: push `main` so CI publishes images and the bundle; then the stage-only smoke deploy per [migrate-backstage.md](runbooks/migrate-backstage.md). Target-unhealthy alarm is in ALARM until the first deploy (expected). Downloads bucket and CloudFront in a later PR. See the [hosting response](platform-interface/module-feedback/backstage-aws-hosting-response.md), [manifest receipt](platform-interface/module-feedback/backstage-deployment-manifest-response.md) and [spec review](platform-interface/module-feedback/backstage-hosting-spec-review.md). |
| Core 7F/B2 custody | NO-GO under the reviewed design | Core + Complex own enforcement/completion amendments; Overcast supplied infrastructure options. SF consumer work remains deferred until B2. |
| Deployment model / CI debt | Open (DR-1): the plan side works on pull requests since 2026-10-23; `terraform-apply.yml` is still broken | Overcast: deployment-model scoping. Staging applies are run locally by an administrator after `scripts/plan_guard.py`. |

The bounded 7G/7F investigation was delivered and acknowledged by Complex in the coordination task. The locally available platform record at `745ec876` still says the response is pending; a committed receipt update was not verified. This difference concerns publication of the receipt, not reopening the completed investigation or accepting a custody mechanism.

## Checkout cleanup and observations — 2026-10-05

- PR #6 is merged at `00c93d8`; its Terraform Corporate Validate checks passed. The **Cloudflare Pages** check (project `arclight-labs`, account CF-01) failed on both the PR and the merge commit. The project builds this repository on push; its logs are only reachable from the Cloudflare dashboard, which the current API tokens cannot list (403). Cause not established. Record under the Cloudflare hosting connection in the [service registry](service_registry.md).
- The July Cloudflare adoption stash was moved unchanged to branch `cloudflare-adoption` (commit `3d2e57c`, pushed). It is **not** for merge: the provider needs `CLOUDFLARE_API_TOKEN` at plan time, the ALB hostname is hardcoded, and the Access policy is not adopted. The stash entry itself is left for the operator to drop after confirming the branch.
- Six fully merged local branches (`claude-dev-worskspaces`, `coturn-reimpl`, `docs/drift-reconciliation`, `fix/ecs-taskdef-json-churn`, `podbay-controller-wiring`, `v2`) and five merged remote twins are candidates for deletion by the operator. `origin/gh-pages` (the GitHub Pages site, separate lineage) and `origin/claude/gh-pages-work-4gdos8` (PR #5) are not.
- PR #5's account documentation was folded into [DEVELOPMENT.md](DEVELOPMENT.md) after read-only IAM corroboration. Deviations found: `john-admin` has a direct `AdministratorAccess` attachment in addition to group membership; `sam-admin` has no MFA device; `arclight-dev` (no keys, no policies, never signed in, since 2026-06-23) is the owner's personal console account per the owner on 2026-10-05. Operator decisions, not Terraform-managed.
- 2026-10-16: the owner restricted Cloudflare Pages preview builds for `arclight-labs` to the `site/*` branch pattern in the dashboard (production branch `gh-pages`, automatic production deployments still on). DR-4 closed; this commit is the first `main` push expected to carry no Pages check. The CF-01 API token still lacks Pages permission, so the hosting inventory in the registry remains open.
- A fresh Graph read by codex astra on 2026-10-05 confirmed one certificate, zero secrets and the single original Graph grant on the Entra management application.
- `terraform fmt -check` reports four pre-existing unformatted files under `terraform/` on `main` (`envs/staging/main.tf`, `envs/staging/variables.tf`, `modules/coturn/main.tf`, `modules/iam-github-oidc/main.tf`). Left untouched here because any `terraform/**` change on `main` triggers the broken auto-apply workflow; fold into the deployment-model work.
- `demo/` (earlier React+Vite landing page plus four third-party black-hole shader clones under `demo/eval`) was archived out of the repository on 2026-10-05 to `C:\Projects\_archive\arclight-overcast-demo` with its untracked content and local edits intact; history retains the tracked files. The live website is the `gh-pages` branch, built by Cloudflare Pages project `arclight-labs` (production branch `gh-pages`); its failing checks on `main` are preview builds of a branch with no site, to be disabled in the Pages dashboard.

## Debt register

Open items that are known, bounded and deliberately not being worked. Each row names an owner and the trigger that reopens it. Add rows here when deferring; remove rows when the fix merges or the item is formally dropped.

| # | Item | Evidence | Owner | Reopen when |
|---|---|---|---|---|
| DR-1 | CI `terraform-plan.yml` / `terraform-apply.yml` non-functional (version constraint vs cross-variable validation; no-default variables with gitignored tfvars). The plan side was fixed 2026-10-23 (DR-1b); the apply side is still broken. | Known debt section below; O-009 | Overcast | Deployment-model scoping (after corporate connections) |
| DR-1b | Third CI cause found 2026-10-21: `terraform-plan.yml` on pull requests never reaches Terraform because the OIDC trust admits only `ref:refs/heads/main` and `environment:staging`, not `pull_request` subjects (`terraform/modules/iam-github-oidc/main.tf:36-41`; PR #18 run 39647172786 failed at AssumeRoleWithWebIdentity). | PR #18 check | Overcast | **Plan side CLOSED 2026-10-23**: read-only `arclight-overcast-terraform-plan-staging` trusts `:pull_request`; `terraform-plan.yml` uses it, pins 1.15.6, posts summary only. Apply side stays with DR-1 |
| DR-2 | **CLOSED 2026-11-10**: `terraform fmt -check -recursive` exits 0 on every root (staging, prod, backstage, corporate) and on `terraform/modules`; `modules/coturn` no longer exists. Original: `terraform fmt -check` fails on four files under `terraform/` on `main` (`envs/staging/main.tf`, `envs/staging/variables.tf`, `modules/coturn/main.tf`, `modules/iam-github-oidc/main.tf`). Left alone because any `terraform/**` change on `main` triggers the broken auto-apply. | 2026-10-05 local check | Overcast | Same change set as DR-1 |
| DR-3 | IAM user `sam-admin` has no MFA device; `john-admin` carries a direct `AdministratorAccess` attachment in addition to `Administrators` group membership. Owner declared not a concern for now (2026-10-16). | [DEVELOPMENT.md](DEVELOPMENT.md) inventory, 2026-10-05 | Owner | Identity Center / Entra federation replaces IAM users, or earlier at owner discretion |
| DR-5 | GitHub Pages also deploys `gh-pages` to `arclightintel-dev.github.io/arclight-overcast`, a redundant public copy of the site. | Repo Pages config, 2026-10-05 | Owner | Any website change |
| DR-6 | The public website lives on the orphan `gh-pages` branch of the infrastructure repo. Owner decision 2026-10-16: keep it there for now. | gh-pages = Cloudflare Pages production branch | Owner | Next substantive website work; candidate for a dedicated site repo |
| DR-7 | `cloudflare-adoption` branch holds unreviewed Cloudflare Terraform adoption (hardcoded ALB hostname, Access policy not adopted, provider needs `CLOUDFLARE_API_TOKEN` at plan time). Not for merge. | branch `cloudflare-adoption` | Overcast | Cloudflare Terraform workstream (after Entra application connections) |
| DR-8 | CLOSED 2026-10-21 18:55Z: prod push roles and the Overcast Terraform role now trust `arclightintel-dev`; the SF push roles also trust `v1-operate`. Root cause was `github_org = "arclight-intel"` in the prod root's gitignored `terraform.tfvars`; `github_org` has no default, so the two roots drifted silently. Consider giving it a default or a validation in the deployment-model work. | IAM reads after apply | Overcast | Closed |
| DR-9 | Removing an ECS capacity provider together with its `aws_ecs_cluster_capacity_providers` entry in one change stalls: Terraform deletes the provider before updating the association. Next time, apply the association change first or expect to dissociate by hand. The prod ALB also carried a hand-made listener rule outside Terraform; audit prod listeners for other manual rules before the next prod change. | 2026-10-21 applies | Overcast | Next capacity-provider or prod ALB change |
| DR-10 | **JWKS over TLS, now a staging item.** ShuttleForge `SECURITY.md` §5.6 requires its JWKS fetch over TLS wherever real operational material is present. **Owner ruling 2026-11-10** (SF-D-0261 addendum, SF `r6-release-records` `0c13c90`): with no production in v1, that is staging. Today's plain-HTTP Core path inside the VPC (M-7) is accepted only for SF.11 Stages A and B (fixture data). **Before SF.11 Stage C entry** (first live provider credential reaching SF), three changes:<br>(1) Core serves its internal JWKS over TLS and hands over its CA certificate (Core).<br>(2) `SHUTTLEFORGE_CORE_JWKS_URL` moves to `https://`.<br>(3) SF's task gets a CA bundle (public roots plus Core's CA, built like SF's local `config/ca-bundle.pem`) with `SSL_CERT_FILE` pointing at it. A bundle of Core's CA alone breaks SF's other outbound HTTPS.<br>Overcast owns (2) and (3), and the security-group pair if Core's TLS port is not 8000. **Spec first** (INV-005): Fargate cannot bind-mount a host file, so how the bundle is placed (an init container writing a shared volume, an image-provided file, or EFS), where the public roots come from and how they stay current, and where Core's CA certificate lives (public, so SSM is fine) are open. SF needs no code change.<br>**Owner chose option A, 2026-11-10** (first-hand, in Overcast's session, on Overcast's recommendation). The choice is an internal HTTPS load balancer with a public ACM certificate in front of Core; the last hop to Core stays plain HTTP inside the VPC. That supersedes (1) and (3): Core needs no TLS work (subject to spec point (c)), and no trust bundle is needed, because SF's httpx client trusts public roots. Overcast work, **spec first**:<br>- a new internal load balancer (both existing ALBs are internet-facing);<br>- a name under `*.staging.arclight-complex.net`, already covered by the issued wildcard certificate;<br>- security-group pairs: SF to the load balancer on 443, and the load balancer to Core on 8000;<br>- `SHUTTLEFORGE_CORE_JWKS_URL` moved to `https://`.<br>Spec points:<br>- (a) Place it in the public subnets `10.0.1.0/24` and `10.0.2.0/24`, which hold only the ALB and NAT network interfaces. Core's trusted-proxy list (H1b) then needs no change, and SF and NF tasks still cannot forge `X-Forwarded-For`. In the app subnets they could.<br>- (b) DNS: a DNS-only Cloudflare record, or a private-zone record.<br>- (c) Core's handling of the new Host name.<br>- (d) The health check path.<br>- (e) NF's `CORE_URL` and JWKS URL, if Complex's TLS-to-Core platform rule is adopted. | SF manifest rev 3 (`d031251`); SF `DEPLOYMENT_MANIFEST.md` at `0c13c90` l.250-266; owner choice 2026-11-10 | Overcast | Before SF.11 Stage C entry |
| DR-11 | **CLOSED 2026-11-09 (O-016)**: the hand-made duplicate prod listener rules (ShuttleForge 2, Core 3) were deleted by ARN, and Terraform's own core/shuttleforge rules and target groups went with the prod reduction. The prod HTTPS listener holds only Backstage's rule 100 and the default. | `aws elbv2 describe-rules`, 2026-11-09 | Overcast | Closed |
| DR-12 | Backstage routes source traffic through its own proxy setting to three fixed endpoints (O-012 item 2, launch). Moving it to ShuttleForge leases and narrowing the host's egress to ShuttleForge needs ShuttleForge in the **prod** VPC, where Backstage runs; ShuttleForge is planned for staging only. That needs prod Core and DR-10, and the staging-JWKS condition is met (key rotated and retired 2026-10-23; containment complete). Also recorded: the owner accepted shipping Backstage's migration-002 proxy credentials in the first private ECR images and rotating later ("accepted, we will rotate later", 2026-10-22; Backstage register B14). | Owner, 2026-10-22 | Overcast + ShuttleForge + Core | When ShuttleForge's prod deployment is planned |
| DR-13 | **CLOSED 2026-10-24 (D-075 / O-015, applied on staging)**: no expiry (Deep Archive for objects of 128 KB or more after 90 days), log file validation, multi-region trail, Object Lock governance 365 days; existing versions locked until 2027-10-24 (retrofit complete 2026-10-24 04:39Z, 120,294 versions). Older logs are noncurrent versions: see `docs/runbooks/cloudtrail-log-protection.md`. | Complex D-059 §6 question, owner ruling D-075 | Overcast | The D-059 §6 CloudTrail posture holds. (V-1 completed 2026-10-24, which lifted the D-059 §9 hold on real material in staging.) |
| DR-14 | `arclight-overcast`, the infrastructure repository, is **public**: job logs, PR comments and artifacts are world-readable, and the code exposes the account ID, network layout and runbooks (no secret values: INV-004). The owner believes there was a reason, possibly Cloudflare Pages / the `gh-pages` branch for arclightlabs.io, or free Actions minutes; keep it public for now. CI already posts plan summaries only. | Owner, 2026-10-23 | Owner + Overcast | Work through later: find what depends on public visibility, decide, and if it goes private, budget its Actions minutes |
| DR-15 | **APPLIED 2026-11-09 21:07Z (owner's go)** (owner chose open egress for staging): `aws_security_group_rule.sf_provider_egress` allows the ShuttleForge group outbound TCP to any address and port through the NAT. Earlier analysis: ShuttleForge's dataplane dials arbitrary internet TCP: provider gateways (`brd.superproxy.io:44445`, `pr.oxylabs.io:7777`, per-account hosts), Proxy-Cheap endpoints from its API, health-check probes to every endpoint, and `direct` routing to arbitrary targets. The staging SF group allows only 443 (any), RDS 5432 and Core 8000. The first image needs no more: no live provider credential before fixture-only restore evidence (SF-D-0261 item 7, SF-D-0210). | SF code at `ad2668b` (`brightdata.py:56-58`, `oxylabs.py:42`, `health_checker.py:84-98`, `routing.py:600`) | Overcast + SF + owner | Before the first live provider credential on staging: decide the egress model (open egress, NAT + allowlist, or a forward proxy) |
| DR-16 | **Shell APPLIED 2026-11-09 21:07Z (owner's go); value and binding pending the reviewed policy**: the empty shell `arclight/<env>/shuttleforge/policy-yaml-b64`, and the toggle `shuttleforge_policy_enabled` (default false), which binds it as `SHUTTLEFORGE_POLICY_YAML_B64` once the owner has written base64(YAML). Earlier analysis: ShuttleForge's staging policy is not delivered: without `SHUTTLEFORGE_POLICY_YAML_B64` the image installs its deny-by-default policy (no leases granted). The reviewed policy comes from the SF operator; it names principals, pools and lanes, so it does not belong in this public repository (DR-14) as plain text. SF (2026-10-29): the reviewed YAML lives in SF's private repository and follows enrollment and live credentials; deny-by-default is intended until then. The owner sets `SHUTTLEFORGE_POLICY_YAML_B64` out of band (SSM SecureString or an S3 `environmentFiles` object); this repository carries only the reference, plus the execution-role read it needs. The SF `core-client-secret` shell also has no consumer (SF v1); remove it or keep it for SF.10. | SF manifest `126a679` (policy section); SF answers 2026-10-29 | Overcast + SF | When SF supplies the reviewed staging policy, before the first lease is expected to succeed |
| DR-17 | Bootstrap tooling drift.<br>(a) `build-and-push-image.yml` cannot push: the CI role it assumes has only `ecs-deploy` and `terraform-state`, so dbbootstrap images are pushed by an administrator.<br>(b) `dbverify-svc` is broken: `verify-service` requires `PODBAY_DATABASE_URL`, unbound since O-011. Its ShuttleForge check also cannot pass once `db-url` is the DML-only `postgresql+asyncpg://` URL (psql cannot parse it, and the role cannot `CREATE`).<br>(c) The CI deploy role may pass any `arclight-ecs-*-staging` role and register task definitions, so it can obtain any service secret through ECS injection, now including the SF schema-owner URL, and with O-013 the NF execution roles (`arclight-ecs-exec-nerfherder-*-staging`) too. This is inherent to a deploy role; it bounds what the `main` / `staging` OIDC trust is worth.<br>(d) **Platform divergence (alignment 2026-11-10):** the `bootstrap` mode still creates Podbay's database and role and loops over `podbay` (`services/dbbootstrap/bootstrap.sql`, `entrypoint.sh` l.13-16, 34, 44), and `podbay_staging` remains on RDS, although Podbay is deferred to v2 (D-071). Nothing runs `bootstrap` today; it would also reset every service password. | Review of the SF substrate PR, 2026-10-29; IAM reads; alignment pass 2026-11-10 | Overcast | (a)/(b)/(d): the next dbbootstrap change. (c): deployment-model work (DR-1) |
| DR-19 | **CLOSED 2026-11-09 (O-016)**: the prod substrate is reduced to what Backstage runs on (VPC, NAT, endpoints, ALB, alarm topic). The RDS instance was removed with final snapshot `arclight-prod-final-fcf44ee8`, along with the empty ECS cluster, secrets, roles and dbbootstrap tasks. Saving about $72/month. **Owner: confirm the AWS email for the `arclight-prod-alarms` subscription**; until then Backstage's alarms reach no one. | O-016; PR #62 | Owner (email) / Overcast | Closed once the subscription shows confirmed |
| DR-20 | Nerfherder's "ShuttleForge is the only route" (`NERFHERDER_EGRESS_MODE=sf_required`) is enforced in NF's configuration, not the network. NF's group allows 443 to any address through the NAT, for Secrets Manager, ECR, logs and S3. NF's manifest accepts this (line 180). Tightening it means interface endpoints for Secrets Manager and STS in staging, then dropping the open 443. | Review of PR #64, 2026-11-09 | Overcast + NF | When staging gains interface endpoints for those services, or before any NF deployment beyond staging |
| DR-21 | **No origin protection beyond the ALB security group.** The staging ALB admits Cloudflare's ranges, which every Cloudflare customer shares. A zone pointed at the ALB from another account reaches Core and ShuttleForge and skips the `*.staging` Access app. The 443 listener has no mTLS, rules match the host header only, and authenticated origin pulls are off. **Owner decision 2026-11-10: client certificates**, meaning zone-level authenticated origin pulls with our own certificate and ALB mTLS verify mode. Spec first: trust store, certificate custody, rotation, cutover order. Needs Cloudflare SSL and Certificates write access, and Terraform for Cloudflare (branch `cloudflare-adoption`). The same token can't read Managed Transforms or Transform Rules (H1b.6, unverified). | Core hardening H1b receipt, 2026-11-10 | Overcast | Now: spec, then plan, then the owner's go |
| DR-18 | **ShuttleForge first-admission allowance, temporary.** `deploy-service.yml` accepts `/ready` `degraded` for `shuttleforge` only when `/ready/detail` passes `scripts/sf-first-admission.jq`: exactly the pinned check set, all `ok` except `snapshot` = `warn` "snapshot has no usable config or endpoint inventory". The pinned set is SF's r6 list, confirmed 2026-11-10 against r6 code `55a2d20` (`ready.py` unchanged since r5's `5c6d617`) and SF's verbatim r6 capture. It is identical to r5 and r4. A stale set fails closed. | Complex PR #20 (§3), owner C7 ruling 2026-10-29, SF PR #34 `a3a5da8`, SF r5 notice 2026-11-10 | Overcast | Remove the allowance and the jq file once SF provider inventory exists: plain `ready` is the gate after that. Re-pin if a later SF release changes its check set |
| DR-22 | **Runbook drift (non-platform), found in the 2026-11-10 alignment pass.** `bootstrap-databases.md`: pins `:v5` (the shared family runs `v1-9264f1a`, NF's `v1-4a9ce79`), step 6 writes the owner URL into `shuttleforge/db-url` (superseded by the migration-URL split), Podbay steps. `restore-rds.md`: snapshot list misses `…-p8-20261029` and `…-s054-20261102`; "only core is running" predates the SF and NF services at 0/0; a Podbay leaf. `rotate-secrets.md`: a Podbay leaf, no migration-URL split. `initial-bootstrap.md`: ECR list still has the Podbay repositories; says plan and apply are both broken. | Alignment inventory, 2026-11-10 | Overcast | Before the next use of each runbook, and before N-G3 / SF G3 |
| DR-23 | **CLOSED 2026-11-10 (Complex ruling): not a divergence; keep the Access headers.** Complex: the rule means module credentials, ones the module itself checks. An edge-gate token consumed by Cloudflare is outside it (D-074 §6). Conditions: the token stays scoped to reaching the edge with no module authority behind it, and `/ready` must pass on its own merits. Complex will clarify the §3 sentence in its next records batch. Original: **Possible platform divergence: credentials on deploy verification.** TESTING_PROTOCOLS §3 (amended 2026-10-29): "Deploy verification must never present a credential." `deploy-service.yml` (l.211-218) sends `CF-Access-Client-Id` / `CF-Access-Client-Secret` on its `/ready` check, because `*.staging` sits behind Cloudflare Access. Overcast reads the rule as module credentials: Cloudflare's edge consumes the Access token, and D-074 §6 makes the edge gate defense in depth only. Unconfirmed; asked Complex 2026-11-10. | TESTING_PROTOCOLS §3 at `48c1715`; `deploy-service.yml` | Complex (reading), Overcast (change) | Complex's answer. If edge credentials are covered, verification moves to an in-VPC probe (the N-G4 pattern) |

## Core staging test-token incident — 2026-10-22 (CLOSED 2026-10-23T01:58:52Z)

Core reported that staging Core's `POST /api/admin/test-token` (enabled when `CORE_ENVIRONMENT=staging`) mints
tokens signed with the staging key without authentication; Core is removing it in a release. Overcast, at Core's
request with the owner's approval of the fix:

- **Staging ALB rule** (hand-made, not in Terraform): HTTPS listener priority 1, host `core.staging.arclight-complex.net`
  and path `/api/admin/test-token` or `/api/admin/test-token/*` → fixed 403, created 06:14:40Z, tagged
  `Name=core-test-token-block`, `Remove=after-core-fix-live`. Core's forward rule moved from priority 1 to 10 to sit
  behind it (the ALB module leaves priority unset, so Terraform does not revert it). ALB path patterns cannot contain
  `%`, so percent-encoded variants are not blocked here.
- **Cloudflare**: deployed by the owner 2026-10-22 (Overcast's token has no WAF permission). Custom rule
  "Block Core staging test-token"
  `(http.host eq "core.staging.arclight-complex.net" and starts_with(lower(http.request.uri.path), "/api/admin/test-token"))`
  → Block, evaluated on the normalized path, so it also covers the percent-encoded variants the ALB rule cannot match. The Access application on `*.staging` (Team emails,
  Cloudflare login, `staging-automation` service token) already stops unauthenticated internet requests.
- **Usage**: `/arclight/staging/core` keeps 30 days (oldest event 2026-09-22T06:21:38Z); 249,028 records scanned,
  0 requests to the path. Before 2026-09-22 is unknowable from logs; no user agent is logged anywhere.
- **Hold**: no new ingress to staging Core:8000 (NF or SF wiring) until Core confirms the fixed release is live.
  Today Core's group admits only the staging ALB.
- **Fix live 2026-10-22 (Core S-046, owner's go)**: revision 12 = revision 10 with only the image changed (asserted),
  `arclight/core:v2-e3eb5c9`; rolling update 20:24:45Z, stable 20:27:23Z, rollout COMPLETED, target healthy. Identity proof:
  the running task reports `sha256:9ad537c8e5a780167682f733c9a3427d81cfe43364af48b7eeaf33bcfd4edb50` (the image index) and
  revision 12 sets `CORE_ENVIRONMENT=staging`. Canary `GET /auth/callback?code=s046canary&state=s046canary` through Access
  (20:27:53Z, 400): Core logged `"GET /auth/callback HTTP/1.1" 400` with no query string; 0 log events contain the canary.
  The ALB 403 rule was deleted at 20:29:10Z; Core's rule stays at priority 10. The Cloudflare rule stays as defence in
  depth (Core's recommendation). The Core:8000 ingress hold is lifted. **Open**: until Core's S-047 ships and the owner
  rotates and retires the staging signing key, ShuttleForge must not trust staging's JWKS (NF calling Core is unaffected).
- **S-047/S-048 live 2026-10-23 (owner's go)**: revision 13 = revision 12 with only the image changed (every field walked), `arclight/core@sha256:e5028c190ec373a300caa14472ffc940e84dcf22615ed9a8efd8049bd7ce5f2f` (`v2-933caf7`, arclight-core `933caf7`); update-service 00:35:12Z, steady state 00:37:56Z, task `ad9786aa8f6645e0903970ba4b165bd2`, target healthy. Checks: running digest = the index; `POST /api/signing-keys/key_probe/retire` without credentials 401 through the edge; `/ready` 200. Rollback: revision 12. Local `core_image_tag` pin moved to `v2-933caf7`.
- **Phase A authority inventory (S-048) 2026-10-23**: one-off task `1f3230f4e49b481fbddcdac113a4e7a1` on revision 13, `--since 2026-07-09T19:58:52Z`, exit 0, `RESULT: OK`, nothing truncated; full 52-line output sent to Core. The one signing key `key_USbyrBeZ-KpF_o2Z` was created 2026-07-02T08:19:52Z, seconds before the 08:20 automated snapshot that the aborted 07-02 V-1 restore used (DR-13), so that copy held its encrypted form. **Next**: Core and the owner reconcile the rows; the owner rotates and retires the key (S-047); then phase B, the same run again. ShuttleForge still must not trust staging's JWKS until then.
- **Phase B and closure 2026-10-23**: the owner rotated (`key_2m50PYhbwsk6ijk5` active 01:40:27Z) and retired `key_USbyrBeZ-KpF_o2Z` (01:57:23Z, grace 720 s, inside D-074 §3's window). Phase B task `82c8a6098ff8438d831a1626f2aa8ca9` on revision 13: exit 0, `RESULT: OK`, only the expected changes (two key rows, rotate/retire audit by the owner, three owner sign-ins that Core reconciled to the owner's script). Independent JWKS read through Access (origin, not cache): exactly `["key_2m50PYhbwsk6ijk5"]`. **Core declared containment complete at 2026-10-23T01:58:52Z** (closure record revision 3) and lifted ShuttleForge's JWKS hold; SF passed the all-clear the same day before any SF staging task trusts that URL. Revision 13 (`v2-933caf7`) is the running baseline. The Cloudflare block rule stays as defence in depth.
- **S-049 2026-10-23** (revision 14, `v2-8610b46`): `/ready/detail` requires a human, MFA-gated admin; Overcast verifies with `/ready` plus the running digest (#50).
- **Phase 8 live 2026-10-29 (owner's go)**: revision 15 = revision 14 with only the image changed, `arclight/core@sha256:cdb317abacbf03269124c76826411a6bde4fe6935f3a6b192e06a35261fd96d7` (`v2-570285c`), all feature flags off. Preflight PASS on `p7g1`; manual snapshot `arclight-staging-pre-core-p8-20261029`; migration `p7g1_grant_expiry_notif -> sf10p2_permissions` (4 permission rows); preflight PASS on `sf10p2`; deployment `ecs-svc/7986227536126687347` steady 14:56:48Z; `/ready` and `/health` 200; S-048 inventory: 74 permissions, `RESULT: OK`. **Rollback = service update to revision 14 only; never run revision 14's migrate or preflight against this database.** CI `CORE_IMAGE_TAG` = `v2-570285c`.
- **C11 old-image cleanup 2026-10-29 15:09Z (owner's "yes, C11")**: 21 `arclight/core` artifacts deleted by digest (7 indexes, then their 14 children; no failures); revisions :3 :5 :7 :9 :10 :11 :12 deregistered. Kept: revisions :8 (Terraform's), :13, :14, :15 and the three newest images with their children (`v2-933caf7`, `v2-8610b46`, `v2-570285c`, 9 artifacts). Service unchanged on :15, HEALTHY. Core verified the hashed receipt (0 mismatches) and recorded it at Core `3f535ad` (Core PR #23).
- **S-054 / D-076 live 2026-11-02 (owner's "hit it")**: revision 16 = revision 15 with only the image changed (every field walked), `arclight/core@sha256:de68ac95b4065e7381a628ab6f3f109383d7083ef6de91831557a4b52388ef01` (`v2-6add49d`, Core master `6281397`).
  - Manual snapshot `arclight-staging-pre-core-s054-20261102` (available 20:59:48Z).
  - Preflight PASS on `sf10p2_permissions`, including [6]: 0 operator principals.
  - Migration `sf10p2_permissions -> d076a_retire_operator` (task `c233294b…`, exit 0).
  - Preflight PASS on `d076a_retire_operator`.
  - CHECKs: `ck_audit_actor_type` gains `external_client` and keeps `operator`; `ck_principal_type` drops `operator`.
  - Rolling update from 21:03:15Z; task `90605148…` on the index digest, HEALTHY; revision 15 drained at 21:05:40.290Z; `/ready` and `/health` 200.
  - Inventory: head `d076a_retire_operator`, `RESULT: OK`.
  - **Rollback = service update to revision 15 only**; never run revision 15's migrate or preflight against this database.
  - CI `CORE_IMAGE_TAG` and the local pin are `v2-6add49d`. Evidence: `evidence/s054-*.hashed.txt`, receipt sent to Core.
- **Core hardening H1b: trusted proxies narrowed 2026-11-10 (owner's "yes, narrow")**.
  - Revision 17 = revision 16 with only `CORE_TRUSTED_PROXY_CIDRS` changed: `10.0.0.0/16` replaced by the ALB's subnets `10.0.1.0/24` and `10.0.2.0/24`, Cloudflare's 15 + 7 ranges unchanged. Every field was walked; the only other difference is the AWS-computed `compatibilities` order.
  - Why: the whole VPC let ShuttleForge and Nerfherder, which call Core:8000 directly from the private app subnets, choose their rate-limit key with a forged `X-Forwarded-For`. Only the three requester-managed ENIs (two ALB, one NAT) live in the ALB's subnets.
  - Rolling update from 03:38:31Z, stable 03:41:06Z; task `ca825747…` HEALTHY, target healthy; `/ready` and `/health` 200 through Cloudflare and Access; 0 error lines in the new task's log.
  - The Terraform template renders the same value from `module.vpc.public_subnet_cidrs` (`terraform/envs/staging/main.tf`). **Rollback = service update to revision 16.**
  - The same pass (H6) found scan-on-push already on for all seven repositories, with v2-6add49d scanned at push: 0 critical, 6 high. A registry-level rule filtered to `arclight/core` would set the other six repositories to manual, so none was added. Owner: rescan on demand, not now.
- **Core S-055 live 2026-11-10 (owner's "Hit it")**: revision 18 = revision 17 with only the image changed, `arclight/core@sha256:2393682f3ec93121d7898abdd73680be570382440b66c4c7bd6fe3f5e424a777` (`v2-08de4e6`, OCI index; code `08de4e6`). The field walk shows only `.containerDefinitions[0].image` differs, so revision 17's narrowed `CORE_TRUSTED_PROXY_CIDRS` is kept. No migration.
  - Preflight PASS on `d076a_retire_operator` (task `6ffa2b12…`, build `08de4e6`, checks [1]-[6] 0 rows).
  - Rolling update 09:31:02Z, deployment completed 09:33:34Z: task `c728d03d…` HEALTHY on the index digest, revision 17's task stopped and drained, `/ready` 200 `ready`.
  - Body cap (Overcast's check): a POST to `/oauth/token` through Cloudflare and Access with a declared 2,097,152-byte body, `Expect` suppressed and no Authorization, got **413** in Core's envelope (`payload_too_large`, `request_id` matching `x-request-id`). A second POST with `Expect: 100-continue` also got 413; its `100 Continue` came from Cloudflare's edge. CloudWatch 09:34Z: `HTTPCode_Target_4XX_Count` 2, `RequestCount` 3, ELB 502 / 5XX and target 5XX none. No RST or 502.
  - ECR scan-on-push (amd64 child `sha256:1aad78cb…`): 0 critical, 2 high, 9 medium, 3 low (H6 baseline on `v2-6add49d`: 0 / 6 / 15 / 4).
  - Pins moved to `v2-08de4e6`: local `core_image_tag` and repository variable `CORE_IMAGE_TAG`. Hashed receipt sent to Core. Pending: the owner's Entra login, for Core's `token.issued` check after 09:33:34Z. **Rollback = service update to revision 17.**

## Applied 2026-10-21 — Podbay removal + Core deploy prerequisites (PR #18)

Applied by claude-main with the owner's "go" (john-admin, local), from the branch before merge.

| Root | Result | Window (UTC) | Interventions |
|---|---|---|---|
| staging | 6 added, 6 changed, 74 destroyed; post-apply plan: no changes | 17:52:05 to 18:08:09 | Capacity provider deletion stalled 15 min (Terraform ordered the provider delete before the cluster association update); resolved by `put-cluster-capacity-providers` to the intended end state and re-issuing the delete. |
| prod | 7 added, 6 changed, 31 destroyed over three applies; post-apply plan: no changes | 17:52:28 to 18:11:58 | Same capacity-provider stall; then the Podbay target group was held by a non-Terraform listener rule for `podbay.arclight-complex.net` (manual leftover), deleted by hand. |

Pre-steps executed first: both Podbay ECR repositories force-deleted (12 images each); unmanaged instance `coturn-probe-disposable` (`i-07b8dc451e38bf204`) terminated.

Verified live after apply: the only ECS service is `arclight-core-staging`, still on revision 7; revision **8** is registered with `CORE_TRUSTED_PROXY_CIDRS` (VPC + Cloudflare ranges) and the `/health` container check and is **not deployed** (the service ignores task_definition; Core's tranche C deploys it). Clusters list `FARGATE` and `FARGATE_SPOT` only; coturn instance terminated and EIP `52.72.36.174` released; workspace subnets and Podbay security groups gone; Podbay secret shells scheduled for deletion (recovery window); `core-client-secret` shells exist for nerfherder and shuttleforge in both environments (no values); core and shuttleforge target groups at 30 s deregistration delay. Left in place: `podbay_staging` database and role. Correction to PR #18's commit message: moving the container check to `/health` removes one ECS replacement trigger, not both; ECS still replaces a task that fails the ALB `/ready` check (Core's Astra review, accepted).

## Next actions

Updated 2026-11-10. Each state change waits on the owner's go, given first-hand.

1. **Core S-055, revision 18**: live 2026-11-10 (record above). Pending: the owner's Entra login for Core's issuance check.
2. **Nerfherder N-G3**: waits on NF's image push; then register the migrate family on its digest, run it, and re-run `nf-app-role`.
3. **ShuttleForge G3**: waits on SF's reviewed SF.11 plan. The first staging image is the line release current at that review (r6, `55a2d20`, today); the first-admission pin is confirmed for r6. G3's push record gives the tag, ECR digest and media type, and the amd64 child digest.
4. **Cloudflare Terraform**: spec an isolated root (provider v5) adopting the arclight-complex.net staging records and the Access app, then DR-21 origin client certificates.
5. **Owner**: confirm the `arclight-prod-alarms` subscription email (DR-19); decide whether to take a live `SHOW max_connections` reading (needs a one-off task definition).
6. Keep 7G scheduling blocked on Core/Complex's authority decision, and 7F blocked on the custody amendment.

## Corporate management evidence — 2026-09-30

The user requested Microsoft Entra management access and Terraform ownership before further infrastructure work. Azure CLI/Graph access is verified for `ANS Analytics LLC`, tenant `27564b9c-b516-4bc4-9aa5-5692a38a1116`, administrator `john@arclightlabs.io`, default domain `ansanalytics.com`. Entra supersedes the historical Google Workspace workforce-IdP direction below.

The dedicated corporate Terraform backend and management identity were provisioned under `terraform/corporate/`; authenticated post-apply plans returned no changes on that date. The user-approved `Application.ReadWrite.OwnedBy` grant was verified, and a certificate-authenticated application session successfully read 7 application registrations and 364 service principals. Existing Core applications and staging/prod infrastructure were outside this bootstrap; automation ownership/imports and writes to existing applications remain subsequent work. See [service registry](service_registry.md), [design](specs/entra-management.md), and [runbook](runbooks/manage-entra.md) for dated evidence and scope. The deployment snapshot below has not been refreshed by this identity or documentation work.

## Historical deployment snapshot — 2026-07-10

Recorded phase: Phase 5 (Podbay Deploy), in progress at `5f74a55`. All live-state language, image tags, resource counts and external blockers in this section describe that July session. Recheck the relevant service before relying on them operationally. The Google Workspace workforce-IdP direction is superseded by Entra; the old Core Phase 6A custody guidance is withdrawn below and in its source memo.

> **2026-10-21**: Podbay is withdrawn (O-011). Every Podbay, workspace and coturn line in this snapshot is historical.
>
> **2026-11-10**: Phase 3 (Prod Environment) is parked for v1 (no production environment, owner ruling 2026-11-09) and was reduced by O-016 to Backstage's substrate; the prod RDS and databases are gone. The ShuttleForge PostgreSQL blocker closed with SF.9 (2026-09-30).

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
