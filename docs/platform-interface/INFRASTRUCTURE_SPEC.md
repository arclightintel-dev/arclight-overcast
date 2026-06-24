# Production Infrastructure Spec — AWS

> **Status**: MODULE REVIEW COMPLETE. Ready for D-056 ratification.
> **Produced**: 2026-06-22 | **Amended**: 2026-06-22 (module review feedback incorporated)
> **Author**: claude-main, incorporating external infrastructure review + Core/ShuttleForge/Podbay review responses
> **Module buy-in**: Core (Phase 4 complete, 359 tests), ShuttleForge (at HEAD), Podbay (Phase 2 spec locked)
> **Implementation repo**: `arclight-overcast` (Terraform)
> **Domain**: [chosen domain] — deliberately anodyne, not connected to public-facing identity

---

## 1. Architecture Decision

Arclight production runs on AWS using Terraform-managed infrastructure.

- Core runs as **ECS Fargate** in private subnets. ShuttleForge runs as a **single ECS Fargate task** with both control plane (port 9000) and dataplane (ports 9050/9100) — they are one process with shared event loop and in-memory IPC; splitting is a v2 optimization.
- Podbay runs on **ECS backed by a dedicated EC2 capacity provider** for browser/workspace workloads. Not a hand-managed EC2 snowflake — one ECS cluster with mixed capacity providers.
- All public HTTP traffic terminates at an **ACM-backed Application Load Balancer** using host-based routing.
- All service-to-service traffic uses **private ECS Service Connect / Cloud Map DNS**.
- **RDS PostgreSQL** is shared per environment with per-module databases and roles.
- Secrets live in **AWS Secrets Manager / SSM Parameter Store** and are injected by task definitions.
- The first OIDC deployment uses **direct external IdP integration through Core**. No Keycloak, Cognito, or Auth0 broker.
- Infrastructure as code: **Terraform** (HCL, OpenTofu-compatible).

---

## 2. Network Topology

One VPC per environment, at least two Availability Zones.

```
┌─────────────────────────────────────────────────────────────┐
│ VPC (10.0.0.0/16)                                           │
│                                                             │
│  Public subnets (10.0.1.0/24, 10.0.2.0/24)                │
│    ├── Application Load Balancer (public)                   │
│    └── NAT Gateway (if needed — minimize via VPC endpoints) │
│                                                             │
│  Private app subnets (10.0.10.0/24, 10.0.11.0/24)          │
│    ├── Core (ECS Fargate)                                   │
│    ├── ShuttleForge control plane (ECS Fargate)             │
│    ├── Podbay controller (ECS on EC2 capacity provider)     │
│    └── Podbay workspace tasks (ECS on EC2 capacity provider)│
│                                                             │
│  Private database subnets (10.0.20.0/24, 10.0.21.0/24)     │
│    └── RDS PostgreSQL                                       │
└─────────────────────────────────────────────────────────────┘
```

**No ECS task or Podbay EC2 host has a public IP.** Use SSM Session Manager for emergency host access, not SSH.

**VPC Endpoints** (to minimize NAT Gateway cost): ECR, CloudWatch Logs, Secrets Manager, SSM, KMS, S3. Keep NAT only for external internet access (IdP token exchange, provider APIs, package updates).

---

## 3. Public Traffic Flow

```
Route 53 alias records
  → ACM TLS certificate (auto-renewed)
    → Public ALB (host-based routing)
      → core.[domain]         → Core ECS Fargate target group
      → podbay.[domain]       → Podbay controller target group
      → shuttleforge.[domain] → ShuttleForge control plane target group (if public operator access needed)
```

ALB health checks target each module's `/ready` endpoint (D-052). Unhealthy targets are removed from rotation.

---

## 4. Internal Service Discovery

Services reference each other via **private Cloud Map DNS**, not public ALB URLs. Internal traffic never exits the VPC.

```
core.prod.arclight.local
shuttleforge.prod.arclight.local
podbay.prod.arclight.local
```

### URL Split (critical for OIDC)

Three distinct URL concerns. Do not collapse them.

