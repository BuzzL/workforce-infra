output "policy_ids" {
  description = "IDs of the SCPs, by name. Nothing is attached by this module."
  value       = { for name, p in aws_organizations_policy.this : name => p.id }
}
