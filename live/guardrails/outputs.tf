output "attached" {
  description = "The SCPs attached by this stack, as OU name/policy name. No IDs."
  value       = { for key, _ in aws_organizations_policy_attachment.this : key => true }
}

output "policy_ids" {
  description = "IDs of the baseline SCPs, by name, for the detach commands of the rollout. Sensitive: the repository is public."
  value       = module.scp_baseline.policy_ids
  sensitive   = true
}
