# Internal TLS for Core and ShuttleForge: two internal NLBs (D-077, DR-10)

Status: **DRAFT revision 3, for approval. Nothing built or applied.** Each phase is applied only
on the owner's go, given first-hand.

Revision history:
- **Revision 2** folded in the internal adversarial review.
- **Revision 3** folds in the external reviews (codex-1, codex-2, hotpants) and an ultracode
  verification of their findings (see "Review record").
- **Owner, 2026-11-10:**
  - **two NLBs**, one per service: Core in P1, ShuttleForge in P2;
  - **disable the "Terraform Apply" workflow** from before the P1 merge until DR-1 is repaired.
    Done 12:48Z, and it reads `disabled_manually`.

## Why

Owner rulings, 2026-11-10:
- **D-077.** On deployed environments, every internal hop that carries a credential uses TLS
  with server authentication that the client verifies.
  - Complex records it as a pointer under D-074 in its next records batch. It is not yet
    present at Complex `48c1715`.
- **Option A for Core.** TLS terminates at an internal load balancer holding a public ACM
  certificate.
  - The last hop to the task stays plain inside the private subnets. That is the same posture
    as today's public path.
  - End-to-end TLS is v2 hardening.
- **ShuttleForge's `:9000`, `:9050` and `:9100` are in scope.** There is no v1 exception for
  the proxy ports.
- **Sequencing:**
  - Core's JWKS and `/oauth/token` come first. They gate SF.11 Stage C and NF's N-G4, because NF
    PR #55 refuses an `http` Core URL on a deployed environment.
  - SF's inbound hops follow, before SF holds its first live provider credential.

| Hop (plain HTTP inside the VPC today) | Credential |
|---|---|
| SF → Core JWKS | none (public keys), but key integrity |
| NF → Core `/oauth/token` | NF's client secret (Basic) |
| NF → SF `:9000` | NF's Core JWT; lease credential in the response |
| NF → SF `:9050` / `:9100` | lease credential in `Proxy-Authorization` |

## Design

**Two internal Network Load Balancers, one per service.**

| | Core NLB (P1) | SF NLB (P2) |
|---|---|---|
| Terraform | `aws_lb.core_internal` | `aws_lb.sf_internal` |
| Name (≤ 32 chars, fixed before apply; `name` is ForceNew) | `arclight-stg-int-core` | `arclight-stg-int-sf` |
| Listeners (TLS) | 443 | 9000, 9050, 9100 |
| DNS name | `core-internal.staging.arclight-complex.net` | `shuttleforge-internal.staging.arclight-complex.net` |
| Target groups | `stg-int-core-8000` → Core :8000 | `stg-int-sf-9000`, `-9050`, `-9100` → SF |
| Security group | `aws_security_group.core_nlb`, attached at creation | `aws_security_group.sf_nlb`, attached at creation |

**Shared settings for both NLBs:**
- `internal = true`, `load_balancer_type = "network"`, IPv4.
- In the two private app subnets: `10.0.10.0/24` (us-east-1a) and `10.0.11.0/24` (us-east-1b).
- The security group must be attached at creation. AWS does not allow one to be added to an NLB
  later.
- `enable_cross_zone_load_balancing = false` and
  `dns_record_client_routing_policy = "any_availability_zone"`.

**Why an NLB.**
- `:9050` and `:9100` carry CONNECT tunnels, which an ALB does not carry. SF's manifest already
  bans them from ALB target groups.
- An NLB keeps the client's IP (below).

**Why two NLBs (finding F1, verified).** AWS evaluates zonal DNS health per load balancer,
across **every** target group attached to it:
- One group that is unhealthy in a zone removes that zone from DNS, even if another group is
  healthy there. Failover affects all groups on that load balancer. (*Target groups for your
  Network Load Balancers → Target group health*)
- When every zone is unhealthy, DNS fails open to all node IPs.
- "Network Load Balancers will also fail open when you have an empty target group" (*Health
  checks for Network Load Balancer target groups*).
- With cross-zone off, a node still forwards only to targets in its own zone. A node with no
  local target fails the connection.

So on one shared NLB, Core would fail **persistently**, not just for a TTL window, in two
cases:
- whenever SF's groups are empty: SF at 0/0 today, every stop-before-start, any SF crash;
- whenever Fargate places Core and SF in different AZs. Each service is given both subnets
  (`main.tf:183`, `shuttleforge.tf:37`) with no placement constraint.

