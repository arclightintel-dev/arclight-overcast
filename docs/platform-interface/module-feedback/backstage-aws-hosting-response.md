# Overcast response — Backstage on AWS (hosting brief of 2026-10-21)

> **Answered**: 2026-10-21 by claude-main (Overcast) | **To**: Backstage orchestrator, via the owner
> **Naming**: the product is Backstage; `podbay` is a legacy repository and code name only. Overcast's former Podbay platform substrate (controller, workspace hosts, coturn) was removed on 2026-10-21 under O-011 and has nothing to do with this application.
> **Basis**: Overcast `main` at `32301e2`; live AWS reads 2026-10-21; `docs/service_registry.md` (2026-09-30 provider observations). No infrastructure was created for this answer.

Verdict on the §4 shape: **GO-WITH-CONDITIONS** (conditions at the end).

## A. Accounts and conventions

**A1.** Account `650880817826`, region `us-east-1`, same as everything else. It is the management account of Organization `o-626c11uior` with no member accounts. The platform rule (D-059 position 5) is one account until real operational material enters production or the team passes five developers; Backstage carries real procurement data and proxy credentials, so it meets the first trigger on day one. **Needs owner**: (a) same account, separated by its own Terraform root, VPC, IAM boundary and tags, which Overcast can stand up now; or (b) a new member account under the Organization, which is cleaner isolation but adds Identity Center, cross-account state and a second set of guardrails before anything runs. Overcast recommends (a) now with (b) as the stated destination. Tags: `app=backstage`, `environment=<env>`, `managed-by=terraform`. Resource names `arclight-backstage-<env>-*`; secret paths `arclight/backstage/<env>/*`.

**A2.** Terraform, `terraform/envs/backstage/` as its own root with its own state key in the existing state bucket (`backstage/terraform.tfstate`), reusing Overcast modules where they fit (`vpc`, `alb`, `secrets`, `observability`, `ecr`, `iam-github-oidc`) and one new module for the Docker host. Overcast owns every file under `terraform/` and `.github/`. Backstage owns its repository, image, compose file and a deployment manifest (B-side deliverable 1). Overcast consumes the manifest, Backstage consumes Terraform outputs (ALB DNS, bucket names, secret ARNs, SSM parameter names).

**A3.** One environment to start, named `backstage-prod` in naming and `prod` in tags, because the owner wants the production hostname and three real users; a `staging` copy is a second root instantiation when there is something to test against. Rough monthly cost for the single-host shape in (a): EC2 4 vCPU/16 GB on-demand about $120 (m6i.xlarge; t3.xlarge about $100 with burst limits), gp3 100 GB about $8, ALB about $20, NAT gateway about $35 plus data, S3 and snapshots a few dollars, CloudWatch a few dollars: **about $190–220 before egress traffic and before any network-layer domain filtering** (see D9, which can double it).

## B. DNS, edge, certificates

**B4.** `arclight-complex.net` is **not in Route 53**. It is a Cloudflare zone in account CF-01 (`0f8d0f55f4873252390ed99f611f3f1a`), managed by hand today; Terraform adoption is an unmerged Overcast branch. `backstage.arclight-complex.net` is a proxied CNAME to the ALB, created by Overcast in Cloudflare. No clash: Core is `core.staging.arclight-complex.net` and prod hostnames are reserved for platform modules; `backstage` is unused. The certificate exists already: an ACM wildcard `*.arclight-complex.net` is issued and used by the prod ALB (`terraform/envs/prod/main.tf:34–38`), and a second one covers `*.staging.arclight-complex.net`. Backstage's ALB attaches the wildcard; nothing to request.

**B5.** ALB, not CloudFront, in front of one host: the app needs WebSockets and long-lived connections, the ALB already carries a 3600 s idle timeout (`terraform/modules/alb/main.tf:78`), and Cloudflare is the CDN/edge already. Overcast's ALBs admit only Cloudflare's IP ranges (O-005), so the hostname must be Cloudflare-proxied. There is **no WAF baseline** in Overcast today (no `wafv2` anywhere in `terraform/`); Cloudflare's managed rules at the zone are the current edge protection. A Cloudflare Access gate in front of the hostname is available as a second factor (the staging gate uses one-time PIN); with Entra SSO in the app it is optional.

## C. Identity

