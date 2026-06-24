# ECS Fargate Service Module
#
# Generic module for deploying a service on Fargate capacity.
# Used by: Core, ShuttleForge
#
# Provisions:
#   - ECS service definition (Fargate launch type)
#   - Task definition (references ECR image, secrets, env vars)
#   - CloudWatch log group
#   - Service Connect / Cloud Map service registration
#   - ALB target group attachment (if public)
#   - IAM task execution role + task role
#   - Security group for the service
#
# Per D-056 §4, each service gets three URL concerns:
#   *_PUBLIC_URL  — ALB, for browser redirects
#   *_INTERNAL_URL — Cloud Map, for service-to-service
#   CORE_ISSUER — platform const (https://core.internal), never changes