Separate Route 53 names cannot isolate the two services, because both aliases resolve to the
same load balancer's node set.

**Under two NLBs, DNS failover is scoped per service.**
- Core's NLB carries only Core's group, so it publishes only the node in Core's AZ.
- SF's three groups all front one task and share one health check (`/ready` on 9000), so they
  always agree on its AZ.
- While SF is at 0/0, only SF's own name fails open, which is expected. Core is unaffected.

**Cross-zone stays OFF on both NLBs and all four target groups.** With client IP preservation,
AWS documents intermittent resets from 5-tuple collisions when:
- cross-zone is on and the target count is small (ours are singletons); or
- several NLBs register the same target IP:port.

Neither condition arises here. Source: re:Post *Troubleshoot connections that drop or
intermittently fail with my NLB*, and the NLB troubleshooting guide, *Intermittent TCP
connection establishment failure*.

**Explicit attributes, so defaults cannot drift:**
- Every target group sets `load_balancing_cross_zone_enabled = "false"`, never `"true"`.
- **No `target_group_health` block anywhere.**
  - An empty `dns_failover {}` block makes provider 5.100.0 default its count to `"off"`
    (`internal/service/elbv2/target_group.go:332-336`).
  - That would keep the AZ without a task in DNS permanently.

**Listeners (TLS):**
- Certificate: `data.aws_acm_certificate.staging`, the issued `*.staging.arclight-complex.net`
  wildcard. It renews automatically.
- `ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"`, with no ALPN policy.
- The TLS listener idle timeout is **fixed at 350 s**.
  - NF opens a fresh CONNECT per request and holds it at most about 30 s.
  - The NLB docs say: "When a TLS listener receives a TCP keepalive packet from either a client
    or a target, the load balancer generates TCP keepalive packets and sends them to both the
    front-end and back-end connections every 20 seconds." So keepalive from either side would
    carry a longer-lived tunnel if a later consumer needs one.
- Core's note: a caller that declares a long body and then stalls holds its connection up to
  that 350 s limit. The callers are trusted internal services (LOW).

**Target groups:**
- `protocol = "TCP"`, `target_type = "ip"`.
- `preserve_client_ip = "true"`, set explicitly; it defaults to off for TCP groups with IP
  targets.
- `proxy_protocol_v2 = false`. Uvicorn and mitmproxy do not parse it (Core).
- `deregistration_delay = 30`.
- Health check: `protocol = "HTTP"`, `path = "/ready"`, `matcher = "200"`, `interval = 10`, and
  healthy/unhealthy thresholds of 2/2.
  - Core checks its traffic port.
  - **All three SF groups check port 9000.** TCP checks on 9050 and 9100 are rejected: a
    divergent check on SF's NLB would recreate the any-group zonal split inside it. SF's
    manifest also requires `/ready` for traffic-gating probes.
  - Health-check Host is the node IP plus the port. Neither service validates Host (see "DR-10
    spec points").
- SF ends with four target groups: the public ALB's plus three, of the five ECS allows.

**Client IP preservation.** Targets see the consumer task's own address as the transport
peer.
- **Core.** The address is untrusted, so the rate limiter keys on the consumer.
  - `X-Forwarded-For` is never read on this path.
  - `CORE_TRUSTED_PROXY_CIDRS` is unchanged (`rate_limit_service.py:81-105`).
  - Rate-limit buckets carry over.
- **SF.** Client-IP stickiness (`dataplane/routing.py:518`) and `request.client.host` audit
  rows are unchanged.
- **Hairpin.** No target calls its own NLB.

**DNS.** One **Route 53 private hosted zone per name**, associated with the staging VPC. Each
has an alias A record at the apex to its NLB, with `evaluate_target_health = false`.
- Each name is one label under the wildcard.
- Inside the VPC the private zone wins, so the name never resolves to Cloudflare, the NAT or
  Access.
- The VPC's only other private zone today is Cloud Map's `staging.internal.arclight-complex.net`,
  plus endpoint zones. It resolves through AmazonProvidedDNS, with no DNS firewall.
- *Inferred:* the alias returns the same health-filtered node set as the NLB's own name. The P1
  probe checks this.

**Security groups.** A target rule that references an NLB's security group admits data and
health checks with client IP preserved, and blocks clients from reaching the target directly.
The NLB's health checks are subject to its own egress rules. (*Update the security groups for
your Network Load Balancer*)

