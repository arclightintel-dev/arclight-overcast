# Internal TLS for Core and ShuttleForge: one internal NLB (D-077, DR-10)

Status: **DRAFT revision 2, for review. Nothing built or applied.**
- Each phase is applied only on the owner's go, given first-hand, after this spec is reviewed.
- Revision 2 folds in the internal adversarial review (GO-WITH-CHANGES; findings 1-12 below)
  and Core's notes relayed by Complex.

## Why

Owner rulings, 2026-11-10:
- **D-077**, which Complex records as a pointer under D-074. On deployed environments, every
  internal hop that carries a credential uses TLS with server authentication that the client
  verifies.
- **Option A for Core**, chosen in Overcast's session on Overcast's recommendation. TLS ends
  at an internal load balancer that holds a public ACM certificate. The last hop to the task
  stays plain inside the private subnets, the same posture as today's public path.
  End-to-end TLS is v2 hardening.
- **ShuttleForge's `:9000`, `:9050` and `:9100` are in scope**, with no v1 exception for the
  proxy ports. The owner confirmed this to SF, and SF relayed it.
- **Sequencing:**
  - Core's JWKS and `/oauth/token` come first. They gate SF's SF.11 Stage C and Nerfherder's
    service start; NF PR #55 refuses an `http` Core URL on a deployed environment.
  - SF's inbound hops follow, before SF holds its first live provider credential.

Credentials on these hops today, all plain HTTP inside the VPC:

| Hop | Credential |
|---|---|
| SF → Core JWKS | none (public keys), but key integrity |
| NF → Core `/oauth/token` | NF's client secret (Basic) |
| NF → SF `:9000` | NF's Core JWT; lease credential in the response |
| NF → SF `:9050` / `:9100` | lease credential in `Proxy-Authorization` |

## Design

**One internal Network Load Balancer, `arclight-staging-internal`:**
- `internal = true`, `load_balancer_type = "network"`, IPv4.
- In the two private app subnets: `10.0.10.0/24` (us-east-1a) and `10.0.11.0/24`
  (us-east-1b).
- A security group **attached at creation**. AWS does not allow one to be added to an NLB
  later.
- Why an NLB and not an ALB:
  - `:9050` and `:9100` carry CONNECT tunnels, which an ALB does not carry. SF's manifest
    already bans them from ALB target groups.
  - An NLB keeps the client's IP (below).

**Cross-zone load balancing OFF** (review finding 2).
- With client IP preservation **and** cross-zone both on, AWS documents intermittent resets
  from 5-tuple collisions. A client that reuses one source port toward both NLB node IPs
  reaches the same target twice. The named risk factor is a small number of targets, and
  ours are singletons (re:Post *Troubleshoot connections that drop or intermittently fail
  with my NLB*).
- With cross-zone off, the node IP of an AZ with no healthy target leaves the NLB's DNS, so
  a singleton still works.
- **Cost:** a bounded gap of about 60 s (the record's TTL) when a deploy moves the task to
  the other AZ. Clients that cached the old node IP fail until they re-resolve.
- **Why that is acceptable:**
  - SF's JWKS refresh retries well inside its 1 h cache.
  - NF's token and lease calls retry or fail visibly. A failure surfaces as
    `core_auth.unreachable`, and S4's gate catches it before any run.
  - Collisions with cross-zone on would be random and silent instead.

**Listeners** (TLS):
- Certificate: `data.aws_acm_certificate.staging`, the issued `*.staging.arclight-complex.net`
  wildcard. It renews automatically.
- `ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"`, with no ALPN policy (HTTP/1.1).
- The TLS listener idle timeout is **fixed at 350 s**.
  - NF opens a fresh CONNECT per request and holds it at most about 30 s, so the limit
    never applies today.
  - The NLB docs say: "When a TLS listener receives a TCP keepalive packet from either a
    client or a target, the load balancer generates TCP keepalive packets and sends them to
    both the front-end and back-end connections every 20 seconds" (*Network Load Balancers →
    Connection idle timeout*). So TCP keepalive from either side extends a long-lived tunnel
    if a later consumer needs one.
- Core's note: a caller that declares a long body and then stalls holds its connection until
  that 350 s timeout, where the public ALB's idle timeout bounds it today. The callers are
  trusted internal services, so this is LOW.