**C6.** The tenant is `27564b9c-b516-4bc4-9aa5-5692a38a1116` ("ANS Analytics LLC"; verified domains `ansanalytics.com` default, `arclightlabs.io`, `ANSAnalytics.onmicrosoft.com`); administrator `john@arclightlabs.io`. The "arclightlabs.io tenant" in the brief is this tenant. **New app registration**, not reuse: the existing registrations (`Arclight Core Staging`, `Arclight Core Dev`, `backstage`, others) belong to other applications; a registration named `backstage` already exists in the tenant and must be inspected before a new one is created, so the owner does not end up with two. Group and role claims: use **app roles** on the registration (`ops`, `operator`, `dev`, `admin`) assigned to users; they arrive in the ID token's `roles` claim without the groups-claim size and GUID-mapping problems. Overcast's Entra management identity (`Application.ReadWrite.OwnedBy`) can create and own the registration through Terraform if the owner prefers it managed; the brief says the owner updates it by hand, and both are fine.

**C7.** No platform rule on client type. Overcast's recommendation for a server-side FastAPI relying party: **confidential client** (client secret in Secrets Manager) with PKCE as well. Redirect `https://backstage.arclight-complex.net/auth/callback`; the Desktop app uses the same web flow through the cloud host rather than its own registration, which keeps one client and one secret. Dex is not needed in AWS.

## D. Compute, Docker, network

**D8.** EC2 with Docker fits. Overcast ran a plain Ubuntu 24.04 EC2 host with user-data bootstrap, an instance profile, SSM agent and a Secrets Manager read for coturn (module retired 2026-10-21, pattern in git history at `6a507e0^:terraform/modules/coturn/main.tf`), so the host module is a known shape, not an experiment. Recommendation for this application: **one EC2 host running `docker compose`** (app, Engine, Litestream sidecar), with the Portal containers started by the app through the host's Docker socket, in a private subnet behind the ALB. ECS-on-EC2 is possible but adds the ECS agent, task definitions and a capacity provider for no gain at three users, and the app's own container launches would still need the Docker socket. Constraints: Chromium containers need `--shm-size` and memory limits per container, not privileged mode; the app container holding the Docker socket is root-equivalent on the host, which is acceptable only because the host runs nothing else. Size 4 vCPU/16 GB as proposed; Portal sessions are the memory driver, so Backstage must state per-session memory and the concurrency cap (B-side deliverable 1).

**D9.** What Overcast runs today: a NAT gateway per VPC and security groups; **no Network Firewall, no domain allowlisting, no egress proxy**. Security groups cannot filter by domain. Enforcing "only proxy endpoints plus allowlist" at the network layer means one of: (i) **AWS Network Firewall** with a domain (TLS SNI/HTTP host) allowlist, about $290/month for the endpoint plus per-GB, the only managed option; (ii) an Overcast-run **forward proxy host** (Squid with an allowlist) that is the host's sole egress, with the host's security group permitting 443 only to that proxy and the proxy's security group permitting the allowlist's resolved addresses, cheap but another box to run and to keep in step with proxy-provider address changes; (iii) **host-level** enforcement, an allowlisting forward proxy container on the same host plus iptables forcing all egress through it, no network-layer guarantee against the host itself. **Needs owner** on cost: Overcast recommends (ii) if the hard rule must hold at the network layer and (iii) if host-level is accepted, and in every case the app's own proxy rule remains the primary control. Direct denial of source domains is a consequence of allowlisting, not a separate rule.

**D10.** Same HTTPS endpoint and WebSockets for the Desktop app; no restriction. Cloudflare proxies WebSockets; the ALB idle timeout is already 3600 s. The only consequence is that Desktop users are admitted by the same Cloudflare and Entra path as browsers.

## E. Data, backups, secrets

**E11.** SQLite on gp3 with WAL is fine for one writer. Backup pattern: **Litestream to S3** (continuous WAL shipping, versioned bucket, 30-day retention) for `podbay.db` and `control.sqlite`, plus **daily EBS snapshots** through AWS Backup (Overcast has no Backup vault yet; it is a roadmap item and Backstage would be the first consumer) with 14 daily and 4 weekly points, plus S3 versioning on the assets bucket if assets move. Encryption: SSE-S3 (AES256) and the account's default EBS key are the Overcast pattern; a per-app KMS CMK is not needed for three users and adds key-policy work. Restore drill before go-live is a condition (see verdict).

**E12.** **Secrets Manager** for secrets (Anthropic key, proxy credentials, OIDC client secret, session keys) as shells created by Terraform and populated by the operator, never in Terraform state (INV-004); **SSM Parameter Store** for non-secret configuration. Delivery at boot: the instance profile may read only `arclight/backstage/<env>/*`; a bootstrap script fetches each secret into a root-owned `0600` env file consumed by `docker compose`, and a deploy re-reads them. No secret in the image, the repo or user-data.

**E13.** One-time migration: Overcast creates `arclight-backstage-<env>-migration` (versioned, SSE-S3, lifecycle 30 days); the owner uploads with `aws s3 cp --recursive` from the PC (25 GB over a home link is hours, not days; S3 Transfer Acceleration is available if it drags); the host runs `aws s3 sync` to the EBS volume through the S3 gateway endpoint (no NAT charges); Litestream starts after the copy. Cutover is a scheduled stop of the local app, final sync, start on AWS, DNS already pointing at the ALB.

