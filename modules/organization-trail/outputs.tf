output "arn" {
  description = "ARN of the trail."
  value       = aws_cloudtrail.this.arn
}

output "name" {
  description = "Name of the trail."
  value       = aws_cloudtrail.this.name
}
