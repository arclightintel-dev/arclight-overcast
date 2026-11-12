# Bandersnatch: gated delivery to a named outside recipient (spec and plan)

Status: **draft for the owner.** Spec and plan in one. Nothing is built, applied, sent or published.
Request: the owner, 2026-11-10. Branch cut from `main` at `08ec540`. Live read-outs are dated 2026-11-10, read-only.
**This repository is public (DR-14).** This document names no recipient, address, payload subject, hostname or recipient-facing wording; it uses `<page-host>` and `<mail-domain>`.
History: earlier revisions and their reviews are in pull request #82 and git.

## 1. Decisions for the owner

| # | Decision | Recommendation | Section |
|---|---|---|---|
| **D1** | Who owns the token, session and audit logic: (a) a small hosted application in its own private repository on Overcast's substrate; (b) Core; (c) Cloudflare Access alone | **(a)** for the first share, by owner ruling on the O-012 pattern. Whether it becomes the platform standard is a question the owner puts to Complex; hosting the first application does not wait on the answer | 4 |
| D3 | Which JSON ships | The compact example. The full export only on a stated need, as its own release; never its companion guide as it stands | 7 |
| **D3b** | The page's own data bundle carries more than either JSON | Before the first release, strip what the page never displays and every internal name and identifier; the owner confirms the displayed personal data is meant to leave | 7 |
| D4 | The OpenStreetMap tile calls | A static map image built at release time; map library removed | 7 |
| D12 | Lock mail on the hosting domain | Null SPF (`v=spf1 -all`) and `p=reject` DMARC on `arclight-complex.net`, which never sends mail (A5) | 6.5 |
| **D13** | The mail path: (1) Microsoft 365; (2) Amazon SES on a subdomain; (3) no automated mail | **(1)** for the first share, because it needs no wait. (2) is the better long-term setup | 6.5 |
| D15 | Proving a request came through our own Cloudflare zone while DR-21 is open | A shared-secret header set by a Cloudflare rule and required by the application, removed when DR-21's client certificates land. Alternatives: wait for DR-21; or accept forgeable rate-limit keys and logged IPs for anyone with their own Cloudflare zone | 6.2 |

Already ruled by the owner, not reopened:
- **A1.** 24 hours from the click, once per token, fixed. Extending means reissuing. (Amended by the owner 2026-11-11; it was one hour.)
- **A2.** A token binds to the exact email address, not a domain.
- **A3.** Tokens are tracked under accounts; an account can be assigned organisations, domains and people.
- **A4.** Served material is never deleted, only flagged inaccessible, so a token can be reissued against it.
- **A5.** `arclight-complex.net` is application hosting only; mail goes out under `arclightlabs.io`.

## 2. Defaults

These stand unless the owner says otherwise. They were decisions in earlier revisions (original id in brackets).