| Group | Rule | Phase |
|---|---|---|
| `core_nlb` | ingress 443 from SF; ingress 443 from NF | P1 |
| `core_nlb` | egress 8000 to Core (traffic and health checks) | P1 |
| Core | ingress 8000 from `core_nlb` | P1 |
| `sf_nlb` | ingress 9000, 9050, 9100 from NF; egress 9000, 9050, 9100 to SF | P2 |
| SF | ingress 9000, 9050, 9100 from `sf_nlb` | P2 |
| NF | egress 9000, 9050, 9100 to `sf_nlb` | P2 |
| removed | `core_from_sf`, `sf_to_core`, `core_from_nf`, `nf_to_core`, `nf_to_sf[*]`, `sf_from_nf[*]` (ten rule instances) | P3 |

- SF and NF already have egress on 443 through the module's `https_egress`
  (`ecs-service-fargate/main.tf:56-64`).
- SF's `sf_provider_egress` allows 0-65535 anywhere. Closing a plain path therefore rests on
  **ingress** at Core and SF, and a closed path **times out**.

**Module change (`ecs-service-fargate`).**
- New `additional_load_balancers`, a list of `{target_group_arn, container_port}` defaulting to
  `[]`, rendered as extra `load_balancer` blocks.
- `health_check_grace_period_seconds` applies when any load balancer is attached.
- Services that pass none plan no diff.
- **Ordering.** ECS refuses a target group that has no listener yet. The root therefore passes
  each `target_group_arn` as `aws_lb_listener.<name>.default_action[0].target_group_arn`, which
  makes the service depend on its listener.
- The update is in place. In provider 5.100.0 `load_balancer` is a set with no ForceNew, and
  `UpdateService` sends `LoadBalancers` on change. `task_definition` is suppressed by
  `ignore_changes`, so Core stays on `:18` (codex-1, proven from provider source).

## DR-10 spec points, closed

| Point | Resolution |
|---|---|
| (a) placement | **Private app subnets.** Client IP is preserved, so Core never sees an NLB as the peer. If preservation were ever off, the NLB's addresses would be untrusted and Core would fall back to one shared bucket. An NLB in the trusted `10.0.1.0/24` / `10.0.2.0/24` could instead let a forged `X-Forwarded-For` choose the key. This placement fails safe. |
| (b) DNS | Route 53 private zone per name (above). |
| (c) Host | Core does not validate Host. Its only middlewares are the body cap and the request ID (`arclight_core/main.py:202-203` at `08de4e6`). `iss` is fixed. The JWKS and `/oauth/token` paths read neither Host, scheme nor `X-Forwarded-Proto` (Core). |
| (d) health check | HTTP `/ready`, 200: unauthenticated, not rate-limited, 503 when not ready (TESTING_PROTOCOLS §3). |
| (e) NF URLs | Move to `https://` in P3, gated on the running task (below). |

## Phases

**Apply control.**
- "Terraform Apply" is **disabled** (owner, 2026-11-10, 12:48Z). It ran untargeted
  `apply -auto-approve` on pushes to `main` that touch `terraform/**` or `services/**/*.tpl`
  (`terraform-apply.yml:3-10, 47-49`).
- It stays disabled through P3, and is re-enabled only together with DR-1's repair.
- Each phase PR records `gh workflow list --all` showing `Terraform Apply | disabled_manually`
  before it merges.
- One PR per phase, merged only around its own targeted apply.

**P1: Core's NLB.**
- What it builds:
  - `aws_lb.core_internal`, its security group and rules, and `stg-int-core-8000`;
  - the 443 listener, the `core-internal` zone and record;
  - the alarm and the probe resources;
  - the module variable, and Core's `additional_load_balancers`.
- Attaching the group starts a rolling deployment of the **same** revision, `:18`.

**P2: SF's NLB.**
- What it builds: `aws_lb.sf_internal`, its security group and rules, three target groups, three
  listeners, the `shuttleforge-internal` zone and record, the three SF alarms, and SF's
  `additional_load_balancers`.