## F. Deploy, observability, distribution

**F14.** GitHub Actions in the Backstage repository (`arclightintel-dev/podbay`, confirmed as its own repository) builds the image and pushes to ECR `arclight/backstage` through an OIDC push role Overcast provisions (same pattern as Core and ShuttleForge; trust on the branch Backstage names). Deploy: an Overcast workflow (`workflow_dispatch`, plus `repository_dispatch` from the Backstage repo if wanted) runs `docker compose pull` and `up -d` on the host through **SSM Run Command**, no SSH, then checks the app's readiness URL body. Who presses deploy: the Backstage orchestrator or the owner; Overcast does not deploy on merge.

**F15.** CloudWatch: the host's container logs through the `awslogs` driver into `/arclight/backstage/<env>/{app,engine,portal,litestream}`, 30-day retention; the CloudWatch agent for disk and memory. Alarms Overcast expects every app to have: ALB 5xx rate, target unhealthy, host status check, root and data volume above 80 percent, and for this app a Litestream replication-lag alarm (custom metric) and a Portal container-count ceiling. SNS to the existing alarm address.

**F16.** Installers: S3 bucket behind CloudFront with an origin access control, at `downloads.backstage.arclight-complex.net` or a path on the main hostname via the ALB; CloudFront is the better fit for large static files and avoids pushing installer bytes through the app host. Code signing: **Overcast has no Windows Authenticode certificate and no macOS signing identity** (needs owner). Options: Azure Trusted Signing (uses the existing Entra tenant, monthly fee, no hardware token) for Windows; an Apple Developer account for macOS. Unsigned Windows installers trip SmartScreen for three analysts, which is survivable but ugly; macOS unsigned is painful. Overcast's position: Windows first, signed through Azure Trusted Signing; macOS only if an analyst needs it.

## G. Open-ended

**G17. Conflicts and what breaks first.** (1) The Docker socket in the app container is the biggest standing risk: a compromise of the app is a compromise of the host and every secret on it. Mitigation is isolation (nothing else on the host, no platform access from it) and the egress controls, not a fix. (2) The proxy rule is only as strong as the weakest path: the Engine's Anthropic calls and the app's identity-provider calls are legitimate direct egress, and any allowlist must be explicit about them; a misconfigured allowlist breaks sign-in first. (3) SQLite at 12 GB restores slowly; the first restore drill will show the real RTO. (4) The host is a single point of failure by design; a bad deploy means downtime until the previous image is re-pulled, so the compose file must pin image digests and keep the previous one. (5) Nothing in Overcast's charter covers a non-platform application; the owner's direction is enough to proceed, and Overcast records it as a decision, but Complex should be told so the platform record does not later claim Backstage is a module.

