# ECS EC2 service module variables
#
# Expected inputs:
#   - service_name
#   - environment
#   - cluster_id
#   - vpc_id, private_subnet_ids
#   - capacity_provider_name
#   - container_port
#   - desired_count
#   - cpu, memory
#   - ecr_repository_url, image_tag
#   - secrets, environment_variables
#   - target_group_arn (optional)
#   - health_check_path
#   - linux_capabilities (list, e.g., ["SYS_ADMIN"])
#   - shared_memory_size_mb (default 256)
#   - cloud_map_namespace_id
