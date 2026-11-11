# Internal TLS for Core and ShuttleForge: two internal NLBs (D-077, DR-10)

Status: **Revision 3, approved (merged `a9979c6`); P1 applied 2026-11-10 (PR #76); P2 applied 2026-11-11 (PR #88); P3 applied 2026-11-11 (PR #89, path B).**
- **Amendment 3a (2026-11-10):** cross-zone is **ON for Core's target group**, by owner decision,
  after P1 measured the stale-node window.
- **Amendment 3b (2026-11-10):** SF's JWKS URL moves to `https://core-internal…` **before SF's
  first run** (HTTPS-first), ahead of the rest of P3. Owner's ruling.
- **Amendment 3c (2026-11-11):** P2's decisions. Cross-zone is **ON for SF's three target
  groups**. SF is now **running**, so P2's apply restarts it. The alarms are applied after SF is
  healthy. See "Amendment 3c" under P2.
- Each phase is applied only on the owner's go, given first-hand.

Revision history:
- **Revision 2** folded in the internal adversarial review.
- **Revision 3** folds in the external reviews (codex-1, codex-2, hotpants) and an ultracode
  verification of their findings (see "Review record").
- **Owner, 2026-11-10:**
  - **two NLBs**, one per service: Core in P1, ShuttleForge in P2;
  - **disable the "Terraform Apply" workflow** from before the P1 merge until DR-1 is repaired.
    Done 12:48Z, and it reads `disabled_manually`.
- **Amendment 3a** (owner, 2026-11-10): cross-zone on for Core's target group, after P1's
  measurement.
  - codex-1 reviewed it at `6c754df`: GO-WITH-CHANGES, documentation only.
  - Its corrections are folded in: per-node acceptance, the unmeasured collision rate, the DNS
    qualifier and the blip wording.
  - One point was rejected: NF and SF are both 0/0 (live `describe-services`), so "SF and NF are
    0/0" stays.
- **Amendment 3b** (owner, 2026-11-10, "yes" to HTTPS-first): SF's JWKS URL to `https` before
  SF's first run. See "Amendment 3b" under P3.
- **Amendment 3c** (owner, 2026-11-11, "yes. hit it" to P2 with cross-zone on): P2's
  decisions. See "Amendment 3c" under P2.

## Why

Owner rulings, 2026-11-10:
- **D-077.** On deployed environments, every internal hop that carries a credential uses TLS
  with server authentication that the client verifies.
  - Recorded on Complex `main` since `3135bca` (PR #30), at `platform/DECISIONS.md:1613`,
    verified read-only. The external reviewers read the older alignment pin `48c1715`.
  - Complex PR #31 (`ac261ea`) adds a pointer under D-077 for this spec, marked
    Overcast-reported. Cite `3135bca` or newer in later reviews.
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
- Core's NLB carries only Core's group. Before amendment 3a it published only the node in Core's
  AZ. Since 3a both node addresses stay in DNS (see the cross-zone section below).
- SF's three groups all front one task and share one health check (`/ready` on 9000), so they
  always agree on its AZ.
- While SF is at 0/0, only SF's own name fails open, which is expected. Core is unaffected.

**Cross-zone: ON for Core's target group (amendment 3a, owner 2026-11-10); OFF on SF's NLB
until P2 decides.**

With client IP preservation, AWS documents intermittent resets from 5-tuple collisions when:
- cross-zone is on and the target count is small (ours are singletons); or
- several NLBs register the same target IP:port.

Sources: re:Post *Troubleshoot connections that drop or intermittently fail with my NLB*, and
the NLB troubleshooting guide, *Intermittent TCP connection establishment failure*. Revision 3
kept cross-zone off everywhere to avoid that, assuming the stale-node gap after an AZ move
would be about one TTL (60 s).

**P1 measured otherwise:**
- After the NLB was created, `core-internal` kept returning the empty AZ's node for **about 4-6
  minutes**.
- That node **accepts TCP and then fails**, either by TLS timeout or with an empty response.
  NF's Happy Eyeballs cannot absorb that.
- Core runs one task, and any rollout can move it to the other AZ; P1's own rollout did.

So with cross-zone off, every Core deploy would open a window of minutes in which new
connections to the stale node fail.

**The owner turned cross-zone ON for `stg-int-core-8000`.**
- The target-group attribute overrides the NLB-level `false`.
- Either node now forwards to the single task, so both node addresses answer.
- Both stay in DNS. With cross-zone on, DNS-failover thresholds apply to the targets in all
  enabled zones, not per zone (*Target groups for your Network Load Balancers → Requirements
  and considerations*), so both zones count the one task. This holds while both zones' NLB
  infrastructure is itself healthy; AWS lists other DNS-failover causes, such as a zonal shift.
  It is Inferred from the docs until the 3a verification measures it.
- Core's NLB carries only Core's group, so the shared-NLB coupling that gave SF its own NLB does
  not apply.
- **Residual risk:** the collision class above, at an **unmeasured** rate.
  - Not being behind NAT does not prevent source-port reuse. Linux can give two concurrent
    connections to different destinations the same local port.
  - NF's Happy Eyeballs can overlap attempts to both node IPs when the first TCP connect is
    still pending after 0.25 s. That is a plausible path to a duplicate tuple at Core's task
    (Inferred; codex-1, 2026-11-10).
  - NF reports it would surface as a sporadic `core_auth.unreachable`, healed by the next 30 s
    probe.
  - It shows in `TCP_Target_Reset_Count` on Core's NLB, which is now the watch item (see
    Monitoring).

**SF's NLB stays cross-zone OFF until P2 decides.** SF is also a singleton, so the same
measurement applies. P2 decides with its own plan.

**Explicit attributes, so defaults cannot drift:**
- Core's target group sets `load_balancing_cross_zone_enabled = "true"` (amendment 3a).
- SF's target groups set `"false"` unless P2 decides otherwise.
- Every target group sets the value **explicitly**.
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
- Preconditions, **both met 2026-11-10**:
  - SF's `DEPLOYMENT_MANIFEST.md` amendment ("Internal TLS") has merged: SF PR #42, `f14ab7b` on
    `appliance/main`, carried to `v1-operate` as `63f4492`. Read at `63f4492`, l.130-160, it
    agrees with this spec:
    - TLS on 9000, 9050 and 9100 with the `*.staging` certificate;
    - TCP target groups with client IP preserved;
    - `/ready:9000` for all three health checks;
    - from Stage C, consumers admitted only through the NLB's security group.
  - SF has been told why all three checks stay on `/ready:9000`.
- **SF's two open questions, answered.**
  - *Where the first-admission probe comes from.* It is unchanged. `deploy-service.yml` reads
    SF's `/ready` and `/ready/detail` at `https://shuttleforge.<domain>` through Cloudflare and
    Access to the public ALB. SF stays attached to the ALB target group on 9000
    (`shuttleforge.tf:42`), and the ALB's security group stays admitted on 9000.
  - *How the manifest's YAML names the NLB listeners.* **Landed 2026-11-10:** SF PR #43,
    `de8c8df` on `appliance/main`, carried to `v1-operate` as `4c50b3e`. Each port keeps its
    `exposure` string and gains `internal_tls: nlb` (manifest l.103-112 at `4c50b3e`). The
    prose names `arclight-stg-int-sf` and `shuttleforge-internal` (l.170-175). Overcast
    verified it read-only.
    - No Overcast tooling parses SF's manifest; the only references are prose and Terraform
      comments (checked 2026-11-10).
    - A list-typed `exposure` would break SF's `tests/test_deployment_5a.py`, which pins each
      `exposure` as a string. The wording is SF's.
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

**Amendment 3c: P2's decisions (owner, 2026-11-11).**
1. **Cross-zone ON for SF's three target groups** (`stg-int-sf-9000`, `-9050`, `-9100`).
   - **Why:** this is 3a's reasoning. SF is a singleton (0/100), and any SF deploy can move it to
     the other AZ. With cross-zone off, P1 measured the empty AZ's node staying in DNS for 4-6
     minutes and failing after connect.
   - **The NLB-level attribute stays `false`.**
   - The three groups front one task on **different ports**, so no target IP:port is shared
     between groups or NLBs, and the shared-target collision case does not arise.
   - **Residual:** the singleton collision class, at an unmeasured rate, as for Core. NF's
     failed connects and requests are the discriminating signal.
   - `ZonalHealthStatus` summed is expected to read 2, as on Core's NLB since 3a (Inferred until
     measured).
