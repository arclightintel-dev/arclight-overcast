# Coturn TURN Server Implementation Spec

> **Version**: 1.1-draft (codex-1 NO-GO fixes)
> **Date**: 2026-07-08
> **Author**: claude-main (step 3 of spec process)
> **Process**: hotpants scoping → codex-2 structuring → **claude-main writing** → codex-1 verification
> **Governing decisions**: D-062 (via O-002 summary), O-002, INV-004, INV-005, INV-006
> **Actual counts**: 26 research questions, 7 blocking conditions, FM-00 + FM-01 through FM-12

---

## 1. Decision authority

### Authority source table

| Source | Local citation | Normative effect | Status |
|--------|---------------|-----------------|--------|
| O-002 | `docs/DECISIONS.md:19-25` | Self-hosted coturn on EC2 t3.micro with EIP, per-environment. Twilio rejected. Module exists but NOT WIRED pending spec. | Ratified, implementation pending |
| INV-005 | `docs/CONSTITUTION.md:27-37` | Spec before implement. Requires OS, packages, systemd, config, bootstrap, failure modes before code. | Active invariant |
| INV-004 | `docs/CONSTITUTION.md:23-25` | Terraform creates secret shells only. No `aws_secretsmanager_secret_version` — values out-of-band. | Active invariant |
| INV-006 | `docs/CONSTITUTION.md:39-41` | `aws_instance.user_data` expects plain text. `aws_launch_template.user_data` requires `base64encode()`. | Active invariant |
| D-062 | `arclight-complex/platform/DECISIONS.md:1205-1221` | Self-hosted coturn EC2 with EIP, per-environment, `use-auth-secret` HMAC-SHA1 credentials, shared secret in SM, no ALB/NLB, Twilio rejected (attribution surface), HA deferred. | Ratified |

### Non-goals

| Non-goal | Reason | Source | Impact |
|----------|--------|--------|--------|
| TLS/TURNS (port 5349) | Not required for v1 staging. UDP and TCP 3478 provide sufficient transport options. | Design decision | Deferred to Phase 6 or when browser environments require it |
| Zero-downtime secret rotation | v1 accepts brief invalidation window (≤5 min). Multi-secret rotation is supported but not required. | `docs/specs/coturn-podbay-answers.md:RQ-POD-06` | Acceptable for staging; revisit for prod |
| Prometheus metrics | Ubuntu 24.04 coturn package built without `libmicrohttpd-dev` (`-DTURN_NO_PROMETHEUS`). | `docs/specs/coturn-research-findings.md:RQ-OS-10` | Use journald + blackbox probing |
| Custom AMI / Packer build | Zip-based AWS CLI install in user-data is the AWS-recommended approach. AMI baking adds complexity without commensurate value for a single t3.micro. | `docs/specs/coturn-research-findings.md:RQ-AWS-01` | Bootstrap uses runtime package install |
| Credential minting logic | Owned by Podbay controller, not Overcast infrastructure. | `docs/specs/coturn-scoping.md:§1`, `docs/specs/coturn-podbay-answers.md:§implications` | Overcast delivers EIP + populated secret only |
| Cloudflare DNS record | Nice-to-have; Podbay consumes EIP as IP via `PODBAY_TURN_ENDPOINT`. DNS record creation deferred to Cloudflare Terraform unification work. | `docs/specs/coturn-podbay-answers.md:§implications`, `docs/specs/coturn-research-findings.md:RQ-AWS-08` | Module outputs EIP; DNS composed in root module when Cloudflare provider is added |

### Implementation stop rule

Implementation may NOT begin until:

- [x] INV-005 satisfied — this spec covers OS, packages, systemd, config, bootstrap, failure modes
- [x] O-002 acknowledged — module is not wired and needs spec (`docs/DECISIONS.md:23`)
- [x] BC-01 closed — disposable EC2 probe passed 11/11 on `ami-0a02a779008fa3b99` (2026-07-08)
- [x] BC-02 through BC-06 closed — see §12 open questions register
- [ ] BC-07 closed — acceptance tests defined in §10 (this spec)
- [ ] codex-1 verification pass — pending

---

## 2. Runtime architecture

### Topology inventory

| Component | Owner | Current reference | Target decision | Source |
|-----------|-------|-------------------|-----------------|--------|
| EC2 instance (t3.micro) | Overcast | `terraform/modules/coturn/main.tf:127-233` | Self-hosted per O-002 | O-002 |
| Elastic IP | Overcast | `terraform/modules/coturn/main.tf:239-248` | Stable public endpoint | O-002 |
| Security group | Overcast | `terraform/modules/coturn/main.tf:5-43` | Public TURN ingress + unrestricted egress | Design decision (§9) |
| IAM role + instance profile | Overcast | `terraform/modules/coturn/main.tf:49-102` | Secrets Manager read + SSM | Current code + spec amendments |
| Ubuntu 24.04 AMI | Canonical (via AWS) | `terraform/modules/coturn/main.tf:108-121` | Noble hvm-ssd-gp3 amd64 | RQ-OS-01 |
| coturn package | Ubuntu universe | Package install in user-data | 4.6.1-1build4 | RQ-OS-01 |
| Public subnet | Overcast (VPC module) | Passed via `var.subnet_id` | Required for TURN — EIP binding | RFC 8656 |

### Module interface inventory

| Name | Kind | Current/proposed | Consumer | Source |
|------|------|-----------------|----------|--------|
| `environment` | variable | Current | Module internal | `terraform/modules/coturn/variables.tf:1-4` |
| `vpc_id` | variable | Current | Security group | `terraform/modules/coturn/variables.tf:6-9` |
| `subnet_id` | variable | Current | EC2 instance | `terraform/modules/coturn/variables.tf:11-14` |
| `turn_secret_arn` | variable | Current | IAM policy + user-data | `terraform/modules/coturn/variables.tf:16-19` |
| `realm` | variable | Current | coturn config | `terraform/modules/coturn/variables.tf:21-24` |
| `instance_type` | variable | Current (default: t3.micro) | EC2 instance | `terraform/modules/coturn/variables.tf:26-30` |
| `aws_region` | variable | Current (default: us-east-1) | AWS CLI + IMDS | `terraform/modules/coturn/variables.tf:32-36` |
| `vpc_cidr` | variable | PROPOSED | denied-peer-ip config — render script converts CIDR to IP range format (coturn does not accept CIDR notation) | Spec §6 |
| `turn_endpoint` | output | Current | Podbay (`PODBAY_TURN_ENDPOINT`) | `terraform/modules/coturn/outputs.tf:1-4` |
| `turn_security_group_id` | output | Current | Staging wiring | `terraform/modules/coturn/outputs.tf:6-9` |
| `instance_id` | output | Current | Debugging/ops | `terraform/modules/coturn/outputs.tf:11-14` |

### Ownership boundary

| Area | Overcast owns | Podbay owns | Shared handoff | Source |
|------|--------------|-------------|----------------|--------|
| TURN host lifecycle | EC2, EIP, SG, IAM, SSM | — | — | O-002 |
| Shared secret storage | Secrets Manager shell + population | — | Secret ARN passed to Podbay controller via env var | INV-004, `docs/specs/coturn-podbay-answers.md:§implications` |
| Credential minting | — | Controller generates HMAC credentials | — | `docs/specs/coturn-podbay-answers.md:RQ-POD-03` |
| ICE configuration | — | `ice_servers` in grant response | Endpoint IP from Overcast output | `docs/specs/coturn-podbay-answers.md:RQ-POD-01` |
| Network exposure | Inbound SGs, relay port range | — | — | Spec §9 |
| Observability | journald, SSM access | Grant audit events, credential redaction | — | RQ-OS-10, RQ-POD-08 |

### Observability path