| Listener | Name | Target group (name ≤ 32 chars) | Phase |
|---|---|---|---|
| 443 | `core-internal.staging.arclight-complex.net` | `stg-int-core-8000` → Core :8000 | P1 |
| 9000 | `shuttleforge-internal.staging.arclight-complex.net` | `stg-int-sf-9000` → SF :9000 (lease API) | P2 |
| 9050 | same | `stg-int-sf-9050` → SF :9050 (upstream proxy) | P2 |
| 9100 | same | `stg-int-sf-9100` → SF :9100 (MITM proxy) | P2 |

**Target groups:**
- `protocol = "TCP"`, `target_type = "ip"`.
- `preserve_client_ip = "true"`, set explicitly. It defaults to off for TCP target groups
  with IP targets.
- `proxy_protocol_v2 = false`. Uvicorn and mitmproxy do not parse it (Core).
- `deregistration_delay = 30`, matching the public Core target group.
- Health check: `protocol = "HTTP"`, `path = "/ready"`, `matcher = "200"`, `interval = 10`,
  `healthy_threshold = 2`, `unhealthy_threshold = 2`.
  - The thresholds are explicit to shorten SF's stop-before-start window.
  - Core's group checks its traffic port. All three SF groups check port 9000, because SF's
    manifest says every traffic-gating probe uses `/ready`, and `/ready`'s `proxy_engine`
    check covers SF's proxy listeners.
  - NLB health checks come from every node and are decided by consensus. Three SF groups
    multiply the `/ready` load on 9000 by three. At a 10 s interval that is small. If SF
    objects, groups 9050 and 9100 switch to TCP checks.
  - The Host header is the node's IP plus the listener port; Core does not validate Host (see
    "DR-10 spec points").
- SF ends with **four target groups** (the public ALB's plus three) of the five ECS allows
  per service.

**Client IP preservation.** Targets see the consumer task's own address as the transport
peer.
- **Core:** that address is untrusted, so the rate limiter keys on the consumer directly.
  `X-Forwarded-For` is never read on this path, and `CORE_TRUSTED_PROXY_CIDRS` is unchanged
  (Core, 2026-11-10, `rate_limit_service.py:81-105`). The rate-limit buckets carry over.
- **SF:** client-IP stickiness (`dataplane/routing.py:518`) and the `request.client.host`
  audit rows are unchanged (SF, 2026-11-10).
- **Hairpin.** No target calls its own NLB: Core never calls `core-internal`, and SF never
  calls `shuttleforge-internal`.

**DNS.** One **Route 53 private hosted zone per name**, associated with the staging VPC,
with an alias A record at the apex to the NLB and `evaluate_target_health = false`.
- The NLB's own DNS already drops node IPs without a healthy target.
- Each name is exactly one label under the wildcard. The Cloud Map form
  (`core.staging.internal…`) would not match the certificate.
- Inside the VPC the private zone wins, so the name never resolves to Cloudflare. A
  Cloudflare answer would send traffic out through the NAT and into Access.
- Today the VPC's only private zone is Cloud Map's `staging.internal.arclight-complex.net`
  (plus endpoint zones). Its DNS is AmazonProvidedDNS with no DNS firewall (read-only check,
  2026-11-10).
- Per-name zones avoid shadowing the public `*.staging` names.

**Security groups.**
- A target rule that references the NLB's security group admits data traffic and health
  checks even with client IP preserved, and blocks clients from reaching the target directly.
  The NLB's health checks are subject to its own egress rules (AWS doc *Update the security
  groups for your Network Load Balancer*).

| Group | Rule | Phase |
|---|---|---|
| NLB | ingress 443 from SF; ingress 443 from NF | P1 |
| NLB | egress 8000 to Core (traffic and health checks) | P1 |
| Core | ingress 8000 from NLB | P1 |
| NLB | ingress 9000, 9050, 9100 from NF; egress 9000, 9050, 9100 to SF | P2 |
| SF | ingress 9000, 9050, 9100 from NLB | P2 |
| NF | egress 9000, 9050, 9100 to NLB | P2 |
| removed | `core_from_sf`, `sf_to_core`, `core_from_nf`, `nf_to_core`, `nf_to_sf[*]`, `sf_from_nf[*]` | P3 |

- SF's and NF's egress to the NLB on 443 is already allowed by the module's `https_egress`
  (`ecs-service-fargate/main.tf:56-64`).
