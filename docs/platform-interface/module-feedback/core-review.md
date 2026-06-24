# Core — D-056 Infrastructure Spec Review Response

> **Date**: 2026-06-22
> **Module state**: Phase 4 complete (commit aff6083, 359 tests). S-019 gate 3 resolved. No open implementation work.
> **Reviewed**: `arclight-complex/docs/proposals/production-infrastructure-spec.md`

---

## 1. OIDC URL split

**Problem.** The spec proposes `CORE_PUBLIC_URL` for issuer/redirects and `CORE_INTERNAL_URL` for module calls. Core currently has:

- `CORE_ISSUER` (`settings.issuer`) — hardcoded to `https://core.internal`, validated at startup, used as JWT `iss` claim and in discovery metadata URLs
- `CORE_BASE_URL` (`settings.base_url`) — used for OIDC redirect_uri construction (`auth.py:151`)

The issuer is a **platform contract const** (`jwt-claims.schema.json` has `"const": "https://core.internal"`). It cannot be the public URL without changing the platform contract.

**What works today**: `CORE_BASE_URL` handles the browser redirect target (the public URL). `CORE_ISSUER` stays `https://core.internal`. Modules validate JWT `iss` against the const, not against a URL they fetch from.

**What needs to change**: Either (a) the platform contract changes `iss` from const to the public URL, or (b) the spec accepts that `iss` stays `https://core.internal` and modules validate against that literal value regardless of which URL they fetched JWKS from. Option (b) is simpler and matches F-004 — tokens are self-validating with a known issuer.

**Recommendation**: Keep `iss = https://core.internal` as the platform contract const. **Adopted in spec amendment.**

## 2. Alembic as ECS task

**Works today.** `alembic/env.py` reads `CORE_DATABASE_URL` from settings (line 20). No lifespan interaction. The Dockerfile CMD runs `alembic upgrade head && uvicorn ...` but for ECS, splitting these into a one-off migration task + a service task is straightforward — just change the CMD override in the task definition. No code changes needed.

## 3. IdP recommendation

**Google.** Easiest OAuth app registration (Google Cloud Console, no approval needed for internal testing), most users already have accounts, Core's OIDC service already has Google IdP config in the Keycloak dev realm that translates directly to direct integration. Microsoft requires tenant configuration. GitHub works but has narrower user reach.

**Adopted in spec amendment.**

## 4. Fernet key rotation

**Single-key only.** Core uses `Fernet(key)` everywhere — `main.py:52`, `jwk.py:49/58`, `readiness.py:70`. No `MultiFernet` support. The spec's key-ring proposal (new key encrypts, old keys decrypt, background re-encrypt, retire) requires changing every Fernet callsite to use `MultiFernet([new_key, old_key])`. This is a small code change (~4 callsites) but it's not implemented.

**Needs a Core code change before first key rotation.** Tracked as pre-production item.

## 5. Secrets inventory

The spec's list is complete for Core. Full inventory:

| Secret | In spec? |
|--------|----------|
| `CORE_SIGNING_KEY_ENCRYPTION_KEY` | Yes |
| `CORE_ADMIN_BOOTSTRAP_SECRET` | Yes |
| `CORE_OIDC_CLIENT_SECRET` (via `CORE_OIDC_CLIENT_SECRET_REF` indirection) | Yes |
| `CORE_DATABASE_URL` (contains password) | Yes (DB credentials) |
| Direct IdP OAuth client secret | Yes (OIDC client secrets) |

No additional secrets beyond what's listed.

## 6. Fargate concerns

**No blockers for Core.** Core is stateless (DB in RDS, no local files). In-memory OIDC nonce cache works in single-task deployment but needs attention at 2+ tasks — nonces are single-use and stored in-process. With 2 Core tasks behind ALB, a login started on task A could callback to task B which doesn't have the nonce.

**Fix**: ALB sticky sessions for `/auth/*` paths, or move nonce to RDS/ElastiCache. Known deferral (`In-memory nonce cache not multi-process safe` in PROJECT_STATE.md).

## Spec discrepancy found

The OIDC flow in spec §5 step 6-7 describes an authorization-code exchange between Podbay and Core. **This doesn't exist.** Core's current flow returns the JWT directly via redirect after callback — there's no Podbay-to-Core server-to-server code exchange. If the spec wants that pattern (which is more secure), it's new work. The current flow is: Core callback → session created → redirect to Podbay with session token.

**Corrected in spec amendment.**
