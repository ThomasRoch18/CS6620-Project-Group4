# SQS Queue URLs

output "sast_queue_url" {
  value = aws_sqs_queue.sast.url
}

output "pentest_queue_url" {
  value = aws_sqs_queue.pentest.url
}

# SQS Queue ARNs

output "sast_queue_arn" {
  value = aws_sqs_queue.sast.arn
}

output "pentest_queue_arn" {
  value = aws_sqs_queue.pentest.arn
}

# SNS Topic ARN

output "scan_notifications_topic_arn" {
  value = aws_sns_topic.scan_notifications.arn
}

# ECR Repository URLs

output "sast_ecr_repository_url" {
  value = aws_ecr_repository.sast.repository_url
}

output "pentest_ecr_repository_url" {
  value = aws_ecr_repository.pentest.repository_url
}

# ECS Cluster

output "pentest_ecs_cluster_arn" {
  value = aws_ecs_cluster.pentest.arn
}

# VPC Endpoint Outputs

output "s3_vpc_endpoint_id" {
  description = "S3 gateway endpoint ID"
  value       = aws_vpc_endpoint.s3.id
}

output "dynamodb_vpc_endpoint_id" {
  description = "DynamoDB gateway endpoint ID"
  value       = aws_vpc_endpoint.dynamodb.id
}

# Dashboard Outputs

output "dashboard_alb_dns" {
  description = "Public DNS address of dashboard ALB"
  value       = aws_lb.dashboard.dns_name
}

output "dashboard_target_group_arn" {
  description = "Dashboard target group ARN"
  value       = aws_lb_target_group.dashboard.arn
}

output "dashboard_asg_name" {
  description = "Dashboard Auto Scaling group name"
  value       = aws_autoscaling_group.dashboard.name
}

# IAM Role ARNs

output "dashboard_instance_profile_arn" {
  value = aws_iam_instance_profile.dashboard.arn
}

output "ecs_execution_role_arn" {
  value = aws_iam_role.services["ecs_execution"].arn
}

output "pentest_task_role_arn" {
  value = aws_iam_role.services["pentest"].arn
}

output "lambda_role_arns" {
  value = {
    for role in ["sast", "dispatcher", "reconciler", "notifier"] :
    role => aws_iam_role.services[role].arn
  }
}

# ---------------------------------------
# Lambda Outputs
# ---------------------------------------

output "sast_lambda_arn" {
  value = aws_lambda_function.sast.arn
}

output "python_lambda_arns" {
  value = {
    for name, fn in aws_lambda_function.python :
    name => fn.arn
  }
}

# ---------------------------------------
# ECS Task Definition
# ---------------------------------------

output "pentest_task_definition_arn" {
  description = "ARN of the PenTest Fargate task definition"
  value       = aws_ecs_task_definition.pentest.arn
}
