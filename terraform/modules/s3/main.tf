# S3 Module
#
# Provisions:
#   - Terraform state bucket (versioning, encryption, no public access)
#   - Workspace artifact storage (sealed workspace exports, SEAM-015)
#   - Evidence/collection output storage (future)
#   - Bucket policies and lifecycle rules
#   - Server-side encryption (AES-256 or KMS)
