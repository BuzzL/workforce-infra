variable "name" {
  description = "Role name, one of the platform names of docs/ENVIRONMENT_PERMISSIONS.md: <acct>-<project>-agent-role, -infra-role, -infra-plan-role, -github-role, -github-plan-role or <app>-deploy-role, <app>-exec-role."
  type        = string

  validation {
    condition     = can(regex("^(test|qual|demo|root|wrkf|scrt)-[a-z0-9]{1,10}-(agent-role|infra-role|infra-plan-role|github-role|github-plan-role|matrix-(test|quality|demo)-role|[a-z0-9]{1,16}-(deploy-role|exec-role))$", var.name))
    error_message = "The name must be a platform role name: <acct>-<project>-(agent-role|infra-role|infra-plan-role|github-role|github-plan-role|matrix-<env>-role|<app>-deploy-role|<app>-exec-role), the account being one of the keys test, qual, demo, root, wrkf, scrt."
  }
}

variable "path" {
  description = "IAM path. Platform roles live under /platform/, which the execution roles of the applications cannot reach."
  type        = string
  default     = "/platform/"

  validation {
    condition     = can(regex("^/([a-z0-9-]+/)+$", var.path))
    error_message = "The path must start and end with a slash and hold lowercase segments."
  }
}

variable "description" {
  description = "What the role is for and who assumes it."
  type        = string
}

variable "max_session_duration" {
  description = "Session length in seconds."
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "The session duration must be between 3600 and 43200 seconds."
  }
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary of the role. A boundary can lock a role out, so creating one needs the maintainer's approval (CLAUDE.md); this module only attaches it."
  type        = string
  default     = null
}

variable "trust" {
  description = <<-EOT
    Who may assume the role. Exactly one block, selected by mode, and nothing else is accepted:
    - assume_role: sts:AssumeRole by one role, by exact ARN, from one account, with an ExternalId
      (one value, two during a rotation) and optionally a session name pattern.
    - web_identity: sts:AssumeRoleWithWebIdentity by one OIDC subject, exact (no ExternalId exists there).
    - service: sts:AssumeRole by one AWS service, bound to one account and to a source ARN pattern.
  EOT
  type = object({
    mode = string
    assume_role = optional(object({
      principal_arn        = string
      source_account_id    = string
      external_ids         = list(string)
      session_name_pattern = optional(string)
      extra_principal_arns = optional(list(string), [])
    }))
    web_identity = optional(object({
      provider_arn = string
      subject      = string
      audience     = optional(string, "sts.amazonaws.com")
    }))
    service = optional(object({
      principal          = string
      source_account_id  = string
      source_arn_pattern = string
    }))
  })

  validation {
    condition = contains(["assume_role", "web_identity", "service"], var.trust.mode) && (
      (var.trust.mode == "assume_role" && var.trust.assume_role != null && var.trust.web_identity == null && var.trust.service == null) ||
      (var.trust.mode == "web_identity" && var.trust.web_identity != null && var.trust.assume_role == null && var.trust.service == null) ||
      (var.trust.mode == "service" && var.trust.service != null && var.trust.assume_role == null && var.trust.web_identity == null)
    )
    error_message = "trust.mode must be assume_role, web_identity or service, and only the block of that mode may be set."
  }

  # assume_role: the principal is one role (no root, no wildcard) in the declared source account.
  validation {
    condition = var.trust.assume_role == null || (
      can(regex("^arn:aws:iam::[0-9]{12}:role(/[A-Za-z0-9+=,.@_-]+)*/[A-Za-z0-9+=,.@_-]+$", var.trust.assume_role.principal_arn)) &&
      can(regex("^[0-9]{12}$", var.trust.assume_role.source_account_id)) &&
      can(regex(":iam::${var.trust.assume_role.source_account_id}:role/", var.trust.assume_role.principal_arn))
    )
    error_message = "trust.assume_role.principal_arn must be the exact ARN of one IAM role (no wildcard, not an account root) in the 12-digit trust.assume_role.source_account_id."
  }

  # Extra principals are exact roles of the same account, never duplicates of the first.
  validation {
    condition = var.trust.assume_role == null || (
      length(var.trust.assume_role.extra_principal_arns) <= 3 &&
      length(distinct(concat([var.trust.assume_role.principal_arn], var.trust.assume_role.extra_principal_arns))) == 1 + length(var.trust.assume_role.extra_principal_arns) &&
      alltrue([for a in var.trust.assume_role.extra_principal_arns :
        can(regex("^arn:aws:iam::[0-9]{12}:role(/[A-Za-z0-9+=,.@_-]+)*/[A-Za-z0-9+=,.@_-]+$", a)) &&
        can(regex(":iam::${var.trust.assume_role.source_account_id}:role/", a))
      ])
    )
    error_message = "trust.assume_role.extra_principal_arns holds at most three more exact role ARNs (no wildcard, not an account root, no duplicate) of trust.assume_role.source_account_id."
  }

  validation {
    condition = var.trust.assume_role == null || (
      length(var.trust.assume_role.external_ids) >= 1 && length(var.trust.assume_role.external_ids) <= 2 &&
      alltrue([for e in var.trust.assume_role.external_ids : can(regex("^[A-Za-z0-9_+=,.@:/-]{16,1000}$", e))])
    )
    error_message = "trust.assume_role.external_ids must hold one ExternalId, or two during a rotation, of 16 to 1000 characters from [A-Za-z0-9_+=,.@:/-] (no wildcard characters)."
  }

  validation {
    condition = var.trust.assume_role == null || try(var.trust.assume_role.session_name_pattern, null) == null || (
      can(regex("^[A-Za-z0-9_=,.@-]+-\\*$", var.trust.assume_role.session_name_pattern))
    )
    error_message = "trust.assume_role.session_name_pattern must be a fixed prefix followed by a single trailing wildcard, such as agent-*."
  }

  # web_identity: an exact subject, the provider of this account.
  validation {
    condition = var.trust.web_identity == null || (
      can(regex("^arn:aws:iam::[0-9]{12}:oidc-provider/[A-Za-z0-9.-]+$", var.trust.web_identity.provider_arn)) &&
      length(var.trust.web_identity.subject) > 0 &&
      !can(regex("[$*?]", var.trust.web_identity.subject)) &&
      !can(regex("[$*?]", var.trust.web_identity.audience))
    )
    error_message = "trust.web_identity needs an OIDC provider ARN, and a subject and audience without wildcards or policy variables ($)."
  }

  # service: one AWS service, bound to an account and to the ARN of what acts on its behalf.
  validation {
    condition = var.trust.service == null || (
      can(regex("^[a-z0-9-]+\\.amazonaws\\.com$", var.trust.service.principal)) &&
      can(regex("^[0-9]{12}$", var.trust.service.source_account_id)) &&
      can(regex("^arn:aws:[a-z0-9-]+:[a-z0-9-]*:[0-9]{12}:[^*?]", var.trust.service.source_arn_pattern)) &&
      can(regex("^arn:aws:[a-z0-9-]+:[a-z0-9-]*:${var.trust.service.source_account_id}:", var.trust.service.source_arn_pattern))
    )
    error_message = "trust.service needs a service principal (<name>.amazonaws.com), the 12-digit source account, and a source ARN pattern of that account whose resource part does not start with a wildcard."
  }
}

