mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
}

variables {
  account_name      = "workforce"
  state_bucket_name = "workforce-tfstate-a1b2c3d4"
  state_key         = "live/accounts/workforce/terraform.tfstate"
}

run "no_wildcards_in_allow" {
  command = apply

  # No * action, no service:* action, no * principal, no NotAction/NotPrincipal/NotResource,
  # and no * in a resource, in any policy of either role.
  assert {
    condition = alltrue([
      for p in [
        aws_iam_role_policy.apply_state.policy,
        aws_iam_role_policy.apply_baseline_read.policy,
        aws_iam_role_policy.plan_state_read.policy,
        aws_iam_role_policy.plan_baseline_read.policy,
        aws_iam_role.apply.assume_role_policy,
        aws_iam_role.plan.assume_role_policy,
        ] : alltrue([
          for s in jsondecode(p).Statement : s.Effect == "Allow"
          && !contains(keys(s), "NotAction") && !contains(keys(s), "NotResource") && !contains(keys(s), "NotPrincipal")
          && alltrue([for a in try(tolist(s.Action), [s.Action]) : !strcontains(a, "*")])
          && alltrue([for r in try(tolist(s.Resource), []) : !strcontains(r, "*")])
      ])
    ])
    error_message = "An Allow uses a wildcard action or resource, or a Not* element."
  }
}

run "apply_role_permissions" {
  command = apply

  assert {
    condition = jsondecode(aws_iam_role_policy.apply_state.policy).Statement == [
      {
        Sid       = "ListStateBucket"
        Effect    = "Allow"
        Action    = ["s3:ListBucket"]
        Resource  = ["arn:aws:s3:::workforce-tfstate-a1b2c3d4"]
        Condition = { StringEquals = { "s3:prefix" = ["env:/", "live/accounts/workforce/terraform.tfstate", "live/accounts/workforce/terraform.tfstate.tflock"] } }
      },
      {
        Sid      = "ReadAndWriteState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = ["arn:aws:s3:::workforce-tfstate-a1b2c3d4/live/accounts/workforce/terraform.tfstate"]
      },
      {
        Sid      = "LockState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["arn:aws:s3:::workforce-tfstate-a1b2c3d4/live/accounts/workforce/terraform.tfstate.tflock"]
      },
    ]
    error_message = "The apply role must reach only its own state key and lockfile."
  }

  assert {
    condition     = length(regexall("iam:(Create|Put|Update|Delete|Attach|Detach)", aws_iam_role_policy.apply_baseline_read.policy)) == 0
    error_message = "The apply role must not change IAM: the baseline is changed through break-glass only."
  }
}

run "plan_role_is_read_only" {
  command = apply

  assert {
    condition = jsondecode(aws_iam_role_policy.plan_state_read.policy).Statement == [
      {
        Sid       = "ListStateBucket"
        Effect    = "Allow"
        Action    = ["s3:ListBucket"]
        Resource  = ["arn:aws:s3:::workforce-tfstate-a1b2c3d4"]
        Condition = { StringEquals = { "s3:prefix" = ["env:/", "live/accounts/workforce/terraform.tfstate"] } }
      },
      {
        Sid      = "ReadState"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["arn:aws:s3:::workforce-tfstate-a1b2c3d4/live/accounts/workforce/terraform.tfstate"]
      },
    ]
    error_message = "The plan role must only read its own state object: no lockfile, no writes."
  }

  assert {
    condition = alltrue([
      for p in [aws_iam_role_policy.plan_state_read.policy, aws_iam_role_policy.plan_baseline_read.policy] :
      length(regexall(":(Put|Delete|Create|Update|Attach|Detach)", p)) == 0
    ])
    error_message = "The plan role must have no write action."
  }
}

run "baseline_read_includes_tag_reads" {
  command = apply

  # The resources carry tags, so refreshing them reads the tags too (as in bootstrap/).
  assert {
    condition = alltrue([
      for p in [aws_iam_role_policy.apply_baseline_read.policy, aws_iam_role_policy.plan_baseline_read.policy] :
      strcontains(p, "iam:ListRoleTags") && strcontains(p, "iam:ListOpenIDConnectProviderTags")
    ])
    error_message = "Both roles must be able to read the tags of the provider and the roles they refresh."
  }
}

