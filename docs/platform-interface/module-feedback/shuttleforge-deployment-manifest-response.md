# Overcast receipt — ShuttleForge deployment manifest (v1 exit item 4)

> **Review completed**: 2026-10-20 | **Reviewer**: claude-main (Overcast)
> **Disposition**: **ACCEPT-WITH-CHANGES**. Acceptance does not schedule a deploy; SF.11 stays deferred until the owner resumes cloud work.
> **Scope**: Source/document review plus read-only AWS reads (IAM, ECR, RDS, Secrets Manager metadata). No apply, push, secret population, migration or traffic.

## Pins

| Input | Pin |
|---|---|
| ShuttleForge manifest | `arclight-shuttleforge@f887635:docs/DEPLOYMENT_MANIFEST.md` (unchanged since `31a9904`, 2026-09-26; verified by diff) |
| ShuttleForge v1 definition | `arclight-shuttleforge@f887635:docs/v1/v1_definition.md` §8 exit gate (l.443–454), §9.2 residues R3–R6 (l.469–476) |
| ShuttleForge source checked | `scripts/entrypoint.sh`, `Dockerfile`, `shuttleforge/startup.py`, `shuttleforge/config.py`, `shuttleforge/api/ready.py`, `shuttleforge/main.py`, `docker/compose.shuttleforge.yml`, `docs/PHASE_PLANS/phase_SF9_spec_s10_s11.md`, `phase_SF9_spec_s13_s14_s15.md`, `tests/integration/test_brightdata_live.py`, all at `f887635` |
| Platform baseline | `arclight-complex@c808bf2`: `platform/DECISIONS.md` D-059 position 6 (l.1141) and §9 (l.1149); `docs/proposals/production-infrastructure-spec.md` (D-056) l.92, 151, 259; `platform/boundary-charters/charter-overcast.md` l.90–100, 166 |
| Overcast source | `main` at `5aeac72` |
| Live AWS reads (2026-10-20, `john-admin`, read-only) | IAM role listing and two trust policies; `arclight/shuttleforge` ECR image count; `arclight-staging` RDS attributes; `arclight/staging/shuttleforge/*` secret names |

Other-repo citations are `file:line` at the pins above. Overcast citations are at `5aeac72`.

## 1. Does the manifest give Overcast everything needed to deploy without asking SF?

