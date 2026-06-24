# RDS PostgreSQL module variables
#
# Expected inputs:
#   - environment
#   - vpc_id
#   - private_db_subnet_ids
#   - instance_class (e.g., db.t3.micro for staging, db.t3.small for prod)
#   - allocated_storage_gb
#   - engine_version
#   - multi_az (bool)
#   - app_security_group_ids (allowed to connect)
#   - module_databases (list of {name, username} for per-module DBs)