**JWT issuer (`iss`) is a platform contract const**: `https://core.internal` — hardcoded in `jwt-claims.schema.json`, validated at startup. This is NOT the public URL. Modules validate `iss` against this literal value, regardless of which URL they fetched JWKS from. (Core review finding.)

| Variable | Value | Used for |
|----------|-------|----------|
| `CORE_ISSUER` | `https://core.internal` | JWT `iss` claim (platform const, never changes). Modules validate against this literal. |
| `CORE_BASE_URL` | `https://core.[domain]` | OIDC browser redirects (`/auth/login`, `/auth/callback`). This is the public URL users see. |
| `CORE_INTERNAL_URL` | `http://core.prod.arclight.local:8000` | Module-to-module service calls |
| `CORE_JWKS_URL` | `http://core.prod.arclight.local:8000/.well-known/jwks.json` | JWT validation (internal, not through ALB) |
| `CORE_TOKEN_URL` | `http://core.prod.arclight.local:8000/oauth/token` | Service-to-service token acquisition (internal) |
| `PODBAY_PUBLIC_URL` | `https://podbay.[domain]` | Browser access, OIDC redirect target |
| `PODBAY_INTERNAL_URL` | `http://podbay.prod.arclight.local:8099` | Service calls from Nerfherder (future) |
| `SHUTTLEFORGE_PUBLIC_URL` | `https://shuttleforge.[domain]` | Operator API (if exposed) |
| `SHUTTLEFORGE_INTERNAL_URL` | `http://shuttleforge.prod.arclight.local:9000` | Lease/tender requests from Podbay/Nerfherder |

**Key separation**: `CORE_ISSUER` (JWT const, `https://core.internal`) ≠ `CORE_BASE_URL` (public URL for browser redirects, `https://core.[domain]`) ≠ `CORE_INTERNAL_URL` (private service calls). Modules fetch JWKS from the internal URL and validate `iss` against the const. These are independent operations.

---

## 5. OIDC / Authentication Flow

Direct external IdP integration through Core. No intermediate broker service.

```
1. User opens https://podbay.[domain]
2. Podbay redirects to Core /auth/login?audience=podbay-api
3. Core redirects to external IdP (Google/Microsoft/GitHub)
4. IdP authenticates user, redirects to Core /auth/callback
5. Core validates IdP tokens, provisions/resolves Arclight principal, creates session
6. Core redirects to Podbay with session token
7. Podbay validates Core-issued JWTs via JWKS (internal URL)
```

**Core is the Arclight authority service.** Core uses external IdPs as upstream identity sources. Core issues Arclight tokens to modules. Modules validate Core-issued tokens. This is the existing D-028 model deployed to production.

**Note**: The current Core implementation returns a session token via redirect after callback — there is no Podbay-to-Core server-to-server authorization-code exchange. If that pattern is desired (more secure), it requires new work in both Core and Podbay. For v1, the redirect-with-session-token flow is what ships. (Core review finding.)

**Nonce cache warning**: Core's OIDC nonce cache is in-memory. With 2+ Core tasks behind ALB, a login started on task A could callback to task B which doesn't have the nonce. Fix: ALB sticky sessions for `/auth/*` paths, or move nonces to RDS/ElastiCache. (Core review finding — known deferral.)

---

## 6. Compute Layout

### Core (ECS Fargate)

- Desired count: 1 for bootstrap, 2 across AZs for production
- Stateless — all state in RDS
- Runs Alembic migrations as a one-off ECS task before service deployment

### ShuttleForge (ECS Fargate — single task, both planes)

