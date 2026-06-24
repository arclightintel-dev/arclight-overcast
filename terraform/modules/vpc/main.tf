# VPC Module
#
# Provisions per D-056 §2:
#   - VPC (10.0.0.0/16)
#   - Public subnets (2 AZs) — ALB, NAT Gateway
#   - Private app subnets (2 AZs) — ECS tasks (Core, ShuttleForge, Podbay)
#   - Private database subnets (2 AZs) — RDS PostgreSQL
#   - NAT Gateway (minimize via VPC endpoints)
#   - VPC Endpoints: ECR, CloudWatch Logs, Secrets Manager, SSM, KMS, S3
#   - Security groups for each tier
#
# No ECS task or Podbay EC2 host gets a public IP.
# Use SSM Session Manager for emergency host access, not SSH.
