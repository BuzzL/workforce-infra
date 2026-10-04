variable "region" {
  description = "AWS region of the provider and of the state bucket."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    Project   = "ai-workforce"
    ManagedBy = "terraform"
    Stack     = "live/environments/quality"
  }
}
