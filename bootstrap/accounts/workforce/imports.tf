# One-time move of the baseline out of live/accounts/workforce, where it used to live (the
# matching `removed` block is there). The resources already exist in the account: these blocks
# adopt them into this stack's state, and the plan must read "N to import, 0 to add, 0 to
# destroy". After the first apply they have no effect; a later change removes this file.
locals {
  import_account_id = data.aws_caller_identity.current.account_id
}

import {
  to = module.baseline.aws_iam_openid_connect_provider.github
  id = "arn:aws:iam::${local.import_account_id}:oidc-provider/token.actions.githubusercontent.com"
}

import {
  to = module.baseline.aws_iam_role.apply
  id = "github-infra-workforce"
}

import {
  to = module.baseline.aws_iam_role.plan
  id = "github-infra-workforce-plan"
}

import {
  to = module.baseline.aws_iam_role_policy.apply_state
  id = "github-infra-workforce:terraform-state"
}

import {
  to = module.baseline.aws_iam_role_policy.apply_baseline_read
  id = "github-infra-workforce:baseline-read"
}

import {
  to = module.baseline.aws_iam_role_policy.plan_state_read
  id = "github-infra-workforce-plan:terraform-state-read"
}

import {
  to = module.baseline.aws_iam_role_policy.plan_baseline_read
  id = "github-infra-workforce-plan:baseline-read"
}

import {
  to = module.baseline.aws_iam_role_policies_exclusive.apply
  id = "github-infra-workforce"
}

import {
  to = module.baseline.aws_iam_role_policies_exclusive.plan
  id = "github-infra-workforce-plan"
}

import {
  to = module.baseline.aws_iam_role_policy_attachments_exclusive.apply
  id = "github-infra-workforce"
}

import {
  to = module.baseline.aws_iam_role_policy_attachments_exclusive.plan
  id = "github-infra-workforce-plan"
}