**G18. Missing from the brief.** Admin access path (SSM Session Manager, no SSH, no bastion; the host's security group has no inbound at all except from the ALB). Patching (Ubuntu unattended-upgrades for the OS; image rebuilds for the app; Docker engine updates on a schedule). Access logging (ALB access logs to S3, CloudTrail already on). Disaster recovery (restore drill, documented RTO/RPO, the migration bucket doubles as the seed for a rebuild). Data classification and retention for 860K procurement records and 13 GB of downloaded attachments (who may see what, how long it is kept, and whether any of it changes the D-059 account-separation answer). Session and cookie hardening behind two proxies (the app must trust `X-Forwarded-*` from the ALB only and build URLs from the configured host, not the Host header it receives). A health endpoint contract (what `200` means, what the deploy check reads). Budget alarm (Overcast has one for the account; a per-app cost allocation tag is the minimum).

**G19. What Overcast needs from Backstage, in order.**
1. A **deployment manifest** in the Backstage repo, the same shape Overcast asks of platform modules: image name and build command, ports (8430, 8781, anything the Portal exposes), every environment variable with default and production value, the list of secrets by name, volumes and paths (`podbay.db`, `control.sqlite`, `data/`, the Docker socket), readiness and liveness URLs and what their bodies mean, per-Portal-session memory and the concurrency cap, outbound destinations by hostname (proxy provider endpoints, Anthropic, Entra, anything else), and the compose file that runs it.
2. The **Entra facts**: whether the existing `backstage` registration is theirs, the final redirect URIs, which claims the app reads (roles vs groups), and the client type.
3. The **egress decision input**: the exact proxy-provider hostnames and whether their addresses are stable, so D9 can be costed.
4. The **data facts**: current sizes of the two databases and `data/`, growth rate, and whether `data/` must stay on local disk or can be served from S3 with a cache.
5. The **cutover window** the analysts can accept.

## What Overcast builds, in order

1. Decision record (O-012) that Overcast hosts Backstage as a non-platform application, with the account-separation and egress answers the owner gives; Complex informed.
2. `terraform/envs/backstage/` root: VPC (own CIDR), ALB with the wildcard certificate and a host rule, secret shells, SSM parameters, ECR repository and OIDC push role for `arclightintel-dev/podbay`, migration and Litestream buckets, log groups and alarms.
3. Host module: Ubuntu 24.04 EC2, instance profile (SSM core, secret read, S3 read/write to its buckets, ECR pull), gp3 data volume, user-data that installs Docker and compose, fetches secrets and starts the stack; specified before it is written (INV-005 exists because the last EC2 module burned four apply cycles).
4. Egress control per the owner's D9 choice.
5. Deploy workflow (SSM Run Command) and the downloads bucket with CloudFront.
6. Cloudflare record and, if wanted, an Access policy.
7. Migration runbook, restore drill, cutover.

## What Backstage must deliver

1. The deployment manifest and compose file (G19.1) before item 2 above starts.
2. The app changes the brief already lists: Entra as direct OIDC issuer, `X-Forwarded-*` trust limited to the ALB, readiness endpoint, optimistic concurrency, Litestream-compatible file layout (WAL mode, no other writer), Desktop packaging.
3. An image in ECR built by its own CI through the push role.
4. The Entra registration (owner) with app roles and the redirect URI.
5. Operator values for every secret shell.

## Verdict

**GO-WITH-CONDITIONS** on the §4 shape. Conditions:

1. Owner decides A1 (same account with separation now, member account later) and D9 (which egress enforcement, at what cost); both are recorded before Overcast writes Terraform.
2. The deployment manifest (G19.1) exists before the host module is specified.
3. The Portal runs through the Docker socket on a host that runs nothing else; no privileged containers; per-container memory limits and a concurrency cap come from Backstage.
4. Litestream plus EBS snapshots are in place and **one restore drill is completed before cutover**; the restore drill is also the first real test of Overcast's backup pattern for any app.
5. The app trusts `X-Forwarded-*` only from the ALB and builds absolute URLs from configuration; sessions and CSRF survive two proxies (Cloudflare and the ALB).
6. Windows installers are signed (Azure Trusted Signing or an owner-supplied certificate) before the download link goes on the login page; macOS is out of scope until an analyst needs it.
7. Deploys pin image digests and keep the previous image on the host for rollback.

Overcast will not start Terraform for Backstage until conditions 1 and 2 are met; everything else is sequenced in the build list above.

## Addendum: owner decisions, 2026-10-21 (O-012)

The owner answered the needs-owner items and asked three questions; the shape is revised accordingly.

| Topic | Decision / answer |
|---|---|
| A1 account | Same account, not walled off; prototype platform app. Backstage uses the existing **prod VPC and prod ALB** (wildcard certificate already attached, nothing else running) through a separate Terraform root with data sources. No new VPC, NAT or ALB. |
| "More direct than Ubuntu + Docker + ALB?" | The ALB is already paid for and already does WebSockets; reusing it is the direct path. A Cloudflare Tunnel from the host would remove the ALB and all inbound surface but buys nothing while the ALB exists. |
| E11 backups | Weekly EBS snapshots, 30-day retention (owner), **plus** Litestream continuous WAL shipping to S3 (cents per month) so the recovery point is minutes, not a week. |
| Cost | With the shared VPC/ALB: `t3.large` about $60/month running all day, about $20/month with idle-stop (no ALB requests for 30 min, then stop; scheduled start in the morning), plus about $12 for gp3 100 GB, S3 and logs. Wake-on-login (Cloudflare Worker starts the instance on the first request, "starting" page for about two minutes) is a later step if wanted. 16 GB only if many concurrent Portal sessions. |
| D9 egress | Proxy-only, no firewall product. Launch with the app's proxy rule and a host security group allowing egress only to the proxy provider, Anthropic, Entra and AWS endpoints; move to ShuttleForge's lease API when SF is deployed and narrow egress to SF's security group. |
| F16 signing | Azure Trusted Signing, Windows only. |
| C6/C7 identity | Direct Entra now with the existing `backstage` registration and app roles. Whether Core should broker login later (Core as OIDC issuer with Arclight scopes) was asked of Core on 2026-10-21; if supported, the issuer swap is a configuration change in the same relying-party code. |
| Cutover | Open now. Gate: Backstage's deployment manifest (G19.1). |

Verdict unchanged: GO-WITH-CONDITIONS; condition 1 (account, egress) is met by O-012, condition 2 (manifest) is the remaining gate.

