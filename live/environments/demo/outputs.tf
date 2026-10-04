output "environment" {
  description = "Name and four-letter key of the environment this stack belongs to (scripts/environment-keys.tsv)."
  value       = { name = local.environment, key = local.key }
}
