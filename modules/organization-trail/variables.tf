variable "name" {
  description = "Name of the trail. Must equal the trail_name the log bucket policy admits, since that policy names the exact trail ARN."
  type        = string
  default     = "workforce-organization"
}

variable "s3_bucket_name" {
  description = "Log bucket, in the security account (modules/audit-log-bucket)."
  type        = string
}

variable "tags" {
  description = "Tags applied to the trail."
  type        = map(string)
  default     = {}
}
