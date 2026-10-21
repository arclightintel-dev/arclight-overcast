# The compose services log to app, engine and litestream; Portal containers started by the
# app take the Docker daemon default, portal. The log driver never creates groups.
resource "aws_cloudwatch_log_group" "this" {
  for_each = local.log_groups

  name              = each.value
  retention_in_days = var.log_retention_days
}
