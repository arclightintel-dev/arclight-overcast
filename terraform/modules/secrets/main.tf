# Secrets Module
#
# Provisions per D-056 §8:
#   - Secrets Manager entries (SHELLS only — never production values)
#   - SSM Parameter Store entries (non-secret config)
#   - IAM policies for per-service secret access
#
# Core secrets:
#   - CORE_SIGNING_KEY_ENCRYPTION_KEY (Fernet/MultiFernet key ring)
#   - CORE_ADMIN_BOOTSTRAP_SECRET (one-time, disable after first platform_owner)
#   - OIDC client secrets
#   - DB credentials
#
# ShuttleForge secrets (6):
#   - SHUTTLEFORGE_KEK_RING_B64
#   - SHUTTLEFORGE_LISTENER_AUTH_HMAC_KEY
#   - SHUTTLEFORGE_LEASE_HMAC_KEY
#   - SHUTTLEFORGE_OPERATOR_TOKEN
#   - SHUTTLEFORGE_DB_URL
#   - CORE_JWKS_URL (SSM — not a secret)
#
# CRITICAL: Terraform creates structure and IAM permissions.
# Terraform does NOT write production secret values into state.
# Values are populated via AWS Console, CLI, or bootstrap script.
