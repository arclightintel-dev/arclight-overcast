# SF.11 Stage B4: the staging restore drill (Overcast run plan)

Status: **Draft, revision 1 (2026-11-11).** It needs one review pass and the owner's first-hand go. The
**teardown** at the end needs its own go.

B4 is SF's runbook "Staging evidence order", step 6, and acceptance criterion AC-15.12:
- snapshot fixture-only state;
- restore it to a **separate protected target**;
- prove that the target matches the source and that its guards hold;
- run SF's verifier against it.

The live instance, `arclight-staging`, is never written to, and only ShuttleForge is stopped
(briefly).

Inputs from SF (2026-11-11):
- `sf11_b4_restore_check_a.sql` (read-only fingerprint) and `sf11_b4_restore_check_b.sql` (the
  append-only guard probe). Final text and SHA-256 come after SF's review, SF PR #51. **Overcast runs
  only the final files, checked byte for byte.**
- `docs/PHASE_PLANS/sf11_b4_verifier.py`, final (sha256 `cd3777662d85bbec…`, unchanged since SF PR #44).

## Facts this plan relies on (read 2026-11-11)

- **Source instance:** `arclight-staging`. db.t3.micro, PostgreSQL 16.13, gp3 20 GB, encrypted (KMS key
  `adff38a9…`), single-AZ, deletion protection on, 7-day automated backups. Subnet group `arclight-staging`,
  security group `sg-0098d9af3d843bfa1`, parameter group `arclight-staging-pg16-…` (`rds.force_ssl` = 1).
- **ShuttleForge:** serves r6 on `arclight-shuttleforge-staging:5`. Its database URL is the secret
  `SHUTTLEFORGE_DB_URL` ← `arclight/staging/shuttleforge/db-url` (runtime role). SF's execution role
  can read every `arclight/staging/shuttleforge/*` secret.
- **The dbbootstrap execution role** can read `arclight/staging/shuttleforge/db-url-migration`, the
  owner-role URL. The tables' owner is needed for Part B's `TRUNCATE` probe. The dbbootstrap group
  reaches RDS on 5432 and nothing outside the VPC.
- **Database passwords:** a restored instance keeps the source's roles and their passwords. The same
  credentials work on the target; only the host differs.
- **Nothing else depends on SF's database.** Nerfherder is at 0, and Core and Bandersnatch don't use
  it.

## Prerequisite (one PR, before the run)

- **P1.** Terraform: a new secret **shell** `arclight/staging/shuttleforge/b4-target-db-url` (no value),
  next to `db-url-migration` in `shuttleforge.tf`. SF's execution role already covers it.
- **P2.** At step 6 the **owner** writes its value: SF's runtime URL (`db-url`) with the host replaced by
  the target's endpoint. Overcast gives exact PowerShell steps that never display the value.

## Run

0. **Pre-flight (nothing changes yet):**
   - SF's final SQL files have arrived, and their SHA-256 values are recorded.
   - SF confirms that revision `:5` starts with migrations suppressed. The verification task copies it
     against the target.
   - A **check-task dry run against the SOURCE** runs `SELECT current_database()` only. It proves the
     owner-URL handling below before anything stops.
   - SF serves r6 on `:5`, and Nerfherder is at 0.
1. **Quiesce:** set SF's service to desired 0 through the API, and wait for no running task.
   - SF is down from here until step 4: about 15-25 minutes, fixture-only.
2. **Part A on the SOURCE.** A one-off **check task**:
   - image: the dbbootstrap image by digest (`sha256:5d05a32b…`, postgres:16-alpine, which has `psql`,
     `sha256sum` and `base64`);
   - role, group and logs: the dbbootstrap execution role, the dbbootstrap group, and the dbbootstrap
     log group;
   - `entryPoint ["sh","-c"]`.

   The script it runs:
   - decodes each SQL file from a base64 environment value and checks it with `sha256sum -c` against
     SF's final hash, stopping on any mismatch;
   - builds a libpq URL from the injected `db-url-migration`: the scheme `postgresql+<driver>://`
     becomes `postgresql://`, and `ssl=require` becomes `sslmode=require`. The URL is never printed;
   - runs Part A exactly as SF specifies (`PGOPTIONS='-c default_transaction_read_only=on' psql -X -At
     -F '|' -v ON_ERROR_STOP=1 -f …`);
   - prints the output, each line prefixed `A|`, then `OUT_SHA <sha256>`. The output holds names,
     counts and digests only.
3. **Snapshot.**
   - `create-db-snapshot` → `arclight-staging-sf11-b4-<UTC yyyymmddhhmm>`; wait until `available`.
   - Record the snapshot ID, its create time, and the PITR window: the earliest time and
     `LatestRestorableTime`.
4. **Resume SF:** set SF's service back to desired 1 (Terraform's default), wait until stable, then:
   - readiness `ready` on commit `55a2d20`;
   - SF repeats its fixture read.
