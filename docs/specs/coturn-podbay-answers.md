# Coturn Spec — Podbay Team Answers

> **Source**: Podbay team, verified against `claude-dev-phase-2` HEAD `43b1e92`
> **Date**: 2026-07-08
> **Status**: All 8 RQ-POD questions answered. No open items.

---

## RQ-POD-01: TURN credential API endpoint — RESOLVED

TURN credentials are returned as part of the surface-grant response. No separate `/turn-credentials` endpoint.

When a `browser_stream` surface grant is minted via `POST /api/v0/workspaces/{ref}/surface-grants`, the response includes an `ice_servers` array alongside the grant token:

```json
{
  "grant_id": "sg_...",
  "surface_type": "browser_stream",
  "token": "pbg_...",
  "endpoint_url": "wss://.../stream",
  "ice_servers": [
    {"urls": ["stun:98.80.0.222:3478"]},
    {"urls": ["turn:98.80.0.222:3478"], "username": "1720001800:sg_abc123", "credential": "base64...", "credential_type": "password", "ttl_seconds": 900}
  ],
  "issued_at": "...",
  "expires_at": "..."
}
```

This exists today. Code: `workspaces.py:909-918`.

---

## RQ-POD-02: Surface grant object — RESOLVED

`surface_grants` table. Fields available at TURN mint time:

| Field | Available | Example |
|-------|-----------|---------|
| `grant_id` | Yes | `sg_a1b2c3d4...` |
| `session_ref` | Yes | `ws_x1y2z3...` (workspace_ref) |
| `actor_principal_id` | Yes | `prn_usr_alice` |
| `actor_principal_type` | Yes | `human` |
| `surface_type` | Yes | `browser_stream` |
| `capability` | Yes | `operate` |
| `issued_at` | Yes | ISO 8601 |
| `expires_at` | Yes | ISO 8601 (clamped to settings min/max) |
| `status` | Yes | `active` |

All available before `build_ice_servers` is called — the grant is minted and flushed to DB first, then TURN credentials are derived.

---

## RQ-POD-03: TURN username shape — RESOLVED

`<expiry_epoch>:<surface_grant_id>`

Code: `turn_service.py:72`:

```python
username = f"{expiry}:{grant_id}"
```

Example: `1720001800:sg_a1b2c3d4e5f6`

Rationale: grant_id is auditable (appears in audit events), non-secret (`sg_` prefix, no auth material), and uniquely scopes the credential to a specific grant. Session ID and principal ID are recoverable from the grant record if needed for log correlation. No need to embed them in the username.

---

## RQ-POD-04: Credential TTL — RESOLVED

`min(grant_ttl_remaining, max_turn_credential_ttl)` — effectively.

The implementation derives TTL from the grant's actual expiry, not the raw request:

```python
effective_ttl = int(
    (datetime.fromisoformat(grant.expires_at) - datetime.now(timezone.utc)).total_seconds()
)
effective_ttl = max(60, effective_ttl)
```

Code: `workspaces.py:912-915`.

Grant lifetime range: min 60s, max 7200s (2h), default 900s (15m). These are settings-configurable. The grant TTL is clamped by `grant_service.py:91` before the grant is created, so the TURN credential can never outlive the grant (S-020).

No credential refresh mechanism exists. For the expected grant lifetime range (15m default, 2h max), single-mint-per-grant is sufficient.

---

## RQ-POD-05: Workspace-side TURN credentials — RESOLVED

**The workspace container does NOT need TURN credentials.**

Neko (the WebRTC server inside the container) operates as a TURN peer, not a TURN client. The TURN server relays UDP to the workspace's private IP. The shared secret stays on the controller; only pre-minted credentials go to the browser client.

No TURN-related env vars are injected into the workspace container.

---

## RQ-POD-06: Secret rotation overlap — RESOLVED

Controller fetches fresh on each mint, with 5-minute cache (`_CACHE_TTL = 300.0`). On cache miss, fetches fresh. On fetch failure, falls back to cached value.

Code: `turn_service.py:36-54`.

Rotation sequence:
1. Operator updates Secrets Manager value
2. Operator restarts coturn (picks up new secret)
3. Within 5 minutes, controller's cache expires and fetches new secret
4. New credentials use new secret

Brief invalidation on rotation is acceptable for v1. The window is bounded:
- Existing TURN allocations continue (coturn preserves established sessions)
- New allocations during the cache-miss window (up to 5 minutes) may fail if controller still has old secret but coturn has new secret
- Reconnecting clients get new credentials from controller (which will have fetched the new secret by then)

---

## RQ-POD-07: Clock skew tolerance — RESOLVED

- Controller clock: ECS Fargate task, NTP via AWS (< 1s skew)
- coturn clock: EC2 instance, NTP via AWS (< 1s skew)
- Browser client: receives credentials, doesn't validate expiry — coturn does

Both controller and coturn are AWS-managed NTP. Expected skew < 1s. Minimum credential TTL is 60s, providing > 59s margin against sub-second NTP drift.

**No explicit skew handling needed.**

---

## RQ-POD-08: Credential minting provenance/logging — RESOLVED

**Logged** (via audit event `podbay.surface_grant.issued`):
- grant_id
- session_ref (workspace ID)
- actor_principal_id
- surface_type (`browser_stream`)
- capability
- ttl_seconds
- correlation_id

**NOT logged** (redaction enforced):
- Shared secret (never leaves `_get_shared_secret`)
- Generated credential value (redaction pattern `turn_credential` in `redaction.py:38`)
- Raw grant token (`pbg_*` pattern in `redaction.py:17`)

The grant issuance audit event is the provenance record. TURN credential minting happens inline and doesn't generate a separate audit event.

Code: `grant_service.py:146-162` (audit on mint), `redaction.py:38` (TURN credential pattern).

---

## Implications for Overcast coturn spec

1. **Overcast delivers**: EIP + populated shared secret. That's it.
2. **Secret format**: Raw hex string (`openssl rand -hex 32`), not JSON.
3. **Endpoint**: Podbay consumes `PODBAY_TURN_ENDPOINT` as an IP address. DNS is nice-to-have, not a blocker.
4. **Realm**: Must match what appears in the `ice_servers` array. Currently using IP directly — realm should be the environment domain (e.g., `staging.arclight-complex.net`).
5. **Workspace containers**: No TURN credentials needed. No shared secret exposure.
6. **Rotation**: 5-minute cache window is the accepted invalidation bound.
7. **Clock skew**: Non-issue with AWS NTP on both sides.
8. **BC-02 (Podbay credential contract)**: CLOSED by these answers.
