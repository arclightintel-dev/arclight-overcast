output "instance_endpoint" {
  description = "RDS instance endpoint (host:port)"
  value       = aws_db_instance.this.endpoint
}

output "instance_address" {
  description = "RDS instance hostname"
  value       = aws_db_instance.this.address
}

output "instance_arn" {
  description = "RDS instance ARN"
  value       = aws_db_instance.this.arn
}

output "master_user_secret_arn" {
  description = "ARN of the RDS-managed master user secret in Secrets Manager"
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "rds_security_group_id" {
  description = "RDS security group ID"
  value       = aws_security_group.rds.id
}

output "db_subnet_group_name" {
  description = "DB subnet group name"
  value       = aws_db_subnet_group.this.name
}
