mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111122223333" # fake: the mock must not need a real account
    }
  }
}

variables {
  region            = "eu-west-1"
  state_bucket_name = "workforce-tfstate-a1b2c3d4"
}

# Values below are asserted literally on purpose: a change to any of them must be a
# visible, reviewed change to this file.

run "trust_policy_admits_only_the_management_environment" {
  command = apply

  assert {
    condition = jsondecode(aws_iam_role.github_infra_management.assume_role_policy) == {
      Version = "2012-10-17"
      Statement = [
        {
          Effect    = "Allow"
          Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
          Action    = "sts:AssumeRoleWithWebIdentity"
          Condition = {
            StringEquals = {
              "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
              "token.actions.githubusercontent.com:sub" = "repo:BuzzL@6116516/workforce-infra@1394667495:environment:management"
            }
          }
        }
      ]
    }
    error_message = "The trust policy must be one Allow of sts:AssumeRoleWithWebIdentity for the GitHub OIDC provider, with StringEquals on aud and on the exact immutable sub, and nothing else."
  }

  assert {
    condition     = aws_iam_role.github_infra_management.max_session_duration == 3600
    error_message = "Sessions must last one hour."
  }
}

run "role_permissions_are_exactly_the_documented_ones" {
  command = apply

  assert {
    condition = jsondecode(aws_iam_role_policy.state_access.policy) == {
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "ListStateBucket"
          Effect   = "Allow"
          Action   = ["s3:ListBucket"]
          Resource = ["arn:aws:s3:::workforce-tfstate-a1b2c3d4"]
        },
        {
          Sid      = "ReadBootstrapState"
          Effect   = "Allow"
          Action   = ["s3:GetObject"]
          Resource = ["arn:aws:s3:::workforce-tfstate-a1b2c3d4/bootstrap/terraform.tfstate"]
        },
        {
          Sid      = "ReadAndWriteManagementState"
          Effect   = "Allow"
          Action   = ["s3:GetObject", "s3:PutObject"]
          Resource = ["arn:aws:s3:::workforce-tfstate-a1b2c3d4/live/management/terraform.tfstate"]
        },
        {
          Sid      = "LockManagementState"
          Effect   = "Allow"
          Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
          Resource = ["arn:aws:s3:::workforce-tfstate-a1b2c3d4/live/management/terraform.tfstate.tflock"]
        },
        {
          Sid      = "LockBootstrapState"
          Effect   = "Allow"
          Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
          Resource = ["arn:aws:s3:::workforce-tfstate-a1b2c3d4/bootstrap/terraform.tfstate.tflock"]
        }
      ]
    }
    error_message = "State access must be list on the bucket, read of the bootstrap state, read and write of the live/management state, and lock/unlock of the two lockfiles only."
  }

  assert {
    condition = jsondecode(aws_iam_role_policy.plan_bootstrap.policy) == {
      Version = "2012-10-17"
      Statement = [
        {
          Sid    = "ReadStateBucketConfiguration"
          Effect = "Allow"
          Action = [
            "s3:GetAccelerateConfiguration",
            "s3:GetBucketAcl",
            "s3:GetBucketCORS",
            "s3:GetBucketLogging",
            "s3:GetBucketObjectLockConfiguration",
            "s3:GetBucketOwnershipControls",
            "s3:GetBucketPolicy",
            "s3:GetBucketPublicAccessBlock",
            "s3:GetBucketRequestPayment",
            "s3:GetBucketTagging",
            "s3:GetBucketVersioning",
            "s3:GetBucketWebsite",
            "s3:GetEncryptionConfiguration",
            "s3:GetLifecycleConfiguration",
            "s3:GetReplicationConfiguration",
            "s3:ListTagsForResource",
          ]
          Resource = ["arn:aws:s3:::workforce-tfstate-a1b2c3d4"]
        },
        {
          Sid    = "ReadGithubProviderAndRole"
          Effect = "Allow"
          Action = [
            "iam:GetOpenIDConnectProvider",
            "iam:GetRole",
            "iam:GetRolePolicy",
            "iam:ListAttachedRolePolicies",
            "iam:ListOpenIDConnectProviderTags",
            "iam:ListRolePolicies",
            "iam:ListRoleTags",
          ]
          Resource = [
            aws_iam_openid_connect_provider.github.arn,
            aws_iam_role.github_infra_management.arn,
            aws_iam_role.github_infra_management_plan.arn,
          ]
        },
        {
          Sid      = "ReadDelegatedAdministrators"
          Effect   = "Allow"
          Action   = ["organizations:ListDelegatedAdministrators"]
          Resource = "*"
        }
      ]
    }
    error_message = "The plan policy must be read-only on the state bucket configuration and on this stack's own provider and role, and nothing else."
  }
}

