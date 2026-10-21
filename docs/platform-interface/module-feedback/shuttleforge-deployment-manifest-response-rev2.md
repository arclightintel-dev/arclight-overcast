# Overcast receipt — ShuttleForge deployment manifest, revision 2

> **Review completed**: 2026-10-21 | **Reviewer**: claude-main (Overcast) | **Supersedes**: the 2026-10-20 receipt's M-1..M-6 dispositions; its O-items are restated below.
> **Disposition**: **ACCEPT-WITH-CHANGES**, narrowed to two wording amendments (M-7, M-8) and one answer Overcast needs (M-9). The six original defects are closed.
> **Scope**: source/document review and read-only AWS reads. No apply, deploy, image build, secret value or traffic.

## Pins

| Input | Pin |
|---|---|
| Resubmission | `arclight-shuttleforge@d5d34f5` (appliance/main, 2026-10-21); manifest revision 2 landed in `52b3175` (ancestor of `d5d34f5`, verified) |
| Release line the image builds from | `v1-operate` at `3290c54` (SF's note; branch present locally) |
| SF source checked at `d5d34f5` | `shuttleforge/config.py`, `shuttleforge/auth/jwks.py`, `shuttleforge/api/ready.py`, `shuttleforge/policy/materialize.py`, `scripts/entrypoint.sh`, `scripts/local_appliance_recovery.py` |
| Code parity `3290c54` vs `d5d34f5` | `startup.py`, `auth/jwks.py`, `policy/materialize.py`, `api/leases.py`, `scripts/entrypoint.sh`, `Dockerfile` identical; `config.py`, `db_config.py`, `api/ready.py`, `alembic/env.py` differ only by SF.10 additions absent on `v1-operate` (`sf10_*` settings and validator, `sf10_worker` readiness check, `required_tables`, migration-schema filters). Every revision-2 claim Overcast relies on holds on the release line. |
| Overcast | `main` at `6a507e0` (Podbay removed; Core prerequisites applied 2026-10-21) |
| AWS reference | ECS service quotas: **task definition size 64 KiB, not adjustable** (AWS General Reference, "Amazon ECS endpoints and quotas") |

## Disposition of the six original items

| Item | Manifest rev 2 | Verified against | Result |
|---|---|---|---|
| M-1 JWKS URL | Moved to `parameters[]` (l.51); five secret bindings (l.44–49, 117–125) | `config.py:79` default only; no scheme or secrecy handling in `auth/jwks.py` | **Closed.** Overcast derives the value. The "six" in D-056 §7 is SF's item with Complex. See M-7 for the value itself. |
| M-2 DB roles | One variable, two leaves `db-url` / `db-url-migration` (l.35–37, 127–147); roles are logical labels | Matches Overcast's proposal | **Closed.** Overcast maps `owner` to the existing `shuttleforge_staging` and creates `shuttleforge_app_staging` (DML only), adds the `db-url-migration` shell and a migrate-only task definition bound to it (O-4). |
| M-3 Readiness budget | `readiness_budget_seconds: 110`, `start_period_seconds: 120`; prose asks any killing/de-registering grace to be at least 110 s plus one probe interval (l.22–23, 245) | `startup.py` unchanged at 110 s | **Closed.** 110 + 30 = 140 s; the manifest's own 120 s is below its stated rule. Overcast sets the ECS container `startPeriod` to 120 s (failures inside it do not count; three 30 s retries follow) and the service `healthCheckGracePeriodSeconds` to **150 s**, which satisfies the rule for the ALB path. No manifest change needed; stating 150 would be cleaner. |
| M-4 Internal DNS | `cloud_map_service: shuttleforge` authoritative; `dns_name` records Overcast's FQDN (l.41–43); `TRANSPORT_ENDPOINT` is echoed verbatim in lease responses and must resolve from consumers' namespace (l.164, 179–184) | `api/leases.py` identical on both lines | **Closed.** Consumers (NF) run in the same VPC and namespace, so `http://shuttleforge.staging.internal.arclight-complex.net:9050` resolves for them. Charter template drift is SF's item with Complex. |
| M-5 Policy file | `SHUTTLEFORGE_POLICY_YAML_B64` env value, decoded by the entrypoint to `/data/policy.yaml`, SHA logged, default deny when absent (l.52, 189–206) | `policy/materialize.py:37` `MAX_POLICY_BYTES = 65536`; `:60` enforces; entrypoint hook present on both lines | **Closed as mechanism.** See M-8 for the size cap. |
| M-6 Parameters | Full default/staging table (l.160–177); `SKIP_MIGRATIONS` raw; `ENABLE_WEBHOOKS` does not exist; `INSTANCE_ID` optional with a 29-char `[A-Za-z0-9._-]` rule; never set `PROCESS_ROLE` | Table matches code at the pin | **Closed.** Overcast leaves `INSTANCE_ID` unset. |

Unasked corrections in revision 2 are accepted: `/ready` is 200 for `ready` and `degraded` with the top-level `status` key (`api/ready.py` ready handler: `status in ("ready","degraded")` → 200, else 503), so Overcast's deploy-workflow body check (`.status == "ready"`, merged 2026-10-21) already fits SF; SF.10 is out of scope; capture storage applies to config flows only; unprefixed `CORE_JWKS_URL` is ignored.

## New items

**M-7 (SF, required wording): the JWKS URL value for staging.** Manifest l.186–187 says `SHUTTLEFORGE_CORE_JWKS_URL` is `https://<Core internal Cloud Map name>/.well-known/jwks.json` "(HTTPS; the local appliance refuses any other scheme)". Core's internal path is **plain HTTP on port 8000** with no private CA (D-056; Overcast's Core review answer 11; Podbay ran this way). The HTTPS refusal exists only in the local-appliance tooling (`scripts/local_appliance_recovery.py:455`), not in the image: `auth/jwks.py` and `config.py` impose no scheme. The staging value Overcast will set is `http://core.staging.internal.arclight-complex.net:8000/.well-known/jwks.json`. The manifest must say so (scheme and port) or state that the image accepts it, so an operator does not read the HTTPS line as a requirement Overcast cannot meet.

