# Overcast receipt — Core 7G adoption and 7F custody

> **Review completed**: 2026-10-01 | **Recorded**: 2026-10-03
> **Disposition**: GO for 7G source-contract acknowledgment only; NO-GO for unattended dispatch; NO-GO for the reviewed 7F/B2 custody design.
> **Scope**: Source/document review. No operational cloud access, migrations, deployment, scheduling or privilege changes; tests inspected, not rerun.

## Evidence and delivery

| Input | Immutable pin |
|---|---|
| Overcast source | `5c3a93c33e0493f72c5e2aef0c2ce99efb6bdcd5` |
| Core application | `a9eb0307e651ab2322b8d5ec4e142dd1418cf108` |
| Core 7G handoff | `8892c5df9d265d1371cb2d7f1258e8c7d3cfc17e`, `docs/reviews/phase7-7g-integration-handoff.md` |
| Core 7F report | `d456bb96aa6746269d9847f5ad70ed312cd217ce`, `docs/reviews/phase7-7f-custody-readiness-astra.md` |
| Core owner answers | `43ff69f6c6a87cc100423e5c275b1ee33c2abb33`, `docs/reviews/phase7-platform-coordination-2026-10-01.md` |
| Governing platform baseline | `bbb8a1872644ff7148284698be3a07be8449d8ce` |
| Platform coordination record | `745ec876e7de5884429398f8b6c1690ee6e5c9c0`, `platform/proposals/core-phase7-integration-coordination.md` |

Core anchors below refer to the application pin, not an ambient checkout. The relevant custody implementation was unchanged from the 7F report's application baseline `01f61db0a166a40b05da03d87afa83e216d9e44d` to `a9eb030`. Historical guidance is preserved, with a withdrawal notice, in [the Phase 6A response](core-phase6a-sm-backend-response.md).

The complete response and concise receipt were delivered to Complex task `01a0f301-f9aa-7863-8b0f-ae8a550e92db`; that task acknowledged receipt and closed the bounded investigation. Core task `01a0f264-0cca-7c42-bbf8-42740db688cd` supplied the four owner answers. At the October 3 local inspection, Complex HEAD was `5f5ff3c2b965f1aad008b4b0de0fd15cfeef69e7`; its coordination file still matched the pending-receipt wording at `745ec876`. Task acknowledgment is established; publication of an updated platform receipt was not verified. This local record does not amend that repository.

## 7G adoption

The reviewed endpoint is `POST /api/admin/grants/expire-sweep`.

| Check | Result | Evidence / consequence |
|---|---|---|
| Response contract | PASS | `arclight_core/api/schemas.py:452–458`: `warnings_created`, `expirations_created`, `grants_expired`, `skipped_existing_notifications`, all nonnegative integers. These replace `materialized/warnings/total_events`. |
| Invocation semantics | PASS, source | `services/grant_service.py:678,708,760`: repeated warnings can increment skipped; an already completed expiry normally leaves four zeroes on retry. Do not sum expiration-event and grant-transition counters as separate notifications. A zero retry does not prove a prior lost-response attempt had no effects. |
| Route / migration | PASS, source | `api/routes/admin.py:14–22` commits changes and has no dry-run option. `alembic/versions/p7g1_grant_expiry_notif.py:10–53` follows `sf10c1_client_purpose`, creates an empty ledger and refuses populated downgrade. |
| Actual Overcast caller | WARN, bounded absence | No endpoint caller, old/new decoder, matching scope invocation, cron or EventBridge scheduler found in pinned `.github`, `terraform`, `services`, `docs` and corresponding working files plus `scripts`. External schedules were not inspected. |
| Unattended authorization | FAIL prerequisite | `api/deps.py:149,194,212,241`: human principal, MFA and `core.principal.manage`; service/system tokens remain refused. Activated-bootstrap secret fallback is refused. Core confirms neither an internal maintained job nor a machine-auth endpoint is approved. |
| Rollout readiness | WARN | Overcast `.github/workflows/deploy-service.yml:166–168` accepts HTTP 200 alone. Core `api/routes/readiness.py:26,337` can return 200 with `status="unavailable"`; eventual acceptance must inspect body and schema revision. |

Overcast acknowledges the source contract. There is no existing caller to update, and no scheduler was delivered. Request IDs correlate calls; they are not sweep response-replay keys. Notification means durable audit materialization, not email/transport delivery. The handoff's test totals are producer evidence, not fresh Overcast execution.

Core + Complex must first select the unattended identity, authority, audit and failure model. Direct Python invocation, a reused human session or a bootstrap secret is not an implicit exception. Overcast then owns the actual adapter, counter/error decoding, request correlation, schedule, timeout/backoff/overlap controls and monitoring. Migration/image binding, authenticated positive/refusal/retry cases, durable effects and actual staging invocation require separate operational authorization and acceptance before recurrence.

## 7F custody and actual infrastructure

| Check | Result | Pinned evidence |
|---|---|---|
| AWS backend implementation | FAIL | Core `services/aws_secrets_backend.py:10–25` remains unimplemented. The proposed VersionId mapping is a design, not observed AWS execution. |
| Independent grants | FAIL in proposed mapping | `services/secret_backend.py:23` and `services/admin_asset_service.py:592–623`: backend receives locator + TTL; service, operation and reference identity remain Core metadata. Shared ARN/version authorization does not distinguish independent references. |
| Expiry / retirement | FAIL | `admin_asset_service.py:354–357,571–623`: retirement deadline and reference expiry are stored, but no custody enforcement/reconciliation worker was found. Grant/session sweeps do not supply this behavior. |
| Completion / repair | FAIL | `admin_asset_service.py:867–939,995–1047,1077–1089`: lifecycle changes precede best-effort backend effects; false results/errors do not prevent ordinary success. Already-revoked retry is refused at `987–988`; restriction selects only active references at `856–864,900–907`. |
| Runtime identity | FAIL for historical premise | Overcast `terraform/modules/secrets/main.tf:83–121` attaches reads to ECS execution roles. Core staging `main.tf:204` has no task-role binding; `216` selects `local_encrypted`. Generic runtime task role defaults to null (`modules/ecs-service-fargate/variables.tf:70`). |
| Consumer topology | FAIL for general custody | Podbay's runtime role only reads its exact TURN secret (`terraform/envs/staging/main.tf:810–823`). No SF service binding exists in the inspected roots. Prod is substrate-only in source. No live deployment is inferred. |

