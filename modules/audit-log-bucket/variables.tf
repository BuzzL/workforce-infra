variable "bucket_name" {
  description = "Name of the log bucket. Globally unique."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "The bucket name must be 3 to 63 lowercase letters, digits, dots or hyphens."
  }
}

variable "organization_id" {
  description = "ID of the Organization (o-xxxx). The organization trail writes under AWSLogs/<organization id>/. Passed in from a secret, not looked up."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^o-[a-z0-9]{10,32}$", var.organization_id))
    error_message = "The Organization ID must look like o-ab12cd34ef."
  }
}

variable "trail_account_id" {
  description = "Account that owns the trail (the management account for an organization trail). Passed in from a secret."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[0-9]{12}$", var.trail_account_id))
    error_message = "The account ID must be 12 digits."
  }
}

variable "trail_region" {
  description = "Region of the trail, which is also the home region of the Organization."
  type        = string
}

variable "trail_name" {
  description = "Name of the trail allowed to write. The bucket policy names this exact trail ARN, so no other trail can write here."
  type        = string
  default     = "workforce-organization"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._-]{2,127}$", var.trail_name))
    error_message = "The trail name must be 3 to 128 letters, digits, dots, underscores or hyphens."
  }
}

variable "log_retention_days" {
  description = "Days after which log objects expire."
  type        = number
  default     = 365

  validation {
    condition     = var.log_retention_days >= 90
    error_message = "Keep logs for at least 90 days."
  }
}

variable "noncurrent_version_days" {
  description = "Days after which noncurrent object versions expire."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_days >= 1
    error_message = "Noncurrent versions must be kept for at least one day."
  }
}

variable "tags" {
  description = "Tags applied to the bucket."
  type        = map(string)
  default     = {}
}
