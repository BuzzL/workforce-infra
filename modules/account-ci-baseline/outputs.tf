output "apply_role_arn" {
  description = "ARN of the apply role. Sensitive: the repository is public and the ARN holds the account ID."
  value       = aws_iam_role.apply.arn
  sensitive   = true
}

output "plan_role_arn" {
  description = "ARN of the read-only plan role. Sensitive for the same reason."
  value       = aws_iam_role.plan.arn
  sensitive   = true
}

output "apply_role_id" {
  description = "Unique ID of the apply role (AROA...), registered as a secret only so CI masks it in logs."
  value       = aws_iam_role.apply.unique_id
  sensitive   = true
}

output "plan_role_id" {
  description = "Unique ID of the plan role (AROA...), registered as a secret only so CI masks it in logs."
  value       = aws_iam_role.plan.unique_id
  sensitive   = true
}