run "role_has_no_other_permissions" {
  command = apply

  # The exclusive resources make Terraform remove anything else attached to the role.
  assert {
    condition     = aws_iam_role_policies_exclusive.github_infra_management.policy_names == toset(["terraform-state", "plan-bootstrap-stack", "organization-units", "budget"])
    error_message = "Only the four documented inline policies may exist on the role."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachments_exclusive.github_infra_management.policy_arns) == 0
    error_message = "No managed policy may be attached to the role."
  }
}

run "plan_role_trust_admits_only_the_management_plan_environment" {
  command = apply

  assert {
    condition = jsondecode(aws_iam_role.github_infra_management_plan.assume_role_policy) == {
      Version = "2012-10-17"
      Statement = [
        {
          Effect    = "Allow"
          Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
          Action    = "sts:AssumeRoleWithWebIdentity"
          Condition = {
            StringEquals = {
              "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
              "token.actions.githubusercontent.com:sub" = "repo:BuzzL@6116516/workforce-infra@1394667495:environment:management-plan"
            }
          }
        }
      ]
    }
    error_message = "The plan role must be assumable only by the immutable subject of the management-plan environment."
  }

  assert {
    condition     = aws_iam_role.github_infra_management_plan.name == "github-infra-management-plan" && aws_iam_role.github_infra_management_plan.max_session_duration == 3600
    error_message = "The plan role must keep its documented name and a one-hour session."
  }
}

run "plan_role_is_read_only" {
  command = apply

  assert {
    condition = jsondecode(aws_iam_role_policy.plan_state_read.policy) == {
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "ListStateBucket"
          Effect   = "Allow"
          Action   = ["s3:ListBucket"]
          Resource = ["arn:aws:s3:::workforce-tfstate-a1b2c3d4"]
        },
        {
          Sid      = "ReadBootstrapState"
          Effect   = "Allow"
          Action   = ["s3:GetObject"]
          Resource = ["arn:aws:s3:::workforce-tfstate-a1b2c3d4/bootstrap/terraform.tfstate"]
        },
        {
          Sid      = "ReadManagementState"
          Effect   = "Allow"
          Action   = ["s3:GetObject"]
          Resource = ["arn:aws:s3:::workforce-tfstate-a1b2c3d4/live/management/terraform.tfstate"]
        }
      ]
    }
    error_message = "The plan role may only list the bucket and read the bootstrap and live/management states: no other stack, no lockfile, no writes."
  }

  # Every action of every policy of this role is a Get or a List.
  assert {
    condition = alltrue([
      for s in concat(
        jsondecode(aws_iam_role_policy.plan_state_read.policy).Statement,
        jsondecode(aws_iam_role_policy.plan_bootstrap_read.policy).Statement,
        jsondecode(aws_iam_role_policy.plan_organization_units.policy).Statement,
        jsondecode(aws_iam_role_policy.plan_budget.policy).Statement,
        ) : alltrue([
          for a in flatten([s.Action]) : can(regex("^((s3|iam|organizations):(Get|List|Describe)[A-Za-z]*|budgets:(ViewBudget|ListTagsForResource))$", a))
      ])
    ])
    error_message = "The plan role may only have S3, IAM and Organizations Get, List and Describe actions and the two read actions on its budget, and exactly the documented ones (see the literals above and below)."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.plan_bootstrap_read.policy) == jsondecode(aws_iam_role_policy.plan_bootstrap.policy)
    error_message = "Both roles must read exactly the same bootstrap resources, in the same policy document."
  }

  # Each policy is attached to the role it is written for.
  assert {
    condition = (
      aws_iam_role_policy.plan_state_read.role == aws_iam_role.github_infra_management_plan.id &&
      aws_iam_role_policy.plan_bootstrap_read.role == aws_iam_role.github_infra_management_plan.id &&
      aws_iam_role_policy.state_access.role == aws_iam_role.github_infra_management.id &&
      aws_iam_role_policy.plan_bootstrap.role == aws_iam_role.github_infra_management.id &&
      aws_iam_role_policy.organization_units.role == aws_iam_role.github_infra_management.id &&
      aws_iam_role_policy.plan_organization_units.role == aws_iam_role.github_infra_management_plan.id &&
      aws_iam_role_policy.budget.role == aws_iam_role.github_infra_management.id &&
      aws_iam_role_policy.plan_budget.role == aws_iam_role.github_infra_management_plan.id
    )
    error_message = "Every inline policy must be attached to its own role."
  }

  assert {
    condition = (
      aws_iam_role_policies_exclusive.github_infra_management_plan.role_name == "github-infra-management-plan" &&
      aws_iam_role_policy_attachments_exclusive.github_infra_management_plan.role_name == "github-infra-management-plan" &&
      aws_iam_role_policies_exclusive.github_infra_management.role_name == "github-infra-management" &&
      aws_iam_role_policy_attachments_exclusive.github_infra_management.role_name == "github-infra-management"
    )
    error_message = "The exclusive resources must manage the role they are named after."
  }

  assert {
    condition = (
      aws_iam_role.github_infra_management_plan.permissions_boundary == null &&
      (aws_iam_role.github_infra_management_plan.path == null || aws_iam_role.github_infra_management_plan.path == "/") &&
      output.github_infra_management_plan_role_arn == aws_iam_role.github_infra_management_plan.arn &&
      output.github_infra_management_role_arn == aws_iam_role.github_infra_management.arn
    )
    error_message = "The plan role has the default path and no boundary, and each output is the ARN of its own role."
  }

  assert {
    condition     = aws_iam_role_policies_exclusive.github_infra_management_plan.policy_names == toset(["terraform-state-read", "plan-bootstrap-stack", "plan-organization-units", "plan-budget"])
    error_message = "Only the four documented inline policies may exist on the plan role."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachments_exclusive.github_infra_management_plan.policy_arns) == 0
    error_message = "No managed policy may be attached to the plan role."
  }
}

