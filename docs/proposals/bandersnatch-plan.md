# Bandersnatch: phased plan and acceptance tests

Status: **Revision 3, draft for the owner's review.** Companion to the
[spec](bandersnatch.md). Nothing here is scheduled: every phase waits on the owner's ruling
on the spec's decisions, and every state change waits on the owner's go, given first-hand.

Parties: **Owner**; **Overcast** (substrate, DNS, mail identity); **App** (the hosted
application's own repository and session, spec D1); **Payload** (the repository the first
payload is built from).

## Phases

| Phase | Who | What | Gate to leave |
|---|---|---|---|
| P0 | Owner | Rulings, names, Cloudflare access, prerequisites | Rulings recorded as an O-decision |
| P1 | Overcast | Mail domain on `arclightlabs.io` | AT-14 |
| P2 | App | Build the application and its operator tool | App test suite, including every negative below; code review |
| P3 | Overcast | Substrate on staging, service at desired count 0 | Expected plan; AT-9 (bucket), AT-15, AT-17, AT-18 (neighbours) |
| P4 | Payload, operator | First release: map fix, download fix, data bundle, JSON choice, pin, publish | AT-6 (lint), AT-10 (storage and pin) |
| P5 | Overcast, App, Owner as the test recipient | Staging acceptance, end to end | Every AT passes; the owner's sign-off |
| P6 | Owner | First live share | The owner's go |
| P7 | Overcast | Follow-ups (tracked, not gating) | — |

P1 and P2 can run in parallel once P0 is done. P3a (the ECR repository and push role) comes
before P2's first push.

Review, per `docs/REVIEW_PROCESS.md`: P1 (IAM, shared DNS) and P3 (new service wiring, IAM,
security groups, a module change) each get claude-core and a contract audit, then codex-1,
codex-2 and hotpants, before any apply. P2's code review is App's.

### P0. Rulings and prerequisites (Owner)

1. Rule on D1-D15 in the spec. Overcast records the outcome as **O-019** in
   `docs/DECISIONS.md`. Under D1, the owner asks Complex whether "the platform's standard way
   to share" needs a D-series decision; hosting the first application does not wait on the
   answer (the O-012 pattern).
2. Choose, and keep out of git (D8): the public hostname, the mail subdomain, the page title
   and wording, the sender's display name, the reply-to mailbox and the DMARC report mailbox
   (both on `arclightlabs.io`). They go into the gitignored `terraform.tfvars` and into
   repository **secrets** for `terraform-plan.yml`.
3. Create the application's private repository.
4. **Submit the SES production-access request** (console, or `aws sesv2 put-account-details`).
   AWS's documentation gave an initial response time of up to 96 hours when read on
   2026-11-10. Draft use case, for the owner to edit and send:
   > Transactional mail only: single-use access links sent to named business contacts who
   > have just requested one on our site with a code we issued to them. No marketing, no
   > lists. Expected volume: under 50 messages a day. Bounces and complaints are handled by
   > the account-level suppression list and CloudWatch alarms; every recipient is
   > individually invited.
5. **Cloudflare** (the owner has offered to change tokens and settings; this is the full
   list). Permission names are as Cloudflare's token editor shows them; if one is named
   differently, the equivalent is the one that edits that rule type.

   | What | Where | Why |
   |---|---|---|
   | Write token: add zone `arclightlabs.io` with **DNS: Edit** | My Profile → API Tokens → the Terraform token | The six mail records (P1). Today the token works on `arclight-complex.net` only |
   | Write token: on `arclight-complex.net` add **Cache Rules: Edit**, **Config Rules: Edit**, **Zone WAF: Edit** | Same token | The cache rule, the configuration rule and the rate-limiting rule (P3). It already has DNS, zone settings and transform rules |
   | Read-only token: add **Cache Rules: Read**, **Config Rules: Read**, **Zone WAF: Read**, and Web Analytics and Zaraz read if offered | The read-only token | So every rule can be read back and recorded |
   | Is **Web Analytics** automatic setup on for `arclight-complex.net`? | Dashboard: Web Analytics | It injects a third-party beacon (spec, Edge). Blocked either way; the answer goes in the record |
   | Is anything configured in **Zaraz**? | Dashboard, the zone | Same reason |
   | Is **Speed Brain** on? | Dashboard, the zone: Speed, content optimisation | It prefetches links. The application refuses prefetches either way |
   | Two mailboxes on `arclightlabs.io` | Microsoft 365 | Reply-to, and DMARC reports for the new subdomain |