**M-8 (SF, advisory with a number): policy size.** The 64 KiB decoded cap (`MAX_POLICY_BYTES`) cannot be delivered through an environment value: AWS caps the **entire task definition at 64 KiB** (not adjustable), and base64 inflates the YAML by a third. Overcast's working limit for the parameter is **32 KiB decoded (about 43 KiB encoded)**, leaving the rest of the task definition room. If a staging policy ever exceeds that, the delivery path changes to an ECS `environmentFiles` object in S3 (no size limit; same variable name, same entrypoint behaviour) which Overcast would provision. The manifest should carry the 32 KiB figure or point at the S3 alternative.

**M-9 (SF, answer needed): which Git ref pushes the image.** SF builds from `v1-operate`, not `appliance/main`. Overcast's staging push role trusts exactly `repo:arclightintel-dev/arclight-shuttleforge:ref:refs/heads/main` (live read 2026-10-21; `terraform/modules/iam-github-oidc/main.tf:187`). A push workflow running on `v1-operate` will be refused at `AssumeRoleWithWebIdentity`. Either SF's push workflow runs on `main` (merging the release line, or a `main`-triggered build of the pinned commit), or SF names the ref and Overcast adds it to the trust (O-6, a Terraform change and an owner apply). State which.

**Note, not an item:** `docs/DEPLOYMENT_MANIFEST.md` on `v1-operate` at `3290c54` is still revision 1 (117-line difference from `52b3175`). The code Overcast depends on is equivalent (parity table above), so this does not change the verdict; SF may want the release line to carry the revision it is being deployed under.

## Overcast obligations (restated, with status at `6a507e0`)

| # | Obligation | Status |
|---|---|---|
| O-1 | Security-group ingress for 9050/9100 from the consumers' security group (Nerfherder's, once it exists; Podbay's is gone) | Pending; no consumer SG exists yet |
| O-2 | Module variables for `deployment_minimum_healthy_percent` / `maximum_percent`; SF gets 0 / 100, `desired_count` 1 | Pending |
| O-3 | Digest-pinned deploys in `deploy-service.yml` | Pending; body check landed |
| O-4 | SF task template refresh: `SHUTTLEFORGE_` names, five secrets + `db-url-migration` shell, `shuttleforge_app_staging` role and grants in `bootstrap.sql`, migrate-only task definition, `startPeriod` 120, grace 150, parameters from the rev-2 table, `POLICY_YAML_B64`, `TRANSPORT_ENDPOINT` and `CORE_JWKS_URL` rendered from the namespace | Pending; `core-client-secret` shell already exists |
| O-5 | Prod push-role trust (DR-8) | Overcast Terraform role trust updated 2026-10-21; per-module push roles not re-read |
| O-6 | Add SF's push ref to the staging push-role trust if it is not `main` | Waiting on M-9 |
| R3 | D-059 §6 attestation (staging restore drill) | Unchanged; owner has not scheduled the drill |

## Verdict

**ACCEPT-WITH-CHANGES.** M-1 through M-6 are closed on the evidence above and hold on the release line. Before Overcast writes the SF task definition it needs M-7 corrected in the manifest and M-9 answered; M-8 is a cap Overcast will apply regardless. None of this schedules a deploy; SF.11 stays deferred and R3 remains the gate for live credentials.

## Addendum — revision 3 (`arclight-shuttleforge@d031251`, 2026-10-21): ACCEPT

Verified at the pin (`d5d34f5` is an ancestor): the manifest now states the image imposes no scheme on `SHUTTLEFORGE_CORE_JWKS_URL`, that the HTTPS-only rule belongs to the local appliance controller, and names the staging value `http://core.staging.internal.arclight-complex.net:8000/.well-known/jwks.json` (l.188–190); it carries the 32 KiB decoded / 43 KiB encoded environment limit with the S3 `environmentFiles` path for larger policies (l.199–201; operating policy about 7 KiB); and it records that v1 images build from `v1-operate` and asks for `refs/heads/v1-operate` on the staging push-role trust (l.230–237). M-7, M-8 and M-9 are closed. SF's note that `SECURITY.md` §5.6 requires the JWKS fetch over TLS in production is recorded as DR-10: Core's internal path has no TLS today, so a production SF deployment needs Core-side termination or a private CA the image trusts; an SF.11 input, not a staging item.

**Verdict: ACCEPT.** No SF-side items remain. Overcast obligations O-1..O-6 and R3 stand as listed above; O-6 is now a concrete change (trust `main` and `v1-operate` for the SF push role).