- Preconditions:
  - SF's `DEPLOYMENT_MANIFEST.md` amendment, allowing an NLB TLS listener on `:9050` / `:9100`,
    has merged on SF's line;
  - SF has been told why all three checks stay on `/ready:9000`.
- SF is at 0/0, so no task starts.
- **SF deploy gap.** A stop-before-start (0/100) outage lasts several minutes, not 60 s. It adds
  up:
  - drain (30 s, across the groups in parallel) and `stopTimeout` 30;
  - Fargate provisioning and image pull, then process start;
  - NLB registration. AWS says this "can take a few minutes" before health checks start.
  - two 10 s checks on each group;
  - up to the TTL if the task changes AZ.
- While SF has no task, SF's NLB fails open and SF connections fail. That is expected, and Core
  is unaffected.
- Record the time from stop to first successful lease on the first controlled redeploy.

**P3: consumers to `https://`, then close the plain paths.**
- **SF template:** `SHUTTLEFORGE_CORE_JWKS_URL` → `https://core-internal…/.well-known/jwks.json`;
  `SHUTTLEFORGE_TRANSPORT_ENDPOINT` → `https://shuttleforge-internal…:9050`.
- **NF template:**
  - `CORE_URL`, `NERFHERDER_JWKS_URL` and `SHUTTLEFORGE_URL` → the `https://` names;
  - remove `NERFHERDER_ALLOW_PLAINTEXT_INTERNAL_HTTP=true`
    (`services/nerfherder/task-definition.json.tpl:24`).
- **SSM** (`terraform/modules/secrets/main.tf:48-53`): `core/internal-url`, `core/jwks-url`,
  `core/token-url` and `shuttleforge/internal-url` → `https://`.
- **Removed:** the ten direct rule instances.

**Why the cutover gates on the running task (finding F2).**
- The service module ignores `task_definition` (`ecs-service-fargate/main.tf:126-128`).
- A template change therefore registers a new `https` base revision but never moves a running
  service onto it.
- A rendered-revision check proves nothing about the running task.
- A service at 0/0 that **references** a real-digest `http` revision would bring it back on the
  next `desired_count` flip, so "desired 0" alone is not enough either.

**P3, path A (expected: neither service has ever run).** A single apply, only if read-only
checks immediately before it show, for both SF and NF:
- `desiredCount`, `runningCount` and `pendingCount` all 0;
- exactly one PRIMARY deployment;
- the service's `taskDefinition`, and every `deployments[].taskDefinition`, naming a
  sentinel-digest (`@sha256:000…0`) revision;
- `list-tasks --family arclight-{shuttleforge,nerfherder}-staging --desired-status RUNNING`
  empty.

After the apply, `describe-task-definition` on each bare family (the latest ACTIVE revision)
shows the `https` URLs and no `NERFHERDER_ALLOW_PLAINTEXT_INTERNAL_HTTP`. That revision is
`deploy-service.yml`'s base for SF and N-G4's base for NF.

**P3, path B (if either service references a real-digest pre-P3 revision, running or at
0).** Split the work:
1. **P3a:** templates, SSM and the NF flag. No rule removal.
2. **Deploy the `https` revisions.** SF goes through `deploy-service.yml` with its current tag.
   NF goes by hand from its latest ACTIVE revision with its real digest, then `update-service
   --task-definition`. SF goes first or with NF, because SF advertises `TRANSPORT_ENDPOINT`.
3. **Verify running adoption:**
   - `describe-tasks` shows every running task on the new revision, with `https` in its
     environment;
   - `NewFlowCount_TLS` or `ActiveFlowCount_TLS` rises on the target groups;
   - SF `/ready/detail` shows `jwks` `ok` from the fresh task;
   - NF's Core token and lease calls succeed.
4. **Deregister** the pre-P3 real-digest `http` revisions, so they cannot be rollback targets.
5. **P3b:** remove the rules. Then re-verify with **new** connections, because security-group
   connection tracking keeps established flows:
   - a direct `:8000` / `:9000` probe times out;
   - SF's JWKS refresh and NF's token and lease calls still succeed.

**Tie to SF.11 Stage C and N-G4.**
- **SF.11 Stage C entry requires:**
  - SF's **running** task on an `https` revision, with `jwks` `ok` fetched over
    `core-internal`;
  - if NF runs, NF→SF over `shuttleforge-internal`;
  - the direct rules removed.
