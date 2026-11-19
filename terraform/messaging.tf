# ---------------------------------------
# SAST Dead-Letter Queue
# ---------------------------------------
resource "aws_sqs_queue" "sast_dlq" {
  name = "${var.project_name}-sast-dlq"

  message_retention_seconds = 1209600 # 14 days
  sqs_managed_sse_enabled   = true

  tags = {
    Name = "${var.project_name}-sast-dlq"
  }
}

# ---------------------------------------
# SAST Main Queue
# ---------------------------------------
resource "aws_sqs_queue" "sast" {
  name = "${var.project_name}-sast-queue"

  visibility_timeout_seconds = 900
  message_retention_seconds  = 345600 # 4 days
  receive_wait_time_seconds  = 20
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.sast_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name = "${var.project_name}-sast-queue"
  }
}

# ---------------------------------------
# PenTest Dead-Letter Queue
# ---------------------------------------
resource "aws_sqs_queue" "pentest_dlq" {
  name = "${var.project_name}-pentest-dlq"

  message_retention_seconds = 1209600 # 14 days
  sqs_managed_sse_enabled   = true

  tags = {
    Name = "${var.project_name}-pentest-dlq"
  }
}

# ---------------------------------------
# PenTest Main Queue
# ---------------------------------------
resource "aws_sqs_queue" "pentest" {
  name = "${var.project_name}-pentest-queue"

  visibility_timeout_seconds = 180
  message_retention_seconds  = 345600
  receive_wait_time_seconds  = 20
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.pentest_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name = "${var.project_name}-pentest-queue"
  }
}

# ---------------------------------------
# SNS Scan Notifications
# ---------------------------------------
resource "aws_sns_topic" "scan_notifications" {
  name = "${var.project_name}-scan-notifications"

  tags = {
    Name = "${var.project_name}-scan-notifications"
  }
}
