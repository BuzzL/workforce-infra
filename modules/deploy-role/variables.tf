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

variable "application" {
  description = "The registered application this role deploys, one per role (docs/ENVIRONMENT_PERMISSIONS.md, table of applications)."
  type        = string
  default     = "testbed"

  validation {
    condition     = can(regex("^[a-z0-9]{1,16}$", var.application)) && !contains(["agent", "platform", "infra", "github"], var.application)
    error_message = "The application is one segment matching ^[a-z0-9]{1,16}$ and never a reserved name (agent, platform, infra, github)."
  }
}

variable "stacks" {
  description = "The stack qualifiers registered for the application (Stacks column). quality and demo allow exactly these stacks, test any stack of the application."
  type        = list(string)

  validation {
    condition = length(var.stacks) > 0 && alltrue([
      for q in var.stacks : can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", q)) && length("${var.application}-${q}") <= 39
    ])
    error_message = "Stacks are qualifiers of lowercase segments joined by hyphens, with <application>-<qualifier> at most 39 characters, and at least one is registered."
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
  description = "The environment account that holds the role and the resources it deploys."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "The account ID must be 12 digits."
  }
}

variable "oidc_provider_arn" {
  description = "The GitHub OIDC provider of this account (created by modules/account-ci-baseline)."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:oidc-provider/token\\.actions\\.githubusercontent\\.com$", var.oidc_provider_arn))
    error_message = "The provider must be the GitHub OIDC provider token.actions.githubusercontent.com of an account."
  }
}

variable "github_owner" {
  description = "GitHub owner (user or organization) of the application's repository."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,38}$", var.github_owner))
    error_message = "The owner must be a GitHub user or organization name."
  }
}

variable "github_owner_id" {
  description = "Numeric GitHub ID of the owner. Public, not an AWS ID. Needed for the immutable OIDC subject (owner@id/repo@id)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.github_owner_id))
    error_message = "The owner ID must be numeric."
  }
}

variable "github_repository" {
  description = "Name of the application's repository (without the owner), the only one allowed to assume the role."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$", var.github_repository))
    error_message = "The repository must be a plain GitHub repository name."
  }
}

variable "github_repository_id" {
  description = "Numeric GitHub ID of the repository (public), the second half of the immutable subject."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repository_id))
    error_message = "The repository ID must be numeric."
  }
}

variable "artifact_bucket" {
  description = "Bucket that holds the artifact built once in CI. A placeholder until the first deployable exists (docs/ENVIRONMENT_PERMISSIONS.md, open items)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,62}$", var.artifact_bucket))
    error_message = "The bucket must be a bucket name of lowercase letters, digits and hyphens (no dots, so the virtual-hosted template URL stays valid)."
  }
}

variable "artifact_prefix" {
  description = "Prefix of the application's artifacts in the bucket, without leading or trailing slash. Readable, and the only place a template may be loaded from."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$", var.artifact_prefix))
    error_message = "The prefix must be one or more path segments without wildcards, with no leading or trailing slash."
  }
}

variable "tags" {
  description = "Tags applied to the role."
  type        = map(string)
  default     = {}
}