run "organization_permissions_are_exactly_the_documented_ones" {
  command = apply

  assert {
    condition = jsondecode(aws_iam_role_policy.organization_units.policy) == {
      Version = "2012-10-17"
      Statement = [
        {
          Sid    = "ReadOrganizationalUnitsAndAccounts"
          Effect = "Allow"
          Action = [
            "organizations:DescribeAccount",
            "organizations:DescribeOrganizationalUnit",
            "organizations:ListAccountsForParent",
            "organizations:ListOrganizationalUnitsForParent",
            "organizations:ListParents",
            "organizations:ListTagsForResource",
          ]
          Resource = ["arn:aws:organizations::111122223333:root/o-*/r-*", "arn:aws:organizations::111122223333:ou/o-*/ou-*", "arn:aws:organizations::111122223333:account/o-*/*"]
        },
        {
          Sid    = "ManageOrganizationalUnits"
          Effect = "Allow"
          Action = [
            "organizations:CreateOrganizationalUnit",
            "organizations:UpdateOrganizationalUnit",
            "organizations:DeleteOrganizationalUnit",
            "organizations:TagResource",
            "organizations:UntagResource",
          ]
          Resource = ["arn:aws:organizations::111122223333:root/o-*/r-*", "arn:aws:organizations::111122223333:ou/o-*/ou-*"]
        }
      ]
    }
    error_message = "The management role may read the Organization and its accounts and manage organizational units of this account's Organization, and nothing else in Organizations."
  }

  # Account creation is irreversible and applied locally (IAT-31): CI can only read accounts.
  assert {
    condition = !anytrue([
      for s in jsondecode(aws_iam_role_policy.organization_units.policy).Statement :
      anytrue([for a in flatten([s.Action]) : contains(["organizations:CreateAccount", "organizations:CreateGovCloudAccount", "organizations:MoveAccount", "organizations:CloseAccount", "organizations:RemoveAccountFromOrganization", "organizations:InviteAccountToOrganization"], a)])
    ])
    error_message = "The management role must not be able to create, move or close accounts."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.plan_organization_units.policy).Statement == slice(jsondecode(aws_iam_role_policy.organization_units.policy).Statement, 0, 1)
    error_message = "The plan role must have exactly the read statements of the management role, without the write statement."
  }
}

