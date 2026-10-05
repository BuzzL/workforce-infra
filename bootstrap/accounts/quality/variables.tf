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
  description = "Account ID of the quality account. Set only for the one-time local bootstrap, to assume OrganizationAccountAccessRole; null in CI. Never committed."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = var.break_glass_account_id == null || can(regex("^[0-9]{12}$", var.break_glass_account_id))
    error_message = "The account ID must be 12 digits."
  }
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    Project   = "ai-workforce"
    ManagedBy = "terraform"
    Stack     = "bootstrap/accounts/quality"
  }
}

variable "agent" {
  description = "The agent role of this account (docs/AGENT_ROLES.md): the exact ARN of the agent task role in workforce, that account's ID and the ExternalId of this environment (two during a rotation). Null creates no role. Set in the gitignored terraform.tfvars; never committed."
  type = object({
    principal_arn        = string
    workforce_account_id = string
    external_ids         = list(string)
  })
  default   = null
  sensitive = true
}
