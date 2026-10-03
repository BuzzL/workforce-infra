variable "allowed_region" {
  description = "The single AWS region where requests are allowed."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.allowed_region))
    error_message = "The region must look like eu-south-1."
  }
}

variable "global_service_prefixes" {
  description = "Service prefixes that stay allowed in every region because the service is global or served from us-east-1. Add a prefix only in the PR that needs it, with its test. See docs/ORGANIZATIONS.md."
  type        = list(string)
  default = [
    "account",
    "budgets",
    "ce",
    "iam",
    "identitystore",
    "organizations",
    "sso",
    "sts",
    "support",
  ]

  # Without these three the CI role cannot assume its role through the global STS
  # endpoint (us-east-1) and the Organization cannot be managed outside the region.
  validation {
    condition     = length(setintersection(var.global_service_prefixes, ["iam", "organizations", "sts"])) == 3
    error_message = "The exceptions must include at least iam, organizations and sts, or the SCP would lock out the CI role."
  }

  validation {
    condition     = length(distinct(var.global_service_prefixes)) == length(var.global_service_prefixes)
    error_message = "Service prefixes must be unique."
  }

  validation {
    condition     = alltrue([for p in var.global_service_prefixes : can(regex("^[a-z0-9-]+$", p))])
    error_message = "A service prefix is lowercase letters, digits and hyphens, without a colon or a wildcard."
  }
}

variable "tags" {
  description = "Tags applied to every policy."
  type        = map(string)
  default     = {}
}
