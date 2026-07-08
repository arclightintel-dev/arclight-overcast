# Podbay Batch 5 — Infrastructure Requirements (v1)

> **Source**: arclight-podbay, branch `claude-dev-phase-2` at `56edc99`
> **Received**: 2026-07-02
> **Spec**: `docs/specs/phase-2-spec.md` v1.1.0, deployment profiles at lines 140-158
> **Context**: Batches 1-4 complete (788 tests, all reviewers GO). Batch 5 is first AWS integration.

---

## 5a: ECS Adapter

Podbay needs to RunTask workspace containers on ECS EC2 capacity provider.

| Resource | Purpose | Notes |
|----------|---------|-------|
| ECS cluster | Workspace container host | EC2 capacity provider (ASG desired=0, scales on demand) |
| ECS task definition | Workspace browser container | Image: `podbay/workspace-browser` from ECR. Needs: CPU/memory, volume mounts, port mappings (none published externally), environment variables (CAPTURE_SERVICE_SECRET, NEKO_*), security group assignment |
| ECR repository | Browser image storage | Repo name/URI for `podbay/workspace-browser` image push |
| Security group (workspace SG) | Network isolation | Inbound: allow from controller SG only (CDP 9223, capture service 9280, Neko 8080). No public inbound. Outbound: allow all (S-016 direct egress) |
| Security group (controller SG) | Controller identity | The existing Fargate controller SG. Workspace SG references this for ingress rules |
| IAM task execution role | ECS task launch | ECR pull, CloudWatch logs write |
| IAM task role | Workspace container permissions | Minimal — no AWS API access needed from inside workspace |
| CloudWatch log group | Container logs | For workspace container stdout/stderr |
| VPC subnets | Task placement | Private subnets with NAT gateway for outbound (S-016 direct egress) |

## 5b: Production TURN

WebRTC media must traverse a Podbay-controlled TURN relay in staging/prod. No direct client-to-workspace UDP.

| Resource | Purpose | Notes |
|----------|---------|-------|
| TURN server | WebRTC media relay | coturn or equivalent. Must support credential-based auth with per-grant credentials |
| TURN server endpoint | Client-facing | Public IP/hostname for TURN. Clients configure this as ICE server |
| TURN credential API | Grant-scoped credentials | Podbay mints short-lived TURN credentials per surface grant. Needs: shared secret or REST API for credential generation. Credential lifetime matches grant TTL |
| Security group | TURN traffic | UDP port range (e.g., 49152-65535) for TURN relay. TCP 3478 for TURN control |
| DNS record | TURN hostname | e.g., `turn.staging.arclight-complex.net` or public DNS for client access |

## 5c: Full Readiness (staging/prod)

| Resource | Purpose | Notes |
|----------|---------|-------|
| S3 bucket | Export storage | Bucket name, write permissions for controller |
| S3 bucket policy / IAM | Controller write access | Controller's task role needs `s3:PutObject`, `s3:GetObject`, `s3:HeadBucket` on the export bucket |

## 5d: SS12.7 Debt

No new infrastructure — controller-side code changes only.

## Environment variables Podbay will consume

```
PODBAY_ECS_CLUSTER=arclight-staging
PODBAY_ECS_TASK_DEFINITION=arclight-podbay-workspace-staging
PODBAY_ECS_SUBNETS=<comma-separated private app subnet IDs>
PODBAY_ECS_SECURITY_GROUPS=<workspace SG ID>
PODBAY_EXPORT_S3_BUCKET=<export bucket name>
PODBAY_TURN_ENDPOINT=<TURN server public endpoint>
PODBAY_TURN_SECRET=<TURN shared secret — from Secrets Manager>
```