run "budget_permissions_are_exactly_the_documented_ones" {
  command = apply

  assert {
    condition = jsondecode(aws_iam_role_policy.budget.policy) == {
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "ReadBudget"
          Effect   = "Allow"
          Action   = ["budgets:ViewBudget", "budgets:ListTagsForResource"]
          Resource = ["arn:aws:budgets::111122223333:budget/Workforce Budget"]
        },
        {
          Sid      = "ManageBudget"
          Effect   = "Allow"
          Action   = ["budgets:ModifyBudget", "budgets:TagResource", "budgets:UntagResource"]
          Resource = ["arn:aws:budgets::111122223333:budget/Workforce Budget"]
        }
      ]
    }
    error_message = "The management role may read and manage the one budget of the stack, and nothing else in Budgets."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.plan_budget.policy).Statement == slice(jsondecode(aws_iam_role_policy.budget.policy).Statement, 0, 1)
    error_message = "The plan role must have exactly the read statement of the management role, without the write statement."
  }
}

run "state_bucket_is_protected" {
  command = apply

  assert {
    condition     = aws_s3_bucket.state.bucket == "workforce-tfstate-a1b2c3d4" && !aws_s3_bucket.state.force_destroy
    error_message = "The bucket must use the given name and must not be force-destroyable."
  }

  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning must be enabled."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.state.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    error_message = "The bucket must be encrypted at rest."
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.state.block_public_acls,
      aws_s3_bucket_public_access_block.state.block_public_policy,
      aws_s3_bucket_public_access_block.state.ignore_public_acls,
      aws_s3_bucket_public_access_block.state.restrict_public_buckets,
    ])
    error_message = "All four public access blocks must be on."
  }

  assert {
    condition     = one(aws_s3_bucket_ownership_controls.state.rule).object_ownership == "BucketOwnerEnforced"
    error_message = "ACLs must be disabled."
  }

  # The one Deny that legitimately uses * for principal and action: it restricts access.
  assert {
    condition = jsondecode(aws_s3_bucket_policy.state.policy) == {
      Version = "2012-10-17"
      Statement = [
        {
          Sid       = "DenyInsecureTransport"
          Effect    = "Deny"
          Principal = { AWS = "*" }
          Action    = "s3:*"
          Resource  = ["arn:aws:s3:::workforce-tfstate-a1b2c3d4", "arn:aws:s3:::workforce-tfstate-a1b2c3d4/*"]
          Condition = { Bool = { "aws:SecureTransport" = "false" } }
        }
      ]
    }
    error_message = "The bucket policy must be exactly one TLS-only Deny, for everyone and every action, on the bucket and its objects."
  }
}

run "old_state_versions_are_kept_for_recovery" {
  command = apply

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.state.rule) == 1
    error_message = "There must be exactly one lifecycle rule."
  }

  assert {
    condition = (
      one(aws_s3_bucket_lifecycle_configuration.state.rule).status == "Enabled" &&
      one(one(aws_s3_bucket_lifecycle_configuration.state.rule).noncurrent_version_expiration).noncurrent_days == 90 &&
      one(one(aws_s3_bucket_lifecycle_configuration.state.rule).noncurrent_version_expiration).newer_noncurrent_versions == 10 &&
      one(one(aws_s3_bucket_lifecycle_configuration.state.rule).abort_incomplete_multipart_upload).days_after_initiation == 7
    )
    error_message = "Old versions must expire only after 90 days, the newest 10 must be kept and incomplete uploads aborted after 7 days."
  }

  # The live state and its old versions must never expire or move to another storage class.
  assert {
    condition = (
      length(one(aws_s3_bucket_lifecycle_configuration.state.rule).expiration) == 0 &&
      length(one(aws_s3_bucket_lifecycle_configuration.state.rule).transition) == 0 &&
      length(one(aws_s3_bucket_lifecycle_configuration.state.rule).noncurrent_version_transition) == 0
    )
    error_message = "The lifecycle rule must not expire current versions or transition any version."
  }
}

