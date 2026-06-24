output "capacity_provider_name" {
  description = "ECS capacity provider name"
  value       = aws_ecs_capacity_provider.this.name
}

output "asg_arn" {
  description = "Auto Scaling Group ARN"
  value       = aws_autoscaling_group.this.arn
}

output "instance_security_group_id" {
  description = "EC2 host security group ID"
  value       = aws_security_group.ec2_host.id
}
