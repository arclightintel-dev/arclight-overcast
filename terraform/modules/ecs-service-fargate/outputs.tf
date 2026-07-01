output "service_arn" {
  description = "ECS service ARN"
  value       = aws_ecs_service.this.id
}

output "service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.this.name
}

output "task_definition_arn" {
  description = "Task definition ARN"
  value       = aws_ecs_task_definition.this.arn
}

output "task_definition_family" {
  description = "Task definition family"
  value       = aws_ecs_task_definition.this.family
}

output "cloud_map_service_arn" {
  description = "Cloud Map service ARN"
  value       = aws_service_discovery_service.this.arn
}
