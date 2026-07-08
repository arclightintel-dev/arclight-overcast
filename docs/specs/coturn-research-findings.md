# Coturn Research Findings — OS/Package and AWS/Bootstrap

> **Date**: 2026-07-08
> **Method**: Deep research agent (Opus 4.8) with 15+ sub-agents cross-referencing packaging source, AWS docs, upstream coturn source, and Terraform provider docs
> **Coverage**: All 18 RQ-OS and RQ-AWS questions resolved. 16 VERIFIED, 2 LIKELY, 0 UNVERIFIED.

---

## RQ-OS-01: Package availability — VERIFIED

`coturn` is in Ubuntu 24.04 `universe` repository. Version `4.6.1-1build4`. `universe` is enabled by default on Ubuntu server AMIs. `apt-get install coturn` works without enabling extra repos.

## RQ-OS-02: systemd unit content — VERIFIED

Installed at `/usr/lib/systemd/system/coturn.service`. Content from Debian packaging branch:

```ini
[Unit]
Description=coTURN STUN/TURN Server
Documentation=man:coturn(1) man:turnadmin(1) man:turnserver(1)
After=network.target

[Service]
User=turnserver
Group=turnserver
Type=notify
ExecStart=/usr/bin/turnserver -c /etc/turnserver.conf --pidfile=
Restart=on-failure
InaccessibleDirectories=/home
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
```

Key: `Type=notify`, `User=turnserver`, no `ExecStartPre`, no `EnvironmentFile`, no reference to `/etc/default/coturn`.

## RQ-OS-03: TURNSERVER_ENABLED behavior — VERIFIED (HIGHEST IMPACT)

**`/etc/default/coturn` and `TURNSERVER_ENABLED=1` are SysV init conventions only.** The systemd unit does not read this file. The current module's line 149 (`echo 'TURNSERVER_ENABLED=1' > /etc/default/coturn`) is **inert** — it has no effect on systemd-managed Ubuntu 24.04.

The service auto-enables on package installation via `dh_installsystemd` defaults.

## RQ-OS-04: Runtime user and group — VERIFIED

`User=turnserver`, `Group=turnserver` (from systemd unit).

## RQ-OS-05: Service account creation — VERIFIED

Package `postinst` script creates:
- Group: `turnserver` (system)
- User: `turnserver` (system, shell `/bin/false`, home `/`, no login)
- Also creates `/var/lib/turn` with ownership `turnserver:turnserver`, permissions `775`.

## RQ-OS-06: Default ownership and permissions — VERIFIED

| Path | Owner | Permissions | Created by |
|------|-------|-------------|------------|
| `/etc/turnserver.conf` | `root:turnserver` | `640` | Package (via `dpkg-statoverride`) |
| `/etc/default/coturn` | `root:root` | `644` | Package |
| `/var/lib/turn/` | `turnserver:turnserver` | `775` | Package postinst |
| `/var/log/turnserver/` | Does not exist by default | — | — |

## RQ-OS-07: Auto-start behavior — VERIFIED

Service **auto-enables and auto-starts** on `apt-get install coturn`. The `systemctl enable coturn` and `systemctl start coturn` lines in the current module (lines 228-229) are redundant.

## RQ-OS-08: Default generated state — VERIFIED

No default secrets, CLI passwords, TLS certs, or sample config state generated on install. `/etc/turnserver.conf` ships as a commented-out example. No cleanup needed.

## RQ-OS-09: use-auth-secret and multi-secret support — VERIFIED

Version 4.6.1 supports `use-auth-secret` and `static-auth-secret`. Source-code confirmed (git tag 4.6.1): `static-auth-secret` uses a dynamic array — multiple `static-auth-secret` lines are tried sequentially. Zero-downtime rotation is possible with overlapping secrets.

## RQ-OS-10: Prometheus support — VERIFIED

**Not available.** Ubuntu package built without `libmicrohttpd-dev`, which causes `-DTURN_NO_PROMETHEUS` at compile time. Using `prometheus` in config produces a parse error. Metrics must come from journald/CloudWatch/blackbox probing.

---

## RQ-AWS-01: AWS CLI v2 installation — VERIFIED

Public zip download is the recommended approach for user-data scripts. No `awscli` apt package on Ubuntu 24.04. Snap is an alternative but slower. GPG signature verification available (`.sig` file) but marked optional by AWS. Current module's zip approach is correct.

## RQ-AWS-02: SSM agent on Ubuntu 24.04 — VERIFIED

Pre-installed via snap on official Canonical Ubuntu 24.04 AMIs. Service name: `snap.amazon-ssm-agent.amazon-ssm-agent.service` (NOT `amazon-ssm-agent`). Enabled and started by default. Requires `AmazonSSMManagedInstanceCore` IAM policy on the instance profile.

**Current module bug**: Lines 158-159 use wrong service name (`amazon-ssm-agent` instead of `snap.amazon-ssm-agent.amazon-ssm-agent`). The `|| true` masks the failure.

## RQ-AWS-03: EIP association timing — VERIFIED (HIGH IMPACT)

**Race condition confirmed.** Cloud-init runs BEFORE EIP association. Terraform considers the instance "created" at `running` state, then creates `aws_eip_association` while cloud-init is still executing. With no auto-assigned public IP, IMDS `public-ipv4` returns 404 until EIP associates.

The current module's 10-retry loop (lines 186-198) is a fragile workaround for this race.

## RQ-AWS-04: external-ip sourcing — VERIFIED (HIGH IMPACT)

