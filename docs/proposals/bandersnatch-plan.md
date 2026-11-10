# Bandersnatch: phased plan and acceptance tests

Status: **Revision 1, draft for the owner's review.** Companion to the
[spec](bandersnatch.md). Nothing here is scheduled: every phase waits on the owner's ruling
on the spec's decisions, and every state change waits on the owner's go, given first-hand.

Parties: **Owner**; **Overcast** (substrate, DNS, mail identity); **App** (the hosted
application's own repository and session, spec D1); **Payload** (the repository the first
payload is built from).

## Phases

| Phase | Who | What | Gate to leave |
|---|---|---|---|
| P0 | Owner | Rulings, names, prerequisites | Rulings recorded as an O-decision |
| P1 | Overcast | Mail domain | AT-14 |
| P2 | App | Build the application and its operator tool | App test suite, including every negative below; code review |
| P3 | Overcast | Substrate on staging, service at desired count 0 | Expected plan; AT-9 (bucket), AT-15, AT-17, AT-18 |
| P4 | Payload, operator | First release: map fix, JSON choice, pin, publish | AT-6 (lint), AT-10 |
| P5 | Overcast, App, Owner as the test recipient | Staging acceptance, end to end | Every AT passes; the owner's sign-off |
| P6 | Owner | First live share | The owner's go |
| P7 | Overcast | Follow-ups (tracked, not gating) | — |

P1 and P2 can run in parallel once P0 is done. P3a (the ECR repository and push role) comes
before P2's first push.

### P0. Rulings and prerequisites (Owner)

1. Rule on D1-D14 in the spec. Overcast records the outcome as **O-019** in
   `docs/DECISIONS.md` and tells Complex (the O-012 pattern).
2. Choose, and keep out of git: the public hostname, the mail subdomain, the page title and
   the sender's display name. They go into the gitignored `terraform.tfvars` and into
   repository variables for `terraform-plan.yml`.
3. Create the application's private repository.
4. **Submit the SES production-access request** (console or `aws sesv2 put-account-details`;
   AWS answers within 96 hours). Draft use case, for the owner to edit and send:
   > Transactional mail only: single-use access links sent to named business contacts who
   > have just requested one on our site with a code we issued to them. No marketing, no
   > lists. Expected volume: under 50 messages a day. Bounces and complaints are handled by
   > the account-level suppression list and CloudWatch alarms; every recipient is
   > individually invited.
5. In the Cloudflare dashboard, read the zone's Web Analytics and Zaraz state (the API token
   cannot) and tell Overcast.

Rollback: none needed; nothing exists yet.

### P1. Mail domain (Overcast)

1. Terraform (staging root): SES domain identity for the mail subdomain with Easy DKIM
   (RSA 2048); custom MAIL FROM `bounce.<mail-domain>` with reject-on-MX-failure; a
   configuration set with reputation metrics and a CloudWatch event destination; email
   feedback forwarding off; alarms on bounces, complaints and sends.
2. Cloudflare, DNS-only records, written with the Terraform token and read back: three DKIM
   CNAMEs, the MAIL FROM MX and SPF TXT, the subdomain's DMARC TXT. If D12 is approved: the
   apex null SPF and `p=reject` DMARC. Recorded in `docs/service_registry.md` by name only.
3. Wait for SES to report the identity, DKIM and MAIL FROM as verified (AWS can take up to
   72 hours to see the MX).
4. Verify the owner's own address as a sandbox recipient (it mails the owner, nobody else)
   and send one test message with `aws sesv2 send-email`.

- Expected plan: additions only (identity, DKIM, MAIL FROM, configuration set, event
  destination, three alarms). No change to any existing resource.
- Acceptance: **AT-14**.
- Rollback: destroy the SES resources; delete the DNS records. Nothing else depends on them.

### P2. Application (App)

Overcast hands over the interface; App owns everything behind it.

| Interface | Value |
|---|---|
| Listens | 8080, HTTP, non-root, read-only root file system |
| Health | `/ready`: 200 when every accessible release verifies and DynamoDB answers; 503 otherwise; not served for the public `Host` |
| Configuration (environment) | public host, sender address and display name, page title, table names, payload bucket, SES configuration set, region |
| AWS access | The task role in the spec's IAM section; no secrets, no static keys |
| Egress | Exactly the spec's network table; **no internet** |
| Image | `arclight/bandersnatch`, tag `v1-<sha>`, immutable; deployed by digest |
| Logs | JSON lines on stdout; never a token, nonce or session identifier |
| Operator tool | `account create/assign/suspend/show`, `issue`, `revoke`, `session revoke`, `release lint/publish/set-access`, `report --account`, `audit export`; runs on an administrator's machine against DynamoDB and S3 |

