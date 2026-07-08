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
      {
        Sid      = "KMSDecrypt"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = ["*"]
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${var.aws_region}.amazonaws.com"
          }
        }
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

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

################################################################################
# EC2 Instance
################################################################################

resource "aws_instance" "coturn" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.coturn.id]
  iam_instance_profile   = aws_iam_instance_profile.coturn.name

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  user_data = base64encode(<<-USERDATA
    #!/bin/bash
    set -e

    # Install coturn
    dnf install -y coturn

    # Install render script (re-run on every coturn restart via ExecStartPre)
    cat > /usr/local/bin/render-coturn-config << 'RENDERSCRIPT'
    #!/bin/bash
    set -e

    REGION="${var.aws_region}"
    SECRET_ARN="${var.turn_secret_arn}"
    REALM="${var.realm}"

    # Fetch TURN shared secret (retry up to 5 times)
    SECRET=""
    for i in 1 2 3 4 5; do
      SECRET=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" --region "$REGION" --query 'SecretString' --output text 2>/dev/null || true)
      if [ -n "$SECRET" ]; then break; fi
      echo "render-coturn-config: secret not available (attempt $i), retrying in 5s..."
      sleep 5
    done

    # Fail-closed: if secret is empty, use a throwaway secret nobody knows
    if [ -z "$SECRET" ]; then
      SECRET=$(openssl rand -hex 32)
      echo "render-coturn-config: WARNING — using throwaway secret. Populate the real secret and restart coturn."
    fi

    # Fetch public IPv4 from IMDS (retry — EIP may associate after boot)
    PUBLIC_IP=""
    for i in 1 2 3 4 5 6 7 8 9 10; do
      TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
      PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || true)
      if [ -n "$PUBLIC_IP" ]; then break; fi
      echo "render-coturn-config: public IP not available (attempt $i), retrying in 5s..."
      sleep 5
    done

    if [ -z "$PUBLIC_IP" ]; then
      echo "render-coturn-config: ERROR — could not determine public IP"
      exit 1
    fi

    # Render config
    cat > /etc/turnserver.conf << EOF
    listening-port=3478
    realm=$REALM
    use-auth-secret
    static-auth-secret=$SECRET
    external-ip=$PUBLIC_IP
    min-port=49152
    max-port=65535
    no-cli
    no-tlsv1
    no-tlsv1_1
    fingerprint
    EOF

    echo "render-coturn-config: rendered with realm=$REALM external-ip=$PUBLIC_IP"
    RENDERSCRIPT

    chmod +x /usr/local/bin/render-coturn-config

    # Configure systemd to re-render config on every restart
    mkdir -p /etc/systemd/system/coturn.service.d
    cat > /etc/systemd/system/coturn.service.d/render-config.conf << 'OVERRIDE'
    [Service]
    ExecStartPre=/usr/local/bin/render-coturn-config
    OVERRIDE

    systemctl daemon-reload
    systemctl enable coturn
    systemctl start coturn
  USERDATA
  )

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
