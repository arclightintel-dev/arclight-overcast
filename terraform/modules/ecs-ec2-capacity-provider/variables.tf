# EC2 capacity provider module variables
#
# Expected inputs:
#   - environment
#   - cluster_name
#   - vpc_id
#   - private_subnet_ids
#   - instance_type (e.g., t3.medium, m5.large)
#   - desired_capacity, min_size, max_size
#   - key_pair_name (optional — prefer SSM over SSH)
