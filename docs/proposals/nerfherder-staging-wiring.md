# Nerfherder staging wiring (O-013)

Status: **built, not applied.** Owner 2026-11-09: build NF's wiring now, in parallel with SF's
remaining gates; every apply needs the owner's go first-hand. Inputs: NF's accepted manifest at
`cf5b228` (final for every rendered value), O-013, and Overcast's nine confirmations of
2026-10-29. Nothing contradicts them.

## Built (`terraform/envs/staging/nerfherder.tf`)

**Network.** A new `nerfherder` security group and its rules:
- Egress: 443 and 5432 (from the Fargate module), Core 8000 (token endpoint), and ShuttleForge
  9000, 9050 and 9100.
- Matching ingress on Core 8000, on ShuttleForge's 9000/9050/9100 (**O-1**, rescoped to NF), and
  on RDS 5432.
- A self rule on 8100 for one-off probe tasks: NF's post-deploy check reads `/ready/detail`, and
  nothing else can reach NF.
- Not behind the ALB.

**Service.** 1 vCPU / 2 GB, port 8100, Cloud Map `nerfherder`, 0/100 (**O-2**), stopTimeout 35.
- The python health check follows NF's compose precedent; the image has no curl.
- The manifest's staging environment: `NERFHERDER_EGRESS_MODE=sf_required`, and the three S3
  values as empty strings.
- Two secrets: `database-url` (runtime) and `core-client-secret`.
- Base revisions name an all-zero digest, as for ShuttleForge.

**Families.**
- **Migrate:** `python -m nerfherder.migrate`; it binds only `migration-database-url` and has its
  own execution role.
- **Bootstrap:** `python -m nerfherder.bootstrap --input-env NERFHERDER_BOOTSTRAP_INPUT`, runtime
  URL, the S3 environment and the task role. NF's evidence export and diagnostics run as command
  overrides of it.

**Roles.**
- The runtime execution role reads only `database-url` and `core-client-secret`.
- The migrate execution role reads only `migration-database-url`.
- The task role has S3 `ListBucket` (no prefix condition) and Get/Put/Delete on `bucket/*`.
- **Push role:** `arclight-nerfherder-ecr-push-staging` trusts `arclight-nerfherder` on `main`.
  The owner sets `NERFHERDER_ECR_PUSH_ROLE_ARN` in NF's repository when authorizing the run.

**Bucket** `arclight-staging-nerfherder-artifacts`:
- public access blocked, bucket-owner ownership, SSE-S3, TLS-only policy;
- **no expiration or transition**: artifact keys share no prefix a rule could exempt;
- only incomplete multipart uploads expire, after 7 days.

**Logs and alarm.** Log group `/arclight/staging/nerfherder` (30 days). The running-task alarm goes
to the staging alarm topic, with actions enabled only while the desired count is 1.

**Database.**
- `dbbootstrap nf-app-role` (image `v1-4a9ce79`) creates `nerfherder_app_staging` with NF's
  grants: no sequences, `alembic_version` read-only, no connection limit.
- It runs in its own family (`arclight-dbbootstrap-nf-staging`, default command `nf-app-role`), so
  the shared bootstrap task, including ShuttleForge's post-migration re-run, never waits on NF's
  shells.

**Secret values.** `scripts/sf-staging-secrets.ps1 -Service nerfherder` runs `Prepare` and
`RuntimeUrl`, as for ShuttleForge.

## Sequence (each step on the owner's go)

1. **N-G1:** targeted staging apply of the above. Nothing runs.
   - Targets: `module.nerfherder_service`, `module.iam_github_oidc`, `module.rds`,
     `aws_iam_role_policy.dbbootstrap_secrets`, and every resource in `nerfherder.tf`.
   - The targeted plan must read **38 to add, 1 to change, 0 to destroy**. The Core
     task-definition churn stays out.
   - **Exit check before N-G2:** `describe-task-definition` on `arclight-nerfherder-staging` and
     `arclight-nerfherder-bootstrap-staging` shows all three `NERFHERDER_S3_*` keys present with
     value `""`, and a full plan afterwards shows no diff on Nerfherder's task definitions.
   - If ECS stripped them, stop: NF's defaults (`minioadmin`, `localhost`) would make the hosted
     start refuse. The fix is on NF's side.
2. **N-G2:**
   1. An administrator builds and pushes `dbbootstrap:v1-4a9ce79`.
      Record `SHOW max_connections` while there (the RDS alarm is at more than 40).
   2. The owner runs `-Service nerfherder -Phase Prepare`, which copies the owner URL from
      `database-url` into `migration-database-url` and generates the app password.
   3. Run `nf-app-role`.
   4. The owner runs `-Phase RuntimeUrl`.
   5. Remove the old version's `AWSPREVIOUS` label, as for ShuttleForge.
3. **N-G3:** NF pushes its image. Register the migrate family on its digest, run it in the
   dbbootstrap group, then re-run `nf-app-role`.
4. **N-G4:**
   1. Register the service revision on the digest and run `update-service --desired-count 1`.
   2. **Probe.** Register a copy of the latest `arclight-nerfherder-bootstrap-staging` revision
      on the real digest, then run it once in NF's security group and the private-app subnets,
      with no public IP. Override the command to
      `python -c "import urllib.request; print(urllib.request.urlopen('http://nerfherder.staging.internal.arclight-complex.net:8100/ready/detail', timeout=5).read().decode())"`.
      Run it only after ECS has registered the service task in Cloud Map. Its log stream is the
      evidence. Check the body for `host_lease` held.
   3. Flip `nerfherder_desired_count` to 1.
   4. Record the 15-minute `DatabaseConnections` baseline before start, the TLS receipt
      (`rds.force_ssl = 1`, plaintext refused) and ECS CPU and memory, as NF asked.

**N-G4 is useful only after ShuttleForge serves leases:** SF r5 and G3/G4, provider enrollment,
the reviewed policy (DR-16) and SF egress (DR-15). Until then NF starts but every source route is
refused at admission (`sf_required`). That is correct behaviour, not a fault.

## Notes for NF

- **stopTimeout** is exactly NF's 35 s drain budget (3 + 25 + 5). If a drain overruns and ECS
  kills the task, the stale PostgreSQL session keeps the host lease until RDS reaps it, and the
  new task waits in standby while reporting healthy. Fargate allows up to 120 s if NF wants a
  margin.
- **Empty strings.** The three empty `NERFHERDER_S3_*` values must reach the container as `""`:
  this is the N-G1 exit check, unproven until then. Nothing in this repository used an empty
  value before.
- **Bootstrap pool.** The bootstrap family runs NF's default pool of 10 plus 20 overflow. The
  service runs 5 plus 5. Should the family carry 5/5 as well? This departs from the manifest, so
  it's NF's call.
- **Narrower delete.** NF deletes objects only under `_uncommitted/`. Narrowing
  `s3:DeleteObject` to `_uncommitted/*` would protect `evidence/`. This departs from manifest line
  97, so it's NF's call.
- **Sequences.** `event_chain_state.id` has an implicit sequence that is never used: the row is
  seeded and inserts are blocked. No grant is needed.
- **Merge order.** Merge this after PR #62 (O-016): the shared push-role map would otherwise also
  add an NF role to prod, which no longer uses the module. PR #64 is a draft until then.
- **Changes from review (2026-11-09):**
  - the alarm uses 60 s periods over 5 evaluations, so only five minutes with no running task
    alarms (a stop-then-start deploy doesn't);
  - the health check's startPeriod is 60 s, for a cold Fargate start.
