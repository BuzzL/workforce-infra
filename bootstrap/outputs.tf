output "state_bucket_name" {
  description = "Name of the Terraform state bucket."
  value       = aws_s3_bucket.state.id
}

output "github_infra_management_role_arn" {
  description = "ARN of the github-infra-management role."
  value       = aws_iam_role.github_infra_management.arn
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider of this account."
  value       = aws_iam_openid_connect_provider.github.arn
}

output "github_infra_management_plan_role_arn" {
  description = "ARN of the github-infra-management-plan role."
  value       = aws_iam_role.github_infra_management_plan.arn
}

output "github_ci_role_arns" {
  description = "ARNs of the CI roles of workforce-github, by kind (apply, plan): the AWS_ROLE_ARN of its github and github-plan environments."
  value       = { for k, r in aws_iam_role.github_ci : k => r.arn }
}
