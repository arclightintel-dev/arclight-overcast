# ECS EC2-backed Service Module
#
# For services requiring host-level capabilities (SYS_ADMIN, custom /dev/shm).
# Used by: Podbay controller + workspace tasks
#
# Provisions:
#   - ECS service definition (EC2 capacity provider strategy)
#   - Task definition with Linux capabilities (SYS_ADMIN for Chromium sandbox)
#   - sharedMemorySize: 256 MB (belt-and-suspenders with --disable-dev-shm-usage)
#   - CloudWatch log group
#   - Service Connect / Cloud Map registration
#   - ALB target group attachment (for Podbay controller)
#   - IAM task execution role + task role
#
# Per D-056 §6: workspace tasks launch via ECS RunTask, not Docker socket.
# Docker socket is explicitly rejected for production (§6 security note).
#
# Per D-056 §16: browser workspace task definitions must pass the
# 12-point runtime gate before production launch.
