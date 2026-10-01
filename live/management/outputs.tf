output "organizational_unit_ids" {
  description = "IDs of the top-level organizational units, by name."
  value       = { for name, ou in aws_organizations_organizational_unit.this : name => ou.id }
}
