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

# Target health (hosting response F15). A stopped instance's target is "unused", not
# "unhealthy", so this stays quiet overnight; the 15-minute window covers the app's start-up
# after the morning start. Before the first deploy there is no app on 8430, so it is in ALARM
# until then (one notification on entry, one on recovery).
resource "aws_cloudwatch_metric_alarm" "target_unhealthy" {
  alarm_name          = "${local.name}-target-unhealthy"
  alarm_description   = "Backstage target unhealthy on the prod ALB for 15 minutes while the host is running"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  dimensions          = { TargetGroup = aws_lb_target_group.host.arn_suffix, LoadBalancer = data.aws_lb.prod.arn_suffix }
  period              = 300
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [data.aws_sns_topic.alarms.arn]
  ok_actions          = [data.aws_sns_topic.alarms.arn]
}

# Portal container ceiling (hosting response F15): more Portal containers than Backstage's
# concurrency cap (3, OW-2) for 15 minutes means leaked or orphaned sessions holding memory.
resource "aws_cloudwatch_metric_alarm" "portal_containers" {
  alarm_name          = "${local.name}-portal-containers"
  alarm_description   = "More than 3 Portal containers on the Backstage host for 15 minutes (Backstage caps sessions at 3)"
  namespace           = "Arclight/Backstage"
  metric_name         = "PortalContainers"
  statistic           = "Minimum"
  dimensions          = { InstanceId = aws_instance.host.id }
  period              = 300
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = 3
  treat_missing_data  = "notBreaching"
  alarm_actions       = [data.aws_sns_topic.alarms.arn]
  ok_actions          = [data.aws_sns_topic.alarms.arn]
}

# Root (OS, Docker images and layers) and data (/srv/backstage) filesystems, above 80 percent
# (hosting response F15). The CloudWatch agent publishes both with drop_device, so the
# dimensions are InstanceId, path and fstype.
resource "aws_cloudwatch_metric_alarm" "disk" {
  for_each = { root = "/", data = "/srv/backstage" }

  alarm_name          = "${local.name}-${each.key}-disk"
  alarm_description   = "Backstage ${each.key} filesystem (${each.value}) above 80 percent"
  namespace           = "CWAgent"
  metric_name         = "disk_used_percent"
  statistic           = "Maximum"
  dimensions          = { InstanceId = aws_instance.host.id, path = each.value, fstype = "ext4" }
  period              = 300
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = 80
  treat_missing_data  = "notBreaching"
  alarm_actions       = [data.aws_sns_topic.alarms.arn]
  ok_actions          = [data.aws_sns_topic.alarms.arn]
}
