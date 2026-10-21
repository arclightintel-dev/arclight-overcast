# Overcast → Backstage: Entra registration contract and the code changes it needs

> **Date**: 2026-10-21 | **Basis**: Overcast O-012 (hosting decisions) and O-014 (Entra applications root); Backstage source at `e038702` (read-only). Hosting facts are in the [hosting response and its addendum](backstage-aws-hosting-response.md) and are not repeated here.
> **Status**: the registration is declared in Terraform and validated locally; the client ID and role IDs exist after the first apply (owner's go). Everything below is stable now and can be planned against.

## What Overcast provides

| Item | Value |
|---|---|
| Tenant | `27564b9c-b516-4bc4-9aa5-5692a38a1116` (ANS Analytics LLC; `arclightlabs.io` is a verified domain of this tenant) |
| Issuer (`PODBAY_OIDC_ISSUER`) | `https://login.microsoftonline.com/27564b9c-b516-4bc4-9aa5-5692a38a1116/v2.0` (tenant-specific; discovery at `<issuer>/.well-known/openid-configuration`) |
| Registration | `arclight-backstage`, single tenant, **new** (not the Dex-era `backstage` app; that one is retired later by the owner) |
| Client type | Confidential Web client: Backstage keeps `client_secret_basic` plus PKCE S256, exactly as `podbay/identity/oidc.py:102-104` does today |
| Client ID (`PODBAY_OIDC_CLIENT_ID`) | Terraform output `backstage_client_id`, delivered after apply |
| Client secret (`PODBAY_OIDC_CLIENT_SECRET`) | Created by the administrator, written straight into a Secrets Manager shell `arclight/backstage/<env>/oidc-client-secret` (created by the Backstage hosting root), injected into the task at start; never in a repo, image or chat |
| Redirect URI (Web) | `https://backstage.arclight-complex.net/auth/callback` (`public_origin() + "/auth/callback"`, `oidc.py:62`); no loopback URI, no Desktop URI (`desktop/identity.cjs:57-88` needs none) |
| Scopes granted | Delegated `openid`, `email`, `profile` on Microsoft Graph; admin consent granted by the administrator |
| ID-token claims | Standard `sub`, `iss`, `aud`, `name`, `tid`; optional claim `email`; `roles` when the user holds app roles. Entra does **not** issue `email_verified`. |
| App roles | `ops`, `operator`, `dev`, `admin` (member type User; the `roles` claim carries the `value`). Role IDs via output `backstage_app_role_ids`. **Assignment required**: only users assigned a role can sign in; the administrator assigns the owner to `admin` first, then the analysts. |

## What Backstage must change before direct Entra works (from its own code)

1. **Discovery gate**: `oidc.py:86-87` refuses an issuer whose discovery document does not advertise `code_challenge_methods_supported` S256. Entra's v2.0 document does not include that key. Keep sending PKCE S256 (Entra accepts it) but stop requiring the advertisement.
2. **Scopes**: `oidc.py:27` requests `openid email profile federated:id`. `federated:id` is Dex-only; Entra rejects unknown scopes. Request `openid email profile`.
3. **`email_verified`**: `oidc.py:292` requires `email_verified is True` for email- and domain-matched invitations. Entra never sends it. Either treat `email` from this issuer as verified (the tenant verifies the domain) or admit by `sub` and app role.
4. **Roles**: nothing reads the `roles` claim today (`oidc.py:227-332`); roles are local (`001_control.sql:4` allows `admin` and `ops` only). If app roles are to mean anything, map `roles` → Backstage role at admission (after `verify_id_token`, `oidc.py:378-380`) and widen the role check to the four values.
5. **Re-link users**: accounts are keyed by issuer + `sub` (`docs/settings_identity_setup.md:83-85`). Existing Dex-linked users do not carry over; the owner signs in first (bootstrap claim, `oidc.py:262-280`) and the analysts are re-invited or admitted by role.
6. Keep issuer and client ID configurable (they already are, `oidc.py:38-39`); a later swap to a different issuer is configuration only. Core will not be Backstage's issuer in v1 (Core is not an OpenID provider).

Hosting-side changes (forwarded-header trust behind the ALB, the loopback-only production preflight, the Desktop app's non-loopback `BACKSTAGE_URL`, the deployment manifest Overcast still needs) are listed in the hosting response and stand as written.

## Order

1. Overcast applies the applications root and sends `backstage_client_id`, `backstage_app_role_ids` and the issuer.
2. Administrator: client secret into the shell (once the hosting root exists), admin consent, role assignments.
3. Backstage: items 1–5 above, plus the hosting-side list, plus the deployment manifest.
4. First sign-in by the owner through `https://backstage.arclight-complex.net`.
