# ShuttleForge SF.11 Stage B: Overcast operation record

This is the persistent, Overcast-owned operation record for ShuttleForge's SF.11 Stage B on
staging. It covers SF's runbook "Staging evidence order", step 1 (B0), and later entries. Spec:
[`docs/proposals/sf-stage-b-fixture-upstream.md`](../proposals/sf-stage-b-fixture-upstream.md)
(revision 2, approved 2026-11-11, PR #93).

- **Stable URI:** this file on `main`. Each entry is pinned by the merge commit of the PR that added it.
- **Public-repository rules:**
  - identifiers only (ARNs, names, digests, snapshot IDs, secret VersionIds), never values;
  - operators named by role;
  - no recipient or customer data.
- **Secret references** come from `describe-secret` metadata (`VersionIdsToStages`). No value is read.

---

## Entry B0: Stage B operation record (opened 2026-11-11, PR #98)

- **Target environment:** staging, account `650880817826`, `us-east-1`.
- **Resources:**
  - ECS service `arclight-shuttleforge-staging` (cluster `arclight-staging`), task family
    `arclight-shuttleforge-staging`;
  - migrate family `arclight-shuttleforge-migrate-staging`;
  - RDS instance `arclight-staging` (PostgreSQL 16; deletion protection on; automated backups,
    7-day retention), database `shuttleforge_staging`;
  - internal NLB `arclight-stg-int-sf` (TLS 9000/9050/9100, name
    `shuttleforge-internal.staging.arclight-complex.net`), public ALB `arclight-staging`
    (Cloudflare ranges only);
  - fixture listener (spec section A), recorded below.
- **Operator:** owner. The go was given first-hand in Overcast's session on 2026-11-11, approving the spec
  and "apply". **Executor:** Overcast (claude-main).
- **Images:**
  - **N−1, currently deployed:**
    `sha256:f57384de90d40a9212fe75fda8eaf553c97f8a4efcf6f786457b667ad232f5f4` (`v1-55a2d20`, r6),
    revision `arclight-shuttleforge-staging:5` (internal-TLS P3, 2026-11-11).
  - **N:** `sha256:793033d8da8b8cafa58ad3ede142e71c1fe8b68e05aa76e78bbf802d1c26baa6` (`v1-5999bc0`, SF r7,
    source `5999bc0`, push run `42985081506`, a single manifest). Read back from ECR on 2026-11-11.
    It makes no `alembic/` change, so the schema stays `sf9_5b_pg_baseline`. Staging sets no
    `SHUTTLEFORGE_ALLOW_PLAINTEXT_JWKS` (DEBT #121).
- **Expected schema:** `sf9_5b_pg_baseline`.
- **Recovery point:** pending (B4). That entry records the RDS snapshot ID and time and the PITR window,
  and the restore target is a separate protected instance (SF runbook step 6).
- **Secret-version references** (AWSCURRENT VersionIds, read 2026-11-11):

| Secret (`arclight/staging/shuttleforge/…`) | VersionId |
|---|---|
| `kek-ring-b64` | `136471e5-510e-4146-9e1c-7e2fade16f9d` |
| `listener-auth-hmac-key` | `8541ff69-71f4-4a77-ae19-4dcd7625b4ee` |
| `lease-hmac-key` | `f4b76d30-f27f-4e47-b04d-af828f5ff992` |
| `operator-token` | `cc0c6a76-51f2-4e14-9d57-f8707daa2153` |
| `db-url` | `928c6462-b19f-4d3e-b160-e8b9a45fc8f0` |
| `db-url-migration` | `8570d554-92e9-4ef3-a6c4-65187682bfbf` |
| B4's target-URL secret | pending (B4); created when the restore target exists, value written by the owner (SF plan §4.3) |

Not referenced, because they have no stored version: `core-client-secret` and `policy-yaml-b64`
(DR-16 shell, bound by `shuttleforge_policy_enabled`).

### Fixture listener (spec section A)

- **Endpoint for SF's B1:** `host = fixture-upstream.staging.internal.arclight-complex.net`, `port = 8080`.
- **Service:** `arclight-fixture-upstream-staging`, task definition `arclight-fixture-upstream-staging:1`.
  - Image `arclight/dbbootstrap@sha256:5d05a32b5bde13c47b7eecef4da206dc78324feea732e10606c7ae1e69ba4147`;
  - busybox `nc -ll` persistent server mode.
  - Applied 2026-11-11 05:29:56Z (PR #98, 10 added); stable 05:31:36Z.
- **Flag:** `sf_fixture_upstream_enabled = true`. Teardown sets it to `false`, before Stage C's first live write
  (entry B6).
- **Acceptance** (2026-11-11; `scripts/internal-tls-probe/run_probe.py`, each check judged on its emitted `pass`):
  1. **Repeated accepts:** three **separate** probe runs from SF's group (`bb4f2c4a…`, `73157c98…`,
     `3a2c1a78…`). Each `…:8080:connect` passed to `10.0.10.67`, which proves busybox `nc -ll -e` on the
     pinned image re-listens.
  2. **Isolation:** from NF's group, `…:8080:blocked` passed (TCP timeout to `10.0.10.67`).
  3. **Survives restart:** a forced new deployment at 05:35:20Z was stable at 05:38:27Z, with new task
     `97d18151…` at `10.0.10.146`. Three more separate runs from SF's group each connected to `10.0.10.146`.
  4. **Plan:** the post-apply staging plan reads "No changes".

---

## Entry B1/B2: fixtures created and verified (SF-reported; owner's go in SF's session)

- **B1, 2026-11-11 05:58:18Z.** Three SF operator calls, all `201`:
  - provider `sf11-fixture-provider` (proxycheap, no vendor credentials), id `1`;
  - DISCRETE endpoint `sf11-fixture-discrete-1` → `fixture-upstream.staging.internal.arclight-complex.net:8080`, id `1`;
  - config `sf11-fixture-config` (upstream, direct binding to endpoint 1), id `1`.
- **B2, 05:58:23Z.**
  - `/api/status`: config 1 is in the running snapshot (eligible 1 of 1, `direct_binding`).
  - `/ready/detail`: `status` `ready`, `snapshot` ok "version=3, configs=1, endpoints=1", all 13 checks `ok`, commit `55a2d20`.
- The fixture endpoint was `active` by 05:59:03Z: the listener answered SF's probe.
- Consequence: DR-18's empty-inventory deploy allowance was removed (PR #101). A healthy SF deploy passes on plain `ready`.

---

## Entry B3: compatible rollback while fixture-only (AC-15.11; owner's go in Overcast's session, 2026-11-11)

Both deploys were made by hand, mirroring `deploy-service.yml` (register by digest, `update-service
--force-new-deployment`, wait for stable, verify the running digest), with the deployment set to stop
before start (0/100).

| Step | Revision and image | Old task stopped | New task started | Targets registered | Interruption | New task |
|---|---|---|---|---|---|---|
| 1. N | `:6` = copy of base `:4` on `sha256:793033d8…` (r7; field walk: image only, against `:4` and `:5`; no plaintext-JWKS flag) | 08:27:18Z (`074582d8…`, `:5`) | 08:29:51Z | 08:30:22Z (all four groups) | about 3m04s | `5fbede68…`, us-east-1a |
| 2. N−1 | `:5` (r6, `sha256:f57384de…`), the existing ACTIVE revision | 08:34:26Z (`5fbede68…`) | 08:36:59Z | 08:37:29-08:37:39Z | about 3m03s-3m13s | `1284a069…`, us-east-1b |

- **After each step:** `/ready` and `/ready/detail` returned `ready`, with all 13 checks `ok`, the schema `sf9_5b_pg_baseline`
  unchanged, `snapshot` "configs=1, endpoints=1" and `jwks` ok (no plaintext). Commit `5999bc0` after step 1 and `55a2d20` after step 2.
- **SF's own reads** passed at 08:33:53Z and 08:39:15Z, with the fixture endpoint `active` both times.
- **DEBT #127 startup lines,** from N's task log (stream `shuttleforge/shuttleforge/5fbede68…`):
  - 08:30:16.622Z `INFO shuttleforge.db_config: Database identity: backend=postgresql database=shuttleforge_staging schema_revision=sf9_5b_pg_baseline server_version=16.13`
  - 08:30:16.750Z `INFO shuttleforge.auth.jwks: JWKS client started (url=https://core-internal.staging.arclight-complex.net/.well-known/jwks.json)`
- **SF now runs r6 on `:5`.** `:6` (r7) stays ACTIVE and unused until SF decides.

---

## Entry B4: restore drill (AC-15.12; owner's go in Overcast's session, 2026-11-12)

- **Plan:** [`sf-stage-b4-runplan.md`](sf-stage-b4-runplan.md) revision 2 (PR #112). The target-URL secret shell
  came in PR #113 (applied 2026-11-12).
- **Executor:** Overcast (claude-main). The owner wrote the target URL (step 6).
- **SF inputs:**
  - SQL at SF `268e179`: Part A `8b711866…`, Part B `1836efac…`. The check task re-verified both hashes on every run.
  - Verifier at SF `007d6ad`: `cd377766…`.
- **What it fills:** B0's two pending fields, the recovery point and B4's target-URL secret.
- **Writes:** nothing was written to the live instance `arclight-staging`. Part A ran with
  `default_transaction_read_only=on`.
- **Core** was sent the snapshot I/O notice at 13:19:50Z, before step 1.
- **Check task:** `arclight-sf11-b4-check-staging`.
  - `:1` ran the dry runs. `:2` changed only the evidence fold width to 8000, because busybox `fold` rejects
    12000; `:2` ran every evidence run.
  - Image `arclight/dbbootstrap@sha256:5d05a32b…`, in the dbbootstrap group, with `PG_OWNER_URL` from
    `db-url-migration`.
  - Logs: `/arclight/staging/dbbootstrap`, stream `sf11-b4/check/<task>`.

All times are UTC. Steps 0-8 ran on 2026-11-12. Steps 7 and 8 used the check task's host swap, so they did not need the
step 6 secret. Step 6 and step 9 ran on 2026-11-16.

| Step | Time | Task or resource | Result |
|---|---|---|---|
| 0. Dry run, plain | 13:15:40-13:16:04 | `3886ebbbce904f0eac900af3caa51489` (`:1`) | `D\|shuttleforge_staging` |
| 0. Dry run, host swap (`TARGET_HOST` = source endpoint) | 13:16:34-13:17:00 | `2e6044c8f19048608117a7f8db76de8f` (`:1`) | Same output (`OUT_SHA 8762a439…`) |
| 0. Rehearsal, SF serving (not evidence) | 13:18:42-13:19:05 | `adeaa3592f304e3e98dab0285155a1d5` (`:2`) | 46 lines, `52e6987f…`. The first attempt, `3a7a5b34…` (`:1`), exposed the fold limit and wrote no evidence line |
| 1. Quiesce | desired 0 at 13:20:05 | SF task `1284a069…` STOPPED 13:23:18 (exit 143) | No SF task running |
| 2. Part A, **source** | 13:23:44-13:24:07 | `6e12b906ecf641e1a658a6dcd3dbd38b` | 2464 bytes, 46 lines, sha256 `6e030563bd23b6f11ce6fe77c40aa0347df1c550f559e28e5586cc48517ae436` |
| 3. Snapshot | created 13:24:36.967, available 13:27:33 | **`arclight-staging-sf11-b4-202611121324`** | Manual, encrypted (KMS key `adff38a9…`), 20 GiB, PostgreSQL 16.13. PITR window then: 2026-11-05T13:23:48Z to 2026-11-12T13:23:48Z |
| 4. Resume SF | desired 1 at 13:27:54, stable 13:28:43 | `3a80171f4edb442a812cc6c220352c4c` (`:5`, `sha256:f57384de…`) | Readiness PASS at 13:28:45: commit `55a2d20`, schema `sf9_5b_pg_baseline`, all 13 checks `ok`. SF was down about 8.5 minutes. SF's fixture read passed |
| 5. Restore | created 13:32:20.374, available 13:38:19 | **`arclight-staging-sf11-b4-target`** | db.t3.micro, us-east-1b, single-AZ, gp3, encrypted with the same key. Group `sg-0098d9af3d843bfa1`, subnet group `arclight-staging`, parameter group in sync. Private, deletion protection on. Tags `Purpose=sf11-b4-restore-drill`, `ManagedBy=cli-drill` |
| 7. Part A, **target** | 13:38:58-13:39:22 | `e38dfac29ce54cac965c8ca55b8bbf96` | **Byte-identical to step 2**: same sha256 `6e030563…ae436`, with no sequence advance. SF's `sf11_b4_compare.py` exited 0: PASS |
| 8. Part B, **target** | 13:39:57-13:40:20 | `a13d69fddc8b44739b2613ccea0bda8e` | Shown below. SF: PASS |
| 6. Target URL (owner) | 2026-11-16 14:27:13 | `b4-target-db-url` VersionId **`14da08f9-d6c7-4572-9f37-82a40bb2f2ea`** | Owner's local check, which prints no value: user `shuttleforge_app_staging`; everything through `@` byte-identical to `db-url`; only the host changed (length delta 15, as expected) |
| 9. Verification task | 2026-11-16 15:44:47-15:46:25 | `8ff2d067573e4c25a44588e65aa0ba76` on `arclight-sf11-b4-verify-staging:1` | Verifier exit 0, all four reads `200`. SF: PASS |

**Part B**: stdout is 42 bytes, sha256 `01d7d26b70a3d8a1b63c34307953da51c7b7f92e34b5fe504f512aa768037a48`:

```
BEGIN
DO
ROLLBACK
guard_probe|rolled_back
```

psql notices (`/tmp/b.sql:48`), passed through the stderr allowlist (`WITHHELD 0`):

```
guard|audit_log|UPDATE|rejected
guard|audit_log|DELETE|rejected
guard|audit_log|TRUNCATE|rejected
guard|lease_events|UPDATE|rejected
guard|lease_events|DELETE|rejected
guard|lease_events|TRUNCATE|rejected
```

No `NOT REJECTED` and no `INCONCLUSIVE` line.

**Step 9: the verification task**
- **Task definition:** `arclight-sf11-b4-verify-staging:1` is `arclight-shuttleforge-staging:5` with these changes:
  - the family;
  - `SHUTTLEFORGE_DB_URL` points at `b4-target-db-url`;
  - the log prefix is `sf11-b4-verify`;
  - a non-essential `verifier` container. It runs on the same digest with `python -I -c` and the verifier text
    (`cd377766…`), and has only the secret `SHUTTLEFORGE_OPERATOR_TOKEN`.

  `:5` has no task role, so neither does the copy.
- **Isolation:**
  - The task was started by a bare `run-task` in SF's group `sg-075408be3ea36c30e`, in private subnets with no
    public IP. Its address was `10.0.10.113`, its group `family:arclight-sf11-b4-verify-staging`, and no service started it.
  - SF's four target groups and Cloud Map service `srv-5ny7jrumltffukzg` held only `10.0.10.88`, the serving task
    `3a80171f…`, before the run, while the task was pending and after it stopped.
- **`/ready/detail`:** `ready` on commit `55a2d20ab586aa6099dde796901c05ac236556d2`, database `shuttleforge_staging`,
  schema `sf9_5b_pg_baseline`, with all 13 checks `ok`, including `snapshot` "version=1, configs=1, endpoints=1".
- **Fixtures**, each id `1`:
  - `/api/providers`: `sf11-fixture-provider`;
  - `/api/endpoints`: `sf11-fixture-discrete-1` → `fixture-upstream.staging.internal.arclight-complex.net:8080`;
  - `/api/proxies`: `sf11-fixture-config`.
- **Expected warning:** "Health check staleness: max age 354185.7s". That is the restored `last_health_check` from
  the snapshot time. The checker then probed once, writing only to the drill target.
- **Logs:** group `/arclight/staging/shuttleforge`. Each line is an ISO timestamp, a TAB and the message, with LF endings
  and a final LF.
  - stream `sf11-b4-verify/verifier/8ff2d067573e4c25a44588e65aa0ba76`: 5 events, 4332 bytes, sha256
    `b2bda2ebbadeba25c3fede9f2acd1b95c1755d362645f0d7c03bc7018a0a4cae`;
  - stream `sf11-b4-verify/shuttleforge/8ff2d067573e4c25a44588e65aa0ba76`: 18 events, 1570 bytes, sha256
    `27a2485c006d07a3437f642bc5db767a44e7565ba47238fafbc0d6008b7f1c35`.

  Both were sent to SF verbatim on 2026-11-16. SF rebuilt them from the message and matched both hashes, and
  commits them to its Stage B evidence folder. Both records bind these bytes.
- **Exit codes:** the verifier exited 0. `shuttleforge` exited 143: SIGTERM from Overcast's `stop-task`, after a
  graceful shutdown ("Application shutdown complete"). This is expected, not a failure.
- **Which database answered.** This is SF's analysis, rated inferred with HIGH confidence.
  - r6 writes `last_health_check` on every probe (`health_checker.py:328` at SF `55a2d20`). The primary probes about
    every 60 s, so the source's oldest health-check age stays near 60 s.
  - The database that answered had last been written at about 2026-11-12T13:22:11Z. That is 67 s before SF stopped
    (13:23:18Z) and before the snapshot (13:24:36Z).
  - So the verify task read the restored copy, not the source.
- **Ordering, a deviation from SF's plan text.** SF's plan B4 runs the verify task "while the serving task is
  stopped". This run plan restarted the primary at step 4, before the restore, so step 9 ran beside the live primary.
  AC-10.8a's bound held:
  - the task was in no ALB or NLB target group and no Cloud Map service;
  - it used a separate database;
  - isolation was checked before the run, while the task was pending and after it stopped.

  SF corrects its plan text in its records PR.
- **The primary afterwards:** SF read it at 15:52:47Z and it passed. It was the same process as at step 4
  (started 2026-11-12T13:28:20Z), so step 9 never restarted it. Status `ready`, all 13 checks `ok`,
  `active_leases=0`, `probes_total=5903`.
- **Credentials:** none appear in either log (INV-03). The preflight URL is redacted.
- **AC-15.12** (SF): the drill passes for Stage B's exit gate. AC-15.12 itself closes at Stage C's first live write,
  which completes its "dated later" predicate.
- **Evidence retention:** both log groups keep 30 days, so the check-task streams expire about 2026-12-12 and the
  verification streams about 2026-12-16. SF holds the verbatim copies.

**Recovery point (fills B0):** snapshot `arclight-staging-sf11-b4-202611121324`, kept through Stage C. Deleting
it later needs the owner's go.

**Teardown (2026-11-16).** The owner's go was given first-hand in Overcast's session, conditional on Overcast
judging B4 complete. SF's step 9 PASS met that condition.
- **Pre-checks:**
  - the drill snapshot is `available`;
  - the target matched its drill tags (`Purpose=sf11-b4-restore-drill`, `ManagedBy=cli-drill`), with no replicas;
  - `arclight-staging` was untouched (`available`, deletion protection on);
  - no drill task was running.
- **15:54:04Z:** deregistered `arclight-sf11-b4-check-staging:1` and `:2` and `arclight-sf11-b4-verify-staging:1`
  (all now INACTIVE).
- **15:54:07Z:** turned deletion protection off on `arclight-staging-sf11-b4-target`.
- **15:54:15Z:** `delete-db-instance --skip-final-snapshot --delete-automated-backups`; the instance was deleted by
  16:01:49Z.
  - The target had inherited 7-day backup retention, so it held five automated snapshots of its own, 11-12 to 11-16.
    They hold drill data only.
  - No automated backups were retained after deletion.
  - RDS had removed those automated snapshots by 16:03:58Z.
- **`b4-target-db-url`:** removed by PR #114's Terraform change (merged `1dd0cb7`): a targeted plan with 1 to destroy
  and nothing else, plan_guard passed.
  - Applied after merge at 16:05:19Z, from a fresh saved plan on `main`.
  - `describe-secret` shows `DeletedDate` 16:05:19Z. Secrets Manager keeps the secret unreadable through its 30-day
    recovery window, to about 2026-12-16.

---

## Entry B5: D-059 §6 posture attestation (live read, 2026-11-16)

Overcast attests the six postures of D-059 position 6 for staging from a live read on 2026-11-16, 16:07:26Z to
16:08:41Z. The postures are as worded at arclight-complex `48c1715`, with "CloudTrail log protection" as clarified
by D-075. Every call was read-only, and no secret value was read. SF adds the operator listing of the `sf11-fixture-*`
provider accounts.

| D-059 §6 posture | Live evidence | Status |
|---|---|---|
| RDS deletion protection | `arclight-staging`: `DeletionProtection` true, storage encrypted, not publicly accessible | Met |
| S3 versioning and lifecycle | <ul><li>Trail bucket `arclight-staging-trail-20260624130504376400000006`: versioning on; lifecycle `archive-logs`, with no expiration.</li><li>`arclight-staging-bandersnatch-payload`: versioning on; no lifecycle, by design (`bandersnatch.tf:84`: "never deleted from, no lifecycle rule").</li><li>`arclight-staging-nerfherder-artifacts`: **versioning off**. Its lifecycle only aborts incomplete uploads after 7 days, with no expiry, by design (NF manifest M:205-206).</li><li>`arclight-terraform-state`, outside Terraform: versioning on, no lifecycle.</li><li>SF owns no bucket.</li></ul> | **Partly met**: the Nerfherder artifact bucket is unversioned (DR-25) |
| CloudTrail log protection (D-075) | <ul><li>Trail `arclight-staging` is logging: last delivery 16:06:08Z, no delivery error.</li><li>Multi-region, with log file validation.</li><li>Its bucket has Object Lock `GOVERNANCE` 365 days and versioning on, and its lifecycle has no expiration.</li><li>The bucket policy's `DenyLogDeletion` denies `s3:DeleteObject` and `s3:DeleteObjectVersion`.</li></ul> | Met |
| ALB restricted to Cloudflare ranges | <ul><li>The only internet-facing staging load balancer is `arclight-staging`, security group `sg-00535f859fa624065`.</li><li>Ingress is on 80 and 443 only. Each port's sources exactly equal Cloudflare's published list, read the same minute: `api.cloudflare.com/client/v4/ips`, etag `38f79d05…`, 15 IPv4 and 7 IPv6 ranges.</li><li>No `0.0.0.0/0`, and no security-group or prefix-list sources.</li><li>The NLBs `arclight-stg-int-core` and `arclight-stg-int-sf` are internal.</li></ul> | Met as worded. DR-21 (other Cloudflare accounts share these ranges) stays open |
| Automated backups with a tested restore | <ul><li>`BackupRetentionPeriod` 7; latest restorable time 16:03:44Z.</li><li>Restore tested twice: V-1 on 2026-10-24 (`docs/runbooks/restore-rds.md`), and B4 from 2026-11-12 to 11-16 (Entry B4).</li></ul> | Met |
| CloudWatch log retention set deliberately | <ul><li>Every staging group has an explicit retention:<ul><li>`core`, `dbbootstrap`, `shuttleforge`, `nerfherder` and `probe`: 30 days;</li><li>`fixture-upstream`: 7 days;</li><li>`bandersnatch`: 365 days;</li><li>ECS Container Insights performance: 1 day.</li></ul></li><li>No group is set to never expire.</li><li>SF's group `/arclight/staging/shuttleforge`, added since the 2026-10-24 read, is 30 days.</li></ul> | Met |

**Secrets Manager leaves under `arclight/staging/shuttleforge/`** (names only, `list-secrets
--include-planned-deletion`, 16:08:41Z):

| Leaf | State |
|---|---|
| `b4-target-db-url` | Pending deletion since 2026-11-16 16:05:19Z (Entry B4) |
| `core-client-secret` | Shell, no version |
| `db-url` | One version |
| `db-url-migration` | One version |
| `kek-ring-b64` | One version |
| `lease-hmac-key` | One version |
| `listener-auth-hmac-key` | One version |
| `operator-token` | One version |
| `policy-yaml-b64` | Shell, no version (DR-16) |

The six AWSCURRENT VersionIds re-read at the same time all equal B0's table of 2026-11-11.

---

## Fixture teardown receipt (not scheduled)

Earlier drafts of this record, and the spec, called this entry **B6**. In SF's plan (§4.3), B6 is SF's AC-15.13
teardown authorization: SF binds its runbook's teardown procedure to this record in SF's evidence bundle. That is
SF writing a record; nothing in AWS is torn down.

Removing the fixture is **not scheduled**. Whether and when to remove it is open for SF and the owner. The spec
(PR #93) said it would be removed "before Stage C's first live write"; that wording now waits on their decision.
- **The fixture upstream stays running until then.** C-G3's roll of SF to `:6` (r7) comes before Stage C, and
  `deploy-service.yml` passes only on `ready`.
- Without the upstream, the fixture endpoint turns `degraded` after its third failed probe, about 3 minutes later
  (SF `health_checker.py:46-47` at `55a2d20`).

When it happens, the fields follow the spec:
- decision, UTC time, affected resources (including the fixture listener flag), recovery points, key-version
  references, executor and outcome;
- if live material exists at teardown, every field of SF's "Live-material teardown authorization".
