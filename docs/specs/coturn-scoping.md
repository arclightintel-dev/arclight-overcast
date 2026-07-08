# Coturn TURN Module Scoping Document — Arclight Overcast / Podbay

> **Author**: hotpants (domain architect)
> **Date**: 2026-07-08
> **Governing decisions**: D-062, O-002, INV-005
> **Status**: SCOPING COMPLETE — blocks spec authoring until research questions resolved

## 0. Scope posture

The coturn module must be re-specified before it is rewired. Overcast's own decision log says O-002 implements D-062 as "self-hosted coturn on EC2 t3.micro with Elastic IP, per-environment," but also records that the module was rolled back and is not wired because four failed apply cycles exposed unspec'd OS, package, and systemd assumptions. Staging confirms this: the coturn module is explicitly removed from wiring pending a proper spec.

The existing module should be treated as evidence of attempted implementation, not as authority. It currently creates public TURN ingress on UDP/TCP 3478 and UDP 49152–65535, grants Secrets Manager read access to the instance, selects Ubuntu Noble 24.04, installs coturn via apt, installs AWS CLI v2 by zip download, renders `/etc/turnserver.conf` via an `ExecStartPre` script, and uses a throwaway secret if Secrets Manager retrieval fails.

## 1. What the spec must cover beyond INV-005

INV-005 is necessary but not sufficient. The spec must cover at least eight additional areas.

First, it must define the Podbay/Overcast boundary. Overcast owns the TURN host, network exposure, DNS, EC2 lifecycle, IAM, SSM access, logging, and secret delivery to infrastructure. Podbay owns session authorization, surface grants, ICE configuration construction, and generation of time-limited TURN credentials. The infra module must not become the authority that decides which workspace/session gets relay access.

Second, it must define the credential issuer. D-062's `use-auth-secret` decision means the shared secret is held by coturn and by a trusted server-side issuer. That issuer should be the Podbay controller, not the browser client and not the workspace container. The client must receive only short-lived `username`/`credential` ICE material. The controller may pass short-lived credentials to the workspace side if the workspace WebRTC stack needs them, but the shared secret itself must not be injected into workspace containers.

Third, it must define the ICE server contract. The spec needs the exact shape Podbay receives or emits: endpoint hostname, port, transport variants, realm, credential TTL, username format, credential algorithm, and whether `urls` includes UDP only, TCP fallback, or both. The current Podbay infra feedback asks for `PODBAY_TURN_ENDPOINT` and `PODBAY_TURN_SECRET`, and states that Podbay needs a TURN credential API with grant-scoped credentials matching grant TTL. The spec must refine that: `PODBAY_TURN_SECRET` belongs only in the Podbay controller's secret access path, not in browser-delivered configuration or workspace task environment unless the workspace is explicitly trusted to mint credentials, which it should not be.

Fourth, it must define realm semantics. Coturn's REST-style credentials still use long-term credential mechanics, and coturn documentation says WebRTC requires long-term credentials and a default realm. The realm must be stable per environment, probably `turn.<env>.<domain>` or `<env>.<domain>`, and must match whatever the browser receives during authentication. The spec must say whether realm is tied to DNS hostname, environment domain, or a separate auth namespace. Realm drift will break authentication and make failures look like generic ICE failure.

Fifth, it must define secret rotation semantics. Coturn supports multiple static auth secrets, but the current module writes one `static-auth-secret` value. Coturn documentation says the actual secret for TURN REST API is provided by `static-auth-secret` or a database-backed secret table, and multiple shared secrets can be used. The v1 spec can choose single-secret rotation with restart and brief credential invalidation, but it must explicitly say so. If zero-downtime rotation is required, the spec must choose a multi-secret strategy and prove coturn's package/config behavior for that strategy.

Sixth, it must define DNS and endpoint stability. The existing module only outputs the EIP public IP. Podbay's requirements call for a TURN hostname such as `turn.staging.arclight-complex.net`. The spec must decide whether Podbay consumes an IP or DNS name. DNS should be preferred for browser ICE configuration, cert/TLS future-compatibility, and rotation. The EIP remains the stable attachment point.

Seventh, it must define peer-access policy. TURN is not just "open inbound to coturn." It allows authenticated users to relay traffic from coturn to peers. Because the server sits in a VPC public subnet, the spec must decide whether coturn should deny relay attempts to link-local, metadata, RFC1918, VPC CIDRs, RDS/private service CIDRs, and other internal ranges. Coturn supports allowed/denied peer IP policy, with deny/allow rules used to prevent TURN from reaching otherwise inaccessible machines. This is a real security constraint, not polish.