**Recommendation: Terraform interpolation for public IP, IMDS for private IP.**

Format: `external-ip=<EIP_PUBLIC>/<PRIVATE_IP>`

`aws_eip.coturn.public_ip` is known at plan time (EIP allocation happens before instance creation). Inject it into user-data via `templatefile()`. Query only the private IP from IMDS (always available, no race).

**Current module bug**: Line 206 uses `external-ip=$PUBLIC_IP` without the `/PRIVATE_IP` suffix. coturn documentation and all AWS-specific examples use the dual form. Missing private IP can cause relay candidates to advertise unusable addresses.

## RQ-AWS-05: IMDSv2 handling — VERIFIED

Current module's IMDSv2 pattern is correct but missing `-f` flag on curl (line 188). Without `-f`, HTTP errors are silently stored as the token value. Ubuntu 24.04 AMIs set `ImdsSupport: v2.0` by default, so `http_tokens = "required"` is redundant but good for explicitness.

`http_put_response_hop_limit = 2` is technically unnecessary for bare EC2 (1 is sufficient), but matches the AMI default and is harmless. Could be set to 1 for correctness.

## RQ-AWS-06: Minimal IAM policy — VERIFIED

Minimal policy for secret retrieval:
- `secretsmanager:GetSecretValue` on the specific secret ARN
- `kms:Decrypt` only if using a customer-managed KMS key (not needed with default `aws/secretsmanager` key)
- `AmazonSSMManagedInstanceCore` managed policy for SSM
- No CloudWatch policy needed if not running CloudWatch Agent (journald is local)

**Current module issue**: Lines 88-94 grant `kms:Decrypt` on `Resource: *` scoped by `kms:ViaService`. If using the default AWS-managed key, this entire statement can be removed. If using a CMK, scope to the specific key ARN.

## RQ-AWS-07: Outbound egress restrictions — VERIFIED

**Keep unrestricted egress.** TURN relay requires `UDP 49152-65535 → 0.0.0.0/0` by protocol design (RFC 8656). This single rule defeats fine-grained egress restrictions. VPC endpoints cost $29.20/month for a $7.59/month instance and are architecturally incompatible with TURN (requires public subnet).

**The real security boundary is `denied-peer-ip`** at the application layer, not SG egress. This prevents TURN from being used as a proxy to internal infrastructure (link-local, IMDS, RFC1918, VPC CIDRs). See the Slack TURN compromise incident.

## RQ-AWS-08: DNS record ownership — VERIFIED

DNS record should live in the root module (`staging/main.tf`), not inside the coturn module. The coturn module outputs `turn_endpoint` (EIP); the root module composes it with a `cloudflare_record`. This keeps the module provider-agnostic and follows HashiCorp's composition guidance. A single A record does not justify a separate DNS module.

The project uses Cloudflare, not Route53. New requirements: `cloudflare_api_token` (sensitive variable), `cloudflare_zone_id` variable.

---

## Issues found in current module (`terraform/modules/coturn/main.tf`)

| Line | Issue | Severity | Fix |
|------|-------|----------|-----|
| :137 | `hop_limit = 2` should be 1 (bare EC2, no containers) | Low | Change to 1 or leave (matches AMI default) |
| :149 | `TURNSERVER_ENABLED=1` is inert under systemd | Low | Remove |
| :158-159 | Wrong SSM service name (`amazon-ssm-agent` vs `snap.amazon-ssm-agent.amazon-ssm-agent`) | Low | Fix service name (or remove — pre-installed and auto-started) |
| :179-183 | Throwaway-secret fallback creates fail-dark behavior | **High** | Fail hard — `exit 1` if secret unavailable |
| :186-198 | IMDS `public-ipv4` race with EIP association | **High** | Inject EIP via Terraform interpolation |
| :206 | `external-ip` missing `/PRIVATE_IP` suffix | **High** | Use `external-ip=$PUBLIC_IP/$PRIVATE_IP` |
| :88-94 | `kms:Decrypt` on `Resource: *` — over-broad or unnecessary | Medium | Remove if using default key; scope to key ARN if CMK |
| :201-213 | Config lacks `denied-peer-ip` for internal/link-local/VPC ranges | **High** | Add denied-peer-ip rules per Enable Security guidance |
| :228-229 | `systemctl enable/start coturn` redundant (auto-starts on install) | Low | Remove |

---

## Blocking condition status update

| BC | Status | Resolution |
|----|--------|-----------|
| BC-01 | MOSTLY CLOSED | All answers at VERIFIED/LIKELY. Disposable EC2 probe recommended as mechanical confirmation but not a hard gate. |
| BC-02 | **CLOSED** | Podbay team answered all 8 RQ-POD questions (see coturn-podbay-answers.md) |
| BC-03 | PARTIALLY CLOSED | Secret format confirmed as raw hex string (`openssl rand -hex 32`). Entropy, rotation runbook, and KMS decision remain. |
| BC-04 | PARTIALLY CLOSED | Podbay consumes EIP as IP. DNS (Cloudflare A record in root module) is nice-to-have. |
| BC-05 | MOSTLY CLOSED | Inbound locked. Egress: keep unrestricted. Denied peers: defined. SSM-only: confirmed. No SSH. TLS/TURNS deferred. |
| BC-06 | CLOSED (by design decision) | Throwaway-secret fallback rejected. Fail hard on missing secret. |
| BC-07 | OPEN | Acceptance tests not yet defined (blocked on spec completion). |
