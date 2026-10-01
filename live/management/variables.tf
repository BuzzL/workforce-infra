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
