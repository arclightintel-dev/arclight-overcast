################################################################################
# VPC
################################################################################

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "arclight-${var.environment}" }
}

################################################################################
# Subnets
################################################################################

resource "aws_subnet" "public" {
  count = length(var.azs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "arclight-${var.environment}-public-${var.azs[count.index]}" }
}

resource "aws_subnet" "private_app" {
  count = length(var.azs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_app_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = { Name = "arclight-${var.environment}-private-app-${var.azs[count.index]}" }
}

resource "aws_subnet" "private_db" {
  count = length(var.azs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_db_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = { Name = "arclight-${var.environment}-private-db-${var.azs[count.index]}" }
}

resource "aws_subnet" "private_workspace" {
  count             = length(var.private_workspace_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_workspace_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = { Name = "arclight-${var.environment}-private-workspace-${var.azs[count.index]}" }
}

resource "aws_route_table_association" "private_workspace" {
  count          = length(var.private_workspace_subnet_cidrs)
  subnet_id      = aws_subnet.private_workspace[count.index].id
  route_table_id = aws_route_table.private_app.id
}

################################################################################
# Internet Gateway
################################################################################

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "arclight-${var.environment}" }
}

################################################################################
# NAT Gateway (single, us-east-1a for staging)
################################################################################

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = { Name = "arclight-${var.environment}-nat" }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = { Name = "arclight-${var.environment}" }

  depends_on = [aws_internet_gateway.this]
}

################################################################################
# Route Tables
################################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "arclight-${var.environment}-public" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = length(var.azs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private_app" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "arclight-${var.environment}-private-app" }
}

resource "aws_route" "private_app_nat" {
  route_table_id         = aws_route_table.private_app.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}

resource "aws_route_table_association" "private_app" {
  count = length(var.azs)

  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app.id
}

resource "aws_route_table" "private_db" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "arclight-${var.environment}-private-db" }
}

resource "aws_route_table_association" "private_db" {
  count = length(var.azs)

  subnet_id      = aws_subnet.private_db[count.index].id
  route_table_id = aws_route_table.private_db.id
}

################################################################################
# VPC Endpoints
################################################################################

resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "arclight-${var.environment}-vpce-"
  description = "VPC endpoint interface access"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from app and workspace subnets"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = concat(var.private_app_subnet_cidrs, var.private_workspace_subnet_cidrs)
  }

  tags = { Name = "arclight-${var.environment}-vpce" }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = [
    aws_route_table.private_app.id,
    aws_route_table.private_db.id,
  ]

  tags = { Name = "arclight-${var.environment}-s3" }
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private_app[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  tags = { Name = "arclight-${var.environment}-ecr-api" }
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private_app[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  tags = { Name = "arclight-${var.environment}-ecr-dkr" }
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.logs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private_app[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  tags = { Name = "arclight-${var.environment}-logs" }
}

data "aws_region" "current" {}

################################################################################
# Placeholder Service Security Groups
################################################################################

resource "aws_security_group" "core" {
  name_prefix = "arclight-${var.environment}-core-"
  description = "Core Fargate tasks"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "sg-core-${var.environment}" }
}

resource "aws_security_group" "shuttleforge" {
  name_prefix = "arclight-${var.environment}-shuttleforge-"
  description = "ShuttleForge Fargate tasks"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "sg-shuttleforge-${var.environment}" }
}

resource "aws_security_group" "podbay_controller" {
  name_prefix = "arclight-${var.environment}-podbay-ctrl-"
  description = "Podbay controller Fargate tasks"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "sg-podbay-controller-${var.environment}" }
}

resource "aws_security_group" "podbay_workspace" {
  name_prefix = "arclight-${var.environment}-podbay-ws-"
  description = "Podbay workspace containers"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "sg-podbay-workspace-${var.environment}" }
}

resource "aws_security_group" "dbbootstrap" {
  name_prefix = "arclight-${var.environment}-dbbootstrap-"
  description = "DB bootstrap one-off task"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "sg-dbbootstrap-${var.environment}" }
}
