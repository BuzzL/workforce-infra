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

output "apply_role_name" {
  description = "Name of the apply role (not sensitive: the name holds no account ID)."
  value       = aws_iam_role.apply.name
}

output "plan_role_name" {
  description = "Name of the plan role."
  value       = aws_iam_role.plan.name
}

output "role_path" {
  description = "IAM path of both roles."
  value       = aws_iam_role.apply.path
}

output "plan_read_policy" {
  description = "The read policy of the plan role (JSON), so a stack's tests can assert what it passed in extra_read_statements."
  value       = aws_iam_role_policy.plan_baseline_read.policy
  sensitive   = true
}

output "oidc_provider_arn" {
  description = "ARN of the account's GitHub OIDC provider, for the roles a stack trusts to a GitHub Environment (modules/deploy-role). Sensitive: it holds the account ID."
  value       = aws_iam_openid_connect_provider.github.arn
  sensitive   = true
}

output "github_subject_prefix" {
  description = "The OIDC subject of the repository up to the environment (repo:<owner>@<id>/<repository>@<id>:environment), for the roles a stack trusts to one more GitHub Environment of the same repository. Public values, not AWS IDs."
  value       = local.github_sub_prefix
}
