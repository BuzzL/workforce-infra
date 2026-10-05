output "apply_role_arn" {
  description = "ARN of the apply role: the GitHub Environment secret AWS_ROLE_ARN. Sensitive: public repository."
  value       = module.baseline.apply_role_arn
  sensitive   = true
}

output "plan_role_arn" {
  description = "ARN of the plan role: the secret AWS_ROLE_ARN of the -plan environment."
  value       = module.baseline.plan_role_arn
  sensitive   = true
}

output "apply_role_id" {
  description = "Unique ID of the apply role: the secret AWS_ROLE_ID, registered so CI masks it."
  value       = module.baseline.apply_role_id
  sensitive   = true
}

output "plan_role_id" {
  description = "Unique ID of the plan role: the secret AWS_ROLE_ID of the -plan environment."
  value       = module.baseline.plan_role_id
  sensitive   = true
}

output "agent_role_arn" {
  description = "ARN of the agent task role: the principal of the agent roles in the environment accounts (scripts/set-agent-role-vars.sh). Sensitive: public repository."
  value       = module.agent_role.arn
  sensitive   = true
}

output "matrix_role_arns" {
  description = "ARN of the matrix runner role of each environment, or empty while var.matrix is unset: the secret MATRIX_RUNNER_ROLE_ARN of the <environment>-matrix GitHub Environment, and extra_principal_arns of the agent role of that environment (scripts/set-agent-role-vars.sh). Sensitive: public repository."
  value       = { for env, m in module.matrix_role : env => m.arn }
  sensitive   = true
}
