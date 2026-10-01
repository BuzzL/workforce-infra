variable "name" {
  description = "Name of the budget."
  type        = string
}

variable "limit_usd" {
  description = "Monthly cost limit in USD."
  type        = number

  validation {
    condition     = var.limit_usd > 0
    error_message = "The monthly limit must be greater than zero."
  }
}

variable "alert_emails" {
  description = "Addresses notified at every threshold. Pass them from a secret, never commit them."
  type        = list(string)
  sensitive   = true

  validation {
    condition     = length(var.alert_emails) > 0 && alltrue([for e in var.alert_emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "Provide at least one address, each shaped like local@domain."
  }
}

variable "thresholds_percent" {
  description = "Percentages of the limit, of actual spend, at which to notify."
  type        = list(number)
  default     = [50, 80, 100]

  validation {
    condition     = length(var.thresholds_percent) > 0 && alltrue([for t in var.thresholds_percent : t > 0])
    error_message = "Thresholds must be a non-empty list of positive percentages."
  }
}