- Desired count: 1 for bootstrap. Multi-replica note: 2+ tasks need NLB with connection draining for session affinity on in-flight CONNECT tunnels.
- **Single process**: control plane (port 9000, FastAPI) and dataplane (ports 9050 proxy, 9100 MITM) share one event loop with in-memory IPC (asyncio.Queue for snapshot distribution, closure-bound lease store). Splitting into separate ECS services requires externalizing snapshot distribution, lease state, and policy reload. That is a v2 optimization.
- **Dataplane protocol** (confirmed): Standard HTTP proxy — plain HTTP forwarding + HTTPS via CONNECT tunnels (RFC 7230/7231 §4.3.6). No SOCKS, no raw TCP. mitmproxy "regular" mode on both proxy ports.
- **Dataplane networking**: ALB will NOT work for the dataplane — ALB is L7 HTTP and rejects/misroutes CONNECT requests. For v1 with Podbay workspaces as the only consumer (VPC-internal), **Cloud Map private DNS is sufficient** — no NLB needed. Add NLB only if external dataplane consumers appear.
- **Linux capabilities**: `NET_ADMIN` and `ip_forward` from docker-compose are NOT required by the current codebase (regular mode, not transparent proxy). Fargate compatible as-is. Only `nofile: 65536` ulimit is required for high concurrent connections.
- **Provider credentials**: AES-256-GCM envelope-encrypted in the database (per-record DEK, KEK ring from `SHUTTLEFORGE_KEK_RING_B64` env var). KEK ring moves to Secrets Manager; provider credentials stay in RDS (encrypted at rest + envelope encryption). Not plaintext env vars.
- **Database**: Currently SQLite. Needs a `SHUTTLEFORGE_DB_URL` env var override for PostgreSQL connection string. Config-level change — SQLAlchemy async is already dialect-agnostic.

**ShuttleForge task definition shape:**

| Concern | Value |
|---------|-------|
| Ports | 9000 (control, ALB target), 9050 (proxy, Cloud Map), 9100 (MITM, Cloud Map) |
| Health check | `GET /ready` on 9000 |
| CPU/memory | 512 CPU / 1024 MB minimum (tune for connection volume) |
| Ulimits | nofile 65536 |
| Secrets (6) | KEK_RING_B64, LISTENER_AUTH_HMAC_KEY, LEASE_HMAC_KEY, OPERATOR_TOKEN, DB connection string, CORE_JWKS_URL |
| Migration | `SHUTTLEFORGE_SKIP_MIGRATIONS=true` on app tasks; migration as separate one-off ECS task (already supported) |

### Podbay (ECS on EC2 capacity provider)

Split into three concerns:

| Concern | Deployment |
|---------|-----------|
| Podbay controller/API | ECS service on EC2 capacity provider |
| Workspace runtime tasks | ECS RunTask on dedicated EC2 capacity provider |
| Workspace state volumes | Encrypted gp3 EBS volumes, created per task (see EBS model below) |

**Production direction**: Podbay controller should launch workspace tasks via ECS APIs (RunTask), not Docker socket mount. Docker socket mount is a security liability in production — socket access is effectively host-level power, meaning a controller compromise becomes a host compromise and then a cross-session workspace compromise. The controller calls ECS to run a workspace task definition; ECS handles placement, health, and cleanup.

**Docker socket is explicitly rejected for production** unless approved as a temporary bridge with a documented retirement plan. The correct adapter model:

```
RuntimeProvider
  ├── DockerAdapter     # local/dev
  └── ECSAdapter        # AWS/prod (calls ecs.run_task())
```

**EBS volume model**: ECS-managed EBS volumes are created per task and deleted on termination. They cannot be directly reattached to another task. The correct workspace state lifecycle is:

```
Active workspace:     ECS task + attached EBS volume
Workspace seal:       Snapshot EBS volume content to S3 (SEAM-015 export)
Workspace terminate:  EBS volume deleted with task
Workspace recovery:   Launch new task, seed from S3 snapshot
Long-term artifacts:  S3 object storage + metadata in RDS
```

Do NOT build persistent reattachable EBS volumes for workspace migration. That is v2+ if needed — snapshot/restore is sufficient for v1.

**Target-facing egress**: All target-facing browsing from **transport-enabled** Podbay workspaces MUST route through ShuttleForge leases (SEAM-004, SEAM-013), not AWS NAT Gateway. An operator browsing PLAP through an AWS datacenter IP is a fundamentally different operation than browsing through a ShuttleForge-managed proxy. ShuttleForge owns egress policy, route selection, and provider pools.

