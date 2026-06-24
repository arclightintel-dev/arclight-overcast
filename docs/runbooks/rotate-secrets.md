# Runbook: Rotate Secrets

## General process

1. Generate new secret value
2. Update Secrets Manager entry
3. Restart the affected ECS service (force new deployment)
4. Verify service comes up healthy

## Per-secret notes

### Database passwords
```bash
# Generate new password
NEW_PW=$(openssl rand -base64 32)

# Update in RDS
psql -h <rds-endpoint> -U postgres -c "ALTER USER core_staging PASSWORD '$NEW_PW';"

# Update in Secrets Manager
aws secretsmanager put-secret-value \
  --secret-id arclight/staging/core/DATABASE_URL \
  --secret-string "postgresql+asyncpg://core_staging:$NEW_PW@<rds-endpoint>:5432/core_staging"

# Force service restart
aws ecs update-service --cluster arclight-staging --service arclight-core-staging --force-new-deployment
```

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
