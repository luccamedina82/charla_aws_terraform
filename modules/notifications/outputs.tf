output "topic_arn" {
  description = "ARN del topic SNS. Lo consume cicd (CodeStar Notifications)."
  value       = aws_sns_topic.this.arn
}

output "topic_name" {
  description = "Nombre del topic SNS."
  value       = aws_sns_topic.this.name
}