**Phase 2 exception** (Podbay review finding): Phase 2 `manual_browse_basic` explicitly defers ShuttleForge transport (`require_transport: false`, Phase 2 spec SS1.4 non-goal). Phase 2 workspaces use direct egress via NAT Gateway. This is the accepted posture for the first operator milestone. ShuttleForge egress becomes mandatory at Phase 3 when transport ships. The D-056 rule applies to production workspaces with transport, not Phase 2 MVP.

Direct AWS NAT egress is acceptable for: Phase 2 `manual_browse_basic` workspaces (pre-transport), package updates, health checks, AWS API calls.

**Resource isolation**: Core and ShuttleForge run on Fargate (separate capacity). Podbay workspaces run on the EC2 capacity provider. Browser workspaces cannot starve Core or ShuttleForge.

### Podbay Attach Path

Browser workspace access is proxied through the Podbay controller, not directly routed by the ALB:

```
Browser → podbay.[domain] → ALB → Podbay controller → private workspace task
```

Podbay returns attach metadata and proxies the browser stream (noVNC/WebSocket) to the private workspace task. The workspace task has no public endpoint. This matches the existing Podbay launch-flow design.

**ALB idle timeout** (Podbay review finding): Browser stream connections are long-lived. ALB default idle timeout is 60s. Set `idle_timeout.timeout_seconds` to 3600 on the Podbay target group, or implement WebSocket ping/pong keepalives in the stream proxy. Both is recommended.

---

## 7. Database

**One RDS PostgreSQL instance per environment**, with separate databases and roles per module:

```
core_prod           (user: core_prod, migrations: Core Alembic)
shuttleforge_prod   (user: sf_prod, migrations: ShuttleForge Alembic)
podbay_prod         (user: podbay_prod, migrations: Podbay Alembic)
nerfherder_prod     (user: nf_prod, reserved — created empty)
```

- Single-AZ for staging. Multi-AZ for production with real users (budget-dependent).
- Storage: gp3 (baseline IOPS included, $0.08/GB-month).
- Do NOT store large artifacts, browser profiles, screenshots, HAR/WARC captures, or workspace files in Postgres. RDS holds operational metadata. S3/EBS holds evidence/workspace bytes.

---

## 8. Secrets Management

| Category | Service | Examples |
|----------|---------|----------|
| Credentials / rotating secrets | Secrets Manager | DB passwords, OIDC client secrets, Core Fernet key, Core admin bootstrap secret, ShuttleForge provider credentials |
| Non-secret configuration | SSM Parameter Store | Log levels, feature flags, public URLs, capacity limits |
| Terraform-created secret shells | Secrets Manager | Structure and IAM permissions defined in Terraform; values populated out-of-band |

**Critical rule**: Terraform creates the secret entries and IAM permissions. Terraform does NOT write production secret values into state. Values are populated via AWS Console, CLI, or a tightly controlled one-time bootstrap script.

### Core-specific secrets

| Secret | Handling |
|--------|---------|
| `CORE_SIGNING_KEY_ENCRYPTION_KEY` | Secrets Manager. Rotate with application-level key-ring (MultiFernet), not blind replacement. |
| JWT signing keys | Core-owned JWK lifecycle. Publish active public keys through JWKS. Keep old keys until issued tokens expire. Rotate with overlapping validity windows. |
| Fernet keys | Key ring / MultiFernet. New key encrypts, old keys decrypt. Background migration re-encrypts. Then retire. |
| `CORE_ADMIN_BOOTSTRAP_SECRET` | One-time bootstrap only. Disable/delete after first `platform_owner` creation (D-031). |
| OIDC client secrets | Secrets Manager. Manual rotation initially. Runbook before automation. |
| DB credentials | Secrets Manager. RDS-generated or rotation-ready. |

**Core Fernet status** (Core review finding): Currently single-key only (`Fernet(key)` at ~4 callsites). MultiFernet key-ring rotation requires a Core code change before the first key rotation in production. Small change but not implemented.

