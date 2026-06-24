# RDS PostgreSQL Module
#
# Provisions per D-056 §7:
#   - RDS PostgreSQL instance in private database subnets
#   - DB subnet group
#   - Per-module databases and roles:
#       core_{env}         (user: core_{env})
#       shuttleforge_{env} (user: sf_{env})
#       podbay_{env}       (user: podbay_{env})
#       nerfherder_{env}   (user: nf_{env}, reserved — created empty)
#   - Security group (allow from private app subnets only)
#   - Parameter group
#   - Automated backups / snapshots
#
# Single-AZ for staging. Multi-AZ for production (budget-dependent).
# Storage: gp3 (baseline IOPS included, $0.08/GB-month).
#
# Do NOT store large artifacts, browser profiles, screenshots,
# HAR/WARC captures, or workspace files in Postgres.
# RDS holds operational metadata. S3/EBS holds evidence/workspace bytes.