2. **SF is running, not 0/0.** SF.11 A5 started it at desired 1 on 2026-11-10.
   - P2 adds three load balancers to SF's service. That is an in-place update, but ECS starts a
     new deployment for it.
   - Under 0/100 that is **stop-before-start: an outage of several minutes** (see "SF deploy gap"
     above), on the same task definition (`:3`).
   - **The apply's time is agreed with SF first.** Record the stop-to-`ready` time.
   - Core is unaffected.
   - SF is in Stage A on a deny-by-default policy with no providers, so no lease is voided.
3. **Two targeted applies from one commit.**
   - **P2a:** everything except the three alarms (22 creates, plus SF's service update).
   - **P2b:** the three alarms (3 creates), applied only after SF's task is healthy in all three
     groups, and then confirmed `OK` with `ActionsEnabled = true`.
   - **Why:** with SF at desired 1, `actions_enabled` is true. Alarms created before SF's
     targets register would see missing data, which counts as breaching, and page during the
     planned outage. That is the inverse of the 0/0 case under "Monitoring".
4. **Acceptance with SF running** replaces the 0/0 items under "Acceptance → P2":
   - SF's three NLB groups and its public ALB group are healthy;
   - from NF's group, verified TLS to `shuttleforge-internal` on 9000, 9050 and 9100;
   - `/ready` 200 on 9000, both by name and through each node IP. The probe gains `--port` for
     this, and 443 behaves exactly as before;
   - `core-internal` still answers from NF's group (isolation);
   - record the AZs of Core and SF;
   - the proxy path itself is still proven by NF's lease smoke.

**P3: consumers to `https://`, then close the plain paths.**
- **SF template:** `SHUTTLEFORGE_CORE_JWKS_URL` → `https://core-internal…/.well-known/jwks.json`
  (**done early by amendment 3b**); `SHUTTLEFORGE_TRANSPORT_ENDPOINT` →
  `https://shuttleforge-internal…:9050`.
- **NF template:**
  - `CORE_URL`, `NERFHERDER_JWKS_URL` and `SHUTTLEFORGE_URL` → the `https://` names;
  - remove `NERFHERDER_ALLOW_PLAINTEXT_INTERNAL_HTTP=true`
    (`services/nerfherder/task-definition.json.tpl:24`).
- **SSM** (`terraform/modules/secrets/main.tf:48-53`): `core/internal-url`, `core/jwks-url`,
  `core/token-url` and `shuttleforge/internal-url` → `https://`.
- **Removed:** the ten direct rule instances.

**Amendment 3b: SF's JWKS URL to `https` before SF's first run (owner, 2026-11-10).**

ShuttleForge's SF.11 plan (§5.1 C-G2, row A5, at SF `appliance/main` `1b291af`) offers two
orderings for SF's first run:
- (i) **HTTPS-first**, available because P1 is live;
- (ii) the plain-HTTP value accepted for Stages A and B.

The owner ruled (i). This spec had no JWKS-only step ahead of P3, which bundles the JWKS URL with
SF's transport endpoint (which needs P2) and with removing the direct rules. So:
- **What changes now:** only `SHUTTLEFORGE_CORE_JWKS_URL` in SF's template. It becomes
  `https://${local.core_internal_fqdn}/.well-known/jwks.json`, passed in from `shuttleforge.tf`, so
  the name has one source (`internal-tls.tf`).
- **Unchanged until P3:**
  - SF's transport endpoint (`http://shuttleforge.<namespace>:9050`, the Stage A/B value);
  - the SSM `core/jwks-url` parameter;
  - the SF→Core `:8000` pair (`shuttleforge.tf`). It is not needed for JWKS once 3b runs, but
    it stays until P3 removes the direct rules together.
- **Network path, already in place:**
  - SF's group reaches 443 through `internet_egress` (O-017) and DR-15's all-TCP rule;
  - Core's NLB group admits SF on 443 (`core_nlb_from_sf_443`);
  - the private zone resolves `core-internal` inside the VPC;
  - P1's acceptance, and the 3a re-probe, verified TLS and JWKS 200 from SF's group.
- **Trust:** the certificate is the public ACM `*.staging` wildcard, so SF verifies it against
  public roots. SF needs no CA bundle and no `SHUTTLEFORGE_ALLOW_PLAINTEXT_JWKS`.
- **Plan:** exactly `module.shuttleforge_service.aws_ecs_task_definition.this` replaced. That is
  a new base revision; the service ignores `task_definition`, and SF is at 0/0. No other change.
- **Acceptance:**
  - `describe-task-definition` of the new base revision shows the `https` URL, and every other
    environment value and secret is unchanged (field walk against the old base revision);
  - at A5, SF's `/ready/detail` reports `jwks` `ok`, and Core's log shows the JWKS GET from SF's
    task IP (client IP preserved).
- **Effect on P3:** SF has now run, so SF's P3 takes **path B** (deploy, verify, deregister,
  remove the rules), never path A. P3 for SF reduces to the transport endpoint and the rule
  removals.
