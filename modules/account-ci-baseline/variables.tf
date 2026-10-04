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

variable "baseline_state_key" {
  description = "Object key of the state of the stack that holds this baseline (bootstrap/accounts/<account>), which is applied locally. Both roles can read it and the apply role can take its lock, so the plan of that stack (a drift check) runs in CI; neither can write it. Null when the baseline has no stack of its own."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

variable "extra_read_statements" {
  description = "IAM statements added to the read-only policies of both roles, for what the stack itself manages beyond the baseline (e.g. Identity Center in the security account). Read actions only; the stack's own tests assert them literally."
  type        = any
  default     = []
}

variable "extra_write_statements" {
  description = "IAM statements added to the apply role only, for what the account's own stack (live/accounts/<account>) manages and CI applies. Each statement needs a Sid, Effect Allow, Action and Resource; no * in an action, no Not* element, no Principal, no bare * resource (a * inside an ARN pattern is allowed, for IDs that are not known before the call). The stack passing them writes the reason for each beside it and asserts them literally in its tests. The baseline itself stays out of reach: nothing here changes IAM."
  type        = any
  default     = []

  validation {
    condition = alltrue([
      for s in var.extra_write_statements : alltrue([for k in ["Sid", "Effect", "Action", "Resource"] : contains(keys(s), k)])
    ])
    error_message = "Every write statement needs a Sid, an Effect, an Action and a Resource."
  }

  validation {
    condition = alltrue([
      for s in var.extra_write_statements : s.Effect == "Allow"
      && !contains(keys(s), "NotAction") && !contains(keys(s), "NotResource") && !contains(keys(s), "NotPrincipal") && !contains(keys(s), "Principal")
    ])
    error_message = "A write statement is an Allow without Principal, NotAction, NotResource or NotPrincipal."
  }

  validation {
    condition = alltrue([
      for s in var.extra_write_statements : alltrue([for a in tolist(s.Action) : !strcontains(a, "*")])
    ])
    error_message = "A write statement names its actions: no * and no service:*."
  }

  validation {
    condition = alltrue([
      for s in var.extra_write_statements : alltrue([for r in tolist(s.Resource) : r != "*"])
    ])
    error_message = "A write statement names its resources: a bare * is not allowed."
  }
}
