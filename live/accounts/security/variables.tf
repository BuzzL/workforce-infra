variable "region" {
  description = "AWS region of the provider and of the state bucket."
  type        = string
}

variable "state_bucket_name" {
  description = "Name of the Terraform state bucket (management account). Set by CI from the secret STATE_BUCKET (TF_VAR_state_bucket_name)."
  type        = string
  sensitive   = true
}

variable "break_glass_account_id" {
  description = "Account ID of the security account. Set only for the one-time local bootstrap, to assume OrganizationAccountAccessRole; null in CI. Never committed."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = var.break_glass_account_id == null || can(regex("^[0-9]{12}$", var.break_glass_account_id))
    error_message = "The account ID must be 12 digits."
  }
}

variable "maintainer_username" {
  description = "User name of the maintainer in Identity Center. Set by CI from the secret MAINTAINER_USERNAME (TF_VAR_maintainer_username); never committed."
  type        = string
  sensitive   = true
}

variable "assignment_account_ids" {
  description = "Member accounts the maintainer is assigned to, by name (not the management account). Set by CI from the secret ASSIGNMENT_ACCOUNT_IDS (TF_VAR_assignment_account_ids, JSON); never committed."
  type        = map(string)
  sensitive   = true
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    Project   = "ai-workforce"
    ManagedBy = "terraform"
    Stack     = "live/accounts/security"
  }
}
