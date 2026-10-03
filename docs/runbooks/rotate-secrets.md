# Runbook: Rotate Secrets

## General process

1. Generate new secret value
2. Update Secrets Manager entry
3. Restart the affected ECS service (force new deployment)
4. Verify service comes up healthy

> **Secret names are authoritative in `terraform/modules/secrets/main.tf`** —
> all lowercase-hyphen (e.g. `core/database-url`, **not** `core/DATABASE_URL`).
> Terraform creates shells only; values are populated/rotated out-of-band.

## Per-secret notes

### Database passwords
```bash
# Generate new password
NEW_PW=$(openssl rand -base64 32)

# Update in RDS. The master user is `arclight_admin` with a managed password
# (manage_master_user_password = true) — pull it from the RDS-managed secret
# (rds!db-...), not a hardcoded "postgres" password:
export PGPASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id <rds-managed-secret-arn> --query SecretString --output text | jq -r .password)
psql -h <rds-endpoint> -U arclight_admin -d postgres \
  -c "ALTER USER core_staging PASSWORD '$NEW_PW';"

# Update in Secrets Manager (note lowercase-hyphen name: database-url)
aws secretsmanager put-secret-value \
  --secret-id arclight/staging/core/database-url \
  --secret-string "postgresql+asyncpg://core_staging:$NEW_PW@<rds-endpoint>:5432/core_staging"

# Force service restart
aws ecs update-service --cluster arclight-staging --service arclight-core-staging --force-new-deployment
```

> Repeat with the correct secret name per service: `shuttleforge/db-url`,
> `podbay/database-url`, `nerfherder/database-url`. Confirm the exact URL scheme
> each consumer expects (`postgresql://` vs `postgresql+asyncpg://`) — the
> `bootstrap-databases.md` verify path uses the bare `postgresql://` scheme.

### Core signing key (Fernet)
**WARNING**: Core currently uses single-key Fernet, not MultiFernet key ring.
Rotating the key invalidates all existing encrypted data and tokens.
Do NOT rotate until MultiFernet migration is complete (~4 callsites, Core backlog).

Once MultiFernet is implemented:
1. Generate new key, prepend to key ring
2. Update Secrets Manager
3. Restart Core — new key encrypts, old keys decrypt
4. Run background re-encryption migration
5. Remove old key from ring after all data re-encrypted

### ShuttleForge KEK ring
Same MultiFernet-style rotation:
1. Prepend new key to `SHUTTLEFORGE_KEK_RING_B64`
2. Restart ShuttleForge
3. New providers encrypted with new key, old providers still decryptable

### OIDC client secrets
1. Rotate in the IdP (Google Console)
2. Update Secrets Manager with new client secret
3. Restart Core

Applies to `core/oidc-google-client-secret`, `core/oidc-microsoft-client-secret`,
and `core/oidc-github-client-secret`.

### Podbay TURN shared secret (coturn)
Secret: `arclight/staging/podbay/turn-shared-secret` (coturn `use-auth-secret`).
This value is shared between **two** consumers — the coturn EC2 instance
(`module.coturn`, EIP `52.72.36.174`) and the Podbay controller (reads it as
`PODBAY_TURN_SECRET_NAME`). Rotating it requires updating **both** ends together:

1. Generate a new secret and `put-secret-value` on the secret shell.
2. Re-render/restart coturn so it picks up the new `static-auth-secret`
   (coturn reads the secret at boot via its render script — re-apply the coturn
   module or restart the instance).
3. Force new deployment on `arclight-podbay-staging` so the controller re-reads it.

Until both sides carry the new secret, TURN credential validation for active
WebRTC sessions will fail — rotate during a maintenance window.

### Core asset-encryption-key (Phase 6A)
Secret: `arclight/staging/core/asset-encryption-key` (admin asset encryption,
`asset_backend = local_encrypted`). Same single-key caveat as the Core signing
key applies — confirm Core supports key-ring rotation before rotating, otherwise
rotating invalidates existing encrypted assets. Update the secret and restart Core.
