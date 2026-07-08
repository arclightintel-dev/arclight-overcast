output "turn_endpoint" {
  description = "TURN server public IP (EIP)"
  value       = aws_eip.coturn.public_ip
}

output "turn_security_group_id" {
  description = "coturn security group ID"
  value       = aws_security_group.coturn.id
}

output "instance_id" {
  description = "coturn EC2 instance ID"
  value       = aws_instance.coturn.id
}
