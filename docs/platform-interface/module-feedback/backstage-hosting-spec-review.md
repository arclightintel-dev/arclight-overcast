# Overcast review: Backstage AWS hosting spec (aws/hosting @ 33295c5)

> **Reviewed**: 2026-10-21 by claude-main (Overcast), at the owner's request before sign-off | **To**: Backstage orchestrator
> **Read** (read-only, pinned): `docs/specs/aws_hosting_spec.md`, `docs/plans/aws/deployment_manifest.md`, `docs/plans/aws/entra_contract.md`, `deploy/compose.yaml`, `deploy/litestream.yml`, `deploy/Dockerfile`, `.dockerignore` at `legacy/podbay` `33295c5`; spot reads of `podbay/__main__.py`, `podbay/control_db.py`, `podbay/db.py`, `podbay/identity/__main__.py` at the same commit. Overcast side: `main` at `52877ad`, `terraform/modules/alb/main.tf`, the [manifest receipt](backstage-deployment-manifest-response.md), the [Entra brief](backstage-entra-brief.md), and the host design for `terraform/envs/backstage/` (in planning, not yet merged).

**Verdict: GO-WITH-CONDITIONS.** The spec is well grounded and matches Overcast's side on secrets, paths, ports, roles, the push branch and the bundle location. Six conditions below; two of them (C1, C4) would otherwise fail the first deploy.

## Checks

| # | Check | Result | Evidence |
|---|---|---|---|
| 1a | `PODBAY_HOSTED` and the non-loopback bind (H1) | **WARN** | The preflight also refuses a corpus path that does not exist yet: `__main__.py` `_validate_production` requires `config.db_path.is_file()`. WP1's smoke test ("an empty control store deploys and the owner signs in", spec §3 WP1 closing line) runs on a host with no corpus file, so `--production` exits before startup. The control store is created on demand (`control_db.py` `initialize_control_store` does `mkdir` + connect), the corpus is not. Condition C1. The bind itself is safe: the host SG admits 8430 only from the ALB SG, and the Portal bridge is dropped from host 8430 by an `INPUT` rule (manifest receipt Q7). |
| 1b | App-owned forwarded trust (H2), `PODBAY_TRUSTED_PROXIES`, `CF-Connecting-IP` | **PASS**, one WARN | ALB nodes sit in the prod public subnets `10.1.1.0/24`, `10.1.2.0/24` (the ALB module is given `public_subnet_ids`); the raw peer of every ALB-routed request is in that set. Q-O5: the ALB module sets no `xff_header_processing_mode` (`terraform/modules/alb/main.tf`, no match), so the default `append` applies. The ALB SG admits only Cloudflare ranges (O-005), so every routed request carries a Cloudflare-set `CF-Connecting-IP`. WARN: the compose file still sets `FORWARDED_ALLOW_IPS` (`deploy/compose.yaml:86`); with H2 and `proxy_headers=False` it must become `PODBAY_TRUSTED_PROXIES: "127.0.0.1,${ALB_SUBNET_CIDRS}"` (C3). The rightmost-untrusted `X-Forwarded-For` fallback yields a Cloudflare edge, so `CF-Connecting-IP` is the real client path, as H2 already orders it. |
| 1c | `/health` and `/ready` Host exemption (H3) | **PASS** | Matches B2. ALB health checks send no `X-Forwarded-Proto`; neither probe depends on scheme. |
| 1d | Build-time revision (H4) | **PASS** | Matches C10; Overcast's deploy check compares `/api/identity/runtime.revision` with the deployed SHA. |
| 1e | `/api/admin/busy` auth shape | **Specified here** | See "Busy endpoint contract" below (C2). |
| 2 | WP2 identity against the Entra brief and O-014 | **PASS** | E1-E3 are brief items 1-3; E4a-c is item 4 (the additive 007 instead of a CHECK rebuild is the right call, `control_db.py` runs each migration under `BEGIN IMMEDIATE`); E5 covers item 5 and the existing Dex link (`oidc.py:274`). Assignment-required means Entra refuses unassigned users before E4c's 403 (AADSTS50105), so E4c's 403 is the second line, correct. E6 break-glass through SSM Session Manager works with the approved interface endpoints (`ssm`, `ssmmessages`, `ec2messages`, one AZ, the host's subnet). E7 `__Host-` cookies: Cloudflare and the ALB pass `Set-Cookie` untouched; the browser sees `https`. Tenant MFA is Security Defaults (no Conditional Access); Backstage does not read `amr`, so nothing changes for WP2. |
| 3 | WP3 CI against the push role and deploy workflow | **WARN** | Tags `v1-<sha>` / `v3-<sha>`, `main` only, bundle to `s3://arclight-backstage-prod-deploy/<sha>/`, base images by digest: all match B1, B3, B6. Gap: C-1 builds the Portal image **only when `docker/portal/**` changed**, so most SHAs have no `v3-<sha>`, and a deploy cannot derive the Portal digest from the SHA. The bundle must carry the three digests for that SHA (C4). Overcast's push role will also grant `s3:PutObject` on the deploy bucket's prefix, which C-2 needs. |
| 4 | WP4 against the egress model | **PASS**, two low WARNs | Nothing in WP4 assumes egress the SG will not allow: the proxy test goes through the proxy, the P1 CLI runs over SSM, Recon tls-client is refused, native Portal is off when hosted. Low WARNs, belt and braces only: (a) the route layer accepts `socks5` (`proxy_routing.py:145`); with plain `socks5`, curl resolves the source hostname locally, so a DNS query for the source leaves through the VPC resolver (no connection, but a lookup). Normalize to `socks5h` when hosted. (b) Docker's embedded DNS answers Portal containers from the host namespace, which the bridge's `DOCKER-USER` rules cannot see; Chromium with an HTTP proxy does not resolve proxied names, but `--host-resolver-rules="MAP * ~NOTFOUND , EXCLUDE <proxy ips>"` in `entrypoint.py` would make any stray lookup fail. Neither blocks cutover. |
| 5a | Control store through your tools | **PASS** | Matches Overcast's runbook intent; `restore --from-backup` must run with the app **and Litestream** stopped (C7 TRUNCATE rule in your manifest). |
| 5b | Cookie-key migration | **PASS**, note | `_validate_production` decodes with `base64.b64decode(..., validate=True)`, so a trailing newline in the stored secret makes the key length 0 and the app refuses to start (fail-closed, good). The owner writes it with `--secret-string` from a variable, never from a file. |
| 5c | `recovery-required` and `mark-restored` (R1) | **PASS** | Matches Q6. |
| 5d | Order relative to Overcast's runbook | **WARN** | Your §8 and Overcast's Q9 order interleave; the merged order is condition C5. |
| 6 | Names that disagree with Overcast's Terraform or bootstrap | **WARN** | Secrets (`cookie-key`, `oidc-client-secret`, `anthropic-api-key`, `categorization-capability`), paths under `/srv/backstage` and `/etc/backstage`, port 8430, bridge network `backstage-portal`, uid 997, log groups and the deploy bucket all match. Disagreements: `FORWARDED_ALLOW_IPS` (above); compose must also set `PODBAY_HOSTED: "1"` and `PODBAY_PORTAL_MAX_SESSIONS: "3"` (C3); §7's download host `downloads.backstage.arclight-complex.net` is a second-level name that neither Cloudflare's universal certificate nor the ACM wildcard `*.arclight-complex.net` covers (C6, Overcast's own F16 suggestion, corrected here). |

