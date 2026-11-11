# SF.11 Stage B support: fixture upstream listener and the B0 operation record

Status: **Draft, revision 2 (2026-11-11)**. Revision 2 takes codex-1's review (APPROVE-WITH-CHANGES) and GitHub Codex's finding. The owner asked for this spec ("spec it"). Nothing is
built until the owner approves it and gives a first-hand go.

## Why

ShuttleForge's SF.11 Stage B loads fixture data into staging. B1 creates:
- one proxycheap account with no vendor credentials;
- one DISCRETE endpoint;
- one config bound to that endpoint.

SF's health checker probes that endpoint. While the endpoint answers, SF's `snapshot` check is `ok`
and SF reports `ready`; if it doesn't, SF reports `degraded`. Stage B needs an endpoint that
answers and goes nowhere.

SF also needs an operation record that Overcast owns, which SF's evidence links to. This is "B0", the
first step of SF's runbook `SF9_RECOVERY_RUNBOOK.md`, "Staging evidence order".

Two deliverables:
- **(A)** a fixture upstream listener;
- **(B)** the B0 operation record.

The SF facts come from SF's session (2026-11-11), cited against SF `55a2d20`:
- **Probe:** `asyncio.open_connection(host, port)`, then close (`services/health_checker.py:97-99`).
  It runs about every 60 s, sends no bytes, and times out after 5 s.
- **Address:** the endpoint's `host` is a free string, so a hostname works. Any TCP port works.
- **No other traffic:** no TLS, no proxy protocol. Nothing routes through the fixture config: the
  deny policy grants no lease, and the config's listener password is never retrieved.
- **Lifetime:** from B1 through B4, including the primary's restart check after B4. It must survive
  SF's restarts and B3's two redeploys. It is torn down with the fixture teardown, before Stage C's
  first live write.

## (A) Fixture upstream listener

### Design

| Item | Value |
|---|---|
| Flag | `sf_fixture_upstream_enabled` (bool, default `false`). Everything below is `count`-gated on it. Enable and teardown are each a one-line PR. |
| Service | the `ecs-service-fargate` module, `service_name = "fixture-upstream"`, desired 1, deployment 0/100. No target group, `internet_egress = false`, no RDS. |
| Name | Cloud Map A record `fixture-upstream.staging.internal.arclight-complex.net` (module default: TTL 10, MULTIVALUE, custom health). This is the `host` SF configures. |
| Port | TCP 8080. |
| Image | Overcast's own `arclight/dbbootstrap@sha256:5d05a32b5bde13c47b7eecef4da206dc78324feea732e10606c7ae1e69ba4147` (`v1-9264f1a`, the shared family's current image, postgres:16-alpine). Pinned by digest. Overcast owns the repository's retention, which keeps 10. |
| Command | `entryPoint = ["sh", "-c"]`, `command = ["exec busybox nc -ll -p 8080 -e /bin/busybox true"]`. This is busybox `nc` in persistent server mode (`-ll`). The parent keeps the listening socket, and each accepted connection runs `true` and closes at once. So there is no gap between connections, and a client that never closes can't block later probes (codex-1). stderr stays visible in the log. Alpine's busybox build enables `nc` server mode and `-e`, but the pinned digest is **Unverified** until acceptance check 1. If the flags aren't supported, the task exits at start, acceptance fails, and the fallback is the loop form `while true; do nc -l -p 8080 </dev/null >/dev/null; done`, with its known gap recorded. |
| Size | 256 CPU / 512 MiB. |
| Container health check | None. A probe that can't connect is the signal. |
| Execution role | A dedicated role. It allows only the ECR pull for `arclight/dbbootstrap` (plus `ecr:GetAuthorizationToken`) and `logs:CreateLogStream`/`PutLogEvents` on its own log group. No task role, no secrets, no ECS Exec. |
| Logs | `/arclight/staging/fixture-upstream`, 7-day retention. Container output goes to `/dev/null`, so the group holds only start-up and crash output. |

**Security group `fixture_upstream`** (own group, created in the root):
- ingress TCP 8080 from SF's group (`sg-075408be3ea36c30e`) only;
- egress 443 to the VPC-endpoint group and to the S3 gateway prefix list (`module.vpc.s3_prefix_list_id`), for the image pull and logs. This is the same pattern as NF's `nf_to_vpce_443` and `nf_to_s3_443`;
- no endpoint-side rule: the VPC-endpoint group already admits 443 from the private app subnet CIDRs as an inline rule (`terraform/modules/vpc/main.tf:141-147`). NF relies on the same rule. A standalone rule would also mix ownership with that inline ingress (codex-1);
- nothing else: no internet, no Core, no RDS.

SF's side needs no new rule. SF's DR-15 egress is all-TCP and open, and its own records note
that this matters for Stage B. NF's group has no 8080 egress, so NF can't reach the listener.

### Considered and rejected

- **Point SF at an existing listener**, for example `core-internal:443`. Zero infrastructure, but:
  - every probe is a TLS-less connect to Core's NLB, which adds noise to its client-TLS metrics;
  - SF's fixture health would track Core's availability;
  - a provider fixture would name a platform service.
- **A Python image** (Core's or NF's). It works, but it ties the fixture's lifetime to another
  module's ECR retention and release cadence.
- **A new purpose-built image.** That means a new Dockerfile and push path for a few days' fixture.

### Plan expectations (gates)

