variable "key" {
  description = "Four-letter key of the environment account the role lives in (scripts/environment-keys.tsv): test, qual or demo."
  type        = string

  validation {
    condition     = contains(["test", "qual", "demo"], var.key)
    error_message = "The key must be one of the environment accounts: test, qual, demo."
  }
}

variable "project" {
  description = "Project short name, the second part of every resource name (docs/ENVIRONMENT_PERMISSIONS.md)."
  type        = string
  default     = "foundation"

  validation {
    condition     = can(regex("^[a-z0-9]{1,10}$", var.project))
    error_message = "The project must match ^[a-z0-9]{1,10}$."
  }
}

variable "applications" {
  description = "Registered applications whose resources the agent may read (docs/ENVIRONMENT_PERMISSIONS.md, table of applications)."
  type        = list(string)
  default     = ["testbed"]

  validation {
    condition = length(var.applications) > 0 && alltrue([
      for a in var.applications : can(regex("^[a-z0-9]{1,16}$", a)) && !contains(["agent", "platform", "infra", "github"], a)
    ])
    error_message = "Applications are one segment matching ^[a-z0-9]{1,16}$ and never a reserved name (agent, platform, infra, github)."
  }
}

variable "region" {
  description = "Region of the environment account's resources (one region, docs/ORGANIZATION_INPUTS.md)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "The region must look like eu-west-1."
  }
}

variable "account_id" {
  description = "The environment account that holds the role and the resources it reads."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "The account ID must be 12 digits."
  }
}

variable "principal_arn" {
  description = "Exact ARN of the agent task role in the workforce account, the only principal that may assume the role."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role(/[A-Za-z0-9+=,.@_-]+)*/[A-Za-z0-9+=,.@_-]+$", var.principal_arn)) && can(regex("^wrkf-", element(split("/", var.principal_arn), length(split("/", var.principal_arn)) - 1)))
    error_message = "The principal must be the exact ARN of one role of the workforce account, named wrkf-<project>-... (no wildcard, not an account root)."
  }
}

variable "workforce_account_id" {
  description = "The workforce account, source of the principal."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.workforce_account_id)) && var.workforce_account_id != var.account_id && can(regex(":iam::${var.workforce_account_id}:role/", var.principal_arn))
    error_message = "The workforce account must be 12 digits, differ from the environment account, and own the principal."
  }
}

variable "external_ids" {
  description = "The environment's ExternalId, or two during a rotation (docs/ENVIRONMENT_PERMISSIONS.md)."
  type        = list(string)
  sensitive   = true
}

variable "tags" {
  description = "Tags applied to the role."
  type        = map(string)
  default     = {}
}
