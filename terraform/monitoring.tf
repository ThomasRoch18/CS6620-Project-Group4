# ---------------------------------------
# Lambda CloudWatch Log Groups
# ---------------------------------------

locals {
  monitored_lambdas = toset([
    "sast",
    "dispatcher",
    "reconciler",
    "notifier"
  ])
}

resource "aws_cloudwatch_log_group" "lambda" {
  for_each = local.monitored_lambdas

  name              = "/aws/lambda/${var.project_name}-${each.key == "sast" ? "sast-worker" : each.key}"
  retention_in_days = 14

  tags = {
    Name = "${var.project_name}-${each.key}-logs"
  }
}

# ---------------------------------------
# ECS PenTest Worker Logs
# ---------------------------------------

resource "aws_cloudwatch_log_group" "pentest" {
  name              = "/aws/ecs/${var.project_name}-pentest"
  retention_in_days = 14

  tags = {
    Name = "${var.project_name}-pentest-logs"
  }
}

# ---------------------------------------
# Lambda Error Alarms
# ---------------------------------------

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = local.monitored_lambdas

  alarm_name          = "${var.project_name}-${each.key}-errors"
  alarm_description   = "Detect errors in the ${each.key} Lambda"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0

  namespace   = "AWS/Lambda"
  metric_name = "Errors"
  statistic   = "Sum"
  period      = 300

  dimensions = {
    FunctionName = each.key == "sast" ? aws_lambda_function.sast.function_name : aws_lambda_function.python[each.key].function_name
  }

  treat_missing_data = "notBreaching"

  alarm_actions = [
    aws_sns_topic.scan_notifications.arn
  ]
}

# ---------------------------------------
# Dead-Letter Queue Alarms
# ---------------------------------------

locals {
  dead_letter_queues = {
    sast    = aws_sqs_queue.sast_dlq.name
    pentest = aws_sqs_queue.pentest_dlq.name
  }
}

resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  for_each = toset(["sast", "pentest"])

  alarm_name          = "${var.project_name}-${each.key}-dlq-messages"
  alarm_description   = "Messages detected in ${each.key} DLQ"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0

  namespace   = "AWS/SQS"
  metric_name = "ApproximateNumberOfMessagesVisible"
  statistic   = "Maximum"
  period      = 300

  dimensions = {
    QueueName = "${var.project_name}-${each.key}-dlq"
  }

  treat_missing_data = "notBreaching"

  alarm_actions = [
    aws_sns_topic.scan_notifications.arn
  ]
}

