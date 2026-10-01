variable "permission_sets" {
  description = "Permission sets to create, by name. Each carries exactly one AWS managed policy, so what a set can do is readable from its name and nothing is inlined."
  type = map(object({
    description        = string
    managed_policy_arn = string
    session_duration   = string
  }))

  validation {
    condition     = alltrue([for name, ps in var.permission_sets : can(regex("^arn:aws:iam::aws:policy/[A-Za-z0-9+=,.@_/-]+$", ps.managed_policy_arn))])
    error_message = "Each permission set must use an AWS managed policy ARN (arn:aws:iam::aws:policy/...)."
  }

  validation {
    condition     = alltrue([for name, ps in var.permission_sets : can(regex("^PT([1-9]|1[0-2])H$", ps.session_duration))])
    error_message = "The session duration must be between PT1H and PT12H."
  }
}

variable "maintainer_username" {
  description = "User name of the maintainer in the Identity Center identity store. Set by CI from the secret MAINTAINER_USERNAME (TF_VAR_maintainer_username); never committed."
  type        = string
  sensitive   = true
}

variable "account_ids" {
  description = "Member accounts that get assignments, by name. The management account is not listed: Identity Center cannot provision a permission set into it from the delegated administrator, so it is assigned from the management account."
  type        = map(string)
  sensitive   = true

  validation {
    condition     = alltrue([for name, id in var.account_ids : can(regex("^[0-9]{12}$", id))])
    error_message = "Account IDs must be 12 digits."
  }
}

variable "assignments" {
  description = "Account names (keys of account_ids) the maintainer is assigned to, by permission set name."
  type        = map(list(string))
  default     = {}

  validation {
    condition     = alltrue([for name in keys(var.assignments) : contains(keys(var.permission_sets), name)])
    error_message = "An assignment names a permission set that is not defined."
  }

  validation {
    condition     = alltrue([for name, accounts in var.assignments : alltrue([for a in accounts : contains(keys(var.account_ids), a)])])
    error_message = "An assignment names an account that is not in account_ids."
  }
}

variable "tags" {
  description = "Tags applied to the permission sets."
  type        = map(string)
  default     = {}
}
