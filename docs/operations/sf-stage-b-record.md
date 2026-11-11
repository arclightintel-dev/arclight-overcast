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

## Entry B6: fixture teardown receipt

Not yet written. Fields are per the spec: decision, UTC time, affected resources (including the
fixture listener flag), recovery points, key-version references, executor and outcome. If live material
exists at teardown, it carries every field of SF's "Live-material teardown authorization".
