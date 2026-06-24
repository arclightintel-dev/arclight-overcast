# IAM GitHub OIDC Module
#
# Provisions per D-056 §11:
#   - GitHub OIDC identity provider in IAM
#   - IAM role assumable by GitHub Actions (OIDC federation)
#   - Role policies: ECR push, ECS deploy, Terraform state access
#
# No long-lived AWS keys in GitHub secrets.
# GitHub Actions assume this role via OIDC token exchange.