5. **Restore the target:** `restore-db-instance-from-db-snapshot` → `arclight-staging-sf11-b4-target`.
   - Same class, subnet group, security group (`sg-0098d9af3d843bfa1`) and parameter group as the
     source.
   - Not publicly accessible, single-AZ, **deletion protection on**. Encryption is inherited.
   - Tagged `Purpose=sf11-b4-restore-drill`. Made through the CLI, outside Terraform state: it's a
     drill artifact.
   - Wait until `available`, about 15 minutes, and record the endpoint.
6. **Owner writes `b4-target-db-url`** (P2).
7. **Part A on the TARGET:** the same check task with `TARGET_HOST=<target endpoint>`. The script swaps
   that host into the URL.
   - **PASS only if** the output's SHA-256 equals step 2's, byte for byte.
8. **Part B on the TARGET only** (no read-only `PGOPTIONS`, `TARGET_HOST` required). **PASS only on**:
   - six `guard|<table>|<OP>|rejected` notices;
   - then `guard_probe|rolled_back`;
   - no `NOT REJECTED`.
9. **Verification task.** A one-off family `arclight-sf11-b4-verify-staging`:
   - a copy of `:5` whose `SHUTTLEFORGE_DB_URL` points at `b4-target-db-url`;
   - plus a **non-essential** `verifier` container on the same image digest, with
     `entryPoint ["python","-I","-c"]`, `command [<verifier text, SHA-256 checked>]` and the secret
     `SHUTTLEFORGE_OPERATOR_TOKEN`.

   It runs in **SF's group**, so the SF container reaches the target and the fixture listener, in the
   private subnets with no public IP. It is a task, not a service: no load balancer and no Cloud Map.

   When the verifier exits:
   - copy its log stream verbatim to SF;
   - **stop the task** (the SF container would otherwise keep running).

   SF expects:
   - commit `55a2d20` and database `shuttleforge_staging`;
   - all 13 checks, with every check except `snapshot` `ok`;
   - fixture provider, endpoint and config, each id 1.
10. **Record** B0 entry B4:
    - the snapshot ID and time, and the PITR window;
    - the target instance;
    - both Part A SHA-256 values;
    - Part B's lines;
    - the verifier's log location;
    - every task ID.

## Teardown (separate owner go, after SF accepts B4)

- Deregister the one-off check and verify task definitions.
- **Delete the target instance:** turn deletion protection off, then delete it without a final
  snapshot. The drill snapshot is the recovery point. The deletion is permanent; it's named in the go.
- **Remove `b4-target-db-url`** by a Terraform PR. Its value holds SF's runtime credentials.
- **Keep the drill snapshot** as B4's recovery point through Stage C. Delete it later, on the owner's go.

## Risks

- **SF downtime** of about 15-25 minutes (steps 1-4). Fixture-only; nothing depends on SF while
  Nerfherder is at 0.
- **URL handling** in the check task: the dry run at step 0 catches a wrong conversion before
  anything stops. `psql` errors never print the password.
- **The target accepts SF's real runtime and owner credentials** for its lifetime. It sits in the same
  private subnets and RDS group as the source. Keep its life short; teardown follows acceptance.
- **Cost:** one db.t3.micro and a 20 GB snapshot for a few hours, a few cents.
