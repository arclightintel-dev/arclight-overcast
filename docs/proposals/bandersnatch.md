# Bandersnatch: gated delivery to a named outside recipient (spec)

Status: **Revision 1, draft for the owner's review. Spec only: nothing is built, applied,
sent or published.** The internal review is folded in (see "Review record"); the external
reviews wait on the owner's direction. The phased plan and its acceptance tests are in
[bandersnatch-plan.md](bandersnatch-plan.md).

Request: the owner, 2026-11-10 (condensed in "What was asked"). Branch `spec/bandersnatch`,
cut from `main` at `08ec540`. Live read-outs are dated 2026-11-10 and were read-only.

**This repository is public (DR-14).** This document names no recipient, no recipient
address, no payload subject, no public hostname and no recipient-facing wording. Real values
live outside git (see "Public-repository hygiene").

## Decisions for the owner

Each is argued in the section named. D1 comes first because every other answer depends on it.

| # | Decision | Recommendation | Section |
|---|---|---|---|
| **D1** | **Who owns the token, session and audit logic?** (a) a small hosted application in its own private repository, on Overcast's substrate; (b) Core; (c) Cloudflare Access alone | **(a)** for the first share, by owner ruling on the O-012 pattern. Whether it becomes the platform's standard is a question for Complex | [Ownership](#d1-ownership) |
| D2 | Environment | **Staging**, the only platform environment in v1 | [Environment](#d2-environment) |
| D3 | Which JSON ships | **The compact example.** The full export only on a stated need, and never its companion guide as it stands | [The JSON choice](#d3-which-json-ships) |
| **D3b** | **The page's own data bundle carries more than either JSON** | Before the first release, strip what the page never displays and every internal name and identifier; the owner confirms what remains | [Payload findings](#payload-findings-the-owner-must-see) |
| D4 | The OpenStreetMap tile calls | **A static map image built at release time**, and the map library removed | [Third-party calls](#third-party-calls-and-the-map) |
| D5 | Stamping | **Embedded metadata** in the JSON download, plus a visible line on the served page and metadata in each PDF. Needs the download to become a server file | [Stamping](#stamping) |
| D6 | Mail-scanner and forwarding hardening | The click completes only in the **browser that asked for the link**; any other browser must re-enter the token | [Link and activation](#link-and-activation) |
| D7 | Data store | **DynamoDB** (new, no network path to RDS) over the shared staging RDS | [Data model](#data-model) |
| D8 | Names and mailboxes | Neutral hostname, mail subdomain, sender name, reply-to and report mailboxes: the owner picks them, and **none is written in this repository** | [Hygiene](#public-repository-hygiene) |
| D9 | Token defaults | Expiry 7 days, one activation, three link emails, link valid 24 h | [Tokens](#accounts-and-tokens) |
| D10 | Retention | Accounts, tokens and served releases kept (A3, A4); audit 2 years; failed attempts by strangers 90 days; links and sessions 30 days after expiry | [Logging](#logging-and-retention) |
| D11 | Uptime | The service runs **only while a token is live**; desired count 0 otherwise | [Rollback](#rollback) |
| D12 | Lock mail on the hosting domain | Publish a null SPF and `p=reject` DMARC on `arclight-complex.net`, which never sends mail (A5) | [Mail](#mail-path) |
| D13 | SES production access | **The owner** submits AWS's request (outward-facing); draft text is in the plan | [Mail](#mail-path) |
| D14 | Issuing outside an account's domains (not in the brief; proposed here) | Issue only to a person recorded on the account; an address outside the account's domains needs an explicit override | [Tokens](#accounts-and-tokens) |
| D15 | Proving a request came through our own Cloudflare zone, while DR-21 is open | **A shared-secret header** added by a Cloudflare rule and required by the application, until DR-21's client certificates land | [Origin authentication](#origin-authentication-d15) |

Already decided by the owner (not reopened here):
- **A1. Activation:** strictly one hour from the click, once. Extending means reissuing.
- **A2. Binding:** a token binds to the exact address it was issued to, not a domain.
- **A3. Accounts** (2026-11-10, during drafting): tokens are tracked under accounts, and an
  account can be assigned domains, organisations and people.
- **A4. Served material is never retired** (same message): a release stays exactly as it was
  served and is only flagged inaccessible, so a token can be reissued against it.
- **A5. Domains** (2026-11-10, during drafting): `arclight-complex.net` is for application
  hosting; mail goes out under `arclightlabs.io`.

## What was asked

A minimal gated delivery path that serves a static page and a data download to a named
outside recipient. The owner wants it to become the platform's standard way to share pages,
data or parts of the platform externally. The first payload is a static sample site (HTML,
JS, CSS, images, PDFs) that is still being edited.

| # | Requirement |
|---|---|
| R1 | A nondescript page on the arclight-complex domain: a logo and three fields (token, name, email). No product, recipient or codename in the title, URL or copy |
| R2 | If the token is valid for that address, email the address a link. The same neutral response whether or not the details match |
| R3 | Rate-limit attempts |
| R4 | The link lands on a page that needs a click to start the session. A GET must not consume it (mail scanners open links first). The hour starts at the click |
| R5 | For one hour the session serves the page and allows the download, then ends |
| R6 | Tokens are per recipient, bound to the address, with an expiry and a use count, and revocable |
| R7 | Every asset (data, images, PDFs) sits behind the session. No public object URLs. `no-store` and `noindex` |
| R8 | Served content makes no third-party requests |
| R9 | Log who, when, source IP and what was downloaded |
| R10 | Stamp the download with the recipient and the issue time |
| R11 | The sending domain has aligned SPF, DKIM and DMARC |
| R12 | The payload is pinned to an exact commit or hash at release |

## D1. Ownership

**Overcast cannot own the logic.** The charter: "Modules own what runs. Overcast owns where
it runs" (`docs/CHARTER.md:13`). Overcast does not own "Domain logic, seam contracts, API
design" (l.32) and must not become "A module (no API, no seam contracts, no domain nouns)"
(l.39). The platform record says the same: "Overcast is not a product module — it has no
domain nouns, no seam contracts, no API" (Complex `platform/DECISIONS.md` l.1077 at `48c1715`).
Tokens, links, sessions, accounts and an audit trail are application behaviour with domain
nouns and an HTTP API.

**What Overcast does own here:** "Frontend web application deployment (S3 + CloudFront or
Fargate)" (`docs/CHARTER.md:21`) and "All domain management (Cloudflare DNS, ACM certificates,
SSL/TLS configuration)" (l.22). So Overcast hosts it, names it and provisions the
infrastructure its mail goes through; it does not write its request handling.

### Option (a): a small hosted application on Overcast's substrate (recommended)

A new private repository holds the application code, its Dockerfile, its tests and its
operator tool ("Dockerfiles stay in module repos", `docs/CHARTER.md:41`). Overcast provides
the ECS service, the load-balancer rule, the certificate, DNS, the mail identity, the data
tables, the payload bucket and the egress (everything under [Design](#design)).

The precedent is **O-012**: Backstage is "hosted by Overcast on AWS as a **prototype platform
application**, not a module and not a separate tenant", by owner ruling, with Complex told
and "no D-series decision … required for Overcast to proceed" (`docs/DECISIONS.md:151`,
`:161`).

- **For:** the smallest blast radius of the three (its own tables, bucket, mail identity and
  security group, nothing shared with Core's identity plane). It ships on its own cadence. It
  can meet every requirement and both later rulings (A3, A4).
- **Against:** a new repository and image to look after, and a second set of
  security-sensitive code outside Core's review chain.
- **What O-012 does and does not cover.** It covers Overcast hosting one application on the
  owner's word. It does not make that application "the platform's standard way to share":
  platform governance belongs to Complex (`docs/CHARTER.md:30`). The recommendation is
  therefore **(a) for the first share now, and the owner asks Complex whether the standard
  needs a D-series decision** before a second payload source, a caller from another module,
  or a platform principal depends on it.
- **A3 sharpens this.** Accounts with organisations, domains and people are a small directory
  of outside parties. That is more domain model, so further from Overcast, and it is the part
  most likely to belong with Core one day. It is kept in its own table, which the serving
  task cannot read, so it can move without touching the serving path.

### Option (b): the logic in Core

Core already owns tokens, identity, OIDC and the scope grant.

- **Core's vocabulary has room for outside parties**: the principal-type enum includes
  `external_client` (D-030, Complex `platform/DECISIONS.md` l.310) and there is an
  `external_consumer` principal plane (l.422). So (b) is the natural long-term home for *who
  the outside parties are*.
- **What is missing for this flow** is everything between that vocabulary and a working
  path: a way to admit someone by an out-of-band token plus proof of a mailbox, with no
  account and no login; a scope and a surface for "one hour of this release". D-070 §2 makes
  "the Core scope grant … the admission decision for a seam operation", and D-073 §1 sets
  "One authorization model for every Core-JWT caller" (l.1418, l.1485). Neither forbids an
  outside party; both mean that doing this in Core is a platform design task (identity
  contract, permission vocabulary), not an implementation detail.
- **Core cannot broker it today.** "Core-brokered login is not available in v1 (Core is not
  an OpenID provider)" (`docs/DECISIONS.md:156`).
- **It widens the identity plane's public surface.** Every Core hostname sits behind the
  `*.staging` Access application (live read-out below). An outsider flow needs an
  unauthenticated public path into the service that signs every platform token.
- **Most of the work is not identity.** Serving a pinned static site, stamping downloads and
  sending mail are not Core's job.

Not recommended for v1. If Core later admits external parties this way, the hosted
application can hand its token and account checks to Core without changing its public
behaviour.

### Option (c): managed edge only (Cloudflare Access)

Overcast would only configure: a self-hosted Access application on the page's hostname, a
per-address Include rule, one-time PIN login, a one-hour session. Checked against the flow:

| Requirement | Access with one-time PIN | Fit |
|---|---|---|
| R1: logo and three fields (token, name, email) | The login page takes a logo, header, footer and colour; "custom sign-in forms are not supported", so no token or name field. Sign-in runs on `<team>.cloudflareaccess.com` | **No** |
| R2: email a link; neutral response | The mail carries a code **and** a link. The page "will always say A code has been emailed to you" and blocked addresses get no mail | Neutral: yes. Mail: Cloudflare's |
| R4: a `GET` must not consume | Cloudflare's own page warns that mail-security tools following the link use the code up. A PIN lasts 10 minutes | **No** |
| R5, A1: one hour, once | A one-hour session can be set. The recipient can always request a new PIN and sign in again; there is no single-use or counted policy | **No** ("once" cannot be enforced) |
| R6: per-recipient token with expiry and use count | An Include rule lists exact addresses. No expiry date or use count on a rule | **Partly** |
| R9: who, when, IP, what was downloaded | Authentication logs: address, IP, country, time (no user agent). **Kept 24 hours on the Free plan.** Per-request logs are Enterprise-only | **No** |
| R10: stamped download | Nothing at the edge can stamp; the origin must | **No** |
| R11: our domain's SPF, DKIM, DMARC | Mail comes from `noreply@notify.cloudflare.com`; no documented way to change it | **No** |
| Seats | Each recipient takes one of 50 Free seats until removed | Operational |

Sources: Cloudflare's One-time PIN, session management, custom pages, Access authentication
logs, log retention and seat management documentation, read 2026-11-10.

**D-074 §6 also argues against the edge as the only control:** "Edge authentication is never
the control. An edge gate (for example Cloudflare Access) is defense in depth only" (Complex
`platform/DECISIONS.md` l.1542). That decision is written for module surfaces, and names the
control as the module's own credential check or the Core scope. Options (a) and (b) are those
two forms; (c) is neither. DR-21 gives the practical reason: a zone from another Cloudflare
account can reach the staging ALB and skip the Access application
(`docs/PROJECT_STATE.md:151`).

Option (c) is viable only if the owner relaxes R1, R4, R5, R6, R9, R10 and R11. A3 and A4
(accounts, reissue against kept material) have no counterpart in Access at all.

### Rejected runtimes for option (a)

- **Cloudflare Worker with KV or D1:** application code on a platform Overcast does not run
  today (the service registry records an empty Workers listing); logs and audit would live
  outside AWS.
- **CloudFront with Lambda@Edge:** edge functions log to the region of the edge location, and
  a function outside a VPC has internet egress that O-017 cannot constrain.

## D2. Environment

**Staging.** "For v1, staging is production (D-059 §9)" (Complex `platform/DECISIONS.md`
l.1052). The prod root holds only the substrate Backstage runs on, "not a production
environment awaiting apply" (`CLAUDE.md`, O-016); it has no ECS cluster and no database.
Staging has the cluster, the endpoints, the protected CloudTrail (O-015) and the O-017 egress
pattern this needs.

**What that costs.** This would be the **first hostname in the staging VPC that is not behind
the `*.staging` Access application**. Backstage is the only other Access-free application in
the account, and it sits in the prod VPC (O-012 D19). An internet-facing application in the
staging VPC must therefore have no security-group path to anything holding operational
material. That is why D7 recommends DynamoDB over the shared RDS, and why the design gives the
service no path to Core, ShuttleForge, Nerfherder or RDS (see
[Network](#network-and-egress-o-017), including what it can still reach).

D-059 §8 still applies: no automatic deploys; the owner's go per release. Every name in the
design derives from `var.environment` (INV-001); `staging` below is the value, not a literal.

## Verified reuse

Read 2026-11-10 from code at `08ec540` and live, read-only.

| Component | Verified state | Evidence | Use here |
|---|---|---|---|
| Staging ALB `arclight-staging` | Internet-facing; 443 with `ELBSecurityPolicy-TLS13-1-2-2021-06`; 80 redirects to 443; default action 404 "Not Found" | `terraform/modules/alb/main.tf:91-121`; live `describe-listeners`, `describe-rules` | Host the page behind one new host-header rule |
| ALB rules | Live priorities: ShuttleForge 2, Core 10, default. The module sets no priority (`alb/main.tf:157-172`); Core sits at 10 by hand (`docs/PROJECT_STATE.md:162-165`, `:181`) | live `describe-rules` | Our rule lives in the root with an explicit priority (Backstage pattern, `terraform/envs/backstage/alb.tf:5-44`) |
| ALB ingress | Cloudflare's 15 IPv4 and 7 IPv6 ranges only (O-005) | `terraform/envs/staging/main.tf:46-71`, `alb/main.tf:13-55` | Unchanged. DR-21 applies (D15) |
| ALB access logs | Off | live `access_logs.s3.enabled false`; no `access_logs` in `alb/main.tf:72-85` | Nothing secret may sit in a URL that a later change could log |
| ALB attributes | XFF `append`; invalid header fields not dropped; idle timeout 3600 s (`alb/main.tf:78`) | live attributes | Client IP comes from `CF-Connecting-IP`; the application enforces its own response deadline |
| Staging 443 certificate | `*.staging.arclight-complex.net` only; **no SNI certificates** | live `describe-listener-certificates`; no `aws_lb_listener_certificate` in the repo | Attach a second certificate |
| First-level wildcard | `*.arclight-complex.net` + apex, ISSUED, AMAZON_ISSUED, renewal eligible; in use by the prod ALB and Backstage's CloudFront; requested out of band, read through data sources (`terraform/envs/prod/main.tf:40-44`, `terraform/envs/backstage/downloads.tf:11-15`) | live `acm describe-certificate` | Attach to the staging 443 listener as SNI. **No new certificate, so no new Certificate Transparency entry names the page** |
| Fargate module | `internet_egress` default false (O-017); creates no target group or listener rule; registers Cloud Map; `desired_count` is Terraform-managed (`main.tf:95`, `:146-148`) | `terraform/modules/ecs-service-fargate/variables.tf:96-102`, `main.tf:21-68` | The service, with `internet_egress = false` |
| Interface endpoints (staging) | `ecr.api`, `ecr.dkr`, `logs`, `secretsmanager`; S3 gateway on the private route tables. **None carries an endpoint policy** | live `describe-vpc-endpoints`; `terraform/modules/vpc/main.tf:152-219` | Reuse ECR, Logs, S3, Secrets Manager |
| SES API endpoint | `com.amazonaws.us-east-1.email`: all six AZs; private DNS covers `email.us-east-1.amazonaws.com` and `email.us-east-1.api.aws`; endpoint policies supported. `email-smtp` is **not offered in us-east-1b**, one of staging's two AZs | live `describe-vpc-endpoint-services` | Add `email` to `extra_interface_endpoints` (`terraform/envs/staging/main.tf:83-85`). API, not SMTP |
| Endpoint security group | Inline ingress 443 from the private app subnet CIDRs | `terraform/modules/vpc/main.tf:136-150` | No change; our group adds egress to it (NF pattern, `terraform/envs/staging/nerfherder.tf:49-67`) |
| DynamoDB | Only `arclight-terraform-locks` exists; no DynamoDB endpoint in the VPC | live `list-tables`, `describe-vpc-endpoints` | New tables and a gateway endpoint (D7) |
| SES | **Sandbox** (`ProductionAccessEnabled: false`, 200 per 24 h, 1 per second); **no identities**; account suppression list on for bounces and complaints | live `sesv2 get-account`, `list-email-identities` | New domain identity; production access is an owner step (D13) |
| Mail DNS, `arclightlabs.io` (the mail domain, A5) | Zone on Cloudflare CF-01. MX to Microsoft 365; SPF `include:spf.protection.outlook.com -all`; DKIM `selector1` and `selector2` CNAMEs to Microsoft; DMARC `p=none` with a report mailbox on the domain | live public DNS (1.1.1.1); Cloudflare API (record names and types) | A dedicated subdomain for this sender; the apex records are not touched |
| Mail DNS, `arclight-complex.net` | **No MX, no TXT (no SPF), no `_dmarc`**; Email Routing off | live public DNS; Cloudflare API | Hosting only (A5). D12 locks it against spoofing |
| Mail DNS, `ansanalytics.com` | DNS at WordPress.com, not Cloudflare, with no management connection (`docs/service_registry.md:58`). MX to Microsoft 365, but SPF lists only WordPress's sender, no DKIM at `selector1`, DMARC `p=none` | live public DNS | **Not used.** Outside Overcast's DNS, and not aligned today |
| Cloudflare zone `arclight-complex.net` | Full (strict); Universal SSL covers `*.arclight-complex.net`; 9 records, none for mail | Cloudflare API, read-only token | One proxied record for the page |
| Zone settings that alter responses | **Email Address Obfuscation on**; **Network Error Logging on** (live `Nel` and `Report-To` headers naming `a.nel.cloudflare.com`); Automatic HTTPS Rewrites on; Rocket Loader off; Always Online off; browser cache TTL 14 400 s; **minimum TLS 1.0**; Always Use HTTPS off | Cloudflare API; `curl -sI` on an existing proxied hostname | Rules for the hostname (see [Edge](#edge-cloudflare)) |
| Web Analytics, Zaraz, Speed Brain | **Unreadable** with the read-only token (error 10000). Cloudflare documents Web Analytics (since 2025-10-15) and Speed Brain as on by default for Free zones | Cloudflare API; Cloudflare documentation | Treated as on until the owner reads the dashboard; blocked at the origin regardless |
| Cache, configuration and rate-limit rules | None exist (phase entrypoints absent) | Cloudflare API | New, scoped to the hostname |
| Access | Applications: `*.staging.arclight-complex.net` (24 h session; policies: one address, a "Cloudflare Login" login method, the `staging-automation` service token) and a Pages preview app. IdPs: one-time PIN, Cloudflare. No Entra | Cloudflare API, read-only token | **Not used.** The page hostname must match no Access application |
| Cloudflare write token | Scoped to `arclight-complex.net` only; DNS, zone settings, SSL and transform rules there | Operator's note of 2026-11-10 (not re-tested here) | Needs `arclightlabs.io` DNS and three more permissions; the owner has offered to extend it (plan P0) |
| Deploy workflow | `deploy-service.yml`'s manual trigger offers `core` and `shuttleforge` only (`repository_dispatch` takes any module name); it verifies the digest, then `/ready` through the public hostname with Access headers | `.github/workflows/deploy-service.yml:7-13`, `:24-25`, `:209-257` | Manual deploys for v1; the workflow cannot deploy this service by design (see IAM) |
| CI plan | Supplies `TF_VAR_core_image_tag` from a repository **variable**, which the public job log prints in clear, and `TF_VAR_alarm_email` from a **secret**, which it masks (run 42885203378). A new variable without a default fails the plan | `.github/workflows/terraform-plan.yml:35-37`, `:67` | The names come in as repository **secrets** |
| Push roles | Hard-coded list in `iam-github-oidc`; staging is its only caller. Adding a repository also widens the CI deploy role's `ECRVerifyImage` list in place (`main.tf:122-130`) | `terraform/modules/iam-github-oidc/main.tf:289-343`; `terraform/envs/staging/main.tf:161` | One entry for the new repository |
| Hosted-application pattern | Backstage: own root, own target group, explicit listener priority, standalone ALB egress rule | `terraform/envs/backstage/alb.tf:5-44`, `network.tf:86-95` | Same shape, inside the staging root |

Not reused, deliberately:
- **RDS** (see D7), and with it **`dbbootstrap`** (DR-17 makes its image hard to change).
- **Secrets Manager** holds at most one value here: D15's origin secret, as a shell
  (INV-004). Everything else is reached with the task role, and every token, nonce and
  session identifier is stored only as a hash.

## Design

```
recipient ──HTTPS──▶ Cloudflare (proxied; cache bypass; no injection; adds the origin secret)
                        │  Full (strict)
                        ▼
                 staging ALB :443  ── SNI *.arclight-complex.net ── rule: Host = <page-host>
                        │  8080 (health checks: 8081)
                        ▼
          bandersnatch task (Fargate, private app subnets, no internet egress)
             │ DynamoDB (gateway)   │ S3 payload (gateway)   │ SES API (interface)   │ Logs, ECR (interface)
```

### Edge (Cloudflare)

- One **proxied** record `<page-host>` → the staging ALB's DNS name. A **first-level** name
  under `arclight-complex.net`, so it falls outside the `*.staging` Access application and is
  covered by Universal SSL. It must match no Access application (AT-18).
- **The origin is the first layer for everything below.** It sends
  `Cache-Control: no-store, no-transform`. Cloudflare documents that `no-store` is never
  cached at the edge and that `no-transform` stops both the email-obfuscation rewrite and the
  Web Analytics beacon. The rules are the second layer, and AT-5b and AT-6 test the result
  as the browser receives it, because some of this is documented rather than proven.
- **Cache rule:** bypass cache for the hostname, browser TTL "respect origin". (`.pdf` is on
  Cloudflare's cached-by-default list, and the zone's 4-hour Browser Cache TTL overrides a
  lower origin `max-age`.)
- **Configuration rule for the hostname:**
  - Email Address Obfuscation **off** (it rewrites every address in HTML, which would mangle
    the visible stamp);
  - **Real User Monitoring off** (the Web Analytics beacon loads from
    `static.cloudflareinsights.com`, a third-party request, R8);
  - Automatic HTTPS Rewrites off, Rocket Loader off.
- **Response-header rule for the hostname: remove `NEL` and `Report-To`.** With them, a
  browser that hits a network error reports it to `a.nel.cloudflare.com`: a request to
  another host that R8 does not allow. (Turning Network Error Logging off for the whole zone
  is the alternative.)
- **Request-header rule for the hostname: set the origin secret** (D15).
- **Rate-limiting rule** on `POST` for the hostname. The Free plan gives the zone one rule
  (per IP, 10-second window and block). It is spent here to protect the single unextendable
  hour from a flood; the application's own limits remain the control.
- **Speed Brain** prefetches same-site links. The application refuses any request marked
  `Sec-Purpose: prefetch`, so a prefetch can never count as a view or a download.
- **Compression.** `no-transform` also stops Cloudflare compressing, so the application
  compresses text responses itself.
- **HTTPS only.** Always Use HTTPS is zone-wide and off, and Full (strict) forwards a
  plain-HTTP request to the origin over HTTP. The ALB's port-80 listener already answers 301
  to HTTPS, mailed links are always `https`, and the application sends HSTS.
- **Not ours to set:** Cloudflare answers `/cdn-cgi/*` itself, and its own error and
  challenge pages (like the ALB's 503 when the service is off) carry none of our headers and
  none of our content.
- **Minimum TLS** is zone-wide (1.0 today). Raising it is in the unmerged
  `cloudflare-adoption` branch: an observation here, not part of this change.

### Origin (ALB)

- `aws_lb_listener_certificate`: the existing `*.arclight-complex.net` certificate (data
  source, as prod and Backstage read it) on the staging 443 listener. The listener's default
  certificate stays `*.staging`.
- A target group (`ip`, HTTP 8080) and **one listener rule with an explicit priority** (20,
  which is free: the live rules sit at 2 and 10), condition `Host = <page-host>` only. Order
  does not matter, because the three host conditions are disjoint.
- **Health on its own port.** The target group's health check goes to port **8081**, path
  `/ready`. No listener forwards to 8081, so health is unreachable from the internet whatever
  `Host` is sent. `/ready` reports only "process up, DynamoDB reachable".
- Standalone ALB security-group egress rules to the service on 8080 and 8081 (Backstage
  pattern), and matching ingress on the service's group.
- The application's public routes on 8080 are exactly `/`, `/a/*`, `/v/*`, `/d/*` and
  `/robots.txt`. Everything else is the neutral 404.

### Origin authentication (D15)

DR-21: the ALB admits every Cloudflare address, so a zone in someone else's Cloudflare
account can be pointed at it. On that path our zone's rules do not run, and `CF-Connecting-IP`
is whatever that zone's configuration makes it (Cloudflare documents it as alterable inside a
zone's own Workers, and removable by a managed transform). The gate itself would hold, since
it does not depend on the IP. What fails is: per-IP limits (an attacker picks their own key,
or forges the recipient's to lock them out), and the source IP in the audit log (R9).

| Option | Effect | Cost |
|---|---|---|
| **1. Shared-secret header (recommended)** | Our zone's request-header rule sets a random value; the application returns the neutral 404 without it. Only traffic through our zone reaches the logic, so `CF-Connecting-IP` is Cloudflare's own value (Cloudflare refuses a client-supplied one with Error 1000) | One Secrets Manager shell, value written by the owner (INV-004), read by the execution role; one Cloudflare rule. Rotation is two values accepted during the change |
| 2. Wait for DR-21 | Client certificates on the origin pull close this for every staging hostname | The first share waits on DR-21's spec, plan and apply |
| 3. Accept it | Nothing to build | Forgeable rate-limit keys and logged IPs for anyone with their own Cloudflare zone, and a lockout lever against a recipient whose IP is known |

Option 1 is an interim. When DR-21 lands, the header and its shell are removed.

### Application behaviour

Normative for the application, and **temporary in this repository**: when the application's
repository exists this section moves there, and this document keeps only the interface
(ports, health, configuration, egress, IAM). The charter forbids Overcast becoming "A shadow
platform spec" (`docs/CHARTER.md:43`); specifying another repository's internals here is the
same hazard, accepted only until that repository exists.

**Every response the application generates carries:**
- `Cache-Control: no-store, no-transform`, `Pragma: no-cache`, `Expires: 0`.
- `X-Robots-Tag: noindex, nofollow, noarchive, nosnippet`; HTML also carries the robots meta
  tag; `/robots.txt` disallows everything.
- **`Referrer-Policy: same-origin`.** Nothing is sent to any other origin, so the page's
  address never reaches a link target. (`no-referrer` would be wrong here: under it browsers
  send `Origin: null` on form posts, and the CSRF check below would refuse every real
  submission.)
- `X-Content-Type-Options: nosniff`; `Strict-Transport-Security: max-age=31536000`;
  `Permissions-Policy` denying every feature; `Cross-Origin-Opener-Policy: same-origin`;
  `Cross-Origin-Resource-Policy: same-origin`.
- `Content-Security-Policy`: `default-src 'none'; frame-ancestors 'none'; base-uri 'none';
  form-action 'self'` plus the narrow `'self'` grants each page type needs. Payload pages
  get a per-release policy computed by the release tool, with no host outside `'self'` and
  `connect-src 'none'`.

**Every request is checked, in this order, before anything is counted or looked up:**
1. `Host` is `<page-host>` (compared case-insensitively, port ignored); otherwise 404. Mail
   links are built from configuration, never from the request.
2. The origin secret is present and correct (D15); otherwise 404.
3. `CF-Connecting-IP` is present and well-formed; otherwise 404. IPv6 clients are keyed by
   their /64.
4. `Sec-Purpose: prefetch` is refused.
5. For every `POST`, and for `/d/*`: `Sec-Fetch-Site` is `same-origin`, and on a `POST`
   `Origin` equals `https://<page-host>`. `null` is never accepted. Otherwise 403, whatever
   was submitted. This stops other sites, including sibling subdomains that browsers treat
   as same-site, from posting the forms or forcing a download.
6. Request headers and form fields are capped in size.

All wording the recipient sees (title, form labels, the neutral sentences, the mail) is
neutral, chosen by the owner and held with the names (D8). This document describes it and
does not quote it.

#### Landing page and submission

- `GET /`: one self-contained HTML response (logo inline, CSS inline under a hash, no
  script). Three fields: token, name, email. One button. One line saying access is logged.
- **Normalisation:** email trimmed and lower-cased (no dot or plus folding); token stripped of
  spaces and hyphens and upper-cased (Crockford base32: `O`→`0`, `I`/`L`→`1`); name trimmed,
  control characters removed, capped at 200 characters. **The name is recorded, not
  validated, and is never echoed into a page or a mail.**
- **Rate limits:**
  - **Per IP:** 5 per 15 minutes and 20 per day across both forms. Over the limit: 429 with a
    fixed body, **whatever was submitted**. This is the only limit that refuses.
  - **Per submitted address** (5 failures an hour) and **across the service** (100 an hour):
    these **count and alarm, and never change the response**. A refusal there would do
    nothing useful (a failed submission already sends no mail), would let anyone lock a
    recipient out, and would tell someone holding a token which address it belongs to.
- **Validity:** the token's hash exists; the token is not revoked, not expired and its account
  not suspended; it is bound to the submitted address; it has an activation and a link email
  left; and its release is flagged accessible.
- **If valid** (one DynamoDB transaction, with condition checks on the grant and the release): count the
  link request, record a new link as the token's only current link (older unconsumed links
  are superseded), write the audit event. The mail is handed to an in-process queue and sent
  after the response.
- **Always:** a 200 with one fixed neutral body, a fresh random **binding cookie** (called
  `B` here; 32 random bytes, `__Host-` prefix, `Secure; HttpOnly; SameSite=Strict; Path=/;
  Max-Age=86400`), and an audit event carrying the internal outcome.
- **Equal responses:** status, headers and body are byte-identical apart from the cookie value
  (same length). Every response to a submission is held to a **floor of 1.0 s plus 0-200 ms
  of jitter** from receipt, so database work and mail hand-off cannot be timed.
- **A link request is only spent when SES accepts the mail, and every reservation lives on
  the token.** `link_requests_used` counts accepted sends only. The submission's transaction
  adds the new link to the token's `pending_sends` (its hash and the time). When SES accepts
  the message, the entry is removed and the count goes up by one; if the send fails after
  retries (capped at 60 s) the entry is removed and `mail_failed` alarms. On a stop signal
  the task drains its queue first.
- **A task that dies with mail queued cannot tidy up, so the budget check ignores what it
  left.** The budget is accepted sends plus pending entries younger than two minutes. Older
  entries were never confirmed: they do not count, and the next submission removes them.
  Because every reservation is on the token itself, this also covers a link that a later
  submission superseded before either mail went out, with no search of the `links` table.
  An abrupt stop therefore costs the recipient one retry, never a link from the budget. The
  nonce is still never stored: an unsent link is simply abandoned. (If the task died after
  SES accepted but before recording it, the recipient can receive one mail more than the
  budget. That is the safe direction.)
- **Budget updates are conditional on the state record's version number**, so two submissions
  racing for the last permitted mail cannot both reserve it.

#### Link and activation

- The link is `https://<page-host>/a/<nonce>`, where the nonce is 32 random bytes (base64url).
  Only `SHA-256(nonce)` is stored, as is `SHA-256(B)`.
- **`GET /a/<nonce>` never changes state.** It returns the same static page for any nonce,
  valid or not: one button. It writes a `link_opened` audit event (IP, user agent) when the
  nonce matches, which is how scanner pre-fetches show up. `HEAD` is treated the same way.
- **`POST /a/<nonce>`** (the click) starts the session when all hold:
  - the nonce is the token's current link, unconsumed and less than 24 h old;
  - the token is not revoked or expired, its account is not suspended, its release is flagged
    accessible, and it has an **activation** left. The link-email budget is **not** checked
    here: the link in the last permitted mail must still work after that mail has used the
    budget up;
  - **binding (D6):** the request carries the cookie `B` whose hash was recorded with this
    link, **or** the form carries the token itself.
- Without `B` the click page answers with one field asking for the access code. So the
  recipient who requests and clicks in the same browser just clicks; on another device they
  type the token once more.
- On success, one DynamoDB transaction (idempotent on a client request token, so a retried
  write cannot count twice) marks the link consumed, counts the activation, creates the
  session and writes the audit event. The response sets the session cookie (called `S` here;
  32 random bytes, `__Host-` prefix, `Secure; HttpOnly; SameSite=Lax; Path=/; Max-Age` set
  to the seconds remaining) and redirects (303) to `/v/`.
- **Re-attaching, never restarting.** If the link is already consumed and its session is
  still inside its hour **and has not been revoked**, a `POST` that passes the binding check
  gets that same session back
  (the activation budget is not checked again, since no new activation happens):
  a new session identifier, the old one retired ten seconds later, **the same end time**.
  The ten seconds are for races: after a double click or two requests in flight, whichever
  response the browser keeps must carry a working identifier. This covers a response
  lost on a mobile network, a double click, and a mail app's built-in browser handing over
  to the real one. Without it the only activation could be spent with nothing to show for it.
  It is still one session and one hour (A1).
- Anything else: one neutral page saying the link can no longer be used.

Why D6 rather than a bare click:
- Some mail-security products render links in a sandbox and press buttons. A bare-click
  design would start the recipient's only session inside the scanner, spending the
  activation and handing the scanner a live cookie for an hour.
- `B` exists only in the browser that submitted the form, and the token only with the
  recipient. A scanner, or anyone the mail is forwarded to, has neither.
- The cost is one extra field when the recipient changes device between asking and clicking.

Why `Lax` for `S` and `Strict` for `B`: `B` is only ever needed on a `POST` from our own page.
`S` must survive the recipient clicking the mailed link again from webmail (a cross-site
navigation): with a live session, `GET /` and `GET /a/*` redirect to `/v/`. `Lax` sends the
cookie only on top-level `GET`s, none of which changes anything, and `/d/*` additionally
requires a same-origin request.

The nonce sits in the path, not the fragment: some link-rewriting gateways mishandle
fragments. The application never logs it, the referrer policy keeps it inside our own
origin, and ALB access logs are off; if they are ever turned on, `/a/` must be excluded.

#### Session

- Every `/v/*` and `/d/*` request needs a session whose hash exists, whose end time (start +
  3600 s, fixed) is in the future, which has not been revoked, which was not replaced more
  than ten seconds ago, whose token is not revoked, whose account is not suspended and whose
  release is flagged accessible. (The token's own expiry and budgets are checked at
  submission and activation, not during the hour.) Token and release are read consistently on
  every request, so revoking a token or flagging a release takes effect at the next request. Suspending an account reaches each of its tokens within
  seconds (see Data model).
- **Revoking a session** (the operator's `session revoke`) marks every identifier that
  session has had, and its link. The serving check reads the first; the re-attach check
  reads the second, so a revoked session cannot be picked up again under a new identifier.
- No sliding expiry, no refresh, no second session from the same link. A1: extension means a
  new token.
- No valid session: the neutral 404 for every path, so the asset tree cannot be probed.
- `/v/<path>` serves only paths listed in the pinned release manifest, with the manifest's
  content type. HTML pages carry the visible stamp and a refresh timed to the session's end,
  so an open tab does not outlive the hour.
- `/d/<file>` serves the stamped data download with `Content-Disposition: attachment` and a
  neutral file name.
- A response still being sent when the hour ends is cut off: the application sets its own
  write deadline at the session's end (the ALB's idle timeout is an hour).
- The client IP and user agent are recorded at activation and on every request. **IP changes
  are logged, not enforced** (recipients on mobile networks change address); the one-hour
  bound and revocation contain a stolen cookie instead.

#### Accounts and tokens

**Accounts (A3).** An account is what the owner tracks sharing by. It can be assigned any
number of **organisations**, **domains** and **people** (a name and an address each). Every
token is issued under exactly one account, to one person on it. An account answers "what have
we shared with them, who opened it, and when": its tokens, their sessions and downloads, and
the releases involved.

- Accounts are **records for tracking, not credentials**. A domain on an account admits
  nobody (A2: a token binds to one exact address).
- **D14 (proposed here, not in the brief).** The issuing tool refuses an address that is not
  a person on the account. If the address's domain is not one of the account's domains it
  asks for an explicit override, so a mistyped or personal address is caught before a token
  exists. It also checks the address against the SES suppression list.
- An account can be **suspended**: its tokens refuse within seconds.
- Account data identifies outside people. It lives only in the `accounts` table, which the
  serving task cannot read, and never in git.

**Tokens.**
- 130 random bits as 26 Crockford base32 characters, shown in groups. The plaintext is
  generated on the operator's machine, shown once, and given to the recipient **through a
  different channel from the mail** (phone, Signal, in person), with a word that a mail from
  our sender will follow. Only `SHA-256(token)` is stored. 130 random bits need no pepper:
  there is nothing to brute-force offline.
- Fields: account, bound address (normalised, validated against a strict address grammar at
  issue), release, issued at and by, expires at (default 7 days), `max_activations` (default
  and recommended **1**, A1), `max_link_requests` (default 3), revoked at, by and why.
- `max_activations` above 1 means separate one-hour sessions, never a longer one. The owner
  may prefer to fix it at 1 in code for v1 (D9).
- **Reissue (A4)** is a new token under the same account for the same release. The old token's
  record stays, so the account shows both. Token records are kept, not deleted: they hold a
  hash, not the token.
- The security model is **two factors held by the recipient**: the token (out-of-band
  channel) and control of the mailbox. Either alone starts nothing.

### Data model

**D7: DynamoDB, recommended.** Eight on-demand tables, point-in-time recovery on, deletion
protection on, AWS-owned encryption.

| Table | Key | Attributes | Kept |
|---|---|---|---|
| `accounts` | `account_id` + `item` (`META`, `ORG#…`, `DOMAIN#…`, `PERSON#<address>`) | label, state (`active`, `suspended`), notes; per assignment: who added it and when | Until the owner removes the account |
| `releases` | `release_id` | `manifest_sha256`, **`access`** (`accessible`, `inaccessible`), source repository and commit, published at and by, access changes (at, by, why) | **Always** (A4) |
| `tokens` (the grant; **written only by operators**) | `token_hash`; index on `account_id` | `token_id`, `account_id`, `email`, `release_id`, `manifest_sha256`, `issued_at`, `issued_by`, `expires_at`, `max_activations`, `max_link_requests`, `account_suspended`, `revoked_at`, `revoked_by`, `revoke_reason` | With the account (A3) |
| `token_state` (the counters; written by the task) | `token_hash` | `activations_used`, `link_requests_used`, `pending_sends`, `version`, `current_link_hash` | With the account (A3) |
| `links` | `nonce_hash` | `token_hash`, `binding_hash`, `created_at`, `expires_at`, `consumed_at`, `session_hash`, `session_revoked_at`, `ses_message_id` | TTL: `expires_at` + 30 d |
| `sessions` | `session_hash` | `token_hash`, `nonce_hash`, `started_at`, `expires_at`, `ip`, `user_agent`, `revoked_at`, `replaced_by`, `replaced_at` | TTL: `expires_at` + 30 d |
| `limits` | `key` (`ip#…`, `email#…`, `global#…` with the window) | `count` | TTL: window end + 1 h |
| `audit` | `event_id` (128 random bits); index on `account_id` | `at`, `event`, `outcome`, `account_id`, `token_id`, `session_id`, `release_id`, `manifest_sha256`, `ip`, `forwarded_for`, `cf_ray`, `user_agent`, `submitted_email`, `submitted_name`, `path`, `bytes`, `sha256`, `distribution_id`, `ses_message_id` | TTL per event class (D10) |

- **A token is two records, so the task can count without being able to change what was
  granted.** `tokens` holds who, what, until when, how many times, and whether it is revoked
  or suspended; only operators write it. `token_state` holds the counters, which the task
  updates. Every submission and activation is one transaction: a **condition check** on the
  grant (not revoked, not expired, account not suspended), a condition check on the release,
  and a conditional update of the state. A revocation that lands mid-click therefore wins.
  (An attribute-level allowlist on a single record cannot do this: DynamoDB applies such a
  list to the attributes a condition reads as well as those it writes, and requires the key
  in it, so the guards and the protection would exclude each other.)
- **The serving task reads `releases` and cannot write it; it has no access to `accounts`.**
  Suspending an account is the operator tool stamping `account_suspended` on each of the
  account's tokens and repeating until a consistent check finds none unstamped.
- **A release's `access` flag is a condition of every submission and activation, and is read
  on every request.** Flagging a release inaccessible stops every session on it at the next
  request and changes no object's bytes.
- Supersession costs no extra write: activation requires `nonce_hash == token_state.current_link_hash`.
- Single use and counts are `ConditionExpression`s inside `TransactWriteItems`, so two
  concurrent clicks cannot both start a session.
- **The audit table is write-only for the task:** it may only `PutItem` there (no get, query,
  scan, update or delete). A put can replace an item whose key is known, but event keys are
  random and never returned to the task. Every event is also written to CloudWatch Logs,
  which the task cannot alter; a disagreement between the two copies is itself evidence.
- Audit events: `submit`, `rate_limited` (one per key per window, with a count), `mail_sent`,
  `mail_failed`, `link_opened`, `activation_refused`, `session_started`,
  `session_reattached`, `asset_served`, `download`, `session_ended`, and the operator events
  `account_created`, `account_changed`, `token_issued`, `token_revoked`, `session_revoked`,
  `release_published`, `release_access_changed`.
- Tokens, nonces and session identifiers are never stored or logged in plaintext. Logs carry
  `token_id` and `session_id` (random, non-secret identifiers) instead.
- **Tracking view:** the operator tool's `report --account <id>` joins the account, its
  tokens and its audit events: who was issued what, which links were opened and from where,
  each session's start and end, each file served and each stamped download.

**Why not the staging RDS (the reuse option):**
- An internet-facing task would get a security-group path (5432) to the Postgres server that
  holds Core's, ShuttleForge's and Nerfherder's databases.
- It needs a new `dbbootstrap` mode (an image change; DR-17(a): CI cannot push it), three
  secret shells, a migration task family and an app role.
- Postgres grants can make the audit table insert-only, but an owner-role migration can undo
  that; DynamoDB's IAM boundary is outside the application's reach.
- RDS would give SQL for investigations. At this volume the audit table is small enough to
  export and query offline.

### Mail path

**Sender (A5).** A dedicated subdomain `<mail-domain>` of **`arclightlabs.io`**, with a
no-reply address, a neutral display name and a `Reply-To` pointing at a mailbox the owner
reads, so a recipient who replies "it does not open" reaches someone. A subdomain keeps this
sender apart from corporate mail: **no record at the `arclightlabs.io` apex changes**.

| Record | Where | Value | Purpose |
|---|---|---|---|
| SES domain identity | SES us-east-1 | `<mail-domain>`, Easy DKIM, RSA 2048 | DKIM `d=<mail-domain>`: **aligned** |
| 3 DKIM CNAMEs | Cloudflare zone `arclightlabs.io`, DNS-only | `<sel>._domainkey.<mail-domain>` → `<sel>.dkim.amazonses.com` | DKIM verification |
| Custom MAIL FROM | SES | `bounce.<mail-domain>`, **behaviour on MX failure: reject message** | Envelope sender under our domain: SPF **aligned** (relaxed) |
| MX | Same zone | `bounce.<mail-domain>` → `10 feedback-smtp.us-east-1.amazonses.com` | Required by custom MAIL FROM |
| SPF | Same zone | `bounce.<mail-domain>` TXT `v=spf1 include:amazonses.com -all` | SPF for the envelope sender |
| DMARC | Same zone | `_dmarc.<mail-domain>` TXT `v=DMARC1; p=reject; adkim=s; aspf=r; rua=mailto:<report mailbox on arclightlabs.io>` | Policy; strict DKIM alignment; reports |
| D12, hosting domain lockdown | Cloudflare zone `arclight-complex.net` | Apex TXT `v=spf1 -all`; `_dmarc` TXT `v=DMARC1; p=reject; sp=reject` | Nobody can send as the hosting domain. Safe: it sends no mail (A5) |

- "Reject message" on MX failure matters: otherwise SES silently falls back to its own
  `amazonses.com` MAIL FROM, and SPF stops aligning.
- **Reports go to a mailbox on `arclightlabs.io`**, the same organisational domain, so no
  cross-domain authorisation record is needed.
- **No null MX on the From subdomain.** RFC 7505 lets receivers reject mail whose From domain
  publishes one. The `Reply-To` handles replies.
- **Configuration set** (neutral name; SES strips it before sending) with reputation metrics
  and a CloudWatch **metrics** destination for sends, deliveries, bounces, complaints and
  rejects; alarms on bounces, complaints and sends above 50 an hour. Per-message outcome in
  the audit trail is the application's own `mail_sent` event with the SES message id. A
  per-message delivery log (an EventBridge destination) is a follow-up. Email feedback
  forwarding is off.
- **Sending path:** the task calls the SESv2 `SendEmail` API through the `email` interface
  endpoint with its task role. No SMTP credentials, no IAM user, no access keys. (SMTP needs
  long-lived IAM user keys, and its endpoint is missing from one of staging's AZs.)
- **Sandbox (D13).** In the sandbox SES delivers only to verified addresses. Verifying the
  recipient's address would make AWS email them a verification request, which is
  unacceptable. Production access must be granted before the real send; staging acceptance
  can use the owner's own verified address. If AWS refuses the request, the fallback is the
  alternative below.
- **Message:** plain text with a minimal HTML alternative; neutral subject and copy; the link
  and its validity. No images, no tracking pixels, click tracking disabled (it would rewrite
  the link through an AWS host).
- **Residual: sender and link are on different domains** (`arclightlabs.io` and
  `arclight-complex.net`), and a first message from a new subdomain containing little but a
  link resembles phishing to some corporate gateways. The token hand-over warns the recipient
  to expect it; P5 shows how it lands in a real mailbox.

**Alternative considered: send through Microsoft 365**, which already serves
`arclightlabs.io` with aligned SPF and DKIM. Not recommended: the task would need internet
egress to Microsoft (against O-017's default), a stored credential, and a tenant-level mail
permission able to send as any corporate mailbox.

Checked against AWS's documentation (the sandbox state and the absence of identities were
also read live):
- SES documents SPF alignment through a custom MAIL FROM as **relaxed only**; `aspf=s` would
  break it. DKIM aligns strictly because the identity verified is the exact From domain.
- AWS's documented SPF value ends `~all`. `-all` is used because nothing but SES sends as
  the bounce subdomain, which must carry exactly one MX and be used for nothing else.
- `Feedback-ID` and `Message-ID` show that the message went through Amazon SES.
- SES reviews an account at a 5 % bounce or 0.1 % complaint rate. At this volume one bounce
  matters, so D14's checks on the address are also a deliverability control.

### Payload release, pinning and the JSON choice

**A release** is an immutable directory in the payload bucket:
- `releases/<release_id>/manifest.json`: every file's path, SHA-256, size and content type;
  the source repository, **commit** and a clean-tree flag; the build command; the CSP for the
  release; the creation time and operator; the owner's sign-off of the lint's review list.
- `releases/<release_id>/files/…`: the files, byte-identical to the build output.
- `release_id` is the first 16 hex characters of the manifest's SHA-256. The full hash is the
  pin.

**Pinning is enforced three times:**
1. The release tool refuses a dirty source tree, an untracked build output, a file outside
   the manifest, and any lint failure (below).
2. The `releases` table, which only administrators can write, holds each release's manifest
   hash. Before serving a release the application fetches its manifest, checks the hash, then
   fetches and hashes every file into a local cache. **Any mismatch: that release is not
   served and an alarm fires.** Other releases and the service's health are unaffected.
3. Each token carries its `manifest_sha256`; a session serves only that release.

**Served material is never retired (A4).**
- A release is immutable. Publishing writes new keys only; the bucket policy requires
  `If-None-Match` on every write, so an existing key cannot be overwritten.
- Ending a share flags the release `inaccessible`. The objects, the manifest and the
  `releases` record stay as they were served, so "what exactly did they get" always has an
  answer: the pinned originals, plus the stamp fields in the audit log, reproduce every
  stamped byte. A reissued token serves the same pinned release.
- **Inaccessible also means unreadable by the task.** The task's read permission depends on
  an object tag that only the operator tool sets when it flags a release. A compromised task
  cannot read material that has been withdrawn. Tags change no bytes and no versions.
- Reissue is two deliberate steps: flag the release `accessible`, issue a token. Both are
  audited.
- The bucket enforces retention: versioning on (and its suspension denied), no lifecycle rule
  (and adding one denied, because lifecycle expiry ignores a bucket policy's delete denial),
  `s3:DeleteObject` and `s3:DeleteObjectVersion` denied to every principal, `prevent_destroy`.
  **Object Lock in governance mode** is the stronger form, as O-015 used for CloudTrail; it is
  chosen at bucket creation, and is recommended with a retention period the owner picks (D10).
- There is no delete command in the tool. An edited site is a **new** release with a new
  hash; the earlier one stays.

**The release linter rejects:** any URL the browser would load from another host (scripts,
styles, fonts, images, tiles, `fetch`/XHR targets, CSS `url()` and `@import`); source maps
and `sourceMappingURL`; absolute local paths; the codename; a reference to a local file that
does not exist; any dotfile; any file the entry page cannot reach; service workers; and a
JSON download whose root already has a `distribution` member.

It **reports for the owner's sign-off**, recorded in the manifest: plain hyperlinks, and
every internal system name, internal record identifier, email address and phone number it
finds. Those are editorial calls, not lint failures.

#### The first payload, as inspected

Read-only inspection, 2026-11-10. Described by category only; the file-level evidence,
counts and hashes are in the owner's private receipt.

- **Shape:** one HTML entry page (a single-page application), 10 scripts, 7 stylesheets, one
  self-hosted font, 28 images, 10 PDFs. 57 files, 40.3 MB; the largest is 10.4 MB.
- **Source control:** the site directory is its own git repository (no remote); its parent
  directories are not repositories. The build output is tracked. **At inspection the tree
  was dirty and changing:** files were edited while it was being read, and the entry page
  references two files that do not exist yet. The pin is that repository's commit plus the
  manifest hash, taken only from a clean tree.
- **Runtime behaviour:** no `fetch`, XHR, WebSocket, service worker, storage, cookie, form,
  iframe or `eval`. No inline script, so `script-src 'self'` holds; one inline `style`
  attribute to move into a stylesheet.
- **No analytics, CDN, remote font or source-map file.** One `sourceMappingURL` comment (in
  the map library) points at a file that is not shipped.

#### Payload findings the owner must see

1. **The data download is not a file (blocks R9 and R10 as built).** The page's download
   button assembles the JSON in the browser from data already embedded in the page, and
   saves it locally. The server never sees a download: it can neither stamp nor log it. A
   "copy" button puts the same unstamped text on the clipboard. **The payload must change:**
   the button becomes a link to `/d/<file>`, and the copy button goes or is accepted as
   unstamped.
2. **D3b: the page's data bundle is the larger disclosure, whichever JSON ships.** Every
   recipient's browser receives one data script of about half a megabyte. Beyond what either
   JSON question covers, it holds:
   - personal and contact data about named individuals, and reproduced source text, which
     the page displays;
   - internal record identifiers, which the page displays;
   - an internal system name, and **several kinds of field the page never displays**:
     working notes, follow-up lists, how sources were obtained, identifiers the page's own
     text says are suppressed, and one image that is shipped but never shown.
   The compact JSON is "least data out the door" only if this bundle is reduced to match.
   Recommended: strip every never-displayed field and every internal name and identifier
   before the first release, and have the owner confirm that the displayed personal data is
   meant to leave.
3. **A second copy elsewhere would make this gate moot.** The site's repository carries a
   configuration file for an external hosting service, pointing it at the build output, and
   that file is inside an existing release archive. The release tool excludes dotfiles. The
   owner should confirm the site is not published anywhere else.
4. **Third-party material.** The site redistributes third-party documents in full, captured
   web pages and commercially sourced imagery carrying a vendor's credit. Redistribution
   rights are the owner's call, not an infrastructure question.
5. **An existing handover archive** beside the site has the same issues plus a guide
   containing absolute local paths, internal system names and commit hashes. It is not part
   of this delivery and should not become one as it stands.

#### D3. Which JSON ships

| | Compact example | Full export |
|---|---|---|
| Size | Under 4 KB on disk; 4.5 KB as the page saves it (same data, pretty-printed) | About 730 KB, plus a 33 KB schema |
| Shape | 10 tables, 14 rows, 66 distinct fields | 17 tables, 1,842 rows, 150 distinct fields |
| Named individuals and their contact data | **None** | **Present, at scale** |
| Precise locations | **None** | Present |
| Source references | Placeholders; the mapping is held privately | Internal record identifiers, and identifiers of a kind the page itself says it suppresses |
| Analyst content | A handful of claims and rationales | Hundreds of assessments, rationales, limitations and qualifications |
| Self-description | Declares itself a proposed sample with export-local identifiers | — |
| Schema | Not needed to read it | Root forbids additional properties; its identifier names the producing organisation; descriptions state modelling and analysis rules |
| URLs, local paths, tool names | None | None in the export and schema. The companion guide has local paths, internal system names and commit hashes |

The compact example is not a row-subset of the full export: it is a re-keyed, hand-picked
extract with its own identifiers. The counts behind each row are in the private receipt.

**Recommendation: ship the compact example.**
- The full export puts personal and contact data about many named people, precise locations,
  internal identifiers and the analysis method into one machine-readable file that leaves
  the platform.
- It re-exposes identifiers the page states are suppressed, so shipping it would contradict
  the page.
- The compact file was built as the sample and says so.
- If the recipient's stated purpose needs the structure, ship the **schema with the compact
  example** (its identifier neutralised, and a `distribution` property added so the stamped
  file still validates). That shows the full shape without the full data.
- The full export only on a specific, stated need, as its own release with its own review.

### Third-party calls and the map

**Flag: the page as built must not ship.** One host is contacted automatically:
`tile.openstreetmap.org`.

- A self-hosted copy of Leaflet 1.9.4 requests raster tiles from it when the recipient opens
  the page's map. One live map with fixed markers; a second map exists in the code but can
  never start.
- No bounds or minimum zoom are set and scroll-zoom is on, so the recipient can pan anywhere.
- **What each tile request tells a third party:** the recipient's IP address, this page's
  origin (as referrer), and the tile coordinates, which reveal the area being looked at.
- No other automatic third-party request exists. User-clicked links: the map's attribution
  links, and link annotations inside one PDF. The referrer policy keeps the page's address
  out of the first; a PDF viewer's behaviour is its own.

| Option | What it takes | Third-party requests | Notes |
|---|---|---|---|
| **1. Static map image (recommended)** | The payload replaces the map with one image showing the markers, made at release time, with the "© OpenStreetMap contributors" credit in its caption. The map library, its stylesheet and the dead second map are deleted | None | Smallest change and smallest surface: about 150 KB of script removed, and the stray source-map comment goes with it. Loses pan and zoom, which fixed markers hardly need |
| 2. Self-hosted tiles | A bounded tile set for the area and a few zoom levels, shipped inside the release and served behind the session; bounds and zoom limits set to match | None | OpenStreetMap's tile servers may not be bulk-downloaded for this, so the tiles must come from our own rendering or a licensed source: a new toolchain for one map |
| 3. Remove the map | Delete the button and the map code | None | The rest of the page's location content remains |

The release linter fails any build that still names a tile host, so the choice cannot be
skipped by accident.

### Stamping

**Specified: embedded metadata in the data download, plus visible marks on pages.**

1. **JSON download (embedded metadata).** The served file is the pinned original with a
   `distribution` object inserted textually as the first member of the root object, so every
   other byte of the original is unchanged. Its fields: the bound address, the token's issue
   time, the session's start time, the release id and manifest hash, and a `distribution_id`.
2. **HTML pages (visible).** A plain-text line inserted before `</body>`: the bound address,
   the issue date and a short reference. It survives screenshots and printing.
3. **PDFs (embedded metadata).** An incremental update adds the same fields to the document
   information dictionary and XMP. The original bytes remain the file's prefix.

- **The stamp is fixed for a session and a file**, not per request: every field is known at
  activation, and `distribution_id` is derived from the session and the path. Repeated and
  ranged requests therefore return identical bytes, and the SHA-256 of the stamped file goes
  into the `download` and `asset_served` audit events.
- **Escaping is by format** (JSON string, HTML text, PDF string, XML). The only variable
  text is the bound address, which the operator entered and the tool validated; nothing a
  visitor typed is ever stamped.
- Metadata can be stripped by anyone who wants to. The audit log, the out-of-band token and
  the visible line are what attribute a leak; the embedded stamp is the cheap, honest label.
  Robust invisible fingerprinting and visible per-page PDF watermarks are out of scope for v1.

Notes from the payload inspection:
- **Precondition:** the page's client-side download becomes a link to `/d/<file>` (payload
  finding 1). Until it does, there is no server-side download to stamp or log.
- The page is a single-page application with one HTML entry page, so the visible line is one
  insertion. Whether it stays visible inside a full-viewport application is checked by eye
  in P5.
- If the schema is ever shipped beside the compact example, the shipped schema must allow
  the `distribution` property.
- **What the stamp does not cover:** the same data remains readable, unstamped, inside the
  page's data script. The stamp marks the file handed over as "the download"; the page
  content is attributed by the audit log and the visible line.
- The PDFs are third-party originals; an incremental update leaves their existing content
  intact.

### Logging and retention

- **Who:** the token's bound address (authoritative) and the submitted name (as typed).
  **When:** UTC timestamps on every event. **Source IP:** `CF-Connecting-IP`, recorded with the
  raw `X-Forwarded-For` chain and `CF-Ray`; trustworthy because only our own zone's traffic
  reaches the logic (D15). **What:** every path served, its size and hash, and every
  download's stamped hash and `distribution_id`.
- **Two copies:** the DynamoDB `audit` table and CloudWatch Logs `/arclight/staging/bandersnatch`
  (structured JSON).
- **D10, retention (recommended):**
  - accounts and their tokens: kept until the owner removes the account (A3);
  - `releases` records and served material: kept (A4);
  - audit events: 2 years in both copies (a leak can surface months later);
  - **failed submissions by strangers:** the audit item, with the address and name they
    typed, expires after 90 days (a shorter TTL on that event class); the CloudWatch line for
    such an event carries the outcome, time and IP only, never the typed address or name;
  - links and sessions: deleted 30 days after expiry by TTL (the audit events are the durable
    record); rate-limit keys after an hour;
  - point-in-time recovery adds up to 35 days to every figure above.
- Accounts hold outside people's names and addresses. Erasing one person's records on request
  touches token and audit records, so it is an owner decision, not an automated command.
- **Operator actions are self-reported in v1:** the tool writes its own audit events, under
  administrator credentials. An independent record (CloudTrail data events on these tables
  and this bucket) is a follow-up, and DR-3 notes one administrator has no MFA.

### Network and egress (O-017)

The service's security group, complete:

| Direction | Peer | Port | Why |
|---|---|---|---|
| Ingress | Staging ALB security group | 8080, 8081 | Traffic and health checks |
| Egress | Endpoint security group (`module.vpc.sg_vpc_endpoints_id`) | 443 | ECR api/dkr, Logs, Secrets Manager (D15's one value, at task start), **SES `email` (new)** |
| Egress | S3 prefix list (`module.vpc.s3_prefix_list_id`) | 443 | ECR layers; the payload bucket |
| Egress | DynamoDB prefix list (**new gateway endpoint**) | 443 | The tables |

- `internet_egress = false`. **No egress to the internet, RDS, Core, ShuttleForge or
  Nerfherder.** The task needs nothing else to start or run (no STS call: the task role's
  credentials come from the container credential endpoint).
- **New VPC endpoints:** the `email` interface endpoint (two AZs, private DNS, the existing
  endpoint group) and a DynamoDB gateway endpoint on the private app route table. Both are
  VPC-wide. Nothing in the account uses SES or DynamoDB from the VPC today.
- **Both new endpoints get an endpoint policy from the start:** this account's principals and
  this account's resources only.
- **No internet egress is not the same as no way out.** The existing S3, Logs, ECR and
  Secrets Manager endpoints carry no endpoint policy, and a prefix-list rule reaches the
  whole service: a compromised task holding an attacker's own AWS credentials could write to
  the attacker's bucket through the S3 gateway. `docs/proposals/nf-egress-lockdown.md:286-293`
  records the same residual for Nerfherder. Policies on the shared endpoints affect every
  staging service, so they are a debt item, not part of this change.
- No ECS Exec, no task-level shell (the O-018 posture). Non-root user, read-only root file
  system, a writable temporary volume for the verified payload cache.

### IAM

- **Task role** `arclight-bandersnatch-task-staging`, every statement conditioned on the
  relevant VPC endpoint (`aws:SourceVpce`), so its credentials are useless elsewhere:
  - `tokens`: `GetItem` and `ConditionCheckItem` only. **The task cannot mint a token, or
    change one's address, release, expiry, limits or revocation.**
  - `token_state`: `GetItem`, `UpdateItem`.
  - `links`, `sessions`: `GetItem`, `PutItem`, `UpdateItem`. `limits`: `UpdateItem`.
  - `releases`: `GetItem`, `Scan`, `ConditionCheckItem`. `audit`: `PutItem` only.
    **Nothing on `accounts`.** No `Query` or `DeleteItem` anywhere.
  - `s3:GetObject` on `<bucket>/releases/*`, only for objects tagged accessible.
  - `ses:SendEmail` on the identity and the configuration set, with `ses:FromAddress` equal
    to the configured sender. (`aws:SourceVpce` on SES is a global condition key and fails
    closed if it does not apply; P3 probes it before anything depends on it.)
- **Execution role** `arclight-bandersnatch-exec-staging`: ECR pull for its repository,
  `logs:CreateLogStream` and `logs:PutLogEvents` on its log group, `GetSecretValue` on D15's
  one secret.
- **These names deliberately fall outside the CI deploy role's `PassRole` patterns**
  (`arclight-ecs-*-<env>`, `arclight-*-task-role-<env>`; `iam-github-oidc/main.tf:132-138`).
  The CI role, and anything dispatched to `deploy-service.yml`, therefore cannot run a task
  as this service and read its tables or bucket. DR-17(c) is not extended to recipient data;
  deploys are manual until the owner decides otherwise.
- **Payload bucket policy:** deny non-TLS; deny `GetObject` to anyone but the task role and
  the named administrator principals; deny `PutObject`, tagging and policy-relevant
  configuration to anyone but the administrator principals, and `PutObject` without
  `If-None-Match` to everyone; **deny deletes to everyone** (A4). Block Public Access on,
  `BucketOwnerEnforced`, SSE-S3, versioning on. No presigned URLs are ever issued.
- **Push role** for the application's repository, `main` only, scoped to its ECR repository
  (an entry in `local.ecr_push_roles`).
- **Operators** manage accounts, issue, revoke, publish and flag releases from their own
  machines with their administrator credentials through the application's tool (DynamoDB,
  S3 and SES read APIs only). No one-off ECS task, so the recipient's address and the token
  hash never sit in `RunTask` overrides in CloudTrail. The token plaintext never reaches AWS.

## Threat model

| # | Threat | Controls | Residual | Test |
|---|---|---|---|---|
| T1 | **Scanner pre-fetch** consumes the link or starts the session | `GET` never changes state; activation is a `POST`; binding cookie or token required (D6); prefetch refused | A sandbox that presses buttons reaches only the access-code form | AT-3, AT-4 |
| T2 | **Token guessing** | 130-bit tokens; per-IP limit; neutral answers; failures per address alarm | None practical | AT-7 |
| T3 | **Mail abuse and lockout**: using the form to mail-bomb someone, or to block a recipient | Mail goes only to the bound address of a valid token; three link emails per token, spent only on accepted sends; no limit that an outsider can trip against a recipient | The recipient can receive up to three link emails | AT-7, AT-8 |
| T4 | **Enumeration through response differences** (status, body, headers, timing, cookies, limits) | Identical status, headers and body; cookie always set; 1.0 s floor with jitter; mail sent after the response; the only refusing limit ignores what was submitted | Statistical timing attacks need many samples, which the per-IP limit caps | AT-1 |
| T5 | **Link forwarding** | Link alone is not enough (binding or token); single use; superseded by the next link; one-hour session | A recipient who forwards both the link and the token shares access; the audit log shows the second IP | AT-4 |
| T6 | **Session theft** | `__Host-` cookie, `HttpOnly`, `Secure`, `SameSite=Lax`; strict CSP; no third-party code; one hour; re-attach retires the old identifier; revocable | Malware on the recipient's machine | AT-11, AT-12 |
| T7 | **Cache leakage** (Cloudflare, browser, proxies) | `no-store` everywhere; cache-bypass rule; no service worker; the page reloads at expiry | Content already on screen can be saved while the session lasts | AT-5b |
| T8 | **Public object URLs** | Private bucket, Block Public Access, restrictive bucket policy, no presigned URLs, the application streams every byte | None | AT-9 |
| T9 | **Indexing** | `X-Robots-Tag`, robots meta, `robots.txt` | A link pasted publicly by the recipient: the page needs a session anyway | AT-5b |
| T10 | **Third-party requests** leaking the recipient's IP or the page's existence | Release linter; CSP with no remote host; `no-transform`; injection and error-reporting headers removed at the edge | A PDF viewer following a link inside a PDF | AT-5b, AT-6 |
| T11 | **Origin bypass** (DR-21: another account's zone reaching the ALB) | The origin secret (D15); every control is in the application | Until D15 or DR-21: forgeable rate-limit keys and logged IPs | AT-19, AT-23 |
| T12 | **Host header and link injection** | Host allowlist; mail links built from configuration | None | AT-16b |
| T13 | **Application compromise** | No internet egress; no path to RDS or any module; IAM limited to its tables, tagged releases and one sender, and bound to the VPC endpoints; endpoint policies on the new endpoints | Data can still leave through the unpoliced shared AWS endpoints, or by mail as our sender (send alarm) | AT-15, AT-17 |
| T14 | **Operator machine or account compromise** | Token plaintext only on the operator's machine and the out-of-band channel | Operator actions are self-reported; one administrator has no MFA (DR-3) | — |
| T15 | **Spoofed mail** phishing the recipient with a lookalike link | `p=reject` on the sending subdomain and (D12) the hosting domain | Lookalike domains we do not own; the corporate apex stays at `p=none` | AT-14 |
| T16 | **CSRF, forced downloads and clickjacking** | `Sec-Fetch-Site` and `Origin` on every `POST` and on downloads; no state change on any `GET`; `frame-ancestors 'none'` | None | AT-12 |
| T17 | **Replay of an activation** | Conditional, idempotent transaction; a consumed link only re-attaches its own live session | None | AT-4 |
| T18 | **Payload tampering or loss** | Three-point pin; no overwrite, no delete, no lifecycle; the task cannot write `releases` or the bucket | An administrator can still publish a wrong release (that is the release review's job) | AT-10 |
| T19 | **Exposure through this public repository** | Neutral names; names, wording and pins out of git and out of CI logs; no control depends on the design being secret | The codename and design are public (see Hygiene) | AT-16, AT-16c |
| T20 | **A lost response burns the only activation** | Re-attach within the hour | A recipient who loses both the cookie and the token needs a reissue | AT-4 |

## Blast radius

**On the platform:**
- **Staging ALB:** one listener certificate and one host rule with an explicit priority. Host
  conditions do not overlap with `core.staging…` or `shuttleforge.staging…`; adding an SNI
  certificate leaves the default certificate unchanged. A mistake here could misroute
  staging traffic, so AT-18 checks Core's path and both existing rules before and after.
- **VPC:** two new VPC-wide endpoints (`email`, DynamoDB gateway), each with a policy. They
  change how SES and DynamoDB API names resolve and route from every staging subnet. No
  staging workload calls either today.
- **IAM:** adding the ECR repository widens the CI deploy role's image-read list by one
  repository, in place.
- **Cluster:** one more service; 0.25 vCPU / 0.5 GB while running.
- **DNS:** new records only. In `arclightlabs.io`, the corporate mail and web domain: six
  records under one new subdomain, nothing at the apex. In `arclight-complex.net`: the page
  record, and D12's two records.
- **Cloudflare zone `arclight-complex.net`:** four rules scoped to one hostname, including
  the zone's only free rate-limiting rule.
- **SES production access** is account-wide: afterwards any principal with `ses:SendEmail`
  can mail anyone. Today only administrators hold that permission.
- **No change** to Core, ShuttleForge, Nerfherder, RDS, the Access application, the prod root
  or the Backstage root.

**If the application is compromised:** the attacker gets the accessible releases (going out
anyway, but to the wrong party), the bound addresses and hashes in its tables, and SES
sending as one address, rate-alarmed. It has no security-group path to any module or to RDS.
It can still move data out through AWS's own service endpoints (see Network).

**What cannot be undone:** content already downloaded by the recipient, and mail already sent.

## Rollback

| Level | Action | Effect | Time |
|---|---|---|---|
| RB0, stop one recipient | Tool: `revoke --token <id>` | Token, links and its sessions refuse at the next request | Seconds |
| RB1, stop one release | Tool: `release set-access --inaccessible` | Every session on that material refuses at the next request; the task loses read access; the material is untouched | Seconds |
| RB2, stop everything | Tool: `revoke --all`; desired count to 0 (CLI, and the Terraform variable) | Every request gets the ALB's 503 | 1 minute |
| RB3, unpublish | Remove the proxied DNS record | The hostname stops resolving to us | Minutes |
| RB4, remove the exposure | Targeted destroy of the service, listener rule, listener certificate, SES identity and configuration set, push role and ECR repository; remove the mail and page records and the Cloudflare rules; the `email` endpoint last | Nothing is reachable or sendable. **The payload bucket, every table and the log group stay** (A3, A4) | One apply |
| RB5, remove the records | Not a rollback: the owner's separate, explicit decision. Export first; lift deletion protection and the bucket's protections by hand | Accounts, tokens, audit and served material are gone | Deliberate |

- RB4 leaves the records and the served material in place at a few cents a month, so removing
  the exposure never costs the history. Tables have deletion protection and the bucket has
  `prevent_destroy`, so Terraform cannot take them by accident.
- **D11:** between shares the service runs at desired count 0, so the default state is RB2.
  Desired count is a Terraform variable (default 0). Starting a share sets it to 1 in the
  local variables file and by CLI; **a staging apply with the variable still at 0 would stop
  a share in progress**, so the share runbook sets the variable first.
- Per-phase rollback is in the plan.

## Public-repository hygiene

- **Out of git, and out of anything this public repository prints:** the recipient's name,
  address and organisation; tokens; payload contents and subject; the payload repository's
  name and path; **the public hostname, the mail subdomain, the mailboxes, and every piece of
  wording the recipient sees** (title, form text, neutral sentences, mail text, cookie names,
  download file name); release ids and manifest hashes, which appear inside every stamped
  download and would tie a recipient's file to this repository.
- **How Terraform gets the names:** variables with no default, marked `sensitive`, from a
  gitignored `terraform.tfvars` locally and from repository **secrets** in
  `terraform-plan.yml`. A repository *variable* is printed in clear in this repository's
  public job logs (verified: run 42885203378 prints `TF_VAR_core_image_tag` and masks
  `TF_VAR_alarm_email`). Neither name may appear in a resource address, a resource name or a
  tag.
- **Why keep them out:** the hostname is in public DNS, but not in Certificate Transparency
  (the wildcard covers it). Publishing it, or any exact phrase from the page or the mail,
  would let anyone, including the recipient, search for it and land on this repository's
  description of what the page is for.
- **What this does not hide:** the parent domains are public here, the hostname can be found
  by DNS guessing or by a mail gateway submitting the link to a URL scanner, and the design
  is public. No control depends on any of that staying secret.
- **The codename in a public repository is acceptable.** "Bandersnatch" names an internal
  design. It must never reach a response, a mail, a cookie, a file name or a header the
  recipient sees; AT-16 searches every response and the received mail for it. Internal AWS
  names (service, tables, log group) may carry it: the recipient never sees them.
- **R1's neutrality applies to the access pages and the mail, not to the payload.** The
  payload is about its subject, and its stamp carries the recipient's own address by design.
  AT-16c checks the access pages, the mail, the headers and the names for the product, the
  modules, the recipient and the subject.
- This document's own detail about the first payload is held to categories. The file-level
  evidence is in the owner's private receipt.

## Cost

About **$15 a month when idle** (the `email` interface endpoint in two AZs, about $14.60) and
about **$24 if the service ran all month** (Fargate 0.25 vCPU / 0.5 GB adds about $9). D11
keeps it near the idle figure. DynamoDB on demand, S3, SES ($0.10 per 1,000 mails), one
secret ($0.40) and logs are cents. The DynamoDB gateway endpoint is free. A one-AZ `email`
endpoint halves the endpoint cost at the price of an AZ dependency; not recommended.

## Observations in passing (not in scope)

Recorded so they are not lost; none is changed by this work. DR-24 in
`docs/PROJECT_STATE.md` points here.

- `podbay.staging.arclight-complex.net` is still a proxied CNAME, though Podbay was removed
  (O-011). It resolves to our ALB's default 404, so it is not a takeover risk.
- The `*.staging` Access application has an Allow policy for a "Cloudflare Login" login
  method. What that admits (members of the account, or any Cloudflare user) was not verified.
- The `arclight-complex.net` zone: minimum TLS 1.0, Always Use HTTPS off, Network Error
  Logging on, Email Address Obfuscation on.
- `arclightlabs.io`'s DMARC is `p=none`: corporate mail is aligned but nothing is enforced.
- `ansanalytics.com`'s SPF does not list Microsoft 365, which receives its mail, and no DKIM
  is published at Microsoft's default selector. Mail sent as that domain from Microsoft 365
  probably fails SPF (inferred from DNS; no message header was examined).
- The staging VPC's interface and gateway endpoints carry no endpoint policies.

## Review record

**Internal review, 2026-11-10** (three independent passes on the first draft, `02c4a93`;
every finding was re-checked against code, live state or documentation before it was
accepted):

| Finding | From | Disposition |
|---|---|---|
| `Referrer-Policy: no-referrer` makes browsers send `Origin: null` on form posts, so the CSRF check would refuse every real submission | security, citations | **Accepted:** `same-origin`, plus `Sec-Fetch-Site`; `null` never accepted |
| Limits that refuse only failed submissions turn the status code into a validity oracle, and let a token holder find the address | security, citations | **Accepted:** only the per-IP limit refuses; the others count and alarm |
| `CF-Connecting-IP` cannot be trusted on DR-21's path | security | **Accepted:** D15 (origin secret); header required; IPv6 by /64; checks before counting |
| The single activation can be burned by a lost response or a double click; release and account state were not activation conditions | security | **Accepted:** re-attach within the hour; idempotent transaction; both states are conditions |
| "No internet egress" was presented as "no way out"; the endpoints carry no policy | security, citations | **Accepted:** residual rewritten; policies on the two new endpoints; shared endpoints registered as debt |
| Repository variables print in public CI logs, which would leak the hostname | citations | **Accepted (verified, run 42885203378):** secrets, `sensitive`, never in a resource address |
| Verbatim page and mail wording, and release hashes, would tie the page to this repository | citations | **Accepted:** removed; described instead; pins stay private |
| A deny-delete bucket policy does not stop lifecycle expiry or overwrites | security | **Accepted:** lifecycle and versioning changes denied; `If-None-Match` required; Object Lock recommended |
| The task could mint tokens (`PutItem`), read withdrawn releases, and be run by the CI deploy role | security, citations | **Accepted:** no `PutItem` on `tokens`; tag-gated reads; role names outside the `PassRole` patterns |
| `/ready` relied on a `Host` comparison; "every accessible release" was not implementable with the stated permissions; one bad release would fail the whole service | security, citations | **Accepted:** health on its own port; `Scan` on `releases`; per-release failure |
| A failed or lost mail spent a link request | security | **Accepted:** spent only on accepted sends |
| A per-request stamp breaks ranged requests and reproducibility | security | **Accepted:** stamp fixed per session and file |
| Cloudflare adds `NEL` / `Report-To` (verified live), may prefetch (Speed Brain), and stops compressing under `no-transform` | security, citations | **Accepted:** headers removed at the edge; prefetch refused; the application compresses |
| A 90-day drop inside a 2-year log group has no mechanism; SES's CloudWatch destination is metrics, not logs | security, citations | **Accepted:** per-class TTL; the log line omits the typed address and name; per-message delivery log is a follow-up |
| Option (b) overstated: Core's vocabulary already has `external_client` and `external_consumer`; D-074 §6 "rules out" was too strong; O-012 does not cover a platform standard | citations | **Accepted:** reworded; the standard goes to Complex as a question |
| Rollback levels reused the requirement ids R1-R4 | citations | **Accepted:** RB0-RB5 |
| Acceptance tests that could not run at their phase, contradicted stamping, or had no discriminating negative | security, citations | **Accepted:** see the plan's table |
| `ansanalytics.com` was never addressed; D14 was not in the brief; no pointer in `PROJECT_STATE.md` | scope | **Accepted:** reuse row; D14 labelled as proposed here; pointer and DR-24 added |
| A null MX on the From subdomain | security | **Declined:** RFC 7505 lets receivers reject mail from such a domain; a `Reply-To` is used instead |
| CloudTrail data events for an independent record of operator actions | security | **Deferred** to the plan's follow-ups: it changes the shared account trail |

Also during drafting, from the owner: A3, A4 and A5, and the offer to extend the Cloudflare
tokens (plan P0).

**Automated review on the pull request, 2026-11-10** (Codex, on `b2d52b0`; both checked
against the text and accepted):

| Finding | Disposition |
|---|---|
| Activation reused submission's checks, including "a link email left", so the link in the last permitted mail could never activate | **Accepted:** activation and session checks are now listed separately and exclude the mail budget; AT-8 tests the third mail's link |
| AT-16 searched every response, including the payload itself, for the payload's subject and the recipient, so a correct release would fail it | **Accepted:** AT-16 is the codename everywhere; AT-16c is product, modules, recipient and subject on the access pages and the mail only |
| (on `50b96cf`) A task killed with mail queued keeps the budget spent, and nothing durable records the pending send | **Accepted:** reservations are durable and one unconfirmed after two minutes no longer counts. The nonce is still never stored |
| (on `f9a9567`) A reservation superseded by a later submission before either mail went out could not be found again | **Accepted:** reservations moved from the link record to the token (`pending_sends`), so one read sees them all; budget updates are versioned |
| (on `f9a9567`) AT-9 required a 404 for another release's session on every path, which fails when two releases share a path | **Accepted:** the test asserts that another release's session never receives this release's bytes |
| (on `cd6b508`) The serving and re-attach checks ignored a session's own revocation | **Accepted:** both check it; `session revoke` marks every identifier and the link; AT-21 tests it |
| (on `cd6b508`) An attribute allowlist on `tokens` would deny the conditional writes it was meant to permit (DynamoDB applies it to attributes a condition reads, and requires the key) | **Accepted:** the token is split into an operator-written grant and a task-written state record; guards are condition checks on the grant inside the transaction |
| (on `50b96cf`) AT-4 required 49 of 50 concurrent clicks to be refused, but the re-attach rule lets bound requests succeed | **Accepted:** AT-4 asserts one activation and one end time; and re-attach now retires the old identifier after ten seconds, so racing responses cannot leave the browser with a dead one |

**External reviews** (codex-1 correctness, codex-2 architecture, hotpants domain): prompts are
prepared; they run on the owner's direction.