Rollback: none needed; nothing exists yet.

### P1. Mail domain (Overcast)

The order produces AT-14's two negatives on the way to its positive.

1. Terraform (staging root): SES domain identity for the mail subdomain with Easy DKIM
   (RSA 2048), **without** a custom MAIL FROM yet; a configuration set with reputation
   metrics and a CloudWatch metrics destination; email feedback forwarding off; alarms on
   bounces, complaints and sends.
2. Cloudflare, zone `arclightlabs.io`, DNS-only, written with the extended token and read
   back: the three DKIM CNAMEs and the subdomain's DMARC TXT. **Nothing at the apex.** If D12
   is approved, zone `arclight-complex.net`: the null SPF and `p=reject` DMARC. Recorded in
   `docs/service_registry.md` by record type only.
3. When SES reports DKIM verified: verify the owner's own address as a sandbox recipient (it
   mails the owner, nobody else) and send **test 1**. Expected: DKIM passes aligned; the
   envelope sender is under `amazonses.com`, so SPF is not aligned (AT-14 negative 1).
4. Terraform: the custom MAIL FROM `bounce.<mail-domain>` with reject-on-MX-failure, before
   its MX exists. Send **test 2**. Expected: SES refuses the send (AT-14 negative 2).
5. Cloudflare: the MAIL FROM MX and SPF TXT. Wait for SES to verify it (AWS can take up to 72
   hours to see the MX). Send **test 3**. Expected: AT-14's positive.

- Expected plan: additions only (identity, DKIM, MAIL FROM, configuration set, event
  destination, three alarms). No change to any existing resource.
- Acceptance: **AT-14**.
- Rollback: destroy the SES resources; delete the DNS records. Nothing else depends on them,
  and no apex record was touched.

### P2. Application (App)

Overcast hands over the interface; App owns everything behind it.

| Interface | Value |
|---|---|
| Listens | 8080 (traffic) and 8081 (health only), HTTP, non-root, read-only root file system |
| Health | Port 8081 `/ready`: 200 when the process is up and DynamoDB answers. A release that fails verification is not served and alarms; it does not fail health |
| Configuration (environment) | public host, sender address and display name, reply-to, page wording, table names, payload bucket, SES configuration set, region; the origin secret (D15) injected from its Secrets Manager shell |
| AWS access | The task role in the spec's IAM section; no static keys |
| Egress | Exactly the spec's network table; **no internet** |
| Image | `arclight/bandersnatch`, tag `v1-<sha>`, immutable; deployed by digest |
| Logs | JSON lines on stdout; never a token, nonce, binding cookie, session identifier, origin secret, or `Cookie` or `Referer` header value |
| Stop timeout | At least 90 s, so queued mail drains on a stop signal. The application refuses to start without its origin secret |
| Operator tool | `account create/assign/suspend/show`, `issue`, `revoke`, `session revoke`, `release lint/publish/set-access`, `report --account`, `audit export`; runs on an administrator's machine against DynamoDB, S3 and SES's suppression list |

- Tests run against DynamoDB Local, a stub SES and a **real headless browser**, with an
  injected clock. Every AT marked "CI" below is part of the suite, **including its negative**.
- Review before P5: codex-1 on correctness, a security review of the request handling, and
  claude-core against the spec.
- Rollback: none; nothing is deployed in P2.

### P3. Substrate (Overcast, staging)

