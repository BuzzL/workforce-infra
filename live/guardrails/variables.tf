variable "region" {
  description = "AWS region of the provider and of the state bucket, and the only region the region SCP allows. No default: it comes from the gitignored terraform.tfvars."
  type        = string
}

variable "attachments" {
  description = "The rollout stage: organizational unit name to the baseline SCPs attached to it. Empty attaches nothing. The Organization root and accounts cannot be named: the only targets are OUs."
  type        = map(list(string))
  default     = {}

  validation {
    condition     = alltrue([for ou in keys(var.attachments) : contains(["Management", "Environments", "Development", "Operations"], ou)])
    error_message = "The keys must be organizational unit names: Management, Environments, Development or Operations. The root and accounts are never targets."
  }

  validation {
    condition = alltrue([
      for policies in values(var.attachments) :
      alltrue([for p in policies : contains(["deny-leave-organization", "deny-root-user", "deny-disable-cloudtrail", "deny-outside-allowed-region"], p)])
    ])
    error_message = "Only the four baseline SCPs of modules/scp-baseline can be attached: deny-leave-organization, deny-root-user, deny-disable-cloudtrail, deny-outside-allowed-region."
  }

  validation {
    condition     = alltrue([for policies in values(var.attachments) : length(distinct(policies)) == length(policies)])
    error_message = "A policy can be listed once per organizational unit."
  }
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    Project   = "ai-workforce"
    ManagedBy = "terraform"
    Stack     = "live/guardrails"
  }
}