- Tests run against DynamoDB Local, a stub SES and a headless browser, with an injected
  clock. Every AT marked "CI" below is part of the suite, **including its negative**.
- Review before P5: codex-1 on correctness, a security review of the request handling, and
  claude-core against this spec.
- Rollback: none; nothing is deployed in P2.

### P3. Substrate (Overcast, staging)

**P3a (before P2's first push):** the ECR repository in `module.ecr`'s list and the push-role
entry in `local.ecr_push_roles` (`main` only).

**P3b:**
1. `terraform/modules/vpc`: an optional DynamoDB gateway endpoint on the private app route
   table (default off, so the prod root's plan does not change); staging adds `email` to
   `extra_interface_endpoints` and turns the gateway on.
2. Seven DynamoDB tables (deletion protection, point-in-time recovery, TTL where the spec
   says).
3. The payload bucket and its policy (`prevent_destroy`, versioning, deny-delete).
4. Task and execution roles; the log group (retention per D10).
5. The service's security group and rules; the target group; the listener certificate; the
   listener rule at an explicit priority; the ALB's egress rule; the service at **desired
   count 0** on a placeholder task definition.
6. Alarms: target 5xx, unhealthy target, send volume, release verification failure.
7. Cloudflare, read back and recorded in the service registry: the proxied record (Terraform
   token), the cache rule and the configuration rule (the token if it has the permission,
   otherwise the owner in the dashboard).
8. `terraform-plan.yml` gains the two `TF_VAR_` lines for the names.

- **Expected-plan gate** (`scripts/plan_guard.py`, then by eye): additions only, plus the vpc
  module's two new endpoint resources. **Zero changes or replacements on any Core,
  ShuttleForge, Nerfherder, RDS, ALB-listener-default or existing endpoint resource.** The
  prod and Backstage roots plan "No changes".
- Applied locally by an administrator on the owner's go (DR-1).
- Acceptance: **AT-9** (bucket half), **AT-15**, **AT-17**, **AT-18**, **AT-22**.
- Rollback: targeted destroy in reverse order (rule, certificate attachment, service, target
  group, groups, roles, endpoints). Empty tables and an empty bucket can be destroyed at this
  phase only, by lifting their protection deliberately; after P4 the spec's R3 applies.

### P4. First release (Payload, operator)

1. Payload, then commit with a clean tree:
   - replace the map per D4 and delete the map library;
   - turn the client-side download into a link to `/d/<file>` and drop or accept the copy
     button (payload finding 1);
   - reduce the page's data bundle per D3b;
   - settle the JSON per D3;
   - move the one inline style into a stylesheet; make every referenced file exist.
2. Operator: `release lint` on the build output; fix and repeat until clean. The owner signs
   off the lint's review list (internal names, identifiers, addresses, numbers); the sign-off
   is recorded in the manifest.
3. Operator: `release publish` from the clean commit. Record the release id, the manifest
   SHA-256 and the source commit in the owner's private receipt (the hashes may also go in
   `docs/PROJECT_STATE.md`; they identify nothing).
4. The release is published **inaccessible**.

- Acceptance: **AT-6** (lint half), **AT-10**.
- Rollback: flag the release inaccessible. Nothing is deleted (A4); a corrected site is a new
  release.

### P5. Staging acceptance (Overcast, App, Owner)

1. Deploy the reviewed image by digest (manual, an administrator, the owner's go); desired
   count 1.
2. Create a test account with the owner as its only person; flag the release accessible;
   issue a test token to the owner's own address.
3. Run every AT below against the public hostname. The one-hour expiry is waited out for
   real, once.
4. Flag the release inaccessible; desired count 0; keep the test account as the first entry
   in the record.

- Gate: every AT passes, or the failure is fixed and the affected ATs re-run. The owner
  signs off on the result and on the received mail's appearance.
- Rollback: the spec's R1 (revoke everything, desired count 0).

### P6. First live share (Owner)

Precondition: SES production access granted (D13); P5 signed off.

1. `account create`, then assign the organisation, the domain and the person.
2. `release set-access --accessible`; `issue` to the person; give them the token **by a
   channel other than email**.
3. Desired count 1 (D11). Watch the log group and the alarms.
4. After the hour, or at the token's expiry: `release set-access --inaccessible`; desired
   count 0; `report --account` into the owner's records.

- Rollback: R0 (revoke the token) or R1 at any moment. What was downloaded stays downloaded.

### P7. Follow-ups (tracked here; none gates P6)

| Item | Trigger |
|---|---|
| DR-21 origin client certificates cover this hostname | DR-21's spec |
| The Cloudflare Terraform root adopts the page record, the mail records and the two rules | Next action 4 in `docs/PROJECT_STATE.md` |
| `deploy-service.yml` learns this service (digest check plus target health; no public `/ready`) | Second release of the application |
| DMARC aggregate reporting (`rua`) | A mailbox exists to receive it |
| Visible per-page PDF watermark; invisible fingerprint | A leak, or the owner's call |
| Zone minimum TLS 1.2, Always Use HTTPS | July's zone hardening |
| A platform home (D-series) | Spec D1's trigger |

## Acceptance tests

Every security claim has a positive check and a **discriminating negative**: a case that must
fail, proving the check can tell the difference. "CI" runs in the application's suite; "S"
runs on staging in P3 or P5.

| # | Claim | Positive | Discriminating negative | Where |
|---|---|---|---|---|
| AT-1 | The response to a submission does not depend on the details (R2, T4) | Valid, wrong token, right token with another address, expired, revoked, exhausted and unknown submissions return the same status, header set and body bytes, with a cookie of the same length; 200 timed samples per case differ by under 20 ms at the median and pass a two-sample KS test at 0.01 | The same harness, run against a build that deliberately answers invalid submissions 150 ms sooner, and one that changes one body byte, **must fail** | CI; S (bytes, three cases) |
| AT-2 | A token works only for its exact address (R6, A2) | The bound address in different letter case gets a link | Another address at the same domain, a plus-tagged or dotted variant, and an address on the account's domain with no token get **no mail and no link** (SES send count unchanged) | CI; S |
| AT-3 | A `GET` never consumes the link (R4, T1) | Ten `GET`s and a `HEAD` from a cookieless client leave the link usable; the original browser's click then starts the session | A `POST` from the cookieless client with no token **starts nothing** and leaves the link usable | CI; S |
| AT-4 | Links are single-use, superseded and useless when forwarded (T5, T17) | Opened in another browser, the link asks for the token and accepts the right one | A second `POST` after activation, the first link after a second was requested, the forwarded link with a wrong token, and 49 of 50 concurrent `POST`s are **all refused**; exactly one session exists | CI; S (first three) |
| AT-5 | One hour from the click, once (R5, A1) | The session serves at start + 59 min 50 s; the cookie's `Max-Age` is 3600 | It refuses at start + 60 min 1 s; 100 requests leave `expires_at` unchanged; a link request after activation sends **no mail** | CI (clock); S (real wait) |
| AT-5b | Nothing is cacheable or indexable (R7, T7, T9) | Every response class (200, 303, 403, 404, 429; landing, click, asset, PDF, download) carries `no-store, no-transform` and `X-Robots-Tag: noindex`, as received **through Cloudflare** | A repeated request for the same PDF never returns `cf-cache-status: HIT`; the header checker **must fail** on a fixture route that omits the header | CI; S |
| AT-6 | No third-party request, including ones Cloudflare might inject (R8, T10) | A headless browser with a live session loads every HTML page in the manifest through the public hostname; every request it makes is to that hostname | `release lint` **rejects** fixtures containing a tile URL, a remote font and an analytics beacon; a fixture page with a remote image makes the crawl **fail** | CI; S |
| AT-6b | The landing and click pages load nothing else | Each is a single response with zero subresource requests | — (covered by AT-6's fixture) | CI; S |
| AT-7 | Attempts are rate-limited by the application itself, and the limits cannot lock a recipient out (R3, T2, T3, T11) | The sixth submission from one IP in 15 minutes gets 429; after six failed submissions for the recipient's address from other IPs, the **rightful submission from a fresh IP still gets its link** | The sixth submission from one IP carrying a **valid** token still gets 429 and **no mail**; the sixth failed submission for an address gets 429 whether or not the address is known; the limits hold when the task is called from inside the VPC, bypassing Cloudflare | CI; S |
| AT-8 | The form cannot be used to send mail at will (T3) | Three link requests on a valid token send three mails | The fourth sends **none**; an address with no token is never mailed | CI; S |
| AT-9 | Every asset needs the session; no object is public (R7, T8) | With a valid session every manifest path returns its pinned hash | Every manifest path returns the neutral 404 with no cookie, an expired cookie and another release's session; an anonymous S3 request for each object gets 403; a signed request by a role other than the task role gets `AccessDenied`; no response contains `X-Amz-Signature` | CI; S |
| AT-10 | The payload is pinned and never retired (R12, A4, T18) | `releases.manifest_sha256` equals the recorded pin; after flag-inaccessible then flag-accessible and a reissued token, the served hashes equal the first share's audit hashes | One flipped byte in a fixture release makes the application **refuse it and fail `/ready`**; flag-inaccessible makes a live session refuse at its next request while object version ids are unchanged; an administrator's `DeleteObject` gets `AccessDenied` | CI; S |
| AT-11 | The session cookie cannot be read or sent in clear (T6) | `__Host-s`: `Secure`, `HttpOnly`, `SameSite=Lax`, `Path=/`, no `Domain`; with a live session a second click on the mailed link lands on the content | `document.cookie` is empty in the headless browser; a plain-HTTP request gets a 301 and **no `Set-Cookie`**; a cross-site `POST` carries no session | CI; S |
| AT-12 | No cross-site request changes state (T16) | Same-origin `POST`s work | A `POST` with a foreign or missing `Origin` gets 403 and changes nothing; a cross-site auto-submitting form starts no session; every page sends `frame-ancestors 'none'` | CI |
| AT-13 | The download is stamped with the recipient and the issue time (R10) | The `distribution` member carries the bound address and the token's issue time; the stamped bytes' SHA-256 equals the audit event's; removing the member reproduces the pinned original byte for byte; every HTML page shows the footer; each PDF carries the fields and its first revision hashes to the pinned original | A download under a second token **never contains the first token's address** | CI; S |
| AT-14 | SPF, DKIM and DMARC pass, aligned (R11, T15) | A received message shows `spf=pass` with `smtp.mailfrom` under the mail subdomain, `dkim=pass` with `header.d` equal to the From domain, `dmarc=pass`; DNS shows `p=reject`; the link's host is the public hostname; no images | A message sent **before** the custom MAIL FROM is attached shows `smtp.mailfrom` under `amazonses.com`, and the same header check **must fail** on it; with the MX record absent SES **refuses** the send instead of falling back | S (P1) |
| AT-15 | The service has no path out or sideways (O-017, T13) | From a probe task in the service's group: SES, DynamoDB, S3, ECR and Logs connect | TCP 443 to `1.1.1.1` and a pinned Cloudflare address, 5432 to RDS, and 443 to Core's NLB all **time out** | S (P3) |
| AT-16 | Nothing the recipient receives names the product, the codename or them (R1, T19) | — | A search of every response body, header, cookie name and file name, and of the received mail's headers and body, for the codename, module names, the recipient's name and organisation (supplied at test time) and the payload's subject finds **nothing**; a seeded fixture string makes the search **fail** | CI; S |
| AT-16b | The host cannot be forged into a link (T12) | — | Any other `Host` gets 404; a forged `Host` or `X-Forwarded-Host` on a submission never appears in the mailed link | CI |
| AT-17 | The task role can do only what the spec lists (T13) | The application works with it | `Scan` on `tokens`; get, update or delete on `audit`; any call on `accounts`; `PutItem` on `releases`; `PutObject` and `DeleteObject` on the bucket; `SendEmail` with another From address: all `AccessDenied` (policy simulation for the full matrix, three live calls from a probe task) | S (P3) |
| AT-18 | Nothing else on staging changed (blast radius) | The public hostname returns the landing page and is **not** redirected to Access | `core.staging…` **is** still redirected to Access without a token, and returns `/ready` 200 with one; the listener's default certificate and rules 2 and 10 are unchanged before and after | S (P3) |
| AT-19 | Who, when, from where and what are logged (R9) | After P5, `report --account` shows the submission (address, name, IP), the mail (SES id), each link open, the session start and end, every path served and the download's stamped hash; each event is also in CloudWatch | A request sent through Cloudflare with forged `CF-Connecting-IP` and `X-Forwarded-For` headers is logged with the **test client's real address**; an unmatched submission is logged with its internal outcome | S |
| AT-20 | Tokens are tracked under accounts (A3, D14) | `report --account` lists both the original and the reissued token | `issue` to an address that is not a person on the account, or outside its domains without the override, is **refused**; suspending the account makes a live session refuse | CI; S |
| AT-21 | Revocation is immediate (R6) | — | After `revoke`, the next request on a live session gets the neutral 404 and the outstanding link is refused | CI; S |
| AT-22 | Health is not public | The target is healthy in the target group | `https://<page-host>/ready` returns the neutral 404 | S (P3) |

Not testable, and said so: that the recipient's mail gateway treats the link kindly. AT-3 and
AT-4 simulate the known scanner behaviours; the real gateway is first met in P6, which is why
D6 and three link emails per token exist.
