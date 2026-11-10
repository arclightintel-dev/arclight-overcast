# Bandersnatch: gated delivery to a named outside recipient (spec)

Status: **Revision 1, draft for the owner's review. Spec only: nothing is built, applied,
sent or published.** The phased plan and its acceptance tests are in
[bandersnatch-plan.md](bandersnatch-plan.md).

Request: the owner, 2026-11-10 (condensed in "What was asked"). Branch `spec/bandersnatch`,
cut from `main` at `08ec540`. Live read-outs in this document are dated 2026-11-10 and were
read-only.

**This repository is public (DR-14).** This document names no recipient, no recipient
address, no payload subject and no public hostname. Real values live outside git (see
"Public-repository hygiene").

## Decisions for the owner

Each is argued in the section named. D1 comes first because every other answer depends on it.

| # | Decision | Recommendation | Section |
|---|---|---|---|
| **D1** | **Who owns the token, session and audit logic?** (a) a small hosted application in its own private repository, on Overcast's substrate; (b) Core; (c) Cloudflare Access alone | **(a)**, under an O-012-style owner ruling ("hosted application, not a module"), Complex informed | [Ownership](#d1-ownership) |
| D2 | Environment | **Staging**, the only platform environment in v1 | [Environment](#d2-environment) |
| D3 | Which JSON ships | **The compact example.** The full export only on a stated need, and never its companion guide as it stands (evidence below) | [The JSON choice](#d3-which-json-ships) |
| **D3b** | **The page's own data bundle carries more than either JSON** | Before the first release, strip what the page never displays and every internal name and identifier; the owner confirms what remains | [Payload findings](#payload-findings-the-owner-must-see) |
| D4 | The OpenStreetMap tile calls | **A static map image built at release time**, and the map library removed | [Third-party calls](#third-party-calls-and-the-map) |
| D5 | Stamping | **Embedded metadata** in the JSON download, plus a visible line on the served page and metadata in each PDF. Needs the download to become a server file | [Stamping](#stamping) |
| D6 | Mail-scanner and forwarding hardening | The click completes only in the **browser that asked for the link**; any other browser must re-enter the token | [Link and activation](#link-and-activation) |
| D7 | Data store | **DynamoDB** (new, no network path to RDS) over the shared staging RDS | [Data model](#data-model) |
| D8 | Names | Neutral public hostname and sender; **both held out of this repository** | [Hygiene](#public-repository-hygiene) |
| D9 | Token defaults | Expiry 7 days, one activation, three link emails, link valid 24 h | [Tokens](#accounts-and-tokens) |
| D10 | Retention | Accounts, tokens and served releases kept (A3, A4); audit 2 years; unmatched attempts 90 days; links and sessions 30 days after expiry | [Logging](#logging-and-retention) |
| D11 | Uptime | The service runs **only while a token is live**; desired count 0 otherwise | [Rollback](#rollback) |
| D12 | Apex mail lockdown | Publish `p=reject` DMARC and a null SPF on `arclight-complex.net` itself, which sends no mail today | [Mail](#mail-path) |
| D13 | SES production access | **The owner** submits AWS's request (outward-facing); text drafted in the plan | [Mail](#mail-path) |
| D14 | Issuing outside an account's domains | Issue only to a person recorded on the account; an address outside the account's domains needs an explicit override flag | [Tokens](#accounts-and-tokens) |

Already decided by the owner (not reopened here):
- **A1. Activation:** strictly one hour from the click, once. Extending means reissuing.
- **A2. Binding:** a token binds to the exact address it was issued to, not a domain.
- **A3. Accounts** (2026-11-10, during drafting): tokens are tracked under accounts, and an
  account can be assigned domains, organisations and people.
- **A4. Served material is never retired** (same message): a release stays exactly as it was
  served and is only flagged inaccessible, so a token can be reissued against it.

## What was asked

A minimal gated delivery path that serves a static page and a data download to a named
outside recipient. It becomes the platform's standard way to share pages, data or parts of
the platform externally. The first payload is a static entity-profile sample site (HTML, JS,
CSS, images, PDFs) that is still being edited.

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
Tokens, links, sessions, rate limits and an audit trail are application behaviour with domain
nouns and an HTTP API.

**What Overcast does own here:** "Frontend web application deployment (S3 + CloudFront or
Fargate)" (`docs/CHARTER.md:21`) and "All domain management (Cloudflare DNS, ACM certificates,
SSL/TLS configuration)" (l.22). So Overcast hosts it, names it and sends its mail through
infrastructure it provisions; it does not write its request handling.

### Option (a): a small hosted application on Overcast's substrate (recommended)

A new private repository holds the application code, its Dockerfile, its tests and its
operator CLI ("Dockerfiles stay in module repos", `docs/CHARTER.md:41`). Overcast provides
the ECS service, the load-balancer rule, the certificate, DNS, the mail identity, the data
tables, the payload bucket and the egress (everything under [Design](#design)).

The precedent is **O-012**: Backstage is "hosted by Overcast on AWS as a **prototype platform
application**, not a module and not a separate tenant", by owner ruling, with Complex told
and "no D-series decision … required for Overcast to proceed" (`docs/DECISIONS.md:151`,
`:161`). The same shape fits: the owner rules, Overcast records an O-decision, Complex is
informed.

- **For:** the smallest blast radius of the three (its own tables, bucket, mail identity and
  security group, nothing shared with Core's identity plane). It can ship on its own
  cadence. It meets every requirement (see the fit table).
- **Against:** a new repository and a new image to look after. A second set of
  security-sensitive code outside Core's review chain.
- **Trigger to revisit:** when it gains a second payload source, a caller from another
  module, or a need to admit platform principals, it needs a platform home (a D-series
  decision in Complex, module charter, seams). Until then it is a hosted application.
- **A3 sharpens this.** Accounts with organisations, domains and people are a small directory
  of outside parties. That is more domain model, so further from Overcast, and it is the part
  most likely to belong with Core one day. It is kept in its own table, which the serving
  task cannot read, so it can move without touching the serving path.

### Option (b): the logic in Core

Core already owns tokens, identity, OIDC and the scope grant.

- **The admission model does not fit.** D-070 §2: "The Core scope grant is the admission
  decision for a seam operation"; D-073 §1: "one authorization model for every Core-JWT
  caller" (Complex `platform/DECISIONS.md` l.1418, l.1486). An outside recipient proving
  possession of a mailbox plus an out-of-band token is neither a Core principal nor a scope
  grant. Adding that class to Core is a platform decision (identity contract, permission
  vocabulary), not an Overcast or Core implementation detail.
- **It widens the identity plane's public surface.** Every Core hostname sits behind the
  `*.staging` Access application today (live read-out below). An outsider flow needs an
  unauthenticated public path into the service that signs every platform token. A defect in
  the sharing path becomes a defect in the platform's authority.
- **Most of the work is not identity.** Serving a pinned static site, stamping downloads and
  sending mail are not Core's job.
- **For:** one place for credentials, Core's audit and review discipline, Core's existing
  internet egress (O-017 exception).

Not recommended for v1. If Core later adopts external principals, the hosted application
can delegate token checks to Core without changing its public contract.

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

**D-074 §6 also rules it out as the sole control:** "Edge authentication is never the
control. An edge gate (for example Cloudflare Access) is defense in depth only" (Complex
`platform/DECISIONS.md` l.1542). That decision is written for module surfaces, but its
reasoning (the origin must enforce its own check) applies here with more force, because
DR-21 records that a zone from another Cloudflare account can reach the staging ALB and
skip the Access application (`docs/PROJECT_STATE.md:151`).

Option (c) is viable only if the owner relaxes R1, R4, R5, R6, R9, R10 and R11. A3 and A4
(accounts, reissue against kept material) have no counterpart in Access at all.

### Rejected runtimes for option (a)

- **Cloudflare Worker with KV or D1:** application code on a platform Overcast does not run
  today; the CF-01 API token has no Workers permission; logs and audit would live outside
  AWS.
- **CloudFront with Lambda@Edge:** edge functions log to the region of the edge location, and
  a function outside a VPC has internet egress that O-017 cannot constrain.

## D2. Environment

**Staging.** "For v1, staging is production (D-059 §9)" (Complex `platform/DECISIONS.md`
l.1052). The prod root holds only the substrate Backstage runs on, "not a production
environment awaiting apply" (`CLAUDE.md`, O-016); it has no ECS cluster and no database.
Staging has the cluster, the endpoints, the protected CloudTrail (O-015) and the O-017 egress
pattern this needs.

**What that costs.** This would be the **first hostname in the staging VPC that is not behind
the `*.staging` Access application** (live: the Access application covers only
`*.staging.arclight-complex.net`). Backstage is the only other Access-free application in the
account, and it sits in the prod VPC (O-012 D19). An internet-facing application in the
staging VPC must therefore have no network path to anything holding operational material.
That is why D7 recommends DynamoDB over the shared RDS, and why the design gives the service
no path to Core, ShuttleForge, Nerfherder or RDS (see [Network](#network-and-egress-o-017)).

D-059 §8 still applies: no automatic deploys; the owner's go per release.

## Verified reuse

Read 2026-11-10 from code at `08ec540` and live, read-only.

| Component | Verified state | Evidence | Use here |
|---|---|---|---|
| Staging ALB `arclight-staging` | Internet-facing; 443 with `ELBSecurityPolicy-TLS13-1-2-2021-06`; 80 redirects to 443; default action 404 "Not Found" | `terraform/modules/alb/main.tf:91-121`; live `describe-listeners`, `describe-rules` | Host the page behind one new host-header rule |
| ALB rules | Live priorities: ShuttleForge 2, Core 10, default. The module sets no priority (`alb/main.tf:157-172`); Core sits at 10 by hand (`docs/PROJECT_STATE.md:162-165`, `:181`) | live `describe-rules` | Our rule lives in the root with an explicit priority (Backstage pattern, `terraform/envs/backstage/alb.tf:30-44`) |
| ALB ingress | Cloudflare's 15 IPv4 and 7 IPv6 ranges only (O-005) | `terraform/envs/staging/main.tf:46-71`, `alb/main.tf:13-55` | Unchanged. DR-21 applies |
| ALB access logs | Off | live `access_logs.s3.enabled false`; no `access_logs` in `alb/main.tf:72-85` | Nothing secret may sit in a URL that a later change could log; see [Link](#link-and-activation) |
| ALB XFF | `append`; invalid header fields not dropped | live attributes | Client IP comes from `CF-Connecting-IP` (see Logging) |
| Staging 443 certificate | `*.staging.arclight-complex.net` only; **no SNI certificates** | live `describe-listener-certificates`; no `aws_lb_listener_certificate` in the repo | Attach a second certificate |
| First-level wildcard | `*.arclight-complex.net` + apex, ISSUED, AMAZON_ISSUED, renewal eligible; in use by the prod ALB and Backstage's CloudFront; requested out of band, read through data sources (`terraform/envs/prod/main.tf:40-44`, `terraform/envs/backstage/downloads.tf:11-15`) | live `acm describe-certificate` | Attach to the staging 443 listener as SNI. **No new certificate, so no new Certificate Transparency entry names the page** |
| Fargate module | `internet_egress` default false (O-017); creates no target group or listener rule; registers Cloud Map | `terraform/modules/ecs-service-fargate/variables.tf:96-102`, `main.tf:21-68` | The service, with `internet_egress = false` |
| Interface endpoints (staging) | `ecr.api`, `ecr.dkr`, `logs`, `secretsmanager`; S3 gateway on the private route tables | live `describe-vpc-endpoints`; `terraform/modules/vpc/main.tf:152-219` | Reuse ECR, Logs, S3 |
| SES API endpoint | `com.amazonaws.us-east-1.email`: all six AZs; private DNS covers `email.us-east-1.amazonaws.com` and `email.us-east-1.api.aws`; endpoint policies supported. `email-smtp` is **not offered in us-east-1b**, one of staging's two AZs | live `describe-vpc-endpoint-services` | Add `email` to `extra_interface_endpoints` (`terraform/envs/staging/main.tf:83-85`). API, not SMTP |
| Endpoint security group | Inline ingress 443 from the private app subnet CIDRs | `terraform/modules/vpc/main.tf:136-150` | No change; our group adds egress to it (NF pattern, `terraform/envs/staging/nerfherder.tf:49-67`) |
| DynamoDB | Only `arclight-terraform-locks` exists; no DynamoDB endpoint in the VPC | live `list-tables`, `describe-vpc-endpoints` | New tables and a gateway endpoint (D7) |
| SES | **Sandbox** (`ProductionAccessEnabled: false`, 200 per 24 h, 1 per second); **no identities**; account suppression list on for bounces and complaints | live `sesv2 get-account`, `list-email-identities` | New domain identity; production access is an owner step (D13) |
| Mail DNS for `arclight-complex.net` | **No MX, no TXT (no SPF), no `_dmarc`**, no DKIM at common selectors; Email Routing off | live public DNS (1.1.1.1); Cloudflare API | All mail records are new. The domain sends no mail today |
| Cloudflare zone | Full (strict); Universal SSL covers `*.arclight-complex.net`; 9 records, none for mail | Cloudflare API, read-only token | One proxied record for the page, DNS-only records for mail |
| Zone settings that rewrite content | **Email Address Obfuscation on**; Automatic HTTPS Rewrites on; Rocket Loader off; Always Online off; browser cache TTL 14 400 s; cache level aggressive; **minimum TLS 1.0**; Always Use HTTPS off | Cloudflare API, read-only token | A configuration rule for the hostname (see [Edge](#edge-cloudflare)) |
| Web Analytics, Zaraz | **Unreadable** with the read-only token (error 10000). Web Analytics is on by default for Free zones since 2025-10-15 (Cloudflare's documentation) | Cloudflare API | Turned off for the hostname and blocked by `no-transform`; AT-6 proves it |
| Cache and rate-limit rules | None exist (phase entrypoints absent) | Cloudflare API | One cache rule and one configuration rule, scoped to the hostname; no rate rule |
| Access | Applications: `*.staging.arclight-complex.net` (24 h session; policies: one address, "Cloudflare Login" login method, the `staging-automation` service token) and a Pages preview app. IdPs: one-time PIN, Cloudflare. No Entra | Cloudflare API, read-only token | **Not used.** The page hostname must not match any Access application |
| Deploy workflow | `deploy-service.yml` dispatches `core` and `shuttleforge` only; verifies the digest, then `/ready` through the public hostname with Access headers | `.github/workflows/deploy-service.yml:7-13`, `:209-257` | Manual deploys for v1; extending the workflow is a later change |
| CI plan | Supplies `TF_VAR_core_image_tag` and `TF_VAR_alarm_email` only; a new variable without a default fails the plan | `.github/workflows/terraform-plan.yml:35-37`, `:67` | Hostnames come in as repository variables |
| Push roles | Hard-coded list in `iam-github-oidc`; staging is its only caller | `terraform/modules/iam-github-oidc/main.tf:289-343`; `terraform/envs/staging/main.tf:161` | One entry for the new repository |
| Hosted-application pattern | Backstage: own root, own target group, explicit listener priority, standalone ALB egress rule | `terraform/envs/backstage/alb.tf:30-44`, `network.tf:86-95` | Same shape, inside the staging root |

Not reused, deliberately:
- **RDS** (see D7).
- **Secrets Manager.** The design needs no secret: DynamoDB and SES are reached with the task
  role, and every token, nonce and session identifier is stored only as a hash.
- **`dbbootstrap`.** Not needed without RDS (and DR-17 makes its image hard to change).

## Design

```
recipient ──HTTPS──▶ Cloudflare (proxied, cache bypass, no injection)
                        │  Full (strict)
                        ▼
                 staging ALB :443  ── SNI *.arclight-complex.net ── rule: Host = <page-host>
                        │  8080
                        ▼
          bandersnatch task (Fargate, private app subnets, no internet egress)
             │ DynamoDB (gateway)   │ S3 payload (gateway)   │ SES API (interface)   │ Logs, ECR (interface)
```

### Edge (Cloudflare)

- One **proxied** record `<page-host>` → the staging ALB's DNS name. A **first-level** name
  under `arclight-complex.net`, so it falls outside the `*.staging` Access application and is
  covered by Universal SSL. It must match no Access application (acceptance AT-18).
- The two rules below need cache-rule and configuration-rule permission, which the
  Terraform token may lack; if so the owner creates them in the dashboard. They are the
  second layer either way: the origin's `no-store, no-transform` is the first.
- **Cache rule:** bypass cache for the hostname, browser TTL "respect origin". The origin also
  sends `no-store`, which Cloudflare's edge never caches. The rule is belt and braces for two
  documented defaults: `.pdf` is on the cached-by-default list, and the zone's 4-hour Browser
  Cache TTL overrides a lower origin `max-age` (its effect on `no-store` is undocumented, so
  AT-5b reads the header the browser actually receives).
- **Configuration rule for the hostname:**
  - Email Address Obfuscation **off**. It is on for the zone, rewrites every address in HTML
    and injects a decoder script, which would mangle the visible stamp.
  - **Real User Monitoring off.** Cloudflare Web Analytics has been on by default for Free
    zones since 2025-10-15 and injects a beacon loaded from `static.cloudflareinsights.com`,
    a **third-party request (R8)**. The read-only token cannot read the zone's Web Analytics
    or Zaraz state (error 10000), so this is treated as on until proven off.
  - Automatic HTTPS Rewrites off, Rocket Loader off.
- **`Cache-Control: no-store, no-transform`** from the origin. `no-transform` independently
  stops both the obfuscation and the beacon injection, so R8 does not rest on a dashboard
  setting.
- **HTTPS only.** Always Use HTTPS is zone-wide and off, and Full (strict) forwards a
  plain-HTTP request to the origin over HTTP. The ALB's port-80 listener already answers 301
  to HTTPS, mailed links are always `https`, and the application sends HSTS.
- **No Cloudflare rate-limiting rule.** The Free plan gives the zone one rule (per IP, a
  10-second window, a 10-second block). It would add little, and the application's limits
  must be authoritative anyway (DR-21).
- **Minimum TLS** is zone-wide (1.0 today). Raising it to 1.2 is July's pending zone
  hardening: an observation here, not part of this change.

### Origin (ALB)

- `aws_lb_listener_certificate`: the existing `*.arclight-complex.net` certificate (data
  source, as prod and Backstage read it) on the staging 443 listener. The listener's default
  certificate stays `*.staging`.
- A target group (`ip`, HTTP 8080, health check `/ready`) and **one listener rule with an
  explicit priority** (20, which is free: the live rules sit at 2 and 10), condition
  `Host = <page-host>` only. Order does not matter, because the three host conditions are
  disjoint.
- A standalone ALB security-group egress rule to the service on 8080 (Backstage pattern).
- The public route set is exactly `/`, `/a/*`, `/v/*`, `/d/*` and `/robots.txt`. `/ready`
  answers only when the `Host` header is not `<page-host>` (the ALB's own health checks
  address the target by IP), so it is not reachable from the internet. Everything else is
  the neutral 404.

### Application behaviour

Normative for the application. When the application's repository exists, this section moves
there and this document keeps only the interface (ports, health path, egress, IAM, names).
Overcast must not become a shadow spec of someone else's code (`docs/CHARTER.md:43`).

**Common to every response:**
- `Cache-Control: no-store, no-transform`, `Pragma: no-cache`, `Expires: 0`.
- `X-Robots-Tag: noindex, nofollow, noarchive, nosnippet`; HTML also carries
  `<meta name="robots" content="noindex,nofollow">`; `/robots.txt` disallows everything.
- `Referrer-Policy: no-referrer`; `X-Content-Type-Options: nosniff`;
  `Strict-Transport-Security: max-age=31536000`; `Permissions-Policy` denying every feature;
  `Cross-Origin-Opener-Policy: same-origin`; `Cross-Origin-Resource-Policy: same-origin`.
- `Content-Security-Policy`: `default-src 'none'; frame-ancestors 'none'; base-uri 'none';
  form-action 'self'` plus the narrow `'self'` grants each page type needs. Payload pages
  get a per-release CSP computed by the release tool, with no host outside `'self'` and
  `connect-src 'none'` (the first payload needs `script-src 'self'`, no inline script, and
  one inline style to be moved into a stylesheet).
- Neutral titles and copy (the title is a single neutral word; the owner picks it). No
  codename, product, module or recipient term anywhere in a response (AT-16).
- Requests whose `Host` is not `<page-host>` (other than `/ready`) get 404. Absolute URLs
  in mail are built from configuration, never from the request.

#### Landing page and submission

- `GET /`: one self-contained HTML response (logo inline, CSS inline under a hash, no
  script). Three fields: token, name, email. One button.
- `POST /` (form): checks `Origin` equals `https://<page-host>`; otherwise 403 (independent of
  the details, so it reveals nothing).
- **Normalisation:** email trimmed and lower-cased (no dot or plus folding); token stripped of
  spaces and hyphens and upper-cased (Crockford base32: `O`→`0`, `I`/`L`→`1`); name trimmed and
  capped at 200 characters. **The name is recorded, not validated.**
- **Rate limits:**
  - **Per IP** (from `CF-Connecting-IP`): 5 per 15 minutes and 20 per day, checked **before**
    anything else. Over the limit: 429 with a fixed neutral body, whatever was submitted.
  - **Per submitted address** (5 per hour) and **across the service** (100 per hour, which
    also alarms): these count and refuse **failed** submissions only. A correct token and
    address always get through, bounded by the token's own caps. Otherwise anyone who knew a
    recipient's address could lock them out by hammering it.
  - A 429 therefore says nothing about whether an address is known: every failed submission
    for any address, real or not, is treated alike.
- **Validity:** a token whose hash exists, is not revoked, is not expired, is bound to the
  submitted address, has an activation left and has a link email left.
- **If valid** (one DynamoDB transaction): count the link request, record a new link as the
  token's only current link (older unconsumed links are superseded), write the audit event.
  The link email is handed to an in-process queue and sent after the response.
- **Always:** a 200 with a fixed body ("If the details are correct, a link is on its way. It
  is valid for 24 hours."), a fresh random **binding cookie** `__Host-b` (32 random bytes,
  `Secure; HttpOnly; SameSite=Strict; Path=/; Max-Age=86400`), and an audit event with the
  internal outcome.
- **Equal responses:** status, headers and body are byte-identical apart from the cookie value
  (same length). Every response to a submission is held to a **fixed floor of 1.0 s plus
  0-200 ms of jitter** from receipt, so database work and mail hand-off cannot be timed. Mail
  is sent after the response, never inside it.

#### Link and activation

- The link is `https://<page-host>/a/<nonce>`, where the nonce is 32 random bytes (base64url).
  Only `SHA-256(nonce)` is stored, as is `SHA-256(binding cookie)`.
- **`GET /a/<nonce>` never changes state.** It returns the same static page for any nonce,
  valid or not: one button, "Start". It writes an audit `link_opened` event (IP, user agent)
  when the nonce matches, which is how scanner pre-fetches show up. `HEAD` and any other
  method are treated the same way.
- **`POST /a/<nonce>`** (the click), after the `Origin` check and rate limits, starts a
  session when all hold:
  - the nonce is the token's current link, unconsumed and less than 24 h old;
  - the token is not revoked or expired and has an activation left;
  - **binding (D6):** the request carries the `__Host-b` cookie whose hash was recorded with
    this link, **or** the form carries the token itself.
- Without the binding cookie the click page answers with one field: "Enter your access code
  to continue". So the recipient who requests and clicks in the same browser just clicks; on
  another device they type the token once more.
- On success, one DynamoDB transaction marks the link consumed, counts the activation
  (conditional on one being left), creates the session and writes the audit event. The
  response sets `__Host-s` (32 random bytes; `Secure; HttpOnly; SameSite=Lax; Path=/;
  Max-Age=3600`) and redirects (303) to `/v/`.
- **Why `Lax` for the session and `Strict` for the binding:** the binding cookie is only ever
  needed on a `POST` from our own page. The session cookie must survive the recipient
  clicking the mailed link a second time from webmail (a cross-site navigation): with a live
  session, `GET /` and `GET /a/*` redirect to `/v/` instead of stranding them on a spent
  link. `Lax` sends the cookie only on top-level `GET`s, which change nothing here.
- Anything else: one neutral page, "This link can no longer be used. Request a new one from
  the start page."

Why D6 rather than a bare click:
- Some mail-security products render links in a sandbox and press buttons. A bare-click
  design would then start the recipient's only session inside the scanner, burning the
  activation and handing the scanner a live cookie for an hour.
- The binding cookie exists only in the browser that submitted the form, and the token only
  in the recipient's head or notes. A scanner, or anyone the email is forwarded to, has
  neither.
- The cost is one extra field when the recipient changes device between asking and clicking.

The nonce sits in the path, not the fragment: some link-rewriting gateways mishandle
fragments. The application never logs it, `Referrer-Policy: no-referrer` keeps it out of
`Referer`, and ALB access logs are off; if they are ever turned on, the `/a/` path must be
excluded or the nonce treated as spent.

#### Session

- Every `/v/*` and `/d/*` request needs a session whose hash exists, whose `expires_at`
  (start + 3600 s, fixed) is in the future, and whose token and session are not revoked.
  The token is re-read on every request, so revocation is immediate.
- No sliding expiry, no refresh, no second session from the same link. A1: extension means a
  new token.
- No valid session: the neutral 404 for every path, so the asset tree cannot be probed.
- `/v/<path>` serves only paths listed in the pinned release manifest, with the manifest's
  content type. HTML pages carry the visible stamp (see [Stamping](#stamping)).
- `/d/<file>` serves the stamped data download with `Content-Disposition: attachment` and a
  neutral file name.
- The client IP and user agent are recorded at activation and on every request. **IP
  changes are logged, not enforced** (recipients on mobile networks change address); the
  one-hour bound and revocation contain a stolen cookie instead.

#### Accounts and tokens

**Accounts (A3).** An account is the unit the owner tracks sharing by. It can be assigned
any number of **organisations**, **domains** and **people** (a name and an address each).
Every token is issued under exactly one account, to one person on it. An account answers
"what have we shared with them, who opened it, and when": its tokens, their sessions and
downloads, and the releases involved.

- Accounts are **records for tracking, not credentials**. A domain on an account admits
  nobody (A2: a token binds to one exact address).
- **D14.** The issuing tool refuses an address that is not a person on the account. If the
  address's domain is not one of the account's domains it asks for an explicit override, so a
  mistyped or personal address is caught before a token exists.
- An account can be **suspended**: every token under it refuses at the next request.
- Account data identifies outside people. It lives only in the `accounts` table, which the
  serving task cannot read, and never in git.

**Tokens.**
- 130 random bits as 26 Crockford base32 characters, shown in groups of five or six. The
  plaintext is generated on the operator's machine, shown once, and given to the recipient
  **through a different channel from the email** (phone, Signal, in person). Only
  `SHA-256(token)` is stored. 130 random bits need no pepper: there is nothing to brute-force
  offline.
- Fields: account, bound address (normalised), release, issued at and by, expires at (default
  7 days), `max_activations` (default and recommended **1**, A1), `max_link_requests`
  (default 3), revoked at, by and why.
- `max_activations` above 1 means separate one-hour sessions, never a longer one. The owner
  may prefer to fix it at 1 in code for v1 (D9).
- **Reissue (A4)** is a new token under the same account for the same release. The old token's
  record stays, so the account shows both. Token records are kept, not deleted: they hold a
  hash, not the token.
- The security model is **two factors held by the recipient**: the token (out-of-band
  channel) and control of the mailbox. Either alone starts nothing.

### Data model

**D7: DynamoDB, recommended.** Seven on-demand tables, point-in-time recovery on, deletion
protection on, AWS-owned encryption.

| Table | Key | Attributes | Kept |
|---|---|---|---|
| `accounts` | `account_id` + `item` (`META`, `ORG#…`, `DOMAIN#…`, `PERSON#<address>`) | label, state (`active`, `suspended`), notes; per assignment: who added it and when | Until the owner removes the account |
| `releases` | `release_id` | `manifest_sha256`, **`access`** (`accessible`, `inaccessible`), source repository and commit, published at and by, access changes (at, by, why) | **Always** (A4) |
| `tokens` | `token_hash`; index on `account_id` | `token_id`, `account_id`, `email`, `release_id`, `manifest_sha256`, `issued_at`, `issued_by`, `expires_at`, `max_activations`, `activations_used`, `max_link_requests`, `link_requests_used`, `current_link_hash`, `account_suspended`, `revoked_at`, `revoked_by`, `revoke_reason` | With the account (A3) |
| `links` | `nonce_hash` | `token_hash`, `binding_hash`, `created_at`, `expires_at`, `consumed_at` | TTL: `expires_at` + 30 d |
| `sessions` | `session_hash` | `token_hash`, `nonce_hash`, `started_at`, `expires_at`, `ip`, `user_agent`, `revoked_at`, `distribution_id` | TTL: `expires_at` + 30 d |
| `limits` | `key` (`ip#…`, `email#…`, `global#…` with the window) | `count` | TTL: window end + 1 h |
| `audit` | `event_id` (128 random bits); index on `account_id` | `at`, `event`, `outcome`, `account_id`, `token_id`, `session_id`, `release_id`, `manifest_sha256`, `ip`, `cf_ray`, `user_agent`, `submitted_email`, `submitted_name`, `path`, `bytes`, `sha256`, `distribution_id`, `ses_message_id` | TTL per D10 |

- **The serving task reads `releases` and cannot write it; it has no access to `accounts`.**
  Suspending an account is the operator tool stamping `account_suspended` on each of the
  account's tokens, so the request path needs one token read and one release read.
- **A release's `access` flag is checked on every request.** Flagging a release inaccessible
  stops every session on it at the next request and changes nothing in the bucket.
- Supersession costs no extra write: activation requires `nonce_hash == tokens.current_link_hash`.
- Single use and counts are `ConditionExpression`s inside `TransactWriteItems`, so two
  concurrent clicks cannot both start a session.
- **The audit table is append-only by IAM:** the task role may only `PutItem` there (no get,
  query, scan, update or delete), event keys are random, and every event is also written to
  CloudWatch Logs, which the task cannot delete from.
- Audit events: `submit`, `rate_limited`, `mail_queued`, `mail_sent`, `mail_failed`,
  `link_opened`, `activation_refused`, `session_started`, `asset_served`, `download`,
  `session_ended`, and the operator events `account_created`, `account_changed`,
  `token_issued`, `token_revoked`, `session_revoked`, `release_published`,
  `release_access_changed`.
- Tokens, nonces and session identifiers are never stored or logged in plaintext. Logs carry
  `token_id` and `session_id` (random, non-secret identifiers) instead.
- **Tracking view:** the operator tool's `report --account <id>` joins the account, its
  tokens and its audit events: who was issued what, which links were opened and from where,
  each session's start and end, each file served and each stamped download.

**Why not the staging RDS (the reuse option):**
- An internet-facing task would get a network path (5432) to the Postgres server that holds
  Core's, ShuttleForge's and Nerfherder's databases. A server-side Postgres flaw would then be
  one hop from the public internet.
- It needs a new `dbbootstrap` mode (an image change; DR-17(a): CI cannot push it), three
  secret shells, a migration task family and an app role.
- Postgres grants can make the audit table insert-only, but an owner-role migration can undo
  that; DynamoDB's IAM boundary is outside the application's reach.
- RDS would give SQL for investigations. With one recipient per hour the audit table is
  small enough to export and query offline.

### Mail path

**Sender.** A dedicated subdomain `<mail-domain>` of `arclight-complex.net` (for example a
neutral word), with a no-reply address and a neutral display name. A subdomain keeps this
sender's reputation and policy separate from anything the apex may send later.

| Record | Where | Value | Purpose |
|---|---|---|---|
| SES domain identity | SES us-east-1 | `<mail-domain>`, Easy DKIM, RSA 2048 | DKIM `d=<mail-domain>`: **aligned** |
| 3 DKIM CNAMEs | Cloudflare, DNS-only | `<sel>._domainkey.<mail-domain>` → `<sel>.dkim.amazonses.com` | DKIM verification |
| Custom MAIL FROM | SES | `bounce.<mail-domain>`, **behaviour on MX failure: reject message** | Envelope sender under our domain: SPF **aligned** (relaxed) |
| MX | Cloudflare | `bounce.<mail-domain>` → `10 feedback-smtp.us-east-1.amazonses.com` | Required by custom MAIL FROM |
| SPF | Cloudflare | `bounce.<mail-domain>` TXT `v=spf1 include:amazonses.com -all` | SPF for the envelope sender |
| DMARC | Cloudflare | `_dmarc.<mail-domain>` TXT `v=DMARC1; p=reject; adkim=s; aspf=r; pct=100` | Policy; strict DKIM alignment |
| D12, apex lockdown | Cloudflare | `arclight-complex.net` TXT `v=spf1 -all`; `_dmarc.arclight-complex.net` TXT `v=DMARC1; p=reject; sp=reject; adkim=s; aspf=s` | Nobody can send as the apex or an unlisted subdomain. Safe: the domain sends no mail today |

- "Reject message" on MX failure matters: otherwise SES silently falls back to its own
  `amazonses.com` MAIL FROM, and SPF stops aligning.
- No `rua` reporting address in v1: the domain has no mailbox, and an external reporting
  address needs an authorisation record in the receiving domain. Alignment is proven from
  received headers (AT-14). Reporting is a follow-up.
- **Configuration set** (neutral name) with reputation metrics and a CloudWatch event
  destination for sends, deliveries, bounces, complaints and rejects; alarms on bounces,
  complaints and sends above 50 per hour.
- **Sending path:** the task calls the SESv2 `SendEmail` API through the `email` interface
  endpoint with its task role. No SMTP credentials, no IAM user, no access keys.
- **Sandbox (D13).** In the sandbox SES delivers only to verified addresses. Verifying the
  recipient's address would make AWS email them a verification request, which is
  unacceptable. Production access must be granted before the real send; staging acceptance
  can use the owner's own verified address meanwhile.
- **Message:** plain text with a minimal HTML alternative; neutral subject and copy; the link,
  its 24-hour validity, and "If you did not ask for this, ignore it". No images, no tracking
  pixels, no click tracking (SES click tracking is off: it would rewrite the link through an
  AWS host).

Checked against AWS's documentation and the live account, 2026-11-10:
- SES documents SPF alignment through a custom MAIL FROM as **relaxed only**; `aspf=s` would
  break it. Hence `aspf=r` above. DKIM aligns strictly because the identity verified is the
  exact From domain.
- AWS's documented SPF value ends `~all`. `-all` is used here because nothing but SES sends
  as the bounce subdomain.
- The MAIL FROM subdomain must carry exactly one MX and be used for nothing else.
- SES strips its configuration-set header before sending, so that name never reaches the
  recipient. `Feedback-ID` and `Message-ID` do show that the message went through Amazon SES.
- With no event destination SES mails bounce notices to the From address, which has no
  mailbox here. Hence the configuration set's event destination, with email feedback
  forwarding off.
- SMTP is not an option: it needs long-lived IAM user keys, and the `email-smtp` endpoint is
  not offered in one of staging's two AZs.
- Account health: SES reviews an account at a 5 % bounce or 0.1 % complaint rate. At this
  volume one bounce matters, so D14's check on the address is also a deliverability control.

### Payload release, pinning and the JSON choice

**A release** is an immutable directory in the payload bucket:
- `releases/<release_id>/manifest.json`: every file's path, SHA-256, size and content type;
  the source repository, **commit** and a clean-tree flag; the build command; the CSP for the
  release; the creation time and operator.
- `releases/<release_id>/files/…`: the files, byte-identical to the build output.
- `release_id` is the first 16 hex characters of the manifest's SHA-256. The full hash is the
  pin.

**Pinning is enforced three times:**
1. The release tool refuses a dirty source tree, an untracked build output, a file outside
   the manifest, and any lint failure (below).
2. The `releases` table, which only administrators can write, holds each release's manifest
   hash. Before serving a release the application fetches its manifest, checks the hash, then
   fetches and hashes every file. **Any mismatch: that release is not served, `/ready` fails
   and an alarm fires.**
3. Each token carries its `manifest_sha256`; a session serves only that release.

**Served material is never retired (A4).**
- A release is immutable. Publishing writes new keys only and never overwrites one.
- Ending a share flags the release `inaccessible`. The objects, the manifest and the
  `releases` record stay as they were served, so "what exactly did they get" always has a
  byte-exact answer, and a reissued token serves the same bytes.
- Reissue is two deliberate steps: flag the release `accessible`, issue a token. Both are
  audited.
- The bucket enforces it: versioning on, no expiry rule, `prevent_destroy`, and a bucket
  policy that denies `s3:DeleteObject` and `s3:DeleteObjectVersion` to every principal. There
  is no delete command in the tool. Removing a release means the owner editing that policy
  first.
- An edited site is a **new** release with a new hash. The earlier one stays.

**The release linter rejects:** any `http:`/`https:`/protocol-relative URL that the browser
would load (scripts, styles, fonts, images, tiles, `fetch`/XHR targets, CSS `url()` and
`@import`), plain hyperlinks excepted and listed for review; source maps and
`sourceMappingURL`; absolute local paths; denylisted terms (codename, recipient identifiers
supplied at release time, platform module names); service workers.

It also rejects a reference to a local file that does not exist, any dotfile, and any file
the build's entry page cannot reach. It **reports for the owner's sign-off**, recorded in the
manifest, every internal system name, internal record identifier, email address and phone
number it finds: those are editorial calls, not lint failures.

#### The first payload, as inspected

Read-only inspection, 2026-11-10. Described by category only; the file-level evidence is in
the owner's private receipt.

- **Shape:** one HTML entry page (a single-page application), 10 scripts, 7 stylesheets, one
  self-hosted font, 27 images, 10 PDFs (89 pages). 57 files, 40.3 MB; the largest is 10.4 MB.
- **Source control:** the site directory is its own git repository (no remote, four commits);
  its parent directories are not repositories. The build output is tracked. **At inspection
  the tree was dirty and changing:** three files were edited while it was being read, and the
  entry page now references a script and a stylesheet that do not exist yet. The pin is
  therefore that repository's commit plus the manifest hash, taken only from a clean tree.
- **Runtime behaviour:** no `fetch`, XHR, WebSocket, service worker, storage, cookie, form,
  iframe or `eval`. No inline script, so `script-src 'self'` holds; one inline `style`
  attribute.
- **No analytics, CDN, remote font or source map file.** One `sourceMappingURL` comment (in
  the map library) points at a file that is not shipped.

#### Payload findings the owner must see

1. **The data download is not a file (blocks R9 and R10 as built).** The page's download
   button assembles the JSON in the browser from data already embedded in the page's data
   script, and saves it locally. The server never sees a download: it can neither stamp nor
   log it. A "copy" button puts the same unstamped text on the clipboard. **The payload must
   change:** the button becomes a link to `/d/<file>`, and the copy button goes or is accepted
   as unstamped.
2. **D3b: the page's data bundle is the larger disclosure, whichever JSON ships.** Every
   recipient's browser receives one 532 KB data script. It contains, by category:
   - contact details for several dozen named individuals (shown in one of the page's tabs);
   - reproduced source documents containing email addresses (shown);
   - several hundred internal record identifiers (shown in evidence notes);
   - an internal system name in values the page never displays;
   - **fields the page never displays at all:** methodology notes, a prioritised list of
     analyst follow-ups, how each source was retrieved, gap lists, source identifiers the
     page's own text says are suppressed, image hashes and crop boxes, and one image that is
     shipped but never shown.
   The compact JSON is "least data out the door" only if this bundle is reduced to match.
   Recommended: strip every never-displayed field and every internal name and identifier
   before the first release, and have the owner confirm the displayed contact data is meant
   to leave.
3. **A second copy elsewhere would make this gate moot.** The site's repository carries a
   configuration file for an external hosting service, pointing it at the build output, and
   that file is inside the existing release archive. The release tool excludes dotfiles. The
   owner should confirm the site is not published anywhere else.
4. **Third-party material.** The site redistributes third-party documents in full, captured
   news pages and commercially sourced imagery carrying a vendor's copyright credit.
   Redistribution rights are the owner's call, not an infrastructure question.
5. **An existing handover archive** beside the site has the same issues plus a guide
   containing absolute local paths, internal system names and commit hashes. It is not part
   of this delivery and should not become one as it stands.

#### D3. Which JSON ships

| | Compact example | Full export |
|---|---|---|
| Size | 3.7 KB on disk; 4.5 KB as the page saves it (same data, pretty-printed) | 733 KB, plus a 33 KB schema |
| Shape | 10 tables, 14 rows, 66 distinct fields | 17 tables, 1,842 rows, 150 distinct fields |
| Named individuals | **0** | 3 person records, 42 contributor names, 60 names attached to contact observations |
| Contact data | **0** | 76 phone numbers, 46 of them mobile; 266 dated contact observations |
| Locations | **0** | 2, with full-precision coordinates |
| Source references | 3 placeholders; the mapping is held privately | 111 internal record identifiers; 58 source identifiers of a kind the page itself says it suppresses |
| Analyst content | 2 claims, 3 rationale sentences, confidence labels | 102 analyst assessments, 351 rationales, limitations and qualifications |
| Self-description | Declares itself a proposed sample with export-local identifiers | — |
| Schema | Not needed to read it | Root `additionalProperties: false`; its `$id` names the producing organisation; descriptions state modelling and analysis rules; one enum carries subject-specific tokens |
| URLs, local paths, tool names | 0 | 0 in the export and schema. The companion guide has 8 local paths, internal system names and commit hashes |

The compact example is not a row-subset of the full export: it is a re-keyed, hand-picked
extract with its own identifiers, and none of its rows matches a full-export row.

**Recommendation: ship the compact example.**
- The full export puts the contact details of dozens of named people, exact coordinates,
  internal record identifiers and the analysis method into one machine-readable file that
  leaves the platform.
- It re-exposes identifiers the page states are suppressed, so shipping it would contradict
  the page.
- The compact file was built as the sample and says so.
- If the recipient's stated purpose needs the structure, ship the **schema with the compact
  example** (its `$id` neutralised, and a `distribution` property added so the stamped file
  still validates). That shows the full shape without the full data.
- The full export only on a specific, stated need, as its own release with its own review.

### Third-party calls and the map

**Flag: the page as built must not ship.** One host is contacted automatically:
`tile.openstreetmap.org`.

- A self-hosted copy of Leaflet 1.9.4 requests raster tiles from it when the recipient opens
  the regional map (a location card, then a dialog, then a button). One live map, two
  markers drawn in CSS. A second, smaller map exists in the code but can never start.
- No bounds or minimum zoom are set and scroll-zoom is on, so the recipient can pan anywhere.
- **What each tile request tells a third party:** the recipient's IP address, this page's
  origin (as referrer), and the tile coordinates, which reveal the area being looked at.
- No other automatic third-party request exists. User-clicked links: the map's two
  attribution links, and link annotations inside one PDF. `Referrer-Policy: no-referrer`
  keeps the page's address out of the first two; a PDF viewer's behaviour is its own.

| Option | What it takes | Third-party requests | Notes |
|---|---|---|---|
| **1. Static map image (recommended)** | The payload replaces the map with one image of the region showing both markers, made at release time, with the "© OpenStreetMap contributors" credit in its caption. The map library, its stylesheet and the dead second map are deleted | None | Smallest change and smallest surface: about 150 KB of script removed, and the stray source-map comment goes with it. Loses pan and zoom, which two fixed markers hardly need |
| 2. Self-hosted tiles | A bounded tile set for the area and a few zoom levels, shipped inside the release and served behind the session; `maxBounds`, `minZoom` and `maxZoom` set to match | None | OpenStreetMap's tile servers may not be bulk-downloaded for this, so the tiles must come from our own rendering or a licensed source: a new toolchain for one map |
| 3. Remove the map | Delete the button and the map code | None | The location cards and the existing imagery remain |

The release linter fails any build that still names a tile host, so the choice cannot be
skipped by accident.

### Stamping

**Specified: embedded metadata in the data download, plus visible marks on pages.**

1. **JSON download (embedded metadata).** The served file is the pinned original with a
   `distribution` object inserted textually as the first member of the root object, so every
   other byte of the original is unchanged:
   `{"distribution": {"recipient": "<bound address>", "issued_at": "<token issue time, UTC>",
   "session_started_at": "…", "served_at": "…", "release": "<release_id>",
   "manifest_sha256": "…", "distribution_id": "<128-bit random>"}, …original members…}`.
   The SHA-256 of the stamped bytes and the `distribution_id` go into the `download` audit
   event, so a leaked copy maps to one download.
2. **HTML pages (visible).** A plain-text footer is inserted before `</body>` on every served
   page: "Prepared for `<bound address>` · issued `<date>` · ref `<distribution_id prefix>`".
   It survives screenshots and printing.
3. **PDFs (embedded metadata).** An incremental update adds the same fields to the document
   information dictionary and XMP. The original revision stays intact inside the file.

Metadata can be stripped by anyone who wants to. The audit log, the out-of-band token and the
visible footer are what attribute a leak; the embedded stamp is the cheap, honest label.
Robust invisible fingerprinting and visible per-page PDF watermarks are out of scope for v1.

Notes from the payload inspection:
- **Precondition:** the page's client-side download becomes a link to `/d/<file>` (payload
  finding 1). Until it does, there is no server-side download to stamp or log.
- The page is a single-page application with one HTML entry page, so the footer is one
  insertion.
- The compact example's root is an object, so the textual insertion applies. If the schema
  is ever shipped beside it, the shipped schema must allow the `distribution` property (its
  root forbids additional properties).
- The same data remains readable, unstamped, inside the page's data script. The stamp marks
  the file handed over as "the download"; the page content is attributed by the audit log
  and the visible footer.
- The PDFs are third-party originals, one of them already saved incrementally several times;
  an incremental update leaves their existing revisions intact.

### Logging and retention

- **Who:** the token's bound address (authoritative) and the submitted name (as typed).
  **When:** UTC timestamps on every event. **Source IP:** `CF-Connecting-IP`, recorded with the
  raw `X-Forwarded-For` chain and `CF-Ray`. Only Cloudflare reaches the ALB (O-005), and
  Cloudflare sets `CF-Connecting-IP` itself; DR-21's cross-account path still arrives through
  Cloudflare. **What:** every path served, its size and hash, and every download's stamped hash
  and `distribution_id`.
- **Two copies:** the DynamoDB `audit` table and CloudWatch Logs `/arclight/staging/bandersnatch`
  (structured JSON). Mail events from the SES configuration set go to the same log group.
- **D10, retention (recommended):**
  - accounts, their tokens and the `releases` records: kept until the owner removes the
    account (A3); served material: kept (A4);
  - audit events: 2 years in both copies (a leak can surface months later);
  - the `submitted_email` and `submitted_name` of **unmatched** attempts: dropped after 90
    days (they are strangers' data);
  - links and sessions: deleted 30 days after expiry by TTL (the audit events are the durable
    record); rate-limit keys after an hour.
  - Point-in-time recovery keeps 35 days of every table.
- Accounts hold outside people's names and addresses. They are kept for as long as the
  account is, and the operator tool can remove a person from an account on request.
- The landing page carries one neutral line: "Access is logged."

### Network and egress (O-017)

The service's security group, complete:

| Direction | Peer | Port | Why |
|---|---|---|---|
| Ingress | Staging ALB security group | 8080 | The only way in |
| Egress | Endpoint security group (`module.vpc.sg_vpc_endpoints_id`) | 443 | ECR api/dkr, Logs, **SES `email` (new endpoint)** |
| Egress | S3 prefix list (`module.vpc.s3_prefix_list_id`) | 443 | ECR layers; the payload bucket |
| Egress | DynamoDB prefix list (**new gateway endpoint**) | 443 | The tables |

- `internet_egress = false`. **No egress to the internet, RDS, Core, ShuttleForge or
  Nerfherder.** No Secrets Manager (no secrets). No Cloud Map consumers (the module registers
  the name, but no group admits the service).
- **New VPC endpoints:** the `email` interface endpoint (two AZs, private DNS, the existing
  endpoint group) and a DynamoDB gateway endpoint on the private app route table. Both are
  VPC-wide. Nothing in the account uses SES or DynamoDB from the VPC today (no SES identities;
  the only table is Terraform's lock table, used from operators' machines).
- No ECS Exec, no task-level shell (the O-018 posture). Non-root user, read-only root file
  system, a writable temporary volume for the verified payload cache.

### IAM

- **Task role** `arclight-bandersnatch-task-role-staging` (name fits the deploy role's
  `PassRole` pattern, `iam-github-oidc/main.tf:88-147`):
  - DynamoDB `GetItem`, `PutItem`, `UpdateItem`, `ConditionCheckItem` on `tokens`, `links`,
    `sessions`, `limits`; `GetItem` only on `releases`; `PutItem` only on `audit`; **nothing
    on `accounts`**. No `Scan`, `Query` or `DeleteItem` anywhere.
  - `s3:GetObject` on `<bucket>/releases/*`.
  - `ses:SendEmail` on the identity and the configuration set, with
    `ses:FromAddress` equal to the configured sender and `aws:SourceVpce` equal to the
    `email` endpoint.
- **Execution role** `arclight-ecs-exec-bandersnatch-staging`: ECR pull for its repository,
  `logs:CreateLogStream` and `logs:PutLogEvents` on its log group. No secrets.
- **Payload bucket policy:** deny non-TLS; deny `GetObject` to anyone but the task role and
  the named administrator principals; deny `PutObject` to anyone but the administrator
  principals; **deny deletes to everyone** (A4). Block Public Access on, `BucketOwnerEnforced`,
  SSE-S3, versioning on. No presigned URLs are ever issued.
- **Push role** for the application's repository, `main` only, scoped to its ECR repository
  (an entry in `local.ecr_push_roles`).
- **Operators** manage accounts, issue, revoke, publish and flag releases from their own
  machines with their administrator credentials through the application's CLI (DynamoDB and
  S3 APIs only). No one-off ECS task,
  so the recipient's address and the token hash never sit in `RunTask` overrides in
  CloudTrail. The token plaintext never reaches AWS.

## Threat model

| # | Threat | Controls | Residual | Test |
|---|---|---|---|---|
| T1 | **Scanner pre-fetch** consumes the link or starts the session | `GET` never changes state; activation is a `POST`; binding cookie or token required (D6) | A sandbox that presses buttons reaches only the "enter your access code" form | AT-3, AT-4 |
| T2 | **Token guessing** | 130-bit tokens; per-IP limits, and per-address and global limits on failures; neutral answers | None practical | AT-7 |
| T3 | **Mail abuse and lockout**: using the form to mail-bomb someone, or to block a recipient | Mail goes only to the bound address of a valid token; three link emails per token; send alarm; address and global limits never refuse a correct submission | The recipient can receive up to three link emails | AT-7, AT-8 |
| T4 | **Enumeration through response differences** (status, body, headers, timing, cookies) | Identical status, headers and body; cookie always set; 1.0 s floor with jitter; mail sent after the response; limits checked before validity | Statistical timing attacks need many samples, which the limits cap | AT-1 |
| T5 | **Link forwarding** | Link alone is not enough (binding or token); single use; superseded by the next link; one-hour session | A recipient who forwards both the link and the token shares access; the audit log shows the second IP | AT-4, AT-5 |
| T6 | **Session theft** | `__Host-` cookie, `HttpOnly`, `Secure`, `SameSite=Lax`; strict CSP; no third-party code; one hour; revocable | Malware on the recipient's machine | AT-11, AT-12 |
| T7 | **Cache leakage** (Cloudflare, browser, proxies) | `no-store` everywhere; cache-bypass rule; no service worker; `Vary` irrelevant (nothing cacheable) | A browser's back-forward cache may redisplay a page already seen on the same machine | AT-5b, AT-6b |
| T8 | **Public object URLs** | Private bucket, Block Public Access, deny-all bucket policy, no presigned URLs, the application streams every byte | None | AT-9 |
| T9 | **Indexing** | `X-Robots-Tag`, robots meta, `robots.txt` | A link pasted publicly by the recipient: the page needs a session anyway | AT-5b |
| T10 | **Third-party requests** leaking the recipient's IP or the page's existence | Release linter; CSP with no remote host; Cloudflare injection checked | None after AT-6 | AT-6 |
| T11 | **Origin bypass** (DR-21: another account's zone reaching the ALB) | Every control is in the application; limits are authoritative; `CF-Connecting-IP` still set by Cloudflare | Our Cloudflare cache and rate rules are skipped on that path | AT-7 (direct-to-app limits) |
| T12 | **Host header and link injection** | Host allowlist; mail links built from configuration | None | AT-16b |
| T13 | **Application compromise** | No internet egress; no path to RDS or any module; IAM limited to its tables (audit append-only), its bucket prefix and one sender | An attacker could mail data out through SES as our sender; the send alarm and `ses:FromAddress` bound it | AT-15, AT-17 |
| T14 | **Operator machine compromise** | Token plaintext only on the operator's machine and the out-of-band channel | Out of scope beyond MFA on the administrator account (DR-3 notes `sam-admin` has none) | — |
| T15 | **Spoofed mail** phishing the recipient with a lookalike link | `p=reject` on the sending subdomain and (D12) the apex | Lookalike domains we do not own | AT-14 |
| T16 | **CSRF and clickjacking** | `Origin` check on every `POST`; no state change on any `GET`; `SameSite` cookies; `frame-ancestors 'none'` | None | AT-12 |
| T17 | **Replay of an activation** | Conditional transaction; consumed links refuse | None | AT-4 |
| T18 | **Payload tampering or loss** | Three-point pin; versioned bucket; writes only by administrators, deletes by nobody; the task cannot write `releases` | An administrator can still publish a wrong release (that is the release review's job) | AT-10 |
| T19 | **Exposure through this public repository** | Neutral names; hostnames and recipient data out of git; Kerckhoffs: no control depends on secrecy of the design | The codename and design are public (see Hygiene) | AT-16 |

## Blast radius

**On the platform:**
- **Staging ALB:** one listener certificate and one host rule with an explicit priority.
  Host conditions do not overlap with `core.staging…` or `shuttleforge.staging…`; adding an SNI
  certificate leaves the default certificate unchanged. A mistake here could misroute
  staging traffic, so AT-18 checks Core's and ShuttleForge's paths before and after.
- **VPC:** two new VPC-wide endpoints (`email`, DynamoDB gateway). They change how SES and
  DynamoDB API names resolve and route from every staging subnet. No staging workload calls
  either today.
- **Cluster:** one more service; 0.25 vCPU / 0.5 GB while running.
- **DNS:** new records only. D12 (apex DMARC and null SPF) affects any future mail from the
  apex; nothing sends from it today.
- **SES production access** is account-wide: afterwards any principal with `ses:SendEmail`
  can mail anyone. Today only administrators hold that permission.
- **No change** to Core, ShuttleForge, Nerfherder, RDS, Secrets Manager, the Access
  application, the prod root or the Backstage root.

**If the application is compromised:** the attacker gets the payload releases it serves
(going out anyway, but to the wrong party), the bound addresses and hashes in its tables, and
SES sending as one address, rate-alarmed. It gets no network path to anything else and no
internet egress.

**What cannot be undone:** content already downloaded by the recipient, and mail already sent.

## Rollback

| Level | Action | Effect | Time |
|---|---|---|---|
| R0, stop one recipient | CLI `revoke --token <id>` | Token, links and its sessions refuse at the next request | Seconds |
| R1, stop everything | CLI `revoke --all`, then `aws ecs update-service --desired-count 0` | Every request gets the ALB's 503; nothing is served | 1 minute |
| R2, unpublish | Remove the proxied DNS record; set the listener rule to a fixed 404 | The hostname stops resolving to us | Minutes |
| R1b, stop one release | CLI `release set-access --inaccessible` | Every session on that material refuses at the next request; the material is untouched | Seconds |
| R3, remove the exposure | Targeted destroy of the service, listener rule, listener certificate, SES identity and configuration set, push role and ECR repository; remove the mail and page records; the `email` endpoint last | Nothing is reachable or sendable. **The payload bucket, every table and the log group stay** (A3, A4) | One apply |
| R4, remove the records | Not a rollback: the owner's separate, explicit decision. Export first; lift deletion protection and the bucket's delete-deny by hand | Accounts, tokens, audit and served material are gone | Deliberate |

- R3 leaves the records and the served material in place at a few cents a month, so removing
  the exposure never costs the history. Tables have deletion protection and the bucket has
  `prevent_destroy`, so Terraform cannot take them by accident.
- **D11:** between shares the service runs at desired count 0, so the default state is R1.
- Per-phase rollback is in the plan.

## Public-repository hygiene

- **Out of git:** the recipient's name, address and organisation; tokens; payload contents and
  subject; the payload repository's name and path; **the public hostname and the mail
  subdomain**. Terraform takes the two names as variables with no default, from a gitignored
  `terraform.tfvars` locally and from repository variables in `terraform-plan.yml` (CI fails
  without them, `.github/workflows/terraform-plan.yml:35-37`, `:67`).
- **Why keep the hostnames out:** the hostname is in public DNS, but not in Certificate
  Transparency (the wildcard covers it). Publishing it here would let anyone, including the
  recipient, search the hostname and land on this repository's description of what the page
  is for.
- **The codename in a public repository is acceptable.** "Bandersnatch" names an internal
  design; nothing it controls depends on it being secret. It must never reach a response, a
  mail, a cookie, a file name or a header the recipient sees; AT-16 greps every response and
  the received mail for it. Internal AWS names (service, tables, log group) may carry it:
  the recipient never sees them.
- Evidence that names the payload (field-level findings, file listings) is in the owner's
  private receipt, not here.

## Cost

About **$15-17 a month while the service runs**, about **$15 a month idle**: the `email`
interface endpoint (two AZs, about $14.60); Fargate 0.25 vCPU / 0.5 GB (about $9 a month if
always on, pennies at D11's uptime); DynamoDB on demand, S3, SES ($0.10 per 1 000 mails) and
logs, cents. The DynamoDB gateway endpoint is free. A one-AZ `email` endpoint halves the
endpoint cost at the price of an AZ dependency; not recommended.

## Observations in passing (not in scope)

- `podbay.staging.arclight-complex.net` is still a proxied CNAME (live, 2026-11-10), though
  Podbay was removed (O-011). It points at our ALB, which returns the default 404, so it is
  not a takeover risk. Candidate for removal in the Cloudflare Terraform work.
- The `*.staging` Access application admits a "Cloudflare Login" login method. What that
  method admits (members of the account, or any Cloudflare user) was not verified here.
- The zone's minimum TLS version is 1.0 and Always Use HTTPS is off (July's pending zone
  hardening).

## Review record

<!-- REVIEW-RECORD -->
