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
  description = "Account ID of the security account. Set only for the first local run, to assume OrganizationAccountAccessRole; null once the maintainer's own session in the account is used. Never committed."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = var.break_glass_account_id == null || can(regex("^[0-9]{12}$", var.break_glass_account_id))
    error_message = "The account ID must be 12 digits."
  }
}

variable "audit_log_bucket_name" {
  description = "Name of the organization trail's log bucket. Null or empty keeps audit logging off. Set by CI from the secret AUDIT_LOG_BUCKET (TF_VAR_audit_log_bucket_name); never committed. See docs/AUDIT_LOGGING.md."
  type        = string
  default     = null
  sensitive   = true
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    Project   = "ai-workforce"
    ManagedBy = "terraform"
    Stack     = "bootstrap/accounts/security"
  }
}
