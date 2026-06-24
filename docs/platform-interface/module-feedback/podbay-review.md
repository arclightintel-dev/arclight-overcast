# Podbay — D-056 Infrastructure Spec Review Response

> **Date**: 2026-06-22
> **Module state**: Phase 2 spec cycle on branch `claude-dev-phase-2`. Phase 1 + hardening merged (PR #3, 619 tests). Spec locked at v1.0.0.
> **Reviewed**: `arclight-complex/docs/proposals/production-infrastructure-spec.md`

---

## 1. ECSAdapter feasibility

**The protocol was designed for this.** `SubstrateAdapter` (`protocol.py:128-174`) is a 6-method Protocol — `create_runtime`, `destroy_runtime`, `get_runtime_status`, `probe_readiness`, `remove_volume`, `list_owned_runtimes`. Data shapes (`RuntimeSpec`, `CreateResult`, etc.) are backend-agnostic. `DockerAdapter` is the only impl; `ECSAdapter` slots in at the same interface.

**Key gaps:**

| DockerAdapter | ECSAdapter equivalent | Gap |
|---|---|---|
| `docker.containers.run()` → container | `ecs.run_task()` → task ARN | Return shape: `substrate_ref` = task ARN |
| Container IP on runtime network | Task private IP via CloudMap or `describe_tasks` | Async discovery — need poll-until-assigned |
| Docker volume create + mount | EBS volume via task definition | ECS-managed EBS is per-task, not named volumes |
| `container.attrs["NetworkSettings"]` | `describe_tasks` → `attachments[].details` | Different API shape |
| Labels for ownership | ECS task tags | Tag API vs label API |
| `/json/version` probe via container IP | Same — task private IP + port | No gap if task has reachable IP |

**Effort estimate**: 2-3 weeks focused work. Protocol interface needs zero changes.

**Phase timing**: Phase 3 or parallel production-hardening track. Not Phase 2 scope.

## 2. Docker socket bridge

**Works on ECS-on-EC2.** Current Dockerfile has socket GID fixup (`docker/entrypoint.sh:14-21`). DockerAdapter calls `docker.from_env()`.

**Caveat**: `PODBAY_RUNTIME_NETWORK` (S-014) requires a Docker network both controller and workspace containers share. On ECS-on-EC2, this means a pre-created host-local Docker network — ECS doesn't manage these. Operationally fragile.

**Retirement plan required.** Bridge works for initial deployment; retire when ECSAdapter ships. Target: before first external user.

## 3. Browser stream over ALB

**ALB WebSocket support is sufficient.** Browser → ALB → Podbay controller → private workspace task. Controller proxies the noVNC/WebSocket internally. ALB upgrades HTTP to WebSocket on HTTPS listeners. Same ALB listener as REST API, differentiated by path.

**Critical**: ALB default idle timeout is 60s. Browser streams are long-lived. Set `idle_timeout.timeout_seconds = 3600` on the Podbay target group. Also implement WebSocket ping/pong keepalives.

## 4. EBS sizing

**2 GB per workspace sufficient for Phase 2.** Collection volume holds screenshots (10-50 KB), page archives (100 KB - 2 MB), operator notes (< 1 KB), file downloads (bounded by TTL).

**Lifecycle compatible with seal/export:**

| Spec lifecycle | EBS equivalent |
|---|---|
| `writable` | Attached EBS, filesystem writes |
| `sealing` → `immutable` | Snapshot-copy within container (sealed content root) |
| `export_pending` → `exported` | Package to S3 via SEAM-015 |
| `archived` | S3 object (EBS deleted) |
| `discarded` | S3 TTL / manual delete |

**Note**: Application-level seal runs inside the container. EBS-level snapshot is for recovery, not the seal mechanism.

## 5. 12-Point Browser Workspace Runtime Gate

| # | Gate item | Current state | Production readiness |
|---|-----------|---------------|----------------------|
| a | Browser sandbox | `--no-sandbox` only via `PODBAY_DISABLE_SANDBOX=1` (dev/CI); sandbox enabled by default | **Sandbox enabled in production.** Env var must NOT be set. |
| b | Sandbox mode | Chromium `--sandbox` (default). No seccomp/AppArmor profiles documented. | **Chromium namespace sandbox requires `SYS_ADMIN` or a seccomp profile allowing `clone(CLONE_NEWUSER)`.** |
| c | Linux capabilities | Currently `cap_drop: ["ALL"]` in RuntimeSpec defaults (`protocol.py:42`). | **Needs `SYS_ADMIN` added back explicitly.** |
| d | `SYS_ADMIN` | Required for Chromium namespace sandbox without `--no-sandbox`. | **Required.** Acceptable tradeoff: `SYS_ADMIN` for one container < Docker socket for host. |
| e | `/dev/shm` size | `--disable-dev-shm-usage` flag set (`entrypoint.sh:26`); RuntimeSpec default `shm_size: 256m` (`protocol.py:45`). | **256 MB + `--disable-dev-shm-usage` as belt-and-suspenders.** Set ECS `sharedMemorySize: 256`. |
| f | Seccomp/AppArmor | **Not documented.** No `.json` seccomp profile in repo. | **PRODUCTION BLOCKER.** Must produce Chromium-specific seccomp profile OR document `SYS_ADMIN` exception as S-series decision. |
| g | `--no-sandbox` in production | Forbidden by design. Only via env var. | **Correct.** Add pre-deploy check. |
| h | Host devices/privileged/socket | Workspace tasks need none. Controller uses socket only in bridge mode. | **Workspace tasks clean.** Controller bridge is temporary. |
| i | ECS-on-EC2 confirmed | Yes — Fargate can't do `SYS_ADMIN` or custom `sharedMemorySize`. | **Confirmed ECS-on-EC2 only.** |
| j | Workspace state persistence | Session scratch ephemeral. Collection via seal/export. Cookies/profile on session volume (ephemeral). | **Explicit policy: no cookie/profile persistence in Phase 2.** |
| k | Target egress through ShuttleForge | **Phase 2 does NOT include transport.** `require_transport: false` (SS1.4 non-goal). | **DISCREPANCY — see below.** |
| l | Attach paths authenticated + time-bounded | Browser stream grant-authenticated (SS7), session-scoped, short-lived. No raw port exposure (S-014). | **Correct.** |

## Critical discrepancy: target egress (item k)

Spec says "All target-facing egress from browser workspaces MUST route through ShuttleForge leases." Phase 2 explicitly defers transport (`require_transport: false`, SS1.4 non-goal). These contradict.

**Recommendation**: Option A — D-056 should say "all target-facing egress from *transport-enabled* browser workspaces MUST route through ShuttleForge." Phase 2 `manual_browse_basic` is explicitly non-transport; direct egress is the accepted posture for the first operator milestone. Record as D-056 narrowing.

**Adopted in spec amendment.**

## 6. Concerns

**No fundamental concerns with ECS for Podbay.** Three operational items:

1. **EBS volume creation latency.** gp3 creation + attachment adds seconds to workspace launch. May need provisioning sub-phase or increased timeout.

2. **Task IP discovery timing.** `ecs.run_task` returns before task has a private IP. `probe_readiness` loop handles retries. May need CloudMap DNS name instead of IP for `cdp_upstream_address`.

3. **Seccomp profile is the real blocker.** Item (f) needs work before any production browser launch. Phase 2 hardening deliverable or parallel production-readiness task.