Eighth, it must define observability and acceptance tests. "Terraform apply succeeds" is not an acceptance test. The spec needs systemd health, CloudWatch logs or journald access path, SSM runbook, coturn process readiness, UDP allocation test, TCP fallback test, wrong-secret negative test, expired-credential negative test, and a Podbay end-to-end WebRTC smoke test.

## 2. Research questions that must be answered before writing the implementation spec

The package research must be done against the exact OS image and package version that will be deployed. Ubuntu Noble currently has `coturn` package `4.6.1-1build4` in `universe`. Its file list includes `/etc/default/coturn`, `/etc/turnserver.conf`, `/usr/lib/systemd/system/coturn.service`, and `/usr/bin/turnserver`. That confirms the relevant files exist; it does not prove their contents, default enablement behavior, runtime user, or permission model.

### OS/package questions

1. On the exact Ubuntu 24.04 AWS AMI, does `apt-get install coturn` pull from `universe` without enabling extra repos?
2. What is the installed `coturn.service` content?
3. Does the systemd unit still honor `/etc/default/coturn` and `TURNSERVER_ENABLED=1`, or is that only an init-script convention?
4. What user and group does coturn run as by default?
5. Does the package create a `turnserver`, `coturn`, or other service account?
6. What are the default ownership and permissions on `/etc/turnserver.conf`, `/etc/default/coturn`, `/var/lib/turn`, `/var/log/turnserver`, and any SQLite/userdb path?
7. Does the service start automatically after install, or remain disabled/stopped?
8. Does package installation generate any default secret, CLI password, TLS cert/key, or sample config state that must be removed?
9. Does the package support `use-auth-secret` and `static-auth-secret` exactly as needed in the packaged version?
10. Does the package include Prometheus support? Coturn upstream notes Prometheus is unavailable on apt installations. If true for Noble, metrics must use logs/systemd/blackbox probes instead.

### AWS/bootstrap questions

1. Is AWS CLI v2 installation from the public zip acceptable in user-data, or should the spec avoid runtime unauthenticated package download by baking an AMI, using cloud-init packages, or using a signed/hashed artifact path?
2. Is the SSM agent actually preinstalled and enabled on the selected Ubuntu AWS AMI, or must it be installed from Snap/deb with a verified path?
3. Can cloud-init complete before EIP association? The current module associates the EIP after instance creation, while the render script polls IMDS for `public-ipv4`. The spec must determine whether this race is acceptable or whether service start must be ordered after EIP attachment verification.
4. Should the rendered `external-ip` be the IMDS public IPv4, the Terraform EIP output injected into user-data, or a runtime check that both agree?
5. What IMDSv2 token handling and retry behavior is required?
6. What IAM policy is minimally sufficient for coturn? The current policy permits `kms:Decrypt` on `*` scoped only by `kms:ViaService`. That may be acceptable, but the spec must decide, not inherit it.
7. Should the coturn host have any outbound egress restriction beyond default `0.0.0.0/0`?
8. Should the module include a Route53 record, or should DNS be owned elsewhere?

### Podbay questions

1. What exact API endpoint returns TURN credentials to the browser?
2. Does Podbay already have a surface-grant object with TTL, grant ID, user/principal, workspace/session ID, and revocation state?
3. Is the TURN username `expiry_epoch:grant_id`, `expiry_epoch:principal_id`, `expiry_epoch:workspace_id`, or another auditable identifier?
4. Does credential TTL equal grant TTL, the lesser of grant TTL and a TURN-specific max, or a fixed short TTL?
5. Does the workspace WebRTC server need its own TURN credentials, and if so are they generated by the controller at workspace launch?
6. How does Podbay handle rotation when a credential minted under the previous shared secret is still within TTL?
7. Is clock skew bounded across controller, coturn, and client enough for epoch-based credentials?
8. What logging/provenance is required when credentials are minted: grant ID, workspace ID, principal ID, expiry, endpoint, but never the credential or shared secret?

## 3. Blocking conditions before implementation starts

Implementation should not start until these conditions are true.

The target OS and package behavior must be empirically verified on a disposable EC2 instance using the exact AMI filter and instance type family. This verification must record package version, repo, service unit content, service user, default files, and enable/start behavior.

