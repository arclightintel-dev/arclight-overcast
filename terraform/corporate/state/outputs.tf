output "bucket_name" {
  description = "Dedicated corporate Terraform state bucket."
  value       = aws_s3_bucket.corporate_state.id
}

output "bucket_arn" {
  description = "Bucket ARN for separately reviewed corporate access policies."
  value       = aws_s3_bucket.corporate_state.arn
}