run "baseline_read_scope" {
  command = apply

  assert {
    condition = [for s in jsondecode(aws_iam_role_policy.apply_baseline_read.policy).Statement : s.Resource] == [
      [aws_iam_openid_connect_provider.github.arn],
      ["arn:aws:iam::111122223333:role/github-infra-workforce", "arn:aws:iam::111122223333:role/github-infra-workforce-plan"],
    ]
    error_message = "The baseline reads must name exactly the provider and the two roles."
  }
}

run "extra_read_statements_reach_both_roles" {
  command = apply

  variables {
    extra_read_statements = [{
      Sid      = "ReadSomethingElse"
      Effect   = "Allow"
      Action   = ["sso:ListInstances"]
      Resource = ["*"]
    }]
  }

  assert {
    condition = alltrue([
      for p in [aws_iam_role_policy.apply_baseline_read.policy, aws_iam_role_policy.plan_baseline_read.policy] :
      contains([for s in jsondecode(p).Statement : s.Sid], "ReadSomethingElse")
    ])
    error_message = "Extra read statements must be in the read policy of both the apply and the plan role."
  }

  assert {
    condition     = length(jsondecode(aws_iam_role_policy.plan_baseline_read.policy).Statement) == 3
    error_message = "The two baseline statements must stay, with the extra one added."
  }
}

# The baseline of an account has a stack of its own, applied locally. Only the plan role may read
# its state, so that the plan of that stack runs in CI; the apply role never reaches it.
run "baseline_state_is_read_by_both_roles_and_written_by_neither" {
  command = apply

  variables {
    baseline_state_key = "bootstrap/accounts/workforce/terraform.tfstate"
  }

  assert {
    condition = jsondecode(aws_iam_role_policy.plan_state_read.policy).Statement == [
      {
        Sid       = "ListStateBucket"
        Effect    = "Allow"
        Action    = ["s3:ListBucket"]
        Resource  = ["arn:aws:s3:::workforce-tfstate-a1b2c3d4"]
        Condition = { StringEquals = { "s3:prefix" = ["env:/", "live/accounts/workforce/terraform.tfstate", "bootstrap/accounts/workforce/terraform.tfstate"] } }
      },
      {
        Sid      = "ReadState"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["arn:aws:s3:::workforce-tfstate-a1b2c3d4/live/accounts/workforce/terraform.tfstate"]
      },
      {
        Sid      = "ReadBaselineState"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["arn:aws:s3:::workforce-tfstate-a1b2c3d4/bootstrap/accounts/workforce/terraform.tfstate"]
      },
    ]
    error_message = "The plan role must read the baseline state, with no write and no lock."
  }

  assert {
    condition = jsondecode(aws_iam_role_policy.apply_state.policy).Statement == [
      {
        Sid       = "ListStateBucket"
        Effect    = "Allow"
        Action    = ["s3:ListBucket"]
        Resource  = ["arn:aws:s3:::workforce-tfstate-a1b2c3d4"]
        Condition = { StringEquals = { "s3:prefix" = ["env:/", "live/accounts/workforce/terraform.tfstate", "live/accounts/workforce/terraform.tfstate.tflock", "bootstrap/accounts/workforce/terraform.tfstate", "bootstrap/accounts/workforce/terraform.tfstate.tflock"] } }
      },
      {
        Sid      = "ReadAndWriteState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = ["arn:aws:s3:::workforce-tfstate-a1b2c3d4/live/accounts/workforce/terraform.tfstate"]
      },
      {
        Sid      = "LockState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["arn:aws:s3:::workforce-tfstate-a1b2c3d4/live/accounts/workforce/terraform.tfstate.tflock"]
      },
      {
        Sid      = "ReadBaselineState"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["arn:aws:s3:::workforce-tfstate-a1b2c3d4/bootstrap/accounts/workforce/terraform.tfstate"]
      },
      {
        Sid      = "LockBaselineState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["arn:aws:s3:::workforce-tfstate-a1b2c3d4/bootstrap/accounts/workforce/terraform.tfstate.tflock"]
      },
    ]
    error_message = "The apply role may read and lock the baseline state, to plan it after a merge, and must never write the state object: CI cannot change its own role."
  }
}