- **Rollback:** revert the template line (the Stage A/B plain-HTTP value is owner-accepted),
  apply, and redeploy SF by digest. Before Stage C only.

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
- the service's `taskDefinition` and every `deployments[].taskDefinition`, which are ARNs.
  Dereference each with `describe-task-definition`. The serving container's `image` must end
  in `@sha256:` followed by exactly 64 zeros (`format("%064d", 0)`, `shuttleforge.tf:16`,
  `nerfherder.tf:14`);
- `list-tasks --family arclight-{shuttleforge,nerfherder}-staging --desired-status RUNNING`
  empty.

After the apply, `describe-task-definition` on each bare family (the latest ACTIVE revision)
shows the `https` URLs and no `NERFHERDER_ALLOW_PLAINTEXT_INTERNAL_HTTP`. That revision is
`deploy-service.yml`'s base for SF and N-G4's base for NF.

**P3, path B (if either service references a real-digest pre-P3 revision, running or at
0).** Split the work:
1. **P3a:** templates, SSM and the NF flag. No rule removal.
2. **Move each consumer to its `https` revision, case by case:**
   - **Running (desired ≥ 1).**
     - SF goes through `deploy-service.yml` with its current tag.
     - NF goes by hand: register from its latest ACTIVE revision with its real digest, then
       `update-service --task-definition`.
     - SF goes first or with NF, because SF advertises `TRANSPORT_ENDPOINT`.
   - **Stopped at 0/0, with a real-digest reference.**
     - `deploy-service.yml` cannot be used: it fails when no task runs
       (`deploy-service.yml:179-183`).
     - Instead, register the `https` revision with the real digest and run `update-service
       --task-definition`, leaving the desired count at 0.
     - Confirm zero tasks, and that the service now references the new revision.
     - Step 3's running evidence is deferred to that consumer's activation (G4 or N-G4).