The Podbay credential contract must be locked. Specifically, the controller must be confirmed as credential issuer; the shared secret must be available to the controller via Secrets Manager or equivalent server-side secret injection; browser clients must receive only ephemeral ICE credentials; and workspace containers must not receive the shared secret.

The TURN shared secret must exist as a populated secret value before apply/start. A "secret shell" is not enough. The spec must define whether the secret is a raw string or JSON, minimum entropy, character restrictions, ownership, rotation procedure, and who may read it.

The endpoint model must be locked. The module must know whether it produces only an EIP, an EIP plus DNS record, or an output consumed by a separate DNS module. Podbay's requirement for a public endpoint and likely hostname must be resolved before wiring.

The security policy must be locked. This includes inbound ports, relay port range, outbound policy, denied peer CIDRs, SSM-only admin access, no SSH key path, no coturn CLI/web-admin exposure, and whether TCP 3478 is enough for fallback or whether TLS/TURNS 5349 is deferred.

The bootstrap failure behavior must be locked. The current throwaway-secret fallback must not survive by accident. First boot without the real secret should fail visibly. Steady-state restart behavior must be explicitly chosen.

Acceptance tests must be defined before code is changed. At minimum: Terraform validate/plan; instance reaches SSM; coturn service active; generated config has correct realm, external IP, auth-secret mode, min/max port; valid HMAC credentials can allocate; expired or wrong-secret credentials fail; browser-to-workspace WebRTC smoke succeeds; and CloudWatch/journald shows no secret leakage.

## 4. Domain constraints on credential mode

The credential mode is not an infra-local detail. `use-auth-secret` means coturn validates time-limited credentials generated elsewhere using a shared secret. Coturn documents the pattern: the temporary username is `timestamp:username`; the temporary password is `base64(hmac-sha1(shared-secret, temporary-username))`; both the TURN server and web server know the shared secret.

For Podbay, the controller should generate TURN credentials. The browser client cannot generate them because that would require exposing the shared secret. The workspace container should not generate them because workspaces are operational runtime surfaces, not credential authorities. The controller is the natural authority because it already mediates session creation, workspace launch, and surface grants.

The username should encode expiry and a non-secret grant/session identifier, for example:

```
<expiry_epoch>:<surface_grant_id>
```

or:

```
<expiry_epoch>:<workspace_session_id>:<surface_grant_id>
```

The credential is:

```
base64(HMAC-SHA1(turn_shared_secret, username))
```

The client receives:

```json
{
  "urls": [
    "turn:turn.<env>.<domain>:3478?transport=udp",
    "turn:turn.<env>.<domain>:3478?transport=tcp"
  ],
  "username": "<expiry_epoch>:<grant-bound-id>",
  "credential": "<base64-hmac>",
  "credentialType": "password"
}
```

The infra spec must therefore define only the server-side validation substrate: coturn config, realm, shared secret source, endpoint, and network reachability. It must not define Podbay's full authorization model, but it must require that Podbay implement credential minting and that Overcast grant the Podbay controller read access to the same TURN shared secret or a tightly scoped derivative.

Credential TTL should be short and grant-bound. "Matches grant TTL" is acceptable only if grant TTL is itself short enough for relay exposure. If grants can live longer than a WebRTC reconnection window, define `turn_credential_ttl = min(surface_grant_ttl_remaining, max_turn_credential_ttl)`. The spec should force an upper bound, probably minutes to low hours, not days.

Secret rotation requires a conscious tradeoff. With one `static-auth-secret`, rotation invalidates newly reconnected clients once coturn restarts and Podbay switches secrets. Existing TURN allocations may continue until the session disconnects, because coturn documentation notes that established sessions keep using the original password while the session remains valid. For v1, this is acceptable if documented. Zero-downtime rotation is not a v1 requirement unless the spec chooses multi-secret support and validates it on Noble's packaged coturn.

## 5. Failure modes that matter most

The most important failure mode is secret retrieval failure. The current module's throwaway-secret fallback is the wrong default. It starts a service that appears healthy but cannot authenticate credentials minted by Podbay. That is not useful fail-closed behavior; it is fail-dark behavior. The correct v1 behavior is: fail hard on first boot if the shared secret cannot be fetched; fail the systemd unit on restart if the secret cannot be fetched; emit a clear log message; alert through systemd/CloudWatch/blackbox health. If steady-state resilience is desired, specify a last-known-good cached config strategy separately, with strict file permissions and loud degraded-state logging. Do not silently generate a new secret.

