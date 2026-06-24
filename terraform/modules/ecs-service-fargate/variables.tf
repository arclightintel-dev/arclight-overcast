# ECS Fargate service module variables
#
# Expected inputs:
#   - service_name
#   - environment
#   - cluster_id
#   - vpc_id, private_subnet_ids
#   - task_definition_template (path to .json.tpl)
#   - container_port
#   - desired_count
#   - cpu, memory
#   - ecr_repository_url
#   - image_tag
#   - secrets (map of env var name → Secrets Manager ARN)
#   - environment_variables (map of non-secret env vars)
#   - target_group_arn (optional — omit for internal-only services)
#   - health_check_path (default /ready)
#   - cloud_map_namespace_id