3. **Verify running adoption:**
   - `describe-tasks` shows every running task on the new revision. Read the environment from
     `describe-task-definition` on that revision's ARN; `describe-tasks` shows only overrides.
   - `NewFlowCount_TLS` or `ActiveFlowCount_TLS` rises on the target groups;
   - SF `/ready/detail` shows `jwks` `ok` from the fresh task;
   - NF's Core token and lease calls succeed.
4. **Deregister** the pre-P3 real-digest `http` revisions, so they cannot be rollback targets.
   ECS will not move a service onto an INACTIVE revision once deregistration has propagated.
5. **P3b:** remove the rules. Then re-verify with **new** connections, because security-group
   connection tracking keeps established flows:
   - a direct `:8000` / `:9000` probe times out;
   - SF's JWKS refresh and NF's token and lease calls still succeed.

**Tie to SF.11 Stage C and N-G4.**
- **SF.11 Stage C entry requires:**
  - SF's **running** task on an `https` revision, with `jwks` `ok` fetched over
    `core-internal`;
  - if NF runs, NF→SF over `shuttleforge-internal`;
  - the direct rules removed;
  - SF's written confirmation, with code references, that its JWKS client verifies the server
    certificate and hostname. A successful call alone does not prove verification (hotpants).
    - **Received 2026-11-10, at r6 `55a2d20`. Overcast checked it read-only:**
      - the only JWKS client is `httpx.AsyncClient(timeout=10.0)` (`shuttleforge/auth/jwks.py:110`),
        so httpx defaults apply: `verify=True`, `CERT_REQUIRED`, `check_hostname`;
      - no verification-disabling pattern appears in `shuttleforge/`, `scripts/entrypoint.sh`
        or the `Dockerfile`.
    - **Its conditions are Overcast's to keep.** The client honours its environment, so SF's
      task definition must set none of `SSL_CERT_FILE`, `SSL_CERT_DIR`, `HTTPS_PROXY` or
      `HTTP_PROXY`. None is set in `services/shuttleforge/task-definition.json.tpl` today, and
      P3 must not add one.
    - **Re-confirm at Stage C against the pushed CI image's resolved httpx.** That is r6's
      0.28.1. SF's push compares `pip freeze` with r6's reference and stops on any
      difference.