- SF's `sf_provider_egress` allows 0-65535 anywhere, so closing a plain path rests on
  **ingress** at Core and SF. The P3 test expects a timeout: security groups drop, they do
  not refuse.

**Module change (`ecs-service-fargate`).**
- New variable `additional_load_balancers`, a list of `{target_group_arn, container_port}`
  defaulting to `[]`, rendered as extra `load_balancer` blocks.
- `health_check_grace_period_seconds` applies when any load balancer is attached.
- The existing `target_group_arn` path is unchanged, so services that pass none plan no
  diff.
- **Ordering (review finding 1).** ECS refuses to attach a target group that has no
  load-balancer listener yet, with "target group … does not have an associated load
  balancer". The target group is created in seconds and the NLB and listener take minutes.
  - The root therefore passes each `target_group_arn` as
    `aws_lb_listener.<name>.default_action[0].target_group_arn`. That makes the service
    depend on its listener implicitly, so the attach waits until the listener exists.
- The provider updates the service in place. In provider v5.100.0
  (`internal/service/ecs/service.go`), `load_balancer` is a set with no ForceNew, and
  `UpdateService` sends `LoadBalancers` on change. `task_definition` is sent only on
  `HasChange`, which `ignore_changes` suppresses, so Core stays on `:18`.

## DR-10 spec points, closed

| Point | Resolution |
|---|---|
| (a) placement | **Private app subnets**, not the public ones DR-10 first floated. Client IP is preserved, so Core never sees the NLB as the peer. If preservation were ever switched off, the NLB's addresses would come from the app subnets, which Core does not trust, so Core would key on the NLB (one shared bucket). An NLB in the trusted `10.0.1.0/24` / `10.0.2.0/24` would instead let a forged `X-Forwarded-For` choose the key. The app-subnet choice fails safe. |
| (b) DNS | Route 53 private zone per name (above). |
| (c) Host | Core has no Host validation. Its only middlewares are the body cap and the request ID (`arclight_core/main.py:202-203` at `08de4e6`). `iss` is the fixed `https://core.internal`, and the JWKS and `/oauth/token` paths read neither Host, scheme nor `X-Forwarded-Proto` (Core, 2026-11-10). No Core change. |
| (d) health check | HTTP `/ready`, 200, as above. It is unauthenticated, not rate-limited, and returns 503 when not ready (TESTING_PROTOCOLS §3). |
| (e) NF URLs | Moved to `https://` in P3 (D-077 covers NF). |

## Phases

**One PR per phase, merged only around its own targeted apply** (review finding 11).
`terraform-apply.yml` would otherwise run untargeted on push to `main`. It is broken today
(DR-1), but it must not become the apply path.

**P1: the NLB, Core's 443 listener, DNS, Core's target group and the alarm.**
- `terraform/envs/staging/internal-tls.tf`, the module variable, and Core's
  `additional_load_balancers`.
- **An alarm on `HealthyHostCount < 1`** for `stg-int-core-8000`, sent to
  `module.observability.alarm_topic_arn` (review finding 6). After P3, SF's JWKS refresh and
  NF's token calls depend on this path.
- Attaching the target group starts a new rolling deployment of the **same** revision,
  `:18` (100/200).

**P2: SF's three listeners, its DNS name, target groups and rules.**
- Precondition: SF's `DEPLOYMENT_MANIFEST.md` amendment, allowing an NLB TLS listener on
  `:9050` / `:9100`, has merged on SF's line.
- SF is at 0/0, so attaching target groups starts no task.

**P3: consumers to `https://`, then close the plain paths.**
- **SF template:**
  - `SHUTTLEFORGE_CORE_JWKS_URL = https://core-internal…/.well-known/jwks.json`
  - `SHUTTLEFORGE_TRANSPORT_ENDPOINT = https://shuttleforge-internal…:9050`
- **NF template:**
  - `CORE_URL`, `NERFHERDER_JWKS_URL` and `SHUTTLEFORGE_URL` to the `https://` names;
  - **remove `NERFHERDER_ALLOW_PLAINTEXT_INTERNAL_HTTP=true`**
    (`services/nerfherder/task-definition.json.tpl:24`). It is NF's plaintext allowance,
    reported as a readiness `warn` (review finding 5).
