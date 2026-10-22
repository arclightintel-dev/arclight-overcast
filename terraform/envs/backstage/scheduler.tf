# Morning start (O-012 item 6). Nothing stops the host on a schedule: only the idle alarm
# does, so an evening cron never races an analyst who is still working.
data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${local.name}-scheduler"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}

resource "aws_iam_role_policy" "scheduler" {
  name = "start-host"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "StartHost"
      Effect   = "Allow"
      Action   = ["ec2:StartInstances"]
      Resource = [aws_instance.host.arn]
    }]
  })
}

resource "aws_scheduler_schedule" "morning_start" {
  name                         = "${local.name}-start"
  state                        = var.scheduled_start_enabled ? "ENABLED" : "DISABLED"
  schedule_expression          = var.start_schedule
  schedule_expression_timezone = var.start_timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:startInstances"
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ InstanceIds = [aws_instance.host.id] })

    retry_policy {
      maximum_retry_attempts       = 3
      maximum_event_age_in_seconds = 3600
    }
  }
}
