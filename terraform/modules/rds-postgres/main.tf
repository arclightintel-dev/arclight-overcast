resource "aws_db_subnet_group" "this" {
  name       = "arclight-${var.environment}"
  subnet_ids = var.private_db_subnet_ids

  tags = { Name = "arclight-${var.environment}" }
}

resource "aws_db_parameter_group" "this" {
  name_prefix = "arclight-${var.environment}-pg16-"
  family      = "postgres16"
  description = "Arclight ${var.environment} PostgreSQL 16 parameters"

  tags = { Name = "arclight-${var.environment}-pg16" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "random_id" "rds_snapshot" {
  byte_length = 4
}

resource "aws_security_group" "rds" {
  name_prefix = "arclight-${var.environment}-rds-"
  description = "RDS PostgreSQL access"
  vpc_id      = var.vpc_id

  tags = { Name = "arclight-${var.environment}-rds" }
}

resource "aws_security_group_rule" "rds_ingress" {
  count = length(var.app_security_group_ids)

  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = var.app_security_group_ids[count.index]
}

resource "aws_db_instance" "this" {
  identifier = "arclight-${var.environment}"

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "postgres"
  username = "arclight_admin"

  manage_master_user_password = true

  multi_az               = var.multi_az
  db_subnet_group_name   = aws_db_subnet_group.this.name
  parameter_group_name   = aws_db_parameter_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  backup_retention_period   = var.backup_retention_period
  skip_final_snapshot       = false
  final_snapshot_identifier = "arclight-${var.environment}-final-${random_id.rds_snapshot.hex}"

  deletion_protection = true
  publicly_accessible = false

  tags = { Name = "arclight-${var.environment}" }
}
