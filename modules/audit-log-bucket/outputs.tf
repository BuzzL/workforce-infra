output "bucket_name" {
  description = "Name of the log bucket, for the trail's s3_bucket_name."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "ARN of the log bucket."
  value       = aws_s3_bucket.this.arn
}