| Concern | Result | Evidence |
|---|---|---|
| Three-port shape (9000 ALB; 9050/9100 Cloud Map) | PASS | Manifest l.66–75, 85–88. Overcast: `services/shuttleforge/task-definition.json.tpl:14–18` maps all three; `terraform/modules/alb/variables.tf:54–57` routes 9000 only with `/ready`. Cloud Map publishes A records (`terraform/modules/ecs-service-fargate/main.tf:21–35`), so fixed ports resolve by name. |
| Six secrets | WARN, manifest defect **M-1** | Manifest l.34–40, 99–111 declares six bindings including `SHUTTLEFORGE_CORE_JWKS_URL` and says it "retains D-056's secret classification" (l.101). D-056 at `c808bf2` is self-contradictory: l.151 counts it among "Secrets (6)", l.259 says SSM Parameter Store, "not a secret". Overcast holds five shells (live listing; `terraform/modules/secrets/main.tf:14–18`) and injects the JWKS URL as a derived environment value (`task-definition.json.tpl:29`). The value is Overcast's own internal DNS plus a fixed path, not operator-supplied material; populating it "outside Terraform state" (l.100) would create a hand-maintained copy of a derived string. See change M-1. |
| Singleton constraint and process-local state | PASS as declaration | Manifest l.76–79, 90–95; SF spec `phase_SF9_spec_s10_s11.md:180–213` (AC-10.8a: Overcast owns the ECS rollout config). Overcast obligation **O-2** below. |
| Migration-only invocation | PASS | Manifest l.26, 146–151. Verified: `scripts/entrypoint.sh:12–20` handles `--migrate-only`, rejects extra args, forces `SKIP_MIGRATIONS=false` and `REQUIRE_PG=true`; `Dockerfile:31` sets the script as `ENTRYPOINT`, so the ECS `command` override is `["--migrate-only"]` exactly as l.150 requires. Overcast already runs one-off tasks this way (`terraform/envs/staging/main.tf:392`, `:527`). |
| Image identity by digest | WARN, Overcast obligation **O-3** | Manifest l.143–145; SF AC-13.3 (`phase_SF9_spec_s13_s14_s15.md:74–77`). `Dockerfile:18–19` bakes a 40-char commit, verified. Overcast's pipeline deploys by tag (`.github/workflows/deploy-service.yml`, "Update image in task definition" step) and ECR tags are immutable (`terraform/modules/ecr/main.tf:5`), which is a weaker identity than a digest. ECS accepts `repo@sha256:...`; the workflow needs a digest input. `arclight/shuttleforge` holds 0 images today. |
| Restart / rolling-overlap rule | PASS as declaration | Manifest l.78, 90–95, 152–154. See O-2. |
| Readiness and liveness contract | PASS with one defect **M-3** | `/ready` at `shuttleforge/api/ready.py:496`, `/health` at `shuttleforge/main.py:1601`; ALB probes `/ready` (`alb/variables.tf:56`). Manifest `start_period_seconds: 30` (l.17) contradicts SF's own supervisor, which allows 110 s to readiness (`shuttleforge/startup.py:3–4, 91`). Overcast's template already uses 60 s (`task-definition.json.tpl:27`) and will set 120 s plus a matching ECS health-check grace period. The manifest should state the number it means. |
| Internal DNS name and transport endpoint | FAIL, manifest defect **M-4** | Manifest l.33 and l.123–124 hardcode `shuttleforge.staging.arclight.local`. Overcast's Cloud Map namespace is `staging.internal.arclight-complex.net` (`terraform/envs/staging/main.tf:96, 143, 919`; `terraform/modules/ecs-cluster/main.tf:12–13`). The SSM parameter Overcast already publishes for SF's internal URL is built from that namespace (`terraform/modules/secrets/main.tf:55`). The manifest should declare the Cloud Map service name (`shuttleforge`) and leave the namespace to Overcast. Overcast's own SF template carries the same stale suffix (O-4). |
| Database roles and secret references | WARN, manifest defect **M-2** | Manifest l.26–28, 113–118 wants a migration role with DDL and a runtime DML-only role, resolved through "separate role-specific versions/references of the DB secret". Secrets Manager versions are not a role selector; this needs two secret leaves. Overcast's bootstrap creates one role, `shuttleforge_staging`, owning database `shuttleforge_staging` (`services/dbbootstrap/bootstrap.sql:12–14, 32–33`), and one leaf, `db-url`. Role names must follow INV-001 (environment-suffixed), so the manifest's `shuttleforge_owner` / `shuttleforge_app` are read as logical labels. |
| Policy file | FAIL, manifest defect **M-5** | Manifest l.127–129: "Mount the reviewed environment policy read-only at `/data/policy.yaml`". Fargate has no host bind mounts; the compose fragment's `./policy.yaml:/data/policy.yaml:ro` (`docker/compose.shuttleforge.yml:30`) does not translate. SF requires the file when lease auth is on (`shuttleforge/main.py:874`). The manifest must pick a delivery mechanism and name who authors the "reviewed environment policy". |
| Parameters list versus code | WARN, manifest defect **M-6** | `shuttleforge/config.py:13` reads every `SHUTTLEFORGE_*` with an env prefix. Not in the manifest's parameter list (l.41–58): `SHUTTLEFORGE_INSTANCE_ID` (operator-supplied deployment label, `shuttleforge/db_config.py:95–99`), `SHUTTLEFORGE_ALLOW_ADMIN_PUBLIC` (`shuttleforge/main.py:860`), `SHUTTLEFORGE_ENABLE_WEBHOOKS` (default off, `shuttleforge/api/webhooks.py:5`), the DB pool and migration-lock knobs. `SHUTTLEFORGE_PROCESS_ROLE` is set by the entrypoint (`shuttleforge/startup.py:43`) and needs no Overcast action. The manifest should state which of these Overcast must set and which defaults stand. |
| Compute, ulimit, privileges | PASS | Manifest l.59–65, 80–82 are valid Fargate values; `nofile` 65536 already in the template (`task-definition.json.tpl:20`). Fargate ephemeral storage covers `/data/flows` and `/data/certs`; durable capture storage is explicitly deferred (l.131–132). |
| Database engine | PASS | Manifest requires PostgreSQL ≥16 (l.23–24); staging runs 16.13 (live read; `terraform/modules/rds-postgres/variables.tf:28–32`). `DB_TLS_MODE=require` (l.126) is supported; it does not verify the RDS CA. |

