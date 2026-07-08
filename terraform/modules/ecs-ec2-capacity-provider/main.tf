################################################################################
# AMI lookup — ECS-optimized Amazon Linux 2023
################################################################################

data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

################################################################################
# Security Group
################################################################################

resource "aws_security_group" "ec2_host" {
  name_prefix = "arclight-${var.environment}-ec2-host-"
  description = "ECS EC2 host instances"
  vpc_id      = var.vpc_id

  egress {
    description = "All outbound (NAT + endpoints)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "arclight-${var.environment}-ec2-host" }
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

resource "aws_iam_role" "ec2_instance" {
  name               = "arclight-podbay-ec2-instance-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = { Name = "arclight-podbay-ec2-instance-${var.environment}" }
}

resource "aws_iam_role_policy_attachment" "ecs_agent" {
  role       = aws_iam_role.ec2_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ssm_agent" {
  role       = aws_iam_role.ec2_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2_instance.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "arclight-podbay-ec2-${var.environment}"
  role = aws_iam_role.ec2_instance.name
}

################################################################################
# Launch Template
################################################################################

resource "aws_launch_template" "this" {
  name_prefix   = "arclight-${var.environment}-podbay-"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2.arn
  }

  vpc_security_group_ids = [aws_security_group.ec2_host.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo "ECS_CLUSTER=${var.cluster_name}" >> /etc/ecs/ecs.config
    echo "ECS_ENABLE_CONTAINER_METADATA=true" >> /etc/ecs/ecs.config
  EOF
  )

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "arclight-${var.environment}-podbay"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "arclight-${var.environment}-podbay"
    }
  }
}

################################################################################
# Auto Scaling Group
################################################################################

resource "aws_autoscaling_group" "this" {
  name_prefix      = "arclight-${var.environment}-podbay-"
  desired_capacity = var.desired_capacity
  min_size         = var.min_size
  max_size         = var.max_size

  vpc_zone_identifier = var.private_subnet_ids

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  protect_from_scale_in = true

  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}

################################################################################
# ECS Capacity Provider
################################################################################

resource "aws_ecs_capacity_provider" "this" {
  name = "arclight-${var.environment}-podbay-ec2"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.this.arn
    managed_termination_protection = "ENABLED"

    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = 100
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 1
    }
  }

  tags = { Name = "arclight-${var.environment}-podbay-ec2" }
}