run "no_wildcards_in_any_allow" {
  command = apply

  # Only Allow statements are checked: the TLS-only Deny above legitimately uses a
  # wildcard principal and action, because it restricts access instead of granting it.
  assert {
    condition = alltrue([
      for s in concat(
        jsondecode(aws_iam_role.github_infra_management.assume_role_policy).Statement,
        jsondecode(aws_iam_role_policy.state_access.policy).Statement,
        jsondecode(aws_iam_role_policy.plan_bootstrap.policy).Statement,
        jsondecode(aws_iam_role.github_infra_management_plan.assume_role_policy).Statement,
        jsondecode(aws_iam_role_policy.plan_state_read.policy).Statement,
        jsondecode(aws_iam_role_policy.plan_bootstrap_read.policy).Statement,
        jsondecode(aws_iam_role_policy.organization_units.policy).Statement,
        jsondecode(aws_iam_role_policy.plan_organization_units.policy).Statement,
        jsondecode(aws_iam_role_policy.budget.policy).Statement,
        jsondecode(aws_iam_role_policy.plan_budget.policy).Statement,
        ) : (
        s.Effect == "Allow" &&
        !anytrue([for a in flatten([s.Action]) : a == "*" || endswith(a, ":*")]) &&
        (s.Sid == "ReadDelegatedAdministrators" || !anytrue([for r in flatten([try(s.Resource, [])]) : r == "*"])) &&
        !contains(flatten([for p in values(try(s.Principal, {})) : p]), "*")
      )
    ])
    error_message = "Allow statements must not use * as principal, action or resource (the one resourceless read ReadDelegatedAdministrators is asserted literally above)."
  }
}

run "role_and_provider_are_named_as_documented" {
  command = apply

  assert {
    condition     = aws_iam_role.github_infra_management.name == "github-infra-management"
    error_message = "The role name is the one documented in docs/BOOTSTRAP.md."
  }

  assert {
    condition     = aws_iam_openid_connect_provider.github.url == "https://token.actions.githubusercontent.com" && aws_iam_openid_connect_provider.github.client_id_list == toset(["sts.amazonaws.com"])
    error_message = "The provider must trust GitHub Actions with the sts.amazonaws.com audience only."
  }
}

run "bucket_name_with_an_account_id_is_rejected" {
  command = plan

  variables {
    state_bucket_name = "workforce-tfstate-123456789012"
  }

  expect_failures = [var.state_bucket_name]
}

run "bucket_name_with_uppercase_is_rejected" {
  command = plan

  variables {
    state_bucket_name = "Workforce-State"
  }

  expect_failures = [var.state_bucket_name]
}