- **N-G4 completes only when** NF's **running** task is on an `https` revision with no plaintext
  flag, and its Core token call over `core-internal` succeeds.
- `nerfherder-staging-wiring.md`'s N-G4 step 1 changes accordingly: it registers from the latest
  ACTIVE `arclight-nerfherder-staging` revision after P3. `deploy-service.yml` has no
  `nerfherder` option.

## Expected plans (gates)

Applies run locally by an administrator, after `scripts/plan_guard.py`. The full plan is saved
to a file and never truncated.

**Baseline (main at `e38708e`, 2026-11-10).** A full plan shows `1 to add, 0 to change, 1 to
destroy`. That is the known churn on `module.core_service.aws_ecs_task_definition.this`:
- state still holds revision 8 (`10.0.0.0/16`, `v2-d5a6e70`);
- the template renders H1b's ranges and `v2-08de4e6`.

**P1 `-target` list.** Targeting the service pulls in its dependencies only, so everything
else must be named (codex-1):
- `aws_lb.core_internal`
- `aws_security_group.core_nlb`
- the four standalone rules: `core_nlb_from_sf_443`, `core_nlb_from_nf_443`,
  `core_nlb_to_core_8000`, `core_from_core_nlb_8000`
- `aws_lb_target_group.core_internal_8000`
- `aws_lb_listener.core_internal_443`
- `aws_route53_zone.core_internal` and `aws_route53_record.core_internal`
- `aws_cloudwatch_metric_alarm.core_internal_healthy`
- the probe's `aws_iam_role`, `aws_iam_role_policy` and `aws_cloudwatch_log_group.probe`
- `module.core_service.aws_ecs_service.this`

**The P1 plan must read:**
- **Adds:** exactly the resources above, minus the service.
- **Update in place:** `module.core_service.aws_ecs_service.this`, with one `load_balancer`
  block.
- **Replace:** `module.core_service.aws_ecs_task_definition.this`. `:19` is registered and the
  unused `:8` deregistered; `:17`, the rollback revision, is untouched.
- **Hard stop if:**
  - the service is planned for **replacement**;
  - anything else changes or is destroyed;
  - the field walk below fails;
  - the guard below fails.
- **After the apply, an untargeted staging plan must read "No changes."**

**Pre-apply `:19` field walk.**
- Compare the planned `container_definitions` (`terraform show -json`) against `:18`.
- Allowed differences:
  - the image form, `:v2-08de4e6` against `@sha256:2393682f…a777`. The tag resolves to that
    digest, and the repository is IMMUTABLE.
  - AWS-normalised defaults.
- Anything else is a stop. `:19` becomes `deploy-service.yml`'s base revision
  (`describe-task-definition --task-definition "$FAMILY"`).

**Guard, for every P1 and P2 plan.** Reject any of the following:
- a target group attached to the other service's NLB;
- one target IP:port registered on both NLBs (AWS's multi-NLB collision condition);
- a target group with cross-zone `"true"`;
- any `target_group_health` block.

**P2 additional hard stop:** any change to Core's NLB, listener, target group, zone, record or
alarm.

**P2 and P3:** each phase's PR carries its own exact list from its own plan.

## Acceptance

**P1:**
1. **Steady within 15 min, or abort.** Core's service has no deployment circuit breaker.
   - Abort means removing `additional_load_balancers`, which is an in-place update.
   - Then confirm:
     - `:18` 1/1 with digest `sha256:2393682f…a777`;
     - `stg-int-core-8000` healthy;
     - the public target group healthy.
2. **In-VPC probe**, from SF's security group and from NF's, in the private app subnets with no
   public IP:
   - `core-internal` resolves only to Core's NLB node in Core's AZ;
   - the TLS handshake verifies against public roots;
   - `GET /.well-known/jwks.json` returns 200 with one active key;
   - `GET /ready` returns 200 `ready`.
3. **Per-node check.** The probe also connects with SNI `core-internal` to **each** NLB node IP
   explicitly (from `describe-network-interfaces`). It records the symptom on the node without
   a local target: timeout, RST, or a handshake that then fails. That symptom is Unverified
   today, and it decides whether clients fall through to the other address.
4. **Client IP preserved.** Core's access-log line for the probe's request shows the probe
   task's own IP. Uvicorn runs `--no-proxy-headers`, so it logs the transport peer.
5. **Public path unchanged.** `/ready` through Cloudflare and Access returns 200, and ELB 5XX
   counts stay at zero.
6. **First AZ-move gap.** On the first Core redeploy that changes AZ, measure the real gap: dig
   over time, plus failed connects.

**Probe family `arclight-probe-staging`:**
- **Image:** Core's, by digest, re-pinned each run from the live Core revision (ECR keeps the
  last ten `v` tags). It has Python and the Debian CA store, and `CMD` only.
