output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  description = "Private app subnet IDs"
  value       = aws_subnet.private_app[*].id
}

output "private_db_subnet_ids" {
  description = "Private DB subnet IDs"
  value       = aws_subnet.private_db[*].id
}

output "private_app_subnet_cidrs" {
  description = "Private app subnet CIDR blocks"
  value       = aws_subnet.private_app[*].cidr_block
}

output "nat_gateway_id" {
  description = "NAT Gateway ID"
  value       = aws_nat_gateway.this.id
}

output "sg_core_id" {
  description = "Core service security group ID"
  value       = aws_security_group.core.id
}

output "sg_shuttleforge_id" {
  description = "ShuttleForge service security group ID"
  value       = aws_security_group.shuttleforge.id
}

output "sg_dbbootstrap_id" {
  description = "DB bootstrap task security group ID"
  value       = aws_security_group.dbbootstrap.id
}

output "private_app_route_table_id" {
  description = "Private app route table ID"
  value       = aws_route_table.private_app.id
}