- **SSM parameters** (`terraform/modules/secrets/main.tf:48-53`):
  - `core/internal-url`, `core/jwks-url`, `core/token-url` and `shuttleforge/internal-url`
    move to the `https://` names;
  - otherwise they would keep advertising closed plain paths.
- **Then remove** the six direct rules above.
- Both services are at 0/0 today. If P3 lands before SF's G4 and NF's N-G4, neither ever
  runs on plain HTTP.
  - SF would then not need DEBT #121's `SHUTTLEFORGE_ALLOW_PLAINTEXT_JWKS` on staging at
    all.
  - Otherwise that flag is set from the first image that carries the check until P3.

## Expected plans (gates)

Applies run locally by an administrator, targeted, after `scripts/plan_guard.py`, with the
full plan saved to a file and never truncated.

**P1 baseline (main at `e38708e`, 2026-11-10).** A full staging plan shows exactly
`1 to add, 0 to change, 1 to destroy`.
- That is the known churn on `module.core_service.aws_ecs_task_definition.this`. State still
  holds revision 8 (CIDR `10.0.0.0/16`, image `v2-d5a6e70`), and the template now renders
  H1b's ranges and `v2-08de4e6`.
- Targeting Core's service pulls that task definition in, so P1 carries the churn: it
  registers `:19` and deregisters the unused `:8`.
- `:17`, the rollback revision, is untouched.

**P1 targeted plan must read:**
- **Adds:**
  - the NLB, its security group and rules, and Core's 8000 ingress rule from the NLB's group;
  - `stg-int-core-8000`, the 443 listener, and the private zone and its alias record;
  - the `HealthyHostCount` alarm;
  - the probe family's role, policy and log group.
- **Update in place:** `module.core_service.aws_ecs_service.this`, with one `load_balancer`
  block added.
- **Replace:** `module.core_service.aws_ecs_task_definition.this` (`:19` in, `:8` out).
- **Hard stop if:**
  - `aws_ecs_service` is planned for **replacement**;
  - anything else changes or is destroyed;
  - the pre-apply `:19` field walk below fails.

**Pre-apply `:19` field walk** (review finding 4).
- Compare the planned `container_definitions` from `terraform show -json` on the saved plan
  against `aws ecs describe-task-definition --task-definition arclight-core-staging:18`.
- Allowed differences:
  - the image's form, `:v2-08de4e6` tag against `@sha256:2393682f…a777` digest. The tag
    resolves to that digest, and the repository is IMMUTABLE;
  - AWS-normalised defaults.
- Anything else is a stop. `:19` becomes `deploy-service.yml`'s base revision, because
  `describe-task-definition --task-definition "$FAMILY"` reads the latest ACTIVE revision.
- The review checked this read-only on 2026-11-10: `:18`'s environment equals the template,
  H1b's ranges included.

**P2 and P3:** the exact lists go into each phase's PR, from its own plan. The gate is the
same: SF's and NF's services update in place, and in P2 nothing else is destroyed.

## Acceptance

**P1:**
1. **Steady state within 15 min**, or abort (review finding 7). Core's service has no
   deployment circuit breaker. If the new target group's health check fails, ECS keeps
   replacing the new task while the old one serves.
   - Abort means removing `additional_load_balancers` from Core, which is another in-place
     update.
   - Then: `:18` 1/1 with digest `sha256:2393682f…a777`; `stg-int-core-8000` healthy; the
     public target group healthy.
2. **In-VPC probe**, once from SF's security group and once from NF's, in the private app
   subnets with no public IP:
   - the name resolves only to NLB addresses in `10.0.10.0/24` / `10.0.11.0/24`; with
     cross-zone off, that is only the address in Core's AZ;
   - the TLS handshake verifies against public roots;
   - `GET /.well-known/jwks.json` returns 200 with one active key;
   - `GET /ready` returns 200 `ready`.
3. **Client IP preserved** (review finding 8). Core's access-log line for the probe's request
   shows the probe task's own IP, not an NLB node address. Uvicorn runs `--no-proxy-headers`,
   so it logs the transport peer.
