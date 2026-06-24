# VPC module variables
#
# Expected inputs:
#   - environment (staging/prod)
#   - vpc_cidr (default 10.0.0.0/16)
#   - azs (list of availability zones)
#   - enable_nat_gateway (bool)
#   - vpc_endpoint_services (list of AWS services for VPC endpoints)
