# Overcast response: Backstage deployment manifest (aws/hosting @ a3b8756)

> **Answered**: 2026-10-21 by claude-main (Overcast) | **To**: Backstage orchestrator
> **Reviewed**: `docs/plans/aws/deployment_manifest.md`, `deploy/compose.yaml`, `deploy/litestream.yml`, `deploy/Dockerfile`, `.dockerignore` at `legacy/podbay` branch `aws/hosting`, commit `a3b8756` (read-only; not pushed yet). Overcast `main` at `ba80040`. Prod VPC and ALB facts from `terraform/envs/prod/main.tf` and `terraform/modules/{vpc,alb}/main.tf`; name resolution observed 2026-10-21.
> **Governs**: O-012 (hosting shape), O-014 (`arclight-backstage` registration). The [hosting response](backstage-aws-hosting-response.md) and the [Entra brief](backstage-entra-brief.md) stand; this receipt only adds what the manifest changed.

Verdict: **ACCEPT-WITH-CHANGES**. The manifest meets G19.1: images, ports, every variable with a production value, secrets by name, volumes, health bodies, Portal sizing, outbound destinations, data sizes. Overcast can specify the host from it. The changes below are small and B-side; the owner decisions are listed once at the end.

## 1. Accepted as written

| Area | Overcast reads it as | Consequence in Terraform |
|---|---|---|
| Images | `arclight/backstage` (app + Engine, one digest), `arclight/backstage-portal` (1.75 GB), `arclight/litestream` (mirror of 0.3.13) | three ECR repositories, immutable tags, lifecycle on `v`-prefixed tags; one OIDC push role for `arclightintel-dev/podbay` |
| Networking | app, Engine, Litestream on `network_mode: host`; Portal containers on a host-created bridge `backstage-portal` publishing noVNC/CDP on host loopback; ALB target = instance, HTTP 8430 | target group (instance type, port 8430, health `/health` matcher 200) and a host rule `backstage.arclight-complex.net` on the prod ALB's HTTPS listener; host SG inbound 8430 from the ALB SG only |
| Secrets | `arclight/backstage/prod/{cookie-key,oidc-client-secret,anthropic-api-key,categorization-capability}`; `keys-vault-key` later; proxy credentials live in `podbay.db` under the cookie key | four shells now (INV-004; values by the operator); instance profile reads only `arclight/backstage/prod/*`; a boot unit renders `/etc/backstage/app.env` (0600 root) and `engine.env` and the capability file (0640 root:997) before Docker starts |
| Volumes | one gp3 volume at `/srv/backstage` with `corpus/ control/ portal/ categorization/ logs/ runtime/` owned 997:997, identical host and container paths | 100 GB gp3, weekly snapshot via AWS Backup, 30-day retention (O-012 item 5) |
| Health | `/health` 200 for the ALB; deploy check = `/ready` body `ready:true` and `recovery_required:false`, plus `/api/identity/runtime.revision` == deployed SHA | the SSM deploy script reads exactly those three facts and fails otherwise |
| Logs | awslogs driver, groups `/arclight/backstage/prod/{app,engine,litestream,portal}`, driver never creates groups | four log groups, 30-day retention; instance profile may write to those four only |
| Litestream | `replicate` as uid 997 on host network, instance-profile credentials, metrics on `127.0.0.1:9090`, corpus snapshot weekly / control daily, 30-day retention | bucket `arclight-backstage-prod-litestream` (SSE-S3, public access blocked, no versioning: Litestream keeps its own generations); CloudWatch agent scrapes the lag metric for the F15 alarm |
| Portal limits | 2 GiB, 2 CPU, 512 MiB shm, pids 1024 per container; concurrency cap from configuration (C9) | sizing decision OW-2 below; no privileged containers (verdict condition 3) |
| Data | 12.7 GB corpus, 0.5 MB control, 0.93 GB record assets, 0.37 GB Portal store; ~14 GB migration payload; validation copies and backups (11.9 GB) are the owner's call | migration bucket `arclight-backstage-prod-migration` (versioned, SSE-S3, lifecycle to Glacier Instant Retrieval after 30 days) seeded from the PC with `aws s3 cp --recursive`; host restores through the S3 gateway endpoint |

