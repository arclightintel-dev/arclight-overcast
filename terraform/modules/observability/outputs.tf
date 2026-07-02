output "log_group_arns" {
  description = "Map of service name to log group ARN"
  value       = { for k, v in aws_cloudwatch_log_group.services : k => v.arn }
}

output "alarm_topic_arn" {
  description = "SNS alarm topic ARN"
  value       = aws_sns_topic.alarms.arn
}

output "cloudtrail_bucket_name" {
  description = "CloudTrail S3 bucket name"
  value       = var.create_cloudtrail ? aws_s3_bucket.cloudtrail[0].id : ""
}
