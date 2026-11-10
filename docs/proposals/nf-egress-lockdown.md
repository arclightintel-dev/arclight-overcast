# Nerfherder egress lockdown: no internet path from NF's group (C-G7, DR-20, O-017)

Status: **Revision 2, approved by the owner (merged `e6ff2d1`). L1 and L2 APPLIED 2026-11-10
(PR #79; owner: "good to go on green"); acceptance passed.** The record is in
`docs/PROJECT_STATE.md`, DR-20.

Revision history:
- **Revision 1** (`b792de3`) was reviewed by codex-1, codex-2 and hotpants. All three returned
  GO-WITH-CHANGES with no P1 finding.
- **Revision 2** folds in their findings and NF's answers of 2026-11-10 (see "Review record").

## Why

- **C-G7** (ShuttleForge Stage C gate: "SF is NF's only internet path") is **not met**. Read-outs
  2026-11-10, re-checked against live state before this draft:
  - NF's group `sg-07db42cb0f485be83` allows `tcp 443 → 0.0.0.0/0`. This is the Fargate module's
    unconditional `https_egress` (`terraform/modules/ecs-service-fargate/main.tf:56-64`).
  - NF's subnets route `0.0.0.0/0` to `nat-0cf57f84d01bb8c18`, and the NACL allows all.
  - NF's other egress is security-group to security-group only: Core 8000, SF 9000/9050/9100,
    RDS 5432 and self 8100.
- **DR-20.** `NERFHERDER_EGRESS_MODE=sf_required` is enforced in NF's configuration, not the
  network.
- **NF's manifest expects this change.** At NF main `809c130` (`docs/DEPLOYMENT_MANIFEST.md`):
  - l.183: "443 to the interface-endpoint group (ECR api and dkr, Logs; Secrets Manager
    proposed)";
  - l.184: "443 to 0.0.0.0/0 today (… Overcast proposes removing it once Secrets Manager has its
    endpoint)".
  - NF drops "proposed" at L1 and removes l.184 at L2, as docs-only changes. Overcast tells NF
    before each.
  - The code inventory below is pinned at `0f755ea3`. The 16 commits up to `809c130` touch no
    `src/` file.
- **Owner rulings, 2026-11-10:**
  - spec the lockdown (C-G7 / DR-20);
  - **O-017: consumer services get no internet egress by default. Core and ShuttleForge keep it
    explicitly.**

## What NF actually needs

Overcast's read-only inventory of NF at `0f755ea3` (main, 2026-11-10). Paths are NF's.

