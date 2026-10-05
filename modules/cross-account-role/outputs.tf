output "arn" {
  description = "ARN of the role."
  value       = aws_iam_role.this.arn
}

output "name" {
  description = "Name of the role."
  value       = aws_iam_role.this.name
}

output "trust_policy" {
  description = "The trust policy document (JSON), so a caller's tests can assert it literally."
  value       = aws_iam_role.this.assume_role_policy
}

output "permissions_policy" {
  description = "The permissions policy document (JSON), or null when the role has no statements."
  value       = one(aws_iam_role_policy.permissions[*].policy)
}
