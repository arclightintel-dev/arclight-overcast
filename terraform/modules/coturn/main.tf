################################################################################
# Security Group
################################################################################

resource "aws_security_group" "coturn" {
  name_prefix = "arclight-${var.environment}-coturn-"
  description = "coturn TURN server"
  vpc_id      = var.vpc_id

  ingress {
    description = "TURN control (UDP)"
    from_port   = 3478
    to_port     = 3478
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "TURN control (TCP)"
    from_port   = 3478
    to_port     = 3478
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "TURN relay (UDP)"
    from_port   = 49152
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "arclight-${var.environment}-coturn" }
}

################################################################################
# IAM — Instance Profile
################################################################################

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "coturn" {
  name               = "arclight-coturn-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = { Name = "arclight-coturn-${var.environment}" }
}

resource "aws_iam_role_policy_attachment" "coturn_ssm" {
  role       = aws_iam_role.coturn.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "coturn_secrets" {
  name = "turn-secret-read"
  role = aws_iam_role.coturn.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadTURNSecret"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [var.turn_secret_arn]
      },
    ]
  })
}

resource "aws_iam_instance_profile" "coturn" {
  name = "arclight-coturn-${var.environment}"
  role = aws_iam_role.coturn.name
}

################################################################################
# AMI lookup
################################################################################

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

################################################################################
# EC2 Instance
################################################################################

resource "aws_instance" "coturn" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.coturn.id]
  iam_instance_profile   = aws_iam_instance_profile.coturn.name

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  depends_on = [
    aws_iam_role_policy.coturn_secrets,
    aws_iam_role_policy_attachment.coturn_ssm,
  ]

  user_data                   = templatefile("${path.module}/templates/user-data.sh.tftpl", {
    eip_public_ip          = aws_eip.coturn.public_ip
    realm                  = var.realm
    aws_region             = var.aws_region
    turn_secret_arn        = var.turn_secret_arn
    vpc_cidr               = var.vpc_cidr
    workspace_subnet_cidrs = join(",", var.workspace_subnet_cidrs)
  })
  user_data_replace_on_change = true

  tags = { Name = "arclight-${var.environment}-coturn" }
}

################################################################################
# Elastic IP
################################################################################

resource "aws_eip" "coturn" {
  domain = "vpc"

  tags = { Name = "arclight-${var.environment}-coturn" }
}

resource "aws_eip_association" "coturn" {
  instance_id   = aws_instance.coturn.id
  allocation_id = aws_eip.coturn.id
}