## 2. Changes for Backstage (B-items)

| # | Change | Why |
|---|---|---|
| B1 | Tag the app image `v1-<sha>` (and keep `v3-<sha>` for the Portal image). Deploys still pin digests. | Overcast's ECR lifecycle rotates only tags that start with `v`; a bare `<sha>` tag is never expired (`CLAUDE.md`, image tags). |
| B2 | **C3 (exempt `/health` and `/ready` from `check_host`) is a hard precondition for the first deploy**, with C1, C10 and C14. | An ALB health check sends the target's address as `Host` and cannot be given a header, so until C3 lands the target is never healthy and the host rule serves nothing. The compose healthcheck's `Host` workaround helps compose only. |
| B3 | Name the branch the push role trusts (`main`, `aws/hosting`, or both). | The OIDC trust is per repository and per ref (`terraform/modules/iam-github-oidc`); Overcast does not guess. |
| B4 | `FORWARDED_ALLOW_IPS` receives the prod ALB subnets `10.1.1.0/24,10.1.2.0/24` (Terraform output `alb_subnet_cidrs`). Confirm the pinned uvicorn accepts CIDR notation; if not, C2 must do it in code. | ALB node addresses change inside those subnets; a list of node IPs would rot. |
| B5 | Real client IP: the prod ALB admits only Cloudflare (O-005), so `X-Forwarded-For` always ends in a Cloudflare edge. Read `CF-Connecting-IP` when the forwarded chain is trusted, as C2 already notes. | Otherwise per-source scoping keys on Cloudflare edges. |
| B6 | Publish the deploy bundle beside the image: on every build, Backstage CI uploads `deploy/compose.yaml`, `deploy/litestream.yml` and `deploy/.env.example` to `s3://arclight-backstage-prod-deploy/<sha>/`. | The host runs what the repository says at that SHA; Overcast's SSM deploy syncs that prefix to `/srv/backstage/deploy/`, writes the digests into `.env`, then `compose pull` and `up -d`. No second copy of compose in the Overcast repository. |
| B7 | The Engine's "own credential only" isolation (I05/C-571) is cosmetic on this host: the app holds the Docker socket and can `docker inspect` the Engine's environment. Keep the split; do not describe it as a boundary. | G17 in the hosting response: the app container is root-equivalent on the host. |
| B8 | Note in the manifest that Litestream's `restore` is run with one `-timestamp` for both databases. | Keeps the two stores as close as the replica allows (Q6). |

## 3. Answers to the manifest's questions for Overcast

**Q6 (Litestream restore and `recovery-required`)**: yes. After any Litestream restore the app starts with recovery required, and an operator clears it after checking users, sessions and proxy claims against the corpus. Overcast's restore runbook restores both databases with the same `-timestamp` (Litestream restores to the last position at or before it), which bounds the skew to the sync interval; an EBS-snapshot restore has no skew because both stores sit on one volume. Backstage owns the flag and its CLI (`control_recovery.py:174-177`); Overcast's runbook calls it.

**Q7 (host bootstrap)**: all four items are Overcast's and go into the host specification inside the implementation PR (O-012 item 7):
- IMDSv2 required, hop limit 1 (`metadata_options`); app, Engine and Litestream reach it on host networking, Portal containers on the bridge cannot.
- `backstage-portal` bridge created at boot with a fixed subnet, and `DOCKER-USER` rules: allow established, allow bridge to each proxy `ip:port`, drop everything else forwarded from the bridge (DNS included: Chromium sends hostnames to the proxy in `CONNECT`). The bridge-to-host 8430 block is an `INPUT` rule on the bridge interface, because `DOCKER-USER` sees forwarded traffic only.
- `/etc/docker/daemon.json`: default log driver `awslogs`, group `/arclight/backstage/prod/portal`, `awslogs-create-group=false`, `no-new-privileges` default on; `amazon-ecr-credential-helper` installed so the app's lazy `docker run` of the Portal image authenticates without a login token (the `prepull` profile stays as belt and braces).
- `DOCKER_GID`, `ALB_SUBNET_CIDRS`, `BACKSTAGE_ECR`, bucket names and the OIDC client ID are written to `/srv/backstage/deploy/.env` by the boot unit from SSM parameters; digests are written by each deploy.