- **Secrets:** none, and no task role.
- **Execution role:**
  - `ecr:GetAuthorizationToken` on `*`;
  - `ecr:BatchGetImage`, `ecr:GetDownloadUrlForLayer` and `ecr:BatchCheckLayerAvailability` on
    `arclight/core`;
  - `logs:CreateLogStream` and `logs:PutLogEvents` on
    `arn:aws:logs:us-east-1:650880817826:log-group:/arclight/staging/probe:*`. The `:*` is
    required because these actions authorise on the log stream, as at
    `terraform/modules/secrets/main.tf:166`.
- **Log group:** `aws_cloudwatch_log_group` `/arclight/staging/probe`, 30-day retention.
- **Command:** a `python -c` that resolves, connects and prints the results.

**P2:**
- With SF at 0/0 and SF's NLB in place, `core-internal` still resolves only to Core's AZ node,
  and the Core probe still passes. This proves the isolation.
- `shuttleforge-internal` returning both node IPs at 0/0 is expected (fail-open).
- After G4:
  - all three SF groups are healthy, and SF's public ALB group too;
  - the probe from NF's group runs TLS to `shuttleforge-internal:9000` and gets `/ready`;
  - SF's `/ready` accepts an `IP:port` Host;
  - record the AZs of Core and SF.
- The proxy path is proven by NF's lease smoke.

**P3:** the running-task evidence from the path A or path B gate above.

## Monitoring

**Paging alarms:**
- `AWS/NetworkELB` `HealthyHostCount`, statistic `Maximum`, `LessThanThreshold 1`.
  - Dimensions: `LoadBalancer = aws_lb.<nlb>.arn_suffix` and `TargetGroup = <group>.arn_suffix`.
  - Period 60, `evaluation_periods = 3`, `datapoints_to_alarm = 3`.
  - `treat_missing_data = "breaching"`. AWS reports the metric only while targets are
    registered.
  - `alarm_actions` and `ok_actions` go to `module.observability.alarm_topic_arn`.
- **P1:** one alarm, on Core's group.
- **P2:** one alarm per SF group, with `actions_enabled = var.shuttleforge_desired_count > 0`
  (the NF pattern at `nerfherder.tf:506`). Otherwise breaching-on-missing would page while SF
  is 0/0.
- **Never alarm on `ZonalHealthStatus`.** A cross-zone-off singleton always reports 0 in the AZ
  without its task.

**Diagnostic metrics** (dashboard or non-paging until a baseline exists):
- **Per NLB:**
  - `TCP_Target_Reset_Count`, `TCP_ELB_Reset_Count`, `TCP_Client_Reset_Count`;
  - `ClientTLSNegotiationErrorCount`;
  - `SecurityGroupBlockedFlowCount_Inbound_TCP` and `_Outbound_TCP`, which catch rule gaps;
  - `ZonalHealthStatus` summed across AZs: 1 is normal, 0 means fail-open.
- **Per target group:** `UnHealthyHostCount`, `NewFlowCount_TLS` and `ActiveFlowCount_TLS`.
  The last two are P3's adoption evidence.
- `UnhealthyRoutingFlowCount` is not available for TLS listeners.
- `HealthyHostCount` proves target health, not client-path reachability, so probes stay
  necessary.

## Cost

AWS list prices for us-east-1, read 2026-11-10:

| Item | Monthly |
|---|---|
| Two NLBs (2 × $0.0225 × 730 h) | $32.85 |
| Two Route 53 private zones | $1.00 |
| Alarms: Core $0.10, plus SF $0.30 from P2 | $0.40 |
| NLCU: a fraction of one at staging load | ceiling +$4.38 per NLB at one full NLCU |
| Inter-AZ transfer: about $0.01/GB each way when a consumer and the published node are in different AZs | cents |