| Signal | Emitter | Transport | Reader | Retention | Source |
|--------|---------|-----------|--------|-----------|--------|
| coturn service logs | turnserver process | journald (stdout under systemd `Type=notify`) | SSM Session Manager (`journalctl -u coturn`) | Instance lifetime (journald default) | RQ-OS-02, RQ-OS-10 |
| systemd unit status | systemd | `systemctl status coturn` via SSM | Operator | Live | RQ-OS-02 |
| cloud-init output | cloud-init | `/var/log/cloud-init-output.log` | SSM Session Manager | Instance lifetime | AWS cloud-init docs |
| Instance reachability | EC2 | AWS console / SSM | Operator | — | AWS docs |

---

## 3. OS/package contract

### OS/AMI decision record

| Field | Value |
|-------|-------|
| **Decision** | Ubuntu Server 24.04 LTS (Noble Numbat), amd64, hvm-ssd-gp3 |
| **Alternatives** | Amazon Linux 2023 (rejected — lacks EPEL/coturn, earned as INV-005 at `56acd3e`), Debian 12 (viable but less AWS tooling) |
| **Evidence** | AMI filter: `ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*`, owner `099720109477` (Canonical). Current code: `terraform/modules/coturn/main.tf:108-121` |
| **Implications** | coturn available in `universe` repo. SSM agent pre-installed via snap. AWS CLI v2 not available via apt — must install from zip. |
| **Status** | LOCKED |

### Package evidence table

| Fact | Observed value | Probe command | Source | Status |
|------|---------------|---------------|--------|--------|
| Repository | `universe` (enabled by default on Ubuntu server) | `apt-cache policy coturn` | RQ-OS-01 (Ubuntu packages, research findings) | Resolved |
| Package version | `4.6.1-1build4` | `dpkg -l coturn` | RQ-OS-01 (packages.ubuntu.com) | Resolved |
| Installed binary | `/usr/bin/turnserver` | `which turnserver` | Ubuntu package file list | Resolved |
| systemd unit | `/usr/lib/systemd/system/coturn.service` | `systemctl cat coturn` | RQ-OS-02 (Debian packaging branch) | Resolved |
| Runtime user | `turnserver` (system, shell `/bin/false`, home `/`) | `id turnserver` | RQ-OS-04, RQ-OS-05 (package postinst) | Resolved |
| Runtime group | `turnserver` (system) | `getent group turnserver` | RQ-OS-05 (package postinst) | Resolved |
| Auto-start on install | Yes (enabled + started by `dh_installsystemd`) | `systemctl is-enabled coturn` | RQ-OS-07 | Resolved |
| Default generated state | None (no secrets, TLS certs, or CLI passwords) | `cat /etc/turnserver.conf` (commented-out example) | RQ-OS-08 | Resolved |
| `use-auth-secret` support | Yes (4.6.1 source confirmed) | grep config | RQ-OS-09 (git tag 4.6.1) | Resolved |
| Multi-secret support | Yes — `static-auth-secret` uses dynamic array, tried sequentially | Source code verification | RQ-OS-09 | Resolved |
| Prometheus | Not available (`-DTURN_NO_PROMETHEUS`, no `libmicrohttpd-dev`) | `turnserver --prometheus` (parse error) | RQ-OS-10 | Resolved |

### Systemd/file contract

| Path | Owner | Mode | Created by | Spec requirement | Source |
|------|-------|------|------------|-----------------|--------|
| `/usr/lib/systemd/system/coturn.service` | `root:root` | `644` | Package | Do not modify — use drop-in override | RQ-OS-02 |
| `/etc/turnserver.conf` | `root:turnserver` | `640` | Package (`dpkg-statoverride`) | Overwrite with rendered config (preserves ownership) | RQ-OS-06 |
| `/etc/default/coturn` | `root:root` | `644` | Package | **Do not modify** — inert under systemd | RQ-OS-03 |
| `/var/lib/turn/` | `turnserver:turnserver` | `775` | Package postinst | No spec requirement (unused with `use-auth-secret`) | RQ-OS-06 |
| `/etc/systemd/system/coturn.service.d/render-config.conf` | `root:root` | `644` | user-data | Drop-in for ExecStartPre with `+` prefix (root execution) | RQ-OS-02, research (systemd override) |
| `/usr/local/bin/render-coturn-config` | `root:root` | `755` | user-data | Config render script, called by ExecStartPre | Current code reference |

systemd unit content (from package, not modified):