4. **Probe family `arclight-probe-staging`** (review finding 10):
   - **Image:** Core's, by digest. It has Python and the Debian CA store, `CMD` only, no
     `ENTRYPOINT`, and runs as `appuser`. The digest is **re-pinned per run** from the live
     Core revision, because ECR's lifecycle keeps only the last ten `v` tags.
   - **Secrets:** none, and no task role. It never carries a Core secret into another
     service's group.
   - **Execution role:**
     - `ecr:GetAuthorizationToken` on `*`;
     - `ecr:BatchGetImage`, `ecr:GetDownloadUrlForLayer` and `ecr:BatchCheckLayerAvailability`
       on the `arclight/core` repository;
     - `logs:CreateLogStream` and `logs:PutLogEvents` on its own log group.
   - **Log group:** `/arclight/staging/probe`, an `aws_cloudwatch_log_group` with 30-day
     retention.
   - **Command:** one `python -c` that resolves, connects and prints the results.
5. **Public path unchanged.** `/ready` through Cloudflare and Access returns 200, and the ELB
   5XX counts stay at zero.

**P2:**
- All three SF target groups pass health checks once SF runs (after G4); before then
  `unused` is expected at 0/0.
- Probe from NF's security group: TLS to `shuttleforge-internal:9000`, then `/ready`.
- SF's `/ready` accepts an `IP:listener-port` Host.
- SF's public ALB target group is still healthy.
- The proxy path is proven by NF's lease smoke once SF serves leases.

**P3:**
- The direct rules are gone. A direct `:8000` connection from SF's and NF's groups **times
  out**; the probe tries it.
- The rendered task definitions carry the `https://` URLs and no
  `NERFHERDER_ALLOW_PLAINTEXT_INTERNAL_HTTP`.
- The four SSM parameters read `https://`.

## Cost

AWS list prices for us-east-1 (ELB pricing page, read 2026-11-10):
- **NLB:** $0.0225 an hour ≈ **$16.43 a month**, plus $0.006 per NLCU-hour.
  - A TLS NLCU is 50 new connections a second, 3,000 active connections, or 1 GB an hour,
    billed on the highest.
  - At staging traffic that is a fraction of one NLCU; a full NLCU every hour would add
    $4.38.
- **Route 53:** two private hosted zones at $0.50 each a month.
- **CloudWatch:** one standard alarm at $0.10 a month.
- **Total: about $17.50-22 a month.** P2 adds no base cost.

## Rollback

**P1:**
- Remove Core's `additional_load_balancers`. That is an in-place update and a rolling
  deployment of `:18`.
- Then destroy the NLB resources. The public path is untouched throughout.
- If `:19` turns out wrong after apply, **deregister `:19`** so `:18` is the family's latest
  ACTIVE revision and `deploy-service.yml`'s base again.
- Image rollback stays "update the service to revision 17".

**P2:** remove SF's target groups and listeners.

**P3:** restore the direct rules, the `http://` URLs and the NF flag. Only needed if an
`https://` path fails before a consumer runs live material.

## Out of scope

- The public path (Cloudflare → ALB → Core).
- End-to-end TLS to the task (v2).
- The Cloudflare Terraform root.
- NF's internal config beyond Overcast's template.
- `:9100` CA trust on NF's side. If NF uses `:9100`, its single transport bundle must hold
  the public roots plus SF's MITM CA, because curl_cffi uses one bundle as both `CAINFO` and
  `PROXY_CAINFO`. That is NF's configuration and a later Overcast file-placement item.

## Open before P2

- SF's manifest amendment.
- The NF configuration item for `:9100`, if NF uses that port.
- SF's view on TCP health checks for 9050 and 9100.

## Review record

- **Internal adversarial review, 2026-11-10: GO-WITH-CHANGES.** All twelve findings were
  re-verified against code and AWS docs, and all are applied above:
  1. listener-to-service ordering;
  2. cross-zone off;
  3. DR-10 points closed;
  4. pre-apply field walk, and deregistering `:19` on failure;
  5. P3 also removes NF's plaintext flag and fixes the SSM URLs;
  6. alarm;
  7. abort rule;
  8. client-IP proof;
  9. health-check thresholds, target-group names and SF's four target groups;
  10. probe log group, role and per-run digest;
  11. one PR per phase;
  12. the keepalive wording, now backed by an AWS quote, and `evaluate_target_health = false`.
- **Core, via Complex (2026-11-10):** concurs, with no code change. Its three settings
  (client IP preserved explicitly, PPv2 off, the security group at creation and referenced)
  and its stalled-body note are included.
- **External reviews** (codex-1, codex-2, hotpants): pending.
