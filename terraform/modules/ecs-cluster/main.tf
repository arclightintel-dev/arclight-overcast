resource "aws_ecs_cluster" "this" {
  name = var.cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = var.cluster_name }
}

resource "aws_service_discovery_private_dns_namespace" "this" {
  name = var.private_dns_namespace
  vpc  = var.vpc_id

  tags = { Name = var.private_dns_namespace }
}