| Destination | Port | Who dials | Path after this change |
|---|---|---|---|
| Core token endpoint | 443 | NF code (httpx) | Core's internal NLB: a **new** rule to `core_nlb` SG |
| Core :8000 (plain) | 8000 | nobody when hosted: NF refuses plain HTTP to Core (`config.py:158-164`) | existing rule, removed by internal-TLS P3 |
| SF lease API, proxy | 9000, 9050, 9100 | NF code | existing SG-to-SG rules (P2 adds SF's NLB pairs) |
| RDS | 5432 | every NF task family | existing module rule |
| NF's S3 bucket | 443 | NF code (boto3, task role); the only SDK client (`storage.py:168-175`) | S3 gateway endpoint: a **new** rule to prefix list `pl-63a5400a` |
| Secrets Manager | 443 | Fargate, at task start, over the task ENI | a **new** interface endpoint, and a **new** rule to the endpoint SG |
| ECR api/dkr | 443 | Fargate, image pull | existing endpoints; endpoint SG rule (new); layers through the S3 prefix list |
| CloudWatch Logs | 443 | Fargate `awslogs` | existing endpoint; endpoint SG rule (new) |

**Not filtered by a security group** (*Control traffic to your AWS resources using security
groups → Security group basics*): Amazon DNS, the ECS task metadata endpoints (which serve the
task-role credentials) and the Amazon Time Sync Service.

**Not needed** (Proven at `0f755ea3` unless marked):
- **STS and SSM.** NF never calls them. DR-20's mention of an STS endpoint is withdrawn.
- **KMS.** Secrets Manager decrypts server-side. NF's execution role allows `kms:Decrypt` only
  with `kms:ViaService = secretsmanager` (`nerfherder.tf`, `nf_exec_common`). Inferred from the
  policy shape, not a call trace.
- **The event sink.** Hosted start refuses `event_sink_mode != disabled` (`host.py:1066-1067`).
- **A JWKS fetch.** The URL is validated and never fetched; verification uses a static key file
  (`auth.py:50-89`).
- **Telemetry and update checks.** No exporter, update or license call (grep).

**Platform requirement** (*Migrating to Linux platform version 1.4.0 on Amazon ECS*): from
platform version 1.4.0 all task traffic, including secret retrieval and image pull, flows
through the task ENI.
- With interface endpoints, Fargate needs `ecr.dkr`, `ecr.api`, the S3 gateway endpoint and the
  Secrets Manager endpoint.
- The task's security group must allow traffic to the endpoints.
- Staging services set no `platform_version`, so they run `LATEST` (1.4.0).

## Design

### D1. Secrets Manager interface endpoint (staging)

- `module "vpc"` in `terraform/envs/staging/main.tf` gains
  `extra_interface_endpoints = ["secretsmanager"]`.
  - It uses the existing pattern (`terraform/modules/vpc/main.tf:197-219`): private DNS on, the
    shared endpoint SG, which admits 443 from the private app subnet CIDRs.
  - Prod already runs one, under the same variable.
- **Private DNS makes it the only Secrets Manager path for every staging task**: Core, SF,
  dbbootstrap and probes.
  - All of them already allow 443 to `0.0.0.0/0`, which covers the endpoint's ENI addresses. So
    no other group needs a rule.
  - Running tasks are unaffected; Fargate reads secrets only at task start.
- **AZs: both private app subnets (recommended; the default when
  `extra_interface_endpoint_subnet_indexes` is unset).** With private DNS, a one-AZ endpoint is a
  single point of failure for every task start in staging.
  - Cost: 2 × $0.01/h ≈ $14.60/month, plus $0.01/GB.
  - One AZ halves the hourly cost. That is the owner's call; this spec recommends two.
- **Endpoint policy: the AWS default (full access).** IAM on each execution role still scopes
  which secrets a task can read. A restrictive endpoint policy is not proposed: no consumer needs
  it, and governance is earned.

### D2. The Fargate module: internet egress is opt-in (O-017)

In `terraform/modules/ecs-service-fargate`:
- **New variable** `internet_egress` (bool, **default `false`**). It controls the module's
  `443 → 0.0.0.0/0` rule.
- `aws_security_group_rule.https_egress` gains `count = var.internet_egress ? 1 : 0`.
  - **Its description stays as it is.** Changing it would turn Core's and SF's moves into
    in-place updates and break L2's exact-plan gate (codex-1).
  - The O-017 explanation goes in a code comment instead.
- **A `moved` block** in the module, from `aws_security_group_rule.https_egress` to
  `aws_security_group_rule.https_egress[0]`:
  - Core and SF keep their rules with no replacement and no egress gap;
  - NF's instance moves, then is destroyed because its count is 0.
- **Callers:**
  - `core_service`: `internet_egress = true`. Core keeps it by the owner's ruling (O-017).
    Declaring what Core dials externally is Core's job; Overcast has not inventoried it.
  - `shuttleforge_service`: `internet_egress = true`. SF keeps it (O-017). Its DR-15 rule
    (`sf_provider_egress`, all TCP to any address) is independent and unchanged.
  - `nerfherder_service`: omits it, so the default `false` applies.
- `aws_ecs_service.this` keeps `depends_on = [aws_security_group_rule.https_egress, …]`. A
  reference to a counted resource is valid at zero instances.

### D3. NF's explicit egress (`terraform/envs/staging/nerfherder.tf`)

**New rules** on `aws_security_group.nerfherder`, all `tcp 443`:

| Rule | Destination | Pairs with |
|---|---|---|
| `nf_to_vpce_443` | the endpoint SG (new VPC module output `sg_vpc_endpoints_id`) | the endpoint SG's existing CIDR ingress |
| `nf_to_s3_443` | `prefix_list_ids` = the S3 gateway's prefix list (new VPC module output `s3_prefix_list_id`, from `aws_vpc_endpoint.s3.prefix_list_id`) | the gateway route, already on the private app route table |
| `nf_to_core_nlb_443` | `aws_security_group.core_nlb` | the existing `core_nlb_from_nf_443` ingress |

**Unchanged:**
- `nf_to_core` 8000, until internal-TLS P3 removes it;
- `nf_to_sf` 9000/9050/9100;
- the module's `rds_egress`;
- `nf_probe_self` and `nf_probe_self_egress`.

The comment at `nerfherder.tf:44` ("The Fargate module adds 443 egress…") is rewritten to name
the three rules and O-017.

### D4. What does not change

- **The NAT route and the NACL.** Core and SF share NF's subnets and need the NAT.
  - Enforcement is NF's security group. It is the only egress control on NF's task ENIs, and no
    rule in it names an internet destination.
- **The dbbootstrap group keeps its open 443** (`main.tf:267-275`).
  - It is operations tooling, not a consumer service (O-017's scope).
  - It runs every module's migrations, including NF's migrate family at N-G3.
  - NF's migrations make no HTTP or AWS calls (`alembic/`, Proven).
  - Locking it the same way takes the same three rules. **Owner's call; not proposed here.**
- **SF's own groups and P2's NLB pairs.** P2 adds NF's rules to SF's NLB on its own plan.
  - NF reaches SF only on 9000, 9050 and 9100: to SF's tasks before P3, and to SF's NLB after
    (internal-TLS spec l.60 and l.221). Neither path uses 443, so this change never touches NF's
    route to SF.
- **Prod.** NF does not run there (D-072).

### D5. An injection canary, so the new path is proven before any real start

Secret injection is the endpoint's main new dependency. Fargate performs it before the
application starts, so it can be proven with an inert task (codex-2).

**Revision 2 uses Overcast's own canary, not a module's secret:**
- **Shell:** `aws_secretsmanager_secret.probe_canary`, named `arclight/<env>/probe/canary`. Its
  value is a fixed, non-sensitive string, set out of band with `put-secret-value` at L1, so it
  never enters state (INV-004).
- **Role:** the canary uses the default `aws/secretsmanager` key, as every staging shell does
  (`modules/secrets` sets no `kms_key_id`). `probe_exec` gains only
  `secretsmanager:GetSecretValue` on `aws_secretsmanager_secret.probe_canary.arn`.
  - No KMS statement is needed (codex-1's delta review). Revision 2's
    `kms:ViaService = secretsmanager.<region>` was both unnecessary and wrong: the value ends in
    `.amazonaws.com`.
- **Probe:** `run_probe.py --canary` adds the binding `PROBE_CANARY` to the registered revision
  **only when the flag is given**. Injection happens before Python starts, so an unconditional
  binding would change ordinary runs.
  - `probe.py` reports only `canary: present` and the value's length.
  - The value never enters the `PROBE` dictionary, an assertion message, exception text or an
    environment dump.
- **Why not a Core secret** (codex-2's proposal)? That would place a module's secret in an
  Overcast test task. The canary keeps custody with the modules, and it is reusable for the next
  consumer lockdown.

Cost: about $0.40/month.

## Phases

Two applies, so the endpoint can be verified while NF still has its open path.

**L1: endpoint, canary and outputs.** No change to any group's rules.
- **Expected plan**, exactly:
  - `+1` `module.vpc.aws_vpc_endpoint.extra["secretsmanager"]`;
  - `+1` `aws_secretsmanager_secret.probe_canary`;
  - `~1` `aws_iam_role_policy.probe_exec` (the D5 statements only);
  - two new module outputs.

  There are no Route 53 resources: AWS manages the private DNS (codex-1).
- **Gate:** no ECS rollout in flight (any service), and `plan_guard` OK.
- **After the apply:** set the canary's value. Tell NF before the apply.

**L2: the lockdown.**
- **Expected plan:**
  - two pure moves, `module.core_service…https_egress` and
    `module.shuttleforge_service…https_egress` to `[0]` (no-op, `previous_address` set);
  - `-1` `module.nerfherder_service.aws_security_group_rule.https_egress[0]`, moved and then
    destroyed;
  - `+3` the NF rules in D3;
  - **nothing else:** no update, and no ECS service or task-definition change.
- **Gate:**
  - L1's acceptance passed;
  - the plan JSON matches the expected list exactly;
  - `plan_guard` OK;
  - NF told.

NF and SF are at 0/0 (`describe-services`, 2026-11-10), so L2 changes no running task's path.

## Acceptance

All probes are one-off tasks in NF's group (`scripts/internal-tls-probe/`, extended as below),
in the private app subnets with no public IP.

**L1:**
1. From NF's group, `secretsmanager.us-east-1.amazonaws.com` resolves only to addresses in
   `10.0.10.0/24` and `10.0.11.0/24`, and a TLS handshake to it verifies against public roots.
2. **Canary injection** (`--canary`) succeeds from NF's group: the task reaches RUNNING, and the
   probe reports `canary: present`.
   - With item 1 confirming private resolution, that supports the documented endpoint path.
   - **Attribution:** CloudTrail's `GetSecretValue` event for the canary at that time carries
     the new endpoint's `vpcEndpointId` (codex-1). That makes item 2 discriminating at L1.
   - L2 item 3 additionally proves injection with public HTTPS denied.
3. **Positive control for L2's negative.** From NF's group, `1.1.1.1:443` and one IPv4 address
   of `example.com` **connect on 443**.
   - Record the exact IP:port pairs; L2 reuses them, not a fresh DNS answer. Each must be outside
     the S3 prefix list's CIDRs.
   - Port 80 to the same addresses is already blocked and is recorded as blocked.
4. The next Core deploy (S-057) is the first module injection through the endpoint. It is
   watched, not forced.

**L2 (discriminating):**
1. **The probe task starts and its log arrives.**
   - That proves the ECR endpoints, the S3 prefix list for layers, and the Logs endpoint from
     NF's group.
   - Linux Fargate does not cache image layers (codex-1).
2. **Core.** `core-internal` gives verified TLS and `/ready` 200 through each node IP.
3. **Canary injection** still succeeds, now with no open 443.
4. **S3.** These hosts resolve inside the prefix list's CIDRs and complete a verified TLS
   handshake:
   - required: `arclight-staging-nerfherder-artifacts.s3.amazonaws.com:443`, the global host NF
     reports for its boto3 1.43.77 build;
   - also: `arclight-staging-nerfherder-artifacts.s3.us-east-1.amazonaws.com:443`, because NF
     pins only `boto3>=1.34` and a later default could change (codex-1).
5. **Negative: no internet path.**
   - The exact IP:port pairs that connected in L1 item 3 now **time out** on 443.
   - Port 80 to the same addresses stays blocked.
6. **Core and SF unaffected.** Both services are steady, and their groups' egress rules are
   identical before and after (`describe-security-groups`).
7. **The exact NF proof** comes at N-G4, when NF's service task first starts with its own
   secrets. If that start fails with `ResourceInitializationError`, roll back L2.
8. **C-G7's operational evidence** is not this receipt. L2 can pass with SF at 0/0. Before
   NF's first collection, NF's lease smoke runs under the deployed restrictions. The internal-TLS
   spec's acceptance P2 already requires it ("The proxy path is proven by NF's lease smoke")
   (hotpants).

**Probe extension** (implementation PR):
- an optional list of `host:port:expect` checks, where `expect` is `tls`, `connect` or
  `blocked`. Each result goes in the `PROBE` line.
- `--canary` (D5).

The existing checks do not change.

## Rollback

- **L2:** set `internet_egress = true` on `nerfherder_service`. One apply re-creates the
  `443 → 0.0.0.0/0` rule at `[0]`, with a new rule ID. The three new rules can stay.
- **L1:** roll back L2 first, then remove `"secretsmanager"` from `extra_interface_endpoints`.
  Secrets Manager then reverts to the NAT path for every task.
  - Core, SF and dbbootstrap all keep `443 → 0.0.0.0/0`, so they work either way.
  - The canary can stay.

## Risks

- **Staging-wide private DNS (D1).** A broken endpoint stops every task start that injects
  secrets.
  - Mitigations: two AZs, L1's resolution and canary checks, and watching the next Core deploy.
  - The rollback is one apply.
  - The endpoint group admits only the private app subnets, so a one-off task placed elsewhere
    cannot reach it.
  - The runbooks place dbbootstrap tasks in the app subnets. Core's migration run in
    `deploy-service.md` (l.105) has a placeholder network configuration (codex-1). Name the app
    subnets there (DR-22).
- **The S3 prefix-list rule is service-wide, not bucket-specific** (hotpants).
  - NF's bucket scope comes from its task role.
  - At the network level, NF can still reach any us-east-1 S3 bucket. That includes an origin
    hosted on S3, or a foreign bucket that accepts writes.
  - NF's code refuses direct source paths (`sf_required`, Proven at `0f755ea3`).
  - Closing the network gap needs a gateway endpoint policy, for example
    `aws:ResourceAccount` = this account plus the ECR layer bucket. That would affect **every**
    staging task, so it is not proposed here.
- **Fargate agent traffic.** AWS says Fargate needs no ECS interface endpoints (codex-1, ECS
  VPC endpoints guide). L2 item 1 confirms it.
- **SF's `transport_endpoint`.** NF dials whatever host and port SF's lease returns, with no
  allowlist (`strategies.py:352-360`).
  - It is independent of this change, because NF never reaches SF on 443 (D4).
  - It is an activation dependency for P2, P3 and N-G4. A destination outside the permitted SF
    path fails closed, which is the intent.
  - SF confirms the :9100 route's port at P2.
- **Core's exception: purpose declared (hotpants, P3; answered by Core on 2026-11-10).**
  - Source: Core's code at `6645079`, the S-057 head, unchanged from the live `08de4e6`.
    Core-reported; not re-verified by Overcast.
  - **All of Core's internet egress is the human-login path,** HTTPS on 443:
    - Entra: `login.microsoftonline.com` (discovery, token, JWKS);
    - Google: `accounts.google.com` and the endpoints it names;
    - GitHub OAuth: `github.com` and `api.github.com`.
  - The hosts follow the bound identity brokers (`identity_provider_brokers` rows).
  - Calls happen in **human identity-provider login and linking flows**, including
    `/auth/link` and browser login when enabled. Service-token issuance makes no such calls.
    codex-1's delta review found the linking path at Core `6645079`
    (`api/routes/auth.py:1425` → `services/oidc_service.py:112`).
  - Core has no AWS SDK, webhook or mail traffic.
  - Core will add a `network.egress` declaration in NF's shape after S-057 (tracked by Core).
  - Overcast prescribes no schema, because governance is earned.
  - Core keeps open 443 by O-017. A security group cannot filter by host name, so narrowing
    Core is not proposed.
- **A future NF dependency** (telemetry, a JWKS fetch) needs an explicit rule. NF's manifest
  egress list is the contract; a change to it is a change request to Overcast.
- **SG-only enforcement** fails if an open rule or an open group is later added to NF's task
  (codex-2). The plan gate and this spec's rule list are the control. A consumer subnet split is
  not warranted now.
- **ECS Exec stays off (O-018).** No `ssmmessages` endpoint is needed.

## Decisions recorded with this spec

- **O-017:** consumer services get no permitted direct internet egress by default.
- **O-018:** no ECS Exec for ShuttleForge.

Both are in `docs/DECISIONS.md`.

## Review record

Revision 1 `b792de3`; codex-1, codex-2 and hotpants (gpt-6-astra, ultra, read-only); all
GO-WITH-CHANGES, no P1.

| Finding | From | Disposition |
|---|---|---|
| The TCP 80 positive control can never pass (NF allows only 443 today) | all three | **Accepted:** 443 connects before and times out after; 80 is blocked both times |
| D2's description change makes Core's and SF's moves updates, breaking the exact-plan gate | codex-1 | **Accepted:** description unchanged; L2 is now 3 create, 1 destroy, 2 no-op moves |
| Injection can be proven before N-G4 with an inert task | codex-2 | **Accepted, with Overcast's own canary (D5)** instead of a Core secret |
| O-017's "no route" contradicts keeping the NAT route | codex-2 | **Accepted:** "no permitted direct internet egress from its task ENI" |
| Core's exception has no declared dependencies | hotpants | **Accepted; answered by Core on 2026-11-10:** login-path only (see Risks) |
| The S3 prefix-list rule is service-wide | hotpants | **Accepted:** wording, plus the residual and the endpoint-policy option (not proposed) |
| NF's boto3 is unpinned (`>=1.34`) | codex-1 | **Accepted:** the global host is required, the regional host also probed |
| C-G7 needs operational evidence, not just a network receipt | hotpants | **Accepted:** L2 item 8 |
| Placement of Core's migration run task is unverified | codex-1 | **Accepted:** a risk line; the fix belongs in DR-22's runbook pass |
| The O-018 one-off pattern proves connectivity, not SF's live-provider behaviour | hotpants | **Noted:** SF's behavioural checks are SF's (its logs and `/ready/detail`) |
| L1 creates no Route 53 resources; outputs don't change prod's plan | codex-1 | **Folded** into L1's expected plan |

**Delta review of revision 2** (`b792de3..4286405`; codex-1; GO-WITH-CHANGES, no P1; every
revision-1 finding mapped as resolved):

| Finding | Disposition |
|---|---|
| P2: D5's KMS grant has the wrong `kms:ViaService` value and is unnecessary for the default key | **Accepted:** KMS statement deleted; `GetSecretValue` on the one ARN only |
| P3: Core's outbound calls also occur on `/auth/link` and browser login | **Accepted:** wording fixed; Core told |
| P3: reuse L1's exact IP:port pairs at L2; L1 injection alone does not attribute the path | **Accepted:** pinned pairs, and CloudTrail `vpcEndpointId` attribution at L1 |
| Plans exact (L1: 2 create, 1 update; L2: 3 create, 1 destroy, 2 no-op moves); secret recovery window defaults to 30 days; no resource policy needed | **Confirmed** |

**NF's answers (2026-11-10):**
- `transport_endpoint` is SF's value, and is independent of 443 (D4).
- The S3 host is global, as above.
- NF's T2 S9 counts `core_auth.unreachable` (internal-TLS amendment 3a).