**Core nonce cache** (Core review finding): OIDC nonces are in-memory. Single-task deployment works. Multi-task deployment behind ALB needs either sticky sessions for `/auth/*` or an external nonce store (RDS or ElastiCache). Known deferral.

### ShuttleForge secrets (confirmed, 6 entries)

| Secret | Source | Secrets Manager entry |
|--------|--------|----------------------|
| `SHUTTLEFORGE_KEK_RING_B64` | AES-256-GCM envelope key ring | Yes — ShuttleForge task role only |
| `SHUTTLEFORGE_LISTENER_AUTH_HMAC_KEY` | Dataplane auth | Yes |
| `SHUTTLEFORGE_LEASE_HMAC_KEY` | Lease credential signing | Yes |
| `SHUTTLEFORGE_OPERATOR_TOKEN` | Interim operator auth (until Core operator JWT) | Yes |
| `SHUTTLEFORGE_DB_URL` | PostgreSQL connection string (new — currently SQLite) | Yes |
| Core JWKS URL | `CORE_JWKS_URL` (internal URL) | SSM Parameter Store (not a secret) |

Provider API/proxy credentials stay in RDS (AES-256-GCM encrypted at rest with per-record DEK, KEK from Secrets Manager). Overcast does not need to provision individual provider credentials — only the KEK ring that unlocks them.

Do not pretend the full Core admin-asset-custody model exists until Core implements it. The D-032/D-040 custody model is designed but not built.

---

## 9. Boot Order and Deployment Sequence

```
1. Terraform creates: VPC, RDS, ECR, secrets shells, ECS cluster,
   capacity providers, ALB, Route 53, IAM roles, log groups
2. CI builds and pushes Core image to ECR
3. Run Core Alembic migration (one-off ECS task)
4. Deploy Core ECS service
5. Verify Core /ready through ALB + private service discovery
6. Run ShuttleForge migration (one-off ECS task)
7. Deploy ShuttleForge ECS service
8. Run Podbay migration (one-off ECS task)
9. Deploy Podbay controller ECS service
10. Launch a smoke-test Podbay workspace
11. Execute OIDC login smoke test (browser → Core → IdP → Core → Podbay)
12. Execute service-to-service JWT/JWKS smoke test
```

ECS does NOT provide a reliable cross-service boot graph. Boot order is encoded in the CI/CD pipeline and deployment runbook. Applications should retry dependency calls on startup — Core being Tier 0 does not mean every other process crashes permanently if Core is unavailable for 30 seconds during deployment.

Each module exposes `/ready` (fast probe, <3s, D-052) used as:
- ECS container health check (task-level)
- ALB target group health check (routing-level)

---

## 10. Monitoring and Operations

### Minimum production monitoring

| Concern | Tool | What to watch |
|---------|------|---------------|
| Application logs | CloudWatch Logs | One log group per service per environment |
| ALB health | ALB metrics | Response time, 5xx count, unhealthy targets |
| ECS health | ECS metrics | Desired vs running tasks, restarts, CPU/memory, deployment failures |
| RDS health | RDS alarms | CPU, storage, connections, freeable memory, failover state |
| Podbay EC2 | CloudWatch Agent | CPU, memory, disk/EBS usage, ECS agent health, workspace task failures |
| Secrets/IAM | CloudTrail | Failed secret access, denied task-role permissions |
| Backups | AWS Backup + RDS | RDS automated snapshots, EBS snapshots, S3 versioning |

Podbay disk usage and EBS snapshot health matter more than typical web-service CPU. Browser workspaces fail in operationally weird ways: disk full, session state corrupt, display proxy unhealthy, sidecar failed.

### Readiness endpoints (D-052)

Every module already implements `/ready` (fast probe) and `/ready/detail` (diagnostic). These are the ALB health check targets and the deployment verification check.

---

## 11. CI/CD

### ECR repositories

```
arclight/core
arclight/shuttleforge
arclight/podbay
arclight/podbay-workspace-browser
arclight/nerfherder  (reserved)
```

