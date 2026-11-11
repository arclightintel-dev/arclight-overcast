# SF.11 Stage B4: the staging restore drill (Overcast run plan)

Status: **Draft, revision 2 (2026-11-11), with SF's final SQL.** Revision 2 folds in codex-1's single review pass
(REVISE: two P2 findings plus corrections) and SF's answers. It needs the owner's first-hand go; the
**teardown** at the end needs its own.

B4 is SF's runbook "Staging evidence order", step 6, and acceptance criterion AC-15.12:
- snapshot fixture-only state;
- restore it to a **separate protected target**;
- prove that the target matches the source and that its guards hold;
- run SF's verifier against it.

Nothing is written to the live instance `arclight-staging`. Two services are affected:
- **ShuttleForge** is stopped for about 15-25 minutes.
- **Core**, which shares the single-AZ instance, may see database I/O stall for seconds to minutes
  while the snapshot starts (AWS documents this for single-AZ snapshots). Core is told before step 3.

Inputs from SF (2026-11-11):
- **Final SQL** (SF PR #51 at `268e179`, review step 8 PASS). Overcast decoded both files from SF's base64
  and checked them against SF's hashes and against SF's repository at `268e179`, read-only:
  - `sf11_b4_restore_check_a.sql`: read-only fingerprint, 2840 bytes, sha256 `8b711866ce912743…`.
    Its comments are the only text that could look like writes. It pins `TIME ZONE 'UTC'`,
    `extra_float_digits = 1` and `bytea_output = 'hex'`.
  - `sf11_b4_restore_check_b.sql`: append-only guard probe, 2552 bytes, sha256 `1836efacdabe414f…`.
    It runs as the **schema owner**: PostgreSQL checks the TRUNCATE privilege before the guard fires,
    and the runtime role would report `INCONCLUSIVE`, which fails B4.
  - **Overcast runs only these bytes.** The check task re-verifies both hashes.
  - Part A's generator queries order by table, sequence and trigger name, so its output order is
    deterministic.
- `docs/PHASE_PLANS/sf11_b4_verifier.py`, final. Its sha256 `cd3777662d85bbec…` was checked by Overcast
  read-only at SF `007d6ad`.

## Facts this plan relies on (read 2026-11-11)

- **Source instance:** `arclight-staging`, from module `rds-postgres`.
  - db.t3.micro, PostgreSQL 16.13, gp3 20 GB, encrypted (KMS key `adff38a9…`), single-AZ, deletion
    protection on, 7-day automated backups.
  - Subnet group `arclight-staging`, security group `sg-0098d9af3d843bfa1`, parameter group
    `arclight-staging-pg16-…` (`rds.force_ssl` = 1).
  - It also holds Core's `core_staging`.
- **ShuttleForge:** serves r6 on `arclight-shuttleforge-staging:5`.
  - Its database URL is the secret `SHUTTLEFORGE_DB_URL` ← `arclight/staging/shuttleforge/db-url`
    (runtime role).
  - `:5` sets `SHUTTLEFORGE_SKIP_MIGRATIONS=true`, `SHUTTLEFORGE_DB_TLS_MODE=require`,
    `SHUTTLEFORGE_REQUIRE_PG=true` and `SHUTTLEFORGE_DB_EXPECTED_NAME=shuttleforge_staging`.
    Read from the live task definition.
  - At r6 `55a2d20`, `shuttleforge/serve.py` runs alembic only when migrations are not suppressed
    (`db_config.py` `_migrations_are_suppressed`). So a copy of `:5` never migrates the target.
  - SF's execution role reads `arclight/staging/shuttleforge/*`, with an explicit deny on
    `db-url-migration`.
- **The URL shape SF accepts** (SF; `db_config.py` requires the drivername `postgresql+asyncpg`
  exactly): `postgresql+asyncpg://<user>:<url-encoded password>@<host>:5432/shuttleforge_staging`, with
  no query string. SF takes TLS from `SHUTTLEFORGE_DB_TLS_MODE`.
- **The dbbootstrap execution role** can read `arclight/staging/shuttleforge/db-url-migration` (exact
  ARN), the owner-role URL. The tables' owner is needed for Part B's `TRUNCATE` probe. The dbbootstrap
  group reaches RDS on 5432 and nothing outside the VPC.
- **Database passwords:** a restored instance keeps the source's roles and their passwords **as of the
  snapshot**. SF's credentials work on the target; only the host differs.
- **Nothing else uses SF's database.** Nerfherder is at 0, and the fixture listener never touches a
  database.

## Prerequisite (one PR, before the run)

- **P1.** Terraform: a new secret **shell** `arclight/staging/shuttleforge/b4-target-db-url` (no value),
  next to `db-url-migration` in `shuttleforge.tf`. SF's execution-role wildcard covers it.
- **P2.** At step 6 the **owner** writes its value: SF's runtime URL (`db-url`) with the host replaced by
  the target's endpoint. Overcast gives exact PowerShell steps that never display the value.

## The check task (used at steps 0, 2, 7 and 8)

A one-off family, `arclight-sf11-b4-check-staging`, registered by the CLI and deregistered at teardown:
- **Image:** the dbbootstrap image by digest (`sha256:5d05a32b…`, postgres:16-alpine, which has `psql`,
  `sha256sum` and `base64`).
- **Role, group and logs:** the dbbootstrap execution role, the dbbootstrap group, and the log group
  `/arclight/staging/dbbootstrap`.
- **In the task definition itself, not in overrides:** both SQL files as base64 environment values, their
  expected SHA-256 values, and the script, under `entryPoint ["sh","-c"]`. Only `MODE` (`dry` / `a` / `b`)
  and `TARGET_HOST` are overrides. That keeps the run-task override well under ECS's 8192-character limit.
- **The secret** `PG_OWNER_URL` ← `db-url-migration`.

The script:
- **Checks the SQL files:** decodes each one and checks it with `sha256sum -c`. It stops on any mismatch.
- **Builds a libpq URL, never printed:** the scheme `postgresql+asyncpg://` becomes `postgresql://`, and
  `?sslmode=require` is appended. When `TARGET_HOST` is set, its value replaces the host.
- **Runs the mode:**
  - `dry`: `SELECT current_database()` only;
  - `a`: Part A exactly as SF specifies, with the read-only `PGOPTIONS`;
  - `b`: Part B, without the read-only `PGOPTIONS`, and only when `TARGET_HOST` is set.
- **Withholds raw psql diagnostics** (codex-1: libpq echoes a malformed percent-encoded password in a
  client-side parse error).
  - stdout and stderr go to files.
  - The task log carries only allowlisted lines: Part A's stdout prefixed `A|`, `NOTICE:  guard|…`,
    `guard_probe|…`, and `psql:/tmp/…` script errors raised by the server.
  - Then `OUT_SHA <sha256>`, the exit code, and a count of the lines it withheld.
  - **Part A's evidence file is exact:** psql runs **without `-q`**, so the `SET` ×4, `BEGIN` and `COMMIT`
    command tags stay in. SF's comparator rejects a capture without them (SF `d0f4a62`).
  - The whole stdout file is also logged as one `A64|<base64>` line. Overcast decodes that line into
    the evidence file, checks it against `OUT_SHA`, and hands it to SF byte for byte. The allowlist
    applies only to stderr, never to the evidence.

## Run

0. **Pre-flight (nothing changes yet):**
   - SF's final SQL files are received and their hashes recorded.
   - Register the check task.
   - Run it with `MODE=dry`, twice: once plain, and once with `TARGET_HOST` set to the **source**
     endpoint, which exercises the host replacement. Both must print `shuttleforge_staging`.
   - SF serves r6 on `:5`, and Nerfherder is at 0.
   - Tell Core about the snapshot I/O window.
1. **Quiesce:** set SF's service to desired 0 through the API, and wait for no running task.
2. **Part A on the SOURCE:** `MODE=a`. Save the output and its SHA-256.
3. **Snapshot:** `create-db-snapshot` → `arclight-staging-sf11-b4-<UTC yyyymmddhhmm>`.
   - Core may stall briefly while it starts.
   - Wait until `available`. Record the ID, the create time, and the PITR window (earliest and
     `LatestRestorableTime`).
4. **Resume SF:** set desired 1 (Terraform's default) and wait until stable. Check readiness: `ready` on
   commit `55a2d20`. SF repeats its fixture read.
5. **Restore the target:** `restore-db-instance-from-db-snapshot` → `arclight-staging-sf11-b4-target`.
   - Same class, subnet group, security group and parameter group as the source.
   - Not publicly accessible, single-AZ, **deletion protection on**. Encryption is inherited.
   - Tagged `Purpose=sf11-b4-restore-drill`. It's a CLI-made drill artifact, outside Terraform state; the
     separate identifier doesn't collide with the tracked instance.
   - Wait until `available` and record the endpoint.
6. **Owner writes `b4-target-db-url`** (P2). Record its VersionId.
7. **Part A on the TARGET:** `MODE=a`, `TARGET_HOST=<target endpoint>`. Overcast returns **both** outputs
   (steps 2 and 7) to SF verbatim, with their SHA-256 values. **SF's `sf11_b4_compare.py` decides:**
   - every line must match exactly;
   - except that a target `sequence` line may read the source `last_value + log_cnt`, with `log_cnt`
     0. Crash recovery during a snapshot restore restores the pre-logged sequence value.
   Overcast also records whether the two outputs are byte-identical.
8. **Part B on the TARGET only:** `MODE=b`, `TARGET_HOST=<target endpoint>`. **PASS only on**:
   - six `guard|<table>|<OP>|rejected` notices;
   - then `guard_probe|rolled_back`;
   - no `NOT REJECTED`.
9. **Verification task.** A one-off family `arclight-sf11-b4-verify-staging`:
   - a copy of `:5` whose `SHUTTLEFORGE_DB_URL` points at `b4-target-db-url`, with every other value
     unchanged, `SKIP_MIGRATIONS=true` included;
   - plus a **non-essential** `verifier` container on the same image digest, with
     `entryPoint ["python","-I","-c"]`, `command [<verifier text, SHA-256 checked>]` and the secret
     `SHUTTLEFORGE_OPERATOR_TOKEN`.

   It runs in **SF's group**, so the SF container reaches the target and the fixture listener, in the
   private subnets with no public IP. It is a task, not a service: no load balancer and no Cloud Map.

   When the verifier exits:
   - copy its log stream verbatim to SF;
   - **stop the task.**

   SF expects:
   - commit `55a2d20` and database `shuttleforge_staging`;
   - all 13 checks, with every check except `snapshot` `ok`;
   - fixture provider, endpoint and config, each id 1.
10. **Record** B0 entry B4:
    - the snapshot ID and time, and the PITR window;
    - the target instance;
    - `b4-target-db-url`'s VersionId;
    - both Part A SHA-256 values;
    - Part B's lines;
    - the verifier's log location;
    - every task ID.

## Teardown (separate owner go, after SF accepts B4)

- Deregister the check and verify task definitions.
- **Delete the target instance:** turn deletion protection off, then delete it without a final
  snapshot. The drill snapshot is the recovery point. The deletion is permanent; it's named in the go.
- **Remove `b4-target-db-url`** by a Terraform PR. Its value holds SF's runtime credentials.
- **Keep the drill snapshot** as B4's recovery point through Stage C. Delete it later, on the owner's go.

## Risks

- **SF downtime** of about 15-25 minutes (steps 1-4), fixture-only. **Core** may see a database I/O stall
  of seconds to minutes when the snapshot starts.
- **URL handling:** the step 0 dry runs prove the conversion and the host swap before anything stops.
  Raw psql diagnostics never reach the logs.
- **The target accepts SF's runtime and owner credentials** for its lifetime, in the same private subnets
  and RDS group as the source. Keep its life short; teardown follows acceptance.
- **Cost:** one db.t3.micro and a 20 GB snapshot for a few hours, a few cents.