**Answer to Q1**: no. Overcast could not deploy from this manifest without asking SF about M-4 (which DNS name is authoritative), M-5 (how the policy file arrives and who writes it), M-2 (which secret leaf each task gets) and M-6 (which undeclared parameters matter). M-1 and M-3 are resolvable by Overcast choosing, but the manifest should say so.

## 2. Changes before Overcast would run it against staging

Manifest changes (SF owns):

- **M-1** JWKS URL: declare `SHUTTLEFORGE_CORE_JWKS_URL` as an Overcast-derived environment value (or SSM parameter), not an operator-populated secret. Either classification satisfies ECS; the point is that Overcast computes it and nobody hand-types it. If SF insists on Secrets Manager, say so and accept that Overcast writes the shell's value from Terraform outputs through an operator step, not from Terraform state.
- **M-2** Database access: name two secret leaves, `db-url` (runtime, DML-only role) and `db-url-migration` (owner role), and state the two logical roles. Overcast will map them to `shuttleforge_app_staging` and the existing `shuttleforge_staging` owner, add the runtime role and grants to `bootstrap.sql`, and bind each task to its own leaf.
- **M-3** Readiness budget: make `start_period_seconds` consistent with the supervisor's 110 s, or state that 30 s is the ALB target-group figure and the container grace is separate.
- **M-4** Internal DNS: replace the hardcoded `shuttleforge.staging.arclight.local` with "Cloud Map service `shuttleforge` in the Overcast-provided namespace" and define `SHUTTLEFORGE_TRANSPORT_ENDPOINT` as `http://<that name>:9050`.
- **M-5** Policy file: choose one of (a) Overcast provisions an EFS access point mounted at `/data`, (b) the image ships a default policy and the environment policy is delivered as an SSM parameter that the entrypoint writes to `SHUTTLEFORGE_POLICY_FILE` before serving, or (c) the reviewed policy is baked per environment at build. Name the author and review path for the policy content. Overcast recommends (b): no new storage service, and the policy becomes a versioned parameter.
- **M-6** Parameters: add `SHUTTLEFORGE_INSTANCE_ID` (with the value SF wants for staging, or "unset"), `SHUTTLEFORGE_ALLOW_ADMIN_PUBLIC`, and `SHUTTLEFORGE_ENABLE_WEBHOOKS` to the list with their staging values; confirm the pool and lock-timeout defaults stand.

Overcast changes (Overcast owns; tracked in Phase 4 of `docs/V1_ROADMAP.md` and the debt register):

- **O-1** Security-group ingress for 9050 and 9100 from the Podbay workspace security group. The generic Fargate module opens only `container_port` from the ALB (`terraform/modules/ecs-service-fargate/main.tf:44–54`); the dataplane rules are root-level additions like Podbay's (`terraform/envs/staging/main.tf:564–632`).
- **O-2** Singleton rollout. The module hardcodes `deployment_minimum_healthy_percent = 100` and `deployment_maximum_percent = 200` (`terraform/modules/ecs-service-fargate/main.tf:95–96`), which guarantees a second task during every deploy. SF needs 0 / 100 (stop before start) plus `desired_count = 1`. These become module variables with the current values as defaults, so Core and Podbay do not change. The interruption window is the old task's stop plus up to 110 s to readiness, and the ALB target group's default 300 s deregistration delay should be shortened for SF.
- **O-3** Digest-pinned deploys. `deploy-service.yml` gains an image-digest input (or resolves the digest from the verified tag and writes `repo@sha256:...` into the task definition) and records the digest in the deployment summary, so AC-13.3 can be met.
- **O-4** Template refresh. `services/shuttleforge/task-definition.json.tpl:29–31` still uses `.arclight.local`; `SHUTTLEFORGE_` prefixes replace the bare `CORE_*` names; the sixth binding and the migration task definition are added; `startPeriod` goes to 120 s.
- **O-5** Prod push-role trust drift (found in passing). `arclight-shuttleforge-ecr-push-prod` still trusts `repo:arclight-intel/arclight-shuttleforge`, the obsolete owner; staging correctly trusts `arclightintel-dev`. Not an SF concern, but it will block a prod image push later. Recorded as DR-8.

## 3. D-059 §6 prerequisite and residues R3–R6