- **N-G4 completes only when all of these hold:**
  - NF's **running** task is on an `https` revision with no plaintext flag;
  - its Core token call over `core-internal` succeeds;
  - NF has confirmed in writing, with code references, that its httpx and curl clients verify
    the server certificate and hostname.
    - **Received 2026-11-10, at NF main `cee7463c`, with a negative test.** Each client, built as
      NF builds it, refused a wrong-hostname and an untrusted-CA certificate, at both proxy and
      origin TLS for curl.
    - **Overcast checked it read-only:**
      - the one internal httpx client is
        `httpx.AsyncClient(..., trust_env=False, follow_redirects=False, verify=settings.internal_ca_bundle or True)`
        (`runtime/host.py:1173-1174`);
      - curl's `HttpTransportStrategy` defaults `verify=True` (`plugin/strategies.py:430`);
      - nothing in `src/` disables verification;
      - `internal_ca_bundle` and `transport_ca_bundle` default to `None` (`config.py:130,139`).
    - **Its condition is Overcast's to keep.** With option A, NF's task definition must not set
      an internal CA bundle (`internal_ca_bundle`); one would replace the public roots for the
      Core and SF calls.
      - A transport bundle (`transport_ca_bundle`) is set only if NF uses `:9100`. It must then
        hold the public roots plus SF's MITM CA (see "Out of scope").
      - Neither is set in `services/nerfherder/task-definition.json.tpl` today.
      - `trust_env=False` means `SSL_CERT_FILE` and the proxy variables cannot redirect the httpx
        client.
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

**Revision identities** (all three confirmation reviewers).
- Before planning P1, record:
  - `LIVE_TD`, the ARN the Core service runs;
  - `LIVE_DIGEST`, its running task's resolved `imageDigest`;
  - `ROLLBACK_TD`, the revision before it.
- After the apply, record `P1_TD`, the revision Terraform registered.
- Every expected-plan, acceptance, abort and rollback step uses these names.
- Today they are `:18`, `sha256:2393682f…a777`, `:17` and `:19`. S-057 may change them, so
  those numbers are dated examples, not constants.

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
- **Replace:** `module.core_service.aws_ecs_task_definition.this`. Terraform registers `P1_TD`
  and deregisters the unused `:8` it holds in state. `LIVE_TD` and `ROLLBACK_TD` are
  untouched.
- **Hard stop if:**
  - the service is planned for **replacement**;
  - anything else changes or is destroyed;
  - the field walk below fails;
  - the guard below fails.
- **After the apply, an untargeted staging plan must read "No changes."**

**Pre-apply field walk** of `P1_TD`, the revision Terraform will register.
- Compare the planned `container_definitions` (`terraform show -json`) against `LIVE_TD`.
- **Precondition:** staging `core_image_tag` names the live image's tag exactly. That is
  `v2-08de4e6` today, which resolves to `sha256:2393682f…a777`; `arclight/core` is IMMUTABLE
  (Core verified it).
  - If a Core release has rolled since, `core_image_tag` must already match it.
  - Otherwise Terraform would register a newest-ACTIVE revision carrying an **older** image,
    and `deploy-service.yml` would base the next deploy on it.