- **Environment** [D2]: staging, the only platform environment in v1 (D-059 §9). Cost of that: this is the first hostname in the staging VPC not behind the `*.staging` Access application, so the service gets no path to RDS or any module.
- **Stamping** [D5]: `distribution` metadata in the JSON download plus a visible line on the page. PDF metadata is the first piece to drop if effort is short.
- **Scanners and forwarding** [D6]: the click completes only in the browser that asked for the link; any other browser must re-enter the token.
- **Store** [D7]: DynamoDB, new, so the internet-facing task has no network path to the shared RDS.
- **Token** [D9]: expires in 7 days; three link emails; link valid 24 h.
- **Retention** [D10]. Payloads (served material) are kept and only flagged inaccessible (A4). **A4 does not cover personal data**, which follows these periods:
  - account records (outside people's names and addresses) and their token records: kept until the owner removes the account; removing one person on request is the owner's call;
  - the audit log, including source IPs: 2 years in DynamoDB, 1 year in CloudWatch Logs;
  - a failed attempt not tied to an account: the typed address and name for 90 days (DynamoDB only; never in CloudWatch), its time, outcome and IP as above;
  - links and sessions: deleted 30 days after they expire.
- **Uptime** [D11]: desired count 0 except while a token can still be activated or a session is live.
- **Issuing** [D14]: only to a person recorded on the account; an address outside the account's domains needs an explicit override. Proposed in the earlier spec, not in the brief.
- Choosing the names and mailboxes [D8] is an owner task in the checklist (9.1), not a decision.

## 3. What was asked

A minimal gated path that serves a static page and a data download to a named outside recipient. The owner wants it to become the standard way to share externally. The first payload is a static sample site that is still being edited.

| # | Requirement |
|---|---|
| R1 | A nondescript page on the arclight-complex domain: logo and three fields (token, name, email). No product, recipient or codename in title, URL or copy |
| R2 | If the token is valid for that address, email it a link. The same neutral response either way |
| R3 | Rate-limit attempts |
| R4 | The link's page needs a click. A GET must not consume it (scanners). The 24 hours start at the click |
| R5 | 24 hours of page and download, then it ends |
| R6 | Tokens per recipient, bound to the address, with expiry and use count, revocable |
| R7 | Every asset behind the session; no public object URLs; `no-store`, `noindex` |
| R8 | No third-party requests |
| R9 | Log who, when, source IP, what was downloaded |
| R10 | Stamp the download with the recipient and issue time |
| R11 | The sending domain has aligned SPF, DKIM and DMARC |
| R12 | The payload is pinned to an exact commit or hash at release |

## 4. D1. Ownership

**Why Overcast cannot own the logic.** "Modules own what runs. Overcast owns where it runs" (`docs/CHARTER.md:13`). Overcast does not own "Domain logic, seam contracts, API design" (l.32) and must not become "A module (no API, no seam contracts, no domain nouns)" (l.39). Tokens, sessions, accounts and an audit trail are domain nouns with an HTTP API.

**What Overcast does own here.** "Frontend web application deployment (S3 + CloudFront or Fargate)" (l.21) and "All domain management (Cloudflare DNS, ACM certificates, SSL/TLS configuration)" (l.22). It hosts, names and provisions; it writes no request handling. Dockerfiles stay in the application's repository (l.41).

**(a) A hosted application (recommended).** A new private repository holds the code, Dockerfile, tests and operator tool. Precedent is O-012: Backstage is hosted "as a prototype platform application, not a module and not a separate tenant", by owner ruling, with no D-series needed (`docs/DECISIONS.md:151`, `:161`).
- For: the smallest blast radius (own tables, bucket, mail identity and security group; nothing shared with Core's identity plane). It meets every requirement and A3, A4.
- Against: a new repository and image; security-sensitive code outside Core's review chain.
- Limit: O-012 covers hosting one application, not "the platform's standard". Governance is Complex's (`docs/CHARTER.md:30`). Accounts (A3) are the part most likely to move to Core one day, so they are kept separate from the serving path.

**(b) Core.** Core has the vocabulary (`external_client`, D-030; an `external_consumer` plane) but no way to admit by out-of-band token plus proof of a mailbox. That is platform design (D-070 §2, D-073 §1), not an implementation detail, and "Core-brokered login is not available in v1" (`docs/DECISIONS.md:156`). Wholly in Core, it puts an unauthenticated public path on the service that signs every platform token. Most of the work (serving, stamping, mail) is not identity. Option (a) can later hand its token check to Core without changing its public behaviour.

**(c) Cloudflare Access alone.** It does not fit:

| Requirement | Access with one-time PIN | Fit |
|---|---|---|
| R1 token and name fields | No custom sign-in forms; sign-in runs on Cloudflare's domain | No |
| R4 GET must not consume | Scanners following the link use the code up; PIN lasts 10 min | No |
| R5/A1 24 hours, once | 24-hour session possible; the recipient can always sign in again | No |
| R6 expiry and use count | Exact addresses yes; no expiry or count on a rule | Partly |
| R9 audit | Auth logs kept 24 h on Free; per-request logs Enterprise | No |
| R10 stamp | The edge cannot stamp | No |
| R11 our SPF/DKIM/DMARC | Mail comes from Cloudflare's sender | No |
| A3, A4 | No counterpart | No |

D-074 §6 also rules it out as the control: "Edge authentication is never the control … defense in depth only". And DR-21 is open: a zone in another Cloudflare account can reach the staging ALB and skip Access (`docs/PROJECT_STATE.md:151`). Source: Cloudflare documentation read 2026-11-10.

Rejected runtimes for (a): Cloudflare Workers (a platform Overcast does not run; logs outside AWS) and Lambda@Edge (egress O-017 cannot constrain).

## 5. Verified state

Read 2026-11-10 from code at `08ec540` and live, read-only.

| Thing | State | Use here |
|---|---|---|
| Staging ALB `arclight-staging` | Internet-facing; 443 (`ELBSecurityPolicy-TLS13-1-2-2021-06`), 80 redirects, default 404; ingress from Cloudflare ranges only (O-005); live rule priorities 2 (ShuttleForge) and 10 (Core); access logs off; idle timeout 3600 s | One host rule at explicit priority 20 (Backstage pattern, `terraform/envs/backstage/alb.tf:5-44`) |
| Certificate | The 443 listener has `*.staging.arclight-complex.net` only. The first-level wildcard `*.arclight-complex.net` is ISSUED and already used by the prod ALB and Backstage | Attach it as SNI. No new certificate, so no Certificate Transparency entry names the page |
| Fargate module | `internet_egress` default false (O-017); creates no target group or rule; `desired_count` Terraform-managed | As is |
| VPC endpoints (staging) | `ecr.api`, `ecr.dkr`, `logs`, `secretsmanager`, S3 gateway; none has an endpoint policy. No DynamoDB endpoint. SES API endpoint `com.amazonaws.us-east-1.email` is available in all AZs (`email-smtp` is missing from us-east-1b, so API not SMTP) | Add a DynamoDB gateway endpoint; for D13 option 2, add `email` to `extra_interface_endpoints` (`terraform/envs/staging/main.tf:83-85`) |
| SES | Sandbox (`ProductionAccessEnabled: false`, 200 per 24 h, 1 per second); no identities; account suppression list on | D13 |
| Mail DNS `arclightlabs.io` | Cloudflare CF-01. MX Microsoft 365; SPF `include:spf.protection.outlook.com -all`; DKIM `selector1`/`selector2`; DMARC `p=none` | The sending domain (A5). Apex records untouched |
| Mail DNS `arclight-complex.net` | No MX, no SPF, no `_dmarc` | Hosting only (A5); D12 locks it |
| Mail DNS `ansanalytics.com` | DNS at WordPress.com, no management connection (`docs/service_registry.md:58`); not aligned today | Not used |
| Cloudflare zone `arclight-complex.net` | Full (strict); Universal SSL covers the first-level wildcard; no cache, configuration or rate-limit rules exist | Hostname-scoped rules (6.2) |
| Zone settings that alter responses | Email Address Obfuscation on; Network Error Logging on (live `NEL` and `Report-To` naming `a.nel.cloudflare.com`); Automatic HTTPS Rewrites on; browser cache TTL 14,400 s; minimum TLS 1.0; Always Use HTTPS off. Web Analytics, Zaraz and Speed Brain unreadable with the read-only token (error 10000) | Treated as on; switched off or overridden for the page host |
| Access | One application, `*.staging.arclight-complex.net` | Not used. The page host is first-level, so it matches no Access application |
| Cloudflare write token | Scoped to `arclight-complex.net` only (operator's note, not re-tested) | Needs extending (9.1) |
| CI plan | Repository **variables** print in clear in public job logs (`TF_VAR_core_image_tag`); **secrets** are masked (`TF_VAR_alarm_email`); verified, run 42885203378. A new variable without a default fails the plan | Names go in secrets |
| Deploy workflow | `deploy-service.yml` offers `core` and `shuttleforge` only | Manual deploys for v1 |
| Push roles | Hard-coded list in `iam-github-oidc`; adding a repository widens the CI deploy role's image-read list in place (`main.tf:122-130`) | One expected in-place update |
| RDS and `dbbootstrap` | Shared by every module | Not reused: an internet-facing task would get a 5432 path to the server holding every module's database (DR-17) |

## 6. Design

### 6.1 Shape and flow

```
recipient ──HTTPS──▶ Cloudflare (proxied; cache bypass; no injection; adds the origin secret)
                        │  Full (strict)
                        ▼
                 staging ALB :443  ── SNI *.arclight-complex.net ── rule: Host = <page-host>
                        │  8080 (health checks: 8081)
                        ▼
          bandersnatch task (Fargate, private app subnets, no internet egress)
             │ DynamoDB (gateway)   │ S3 payload (gateway)   │ mail (D13)   │ Logs, ECR (interface)
```

1. The operator creates the account and person, publishes a release, issues a token, and gives the token to the recipient by a channel other than email.
2. The recipient opens `<page-host>` and enters token, name and email. The answer is always the same and neutral.
3. If the token is valid for that exact address, a mail with a link goes to that address.
4. The link's page shows one button. Loading it changes nothing. Pressing it starts the 24 hours, in the same browser that asked, or in another after re-entering the token.
5. For 24 hours the session serves the pinned site and the stamped download. Then it ends.
6. The operator flags the release inaccessible, sets desired count 0 and exports the account report.

### 6.2 What Overcast provides

- **Edge (Cloudflare), scoped to the hostname.** One proxied first-level record to the ALB. A cache rule (bypass; `.pdf` is cached by default and the zone's 4 h browser TTL would override). A configuration rule (Email Address Obfuscation, Real User Monitoring, Automatic HTTPS Rewrites and Rocket Loader off). A response-header rule removing `NEL` and `Report-To`. A request-header rule setting the origin secret (D15). The zone's one free rate-limit rule on `POST` (per IP, 10 s). Cloudflare's own `/cdn-cgi/*` and error pages are not ours to set. Zone minimum TLS and Always Use HTTPS are observations, not part of this change.
- **ALB.** `aws_lb_listener_certificate` for the existing wildcard; a target group (`ip`, HTTP 8080); one rule, priority 20, `Host = <page-host>`. The health check is on port 8081 `/ready`, which no listener forwards to, so health is not public.
- **Service.** Fargate 0.25 vCPU / 0.5 GB, `internet_egress = false`, desired count a variable (default 0), non-root, read-only root file system, no ECS Exec (O-018 posture).
- **Network.** Ingress from the ALB group on 8080 and 8081. Egress on 443 to the endpoint group (ECR, Logs, Secrets Manager, and SES `email` under D13 option 2), to the S3 prefix list and to the DynamoDB prefix list. Nothing to the internet, RDS, Core, ShuttleForge or Nerfherder, except the Microsoft egress of D13 option 1. Residual: the shared endpoints carry no endpoint policy (`docs/proposals/nf-egress-lockdown.md:286-293`), tracked as DR-24.
- **Stores.** The DynamoDB tables the application names (6.4), with deletion protection and point-in-time recovery. One payload bucket: private, Block Public Access, versioning, deletes denied to everyone, no overwrite of an existing key, no lifecycle rule, `prevent_destroy`. No presigned URLs.
- **IAM.** The task can read tokens and releases, write its own links, sessions, counters and audit events, read the payload bucket, and send as the one configured address. It cannot create a token, write a release or the bucket, or touch accounts. The role names (`arclight-bandersnatch-task-<env>`, `-exec-<env>`) fall outside the CI deploy role's `PassRole` patterns (`iam-github-oidc/main.tf:132-138`), so CI cannot run a task as this service. The application's repository gets a push role, `main` only. Operators run the tool from their own machines with administrator credentials; the token plaintext never reaches AWS.
- **Secrets.** One shell for D15's value, written by the owner (INV-004); one more for the mailbox credential under D13 option 1. Names derive from `var.environment` (INV-001).
- **Interface handed to the application.** Ports 8080 (traffic) and 8081 (health); `/ready` = process up and DynamoDB reachable; configuration by environment (host, sender, reply-to, wording, table names, bucket, mail settings, region, origin secret); image `arclight/bandersnatch`, tag `v1-<sha>`, deployed by digest; JSON logs on stdout to `/arclight/staging/bandersnatch`.

### 6.3 Application requirements

Normative for the application. They are held here only until the application's own repository exists, and move there then; Overcast owns infrastructure, not application logic (`docs/CHARTER.md:43`).

- **Neutral response (R2).** Every submission gets the same status, headers and body whether or not the details match. The mail is sent after the response.
- **Rate limit (R3).** Per IP, 5 per 15 minutes and 20 per day, 429 whatever was submitted. This is the only limit that refuses, so nobody can lock a recipient out and the limit is no oracle. Client IP is `CF-Connecting-IP`.
- **Exact binding (A2).** The address is trimmed and lower-cased; nothing else is folded. The name is recorded, never validated, never echoed.
- **Link (R4).** A GET or HEAD on the link never changes state and returns the same page for any link. The click is a POST. It starts the session only with the binding cookie from the browser that asked, or with the token re-entered. A newer link supersedes an older one. A link is valid 24 h. Why: a scanner that presses buttons, or anyone the mail is forwarded to, has neither factor.
- **Once, 24 hours (A1).** One activation per token, with no setting for it. The session ends 86400 s after the click; no refresh, no sliding expiry. Token expiry bounds when a session may start, not when it ends.
- **A lost response or a double click must not burn the only activation.** The same proof within the 24 hours gets the same session back, never a new one.
- **A failed send must not cost the recipient a link.** Three link emails per token.
- **Revocation (R6).** Revoking a token, revoking a session, suspending an account or flagging a release inaccessible takes effect at the next request.
- **Everything behind the session (R7).** Only paths in the pinned manifest are served. Without a valid session every path is the same neutral 404. Public routes are `/`, `/a/*`, `/v/*`, `/d/*` and `/robots.txt`.
- **Headers on every response.** `Cache-Control: no-store, no-transform`; `X-Robots-Tag: noindex, nofollow, noarchive, nosnippet`, plus the robots meta tag and a disallow-all `robots.txt`; `Referrer-Policy: same-origin`; HSTS; `nosniff`; a CSP with no host outside `'self'`, `frame-ancestors 'none'`, `form-action 'self'`. The session cookie is `__Host-`, `Secure`, `HttpOnly`.
- **No third-party requests (R8).** `no-transform` stops Cloudflare's email-obfuscation rewrite and analytics beacon (the edge rules are the second layer). The application compresses its own text responses, because `no-transform` stops Cloudflare doing it. Requests marked `Sec-Purpose: prefetch` are refused.
- **CSRF that works with real browsers.** Every POST and every download requires `Sec-Fetch-Site: same-origin`; a POST also requires `Origin` equal to the page origin; `null` is never accepted. This is why the referrer policy is `same-origin`: under `no-referrer` browsers send `Origin: null` on form posts and every real submission would be refused.
- **Host and origin.** Only `Host = <page-host>` is served. Mail links are built from configuration, never from the request. The origin secret is required if D15 is approved (neutral 404 without it).
- **Wording.** Everything the recipient sees is neutral, chosen by the owner, supplied as configuration, and never contains the codename. The click page says the 24 hours cannot be paused or repeated.
- **Tokens.** 130 random bits (26 Crockford base32 characters), generated on the operator's machine, shown once. Only hashes of tokens, links and cookies are stored; none is logged.
- **Stamping (R10).** The JSON download is the pinned original with a `distribution` object (bound address, token issue time, session start, release id and manifest hash, a distribution id) inserted as the first member, every other byte unchanged. The bytes are the same for every request in a session. HTML pages carry a visible line (address, issue date, short reference). PDF metadata is optional (section 2). Metadata can be stripped; the audit log and the visible line are what attribute a leak.
- **Pinning (R12).** A release is an immutable directory with a manifest (each file's path, SHA-256, size and type; the source commit; a clean-tree flag). The release id is the first 16 hex characters of the manifest's SHA-256. The tool refuses a dirty tree. The application verifies the manifest and file hashes before serving and refuses a release that does not match. Each token carries its release's manifest hash.
- **Release lint.** Rejects any URL loaded from another host, source maps, absolute local paths, the codename, dotfiles and service workers. Reports internal names, identifiers, addresses and phone numbers for the owner's sign-off.
- **Audit (R9).** Who (bound address; name as typed), when (UTC), source IP, and what (every path served, every download with its stamped hash). Two copies: the audit table and CloudWatch Logs. Reports say "accessed under the token issued to", not "read by".
- **Operator tool.** Account create/assign/suspend/show, issue, revoke, session revoke, release lint/publish/set-access, report by account, audit export.

### 6.4 Records

- `accounts`: the organisations, domains and people the owner tracks sharing by (A3). Records for tracking, not credentials. The serving task cannot read it. Suspending an account is the operator tool marking each of that account's tokens as suspended, which is the record the task does read.
- `releases`: each published release, its manifest hash and its accessible flag (A4).
- `tokens`: what was granted, to which address, for which release, until when; its use count and revocation.
- `links` / `sessions`: the emailed link and the one session it starts.
- `limits`: per-IP counters.
- `audit`: every event.

The exact table list is the application's to settle; Overcast provisions what it names. Accounts, tokens and releases are kept; links and sessions expire by TTL.

### 6.5 Mail (D12, D13)

Amazon SES starts in a sandbox that can only mail verified addresses, and verifying the recipient would make AWS email them. Lifting it (production access) takes AWS about a day. So the mail path is the owner's choice:

| Option | Takes | Cost |
|---|---|---|
| **1. Microsoft 365 (recommended for the first share)** | It already serves `arclightlabs.io` with aligned SPF and DKIM. No DNS change, no wait | The task needs a stored credential for one sending mailbox, and internet egress to Microsoft: an explicit exception to the no-egress default (O-017) |
| 2. Amazon SES on a subdomain of `arclightlabs.io` | Through a VPC endpoint: no egress, no stored credential. The better long-term setup | Six DNS records and production access (about a day) |
| 3. No automated mail | The application shows the operator the link and he sends it from his own mailbox | A manual step per link; mail to the bound address is not enforced by the application |

In every option the sender is under `arclightlabs.io` (A5): a no-reply address, a neutral display name, and `Reply-To` to a mailbox the owner reads. The message is plain text with a minimal HTML alternative: the link, how long it is valid, and that the 24 hours start at the button. No images, no tracking.

D12 applies whichever option is chosen: zone `arclight-complex.net` gets apex TXT `v=spf1 -all` and `_dmarc` TXT `v=DMARC1; p=reject; sp=reject`.

Residual: the sender and the link are on different domains, and a first mail from a new sender can look like phishing to a corporate gateway. The token hand-over tells the recipient to expect it.

**Option 2 in detail.** A dedicated subdomain `<mail-domain>`; no apex record changes.

| Record | Where | Value |
|---|---|---|
| SES domain identity | SES us-east-1 | `<mail-domain>`, Easy DKIM, RSA 2048 (DKIM aligned) |
| 3 DKIM CNAMEs | Zone `arclightlabs.io`, DNS-only | `<sel>._domainkey.<mail-domain>` → `<sel>.dkim.amazonses.com` |
| Custom MAIL FROM | SES | `bounce.<mail-domain>`, on MX failure: **reject message** (SPF aligned, relaxed) |
| MX | Same zone | `bounce.<mail-domain>` → `10 feedback-smtp.us-east-1.amazonses.com` |
| SPF | Same zone | `bounce.<mail-domain>` TXT `v=spf1 include:amazonses.com -all` |
| DMARC | Same zone | `_dmarc.<mail-domain>` TXT `v=DMARC1; p=reject; adkim=s; aspf=r; rua=mailto:<report mailbox on arclightlabs.io>` |

- "Reject message" matters: otherwise SES silently falls back to its own MAIL FROM and SPF stops aligning. SES aligns SPF relaxed only, so `aspf=s` would break it. No null MX on the From subdomain (RFC 7505).
- Sending is SESv2 `SendEmail` through the `email` interface endpoint with the task role. No SMTP credentials. A configuration set with CloudWatch metrics; alarms on bounces, complaints and send volume; click tracking off.
- Until production access is granted, staging acceptance uses the owner's own verified address.

## 7. The first payload: findings the owner must act on

One HTML entry page (a single-page application), 10 scripts, 7 stylesheets, one self-hosted font, 28 images and 10 PDFs: 57 files, 40.3 MB. No fetch, XHR, storage, cookies, analytics or remote fonts. File-level evidence is in the owner's private receipt.

1. **The download is built in the browser.** The button assembles the JSON from data embedded in the page. The server never sees a download, so it can neither stamp nor log it (blocks R9, R10). The button must become a link to `/d/<file>`; the copy button goes, or is accepted as unstamped.
2. **D3b: the page's data bundle discloses more than either JSON.** About half a megabyte goes to every recipient's browser: personal and contact data and reproduced source text (displayed); internal record identifiers (displayed); an internal system name and several kinds of never-displayed field (working notes, follow-up lists, how sources were obtained, identifiers the page says are suppressed, one image shipped but never shown).
3. **D4: the map calls `tile.openstreetmap.org`** (self-hosted Leaflet 1.9.4). Each tile request gives a third party the recipient's IP, the page's origin and the area viewed. The page as built must not ship.

   | Option | Takes | Notes |
   |---|---|---|
   | **1. Static map image (recommended)** | One image with the markers, made at release time, credited "© OpenStreetMap contributors"; map library deleted | Smallest change; about 150 KB of script removed; loses pan and zoom |
   | 2. Self-hosted tiles | A bounded tile set shipped in the release | OSM's servers may not be bulk-downloaded; needs own rendering or a licensed source |
   | 3. Remove the map | Delete the button and code | Other location content remains |

4. **A possible second published copy.** The site's repository carries a configuration file for an external hosting service pointing at the build output. The owner confirms the site is published nowhere else, or the gate is moot.
5. **Dirty tree.** At inspection files were being edited, and the entry page references two files that do not exist yet. The pin is taken only from a clean commit.
6. The site redistributes third-party documents and credited commercial imagery; redistribution rights are the owner's call. The existing handover archive and its guide (local paths, internal names, commit hashes) are not part of this delivery.

**D3. Which JSON ships.**

| | Compact example | Full export |
|---|---|---|
| Size | Under 4 KB | About 730 KB, plus a 33 KB schema |
| Shape | 10 tables, 14 rows, 66 fields | 17 tables, 1,842 rows, 150 fields |
| Named individuals and contact data | None | Present, at scale |
| Precise locations | None | Present |
| Source references | Placeholders | Internal identifiers, including a kind the page says it suppresses |
| Analyst content | A handful of claims | Hundreds of assessments and rationales |

Ship the compact example: it was built as the sample and says so. If the recipient needs the structure, ship the schema with it (identifier neutralised, `distribution` allowed). The compact file is "least data out" only if the bundle (finding 2) is reduced to match.

## 8. Threats

| Threat | Control | Residual |
|---|---|---|
| Scanner pre-fetch | A GET never consumes; the click needs the binding cookie or the token | A button-pressing sandbox reaches only the token field |
| Token guessing | 130-bit tokens, per-IP limit, neutral answers | None practical |
| Using the form to mail-bomb or lock out a recipient | Mail only to the bound address of a valid token, three per token; only the per-IP limit refuses | — |
| Enumeration by response differences | Identical responses; mail after the response | — |
| Link forwarding | The link alone is not enough; single use | A recipient who forwards link and token shares access; the audit log shows the second IP |
| Session theft | `__Host-`, `HttpOnly`, `Secure` cookie; strict CSP; 24 hours; revocable | Malware on the recipient's machine |
| Cache and indexing | `no-store`, cache-bypass rule, `noindex` | — |
| Third-party requests | Lint, CSP, `no-transform`, edge rules | A PDF viewer following a link inside a PDF |
| Public object URLs | Private bucket, no presigned URLs; the application streams every byte | — |
| Origin bypass (DR-21) | The origin secret (D15) | Until then, forgeable rate-limit keys and logged IPs |
| CSRF, forced download, clickjacking | `Sec-Fetch-Site` and `Origin`; no state change on GET; `frame-ancestors 'none'` | — |
| Spoofed mail | `p=reject` on the sending subdomain (D13 option 2) and on the hosting domain (D12) | Lookalike domains; the corporate apex stays `p=none` |
| Application compromise | No internet egress, no path to RDS or any module, narrow IAM | Data can still leave through the unpoliced shared AWS endpoints (and the Microsoft egress under D13 option 1). The response is revoke everything and desired count 0, not a redeploy |
| Exposure through this public repository | Names, wording and pins kept out of git and CI logs | No control depends on the design being secret |

What cannot be undone: content already downloaded and mail already sent.

## 9. Plan

### 9.1 Owner checklist (P0)

- Rule on D1, D3, D3b, D4, D12, D13 and D15. Overcast records the outcome as **O-019** in `docs/DECISIONS.md`. Under D1, ask Complex whether a platform standard needs a D-series.
- Choose, and keep out of git: the public hostname, mail subdomain (option 2), page title and wording, sender display name, reply-to mailbox and DMARC report mailbox (both on `arclightlabs.io`). They go in the gitignored `terraform.tfvars` and in repository **secrets** (not variables) for `terraform-plan.yml`. The Terraform variables are `sensitive`, have no default, and appear in no resource address, name or tag.
- Create the application's private repository.
- Confirm the site is published nowhere else (finding 4).
- D13 option 1: create the sending mailbox and write its credential into the secret shell.
- D13 option 2: submit the SES production-access request (console or `aws sesv2 put-account-details`). Draft use case: transactional only; single-use access links to named business contacts who have just requested one; no marketing, no lists; under 50 a day; the suppression list and alarms handle bounces.
- Cloudflare:

| What | Where | Why |
|---|---|---|
| Write token: add zone `arclightlabs.io` with DNS: Edit | API Tokens → the Terraform token | The six mail records (D13 option 2 only) |
| Write token: on `arclight-complex.net` add Cache Rules: Edit, Config Rules: Edit, Zone WAF: Edit | Same token | Cache, configuration and rate-limit rules |
| Read-only token: add Cache Rules: Read, Config Rules: Read, Zone WAF: Read; Web Analytics and Zaraz read if offered | The read-only token | Read-back |
| Is Web Analytics automatic setup on? | Dashboard: Web Analytics | Injects a third-party beacon; blocked either way |
| Is anything configured in Zaraz? | Dashboard, the zone | Same |
| Is Speed Brain on? | Dashboard: Speed | Prefetches links; refused either way |
| Two mailboxes on `arclightlabs.io` | Microsoft 365 | Reply-to and DMARC reports |

### 9.2 Phases

| Phase | Who | What | Gate |
|---|---|---|---|
| P0 | Owner | Rulings, names, Cloudflare access, mail prerequisite | O-019 recorded |
| P1 | Overcast | Mail path per D13 | T10 |
| P2 | App | Application and operator tool | App's own tests and review |
| P3 | Overcast | Substrate on staging, desired count 0 | Expected plan; T11 |
| P4 | Payload, operator | First release: map, download, bundle, JSON, pin | Lint clean; owner's sign-off |
| P5 | All; owner as test recipient | End-to-end acceptance on staging | Every test; owner's sign-off |
| P6 | Owner | First live share | Owner's go; under D13 option 2, SES production access |

- P1 and P2 run in parallel after P0. The ECR repository and push role (P3a) come before P2's first push.
- **P1, option 1:** the credential shell and the Microsoft egress rule; nothing in DNS but D12. **Option 2**, in this order, which yields T10's negatives for free: identity and DKIM first, send test 1 (SPF not aligned yet); add the custom MAIL FROM before its MX, send test 2 (SES refuses); add MX and SPF, send test 3 (all aligned). Additions only; nothing at the apex.
- **P3 expected plan:** additions, plus **one in-place update** (the CI deploy role's image-read list gains the repository). No change to any Core, ShuttleForge, Nerfherder, RDS, listener-default or existing endpoint resource; the prod and Backstage roots plan "No changes". The vpc module's new endpoint options default off. `scripts/plan_guard.py`, then applied locally by an administrator on the owner's go (DR-1).
- **P4:** payload fixes per section 7, commit clean, lint, the owner signs the lint's review list, publish inaccessible. The release id and hashes go to the owner's private receipt, never this repository.
- **P5:** deploy by digest; a test account with the owner as its only person; run the tests; the owner reads the mail in a real mailbox; then flag inaccessible and desired count 0.
- **P6:** create the account, flag the release accessible, issue, hand the token over by another channel, desired count 1 (the variable first, then the service: an apply with the variable at 0 would stop a live share). Afterwards flag inaccessible, count 0, export the account report. Never while a session is live.
- No automatic deploys (D-059 §8); the owner's go per release. Review per `docs/REVIEW_PROCESS.md` before any apply.
- Follow-ups, none gating: DR-21 replaces the origin secret; endpoint policies on the shared endpoints (DR-24); CloudTrail data events for operator actions; the Cloudflare Terraform root adopts the records and rules; `deploy-service.yml` learns this service; PDF watermarking; a platform home (Complex's answer under D1); a move from D13 option 1 to option 2.

## 10. Acceptance tests

Each claim has one negative that must fail, proving the check can tell the difference. "App" runs in the application's suite with a real headless browser; "S" runs on staging.

| # | Claim | Positive | Discriminating negative | Where |
|---|---|---|---|---|
| T1 | Neutral response; exact address (R2, A2) | Valid, wrong-token, wrong-address, expired and revoked submissions return the same status, headers and body; the bound address in another letter case gets a link | Another address at the same domain, or a plus-tagged variant, gets no mail; the comparison harness fails on a build that changes one body byte | App; S |
| T2 | A GET never consumes; the link alone is not enough (R4) | Ten GETs and a HEAD from a cookieless client leave the link usable; the original browser's click starts the session; another browser is asked for the token and accepts the right one | A POST from the cookieless client with no token starts nothing | App; S |
| T3 | Once, 24 hours (R5, A1) | Serves at start + 23 h 59 min 50 s; after a simulated lost response the same proof returns the same session and end time | Refuses at + 24 h 1 s; a second link request after activation sends no mail and starts no session; the first link is refused once a second was requested | App (clock); S (real wait, once) |
| T4 | Revocation is immediate (R6, A4) | A reissued token against a re-flagged release serves the same pinned bytes | After token revoke, session revoke or flag-inaccessible, the live session's next request gets the neutral 404; object versions are unchanged | App; S |
| T5 | Everything behind the session, pinned (R7, R12) | With a session every unstamped manifest path returns its pinned hash; the stamped ones (HTML, the JSON download) match the pinned original once the stamp is removed (T9) | Every path returns the neutral 404 with no cookie or an expired one; an anonymous S3 request gets 403; a release with one flipped byte is refused; `https://<page-host>/ready` is 404 | App; S |
| T6 | Nothing cacheable, indexable or third-party, as received through Cloudflare (R7, R8) | A headless browser with a live session loads every page; every request goes to the page host; every response carries `no-store`, `noindex` and `Referrer-Policy: same-origin` | No response carries `NEL` or `Report-To`; a repeated PDF request never shows `cf-cache-status: HIT`; a fixture page with a remote image fails the crawl; lint rejects a tile URL | App; S |
| T7 | A rate limit that is no oracle and no lockout (R3) | The sixth submission from one IP in 15 minutes gets 429 | The sixth carrying a valid token also gets 429 and no mail; after six failures for the recipient's address from other IPs, the rightful submission still gets its link; (D15) a request without the origin secret gets 404 and is not counted | App |
| T8 | The CSRF check works with real browsers | A real browser submitting the real form succeeds | A POST with `Origin: null`, a foreign origin, or without `Sec-Fetch-Site: same-origin` gets 403 and changes nothing | App |
| T9 | Stamped and logged (R9, R10) | The download's `distribution` carries the bound address and issue time; removing it reproduces the pinned original byte for byte; the account report shows submission, mail, link opens, session start and end, each path and the stamped hash | A download under a token issued to a different address never contains the first address; a request with a forged `X-Forwarded-For` is logged with the client's real IP | App; S |
| T10 | Mail is aligned (R11) | The received mail shows `spf=pass` **with the envelope sender's domain under the From domain**, `dkim=pass` with `header.d` equal to the From domain, and `dmarc=pass`; no apex record changed. Option 2: this is test 3, with `p=reject` in DNS | Option 2: test 1 (no custom MAIL FROM) fails the envelope-domain comparison, because its envelope sender is under `amazonses.com` even though SPF and DMARC both pass; test 2 (MAIL FROM set, MX absent) is refused by SES | S (P1) |
| T11 | No path out; neighbours unchanged (O-017) | From a probe task in the service's group, DynamoDB, S3, ECR, Logs and the chosen mail path connect; the page host returns the landing page and is not redirected to Access | 443 to the internet, 5432 to RDS and 443 to Core's NLB time out; `core.staging…` is still redirected to Access, and rules 2 and 10 and the default certificate are unchanged | S (P3, P5) |
| T12 | Nothing identifying leaks (R1, public repository) | — | A search of the access pages, headers, cookie names, file name and the received mail for the codename, product, modules, recipient and subject finds nothing; a search of every commit on the branch, the plan job's log and the pull request for the hostname, mail subdomain, mailboxes and release hashes finds nothing; a seeded string makes each search fail | App; S |

Not testable: the recipient's real mail gateway is first met in P6. That is why the token re-entry, the same-session retry and three link emails exist.

## 11. Rollback

- **RB0, stop one recipient:** revoke the token. Seconds.
- **RB1, stop one release:** flag it inaccessible. Seconds; the material is untouched.
- **RB2, stop everything:** revoke all; desired count 0 (CLI and the variable). The ALB answers 503. One minute. This, not a redeploy, is the response to a suspected compromise.
- **RB3, unpublish:** remove the proxied DNS record. Minutes.
- **RB4, remove the exposure:** destroy the service, listener rule, certificate attachment, mail identity or credential, push role, DNS records and Cloudflare rules, the `email` endpoint last. One apply.
- **Records and served material stay** (A3, A4). The bucket, the tables, the log group and the image repository survive RB4 at a few cents a month. Deleting them is a separate, explicit owner decision, never a rollback.
- Between shares the service sits at desired count 0, so the resting state is RB2.

## 12. Cost and observations

**Cost.** About **$15 a month idle** under D13 option 2 (the `email` interface endpoint in two AZs, about $14.60); options 1 and 3 do not build that endpoint. Fargate adds about $9 if the service ran all month (about **$24** in all under option 2). DynamoDB, S3, SES ($0.10 per 1,000), a secret ($0.40) and logs are cents; the DynamoDB gateway endpoint is free.

**Blast radius.** One SNI certificate and one host rule on the staging ALB. VPC-wide endpoints nothing else uses. Under option 2, SES production access is account-wide: afterwards any principal with `ses:SendEmail` can mail anyone (today only administrators hold it). Under option 1, one task with egress to Microsoft and a mailbox credential. No change to Core, ShuttleForge, Nerfherder, RDS, the Access application, prod or Backstage.

**Observations in passing** (not in scope; DR-24 in `docs/PROJECT_STATE.md` points here). `podbay.staging.arclight-complex.net` is still a proxied CNAME (Podbay removed, O-011) and resolves to the ALB's 404. The `*.staging` Access application allows a "Cloudflare Login" method; what it admits is unverified. Zone `arclight-complex.net` has minimum TLS 1.0, Always Use HTTPS off, NEL on and Email Address Obfuscation on. `arclightlabs.io` DMARC is `p=none`. `ansanalytics.com` SPF does not list Microsoft 365 and has no DKIM at the default selector (inferred from DNS). The staging VPC endpoints carry no endpoint policies.