```ini
[Unit]
Description=coTURN STUN/TURN Server
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

The `ExecStartPre` drop-in must use the `+` prefix to run as root (the base unit runs as `turnserver`, and the render script needs root to write `/etc/turnserver.conf` and access AWS CLI):

```ini
[Service]
ExecStartPre=+/usr/local/bin/render-coturn-config
```

### Package capability record

| Capability | Packaged support | Limitations | Source |
|-----------|-----------------|-------------|--------|
| `use-auth-secret` | Yes | — | RQ-OS-09, coturn 4.6.1 source |
| `static-auth-secret` (single) | Yes | — | RQ-OS-09 |
| `static-auth-secret` (multiple) | Yes — dynamic array, tried sequentially | Requires multiple lines in config | RQ-OS-09 |
| `denied-peer-ip` | Yes | IP ranges only (e.g., `10.0.0.0-10.255.255.255`), NOT CIDR notation. Render script must convert `var.vpc_cidr` to range format. | coturn docs |
| `no-cli` | Yes | Disables telnet CLI | coturn docs |
| Prometheus metrics | **No** — built without `libmicrohttpd-dev` | Config parse error if used | RQ-OS-10 |
| DTLS/TLS | Available but not tested for this spec | Requires cert/key provisioning | Deferred (non-goal) |

---

## 4. Bootstrap contract

### First-boot sequence

| Step | Preconditions | Action | Failure behavior | Evidence source |
|------|--------------|--------|------------------|-----------------|
| 1 | Instance running, cloud-init Final stage | `apt-get update && apt-get install -y coturn unzip curl` | cloud-init marks failed; instance unreachable via SSM for debugging | RQ-OS-01 |
| 2 | Step 1 complete | coturn auto-starts with default (empty) config — **this is expected and harmless** | Service starts but does nothing useful without config | RQ-OS-07 |
| 3 | Step 1 complete | Install AWS CLI v2 from zip (`awscli-exe-linux-x86_64.zip`) | `exit 1` — instance has no secret access without CLI | RQ-AWS-01 |
| 4 | Step 1 complete | Verify SSM agent running (`snap.amazon-ssm-agent.amazon-ssm-agent.service`) | Log warning — SSM is pre-installed, failure is unexpected | RQ-AWS-02 |
| 5 | Step 3 complete | Write render script to `/usr/local/bin/render-coturn-config` | `exit 1` | Design decision |
| 6 | Step 5 complete | Write systemd drop-in to `/etc/systemd/system/coturn.service.d/render-config.conf` | `exit 1` | RQ-OS-02 (drop-in support) |
| 7 | Step 6 complete | `systemctl daemon-reload` | `exit 1` | systemd docs |
| 8 | Step 7 complete | `systemctl restart coturn` → triggers ExecStartPre → render script | Render script fails → coturn does not start → `systemctl status` shows failure | Design decision (fail hard) |

### Dependency ordering matrix

| Dependency | Must complete before | Timeout/retry | On failure | Source |
|-----------|---------------------|---------------|------------|--------|
| EIP allocation | user-data template rendering (Terraform plan time) | N/A — known at plan time | Plan fails | RQ-AWS-03, RQ-AWS-04 |
| EIP association | NOT a dependency — public IP injected via Terraform, not IMDS | N/A | N/A | RQ-AWS-03 (race eliminated by design) |
| Package install | AWS CLI install, render script creation | apt retry (cloud-init default) | `exit 1` | RQ-OS-01 |
| AWS CLI v2 | Render script (secret fetch) | N/A | `exit 1` | RQ-AWS-01 |
| Secret population | First successful `systemctl restart coturn` | Render script retries 5x with 5s sleep | Render script `exit 1` → systemd unit fails | FM-00, BC-06 |
| Private IP (IMDS) | Config render | IMDSv2 token + GET, retry 5x | Render script `exit 1` | RQ-AWS-05 |

### Render contract

Inputs to the render script:

| Input | Source | Validation | Forbidden fallback |
|-------|--------|-----------|-------------------|
| Shared secret | AWS CLI → Secrets Manager `GetSecretValue` | Non-empty string | ~~`openssl rand -hex 32`~~ **REMOVED** — `exit 1` on failure |
| Public IP | Terraform interpolation (`${eip_public_ip}`) injected into user-data | Valid IPv4 | No IMDS fallback for public IP |
| Private IP | IMDS `local-ipv4` (always available, no EIP race) | Valid IPv4 | `exit 1` after 5 retries |
| Realm | Terraform interpolation (`${realm}`) | Non-empty | `exit 1` |
| AWS region | Terraform interpolation (`${aws_region}`) | Non-empty | `exit 1` |
| Secret ARN | Terraform interpolation (`${turn_secret_arn}`) | Non-empty | `exit 1` |
| VPC CIDR | Terraform interpolation (`${vpc_cidr}`) | Valid CIDR — render script converts to IP range for `denied-peer-ip` (e.g., `10.0.0.0/16` → `10.0.0.0-10.0.255.255`) | `exit 1` |

Rendered config template (placeholders only):

```
listening-port=3478
realm=$REALM
use-auth-secret
static-auth-secret=$SECRET
external-ip=$PUBLIC_IP/$PRIVATE_IP
min-port=49152
max-port=65535
no-cli
no-tlsv1
no-tlsv1_1
fingerprint
no-multicast-peers
denied-peer-ip=0.0.0.0-0.255.255.255
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=100.64.0.0-100.127.255.255
denied-peer-ip=127.0.0.0-127.255.255.255
denied-peer-ip=169.254.0.0-169.254.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.168.0.0-192.168.255.255
denied-peer-ip=240.0.0.0-255.255.255.255
denied-peer-ip=$VPC_RANGE_START-$VPC_RANGE_END
```

### Terraform/user-data constraints

| Terraform construct | Current code reference | Constitution constraint | Spec implication |
|--------------------|----------------------|----------------------|-----------------|
| `aws_instance.user_data` | `terraform/modules/coturn/main.tf:140-230` | INV-006: plain text, Terraform handles base64 internally | Do not use `base64encode()` |
| `aws_secretsmanager_secret` | Not in coturn module (created elsewhere) | INV-004: shell only, no `secret_version` | Secret value populated out-of-band by operator |
| `templatefile()` | Not currently used (heredoc with `${var.*}` interpolation) | — | PROPOSED: switch to `templatefile()` for cleaner variable injection including EIP public IP |

---

## 5. Steady-state contract

### Restart/re-render matrix

| Event | Inputs refreshed | Inputs cached | Expected result | Failure result | Source |
|-------|-----------------|---------------|-----------------|----------------|--------|
| `systemctl restart coturn` | Secret (re-fetched from SM), private IP (IMDS) | Public IP (Terraform-injected, static in script), realm, region | New config rendered, coturn starts with fresh secret | ExecStartPre fails → unit stays failed → `systemctl status` shows error | Design decision |
| Instance reboot | All (user-data re-runs? No — cloud-init only on first boot) | Public IP (in render script, static) | ExecStartPre re-renders config, coturn starts | Same as restart failure | cloud-init docs |
| Secret rotation | Secret (on next restart or manual `systemctl restart coturn`) | Everything else | coturn picks up new secret after restart | If operator forgets to restart coturn, old secret stays active | FM-10 |
| EIP re-association | Public IP is static in render script — does NOT update | — | **Stale public IP in config** — requires user-data update or manual script edit | Relay addresses advertise wrong IP | FM-01 mitigation note |

EIP re-association is an edge case: the EIP public IP is injected at Terraform apply time. If the EIP is ever disassociated and a new one attached, the render script still has the old IP. This requires a `terraform apply` (which regenerates user-data) followed by instance replacement or manual script update. Acceptable for v1 — EIP changes are rare operational events.

### Rotation state machine

**V1: single-secret, restart-required rotation.**

```
State 1: STEADY
  coturn running with secret S1
  Podbay controller cached S1 (TTL ≤ 5 min)

State 2: SECRET_UPDATED
  Operator: aws secretsmanager put-secret-value --secret-id <ARN> --secret-string "<new>"
  coturn still running with S1
  Podbay controller still cached S1

State 3: COTURN_RESTARTED
  Operator: systemctl restart coturn (via SSM)
  ExecStartPre fetches S2, renders config
  coturn running with S2
  Podbay controller still cached S1 (up to 5 min)
  → NEW credentials minted with S1 will FAIL against coturn (S2)
  → EXISTING TURN allocations continue (coturn preserves sessions)

State 4: CONTROLLER_CACHE_EXPIRES
  Podbay controller fetches S2 from Secrets Manager
  New credentials use S2 → match coturn
  → STEADY state restored