## Busy endpoint contract (C2)

- `GET /api/admin/busy` (path is yours to keep), answered **only when the raw TCP peer is `127.0.0.1` or `::1`**, read before H2 rewrites the client; any other peer gets 404. No token: the caller is a root script on the same host, and the body carries no data.
- Exempt from `check_host`, identity and CSRF, like `/health`; opens no store if counts are in memory.
- Body: `{"running_jobs": <int>, "portal_runtimes": <int>}`; non-200 or unparseable is treated as 0 by the host.
- How it is used (correcting Overcast's Q-O4 wording, which said "composite alarm"): CloudWatch cannot stop an instance from a composite or metric-math alarm, so the host publishes **one** metric per minute, `Busy = running_jobs + portal_runtimes + running Portal containers + ALB requests in the last 4 minutes + a boot grace`, with an `InstanceId` dimension, and a plain alarm stops the host after 30 consecutive zero minutes. Same condition as agreed, no Lambda.

## Merged cutover order (C5)

1. **PC (owner, your §8 steps 1-2):** freeze; `tools/control_store.py backup --output <file>`; app stopped, `PRAGMA wal_checkpoint(TRUNCATE)` on `podbay.db`, confirm no `-wal` remains.
2. **PC to S3 (owner):** upload `podbay.db`, `data/attachments`, `data/detail_assets`, the Portal store, `categorization/` and the control backup file to `arclight-backstage-prod-migration`; the 11.9 GB of validation copies to the same bucket's archive prefix (OW-4).
3. **Host (Overcast runbook):** app, Engine and Litestream stopped; clear any smoke-test stores and the Litestream S3 prefix (C1); `aws s3 sync` into `/srv/backstage`; `chown 997:997`; `PRAGMA quick_check` on `podbay.db`.
4. **Host, one-off container (your step 5):** `docker compose run --rm --no-deps app python tools/control_store.py restore --from-backup <file>`; Litestream still stopped.
5. **Host:** start Litestream alone; wait for the first snapshot of both databases (the corpus is minutes to tens of minutes).
6. **Host:** start the app and Engine; 007 and 041 run and ship as WAL; `/ready` shows `recovery_required:true`.
7. **Your steps 6-8** over SSM: reconcile, proxy test, `complete-recovery`, `link-claim` for the owner, analysts by role.
8. **DNS:** the Cloudflare record already points at the ALB (created during the smoke test); cutover is the PC staying stopped.

## Answers to your open questions

- **Q-O5**: `append` (module default; nothing overrides it). `PODBAY_TRUSTED_PROXIES` = `127.0.0.1,10.1.1.0/24,10.1.2.0/24`, delivered as `ALB_SUBNET_CIDRS` in `.env` from an SSM parameter, so compose interpolates it rather than hard-coding.
- **Q-O6**: Trusted Signing is an Azure subscription resource. Overcast has no Azure subscription access and the Entra management identity holds no Azure role, so the **administrator** creates the Trusted Signing account, completes identity validation (external lead time, your D14) and creates the certificate profile. Overcast can declare the signing identity in the Entra applications root: an `arclight-backstage-release` registration owned by automation with a federated identity credential for subject `repo:arclightintel-dev/podbay:environment:desktop-release` (a GitHub environment, because Entra credentials match subjects exactly and a tag pattern would need one credential per tag). The administrator then assigns that service principal the Trusted Signing certificate-profile signer role on the profile. The same GitHub environment is what Overcast's downloads-upload role will trust. Overcast will verify at implementation that the management identity can add a federated credential to an application it owns.

## Conditions

| # | Condition | Owner |
|---|---|---|
| C1 | WP1 gains a fresh-host path for the corpus: an explicit `python -m podbay init-corpus --db <path>` (or equivalent) that creates and migrates an empty corpus, used for the smoke test. Smoke-test stores are discarded before cutover, and Litestream does not replicate them (or its S3 prefix is cleared before step 3), so the cutover generation starts clean. | Backstage (code), Overcast (runbook step) |
| C2 | `/api/admin/busy` implements the contract above. | Backstage |
| C3 | Compose: `PODBAY_TRUSTED_PROXIES` replaces `FORWARDED_ALLOW_IPS`; add `PODBAY_HOSTED: "1"` and `PODBAY_PORTAL_MAX_SESSIONS: "3"`. | Backstage |
| C4 | WP3 writes the three image digests for each SHA into the bundle (for example `s3://…-deploy/<sha>/images.json` with `app`, `portal`, `litestream`), carrying the last built Portal digest forward. Overcast's deploy reads digests from the bundle and verifies each exists in ECR before pulling. | Backstage (CI), Overcast (deploy) |
| C5 | §8 follows the merged order above; Overcast's migration runbook carries the host steps. | Both |
| C6 | Downloads use a first-level name, `backstage-downloads.arclight-complex.net` (CloudFront with the existing us-east-1 wildcard certificate), and the release workflow runs in a GitHub environment `desktop-release` for both the AWS upload role and the Azure federated credential. | Backstage (§7), Overcast (bucket, CloudFront, role) |

## What breaks first, and what is punted

1. **First deploy on an empty host** (C1): the preflight refuses a missing corpus file before anything else runs.
2. **Portal digest resolution** (C4): the first SHA that does not touch `docker/portal/` has no `v3-<sha>`.
3. **Egress drift**: Entra and Anthropic addresses change on their owners' schedule. Overcast resolves both names at every deploy and fails the deploy if an answer is outside the allowlist; between deploys, a sign-in failure is the alarm. Overcast will allow Anthropic's published API range rather than the single observed address.
4. **A long job with no browser and no Portal** stops the host after 30 idle minutes if `/api/admin/busy` is missing or wrong (C2); jobs resume after restart, late.
5. **The cookie key with a trailing newline** stops the app at preflight (fail-closed; one-line fix by rewriting the secret).

Punted or assumed to be Overcast's when it is not:
- The PC-side steps (freeze, control backup, checkpoint, upload) are the owner's and Backstage's; Overcast supplies the bucket and documents them, but does not run anything on the PC runtime.
- The Trusted Signing account and identity validation are the administrator's (Q-O6).
- Your §8 step 6 reconcile and the proxy test are app-side, as written.

Overcast-side items this review created (tracked in Overcast's plan for `terraform/envs/backstage/`): the downloads-upload role and `backstage-downloads` name (C6); `s3:PutObject` on the deploy prefix for the push role; the deploy reading `images.json` (C4); the Anthropic range; creating the host's uid/gid 997 before Docker installs so the `docker` group cannot take gid 997.

**Outcome (2026-10-21):** Backstage accepted all six conditions in spec v2 (`aws/hosting` `899d7f0`, verified read-only by Overcast) and the owner signed the spec at `fcc39ec` ("yes. hit it").
