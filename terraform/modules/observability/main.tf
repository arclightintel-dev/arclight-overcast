# Observability Module
#
# Provisions per D-056 §10:
#   - CloudWatch Log Groups (one per service per environment)
#   - CloudWatch Alarms:
#       ALB: response time, 5xx count, unhealthy targets
#       ECS: desired vs running tasks, restarts, CPU/memory
#       RDS: CPU, storage, connections, freeable memory
#       Podbay EC2: disk/EBS usage, ECS agent health
#   - SNS topic for alarm notifications
#   - CloudWatch Agent config for EC2 instances (Podbay)
#   - CloudTrail for secrets/IAM audit
#
# Podbay disk usage and EBS snapshot health matter more than typical
# web-service CPU. Browser workspaces fail in operationally weird ways.
