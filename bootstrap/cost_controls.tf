# What live/management needs for the cost controls of IAT-13 beyond the Organization budget:
# a budget per member account (named <key>-foundation-cost-budget, keys of
# scripts/environment-keys.tsv), Cost Anomaly Detection and the cost allocation tags.
# Budgets are scoped to those five names. Anomaly monitors and subscriptions are named by an ID
# AWS generates, so their ARNs can only be scoped to the account. Listing and activating cost
# allocation tags has no resource type in IAM, so those two actions take "*".
locals {
  account_budget_keys = ["scrt", "wrkf", "test", "qual", "demo"]
  account_budget_arns = [for k in local.account_budget_keys : "arn:aws:budgets::${data.aws_caller_identity.current.account_id}:budget/${k}-foundation-cost-budget"]

  anomaly_arns = [
    "arn:aws:ce::${data.aws_caller_identity.current.account_id}:anomalymonitor/*",
    "arn:aws:ce::${data.aws_caller_identity.current.account_id}:anomalysubscription/*",
  ]

  cost_controls_read_statements = [
    {
      Sid      = "ReadAccountBudgets"
      Effect   = "Allow"
      Action   = ["budgets:ViewBudget", "budgets:ListTagsForResource"]
      Resource = local.account_budget_arns
    },
    {
      Sid      = "ReadAnomalyDetection"
      Effect   = "Allow"
      Action   = ["ce:GetAnomalyMonitors", "ce:GetAnomalySubscriptions", "ce:ListTagsForResource"]
      Resource = local.anomaly_arns
    },
    {
      Sid      = "ReadCostAllocationTags"
      Effect   = "Allow"
      Action   = ["ce:ListCostAllocationTags"]
      Resource = ["*"]
    }
  ]
}

resource "aws_iam_role_policy" "cost_controls" {
  name = "cost-controls"
  role = aws_iam_role.github_infra_management.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(local.cost_controls_read_statements, [
      {
        Sid      = "ManageAccountBudgets"
        Effect   = "Allow"
        Action   = ["budgets:ModifyBudget", "budgets:TagResource", "budgets:UntagResource"]
        Resource = local.account_budget_arns
      },
      {
        Sid    = "ManageAnomalyDetection"
        Effect = "Allow"
        Action = [
          "ce:CreateAnomalyMonitor", "ce:UpdateAnomalyMonitor", "ce:DeleteAnomalyMonitor",
          "ce:CreateAnomalySubscription", "ce:UpdateAnomalySubscription", "ce:DeleteAnomalySubscription",
          "ce:TagResource", "ce:UntagResource",
        ]
        Resource = local.anomaly_arns
      },
      {
        Sid      = "ActivateCostAllocationTags"
        Effect   = "Allow"
        Action   = ["ce:UpdateCostAllocationTagsStatus"]
        Resource = ["*"]
      }
    ])
  })
}

resource "aws_iam_role_policy" "plan_cost_controls" {
  name = "plan-cost-controls"
  role = aws_iam_role.github_infra_management_plan.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.cost_controls_read_statements
  })
}