- **After P1:** about $17.03.
- **After P2:** about $34.25 base, or $34.55 with all alarms.
- **Ceiling:** about $43.30.

## Rollback

**P1:**
- Remove Core's `additional_load_balancers`. That is in place and a rolling deployment of
  `:18`.
- Destroy Core's NLB resources. The public path is untouched.
- If `:19` turns out wrong, deregister `:19` so `:18` is the latest ACTIVE revision again.
- Image rollback stays "update the service to revision 17".

**P2:** remove SF's `additional_load_balancers`, then SF's NLB resources. Core is unaffected.

**P3**, in order:
1. Restore the direct rules **first**.
2. Restore the templates and SSM.
3. Redeploy the `http` revisions. Restoring templates alone does not move a running service.

## Residual risks

- **AZ moves.** A gap of up to the TTL, plus AWS's undocumented DNS update time, whenever a
  singleton changes AZ.
  - The reviewer's CloudTrail read suggests that happens on about two-thirds of Core
    replacements (Inferred).
  - Removing the gap needs cross-zone on (collision class) or AZ pinning (loses AZ fallback).
- **Core `/ready` blips.** A blip marks Core's only zone unhealthy, so its NLB fails open.
  About half of new connections fail during the blip and for up to the TTL after it. This
  is inherent to cross-zone off with a singleton.
- **Unverified consumer behaviour.** SF's JWKS retry inside its 1 h cache, NF's token and
  lease retry, and in-flight tunnels are relayed claims. Whether SF or NF read the SSM
  parameters at runtime is also unverified.
- **Wiring mistakes** reopen known defects:
  - an SF group on Core's NLB brings back F1;
  - one target on both NLBs, or a cross-zone `"true"` group, brings back collisions;
  - an empty `dns_failover {}` block turns the count off.

  The plan guard is the control.
- **Transitional.** Between P1 and P3, a consumer using both the direct path and the NLB to the
  same Core target at once could hit the shared-target collision (Inferred, negligible). SF and
  NF are 0/0.
- **Prod.** Out of scope (O-016). Prod would need the same two-NLB shape.

## Out of scope

- The public path (Cloudflare → ALB → Core).
- End-to-end TLS (v2).
- The Cloudflare Terraform root.
- NF's internal configuration beyond Overcast's template.
- `:9100` CA trust on NF's side. If NF uses `:9100`, its single transport bundle must hold the
  public roots plus SF's MITM CA, because curl_cffi uses one bundle as both `CAINFO` and
  `PROXY_CAINFO`. That is NF's configuration and a later Overcast file-placement item.

## Open before P2

- SF's manifest amendment.
- The NF `:9100` configuration item, if NF uses that port.

## Review record

- **Internal adversarial review (revision 1 → 2): GO-WITH-CHANGES.** Twelve findings were
  re-verified and applied.
  - Its cross-zone-off recommendation was correct for one service per NLB. It was wrong for a
    shared NLB, which the external reviewers caught.
- **External reviews of `66bfb20`**, via Codex CLI, `gpt-6-astra`, effort ultra, read-only, at
  the owner's direction:
  - **codex-1: GO for P1.** P2 DNS defect (F1). WARN on the target list.
  - **codex-2: GO-WITH-CHANGES.** F1, F2, merge control, alarm semantics, the SF deploy gap and
    cost.
  - **hotpants: GO-WITH-CHANGES.** Running-consumer cutover gate (F2). Notes that D-077 is not
    yet recorded at Complex `48c1715`.
- **Ultracode verification** (workflow `wf_b46c1fa6-e2b`, seven agents):
  - F1 was confirmed by two independent verifiers, one of whom was tasked with refuting it.
    Primary AWS quotes are above.
  - F2 was confirmed in code: `ignore_changes`, `deploy-service.yml:80-81`, and the live
    security-group ingress.
  - Topology options scored: **two NLBs 8**, shared NLB with cross-zone on 7, per-group
    overrides 4.
  - The judge recommended two NLBs and eighteen spec changes, all applied in this revision.
- **Core, via Complex:** concurs, with no code change. Its three settings and its stalled-body
  note are included.
- **Owner, 2026-11-10:** approved two NLBs (+$16.93/month) and disabling "Terraform Apply".
