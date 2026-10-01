variable "region" {
  description = "AWS region of the state bucket."
  type        = string
}

variable "state_bucket_name" {
  description = "Globally unique name of the Terraform state bucket. Random-suffixed and never derived from an account ID."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.state_bucket_name))
    error_message = "The bucket name must be 3-63 lowercase letters, digits or hyphens."
  }

  validation {
    condition     = !can(regex("[0-9]{12}", var.state_bucket_name))
    error_message = "The bucket name must not contain a 12-digit number: it could be an account ID."
  }
}

variable "github_owner" {
  description = "GitHub owner (user or organization) of the repository allowed to assume the management CI role."
  type        = string
  default     = "BuzzL"
}

variable "github_owner_id" {
  description = "Numeric GitHub ID of the owner. Public, not an AWS ID. Needed because the repository issues immutable OIDC subjects (owner@id/repo@id), which also survive no rename or transfer."
  type        = number
  default     = 6116516
}

variable "github_repository" {
  description = "Name of the repository (without the owner) allowed to assume the management CI role."
  type        = string
  default     = "workforce-infra"
}

variable "github_repository_id" {
  description = "Numeric GitHub ID of the repository. Public, not an AWS ID."
  type        = number
  default     = 1394667495
}

variable "noncurrent_version_days" {
  description = "Days before old state versions are deleted."
  type        = number
  default     = 90
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    Project   = "ai-workforce"
    ManagedBy = "terraform"
    Stack     = "bootstrap"
  }
}

variable "budget_name" {
  description = "Name of the monthly budget that live/management manages. The CI roles may touch this budget and no other."
  type        = string
  default     = "Workforce Budget"
}
