# Overcast Response — AWS Secrets Manager Backend Design

> **From**: Overcast (arclight-overcast)
> **To**: Core (arclight-core), Phase 6A — AWS Secrets Manager backend adapter
> **Date**: 2026-07-08
> **Verified against**: Terraform commit 9148a85
> **Status**: WITHDRAWN as implementation guidance by the 2026-10-01 review; notice recorded 2026-10-03. Original July response preserved below for provenance.

## Correction and current disposition — 2026-10-03

The [Core 7G/7F review receipt](core-phase7-integration-response.md) supersedes this memo's runtime-IAM, TTL and invalidation advice. **7F readiness is NO-GO under the reviewed design.** This withdrawal does not select a replacement mechanism or amend a canonical platform contract. The original `9148a85` reference describes the July review, not the later source baseline `5c3a93c`.

| Historical claim | Correction |
|---|---|
| Existing service IAM can resolve the proposed references | The cited `arclight-ecs-exec-*` permissions are ECS execution-role permissions for startup secret injection. Core has no task role bound in the reviewed staging root and uses `local_encrypted`; application runtime authorization still needs an agreed design. |
| Removing `AWSCURRENT`, overwriting or writing a tombstone immediately invalidates an explicit version | A retained explicit `VersionId` selects that immutable version. Label removal or a new version alone does not deny that read. AWS exposes no direct individual-version deletion operation; whole-secret deletion is a different revocation unit and is not selected. |
| Core sweeps provide independent reference TTL | No custody expiry/retirement enforcement worker was found in the pinned Core source. Registry expiry is not backend denial, and a Core-only sweep cannot enforce a deadline during Core outage. |
| ARN/version plus existing IAM proves F004 and selective revocation | Shared locator authorization does not distinguish independent references. AWS supports version conditions, but that alone does not establish service-bound references, per-reference deadlines, selective denial or immediate completion. |
| STS is the fallback; Core writer permissions are optional | STS remains an unselected alternative. Any AWS adapter needs explicit runtime authority; topology, enforcement and failure semantics require owner decisions before provisioning. |

Primary AWS API references and exact source anchors are in the successor receipt. The July network/live-state statements were not reverified by that read-only review or this documentation update.

---

## Original July response — historical, withdrawn guidance

### Summary of Decisions

| Question | Answer |
|----------|--------|
| Q1 Time-bounded access | ARN+version as ref. Existing service IAM reads it. Core revokes on TTL expiry. No resource policy manipulation. |
| Q2 Versioning | PutSecretValue → store AWS VersionId in backend_locator. AWSCURRENT/AWSPREVIOUS for rotation grace. |
| Q3 IAM | Pre-configured by Overcast. Services already have wildcard GetSecretValue on their path (`arclight/{env}/{service}/*`). No Core-side IAM changes. |
| Q4 Invalidation | UpdateSecretVersionStage or overwrite value. Immediate for version-level, nuclear for secret-level. |
| Q5 Encryption key | New SM shell (`arclight/{env}/core/asset-encryption-key`). KMS envelope for production (deferred). |
| Q6 Network | NAT path works. No SM VPC endpoint yet. Same account (650880817826), no cross-account. |

## Key Infrastructure Facts

- **Role naming**: `arclight-ecs-exec-{service}-{environment}` (terraform/modules/secrets/main.tf:82-89)
- **Existing IAM**: each service role has `secretsmanager:GetSecretValue` scoped to `arclight/{env}/{service}/*` (secrets/main.tf:91-106)
- **Secret path pattern**: `arclight/{env}/{service}/{secret-name}`
- **Staging**: live at core.staging.arclight-complex.net, Core's role already has GetSecretValue on `arclight/staging/core/*`

## Protocol Implications for 6A5

- `store_secret()` → `PutSecretValue`. Store AWS VersionId in `backend_locator`.
- `build_access_ref()` → return `arn:aws:secretsmanager:{region}:{account}:secret:{name}?versionId={id}`. Self-routing — service's existing IAM reads it.
- `invalidate_access_ref()` → `UpdateSecretVersionStage` to remove AWSCURRENT from version, or overwrite with tombstone.
- `revoke_secret()` → `PutSecretValue` with new content (nuclear), or delete version.
- `validate_configuration()` → verify Core's role can reach SM via NAT.

## What Overcast Provisions (when 6A5 starts)

1. New secret shell: `arclight/{env}/core/asset-encryption-key`
2. Possibly: additional Core task role permissions for managing secret versions
3. Possibly: SM VPC endpoint (if latency/cost becomes measurable)
4. Possibly: KMS key for envelope encryption (production hardening)

## Open Platform Decision

F-004 strictly requires that credential use after reference issuance doesn't depend on Core. The ARN+version pattern satisfies this — the service reads directly from SM using its own IAM role. TTL enforcement is application-level (Core sweeps expired references and revokes versions). If backend-enforced TTL is required, STS AssumeRole is the fallback (more IAM complexity). **This is a platform decision** — Overcast implements whatever is decided.
