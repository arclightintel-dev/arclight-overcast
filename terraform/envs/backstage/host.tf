# The Backstage host (INV-005 specification: docs/runbooks/migrate-backstage.md "Host" and
# the comments in host/). One Ubuntu 24.04 instance in the private app subnet of host_az, no
# public address, no key pair (Session Manager only), IMDSv2 with hop limit 1 (containers on
# the Portal bridge cannot reach it). The data volume outlives the instance.

resource "aws_ebs_volume" "data" {
  availability_zone = data.aws_subnet.host.availability_zone
  size              = var.data_volume_size_gb
  type              = "gp3"
  encrypted         = true

  tags = {
    Name   = "${local.name}-data"
    Backup = "weekly"
  }

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  host_file_sources = {
    "/usr/local/lib/backstage/common.sh"                  = { mode = "0644", src = "common.sh" }
    "/usr/local/sbin/backstage-mount-data"                = { mode = "0755", src = "backstage-mount-data.sh" }
    "/usr/local/sbin/backstage-firewall"                  = { mode = "0755", src = "backstage-firewall.sh" }
    "/usr/local/sbin/backstage-network"                   = { mode = "0755", src = "backstage-network.sh" }
    "/usr/local/sbin/backstage-render-env"                = { mode = "0755", src = "backstage-render-env.sh" }
    "/usr/local/sbin/backstage-render-secrets"            = { mode = "0755", src = "backstage-render-secrets.sh" }
    "/usr/local/sbin/backstage-compose-up"                = { mode = "0755", src = "backstage-compose-up.sh" }
    "/usr/local/sbin/backstage-busy-publish"              = { mode = "0755", src = "backstage-busy-publish.sh" }
    "/usr/local/sbin/backstage-deploy"                    = { mode = "0755", src = "backstage-deploy.sh" }
    "/etc/systemd/system/backstage-data.service"          = { mode = "0644", src = "backstage-data.service" }
    "/etc/systemd/system/backstage-firewall.service"      = { mode = "0644", src = "backstage-firewall.service" }
    "/etc/systemd/system/backstage-network.service"       = { mode = "0644", src = "backstage-network.service" }
    "/etc/systemd/system/backstage-compose.service"       = { mode = "0644", src = "backstage-compose.service" }
    "/etc/systemd/system/backstage-busy.service"          = { mode = "0644", src = "backstage-busy.service" }
    "/etc/systemd/system/backstage-busy.timer"            = { mode = "0644", src = "backstage-busy.timer" }
    "/etc/systemd/system/docker.service.d/backstage.conf" = { mode = "0644", src = "docker-backstage.conf" }
  }

  # Portal containers take the daemon defaults (the app starts them through the socket).
  # no-new-privileges is not a daemon default: the compose services set it themselves, and
  # whether Chromium in the Portal image tolerates it is Backstage's call per container.
  docker_daemon_json = jsonencode({
    "log-driver" = "awslogs"
    "log-opts" = {
      "awslogs-region"       = var.aws_region
      "awslogs-group"        = local.log_groups["portal"]
      "awslogs-create-group" = "false"
      "mode"                 = "non-blocking"
      "max-buffer-size"      = "4m"
      "tag"                  = "{{.Name}}/{{.ID}}"
    }
    "shutdown-timeout" = 120
    "live-restore"     = false
  })

  cloudwatch_agent_json = jsonencode({
    agent = { metrics_collection_interval = 60, run_as_user = "cwagent" }
    metrics = {
      namespace         = "CWAgent"
      append_dimensions = { InstanceId = "$${aws:InstanceId}" }
      metrics_collected = {
        disk = { measurement = ["used_percent"], resources = ["/", "/srv/backstage"], drop_device = true }
        mem  = { measurement = ["mem_used_percent"] }
      }
    }
  })

  host_files = merge(
    { for dest, f in local.host_file_sources : dest => { mode = f.mode, content = file("${path.module}/host/${f.src}") } },
    {
      "/etc/docker/daemon.json"                             = { mode = "0644", content = local.docker_daemon_json }
      "/opt/aws/amazon-cloudwatch-agent/etc/backstage.json" = { mode = "0644", content = local.cloudwatch_agent_json }
    },
  )

  # Only per-instance constants: anything that can change lives in SSM (ssm.tf), so it never
  # replaces the instance.
  user_data = templatefile("${path.module}/templates/user-data.sh.tftpl", {
    environment    = var.environment
    aws_region     = var.aws_region
    ssm_prefix     = local.ssm_prefix
    data_volume_id = replace(aws_ebs_volume.data.id, "-", "")
    portal_subnet  = var.portal_subnet
    bridge_ifname  = var.bridge_ifname
    files          = local.host_files
  })
}

resource "aws_instance" "host" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnet.host.id
  vpc_security_group_ids      = [aws_security_group.host.id]
  iam_instance_profile        = aws_iam_instance_profile.host.name
  associate_public_ip_address = false

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    encrypted             = true
    delete_on_termination = true
  }

  credit_specification {
    cpu_credits = "unlimited"
  }

  # The rendered script is about 27 KB, over EC2's 16 KB user-data limit, so it is sent
  # gzip-compressed and base64-encoded once; cloud-init detects and unpacks gzip. This is not
  # the double encoding INV-006 forbids (base64-encoding text passed to the plain user_data
  # argument, which the provider encodes again).
  user_data_base64            = base64gzip(local.user_data)
  user_data_replace_on_change = true

  tags = { Name = "${local.name}-host" }

  lifecycle {
    ignore_changes = [ami]

    # EC2 limits the decoded user data (here the gzip bytes) to 16 KB, which is at most
    # 21,848 base64 characters. On 2026-10-21 it was 12,276.
    precondition {
      condition     = length(base64gzip(local.user_data)) <= 21848
      error_message = "Compressed user data exceeds EC2's 16 KB limit; move content out of the template."
    }
  }

  # First boot needs its instance profile, every egress rule (cloud-init's apt step runs
  # within seconds of launch) and the SSM parameters the firewall reads before Docker.
  depends_on = [
    aws_iam_role_policy.host,
    aws_iam_role_policy_attachment.host_ssm,
    aws_vpc_security_group_egress_rule.proxy,
    aws_vpc_security_group_egress_rule.s3,
    aws_vpc_security_group_egress_rule.vpc_endpoints,
    aws_vpc_security_group_egress_rule.entra,
    aws_vpc_security_group_egress_rule.anthropic,
    aws_vpc_security_group_egress_rule.maintenance,
    aws_ssm_parameter.this,
  ]
}

resource "aws_volume_attachment" "data" {
  device_name                    = "/dev/sdf"
  volume_id                      = aws_ebs_volume.data.id
  instance_id                    = aws_instance.host.id
  stop_instance_before_detaching = true
}
