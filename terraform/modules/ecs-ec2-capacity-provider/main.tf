# EC2 Capacity Provider Module
#
# Provisions per D-056 §6 (Podbay compute):
#   - EC2 Auto Scaling Group in private app subnets
#   - ECS-optimized AMI (Amazon Linux 2023)
#   - ECS capacity provider linked to the ASG
#   - Instance profile with ECS agent permissions
#   - Security group for EC2 hosts
#   - SSM Session Manager access (no SSH, no public IP)
#
# Fixed capacity for v1 — no auto-scaling policies.
# Podbay workspaces run on this capacity provider.
# Core and ShuttleForge run on Fargate (separate capacity).
