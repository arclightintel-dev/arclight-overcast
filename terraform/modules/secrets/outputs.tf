output "secret_arns" {
  description = "Map of secret name to ARN"
  value       = { for k, v in aws_secretsmanager_secret.service : k => v.arn }
}

output "execution_role_arns" {
  description = "Map of service name to execution role ARN"
  value       = { for k, v in aws_iam_role.ecs_exec : k => v.arn }
}

output "core_database_url_secret_arn" {
  description = "ARN of the Core database URL secret"
  value       = aws_secretsmanager_secret.service["arclight/${var.environment}/core/database-url"].arn
}

output "shuttleforge_db_url_secret_arn" {
  description = "ARN of the ShuttleForge database URL secret"
  value       = aws_secretsmanager_secret.service["arclight/${var.environment}/shuttleforge/db-url"].arn
}

output "podbay_database_url_secret_arn" {
  description = "ARN of the Podbay database URL secret"
  value       = aws_secretsmanager_secret.service["arclight/${var.environment}/podbay/database-url"].arn
}

output "nerfherder_database_url_secret_arn" {
  description = "ARN of the Nerfherder database URL secret"
  value       = aws_secretsmanager_secret.service["arclight/${var.environment}/nerfherder/database-url"].arn
}
