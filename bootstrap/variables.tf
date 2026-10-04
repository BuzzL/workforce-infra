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

variable "member_account_ids" {
  description = "Account IDs of the member accounts with a CI baseline (security, workforce, test, quality, demo), by name. Set locally only, never committed. Empty until live/accounts/<name> has been bootstrapped: the state bucket policy names the roles that stack creates, and S3 rejects a policy that names a principal that does not exist yet."
  type        = map(string)
  default     = {}
  sensitive   = true

  validation {
    condition     = alltrue([for name, id in var.member_account_ids : contains(["security", "workforce", "test", "quality", "demo"], name) && can(regex("^[0-9]{12}$", id))])
    error_message = "Keys must be security, workforce, test, quality or demo and values 12-digit account IDs."
  }
}

variable "github_ci_repository" {
  description = "Name of the repository (without the owner) that manages GitHub as code and may assume the github-infra-github roles."
  type        = string
  default     = "workforce-github"
}

variable "github_ci_repository_id" {
  description = "Numeric GitHub ID of that repository. Public, not an AWS ID. Needed for the immutable OIDC subject."
  type        = number
  default     = 1398476489
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

variable "audit_trail_enabled" {
  description = "Grant the management CI roles what the organization trail needs (docs/AUDIT_LOGGING.md). True now that the grants are applied: CI plans bootstrap/ without any local variable, so a false default would plan their removal. Set false only to take the grants away on purpose."
  type        = bool
  default     = true
}
