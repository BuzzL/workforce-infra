variable "account_name" {
  description = "Name of the member account (security, workforce). Also the GitHub Environment that may assume the apply role; <name>-plan is the one for the plan role."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.account_name))
    error_message = "The account name must be lowercase letters, digits or hyphens."
  }
}

variable "github_owner" {
  description = "GitHub owner (user or organization) of the repository allowed to assume the roles."
  type        = string
  default     = "BuzzL"
}

variable "github_owner_id" {
  description = "Numeric GitHub ID of the owner. Public, not an AWS ID. Needed for the immutable OIDC subject (owner@id/repo@id)."
  type        = number
  default     = 6116516
}

variable "github_repository" {
  description = "Name of the repository (without the owner) allowed to assume the roles."
  type        = string
  default     = "workforce-infra"
}

variable "github_repository_id" {
  description = "Numeric GitHub ID of the repository. Public, not an AWS ID."
  type        = number
  default     = 1394667495
}

variable "state_bucket_name" {
  description = "Name of the Terraform state bucket, which lives in the management account."
  type        = string
}

variable "state_key" {
  description = "Object key of this account stack's state. The roles can reach this key and its lockfile, nothing else in the bucket."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