**Enable PR** (flag → `true`), an untargeted staging plan: only adds. In order:
1. the module's service, task definition and Cloud Map service;
2. the security group and its three rules (8080 ingress from SF; 443 egress to the VPC-endpoint group and to the S3 prefix list);
3. the execution role and its inline policy;
4. the log group.

There are no changes or destroys. `plan_guard` must pass. The PR carries the exact address list
from its own plan.

**Teardown PR** (flag → `false`): exactly the same addresses, destroyed, and nothing else.

### Acceptance (before SF's B1)

All probes run with `scripts/internal-tls-probe/run_probe.py` and are judged on each check's `pass`
field.
1. **Resolves and accepts repeatedly.** From SF's group, three **separate** probe runs, each with
   one `fixture-upstream…:8080:connect` check, and each must pass.
   - Three passes prove the `nc` loop re-listens; if busybox `nc` behaves differently, a later run
     fails here.
   - The runs are separate because `probe.py` keys results by the check string
     (`checks[spec] = r`, `scripts/internal-tls-probe/probe.py:104`). Repeating the same check in one
     run keeps only the last result (GitHub Codex review, PR #93).
2. **Isolation.** From NF's group, `fixture-upstream…:8080:blocked`.
3. **Survives restart.** Force a new deployment of `arclight-fixture-upstream-staging`, wait until
   stable, then repeat check 1. The name must resolve to the new task IP.
4. **Plan.** The post-apply plan reads "No changes".

Then Overcast gives SF `host = fixture-upstream.staging.internal.arclight-complex.net`, `port = 8080`.

### Operation and teardown

- **During Stage B:** no alarm. SF's `snapshot` check is the detector. If the listener stops, SF reports
  `degraded`; SF's B4 check and Overcast's deploy gate both fail closed on that.
- **Teardown:** the flag goes to `false`, together with or after SF's fixture teardown (B6), and
  before Stage C's first live write. It is recorded in the B0 record (below).
- **Cost:** 0.25 vCPU / 0.5 GB Fargate, about $0.30 per day. Logs are negligible.

### Rollback

Flip the flag to `false`. Nothing else depends on the listener.

## (B) B0 operation record

### Location

`docs/operations/sf-stage-b-record.md`, a new directory. The file is created by a PR before B1;
every later entry is a PR. Each version has a commit and a permanent URL. SF links the file's URL,
and pins each entry to its merge commit.

The repository is public, so the record holds:
- identifiers only: ARNs, names, digests, snapshot IDs and VersionIds. Never values;
- the operator as a role ("owner", "Overcast (claude-main)"), never a personal name or address;
- no recipient or customer data of any kind.

### Template (fields from SF's runbook)

```
## Entry B0: Stage B operation record (opened <UTC>, PR #<n>)
- Target environment: staging (account 650880817826, us-east-1)
- Resources:
  - service arclight-shuttleforge-staging and task family arclight-shuttleforge-staging;
  - migrate family arclight-shuttleforge-migrate-staging;
  - database instance arclight-staging, database shuttleforge_staging;
  - NLB arclight-stg-int-sf; ALB arclight-staging; fixture listener (section A).
- Operator: owner (go first-hand in Overcast's session, <UTC>); executor: Overcast (claude-main)
- Images:
  - N-1 (currently deployed): sha256:f57384de90d40a9212fe75fda8eaf553c97f8a4efcf6f786457b667ad232f5f4
    (v1-55a2d20, r6), revision <n>;
  - N: <digest from SF when pushed> (<tag>).
- Expected schema: sf9_5b_pg_baseline
- Recovery point (filled at B4):
  - RDS snapshot <id> at <UTC>;
  - PITR window <earliest>–<latest>.
- Secret-version references (VersionIds only), each listed with the secret name and VersionId:
  - SF leaves: 136471e5…, 8541ff69…, f4b76d30…, cc0c6a76…;
  - db-url and db-url-migration;
  - B4's target-URL secret.

## Entry B6: fixture teardown receipt
- Decision, UTC time, affected resources (including the fixture listener flag), recovery points,
  key-version references, executor, outcome.
- If staging holds live operational material at teardown time, this entry instead carries every
  field of SF's "Live-material teardown authorization" (SF9_RECOVERY_RUNBOOK.md at SF 55a2d20):
  - record URI/ID, operator identity, approve/refuse decision, UTC time;
  - exact resources, action, reason, scope and window;
  - the live-material classification and what is retained;
  - recovery points, image/schema identities, restore verification and key-version/custodian references;
  - executor, match confirmation, stop/drain state, outcome and evidence location;
  - any deletion-protection approval, and its re-enable result.
```

Overcast fills in the full secret names and VersionIds from `describe-secret`
(`VersionIdsToStages`), never from a value read. Before B1 Overcast checks each one against SF's
list.

## Not in scope

- Removing `scripts/sf-first-admission.jq` and its use in `deploy-service.yml`. That is a separate,
  small PR, after B1 is accepted.
- B3's deploy path, which is chosen when B3 is scheduled.
- Any change to SF's egress (DR-15) or to the internal-TLS paths.
- The other Overcast steps in SF's runbook "Staging evidence order", which SF will ask for separately (B0-B6):
  - step 3, deployed infrastructure facts;
  - step 6, the RDS snapshot restore to a separate protected target (so the shared instance that
    Nerfherder uses is not touched);
  - step 7, the D-059 attestation.
  Each gets its own entry in the B0 record.
