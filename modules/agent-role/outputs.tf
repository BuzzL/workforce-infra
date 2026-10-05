output "arn" {
  description = "ARN of the agent role."
  value       = module.role.arn
}

output "name" {
  description = "Name of the agent role."
  value       = module.role.name
}

output "trust_policy" {
  description = "The trust policy document (JSON)."
  value       = module.role.trust_policy
  sensitive   = true
}

output "permissions_policy" {
  description = "The permissions policy document (JSON)."
  value       = module.role.permissions_policy
}
