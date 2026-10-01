output "organizational_unit_ids" {
  description = "IDs of the top-level organizational units, by name."
  value       = { for name, ou in aws_organizations_organizational_unit.this : name => ou.id }
}

output "account_ids" {
  description = "IDs of the member accounts, by name. Sensitive: the repository is public."
  value       = { for name, account in aws_organizations_account.this : name => account.id }
  sensitive   = true
}
