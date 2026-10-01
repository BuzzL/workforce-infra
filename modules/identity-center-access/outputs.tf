output "permission_set_names" {
  description = "Names of the permission sets this module manages."
  value       = sort(keys(aws_ssoadmin_permission_set.this))
}

output "assignment_keys" {
  description = "Permission set / account pairs the maintainer is assigned to."
  value       = sort(keys(aws_ssoadmin_account_assignment.maintainer))
}