### Pipeline split

| Repo | Responsibility |
|------|---------------|
| Module repos | Build Docker image, run tests, push immutable tag to ECR |
| `arclight-overcast` | Owns infrastructure, task/service definitions. Promotes image tags into staging/prod. Runs migrations. Updates ECS services. Runs smoke tests. |

### Auth

GitHub Actions with **GitHub OIDC to assume AWS roles**. No long-lived AWS keys in GitHub secrets.

### Deployment strategy

Rolling ECS deployments for the first version. Blue/green (CodeDeploy) is available later but adds complexity not warranted before the first stable deployment.

---

## 12. Staging

Identical topology to production, smaller instances:

- Separate VPC, separate RDS, separate ECS cluster
- Subdomain: `staging.[domain]` or separate domain
- Same Terraform modules, different `terraform.tfvars`
- Smoke tests run against staging before production promotion

---

## 13. `arclight-overcast` Repo Structure

```
arclight-overcast/
  README.md
  docs/
    architecture-decision-aws-production.md
    runbooks/
      initial-bootstrap.md
      deploy-service.md
      rotate-secrets.md
      restore-rds.md
      restore-podbay-workspace.md
  terraform/
    modules/
      vpc/
      route53/
      acm/
      alb/
      ecs-cluster/
      ecs-service-fargate/
      ecs-service-ec2/
      ecs-ec2-capacity-provider/
      rds-postgres/
      ecr/
      secrets/
      s3/
      observability/
      iam-github-oidc/
    envs/
      staging/
        backend.tf, main.tf, variables.tf, terraform.tfvars.example
      prod/
        backend.tf, main.tf, variables.tf, terraform.tfvars.example
  .github/
    workflows/
      terraform-plan.yml
      terraform-apply.yml
      promote-image.yml
```

### Ownership boundary

| Owner | What |
|-------|------|
| `arclight-overcast` | Infrastructure (Terraform), ECR repos, task/service definitions, ALB/DNS/RDS/secrets/IAM, CI/CD pipeline, deployment runbooks |
| Module repos | Application code, Dockerfiles, `.env.example`, module-internal config defaults |
| `arclight-complex` | Platform governance, specs, contracts, architecture decisions |

---

## 14. Cost Estimate (us-east-1)

| Scale | Shape | Approx monthly |
|-------|-------|----------------|
| 1 user / MVP | 1 ALB, shared small RDS, 2 Fargate services, 1 Podbay EC2, modest EBS/S3, VPC endpoints | $200–$450 |
| 10 users | 2 Core tasks, 2 SF tasks, larger RDS, 1–2 Podbay EC2, more EBS/logs | $500–$1,200 |
| 50 users | Multiple Podbay EC2 hosts, Multi-AZ RDS, more EBS/S3/logging | $1,500–$4,000+ |

**Biggest cost trap**: NAT Gateway ($32/mo per AZ + data processing). Mitigate with VPC endpoints for AWS service traffic. Keep NAT only for external internet (IdP, provider APIs).

---

## 15. What NOT to Build Yet

- Auto-scaling policies (start with fixed desired capacity)
- Multi-region (single region, us-east-1)
- CDN / CloudFront (no static assets to cache)
- WAF (add when public exposure warrants)
- Nerfherder deployment (not production-ready)
- Admin asset custody infrastructure (D-032 — not implemented in Core)
- Blue/green deployments (rolling is sufficient for v1)
- Full Podbay ECS RunTask adapter (flag as production requirement; Docker socket bridge acceptable for initial deployment with explicit security constraints)

---

## 16. Module Review Questions

Module review complete. Questions answered, findings incorporated into the spec above.