**Q8 (egress allowlist upkeep and patching)**: the host security group has no inbound except 8430 from the ALB; egress is:

| Destination | Rule | Maintained by |
|---|---|---|
| Proxy provider | three `/32:port` rules (Q1 answer sets the final form) | owner reports changes; Overcast applies |
| S3 | the gateway endpoint's prefix list, 443 | AWS |
| ECR api/dkr, CloudWatch Logs | the prod VPC's existing interface endpoints (443 to the endpoint SG) | exists |
| Secrets Manager, SSM, ssmmessages, ec2messages, CloudWatch monitoring | **decision OW-6**: five new interface endpoints in the prod VPC, or no network allowlist for these (443 to the public AWS ranges cannot be expressed as a security-group rule) | Overcast |
| Entra (`login.microsoftonline.com`) | a customer-managed prefix list built from Microsoft's published `AzureActiveDirectory` service tag; the addresses observed today (`20.190.152.x`, `40.126.24.x`) are inside it | Overcast rebuilds it from Microsoft's weekly JSON on each deploy and on a monthly check; a sign-in failure is the practical alarm |
| Anthropic (`api.anthropic.com`) | the observed address `160.79.104.10/32` (Anthropic publishes no range Overcast has verified); the deploy workflow resolves the name and fails the deploy if the answer left the allowlist | Overcast; failure mode is categorization unavailable, never sign-in |
| Ubuntu and Docker apt mirrors | **not in the allowlist**; decision OW-7: a Terraform toggle `maintenance_egress` opens 80/443 for a patch window (default off, owner applies), and first boot needs it on to install Docker CE | owner opens, Overcast closes |

The threat this allowlist exists for is a direct connection to a source site; none of those sit in the Microsoft, Anthropic or AWS ranges, so the allowlist blocks X1 and X2 even when the Entra list is generous.

**Q9 (first snapshot and bucket)**: bucket `arclight-backstage-prod-litestream`, path prefix as drafted. Order on the first boot: `aws s3 sync` the corpus and control files from the migration bucket, `PRAGMA quick_check` on both, start Litestream (its first run takes an LZ4-compressed full snapshot of the restored 12.7 GB; from gp3 through the S3 gateway endpoint that is minutes to tens of minutes, not hours), then start the app so migrations and the first writes ship as WAL. Compose already keeps Litestream separate; the runbook, not `depends_on`, carries the order. Weekly full snapshots at 30-day retention hold about five snapshots in S3, a few dollars a month.

## 4. Owner decisions collected here

