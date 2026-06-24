# ShuttleForge — D-056 Infrastructure Spec Review Response

> **Date**: 2026-06-22
> **Module state**: At HEAD on appliance/main
> **Reviewed**: `arclight-complex/docs/proposals/production-infrastructure-spec.md`

---

## SF-Q1: Dataplane protocol

**HTTP proxy protocol — plain HTTP forwarding + HTTPS via CONNECT tunnels. No SOCKS. No raw TCP.**

- Instance A runs `mode=["regular@{proxy_port}"]` — mitmproxy "regular" mode = explicit HTTP proxy (`engine.py:38-39`)
- Instance B runs `mode=["regular@{mitm_port}"]` — same protocol, adds MITM interception (`engine.py:79-80`)
- SmartRoutingAddon handles `http_connect` (CONNECT tunnels) and `requestheaders` (plain HTTP) (`routing.py:1-8`)
- Both ports (9050, 9100) speak the same protocol; the difference is interception behavior

**ALB will NOT work for the dataplane.** ALB is L7 HTTP; CONNECT requests would be rejected or misrouted.

**For v1 with Podbay workspaces as the only consumer**: Cloud Map private DNS is sufficient. No NLB needed. Add NLB only if external dataplane consumers appear.

**Amendment**: `NET_ADMIN` and `ip_forward=1` from docker-compose are NOT required by the current codebase. Regular mode doesn't need transparent proxy capabilities. Fargate compatible as-is.

## SF-Q2: Control/data split

**Single process. Cannot split for v1.**

- Single `lifespan()` manages both FastAPI and mitmproxy (`main.py:878-1073`)
- `snapshot_queue` is an `asyncio.Queue` — in-process only (`main.py:940-941`)
- Lease publish callback is a closure over `_lease_store` — requires same process (`main.py:204-309`)
- SIGHUP handler reloads policy by in-process mutation (`main.py:316-358`)

**Splitting would require**: externalize snapshot distribution, externalize lease state, separate Alembic lifecycle, replace SIGHUP with external reload.

**Recommendation for v1**: Single ECS task with multiple port mappings. Split is v2.

**Multi-replica note**: 2+ tasks need NLB with connection draining. Session affinity matters for in-flight CONNECT tunnels. The dataplane carries connection-scoped metadata (stickiness caches) that is per-connection, not shared.

## SF-Q3: Dataplane public endpoint

**No. Private-to-VPC is correct.**

- All ports bound to `127.0.0.1` in dev (`docker-compose.yml:5-8`)
- `allow_admin_public` / `allow_control_public` guards exist to prevent accidental public binding (`config.py:69-70`)
- Consumers are VPC-internal (Podbay workspaces, future Nerfherder)

Control plane (9000) can be exposed via ALB for operator access if desired.

## SF-Q4: Provider credentials

**In the database, AES-256-GCM envelope-encrypted. Not from config files or plain env vars.**

- `api_credentials_encrypted` + `api_credentials_dek` per record (`provider.py:42-48`)
- `key_version` tracks KEK ring version (`provider.py:49`)
- KEK ring from `SHUTTLEFORGE_KEK_RING_B64` env var (`config.py:34-35`)
- Decrypted credentials held in-memory only in `EndpointEntry` (`snapshot.py:33-35`)

**Mapping to Secrets Manager**: KEK ring → Secrets Manager → task def env injection. Provider credentials stay in RDS (encrypted at rest + envelope encryption). Compatible.

**Required change**: `config.py:86-87` currently builds SQLite URL. Needs `SHUTTLEFORGE_DB_URL` env var override for PostgreSQL connection string. Config change, not architecture.

## SF-Q5: Network requirements

**TCP only. No UDP, no exotic ports.**

- All three ports (9000, 9050, 9100) are TCP
- `nofile: 65536` ulimit required for high concurrent connections
- `NET_ADMIN` cap: NOT required
- `ip_forward=1` sysctl: NOT required
- Fargate compatible

**Outbound egress**: Provider proxy endpoints via NAT Gateway (typically port 80/443/various). NAT EIP is what providers see. With 2 AZs = 2 NAT GWs = 2 EIPs — providers may need both allowlisted.

## ShuttleForge task definition shape

| Concern | Value |
|---------|-------|
| Ports | 9000 (control, ALB target), 9050 (proxy, Cloud Map), 9100 (MITM, Cloud Map) |
| Health check | `GET /ready` on 9000 |
| CPU/memory | 512 CPU / 1024 MB minimum |
| Ulimits | nofile 65536 |
| Secrets (6) | KEK_RING_B64, LISTENER_AUTH_HMAC_KEY, LEASE_HMAC_KEY, OPERATOR_TOKEN, DB connection string, CORE_JWKS_URL |
| Migration | `SHUTTLEFORGE_SKIP_MIGRATIONS=true` on app tasks; one-off migration task (already supported) |
| Storage | `/data/flows` (CAS) and `/data/certs` (mitmproxy CA) — ephemeral or EFS |

## Amendments needed in spec

| # | Item | Action |
|---|------|--------|
| 1 | §6 dataplane networking | Dataplane via Cloud Map DNS, not ALB. No NLB for v1. |
| 2 | §6 NET_ADMIN/ip_forward | Not required. Fargate compatible. |
| 3 | §6 "control plane only" framing | v1 is single task with both planes. Split is v2. |
| 4 | §7 database dialect | Needs SHUTTLEFORGE_DB_URL override for PostgreSQL. |
| 5 | §8 secrets | 6 confirmed secrets (expanded from generic). |

**All amendments adopted in spec.**