### Core (Phase 4 complete, 359 tests)
1. **OIDC URL split**: Works via `CORE_BASE_URL` (public redirects) + `CORE_ISSUER` (JWT const `https://core.internal`). Issuer ≠ public URL — spec corrected.
2. **Alembic as ECS task**: Works today, no code changes needed. Split CMD in task definition.
3. **IdP recommendation**: Google. Easiest OAuth app registration, no approval needed.
4. **Fernet key-ring**: Single-key only. Needs MultiFernet migration (~4 callsites) before first rotation.
5. **Secrets**: Complete, no additions needed.
6. **Fargate**: No blockers. Nonce cache is in-memory (multi-task needs sticky sessions for /auth/*).
7. **Spec discrepancy found**: §5 OIDC flow described a Podbay↔Core code exchange that doesn't exist. Corrected to redirect-with-session-token.

### ShuttleForge (at HEAD)
1. **Dataplane protocol**: HTTP proxy (plain HTTP forwarding + HTTPS CONNECT tunnels). No SOCKS, no raw TCP.
2. **Control/data split**: Single process, shared event loop. Cannot split for v1. v2 optimization.
3. **Dataplane exposure**: Private-only (Cloud Map DNS). No NLB needed for v1.
4. **Provider credentials**: AES-256-GCM envelope-encrypted in DB (KEK ring from env). Compatible with Secrets Manager.
5. **Network**: TCP only. `NET_ADMIN`/`ip_forward` NOT required. `nofile: 65536` is required.
6. **Database**: SQLite → PostgreSQL needs `SHUTTLEFORGE_DB_URL` env var override (config change).
7. **Task shape confirmed**: 3 ports (9000/9050/9100), 6 secrets, migration skip flag supported.

### Podbay (Phase 2 spec locked)
1. **ECSAdapter**: Feasible, ~2-3 weeks. Protocol interface needs zero changes. Phase 3 effort.
2. **Docker socket bridge**: Works on ECS-on-EC2 as temporary bridge. Retirement plan required.
3. **ALB WebSocket**: Sufficient. Set idle timeout to 3600s. Implement ping/pong keepalives.
4. **EBS sizing**: 2 GB per workspace. Lifecycle compatible with seal/export model.
5. **12-point gate**: Answered in full (see table above). **Seccomp profile is the production blocker** (item 6).
6. **Target egress discrepancy found**: Phase 2 defers transport. D-056 narrowed to "transport-enabled workspaces."

### Pre-production items surfaced by module review

| Item | Owner | Severity |
|------|-------|----------|
| Seccomp profile for Chromium sandbox | Podbay | **Blocker** — gates production browser launch |
| MultiFernet migration (~4 callsites) | Core | Required before first key rotation |
| Nonce cache externalization | Core | Required before 2+ Core tasks (or use ALB sticky sessions) |
| `SHUTTLEFORGE_DB_URL` PostgreSQL override | ShuttleForge | Config change, required for RDS |
| ECSAdapter implementation | Podbay | Phase 3 (~2-3 weeks). Docker bridge for initial deployment. |

### Podbay Browser Workspace Runtime Gate

**Hard fail condition**: A production Podbay browser workspace MUST NOT launch until the following items have been explicitly reviewed and documented in the workspace task definition:

| # | Gate item | Podbay-confirmed answer |
|---|-----------|------------------------|
| 1 | Browser sandbox enabled? | **Yes** — enabled by default. `--no-sandbox` only via `PODBAY_DISABLE_SANDBOX=1` env var (dev/CI only). |
| 2 | Sandbox mode? | **Chromium namespace sandbox** (`--sandbox`). No seccomp/AppArmor profiles documented yet. |
| 3 | Linux capabilities required? | **Yes — `SYS_ADMIN`** for Chromium namespace sandbox. Currently `cap_drop: ["ALL"]` in RuntimeSpec defaults; must add back `SYS_ADMIN`. |
| 4 | `SYS_ADMIN` required or avoidable? | **Required** unless a custom seccomp profile replaces it. Acceptable tradeoff: `SYS_ADMIN` for one container is narrower than Docker socket for the host. |
| 5 | `/dev/shm` size? | **256 MB** in RuntimeSpec default. Chrome also runs with `--disable-dev-shm-usage` (uses /tmp instead). Belt-and-suspenders: set ECS `sharedMemorySize: 256` AND keep the flag. |
| 6 | Seccomp/AppArmor profiles documented? | **BLOCKER — not documented.** No `.json` seccomp profile in the repo. Must produce a Chromium-specific seccomp profile or document the `SYS_ADMIN` exception as an S-series decision before production launch. |
| 7 | `--no-sandbox` forbidden in production? | **Yes** — forbidden by design. `PODBAY_DISABLE_SANDBOX` must NOT be set in production task definition. Add a pre-deploy check. |
| 8 | Host devices, privileged, Docker socket? | **Workspace tasks need none.** Controller uses socket only in Docker bridge mode (temporary, retirement plan required). |
| 9 | ECS-on-EC2 confirmed? | **Yes** — Fargate doesn't support `SYS_ADMIN` or custom `sharedMemorySize`. |
| 10 | Workspace state persistence policy? | **Explicit**: session scratch discarded on terminate; collection output sealed/exported via SEAM-015 before discard; cookies/profile ephemeral (user-data-dir on session volume). No cookie/profile persistence in Phase 2. |
| 11 | Target egress through ShuttleForge? | **Phase 2 exception** — `manual_browse_basic` uses direct egress (no transport). ShuttleForge egress mandatory at Phase 3. See §6 egress amendment. |
| 12 | Attach paths authenticated + time-bounded? | **Yes** — browser stream is grant-authenticated (Phase 2 spec SS7), session-scoped, short-lived. noVNC path through Podbay proxy, not raw port. No raw port exposure (S-014). |

---

## 17. Proposed Decision (D-056, pending review)

```
Arclight production runs on AWS using Terraform-managed infrastructure.

Compute:
  Core runs as ECS Fargate in private subnets.
  ShuttleForge runs as a single ECS Fargate task (control plane + dataplane in one process).
    Dataplane reachable via Cloud Map private DNS, not ALB. NLB added only if external consumers appear.
    Multi-replica needs connection draining for in-flight CONNECT tunnels.
  Podbay runs on ECS backed by a dedicated EC2 capacity provider.
    Workspaces launch via ECS RunTask (ECSAdapter). Docker socket is rejected for production
    unless approved as a temporary bridge with a documented retirement plan.

Networking:
  All public HTTP traffic terminates at an ACM-backed ALB with host-based routing.
  ALB idle timeout: 3600s for Podbay target group (browser stream WebSocket).
  All service-to-service traffic uses private ECS Service Connect / Cloud Map DNS.
  JWT issuer (iss) is the platform const https://core.internal — not the public URL.
    CORE_BASE_URL (public) handles browser redirects. CORE_INTERNAL_URL handles service calls.

Egress:
  All target-facing egress from transport-enabled browser workspaces routes through
    ShuttleForge leases (SEAM-004/013), not AWS NAT Gateway.
  Phase 2 manual_browse_basic (no transport) uses direct egress via NAT — accepted for
    first operator milestone. ShuttleForge egress mandatory at Phase 3.
  AWS NAT acceptable for: Phase 2 pre-transport workspaces, package updates, AWS API calls.

Data:
  RDS PostgreSQL shared per environment with per-module databases and roles.
  ShuttleForge needs SHUTTLEFORGE_DB_URL env var override for PostgreSQL (currently SQLite).

Secrets:
  AWS Secrets Manager / SSM Parameter Store; production values never in Terraform state.
  ShuttleForge: 6 confirmed secrets (KEK ring, 2 HMAC keys, operator token, DB URL, JWKS URL).
  Core: MultiFernet migration needed before first Fernet key rotation (~4 callsites).

Auth:
  Direct external IdP (Google recommended) through Core. No Keycloak/Cognito.
  OIDC flow is redirect-with-session-token (no Podbay↔Core authorization-code exchange).
  Nonce cache is in-memory; multi-task deployment needs ALB sticky sessions for /auth/*.

Ownership:
  arclight-overcast owns infrastructure; module repos own application code and Dockerfiles.

Gates:
  Browser workspace task definitions must pass the 12-point runtime gate (§16).
  Seccomp profile for Chromium sandbox is a production blocker (not yet documented).
```
