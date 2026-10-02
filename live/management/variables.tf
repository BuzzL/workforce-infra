variable "region" {
  description = "AWS region of the provider and of the state bucket."
  type        = string
}

variable "root_id" {
  description = "ID of the Organization root (r-xxxx). Set by CI from the secret ORGANIZATION_ROOT_ID (TF_VAR_root_id). It is passed in, not looked up, so the CI roles need no Organization-wide read."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^r-[a-z0-9]{4,32}$", var.root_id))
    error_message = "The root ID must look like r-ab12."
  }
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    Project   = "ai-workforce"
    ManagedBy = "terraform"
    Stack     = "live/management"
  }
}

variable "account_email_base" {
  description = "Base mailbox of the member accounts (local@domain). Each account gets local+<account>@domain. Set by CI from the secret ACCOUNT_EMAIL_BASE (TF_VAR_account_email_base); never committed."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[A-Za-z0-9._%-]+@[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$", var.account_email_base))
    error_message = "The account email base must look like local@domain and must not contain a +."
  }

  # Organizations limits an email to 64 characters; the longest address is the one with the longest account name (workforce).
  validation {
    condition     = length(var.account_email_base) + length("+workforce") <= 64
    error_message = "local+workforce@domain must not exceed 64 characters."
  }
}

variable "budget_name" {
  description = "Name of the existing monthly budget that this stack imports and manages."
  type        = string
  default     = "Workforce Budget"
}

variable "budget_limit_usd" {
  description = "Monthly cost limit of the budget, in USD. Everything the Organization bills is counted; see docs/BUDGET.md."
  type        = number
  default     = 20
}

variable "budget_alert_email" {
  description = "Address notified at every budget threshold. Set by CI from the secret BUDGET_ALERT_EMAIL (TF_VAR_budget_alert_email)."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.budget_alert_email))
    error_message = "The budget alert address must look like local@domain."
  }
}

variable "audit_log_bucket_name" {
  description = "Name of the log bucket in the security account. Null keeps the organization trail off. To be set by CI from the secret AUDIT_LOG_BUCKET (TF_VAR_audit_log_bucket_name) once the workflow is wired, see docs/AUDIT_LOGGING.md; never committed."
  type        = string
  default     = null
  sensitive   = true
}
