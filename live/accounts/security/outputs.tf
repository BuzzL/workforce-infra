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

output "permission_set_names" {
  description = "Permission sets managed by this stack."
  value       = module.access.permission_set_names
}