run "bucket_name_longer_than_63_characters_is_rejected" {
  command = plan

  variables {
    state_bucket_name = "workforce-tfstate-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  }

  expect_failures = [var.state_bucket_name]
}

# Member accounts with a CI baseline. The IDs are fake; the real ones are never committed.
run "member_roles_reach_only_their_own_state" {
  command = apply

  variables {
    member_account_ids = { security = "111122223333" }
  }

  assert {
    condition = jsondecode(aws_s3_bucket_policy.state.policy).Statement == [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = { AWS = "*" }
        Action    = "s3:*"
        Resource  = ["arn:aws:s3:::workforce-tfstate-a1b2c3d4", "arn:aws:s3:::workforce-tfstate-a1b2c3d4/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Sid       = "ListSecurityState"
        Effect    = "Allow"
        Principal = { AWS = ["arn:aws:iam::111122223333:role/github-infra-security", "arn:aws:iam::111122223333:role/github-infra-security-plan"] }
        Action    = "s3:ListBucket"
        Resource  = "arn:aws:s3:::workforce-tfstate-a1b2c3d4"
        Condition = { StringEquals = { "s3:prefix" = ["env:/", "live/accounts/security/terraform.tfstate", "live/accounts/security/terraform.tfstate.tflock"] } }
      },
      {
        Sid       = "ReadAndWriteSecurityState"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::111122223333:role/github-infra-security" }
        Action    = ["s3:GetObject", "s3:PutObject"]
        Resource  = "arn:aws:s3:::workforce-tfstate-a1b2c3d4/live/accounts/security/terraform.tfstate"
      },
      {
        Sid       = "LockSecurityState"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::111122223333:role/github-infra-security" }
        Action    = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource  = "arn:aws:s3:::workforce-tfstate-a1b2c3d4/live/accounts/security/terraform.tfstate.tflock"
      },
      {
        Sid       = "ReadSecurityStateForPlans"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::111122223333:role/github-infra-security-plan" }
        Action    = "s3:GetObject"
        Resource  = "arn:aws:s3:::workforce-tfstate-a1b2c3d4/live/accounts/security/terraform.tfstate"
      },
    ]
    error_message = "A member's roles must be named exactly and reach only their own state key, the plan role without write or lock."
  }

  # No wildcard in any Allow of the bucket policy: the only * is in the TLS Deny.
  assert {
    condition = alltrue([
      for s in jsondecode(aws_s3_bucket_policy.state.policy).Statement : (
        s.Effect == "Deny" || (
          !strcontains(jsonencode(s.Principal), "*") && !strcontains(jsonencode(s.Resource), "*") && !strcontains(jsonencode(s.Action), "*")
        )
      )
    ])
    error_message = "An Allow in the bucket policy uses a wildcard principal, action or resource."
  }
}

run "management_role_may_bootstrap_listed_accounts_only" {
  command = apply

  variables {
    member_account_ids = { workforce = "444455556666", security = "111122223333" }
  }

  assert {
    condition = jsondecode(aws_iam_role_policy.break_glass_bootstrap[0].policy) == {
      Version = "2012-10-17"
      Statement = [{
        Sid       = "BootstrapMemberAccounts"
        Effect    = "Allow"
        Action    = "sts:AssumeRole"
        Resource  = ["arn:aws:iam::111122223333:role/OrganizationAccountAccessRole", "arn:aws:iam::444455556666:role/OrganizationAccountAccessRole"]
        Condition = { StringEquals = { "sts:RoleSessionName" = "baseline-bootstrap" } }
      }]
    }
    error_message = "The CI role may assume OrganizationAccountAccessRole only in the listed accounts and only as baseline-bootstrap."
  }

  assert {
    condition     = aws_iam_role_policies_exclusive.github_infra_management.policy_names == toset(["terraform-state", "plan-bootstrap-stack", "organization-units", "budget", "break-glass-bootstrap"])
    error_message = "The break-glass policy must be the last inline policy."
  }
}

run "no_member_accounts_means_no_break_glass_permission" {
  command = apply

  assert {
    condition     = length(aws_iam_role_policy.break_glass_bootstrap) == 0
    error_message = "Without member accounts the CI role must not be able to assume anything in them."
  }
}

run "member_account_ids_are_validated" {
  command = plan

  variables {
    member_account_ids = { management = "111122223333" }
  }

  expect_failures = [var.member_account_ids]
}

# Identity Center is administered from the security account (IAT-33). The registration is
# applied locally with SSO admin, never by CI, so no CI role can change who administers access.
run "identity_center_is_delegated_to_security_only_once_it_is_listed" {
  command = apply

  variables {
    member_account_ids = { security = "111122223333", workforce = "444455556666" }
  }

  assert {
    condition     = aws_organizations_delegated_administrator.identity_center[0].service_principal == "sso.amazonaws.com" && aws_organizations_delegated_administrator.identity_center[0].account_id == "111122223333"
    error_message = "Identity Center must be delegated to the security account, and to no other account."
  }

  assert {
    condition     = length(aws_organizations_delegated_administrator.identity_center) == 1
    error_message = "Exactly one delegated administrator."
  }
}

run "no_security_account_means_no_delegation" {
  command = apply

  variables {
    member_account_ids = { workforce = "444455556666" }
  }

  assert {
    condition     = length(aws_organizations_delegated_administrator.identity_center) == 0
    error_message = "Nothing is delegated until the security account is listed."
  }
}

run "ci_roles_cannot_register_delegated_administrators" {
  command = apply

  assert {
    condition = !anytrue([
      for p in [aws_iam_role_policy.organization_units.policy, aws_iam_role_policy.plan_organization_units.policy, aws_iam_role_policy.plan_bootstrap.policy, aws_iam_role_policy.plan_bootstrap_read.policy] :
      anytrue([for s in jsondecode(p).Statement : anytrue([for a in flatten([s.Action]) : contains(["organizations:RegisterDelegatedAdministrator", "organizations:DeregisterDelegatedAdministrator", "organizations:EnableAWSServiceAccess", "organizations:DisableAWSServiceAccess"], a)])])
    ])
    error_message = "A CI role must not be able to change who administers Identity Center."
  }
}