Other high-priority failure modes:

1. **EIP/public-IP race**: coturn starts with the wrong or missing `external-ip`, causing allocations to advertise unusable relay addresses.
2. **Realm mismatch**: Podbay mints credentials under one realm while coturn challenges under another.
3. **Clock skew**: credentials appear expired or not yet valid because controller/coturn/client time assumptions diverge.
4. **Package behavior drift**: Ubuntu package unit/default-file behavior changes, reintroducing the exact class of failures INV-005 is meant to stop.
5. **Secret format mismatch**: Secrets Manager value is JSON while render script expects raw string, or vice versa.
6. **AWS CLI/SSM install failure**: runtime dependency fetch fails, leaving instance unreachable or unable to render config.
7. **Security group incompleteness**: UDP relay range blocked, TCP fallback blocked, or outbound policy prevents peer relay.
8. **Overbroad relay target access**: authenticated TURN users can relay to internal/VPC/link-local targets unless denied-peer policy is set.
9. **Logging leaks**: rendered config, cloud-init output, shell trace, or journald logs expose `static-auth-secret`.
10. **Restart/rotation mismatch**: coturn restarts with a new secret while Podbay still mints with the old one, or vice versa.
11. **No negative tests**: service appears live because port 3478 responds, but authentication, allocation, or WebRTC relay fails.
12. **Abuse/reflection exposure**: public unauthenticated STUN/TURN behavior increases UDP amplification risk if auth, rate-limiting, or STUN-only behavior is misconfigured. Coturn documents an `unauthorized-ratelimit` option for limiting unauthenticated 401 responses, but it is off by default.

## 6. Required contents of the eventual implementation spec

The eventual spec should be organized around verifiable contracts, not prose assumptions:

1. **Decision authority**: D-062/O-002/INV-005 references and explicit non-goals.
2. **Runtime architecture**: EC2, public subnet, EIP, DNS, security group, IAM, SSM, CloudWatch/logging.
3. **OS/package contract**: exact Ubuntu release, AMI selection, package repo, package version, systemd unit content, runtime user, files, permissions.
4. **Bootstrap contract**: first boot sequence, dependency ordering, AWS CLI/SSM handling, EIP detection, secret fetch, config render, systemd start.
5. **Steady-state contract**: restart behavior, re-render behavior, rotation behavior, failure behavior.
6. **Coturn config contract**: required and forbidden options, realm, auth mode, external IP, relay port range, CLI/web-admin disabled, peer deny policy, logging.
7. **Podbay integration contract**: endpoint outputs, DNS, controller secret access, credential minting algorithm, TTL, username shape, ICE config shape.
8. **Secret custody contract**: secret name/ARN, value format, entropy, KMS/IAM, readers, rotation runbook, no logging.
9. **Network/security contract**: inbound, outbound, denied peers, no SSH, SSM debug path.
10. **Verification contract**: pre-implementation package probe, Terraform plan expectations, runtime smoke tests, WebRTC E2E, negative auth tests, observability checks.
11. **Rollback contract**: how to unwire without orphaning EIP/secret/DNS, and what happens to live Podbay sessions.
12. **Open questions register**: any unresolved package, Podbay, DNS, or rotation facts block implementation.

## 7. Recommended scoping rulings

Use Ubuntu 24.04 only if the empirical package probe confirms the systemd/default-file behavior. The fact that the package exists in Noble `universe` and includes `/etc/default/coturn`, `/etc/turnserver.conf`, and `coturn.service` is encouraging, but insufficient.

Use Podbay controller-side credential minting. Do not let clients or workspace containers mint TURN credentials. Do not expose the shared secret outside trusted server-side components.

Use DNS as the Podbay-facing endpoint, backed by EIP. Do not make browser ICE configs depend directly on a raw public IP unless DNS is explicitly deferred.

Reject throwaway-secret startup. Refuse to start when the real shared secret is unavailable, at least for v1. A running TURN service with an unknown secret creates a misleading green status and pushes failure into opaque browser ICE behavior.

Require denied-peer policy research and likely default-deny for internal/link-local/VPC ranges. TURN relay is an authenticated public relay into whatever networks coturn can reach; that must be treated as a network security boundary.

Do not wire the module into staging until the Podbay credential contract, package probe, secret format, DNS endpoint, failure semantics, and smoke tests are locked.
