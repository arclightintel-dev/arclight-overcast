# Idle-stop (O-012 item 6, owner decision D16). The host publishes Arclight/Backstage Busy
# with its InstanceId every minute (host/backstage-busy-publish.sh): running jobs, Portal
# runtimes and containers, operator sessions, the hold file, recent ALB requests and a boot
# grace. Only a plain alarm on a metric with an InstanceId dimension may use the EC2 stop
# action (composite and metric-math alarms may not), so this is that alarm.
# Missing data is "missing": no action before the publisher's first datapoint, and a dead
# publisher never stops a working host. After any start the boot grace publishes Busy >= 1,
# which returns the alarm to OK so the next idle period stops the host again.

# The EC2 stop action runs through this service-linked role; it did not exist in the
# account on 2026-10-21.
resource "aws_iam_service_linked_role" "cloudwatch_events" {
  aws_service_name = "events.amazonaws.com"
  description      = "CloudWatch alarm EC2 actions (Backstage idle-stop)"
}

resource "aws_cloudwatch_metric_alarm" "idle_stop" {
  alarm_name          = "${local.name}-idle-stop"
  alarm_description   = "Backstage host idle (no jobs, Portal, sessions, holds or requests) for ${var.idle_stop_minutes} minutes: stop the instance. The scheduled start or the deploy workflow brings it back."
  namespace           = "Arclight/Backstage"
  metric_name         = "Busy"
  statistic           = "Maximum"
  dimensions          = { InstanceId = aws_instance.host.id }
  period              = 60
  evaluation_periods  = var.idle_stop_minutes
  datapoints_to_alarm = var.idle_stop_minutes
  comparison_operator = "LessThanOrEqualToThreshold"
  threshold           = 0
  treat_missing_data  = "missing"
  actions_enabled     = var.idle_stop_enabled
  alarm_actions       = ["arn:aws:automate:${var.aws_region}:ec2:stop", data.aws_sns_topic.alarms.arn]

  depends_on = [aws_iam_service_linked_role.cloudwatch_events]
}

resource "aws_cloudwatch_metric_alarm" "status_check" {
  alarm_name          = "${local.name}-status-check"
  alarm_description   = "Backstage host failed an EC2 status check for three minutes"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  statistic           = "Maximum"
  dimensions          = { InstanceId = aws_instance.host.id }
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  treat_missing_data  = "notBreaching" # stopped at night: no data, no alarm
  alarm_actions       = [data.aws_sns_topic.alarms.arn]
  ok_actions          = [data.aws_sns_topic.alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "data_disk" {
  alarm_name          = "${local.name}-data-disk"
  alarm_description   = "Backstage data volume (/srv/backstage) above 85 percent"
  namespace           = "CWAgent"
  metric_name         = "disk_used_percent"
  statistic           = "Maximum"
  dimensions          = { InstanceId = aws_instance.host.id, path = "/srv/backstage", fstype = "ext4" }
  period              = 300
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = 85
  treat_missing_data  = "notBreaching"
  alarm_actions       = [data.aws_sns_topic.alarms.arn]
  ok_actions          = [data.aws_sns_topic.alarms.arn]
}
