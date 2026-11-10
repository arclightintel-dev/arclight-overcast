# Nerfherder egress lockdown: no internet path from NF's group (C-G7, DR-20, O-017)

Status: **DRAFT revision 1, for review. Nothing built or applied.** Each phase is applied only on
the owner's go, given first-hand.

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
- **NF's manifest expects this change.** Its egress list keeps "443 for secret injection" only
  until Overcast's interface endpoints exist (NF `docs/DEPLOYMENT_MANIFEST.md:185` at
  `0f755ea3`).
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
- `aws_security_group_rule.https_egress` gains `count = var.internet_egress ? 1 : 0`, and its
  description becomes "HTTPS to the internet (O-017 opt-in)".
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
- **Prod.** NF does not run there (D-072).

## Phases

Two applies, so the endpoint can be verified while NF still has its open path.

**L1: endpoint and outputs.** No change to any group's rules.
- **Expected plan:** `+1` `module.vpc.aws_vpc_endpoint.extra["secretsmanager"]`; two new module
  outputs; nothing else.
- **Gate:** no ECS rollout in flight (any service), and `plan_guard` OK.

**L2: the lockdown.**
- **Expected plan:**
  - `moved`: `module.core_service…https_egress` → `[0]` and
    `module.shuttleforge_service…https_egress` → `[0]` (no change);
  - `-1` `module.nerfherder_service.aws_security_group_rule.https_egress[0]`;
  - `+3` the NF rules in D3;
  - nothing else. In particular, no change to any ECS service or task definition.
- **Gate:**
  - L1's acceptance passed;
  - the plan JSON matches the expected list exactly;
  - `plan_guard` OK.

NF and SF are at 0/0 (`describe-services`, 2026-11-10), so L2 changes no running task's path.

## Acceptance

All probes are one-off tasks in NF's group (`scripts/internal-tls-probe/`, extended as below),
in the private app subnets with no public IP.

**L1:**
1. From NF's group, `secretsmanager.us-east-1.amazonaws.com` resolves only to addresses in
   `10.0.10.0/24` and `10.0.11.0/24`, and a TLS handshake to it verifies against public roots.
2. A Core task start is not required. The next Core deploy (S-057) is the first secret
   injection through the endpoint; it is watched, not forced.

**L2 (discriminating):**
1. **The probe task starts and its log arrives.** That proves the ECR endpoints, the S3 prefix
   list for layers, and the Logs endpoint from NF's group.
2. **Core.** `core-internal` gives verified TLS and `/ready` 200 through each node IP.
3. **Secrets Manager.** TLS to the endpoint name verifies.
4. **S3.** NF's bucket host, in the form botocore uses for `us-east-1` (`<bucket>.s3.amazonaws.com`
   and the regional `<bucket>.s3.us-east-1.amazonaws.com`), resolves inside the prefix list's
   CIDRs and completes a verified TLS handshake.
5. **Negative: no internet path.**
   - TCP 443 and TCP 80 to two public addresses outside AWS's S3 ranges (for example
     `1.1.1.1:443` and the resolved address of `example.com`) **time out**.
   - Run the same probe once **before** L2 as the positive control: it must connect.
6. **Core and SF unaffected.** Both services are steady, and their groups' egress rules are
   identical before and after (`describe-security-groups`).
7. **Secret injection in NF's group, end to end,** is proven at N-G4, when NF's service task
   first starts with its secrets. It cannot be proven earlier without an NF image.
   - If that start fails with `ResourceInitializationError`, use the rollback below.

**Probe extension** (implementation PR): an optional list of `host:port:expect` checks, where
`expect` is `tls`, `connect` or `blocked`. The probe prints each result in the `PROBE` line. No
change to the existing checks.

## Rollback

- **L2:** set `internet_egress = true` on `nerfherder_service`. One apply restores the
  `443 → 0.0.0.0/0` rule at `[0]`. The three new rules can stay.
- **L1:** remove `"secretsmanager"` from `extra_interface_endpoints`. Secrets Manager reverts to
  the NAT path for every task.
  - Core, SF and dbbootstrap all keep `443 → 0.0.0.0/0`, so they work either way.
  - NF needs L2 rolled back first.

## Risks

- **Staging-wide private DNS (D1).** A broken endpoint stops every task start that injects
  secrets.
  - Mitigations: two AZs, L1's resolution check, and watching the next Core deploy.
  - The rollback is one apply.
- **The S3 hostname form (Inferred).** botocore's default for `us-east-1` is the legacy global
  host. Its addresses are us-east-1 S3 ranges, which should be in `pl-63a5400a`. Acceptance
  item 4 decides.
- **Fargate agent traffic (Inferred).** ECS's network guidance lists agent management and
  telemetry endpoints for custom firewalls. On Fargate the agent is AWS-managed and is not
  expected to use the task's security group. Acceptance item 1 (the task starts, runs and stops
  normally) decides.
- **SF's `transport_endpoint`.** NF dials whatever host and port SF's lease returns, with no
  allowlist (`strategies.py:352-360`).
  - With only SG-to-SG rules to SF on 9050/9100, any other destination fails closed, which is
    the intent.
  - Asked NF and SF which host form SF returns in staging (2026-11-10).
- **A future NF dependency** (telemetry, a JWKS fetch) needs an explicit rule. NF's manifest
  egress list is the contract; a change to it is a change request to Overcast.
- **ECS Exec stays off (O-018).** No `ssmmessages` endpoint is needed.

## Decisions recorded with this spec

- **O-017:** consumer services get no internet egress by default.
- **O-018:** no ECS Exec for ShuttleForge.

Both are in `docs/DECISIONS.md`.