**P3a (before P2's first push):** the ECR repository in `module.ecr`'s list and the push-role
entry in `local.ecr_push_roles` (`main` only).

**P3b:**
1. `terraform/modules/vpc`: an optional DynamoDB gateway endpoint on the private app route
   table, and optional endpoint policies (both default off, so the prod root's plan does not
   change); staging adds `email` to `extra_interface_endpoints`, turns the gateway on and
   sets a policy on each of the two new endpoints.
2. Eight DynamoDB tables (deletion protection, point-in-time recovery, TTL where the spec
   says).
3. The payload bucket and its policy (`prevent_destroy`, versioning, Object Lock if D10 says
   so, the denials in the spec).
4. The origin-secret shell (D15; no value in Terraform, INV-004); the owner writes the value.
5. Task and execution roles (named outside the CI deploy role's `PassRole` patterns); the
   log group (retention per D10).
6. The service's security group and rules; the target group with its health check on 8081;
   the listener certificate; the listener rule at an explicit priority; the ALB's egress
   rules; the service at **desired count 0** on a placeholder task definition, its desired
   count a variable.
7. Alarms: target 5xx, unhealthy target, send volume, failures per address, release
   verification failure, `mail_failed`.
8. Cloudflare, read back and recorded in the service registry by rule type: the proxied
   record, the cache rule, the configuration rule, the two header rules (strip `NEL` and
   `Report-To`; set the origin secret), the rate-limiting rule.
9. `terraform-plan.yml` gains two `TF_VAR_` lines fed from repository **secrets**; the two
   variables are `sensitive` and appear in no resource address, name or tag.

- **Expected-plan gate** (`scripts/plan_guard.py`, then by eye): additions, the vpc module's
  new endpoint resources, and **one in-place update**: the CI deploy role's image-read list
  gains the new repository (`iam-github-oidc/main.tf:122-130`). **No other change or
  replacement on any Core, ShuttleForge, Nerfherder, RDS, listener-default or existing
  endpoint resource.** The prod and Backstage roots plan "No changes".
- Applied locally by an administrator on the owner's go (DR-1).
- Acceptance, with the service at 0: **AT-9** (bucket half), **AT-15**, **AT-17** and
  **AT-18** (neighbours unchanged). The probes are one-off tasks in the service's security
  group, run by an administrator (the internal-TLS probe pattern, O-018).
- Rollback: targeted destroy in reverse order (Cloudflare rules, listener rule, certificate
  attachment, service, target group, groups, roles, endpoints). Empty tables and an empty
  bucket can be destroyed at this phase only, by lifting their protection deliberately;
  after P4 the spec's RB4 applies and they stay.

### P4. First release (Payload, operator)

1. Payload, then commit with a clean tree:
   - replace the map per D4 and delete the map library;
   - turn the client-side download into a link to `/d/<file>` and drop or accept the copy
     button (payload finding 1);
   - reduce the page's data bundle per D3b;
   - settle the JSON per D3;
   - move the one inline style into a stylesheet; make every referenced file exist;
   - confirm no other copy of the site is published (payload finding 3).
2. Operator: `release lint` on the build output; fix and repeat until clean. The owner signs
   off the lint's review list (internal names, identifiers, addresses, numbers, hyperlinks);
   the sign-off is recorded in the manifest.
3. Operator: `release publish` from the clean commit. The release id, the manifest SHA-256
   and the source commit go into the owner's private receipt, **not into this repository**:
   both hashes appear inside every stamped download.
4. The release is published **inaccessible**.

- Acceptance: **AT-6** (lint half) and **AT-10**'s storage and pin half (the recorded pin, and the
  refused overwrite, delete, lifecycle rule and versioning suspension). AT-10's serving half
  needs the service and runs in P5.
- Rollback: flag the release inaccessible. Nothing is deleted (A4); a corrected site is a new
  release.

### P5. Staging acceptance (Overcast, App, Owner)

1. Deploy the reviewed image by digest (manual, an administrator, the owner's go). Set the
   desired-count variable to 1 first, then the service.
2. Create a test account with the owner as its only person; flag the release accessible;
   issue a test token to the owner's own address.
3. Run every AT below against the public hostname. The one-hour expiry is waited out for
   real, once.
4. The owner reads the received mail in a real mailbox: where it landed, how it looks, and
   whether the visible stamp shows on the page.
5. Flag the release inaccessible; desired count 0 (variable and service); keep the test
   account as the first entry in the record.

- Gate: every AT passes, or the failure is fixed and the affected ATs re-run. The owner
  signs off.
- Rollback: the spec's RB2 (revoke everything, desired count 0).

### P6. First live share (Owner)

Precondition: SES production access granted (D13); P5 signed off.

1. `account create`, then assign the organisation, the domain and the person.
2. `release set-access --accessible`; `issue` to the person; give them the token **by a
   channel other than email**, and tell them a mail from our sender will follow their request.
3. Desired count 1 (variable, then service; D11). Watch the log group and the alarms.
4. When the session's hour has ended, or the token has expired without being activated:
   `release set-access --inaccessible`; desired count 0; `report --account` exported into the
   owner's records, which is the long-lived evidence of what was served. **Never while a
   session is live:** a token activated just before its expiry still runs its full hour.

- Rollback: RB0 (revoke the token) or RB2 at any moment. What was downloaded stays downloaded.

### P7. Follow-ups (tracked here; none gates P6)

| Item | Trigger |
|---|---|
| DR-21 origin client certificates cover this hostname; D15's header and shell are then removed | DR-21's spec |
| Endpoint policies on the shared staging endpoints (S3, Logs, ECR, Secrets Manager) | DR-24; touches every staging service |
| CloudTrail data events on these tables and this bucket, for a record of operator actions the operator did not write | A second operator, or the owner's call; changes the shared account trail. A second independent operator also reopens D-059 §5's same-account acceptance |
| The Cloudflare Terraform root adopts the page record, the mail records and the rules | Next action 4 in `docs/PROJECT_STATE.md` |
| `deploy-service.yml` learns this service (digest check plus target health); needs a deliberate `PassRole` grant | Second release of the application |
| Per-message delivery log from SES (an EventBridge destination) | First bounce that needs explaining |
| Visible per-page PDF watermark; invisible fingerprint | A leak, or the owner's call |
| Zone minimum TLS 1.2, Always Use HTTPS | The `cloudflare-adoption` branch's zone hardening |
| A platform home (D-series) | Complex's answer under D1 |

## Acceptance tests

Every security claim has a **discriminating negative**: a case that must fail, proving the
check can tell the difference. Where a positive would add nothing it is left out. "CI" runs
in the application's suite (no Cloudflare in front, so anything proven there is the
application's own doing); "S" runs on staging, at the phase named or in P5.

| # | Claim | Positive | Discriminating negative | Where |
|---|---|---|---|---|
| AT-1 | The response to a submission does not depend on the details (R2, T4) | Valid, wrong-token, right-token-wrong-address, expired, revoked, suspended, exhausted, inaccessible-release and unknown submissions return the same status, header set and body bytes, with a cookie of the same length; 200 timed samples per case pass a two-sample KS test at 0.01 (fixture tokens with raised budgets; the harness is exempt from the per-IP limit) | The same harness, run against a build that answers invalid submissions 150 ms sooner, and one that changes one body byte, **must fail** | CI; S (bytes, three cases) |
| AT-2 | A token works only for its exact address (R6, A2) | The bound address in different letter case gets a link | Another address at the same domain, a plus-tagged or dotted variant, and an address on the account's domain with no token get **no mail and no link** (send count unchanged) | CI; S |
| AT-3 | A `GET` never consumes the link (R4, T1) | Ten `GET`s and a `HEAD` from a cookieless client leave the link usable; the original browser's click then starts the session | A `POST` from the cookieless client with no token **starts nothing**; a request marked `Sec-Purpose: prefetch` is refused and logs no view or download | CI; S |
| AT-4 | Links are single-use, superseded and useless when forwarded; a session has one authority; a lost response does not burn the activation (T5, T6, T17, T20) | Opened in another browser, the link asks for the token and accepts the right one. After a simulated lost response, a second `POST` with the same proof gets **the same cookie and the same end time**. Fifty concurrent `POST`s with the binding count **one activation** and return one cookie; with the first response delayed until after the second, the browser's cookie still works for the rest of the hour. The cookie-path and token-path cookies for one session differ, and both work | Refused: a re-attach after the hour; one without a binding factor; one with **another valid, unexpired token** that is not this link's; the first link after a second was requested; fifty concurrent `POST`s without a factor. `activations_used` is never above 1. An activation of the first link racing a request for a second ends with one or the other, never both. **A cookie the harness computes from the nonce and the tables' contents is refused** | CI; S (lost response, forwarding, supersession) |
| AT-5 | One hour from the click, once (R5, A1) | The session serves at start + 59 min 50 s; the cookie's `Max-Age` matches the time left; the open page reloads itself at the end; a token activated one minute before its expiry still serves its full hour | It refuses at start + 60 min 1 s; 100 requests leave the end unchanged; **a re-attach by the other binding factor at + 59 min also refuses at + 60 min 1 s** (no fresh hour); a link request after activation sends **no mail** and no second session can start on the token; a session record whose start is in the future, or after its token's expiry, is refused; a download still streaming at the end is cut | CI (clock); S (real wait) |
| AT-5b | Nothing is cacheable, indexable or reported elsewhere (R7, T7, T9, T10) | Every application response class (200, 303, 403, 404, 429; landing, click, asset, PDF, download) carries `no-store, no-transform`, `X-Robots-Tag: noindex` and `Referrer-Policy: same-origin`, as received **through Cloudflare**; HTML carries the robots meta tag and `/robots.txt` disallows everything | A repeated request for the same PDF never returns `cf-cache-status: HIT`; **no response carries `NEL` or `Report-To`**; the header checker **must fail** on a fixture route that omits a header | CI; S |
| AT-6 | No third-party request, including ones Cloudflare might inject (R8, T10) | A headless browser with a live session loads every HTML page in the manifest through the public hostname; every request it makes is to that hostname | **Any request to another host or any CSP violation fails the crawl.** `release lint` **rejects** fixtures containing a tile URL, a remote font, an analytics beacon and a service worker; a fixture page with a remote image makes the crawl **fail** | CI; S |
| AT-6b | The landing and click pages load nothing else | Each is a single response with zero subresource requests | — (AT-6's fixture) | CI; S |
| AT-7 | Attempts are rate-limited by the application, the limit is no oracle, and it cannot lock a recipient out (R3, T2, T3, T4, T11) | The sixth submission from one IP in 15 minutes gets 429, and the twenty-first in a day; the per-address failure alarm fires at its threshold. After six failed submissions for the recipient's address from other IPs, the rightful submission from a fresh IP **still gets its link**, and a wrong pair for that address **still gets the ordinary 200** | The sixth submission from one IP carrying a **valid** token gets 429 and **no mail**; two addresses in one IPv6 /64 share a limit; a request with no `CF-Connecting-IP` gets 404 and is not counted; the tool draws tokens from the operating system's random source (shown in code review; the test checks length and alphabet) | CI |
| AT-8 | The mail budget's four invariants hold (T3) | Three link requests on a valid token send three mails, and **the link in the third mail still starts the session**. A reservation whose send never happened stops counting: with the budget full of young reservations a submission at + 119 s sends none, and at + 121 s sends one. A task killed with the last permitted mail queued, or a link superseded before either mail went out, costs the recipient one retry and no budget | The fourth mail is never sent in normal running; an address with no token is never mailed. **The stub SES accepts but loses its response: no retry follows and no second copy is sent.** A write conflict injected while an accepted send is being recorded is retried and the send is counted **once**. A send held until its reservation is 61 s old is **never attempted**; forced to be accepted after two minutes, it does not charge the slot a later request reserved, and that later request's mail still goes out. Two submissions racing for the last mail reserve it once | CI; S (three mails, third link) |
| AT-9 | Every asset needs the session; no object is public (R7, T8) | With a valid session every unstamped manifest path returns its pinned hash (stamped paths: AT-13) | Every manifest path returns the neutral 404 with no cookie and with an expired cookie. **Another release's session never receives this release's bytes**: a path only this release has returns 404, and a path both releases share returns the session's own release (fixtures with distinct content). An anonymous S3 request for each object gets 403; a signed request by a role that is neither the task role nor a named administrator gets `AccessDenied`; the task role gets `AccessDenied` on an object tagged inaccessible, on tagging and on reading a specific version, and drops its local copy when a release is flagged; no response contains `X-Amz-Signature` | CI; S (bucket half at P3) |
| AT-10 | The payload is pinned and never retired (R12, A4, T18) | `releases.manifest_sha256` equals the recorded pin. After flag-inaccessible, flag-accessible and a reissued token, the unstamped served hashes equal the first share's | One flipped byte in a fixture release makes the application **refuse that release and alarm**, while another release still serves. An administrator's overwrite of an existing key, delete, lifecycle rule and versioning suspension all get `AccessDenied`. Flag-inaccessible makes a live session refuse at its next request while object version ids are unchanged | CI; S (pin and refusals at P4; serving at P5) |
| AT-11 | The session cookie cannot be read or sent in clear (T6) | `__Host-` prefix, `Secure`, `HttpOnly`, `SameSite=Lax`, `Path=/`, no `Domain`; with a live session a second click on the mailed link lands on the content | `document.cookie` is empty in the headless browser; a plain-HTTP request gets a 301 and **no `Set-Cookie`** | CI; S |
| AT-12 | No other site can post the forms or force a download (T16) | **A real browser submitting the real form succeeds** (this is the test that catches a wrong referrer policy) | A `POST` with `Origin: null`, with a foreign origin, with a sibling subdomain's origin, or without `Sec-Fetch-Site: same-origin` gets 403 and changes and counts nothing; a cross-site link to `/d/` downloads nothing and logs no download; every page sends `frame-ancestors 'none'` | CI |
| AT-13 | The download is stamped with the recipient and the issue time (R10) | The `distribution` member carries the bound address and the token's issue time; the stamped bytes' SHA-256 equals the audit event's; two requests and a ranged request in one session return identical bytes; removing the member reproduces the pinned original byte for byte; the page shows the stamp line **with the address in clear when fetched through Cloudflare**; each PDF carries the fields and begins with the pinned original's bytes | A download under a second token **issued to a different address** never contains the first token's address | CI; S |
| AT-14 | SPF, DKIM and DMARC pass, aligned (R11, T15) | Test 3: `spf=pass` with the envelope sender under the mail subdomain, `dkim=pass` with `header.d` equal to the From domain, `dmarc=pass`; DNS shows `p=reject`; no record at the `arclightlabs.io` apex changed (before and after listing); if D12 is approved, `arclight-complex.net` shows the null SPF and `p=reject` | Test 1 (before the custom MAIL FROM) shows the envelope sender under `amazonses.com`, and the same header check **must fail** on it. Test 2 (MAIL FROM set, MX absent): SES **refuses** the send instead of falling back | S (P1) |
| AT-14b | The mail is what it should be | In the P5 mail's source: the link's host is the public hostname; no images; a `Reply-To` that reaches the owner. Any rewriting seen in the mailbox is the mailbox provider's, and is noted | — | S (P5) |
| AT-15 | The service has no path out or sideways (O-017, T13) | From a probe task in the service's group: SES, DynamoDB, S3, ECR, Logs and Secrets Manager connect | TCP 443 to `1.1.1.1` and a pinned Cloudflare address, 5432 to RDS, and 443 to Core's NLB all **time out**, while each of those targets **connects** from a group allowed to reach it (the internet targets from a group with egress; RDS and Core's NLB from groups that already use them), so a timeout means the rule, not a dead target | S (P3) |
| AT-16 | The codename reaches the recipient nowhere (T19) | — | A search of **every** response body (access pages and payload alike), header, cookie name and file name, and of the received mail's headers and body, for the codename finds **nothing**; a seeded fixture string makes the search **fail** | CI; S |
| AT-16c | The access pages and the mail are nondescript (R1) | — | A search of the **unauthenticated surface only** (landing, click, access-code, neutral and error pages; every response's headers, cookie names and download file name) and of the mail, for the product and module names, the recipient's name and organisation (supplied at test time) and the payload's subject finds **nothing**; a seeded fixture string makes it **fail**. The payload's own bodies are out of scope: they are about the subject, and the stamp carries the recipient's address by design (AT-13) | CI; S |
| AT-16b | The host cannot be forged into a link (T12) | — | Any other `Host` gets 404; a forged `Host` or `X-Forwarded-Host` on a submission never appears in the mailed link | CI |
| AT-17 | The task role can do only what the spec lists, and only from the VPC (T13) | From a probe task running as the task role, the application's own calls succeed: a submission transaction, an activation transaction and `SendEmail` through the endpoint | `Scan` and **any write** on `tokens` (the grant); get, update or delete on `audit`; any call on `accounts`; `PutItem` on `releases`; `PutObject`, `DeleteObject`, tagging and version reads on the bucket; `SendEmail` with another From address: all `AccessDenied` (policy simulation for the full matrix, including a request context outside the endpoints; three live calls) | S (P3) |
| AT-18 | Nothing else on staging changed (blast radius) | At P5: the public hostname returns the landing page and is **not** redirected to Access | At P3 and again at P5: `core.staging…` **is** still redirected to Access without a token, and returns `/ready` 200 with one; the listener's default certificate and rules 2 and 10 are unchanged | S |
| AT-19 | Who, when, from where and what are logged (R9) | After P5, `report --account` shows the submission (address, name, IP), the mail (SES id), each link open, the session start and end, every path served and each stamped hash; each event is also in CloudWatch | A request sent through Cloudflare with a forged `X-Forwarded-For` is logged with the **test client's real address** as its IP; one with a forged `CF-Connecting-IP` is refused by Cloudflare and never arrives; a failed submission's CloudWatch line carries no typed address or name | S |
| AT-20 | Tokens are tracked under accounts (A3, D14) | `report --account` lists both the original and the reissued token | `issue` to an address that is not a person on the account, outside its domains without the override, or on the SES suppression list is **refused**; `issue` into a suspended account is **refused**, and a token issued a moment before the suspension is stamped by it, **even when the account index lags the table** (the fixture delays it); suspending the account makes a live session refuse within seconds | CI; S |
| AT-21 | Revocation is immediate, for a token and for a single session (R6) | A token revoked **between** the activation's read and its write still loses: the transaction's condition check on the grant fails | Three fixtures, since one token cannot hold all of them. Straight after `revoke`: a token with a live session gets the neutral 404 at its next request, and a token with an unconsumed, otherwise valid link has that link refused. Straight after `session revoke`: its requests get 404, and **a `POST` with the binding factor that had not yet been used is refused**; a `session revoke` racing that `POST` always ends revoked | CI; S |
| AT-22 | Health is not public | The target is healthy on port 8081 | `https://<page-host>/ready`, in any letter case of the host, returns the neutral 404 | S (P5) |
| AT-23 | Only our own Cloudflare zone reaches the logic (D15, T11) | Through the public hostname everything works; during a rotation both values are accepted | A request **without** the origin secret, with a **wrong** one, and with a value **retired** after rotation each gets the neutral 404 and causes no lookup, no limit count and no audit event; the application refuses to start with an empty or missing secret | CI; S (rule read-back) |
| AT-24 | Nothing identifying reaches this public repository or its CI (T19, D8) | — | A search of **every commit** on the branch (including content added and later removed), every pull-request ref, the plan job's log and summary, and the pull request's comments, for the hostname, the mail subdomain, the mailboxes, the recipient's identifiers and the release hashes (supplied privately, on the operator's machine) finds **nothing**. It runs **before the first push** of any change that could carry them, before the P3 pull request merges, and again at P5. A value added and then removed in a scratch branch makes it **fail** | S |
| AT-25 | No secret is at rest or in a log (T6, T13) | — | After a full flow, a search of every table item and every log line for the plaintext token, nonce, binding cookie, session identifier and origin secret, and for `Cookie` and `Referer` header values, finds **nothing**; a seeded value makes it **fail** | CI; S |

Not testable, and said so:
- **The recipient's mail gateway.** AT-3 and AT-4 simulate the known scanner behaviours; the
  real gateway is first met in P6. That is why D6, the re-attach and three link emails per
  token exist.
- **Another Cloudflare account's zone reaching the ALB** (DR-21) cannot be staged without
  such a zone. AT-23's CI negative is the evidence that the application refuses it.
- **The 90-day expiry and the two-year retention** are configuration read-backs (TTL
  attributes, log-group retention), not waited out.
- **The endpoint policies' refusal of another account's credentials** needs a second AWS
  account to exercise. Until one exists the evidence is the policy documents read back.