**R3, Overcast attestation of D-059 §6 postures.** Correctly assigned to Overcast. The bar quoted in `v1_definition.md:473` is D-059 §9's rule (`platform/DECISIONS.md:1149`, "Hardening is a precondition, not a response"), and the postures are position 6 (`:1141`). Overcast **cannot attest today**. What source and live reads establish for staging:

| Posture (D-059 pos. 6) | Evidence | Status |
|---|---|---|
| RDS deletion protection | `terraform/modules/rds-postgres/main.tf:68`; live `DeletionProtection: true` | Met |
| Automated backups | `rds-postgres/variables.tf:45–48` default 7 days; live `BackupRetentionPeriod: 7` | Met |
| **Tested restore procedure** | Runbook exists (`docs/runbooks/restore-rds.md`); no dated execution anywhere in `docs/` | **Not met**. D-059 calls the V-1 staging restore drill a precondition. |
| CloudTrail log protection | `terraform/modules/observability/main.tf:75–135` (staging owns the trail, O-006) | Met in source; not re-read live |
| ALB restricted to Cloudflare ranges | `terraform/modules/alb/main.tf:19, 29` from `terraform/envs/staging/main.tf:46` (O-005) | Met in source; not re-read live |
| S3 versioning and lifecycle | Podbay export bucket `terraform/envs/staging/main.tf:838–884`; Terraform state bucket outside Terraform | Partially evidenced; no SF-owned bucket exists yet |
| Deliberate log retention | `terraform/modules/observability/variables.tf:22–25` default 30 days | Met in source |

The attestation requires the restore drill to be executed and recorded, and a live re-read of the other postures on the day. It belongs with SF.11's "fixture-only staging restore evidence" (manifest l.162–163), which is the same drill. Owner: Overcast. Nothing here has moved since 2026-09-30; the July deployment snapshot was never refreshed.

**R4, `SF_STAGING_*` credentials.** Correctly assigned "Principal + Overcast", with a split the register should make explicit. The six variables are integration-test inputs (`tests/integration/test_brightdata_live.py:20–25, 39–44`): `PROXY_URL` is Overcast's to supply (the Cloud Map name plus `:9050`); `LISTENER_USER/PASS` and `SHARED_USER/PASS` are listener configurations created through SF's own operator API; `EXPECTED_STATIC_IP` comes from the provider. Confirmed absent everywhere at `f887635` and in Overcast (no hits). Unchanged since 2026-09-30.

**R5, AWS/ECR credentials for image publish.** The assignment to the principal is stale. Overcast already provisions a GitHub OIDC push role per module (`terraform/modules/iam-github-oidc/main.tf:156–204`), and the live staging role `arclight-shuttleforge-ecr-push-staging` trusts `repo:arclightintel-dev/arclight-shuttleforge:ref:refs/heads/main`. SF's build workflow can assume it with no long-lived credentials. What the principal still owns is enabling that workflow in the SF repo. The prod twin is mis-trusted (O-5). Moved since 09-30: no, but the register should be corrected.

**R6, staging PostgreSQL and Secrets Manager paths.** Correctly Overcast. Database `shuttleforge_staging` and role exist from the July bootstrap; five shells exist live under `arclight/staging/shuttleforge/`. Values have never been populated. The sixth binding and the migration leaf wait on M-1 and M-2. Unchanged since 2026-09-30.

**R11 (for completeness).** The `CF_ACCESS_CLIENT_ID` / `CF_ACCESS_CLIENT_SECRET` pair SF found unreferenced in its `.env` is Overcast's Cloudflare Access service token for `*.staging.arclight-complex.net`; it is how anything outside the VPC reaches staging hostnames, including Overcast's post-deploy health check (`.github/workflows/deploy-service.yml`, "Verify health" step). It is not an SF code path and needs no SF gate.

## 4. Verdict

**ACCEPT-WITH-CHANGES.** The manifest is the right shape and its load-bearing claims about the image, entrypoint, supervisor and ports match SF source at the pin. It is not yet executable by Overcast without questions because of M-4, M-5, M-2 and M-6; M-1 and M-3 are consistency fixes. Overcast's side needs O-1 through O-4 before a staging run and O-5 before any prod push. None of this schedules a deploy. SF.11 remains deferred; the D-059 §6 attestation (R3) is not available until the staging restore drill is executed and recorded.

Overcast will re-review on the next manifest revision that addresses M-1 through M-6; a resubmission need only cite the new commit.