variable "statements" {
  description = <<-EOT
    The permission set, one inline policy. Each statement has an effect, its actions and its resources;
    there is deliberately no way to write NotAction or NotResource. Rules, checked here and asserted by the tests:
    - no action is "*" or "<service>:*" in an Allow;
    - a resource of exactly "*" in an Allow needs any_resource_reason (the exception of docs/ENVIRONMENT_PERMISSIONS.md,
      which the maintainer approves in review);
    - a Deny may carry a wildcard action only with a condition, and never has "*" as its only resource without one.
  EOT
  type = list(object({
    sid                 = string
    effect              = optional(string, "Allow")
    actions             = list(string)
    resources           = list(string)
    conditions          = optional(map(map(list(string))), {})
    any_resource_reason = optional(string)
  }))
  default = []

  validation {
    condition     = alltrue([for s in var.statements : contains(["Allow", "Deny"], s.effect)])
    error_message = "A statement effect must be Allow or Deny."
  }

  validation {
    condition     = alltrue([for s in var.statements : can(regex("^[A-Za-z0-9]+$", s.sid))])
    error_message = "A statement sid must be alphanumeric."
  }

  validation {
    condition = alltrue([for s in var.statements : length(s.actions) > 0 && length(s.resources) > 0 &&
    alltrue([for a in s.actions : can(regex("^[a-z0-9-]+:[A-Za-z0-9*]+$", a))])])
    error_message = "A statement needs actions of the form service:Action and at least one resource."
  }

  validation {
    condition     = alltrue([for s in var.statements : s.effect != "Allow" || !anytrue([for a in s.actions : can(regex("\\*", a))])])
    error_message = "An Allow cannot use a wildcard action: no \"*\", no \"<service>:*\", no prefix pattern."
  }

  validation {
    condition = alltrue([for s in var.statements : s.effect != "Deny" ||
      !anytrue([for a in s.actions : can(regex("\\*", a))]) || length(s.conditions) > 0
    ])
    error_message = "A Deny with a wildcard action must be narrowed by a condition."
  }

  validation {
    condition = alltrue([for s in var.statements : !contains(s.resources, "*") ||
      (s.effect == "Allow" && (s.any_resource_reason != null ? trimspace(s.any_resource_reason) != "" : false)) ||
      (s.effect == "Deny" && length(s.conditions) > 0)
    ])
    error_message = "Resource \"*\" is refused unless an Allow gives any_resource_reason or a Deny carries a condition."
  }
  # An Allow names its resources: an ARN of a service, with no wildcard in the service or account
  # segment and none at the start of the resource part (the bare "*" is the reasoned exception above).
  validation {
    condition = alltrue([for s in var.statements : s.effect != "Allow" || alltrue([
      for r in s.resources : r == "*" || can(regex("^arn:aws:[a-z0-9-]+:[a-z0-9-]*:([0-9]{12})?:[^*?]", r))
    ])])
    error_message = "An Allow resource must be an ARN with a fixed service and account (arn:aws:<service>:<region>:<account>:<resource>), whose resource part does not start with a wildcard, or \"*\" with any_resource_reason."
  }

  # A condition that selects nothing narrows nothing.
  validation {
    condition = alltrue([for s in var.statements : alltrue([
      for op, m in s.conditions : length(m) > 0 && alltrue([for k, v in m : length(v) > 0 && alltrue([for x in v : x != ""])])
    ])])
    error_message = "Every condition needs at least one key, and every key at least one non-empty value."
  }

  validation {
    condition     = length(distinct([for s in var.statements : s.sid])) == length(var.statements)
    error_message = "Statement sids must be unique."
  }
}

variable "tags" {
  description = "Tags applied to the role."
  type        = map(string)
  default     = {}
}
