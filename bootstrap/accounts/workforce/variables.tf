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
  description = "Account ID of the workforce account. Set only for the one-time local bootstrap, to assume OrganizationAccountAccessRole; null in CI. Never committed."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = var.break_glass_account_id == null || can(regex("^[0-9]{12}$", var.break_glass_account_id))
    error_message = "The account ID must be 12 digits."
  }
}

variable "matrix" {
  description = "The matrix runner roles (docs/AGENT_ROLES.md): the account ID of each environment account, whose agent role the runner of that environment may assume. Null creates no role. Set in the gitignored terraform.tfvars and in the secret MATRIX of workforce-plan; never committed."
  type = object({
    environment_account_ids = map(string)
  })
  default   = null
  sensitive = true

  validation {
    condition = var.matrix == null || (
      toset(keys(var.matrix.environment_account_ids)) == toset(["demo", "quality", "test"]) &&
      alltrue([for id in values(var.matrix.environment_account_ids) : can(regex("^[0-9]{12}$", id))])
    )
    error_message = "matrix.environment_account_ids needs the 12-digit account ID of test, quality and demo, and nothing else."
  }
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    Project   = "ai-workforce"
    ManagedBy = "terraform"
    Stack     = "bootstrap/accounts/workforce"
  }
}