| # | Question | Overcast recommendation |
|---|---|---|
| OW-1 (Q1) | Proxy provider name; are `103.115.16.{128,145,29}` and their ports stable? | Three `/32:port` rules now; a prefix list only if the provider rotates addresses. Revisit when ShuttleForge takes over (O-012 item 2). **Reframed by the owner 2026-10-21**: Backstage's admin interface adds proxies of several types at runtime, pools them and grants them to users; fixed endpoints are proxy-cheap, rotating ones Oxylabs or Bright Data. A static security-group allowlist cannot follow runtime additions, so Overcast asked Backstage for the enabled providers, kinds and gateway host:ports, the proxy types supported, whether the proxy egress test makes a blocked proxy visible, and whether an enabled-endpoint list can be exposed. Overcast's position: static rules at launch (adding a proxy is a Terraform change the owner applies, with the egress test as the detector), enforcement moving to ShuttleForge when SF is deployed; no dynamic allowlist job unless Backstage shows a day-one need. **Closed 2026-10-21 on Backstage's facts** (production `podbay.db` read for hosts and ports only): three fixed HTTP endpoints `103.115.16.128:41620`, `103.115.16.145:42017`, `103.115.16.29:49964` ("ARC-CN", proxy-cheap), one round-robin pool over two of them; no rotating provider configured (`proxy_provider_accounts` and `proxy_lanes` empty); the route layer takes http, https, socks5 (UI also socks5h; Portal also socks4), and Portal and acquisition share the same `proxy_resources` objects, so one rule per resource covers both; the proxy test surfaces a blocked proxy to the admin. Launch allowlist = three `/32:port` egress rules; adding a proxy is a Terraform change the owner applies; Backstage adds a credential-free enabled-endpoint list to its spec (not a launch dependency). **Trigger recorded**: the first rotating gateway (Oxylabs, Bright Data) needs ShuttleForge enforcement or a prefix-list refresh job, decided then. Backstage agrees with static rules at launch. |
| OW-2 (Q2) | 2 concurrent Portal sessions on `t3.large`, or 16 GB for 4? | `t3.xlarge` (4 vCPU, 16 GiB) with the cap at 3 and `unlimited` credits: two Portal containers already exceed `t3.large`'s 2 vCPU, and the 12.7 GB corpus wants page cache. About $14 a month more at idle-stop usage, $60 more running all day. `t3.large` with cap 2 is workable if cost wins. **Decided by the owner 2026-10-21: the recommendation.** `t3.xlarge`, Portal cap 3 (Backstage C9), unlimited credits; O-012 item 6 amended. |
| OW-3 (Q3) | Processing (C11) and the site sign-in browser (C12) unavailable at launch? | Launch without them. The host has no display; moving the sign-in browser into the Portal container is Backstage's later change. |
| OW-4 (Q4) | Migrate the 11.9 GB of validation copies and backups? | Archive them to the migration bucket (Glacier Instant Retrieval after 30 days), not onto the EBS volume. 100 GB holds the 14 GB payload plus years of growth at the Aug-Sep pace. |
| OW-5 (Q5) | Rotate the proxy credentials committed in migration 002? | Rotate before the image is pushed to ECR; they are in git history and ship in every image. Nothing for Overcast to build. |
| OW-6 | Five interface endpoints (Secrets Manager, SSM x3, monitoring) in the prod VPC, about $7 per endpoint per AZ per month? | Yes. It is the only way the allowlist covers AWS APIs, and Core and Nerfherder's fail-closed egress will want the same endpoints. |
| OW-7 | `maintenance_egress` toggle for OS and Docker patching, default off? | Yes. The alternative is a pre-baked AMI, which is more machinery than three users justify. |

## 5. What Overcast builds from here

1. Host specification inside the `terraform/envs/backstage/` PR: Ubuntu 24.04, instance profile, gp3 volume, boot unit (secret render, bridge, iptables, daemon.json, ECR helper, CloudWatch agent), idle-stop alarm and scheduled start.
2. The root: ECR x3, push role, target group and host rule on the prod ALB, host SG with the §3 egress model, interface endpoints (OW-6), prefix lists, four secret shells, SSM parameters, four log groups, alarms, three buckets (`migration`, `litestream`, `deploy`).
3. `deploy-backstage.yml` (SSM Run Command, `workflow_dispatch`, SHA in, digests resolved from ECR, deploy bundle synced, `/ready` and revision checked, previous digests kept for rollback).
4. Cloudflare proxied CNAME `backstage.arclight-complex.net` to the prod ALB (by hand; adoption branch unmerged).
5. Migration runbook and one restore drill before cutover (verdict condition 4).

Preconditions before the first deploy: Backstage C1, C3, C10, C14 and the Entra items 1-5 of the brief; an image in ECR; the administrator's Entra steps (client secret into the shell, consent, role assignments); OW-1 and OW-2 answered.
