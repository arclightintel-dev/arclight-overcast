# Core — Secrets Inventory Update (Multi-IdP Cutover)

> **Date**: 2026-06-22
> **Supersedes**: Single OIDC client secret from the original D-056 review
> **Reason**: Core completed multi-IdP cutover (Google, Microsoft, GitHub). Keycloak removed. Three IdP client secrets replace the single Keycloak broker secret.

---

## Updated Secrets Manager shells needed for Core

| Secret Path | Env Var in Task Def | Purpose | New/Changed |
|-------------|-------------------|---------|-------------|
| `arclight/staging/core/database-url` | `CORE_DATABASE_URL` | PostgreSQL connection string | Unchanged (env var name corrected from `DATABASE_URL`) |
| `arclight/staging/core/signing-key-encryption-key` | `CORE_SIGNING_KEY_ENCRYPTION_KEY` | Fernet key | Unchanged |
| `arclight/staging/core/admin-bootstrap-secret` | `CORE_ADMIN_BOOTSTRAP_SECRET` | Bootstrap token (retired after owner onboard) | Unchanged |
| `arclight/staging/core/oidc-google-client-secret` | `OIDC_GOOGLE_CLIENT_SECRET` | Google OAuth client secret | **NEW** (replaces `oidc-client-secret`) |
| `arclight/staging/core/oidc-microsoft-client-secret` | `OIDC_MICROSOFT_CLIENT_SECRET` | Microsoft OAuth client secret | **NEW** |
| `arclight/staging/core/oidc-github-client-secret` | `OIDC_GITHUB_CLIENT_SECRET` | GitHub OAuth client secret | **NEW** |

## Removed

| Old Secret Path | Reason |
|-----------------|--------|
| `arclight/staging/core/oidc-client-secret` | Was the single Keycloak broker secret. Replaced by three IdP-specific secrets above. |

## Impact on Overcast Phase 0

The secrets module in Overcast's Phase 0 plan creates Secrets Manager shells. The plan's current shell list has `arclight/staging/core/oidc-client-secret` (single). This must be replaced with the three IdP-specific shells above.

Also: the Phase 0 plan's secrets table listed `DATABASE_URL` as the Core env var. Core actually reads `CORE_DATABASE_URL` (env_prefix="CORE_"). The plan already flags this as gotcha #14 / Phase 1 blocker. The correct env var name is `CORE_DATABASE_URL` — both the secret shell and the task definition template should use this name.
