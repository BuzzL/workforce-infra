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

  validation {
    condition     = length(var.maintainer_username) > 0
    error_message = "The maintainer user name is empty: set the secret MAINTAINER_USERNAME of this GitHub Environment."
  }
}

variable "assignment_account_ids" {
  description = "Member accounts the maintainer is assigned to, by name (not the management account). Set by CI from the secret ASSIGNMENT_ACCOUNT_IDS (TF_VAR_assignment_account_ids, JSON); never committed."
  type        = map(string)
  sensitive   = true

  validation {
    condition     = !contains(nonsensitive(keys(var.assignment_account_ids)), "management")
    error_message = "The management account cannot be assigned from the delegated administrator: it stays a manual assignment."
  }
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

variable "audit_log_bucket_name" {
  description = "Name of the organization trail's log bucket. Null or empty keeps audit logging off. Set by CI from the secret AUDIT_LOG_BUCKET (TF_VAR_audit_log_bucket_name); never committed. See docs/AUDIT_LOGGING.md."
  type        = string
  default     = null
  sensitive   = true
}

variable "organization_id" {
  description = "ID of the Organization (o-xxxx), for the log bucket policy. Set by CI from the secret ORGANIZATION_ID (TF_VAR_organization_id); required with audit_log_bucket_name."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = !try(length(var.audit_log_bucket_name) > 0, false) || try(length(var.organization_id) > 0, false)
    error_message = "organization_id is required when audit_log_bucket_name is set."
  }
}

variable "management_account_id" {
  description = "ID of the management account, which owns the trail. Set by CI from the secret MANAGEMENT_ACCOUNT_ID (TF_VAR_management_account_id); required with audit_log_bucket_name."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = !try(length(var.audit_log_bucket_name) > 0, false) || try(length(var.management_account_id) > 0, false)
    error_message = "management_account_id is required when audit_log_bucket_name is set."
  }

  validation {
    condition     = !try(length(var.management_account_id) > 0, false) || can(regex("^[0-9]{12}$", var.management_account_id))
    error_message = "The management account ID must be 12 digits."
  }
}