The secret-resource ARN pattern permitted by the execution-role policy is `arn:aws:secretsmanager:{region}:{account}:secret:arclight/{environment}/{service}/*`. It supplies startup injection, not a general runtime custody capability. Runtime identity, resource namespace and trust bindings must be designed explicitly.

The original invalidation advice is withdrawn. Explicit `VersionId` reads select a retained version; removing labels merely deprecates it for possible cleanup, and writing new material creates another immutable version. Whole-secret deletion is a different unit; there is no direct delete-version operation. AWS supports both `secretsmanager:VersionId` and `VersionStage` IAM conditions, but that alone does not establish independent per-reference authorization. IAM/Secrets Manager propagation also prevents inferring global immediate cutoff from a mutation response or one probe. These are API/source conclusions, not live AWS test results.

## Unselected topology and owner decisions

An independent enforcement backend was returned as an option, not an approved service or Terraform plan. The proposed logical boundary is:

- Isolated canonical material at `arclight/{environment}/admin-assets/{asset_ref}` with immutable storage versions. ARN/version addresses material; a unique opaque grant authorizes access.
- Separate startup execution roles, a narrowly scoped Core writer task role and a backend resolver role. Only the backend resolves material for consumers; consumer identities have no direct canonical Secrets Manager/KMS bypass.
- Authenticated workload identity mapped to the Core service principal, independently of possession of the handle. The grant binds service, asset/version, operation/scope, expiry and retirement/revocation state. Authentication technology and implementation ownership remain unselected.
- An authoritative authorization store checks each resolution and deadline, serializes admission with denial, and never serves stale positive authorization on store failure. Core outage must not extend issued deadlines; backend/store outage fails closed.
- Terminal enforcement success requires confirmed denial at the enforcing boundary. Durable idempotent repair must retain failed/pending effects; an outbox entry or registry status alone does not prove completion. No new DTO/status name is accepted by this receipt.

Expiry, selective restriction, rotation and revoke must preserve unaffected independent grants and reject affected grants at the selected enforcement point. A read-time check enforces a deadline; later cleanup/audit sweeps are not the deadline boundary. The current backend protocol and the spec's unchanged-`AdminAssetService` constraint (`phase7-production-hardening-spec.md:613,644`) need owner reconciliation.

This option could enforce next-resolution rules, but does not establish recall of cached plaintext or cancellation of already admitted/in-flight provider work. Neither a resolution-only limit nor universal cancellation is selected. SEAM-012's header infrastructure path and “Core secrets interface” wording, bounded operation, cache behavior, completion and outage guarantees remain contract questions.

| Owner | Required disposition |
|---|---|
| Core | Grant identity/backend API, deadline enforcement, selective issuance/replay behavior, truthful lifecycle/audit/completion and durable retry. |
| Complex | Bounded SEAM-012/S031/7F amendment and exact guarantee/ownership decision; reconcile historical advice without silent weakening. |
| SF | Consumer cache, route, admitted-operation and typed-refusal behavior when B2 starts. Owner-directed deferral remains intact. |
| Overcast | Agreed identities, resource/namespace permissions, networking, deployment and later operational evidence after selection. |

Static service/version policies, per-reference STS sessions and separate secret/resource-policy grants remain alternatives with identity, transferability, propagation and/or custody tradeoffs. No STS, IAM mutation, secret duplication/deletion, weaker staleness guarantee, synchronous per-operation Core dependency or SF bridge retirement is selected. 7F/B2 stays independent of B1 and 7G.

## Primary references and read inventory

Provider documentation used by the October 1 review:

- [GetSecretValue](https://docs.aws.amazon.com/secretsmanager/latest/apireference/API_GetSecretValue.html), [UpdateSecretVersionStage](https://docs.aws.amazon.com/secretsmanager/latest/apireference/API_UpdateSecretVersionStage.html), [PutSecretValue](https://docs.aws.amazon.com/secretsmanager/latest/apireference/API_PutSecretValue.html), [DeleteSecret](https://docs.aws.amazon.com/secretsmanager/latest/apireference/API_DeleteSecret.html).
- [Secrets Manager IAM conditions](https://docs.aws.amazon.com/service-authorization/latest/reference/list_secretsmanager.html), [ECS execution roles](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html).
- [IAM consistency](https://docs.aws.amazon.com/IAM/latest/UserGuide/troubleshoot.html), [Secrets Manager consistency](https://docs.aws.amazon.com/secretsmanager/latest/userguide/troubleshoot.html), [role-session revocation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_revoke-sessions.html).

Read inventory: Core route/DTO/dependency/migration/service/model/backend/readiness/test sources and pinned handoffs; Overcast workflows, environment/ECS/secrets/VPC modules, service templates and historical response; Complex F004, SEAM-012, custody addendum and architecture. October 3 work records that completed review, checks local governance/source correspondence and prepares the handoff; it does not rerun runtime acceptance.
