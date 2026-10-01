# What live/management needs for its budget (modules/budget): read it, and manage it.
# Scoped to that one budget's ARN: the stack imports a budget that already exists, so its ARN
# is known before the call. The ARN carries the account ID, which is read from the caller.
locals {
  budget_arn = "arn:aws:budgets::${data.aws_caller_identity.current.account_id}:budget/${var.budget_name}"

  budget_read_statements = [
    {
      Sid      = "ReadBudget"
      Effect   = "Allow"
      Action   = ["budgets:ViewBudget", "budgets:ListTagsForResource"]
      Resource = [local.budget_arn]
    }
  ]
}

# ModifyBudget covers updating the budget and its notifications and subscribers. Deleting
# is part of it: the stack owns the budget, and the approval of the `management`
# environment is the guard.
resource "aws_iam_role_policy" "budget" {
  name = "budget"
  role = aws_iam_role.github_infra_management.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(local.budget_read_statements, [
      {
        Sid      = "ManageBudget"
        Effect   = "Allow"
        Action   = ["budgets:ModifyBudget", "budgets:TagResource", "budgets:UntagResource"]
        Resource = [local.budget_arn]
      }
    ])
  })
}

resource "aws_iam_role_policy" "plan_budget" {
  name = "plan-budget"
  role = aws_iam_role.github_infra_management_plan.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.budget_read_statements
  })
}
