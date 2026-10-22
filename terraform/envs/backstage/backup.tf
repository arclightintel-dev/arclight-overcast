# Weekly snapshot of the data volume, kept 30 days (O-012 item 5). Litestream is the
# minute-level recovery point; this is the whole-volume fallback and the restore drill's
# second path. Backstage is the first AWS Backup consumer in this account.
resource "aws_backup_vault" "this" {
  name = local.name
}

resource "aws_backup_plan" "this" {
  name = local.name

  rule {
    rule_name         = "weekly-data-volume"
    target_vault_name = aws_backup_vault.this.name
    schedule          = "cron(0 5 ? * SUN *)"
    start_window      = 60
    completion_window = 360

    lifecycle {
      delete_after = var.backup_retention_days
    }
  }
}

data "aws_iam_policy_document" "backup_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backup" {
  name               = "${local.name}-backup"
  assume_role_policy = data.aws_iam_policy_document.backup_assume.json
}

resource "aws_iam_role_policy_attachment" "backup" {
  for_each = toset([
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup",
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores",
  ])

  role       = aws_iam_role.backup.name
  policy_arn = each.value
}

resource "aws_backup_selection" "data" {
  name         = "${local.name}-data"
  plan_id      = aws_backup_plan.this.id
  iam_role_arn = aws_iam_role.backup.arn
  resources    = [aws_ebs_volume.data.arn]
}