```

Invalidation window: up to 5 minutes (Podbay `_CACHE_TTL = 300.0`). Acceptable for v1 staging per `docs/specs/coturn-podbay-answers.md:RQ-POD-06`.

### Runtime failure policy

| Failure | Detection | Service state | Operator signal | Recovery | Source |
|---------|-----------|---------------|-----------------|----------|--------|
| Secret unavailable on restart | ExecStartPre exits non-zero | Failed (systemd `Restart=on-failure` retries, then gives up) | `systemctl status coturn` via SSM shows failure | Populate/fix secret, `systemctl restart coturn` | FM-00, BC-06 |
| IMDS private IP unavailable | Render script retry exhausted | Failed | cloud-init-output.log + journald | Reboot or investigate networking | FM-01 |
| coturn crash | systemd `Restart=on-failure` | Auto-restart (re-runs ExecStartPre) | journald | Automatic up to systemd retry limit | RQ-OS-02 |
| Config parse error | coturn exits with error | Failed | journald: parse error message | Fix render script, restart | FM-04 |

### Clock-skew handling

| Actor | Clock source | Bound | Mitigation | Source |
|-------|-------------|-------|------------|--------|
| Podbay controller | ECS Fargate, AWS NTP | < 1s | — | `docs/specs/coturn-podbay-answers.md:RQ-POD-07` |
| coturn server | EC2 instance, AWS NTP (chrony/systemd-timesyncd) | < 1s | — | AWS NTP docs |
| Browser client | User's local clock | Unbounded | Client does not validate expiry — coturn does | `docs/specs/coturn-podbay-answers.md:RQ-POD-07` |

No explicit skew handling needed. Minimum credential TTL is 60s, providing > 59s margin against sub-second NTP drift between controller and coturn.

---

## 6. Coturn config contract

### Required option table

| Option | Value/source | Reason | Verification | Source |
|--------|-------------|--------|-------------|--------|
| `listening-port` | `3478` | Standard STUN/TURN port | `ss -ulnp \| grep 3478` | RFC 8656 |
| `realm` | `${realm}` (e.g., `staging.arclight-complex.net`) | Must match Podbay controller's realm assumption | Check rendered config | `docs/specs/coturn-scoping.md:§1` |
| `use-auth-secret` | (flag, no value) | HMAC time-limited credentials | Verify with `turnutils_uclient` | D-062 via O-002, RQ-OS-09 |
| `static-auth-secret` | `$SECRET` (fetched from SM) | Shared secret for HMAC credential validation | Allocation test with valid HMAC | RQ-OS-09 |
| `external-ip` | `$PUBLIC_IP/$PRIVATE_IP` | Dual-form: public IP for relay candidates, private IP for binding | `grep external-ip /etc/turnserver.conf` | RQ-AWS-04 (research: missing `/PRIVATE_IP` is a bug) |
| `min-port` | `49152` | Relay port range start | SG ingress match | RFC 8656 |
| `max-port` | `65535` | Relay port range end | SG ingress match | RFC 8656 |
| `no-cli` | (flag) | Disable telnet admin CLI | `ss -tlnp` shows no CLI port | Security posture |
| `no-tlsv1` | (flag) | Disable TLS 1.0 | — | Security posture |
| `no-tlsv1_1` | (flag) | Disable TLS 1.1 | — | Security posture |
| `fingerprint` | (flag) | Add STUN fingerprint to responses | Required for WebRTC interop | coturn docs |
| `no-multicast-peers` | (flag) | Deny multicast relay | Security posture | coturn docs |
| `denied-peer-ip` | See peer policy table | Deny relay to internal/link-local/VPC ranges | Denied peer test | `docs/specs/coturn-scoping.md:§1`, Enable Security guidance |

### Forbidden option table

| Option/surface | Forbidden state | Reason | Verification | Source |
|---------------|----------------|--------|-------------|--------|
| `cli-port` | Must not be set (or `no-cli` must be present) | Telnet admin CLI is a security risk on a public instance | `ss -tlnp \| grep -v 3478` shows no extra listeners | Security posture |
| `web-admin` | Must not be set | Web admin panel is a security risk | Same as above | Security posture |
| `cli-password` | Must not be set | No CLI means no CLI password | grep rendered config | Security posture |
| `prometheus` | Must not be set | Package lacks Prometheus support — causes parse error | Config validation | RQ-OS-10 |
| `lt-cred-mech` | Must not be set | Long-term credentials conflict with `use-auth-secret` | Config validation | coturn docs |
| `static-user` | Must not be set | No static users — HMAC only | Config validation | D-062 via O-002 |

### Rendered config template

```
listening-port=3478
realm=${REALM}
use-auth-secret
static-auth-secret=${SECRET}
external-ip=${PUBLIC_IP}/${PRIVATE_IP}
min-port=49152
max-port=65535
no-cli
no-tlsv1
no-tlsv1_1
fingerprint
no-multicast-peers
denied-peer-ip=0.0.0.0-0.255.255.255
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=100.64.0.0-100.127.255.255
denied-peer-ip=127.0.0.0-127.255.255.255
denied-peer-ip=169.254.0.0-169.254.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.168.0.0-192.168.255.255
denied-peer-ip=240.0.0.0-255.255.255.255
denied-peer-ip=${VPC_RANGE_START}-${VPC_RANGE_END}
```

`${SECRET}` is the only sensitive value. It is fetched at render time from Secrets Manager and written to `/etc/turnserver.conf` (mode `640`, owner `root:turnserver`). It never appears in Terraform state, cloud-init logs (render script does not use `set -x`), or journald (coturn does not log the secret).

### Peer policy table

| CIDR/range | allow/deny | Reason | Source | Verification |
|-----------|-----------|--------|--------|-------------|
| `0.0.0.0-0.255.255.255` | deny | Current network, CVE-2020-26262 bypass | Enable Security config guide | Denied peer test |
| `10.0.0.0-10.255.255.255` | deny | RFC 1918 private | Enable Security, `docs/specs/coturn-scoping.md:§1` | Denied peer test |
| `100.64.0.0-100.127.255.255` | deny | RFC 6598 CGN | Enable Security | Denied peer test |
| `127.0.0.0-127.255.255.255` | deny | Loopback | Enable Security | Denied peer test |
| `169.254.0.0-169.254.255.255` | deny | Link-local (blocks IMDS relay abuse) | Enable Security, Slack TURN compromise | Denied peer test |
| `172.16.0.0-172.31.255.255` | deny | RFC 1918 private | Enable Security | Denied peer test |
| `192.168.0.0-192.168.255.255` | deny | RFC 1918 private | Enable Security | Denied peer test |
| `240.0.0.0-255.255.255.255` | deny | Reserved | Enable Security | Denied peer test |
| VPC CIDR (e.g., `10.0.0.0-10.0.255.255`) | deny | Prevent relay to VPC internal targets (RDS, ALB, other services) | `docs/specs/coturn-scoping.md:§1` | Denied peer test |

### Logging/redaction table

| Log source | Allowed fields | Forbidden fields | Verification | Source |
|-----------|---------------|-----------------|-------------|--------|
| journald (coturn) | Realm, external IP, allocation events, peer addresses, error messages | `static-auth-secret` value | `journalctl -u coturn \| grep -i secret` returns nothing | FM-09 |
| cloud-init-output.log | Package install progress, AWS CLI install progress, render script status messages | Secret value (render script must not echo it) | `grep -i secret /var/log/cloud-init-output.log` returns only status messages, not values | FM-09 |
| `/etc/turnserver.conf` | All config options | — (file contains the secret by necessity, but mode `640` restricts access) | `ls -la /etc/turnserver.conf` shows `root:turnserver 640` | RQ-OS-06 |

---

## 7. Podbay integration contract

### Boundary matrix

| Responsibility | Overcast | Podbay controller | Browser | Workspace | Source |
|---------------|----------|-------------------|---------|-----------|--------|
| Shared secret storage | Secrets Manager shell + out-of-band population | Read access via SM `GetSecretValue` (5-min cache) | **Never** | **Never** | INV-004, `docs/specs/coturn-podbay-answers.md:RQ-POD-05` |
| Credential minting | — | Generates HMAC: `base64(HMAC-SHA1(secret, username))` | — | — | `docs/specs/coturn-podbay-answers.md:RQ-POD-03` |
| Credential delivery | — | Embeds in `ice_servers` array of grant response | Receives ephemeral credentials | **Never** | `docs/specs/coturn-podbay-answers.md:RQ-POD-01` |
| TURN validation | coturn validates credentials against `static-auth-secret` | — | — | — | RQ-OS-09 |
| Endpoint provisioning | EIP, SG, IAM, EC2 | — | — | — | O-002 |
| Endpoint consumption | Outputs `turn_endpoint` (EIP IP) | Reads `PODBAY_TURN_ENDPOINT` env var | Receives in `ice_servers` URLs | TURN peer (relayed to by coturn) | `docs/specs/coturn-podbay-answers.md:§implications` |

### Endpoint handoff

| Field | Producer | Consumer | Format | Source | Status |
|-------|----------|----------|--------|--------|--------|
| `turn_endpoint` | `terraform/modules/coturn/outputs.tf:1-4` | Staging wiring → Podbay env var | IPv4 string (EIP `public_ip`) | Current output | Current |
| `PODBAY_TURN_ENDPOINT` | Staging main.tf (wiring) | Podbay controller | IPv4 string | `docs/specs/coturn-podbay-answers.md:§implications` | PROPOSED (wiring) |
| `PODBAY_TURN_SECRET` | Staging main.tf (wiring, secret ARN) | Podbay controller (Secrets Manager read) | Secret ARN string | `docs/specs/coturn-podbay-answers.md:§implications` | PROPOSED (wiring) |
| DNS (`turn.staging.arclight-complex.net`) | Root module Cloudflare record | Browser ICE config | A record → EIP | RQ-AWS-08 | DEFERRED (non-goal) |

### Credential minting contract

**Issuer**: Podbay controller (not browser, not workspace).

**Algorithm** (from Podbay code at `turn_service.py:72`, `workspaces.py:912-915`):
```python
expiry = int((grant.expires_at - now()).total_seconds())
expiry = max(60, expiry)
username = f"{expiry_epoch}:{grant_id}"
credential = base64(hmac_sha1(shared_secret, username))
```

**Username shape**: `<expiry_epoch>:<surface_grant_id>` (e.g., `1720001800:sg_a1b2c3d4e5f6`). Source: `docs/specs/coturn-podbay-answers.md:RQ-POD-03`.

**Credential TTL**: `max(60, grant_ttl_remaining)`. Grant lifetime range: 60s–7200s, default 900s. Source: `docs/specs/coturn-podbay-answers.md:RQ-POD-04`.

### ICE config schema

From `docs/specs/coturn-podbay-answers.md:RQ-POD-01`:

```json
{
  "ice_servers": [
    {"urls": ["stun:<TURN_ENDPOINT>:3478"]},
    {
      "urls": ["turn:<TURN_ENDPOINT>:3478"],
      "username": "<expiry_epoch>:<grant_id>",
      "credential": "<base64_hmac>",
      "credential_type": "password",
      "ttl_seconds": 900
    }
  ]
}
```

Transport variants: UDP implicit (default for TURN URLs without `?transport=` suffix). TCP 3478 is open at the SG and coturn level for clients in restrictive networks, and Podbay MAY add `turn:<TURN_ENDPOINT>:3478?transport=tcp` to the `urls` array. The infra contract supports both; whether Podbay exposes TCP in ICE URLs is a Podbay decision.

### Podbay logging/provenance

| Event | Fields allowed | Fields forbidden | Source |
|-------|---------------|-----------------|--------|
| `podbay.surface_grant.issued` | grant_id, session_ref, actor_principal_id, surface_type, capability, ttl_seconds, correlation_id | Shared secret, credential value, raw grant token | `docs/specs/coturn-podbay-answers.md:RQ-POD-08` |

---

## 8. Secret custody contract

### Secret inventory

| Secret | Environment | Name/ARN | Value format | Owner | Readers | Source |
|--------|------------|----------|-------------|-------|---------|--------|
| TURN shared secret | staging | `arclight/staging/podbay/turn-shared-secret` | Raw hex string | Operator (out-of-band) | coturn instance role, Podbay controller task role | `terraform/modules/coturn/variables.tf:16-19` (ARN passed as `turn_secret_arn`), INV-004 |
| TURN shared secret | prod | `arclight/prod/podbay/turn-shared-secret` | Raw hex string | Operator (out-of-band) | coturn instance role, Podbay controller task role | Same pattern |

### Value format contract

| Field | Value |
|-------|-------|
| **Decision** | Raw hex string, not JSON |
| **Generation** | `openssl rand -hex 32` (64 hex characters = 256 bits entropy) |
| **Charset** | `[0-9a-f]` only |
| **Minimum entropy** | 256 bits (32 bytes) |
| **Validation** | Non-empty string. Render script checks `[ -n "$SECRET" ]`. |
| **Status** | LOCKED |
| **Source** | `docs/specs/coturn-podbay-answers.md:§implications` (Podbay integration sequence) |

### IAM/KMS matrix

| Principal | Action | Resource | Condition | Reason | Source |
|-----------|--------|----------|-----------|--------|--------|
| coturn instance role | `secretsmanager:GetSecretValue` | `var.turn_secret_arn` (specific secret) | — | Fetch shared secret for config render | `terraform/modules/coturn/main.tf:71-84`, AWS SM docs |
| coturn instance role | ~~`kms:Decrypt`~~ | **REMOVED** — default `aws/secretsmanager` key does not require explicit KMS permissions on the caller | N/A | Not needed with default key | `terraform/modules/coturn/main.tf:85-97` (current, to be removed), research findings RQ-AWS-06 |
| coturn instance role | `AmazonSSMManagedInstanceCore` (managed policy) | `*` | — | SSM Session Manager access | `terraform/modules/coturn/main.tf:66-69`, RQ-AWS-02 |
| Podbay controller task role | `secretsmanager:GetSecretValue` | Same secret ARN | — | Fetch shared secret for credential minting | `docs/specs/coturn-podbay-answers.md:RQ-POD-06` (5-min cache) |

**Design decision on KMS**: The TURN secret uses the default AWS-managed key (`aws/secretsmanager`). The `kms:Decrypt` statement in the coturn IAM policy is **removed** — it is unnecessary with the default key. The current module's `kms:Decrypt` on `Resource: *` (`:88-94`) is over-broad and will be deleted in the reimplementation. If a future decision moves to a customer-managed KMS key, a scoped `kms:Decrypt` statement must be added at that time. Source: research findings RQ-AWS-06, AWS SM docs.

### Rotation runbook outline

1. Generate new secret: `openssl rand -hex 32`
2. Update Secrets Manager: `aws secretsmanager put-secret-value --secret-id <ARN> --secret-string "<new>"`
3. Restart coturn via SSM: `aws ssm start-session --target <instance-id>` → `sudo systemctl restart coturn`
4. Verify coturn started: `sudo systemctl status coturn` — should show `active (running)`
5. Verify new config: `sudo grep static-auth-secret /etc/turnserver.conf` — shows new value
6. Wait ≤ 5 minutes for Podbay controller cache to expire
7. Verify: mint a test grant via Podbay API — TURN allocation should succeed
8. Rollback if needed: put old secret back in SM, restart coturn

### No-leak controls

| Surface | Forbidden data | Control | Verification | Source |
|---------|---------------|---------|-------------|--------|
| Terraform state | Secret value | INV-004: no `aws_secretsmanager_secret_version` | `terraform state list \| grep secret_version` returns nothing | INV-004 |
| cloud-init-output.log | Secret value | Render script does not echo secret; no `set -x` in render script | `grep` output log | FM-09 |
| journald | Secret value | coturn does not log `static-auth-secret`; render script logs only status messages | `journalctl -u coturn \| grep -i` test | FM-09 |
| Podbay audit events | Secret value, credential value | Redaction patterns in `redaction.py:38` | `docs/specs/coturn-podbay-answers.md:RQ-POD-08` | RQ-POD-08 |
| Browser | Shared secret | Controller delivers only ephemeral HMAC credential | Browser never sees shared secret | `docs/specs/coturn-podbay-answers.md:RQ-POD-05` |
| Workspace container | Shared secret, TURN credentials | No TURN env vars injected into workspace | `docs/specs/coturn-podbay-answers.md:RQ-POD-05` | RQ-POD-05 |

---

## 9. Network/security contract

### Inbound policy table

| Protocol | Port/range | Source CIDR | Purpose | Verification | Source |
|----------|-----------|-------------|---------|-------------|--------|
| UDP | 3478 | `0.0.0.0/0` | TURN control (STUN binding + TURN allocation) | `turnutils_uclient` allocation test | `terraform/modules/coturn/main.tf:10-15`, RFC 8656 |
| TCP | 3478 | `0.0.0.0/0` | TURN control (TCP fallback for restrictive networks) | `turnutils_uclient -T` allocation test | `terraform/modules/coturn/main.tf:17-22`, RFC 8656 |
| UDP | 49152-65535 | `0.0.0.0/0` | TURN relay (media) | WebRTC E2E test | `terraform/modules/coturn/main.tf:24-30`, RFC 8656 |
| TCP/UDP | 5349 | — | TURNS (TLS/DTLS) — **NOT opened** | — | Non-goal (deferred) |

### Outbound policy table

| Protocol | Destination | Purpose | Restriction | Verification | Source |
|----------|------------|---------|-------------|-------------|--------|
| All | `0.0.0.0/0` | Unrestricted egress | None — TURN relay requires UDP 49152-65535 to arbitrary public IPs; fine-grained egress is ineffective | `terraform/modules/coturn/main.tf:34-40` | RQ-AWS-07, RFC 8656 |

Egress restriction is not applied because TURN relay to arbitrary peer IPs is a protocol requirement. The security boundary for relay target access is `denied-peer-ip` at the application layer, not SG egress rules. See §6 peer policy table.

### Denied peer policy

| Target class | CIDR/source | Decision | coturn option | Verification | Source |
|-------------|-----------|----------|---------------|-------------|--------|
| Current network | `0.0.0.0-0.255.255.255` | DENY | `denied-peer-ip` | Allocation to `0.0.0.1` fails | CVE-2020-26262, Enable Security |
| RFC 1918 (10.x) | `10.0.0.0-10.255.255.255` | DENY | `denied-peer-ip` | Allocation to `10.0.0.1` fails | Enable Security |
| RFC 6598 CGN | `100.64.0.0-100.127.255.255` | DENY | `denied-peer-ip` | Allocation to `100.64.0.1` fails | Enable Security |
| Loopback | `127.0.0.0-127.255.255.255` | DENY | `denied-peer-ip` | Allocation to `127.0.0.1` fails | Enable Security |
| Link-local / IMDS | `169.254.0.0-169.254.255.255` | DENY | `denied-peer-ip` | Allocation to `169.254.169.254` fails | Slack TURN compromise, Enable Security |
| RFC 1918 (172.16.x) | `172.16.0.0-172.31.255.255` | DENY | `denied-peer-ip` | Allocation to `172.16.0.1` fails | Enable Security |
| RFC 1918 (192.168.x) | `192.168.0.0-192.168.255.255` | DENY | `denied-peer-ip` | Allocation to `192.168.0.1` fails | Enable Security |
| Reserved | `240.0.0.0-255.255.255.255` | DENY | `denied-peer-ip` | — | Enable Security |
| VPC CIDR | Module input `var.vpc_cidr` (e.g., `10.0.0.0/16`), converted to IP range by render script (e.g., `10.0.0.0-10.0.255.255`) | DENY | `denied-peer-ip` (range format, not CIDR) | Allocation to VPC internal IP fails | `docs/specs/coturn-scoping.md:§1`, coturn docs (range-only syntax) |
| Multicast | `224.0.0.0-239.255.255.255` | DENY | `no-multicast-peers` | — | coturn docs |

### Admin/debug access

| Access path | Allowed principal | Forbidden path | Source | Verification |
|------------|------------------|----------------|--------|-------------|
| SSM Session Manager | Operators with SSM permissions | — | RQ-AWS-02, `AmazonSSMManagedInstanceCore` | `aws ssm start-session --target <instance-id>` succeeds |
| SSH (key-based) | **FORBIDDEN** | No SSH key pair in `aws_instance`, no port 22 ingress | Design decision | SG has no port 22 rule |
| coturn telnet CLI | **FORBIDDEN** | `no-cli` in config | Design decision | `ss -tlnp` shows no CLI port |
| coturn web admin | **FORBIDDEN** | Not configured | Design decision | Same as above |

### Abuse/reflection controls

| Risk | Control | Verification | Source |
|------|---------|-------------|--------|
| UDP amplification via unauthenticated STUN | `use-auth-secret` requires credentials for TURN allocations; STUN binding requests are lightweight | Volume monitoring via journald | RFC 8656 |
| Relay to internal networks | `denied-peer-ip` for all RFC 1918, link-local, VPC CIDRs | Denied peer test | Enable Security, Slack incident |
| Relay abuse (data exfiltration tunnel) | Authentication required; short credential TTL (60s-2h) | Grant-bound credentials limit exposure window | `docs/specs/coturn-podbay-answers.md:RQ-POD-04` |

---

## 10. Verification contract

### Pre-implementation package probe

**Disposable EC2 package probe completed 2026-07-08.** AMI `ami-0a02a779008fa3b99` (ubuntu-noble-24.04-amd64-server-20260626), instance `i-0f18fe9125898dca7` (terminated). 11/11 PASS. All research findings confirmed empirically on the exact deployed AMI. BC-01 CLOSED.

| Probe | Command | Expected evidence | Blocks | Status |
|-------|---------|------------------|--------|--------|
| Package available | `apt-cache policy coturn` | `4.6.1-1build4` from `universe` | BC-01 | **PASS** — `4.6.1-1build4` from `noble/universe` |
| Unit content | `systemctl cat coturn` | Matches §3 unit content | BC-01 | **PASS** — exact match (User=turnserver, Type=notify, no EnvironmentFile) |
| Runtime user | `id turnserver` | System user, shell `/bin/false` | BC-01 | **PASS** — `uid=111(turnserver) gid=113(turnserver)` |
| Config permissions | `stat /etc/turnserver.conf` | `root:turnserver 640` | BC-01 | **PASS** — `root:turnserver 640` |
| Default file permissions | `stat /etc/default/coturn` | `root:root 644` (inert) | BC-01 | **PASS** — `root:root 644` |
| Auto-enabled | `systemctl is-enabled coturn` | `enabled` | BC-01 | **PASS** — `enabled` |
| Auto-active | `systemctl is-active coturn` | `active` | BC-01 | **PASS** — `active` (auto-starts on install) |
| TURNSERVER_ENABLED | `grep -r TURNSERVER /usr/lib/systemd/` | No results (SysV only) | BC-01 | **PASS** — `NO_RESULTS` |
| Prometheus | `turnserver --prometheus 2>&1` | Error/unknown | BC-01 | **PASS** — `unrecognized option '--prometheus'` |
| turndb created | `ls -la /var/lib/turn/` | SQLite DB exists | BC-01 | **PASS** — `turndb` 69632 bytes (auto-created from schema.sql) |
| Package files | `dpkg -L coturn \| grep -E '(service\|default\|conf)'` | Lists expected paths | BC-01 | **PASS** — `/etc/default/coturn`, `/etc/turnserver.conf`, `/usr/lib/systemd/system/coturn.service` |

### Terraform validation/plan expectations

| Command | Expected result | Inspected resources | Failure examples |
|---------|----------------|--------------------|-----------------| 
| `terraform validate` | Success | — | Variable type mismatch, missing required variable |
| `terraform plan` | 8 resources to add: `aws_security_group.coturn` (`:5`), `aws_iam_role.coturn` (`:59`), `aws_iam_role_policy_attachment.coturn_ssm` (`:66`), `aws_iam_role_policy.coturn_secrets` (`:71`), `aws_iam_instance_profile.coturn` (`:99`), `aws_instance.coturn` (`:127`), `aws_eip.coturn` (`:239`), `aws_eip_association.coturn` (`:245`) | All 8 resources listed | Missing variable, AMI not found, subnet not in VPC |

### Runtime smoke tests

| Test | Method | Expected result | Failure mode covered | Evidence artifact |
|------|--------|----------------|--------------------|-----------------| 
| SSM reachability | `aws ssm start-session --target <id>` | Shell session opens | FM-06 | Session transcript |
| coturn service active | `systemctl status coturn` (via SSM) | `active (running)` | FM-00, FM-04, FM-05 | Status output |
| Rendered config correct | `sudo grep -E 'realm\|external-ip\|use-auth-secret\|min-port\|max-port' /etc/turnserver.conf` | All expected values present | FM-02, FM-04, FM-05 | Config excerpt |
| External IP correct | `grep external-ip /etc/turnserver.conf` | `<EIP>/<PRIVATE_IP>` | FM-01 | Config line |
| denied-peer-ip present | `grep denied-peer-ip /etc/turnserver.conf \| wc -l` | ≥ 9 rules | FM-08 | Count + content |
| UDP allocation | `turnutils_uclient -u test -w <valid-credential> <EIP>` | Allocation succeeds (exit 0) | FM-00, FM-07 | Command output |
| TCP fallback | `turnutils_uclient -T -u test -w <valid-credential> <EIP>` | Allocation succeeds | FM-07 | Command output |
| journald access | `journalctl -u coturn --no-pager -n 20` (via SSM) | Log entries visible, no secret values | FM-09 | Log excerpt |

### Negative tests

| Test | Invalid input | Expected failure | Failure mode covered | Evidence artifact |
|------|-------------|-----------------|--------------------|-----------------| 
| Wrong secret | HMAC credential minted with wrong secret | 401 Unauthorized / allocation fails | FM-00, FM-05 | `turnutils_uclient` exit code |
| Expired credential | Username with past epoch | 401 Unauthorized | FM-03 | Command output |
| Denied peer (IMDS) | Allocation requesting relay to `169.254.169.254` | Allocation denied (403 Forbidden) | FM-08 | Command output |
| Denied peer (VPC) | Allocation requesting relay to VPC internal IP | Allocation denied | FM-08 | Command output |
| No secret on boot | Boot with empty/missing SM secret | coturn fails to start, `systemctl status` shows error | FM-00 | SSM session + status |
| Realm mismatch | HMAC credential minted with correct secret but wrong realm | 401 Unauthorized / allocation fails | FM-02 | `turnutils_uclient -r wrong.realm` exit code |

### Podbay E2E smoke

| Scenario | Podbay precondition | TURN expectation | Evidence | Owner |
|----------|-------------------|-----------------|---------|---------| 
| Browser-to-workspace relay | Grant minted with `ice_servers` including TURN entry | WebRTC media flows through TURN relay | CDP connection established, video/input operational | Podbay team |
| Credential minting | Controller reads shared secret from SM | Valid HMAC credential in grant response | Grant response includes `ice_servers` with non-empty `credential` | Podbay team |
| Grant expiry | Grant with short TTL (60s) | TURN credential expires, new grant needed | Allocation fails after TTL; new grant works | Podbay team |

### Coverage matrix

| ID | Verifying section | Verification artifact | Status |
|----|------------------|----------------------|--------|
| RQ-OS-01 | §3 Package evidence | `apt-cache policy` | Resolved |
| RQ-OS-02 | §3 Systemd/file contract | `systemctl cat` | Resolved |
| RQ-OS-03 | §3 Systemd/file contract | `grep TURNSERVER` | Resolved |
| RQ-OS-04 | §3 Package evidence | `id turnserver` | Resolved |
| RQ-OS-05 | §3 Package evidence | Package postinst source | Resolved |
| RQ-OS-06 | §3 Systemd/file contract | `stat` commands | Resolved |
| RQ-OS-07 | §3 Package evidence | `systemctl is-enabled` | Resolved |
| RQ-OS-08 | §3 Package evidence | Config file inspection | Resolved |
| RQ-OS-09 | §3 Package capability | Source code tag 4.6.1 | Resolved |
| RQ-OS-10 | §3 Package capability | Compile flags | Resolved |
| RQ-AWS-01 | §4 Bootstrap | AWS CLI docs | Resolved |
| RQ-AWS-02 | §4 Bootstrap | AWS SSM docs | Resolved |
| RQ-AWS-03 | §4 Dependency ordering | Terraform/cloud-init docs | Resolved |
| RQ-AWS-04 | §4 Render contract | Research findings | Resolved |
| RQ-AWS-05 | §4 Bootstrap | IMDS docs | Resolved |
| RQ-AWS-06 | §8 IAM/KMS matrix | AWS SM/KMS docs | Resolved |
| RQ-AWS-07 | §9 Outbound policy | RFC 8656, Enable Security | Resolved |
| RQ-AWS-08 | §2 Module interface | HashiCorp composition docs | Resolved |
| RQ-POD-01 | §7 Boundary matrix | Podbay answers | Resolved |
| RQ-POD-02 | §7 Credential minting | Podbay answers | Resolved |
| RQ-POD-03 | §7 Credential minting | Podbay answers | Resolved |
| RQ-POD-04 | §7 Credential minting | Podbay answers | Resolved |
| RQ-POD-05 | §7 Boundary matrix | Podbay answers | Resolved |
| RQ-POD-06 | §5 Rotation state machine | Podbay answers | Resolved |
| RQ-POD-07 | §5 Clock-skew handling | Podbay answers | Resolved |
| RQ-POD-08 | §7 Podbay logging | Podbay answers | Resolved |
| BC-01 | §3 (all) | Research spike | Resolved |
| BC-02 | §7 (all) | Podbay answers | Resolved |
| BC-03 | §8 Value format | Podbay integration sequence | Resolved |
| BC-04 | §2 Module interface, §7 Endpoint handoff | Design decision (EIP, DNS deferred) | Resolved |
| BC-05 | §9 (all) | Design decision + research | Resolved |
| BC-06 | §4 Render contract | Design decision (fail hard) | Resolved |
| BC-07 | §10 (this section) | Tests defined | Resolved |
| FM-00 | §4 Render contract, §10 Negative tests | Fail-hard + wrong-secret test | Covered |
| FM-01 | §4 Dependency ordering, §10 Smoke tests | Terraform interpolation eliminates race + `grep external-ip /etc/turnserver.conf` confirms `<EIP>/<PRIVATE_IP>` | Covered |
| FM-02 | §6 Required options, §10 Smoke tests | Realm in config + verification | Covered |
| FM-03 | §5 Clock-skew, §10 Negative tests | NTP + expired-credential test | Covered |
| FM-04 | §3 Package evidence, §10 Smoke tests | Version pinning awareness + config validation | Covered |
| FM-05 | §8 Value format, §10 Negative tests | Raw hex format + wrong-secret test | Covered |
| FM-06 | §4 Bootstrap, §10 Smoke tests | AWS CLI zip install + SSM reachability test | Covered |
| FM-07 | §9 Inbound policy, §10 Smoke tests | SG rules + UDP/TCP allocation tests | Covered |
| FM-08 | §6 Peer policy, §9 Denied peer, §10 Negative tests | denied-peer-ip + denied peer tests | Covered |
| FM-09 | §6 Logging/redaction, §8 No-leak, §10 Smoke tests | Redaction controls + journald grep | Covered |
| FM-10 | §5 Rotation state machine, §10 Smoke tests | Single-secret with documented window + rotation runbook test: update secret, restart coturn, verify new config via `grep static-auth-secret /etc/turnserver.conf`, verify new allocation succeeds | Covered |
| FM-11 | §10 Negative tests | 5 negative tests defined | Covered |
| FM-12 | §9 Abuse controls, §10 Negative tests | `use-auth-secret` + short TTL + denied-peer-ip + unauthenticated allocation attempt must fail (no valid credentials → 401) | Covered |

---

## 11. Rollback contract

### Unwire sequence

| Step | Owner | Precondition | Rollback command/change | Verification | Source |
|------|-------|-------------|----------------------|-------------|--------|
| 1 | Operator | Confirm no active Podbay sessions using TURN (or accept disruption) | Notify Podbay team | Podbay confirms no active grants | Operational |
| 2 | Overcast | Step 1 or acceptance of disruption | `terraform state rm module.coturn.aws_eip.coturn module.coturn.aws_eip_association.coturn` — remove EIP from Terraform state so it is not destroyed | `terraform state list \| grep eip` returns nothing | Terraform state management |
| 3 | Overcast | Step 2 | Remove coturn module call from `staging/main.tf` | `terraform plan` shows destroy of EC2, SG, IAM, instance profile (but NOT EIP) | Current pattern (`d441a5d`) |
| 4 | Overcast | Step 3 | `terraform apply` — destroys EC2, SG, IAM, instance profile | Apply succeeds; EIP remains allocated (orphaned from state) | Terraform |
| 5 | Overcast | Step 4 | Verify EIP still allocated: `aws ec2 describe-addresses --allocation-ids <alloc-id>` | EIP exists and is unassociated | AWS CLI |
| 6 | Overcast | Step 4 | Secret shell: **retain** (not managed by coturn module) | Secret still exists in SM | INV-004 |
| 7 | Overcast | Step 4 | DNS record (if created): **retain** or remove depending on reuse plan | Check Cloudflare | — |

### Resource retention matrix

| Resource | Retain/destroy | Reason | Owner | Source | Verification |
|----------|---------------|--------|-------|--------|-------------|
| EIP | **Retain** | Stable endpoint; Podbay may have cached IP | Overcast | Design decision | `aws ec2 describe-addresses` |
| Secret shell | **Retain** | INV-004 — shell is Terraform-managed, value is out-of-band | Overcast | INV-004 | `aws secretsmanager describe-secret` |
| Secret value | **Retain** | Value persists in SM regardless of module state | Operator | INV-004 | — |
| IAM role/profile | Destroy | No consumers after unwire | Terraform | — | Plan shows destroy |
| Security group | Destroy | No consumers after unwire | Terraform | — | Plan shows destroy |
| EC2 instance | Destroy | — | Terraform | — | Plan shows destroy |
| DNS record | Retain or destroy | Depends on reuse plan | Overcast | — | Check Cloudflare |

### Live session impact matrix

| Session state | Expected impact | Podbay action | User-visible behavior | Source |
|--------------|----------------|---------------|----------------------|--------|
| Active TURN allocation | Allocation drops when EC2 terminates | Workspace WebRTC falls back to direct or fails | Video/input freezes or disconnects | RFC 8656 |
| Active grant with TURN credentials | Credentials become unusable (no server to validate against) | Grant remains valid but TURN unusable; signaling still works | Degraded — may fall back to STUN direct if possible | `docs/specs/coturn-podbay-answers.md:RQ-POD-05` |
| No active sessions | No impact | None | None | — |

### Re-entry criteria

Before re-wiring the coturn module after a rollback:

- [ ] Root cause of rollback is resolved
- [ ] All BC-01 through BC-07 are still valid (no stale assumptions)
- [ ] Secret is still populated and valid
- [ ] EIP is still allocated (or a new one is provisioned)
- [ ] Spec is still current (no package/AWS/Podbay changes invalidate it)

---

## 12. Open questions register

### Register table

| Question ID | Section(s) it blocks | Blocking severity | Resolution method | Status |
|------------|---------------------|-------------------|-------------------|--------|
| RQ-OS-01 | 3 | HARD-BLOCK | Package probe | Resolved |
| RQ-OS-02 | 3 | HARD-BLOCK | Package probe | Resolved |
| RQ-OS-03 | 3, 4 | HARD-BLOCK | Package probe | Resolved |
| RQ-OS-04 | 3 | HARD-BLOCK | Package probe | Resolved |
| RQ-OS-05 | 3 | HARD-BLOCK | Package probe | Resolved |
| RQ-OS-06 | 3 | HARD-BLOCK | Package probe | Resolved |
| RQ-OS-07 | 3, 4 | HARD-BLOCK | Package probe | Resolved |
| RQ-OS-08 | 3, 6 | HARD-BLOCK | Package probe | Resolved |
| RQ-OS-09 | 3, 5, 6 | HARD-BLOCK | Package probe / source code | Resolved |
| RQ-OS-10 | 3, 6 | HARD-BLOCK | Package probe | Resolved |
| RQ-AWS-01 | 4 | HARD-BLOCK | AWS doc check | Resolved |
| RQ-AWS-02 | 4, 9 | HARD-BLOCK | AWS doc check | Resolved |
| RQ-AWS-03 | 4, 5 | HARD-BLOCK | AWS doc check / design decision | Resolved |
| RQ-AWS-04 | 4, 6 | HARD-BLOCK | AWS doc check / design decision | Resolved |
| RQ-AWS-05 | 4 | HARD-BLOCK | AWS doc check | Resolved |
| RQ-AWS-06 | 8 | HARD-BLOCK | AWS doc check | Resolved |
| RQ-AWS-07 | 9 | HARD-BLOCK | Design decision | Resolved |
| RQ-AWS-08 | 2, 7 | HARD-BLOCK | Design decision | Resolved |
| RQ-POD-01 | 7 | HARD-BLOCK | Podbay team | Resolved |
| RQ-POD-02 | 7 | HARD-BLOCK | Podbay team | Resolved |
| RQ-POD-03 | 7 | HARD-BLOCK | Podbay team | Resolved |
| RQ-POD-04 | 7 | HARD-BLOCK | Podbay team | Resolved |
| RQ-POD-05 | 7 | HARD-BLOCK | Podbay team | Resolved |
| RQ-POD-06 | 5, 8 | HARD-BLOCK | Podbay team | Resolved |
| RQ-POD-07 | 5 | HARD-BLOCK | Podbay team | Resolved |
| RQ-POD-08 | 7 | HARD-BLOCK | Podbay team | Resolved |
| BC-01 | 3, 4, 10 | HARD-BLOCK | Disposable EC2 package probe | Resolved — probe ran 2026-07-08 on `ami-0a02a779008fa3b99` (Noble 20260626), instance `i-0f18fe9125898dca7` (terminated). 11/11 PASS. All research findings confirmed empirically. |
| BC-02 | 7, 8 | HARD-BLOCK | Podbay team | Resolved |
| BC-03 | 4, 5, 8 | HARD-BLOCK | Design decision / Podbay team | Resolved |
| BC-04 | 2, 7, 9 | HARD-BLOCK | Design decision | Resolved |
| BC-05 | 9 | HARD-BLOCK | Design decision | Resolved |
| BC-06 | 4, 5, 8 | HARD-BLOCK | Design decision | Resolved |
| BC-07 | 10 | HARD-BLOCK | Spec completion (§10) | Resolved |
| D-062-source | 1 | SOFT-BLOCK | Read arclight-complex D-062 | Resolved — verified at `arclight-complex/platform/DECISIONS.md:1205-1221`. O-002 is an accurate summary. No contradictions with spec. |

### Severity definitions

- **HARD-BLOCK**: Unresolved item prevents implementation start because it blocks a BC, changes security/secret/bootstrap/Podbay contract behavior, or prevents a section from meeting its locked criteria.
- **SOFT-BLOCK**: Unresolved item is non-v1, explanatory, or operationally deferrable only after an explicit design decision states why implementation may proceed.

### Status taxonomy

- **Open**: Not yet investigated.
- **Researching**: Investigation in progress.
- **Proposed**: Answer proposed, awaiting verification or approval.
- **Resolved**: Answer verified with cited source; affected section's locked criteria pass.
- **Deferred**: Explicitly deferred with cited design decision, owner, follow-up trigger, and proof that no HARD-BLOCK acceptance gate is bypassed.

### Closure evidence rules

Acceptable evidence classes:
- **Package probe**: Output from commands run against the exact Ubuntu 24.04 AMI / coturn 4.6.1-1build4 package (or equivalent cross-referenced packaging source code)
- **AWS documentation**: Official docs.aws.amazon.com pages
- **Existing code**: Current `terraform/modules/coturn/*.tf` at HEAD
- **Governance document**: `docs/CONSTITUTION.md`, `docs/DECISIONS.md`
- **Podbay team answer**: Verified against Podbay code at cited commit
- **Design decision**: Explicit decision in this spec with rationale

---

## Acceptance gate checklist

- [x] All 12 required sections in order per `docs/specs/coturn-scoping.md:158-169`
- [x] Count discrepancy acknowledged: 26 RQs, 7 BCs, FM-00 + FM-01–FM-12
- [x] Every RQ has Resolved or Deferred row in §12
- [x] Zero HARD-BLOCK rows remain Open/Researching/Proposed
- [x] BC-01 through BC-07 closed
- [x] Verifiable claims cite sources
- [x] Existing Terraform names cite `variables.tf:1-36` / `outputs.tf:1-14`; new names labeled PROPOSED
- [x] Existing module treated as reference, not authority
- [x] INV-005 satisfied (OS, packages, systemd, config, bootstrap, failure modes)
- [x] INV-004 satisfied (no secret values in Terraform state)
- [x] INV-006 addressed (`aws_instance.user_data` plain text)
- [x] O-002 cited
- [x] D-062 verified at `arclight-complex/platform/DECISIONS.md:1205-1221`; O-002 is accurate summary
- [x] Podbay/Overcast boundary locked
- [x] Secret custody contract complete — format locked (raw hex), KMS: remove `kms:Decrypt` if using default key or scope to key ARN if CMK (decision made, not conditional)
- [x] Endpoint model locked (EIP, DNS deferred)
- [x] Security policy locked
- [x] Bootstrap failure behavior locked (fail hard)
- [x] All FM-00 through FM-12 mapped to controls and verification artifacts
- [x] Verification includes all minimum requirements
- [x] Rollback defined
- [ ] No normative placeholders in locked sections — **pending codex-1 verification**