- Allowed differences: the image form (tag against digest) and AWS-normalised defaults.
- Anything else is a stop. The registered revision becomes `deploy-service.yml`'s base
  (`describe-task-definition --task-definition "$FAMILY"`).
- **After the roll:** ECS's resolved `containers[0].imageDigest` on the running task equals
  `LIVE_DIGEST`.

**Coordination with Core's S-057** (image-only availability fix, in Astra review; Core,
2026-11-10):
- Either order works. The NLB attachment is service-level, and S-057 changes only the image.
- **Never apply P1 during an S-057 rollout.**
- Tell Core which revision is live before S-057's field walk. If P1 registers `:19` first,
  S-057 becomes `:20`. Core's plan says "the next revision".

**NLB gates, for every P1 and P2 apply.**
- `scripts/plan_guard.py` checks CloudTrail protection only. It does **not** enforce these
  gates; they are manual, each with a stated evidence source (codex-1, codex-2).
- **Authored configuration** (the phase PR's HCL, not plan values):
  - why HCL: `target_group_health` is Optional+Computed in the provider, so a plan's `after`
    values carry it even when the HCL omits it;
  - no `target_group_health` block anywhere;
  - `enable_cross_zone_load_balancing = false` on both NLBs;
  - `load_balancing_cross_zone_enabled` set explicitly on every NLB target group: `"true"` on
    Core's (3a), `"false"` on SF's unless P2 decides otherwise;
  - each listener's `load_balancer_arn` and `default_action` reference its own service's NLB
    and target group, by root resource reference. An unresolved reference is a stop, not a
    pass.
- **Plan JSON:** the resource change list matches the phase's expected list exactly.
- **Live, after the apply:**
  - `describe-load-balancer-attributes` shows cross-zone false on both NLBs;
  - `describe-target-group-attributes` shows the intended cross-zone value and the
    AWS-default DNS failover on every target group;
  - `describe-target-health` on each group lists only that service's task IP:port. ECS owns
    registration, so the shared-IP:port check can only be made at runtime.

**P2 additional hard stop:** any change to Core's NLB, listener, target group, zone, record or
alarm.

**P2 and P3:** each phase's PR carries its own exact list from its own plan.

## Acceptance

**P1:**
1. **Steady within 15 min, or abort.** Core's service has no deployment circuit breaker.
   - **On success:**
     - `LIVE_TD` 1/1, running `LIVE_DIGEST`;
     - `stg-int-core-8000` healthy;
     - the public target group healthy.
   - **On abort:** remove `additional_load_balancers` (an in-place update). Then confirm:
     - `LIVE_TD` 1/1, running `LIVE_DIGEST`;
     - the public target group healthy;
     - Core's service `loadBalancers` lists only the public target group;
     - `stg-int-core-8000` has no registered targets. ECS deregisters them when the
       load-balancer configuration changes, so "healthy" is not expected here (Codex review,
       PR #74).
2. **In-VPC probe**, from SF's security group and from NF's, in the private app subnets with no
   public IP:
   - every address `core-internal` resolves to completes a TLS handshake and answers `/ready`
     200. Since 3a that is both node addresses; before 3a it was only Core's AZ node;
   - the TLS handshake verifies against public roots;
   - `GET /.well-known/jwks.json` returns 200 with one active key;
   - `GET /ready` returns 200 `ready`.
3. **Per-node check.** The probe also connects with SNI `core-internal` to **each** NLB node IP
   explicitly (from `describe-network-interfaces`).
   - **Since 3a:** each node IP must complete a verified TLS handshake and answer `/ready` 200.
   - **Measured before 3a (P1, 2026-11-10):** the node without a local target accepted TCP and
     then failed. From SF's group it was a TLS handshake timeout; from NF's, the handshake
     completed and HTTP came back empty after 5 s. That is the after-connect case NF's Happy
     Eyeballs cannot absorb, and it is why 3a was made.
4. **Client IP preserved.** Core's access-log line for the probe's request shows the probe
   task's own IP. Uvicorn runs `--no-proxy-headers`, so it logs the transport peer.
5. **Public path unchanged.** `/ready` through Cloudflare and Access returns 200, and ELB 5XX
   counts stay at zero.
6. **First AZ-move gap.** On the first Core redeploy that changes AZ, measure the real gap: dig
   over time, plus failed connects.

**Probe family `arclight-probe-staging`:**
- **Ownership (codex-1):**
  - Terraform owns the execution role and the log group; both are in P1's target list.
  - The task definition is registered by hand for each run, from a JSON template committed
    with P1 and pinned to `LIVE_DIGEST`. It is deregistered after the run.
  - It is not a Terraform resource.
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
- With SF at 0/0 and SF's NLB in place, every `core-internal` address still answers and the
  Core probe still passes. This proves the isolation.
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
  - **SF's first start is G4's gate, not the alarms' (codex-2).**
  - At 0/0 these alarms sit in ALARM with actions disabled. CloudWatch notifies only on a state
    change, so enabling actions later sends nothing while the state stays ALARM. A first SF
    task that never becomes healthy therefore pages no one.
  - G4's operator readiness gate owns that failure.
  - When G4 adopts `shuttleforge_desired_count = 1`, apply the alarm updates and confirm
    `ActionsEnabled = true` and `StateValue = OK` on all three before closing G4.
- **Never alarm on `ZonalHealthStatus`.** A cross-zone-off singleton, as on SF's NLB, always
  reports 0 in the AZ without its task.
- **`TCP_Target_Reset_Count` on Core's NLB is the watch item for amendment 3a's residual
  collision risk.** It stays non-paging until a baseline exists.
  - **Observed after the 3a apply (2026-11-10):** two probes left 25 target resets, all on
    the cross-zone (1a) node, decaying over four minutes after the probe tasks had stopped.
    Every request succeeded, and Core logged no error.
  - So the metric alone cannot separate collisions from teardown noise. A collision shows as a
    failed connect or request, such as NF's `core_auth.unreachable`, and that is the
    discriminating signal.
  - The cause is Unverified (see `PROJECT_STATE.md`, DR-10).

**Diagnostic metrics** (dashboard or non-paging until a baseline exists):
- **Per NLB:**
  - `TCP_Target_Reset_Count`, `TCP_ELB_Reset_Count`, `TCP_Client_Reset_Count`;
  - `ClientTLSNegotiationErrorCount`;
  - `SecurityGroupBlockedFlowCount_Inbound_TCP` and `_Outbound_TCP`, which catch rule gaps;
  - `ZonalHealthStatus` summed across AZs:
    - on SF's NLB (cross-zone off), 1 is normal and 0 means fail-open;
    - on Core's NLB since 3a, 2 is the expected normal (Inferred). The 3a verification records
      the baseline.
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
| NLCU: a fraction of one at staging load | +$4.38 per NLB at one full NLCU continuously |
| Inter-AZ transfer: $0.01/GB charged at each end when a consumer and the published node are in different AZs | cents |

- **After P1:** about $17.03 (one NLB, one zone, one alarm).
- **After P2:** about $34.25, including all four alarms.
- **With one full NLCU on each NLB:** about $43.01, before transfer, probe runs and logs. That
  is not a ceiling.

## Rollback

**P1:**
- Remove Core's `additional_load_balancers`. That is an in-place update and a rolling
  deployment of `LIVE_TD`.
- Destroy Core's NLB resources. The public path is untouched.
- If `P1_TD` turns out wrong, deregister `P1_TD` so `LIVE_TD` is the latest ACTIVE revision
  again.
- Image rollback stays "update the service to `ROLLBACK_TD`" (`:17` today). `loadBalancers` lives on the service, so a task-definition rollback keeps
  the NLB attached. Removing the NLB is its own rollback (Core).

**P2:** remove SF's `additional_load_balancers`, then SF's NLB resources. Core is unaffected.

**P3.** D-077 bounds this rollback (codex-2, hotpants).
- **After a consumer's live-material gate** (SF past Stage C entry, or NF past N-G4), plain HTTP
  is never a recovery path.
  - Repair TLS.
  - If compliant transport is unavailable, **hold or stop** that consumer's activity until it
    is restored.
- **Before that gate** (fixture data only), HTTP recovery is allowed, in this order:
  1. restore the direct rules first;
  2. restore the templates and SSM;
  3. register a **new ACTIVE** `http` revision with the intended digest, then `update-service`.
     - A deregistered pre-P3 revision cannot be reused.
     - Restoring templates alone does not move a running service.

## Residual risks

- **AZ moves.** A gap of up to the TTL, plus AWS's undocumented DNS update time, whenever a
  singleton changes AZ.
  - The reviewer's CloudTrail read suggests that happens on about two-thirds of Core
    replacements (Inferred).
  - Removing the gap needs cross-zone on (collision class) or AZ pinning (loses AZ fallback).
  - **Amendment 3a turned cross-zone on for Core**, which removes this gap for Core. P1 had
    measured it at 4-6 minutes with an after-connect failure. It remains for SF's NLB until P2
    decides.
- **`/ready` blips.**
  - **With cross-zone off (SF's NLB until P2 decides):** a blip marks the singleton's only zone
    unhealthy, so the NLB fails open. About half of new connections land on the node with no
    target and fail, during the blip and for up to the TTL after it.
  - **With cross-zone on (Core, since 3a):** a blip leaves the group with only unhealthy
    targets. AWS documents that the NLB then routes to them anyway (target fail-open), and
    either node can reach the task. So a blip is no longer compounded by a node with no target.
    What a client sees then depends on Core's own state. This is Inferred for this listener
    until a blip is observed.
- **Consumer behaviour on a dead or stale node** (NF-reported from its code at main
  `0f755ea3`, 2026-11-10; not re-verified by Overcast):
  - NF has **no per-request retry**.
  - Its httpx clients (Core token, SF lease API) connect with Happy Eyeballs across every
    resolved address. An address that refuses or resets at TCP connect is skipped, and one
    that times out is overtaken after 0.25 s.
  - A connection that completes TCP and TLS and then fails **fails the request**:
    `core_auth.unreachable` for the token, and the intent is left open for reconciliation on
    a lease.
  - NF's proxy client (curl_cffi, `retry=0`) tries each address on connect failure.
  - Tokens are cached for 600 s, and pooled connections idle out after 5 s.
  - So NF absorbs a connect-time failure and recovers from a stale-DNS window within about
    one 30 s probe past the TTL. An attempt that lands on an accepted-then-failed connection
    fails and is recorded.
  - P1 acceptance item 3 measured the after-connect case on Core's empty-AZ node before 3a.
    Since 3a both of Core's nodes reach the task. The case still applies to SF's NLB until P2
    decides.
  - SF's JWKS retry inside its 1 h cache is SF-reported and unverified. Whether SF or NF read
    the SSM parameters at runtime is also unverified.
- **Wiring mistakes** reopen known defects:
  - an SF group on Core's NLB brings back F1;
  - one target on both NLBs brings back the shared-target collision class;
  - a cross-zone `"true"` group accepts the singleton collision class. Only Core's group does,
    deliberately (3a); on any other group it is a mistake until P2 decides;
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

- The NF `:9100` configuration item, if NF uses that port. SF's manifest amendment landed on
  2026-11-10 (see P2).

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
- **Confirmation round on revision 3 (`53c42b7`)**, same reviewers and setup, at the owner's
  direction. Reports are in the session scratchpad under `nlb/r3/`.
  - **Verdicts:**
    - codex-1: GO-WITH-CHANGES for the merge and P1;
    - codex-2: GO-WITH-CHANGES for the merge, GO for P1;
    - hotpants: GO-WITH-CHANGES for both.
  - All three confirm F1 and F2 are resolved and ask for no topology change.
  - Their P2 corrections were each checked against code, AWS docs or SF's manifest at
    `63f4492` before acceptance. All are applied:
    - captured revision identities instead of a fixed `:18` / `:19`;
    - a P3 rollback that respects D-077 and never reuses deregistered revisions;
    - the NLB gates as manual checks with stated evidence sources (`plan_guard.py` covers
      CloudTrail only);
    - G4 owning SF's first-start failure while its alarms are muted;
    - path B for stopped services;
    - probe task-definition ownership;
    - sentinel inspection by ARN dereference;
    - consumer attestation that clients verify certificates and hostnames;
    - the SF YAML naming marked as agreed and pending;
    - corrected costs.
