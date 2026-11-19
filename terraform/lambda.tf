# ---------------------------------------
# Placeholder Python Lambda Packages
# ---------------------------------------

locals {
  python_lambda_names = toset([
    "dispatcher",
    "reconciler",
    "notifier"
  ])
}

data "archive_file" "lambda_placeholder" {
  for_each = local.python_lambda_names

  type        = "zip"
  output_path = "${path.module}/${each.key}-placeholder.zip"

  source_content_filename = "handler.py"

  source_content = <<-PYTHON
import json
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    component = os.environ.get("COMPONENT", "unknown")

    logger.info(
        "Placeholder invoked for %s",
        component
    )

    return {
        "statusCode": 200,
        "body": json.dumps({
            "component": component,
            "status": "NOT_IMPLEMENTED"
        })
    }
PYTHON
}

# ---------------------------------------
# Python Lambda Functions
# ---------------------------------------

resource "aws_lambda_function" "python" {
  for_each = local.python_lambda_names

  function_name = "${var.project_name}-${each.key}"

  role    = aws_iam_role.services[each.key].arn
  handler = "handler.lambda_handler"
  runtime = "python3.12"

  filename = data.archive_file.lambda_placeholder[each.key].output_path

  source_code_hash = data.archive_file.lambda_placeholder[each.key].output_base64sha256

  timeout     = each.key == "dispatcher" ? 20 : 30
  memory_size = 256

  environment {
    variables = {
      COMPONENT        = each.key
      JOBS_TABLE       = aws_dynamodb_table.jobs.name
      ARTIFACTS_BUCKET = aws_s3_bucket.artifacts.id
      ECS_CLUSTER      = aws_ecs_cluster.pentest.arn
      SNS_TOPIC_ARN    = aws_sns_topic.scan_notifications.arn
    }
  }

  tags = {
    Name = "${var.project_name}-${each.key}"
  }
}

# ---------------------------------------
# SAST Lambda - ECR Container Image
# ---------------------------------------

resource "aws_lambda_function" "sast" {
  function_name = "${var.project_name}-sast-worker"

  role         = aws_iam_role.services["sast"].arn
  package_type = "Image"

  image_uri = "${aws_ecr_repository.sast.repository_url}:latest"

  architectures = ["x86_64"]

  timeout     = 120
  memory_size = 1024

  environment {
    variables = {
      JOBS_TABLE       = aws_dynamodb_table.jobs.name
      ARTIFACTS_BUCKET = aws_s3_bucket.artifacts.id
    }
  }

  tags = {
    Name = "${var.project_name}-sast-worker"
  }
}

# ---------------------------------------
# SAST Queue -> Lambda
# ---------------------------------------

resource "aws_lambda_event_source_mapping" "sast" {
  event_source_arn = aws_sqs_queue.sast.arn
  function_name    = aws_lambda_function.sast.arn

  batch_size = 1
  enabled    = false

  function_response_types = [
    "ReportBatchItemFailures"
  ]
}

# ---------------------------------------
# PenTest Queue -> Dispatcher
# ---------------------------------------

resource "aws_lambda_event_source_mapping" "pentest" {
  event_source_arn = aws_sqs_queue.pentest.arn
  function_name    = aws_lambda_function.python["dispatcher"].arn

  batch_size = 1
  enabled    = false

  function_response_types = [
    "ReportBatchItemFailures"
  ]
}

# ---------------------------------------
# DynamoDB Streams -> Notifier
# ---------------------------------------

resource "aws_lambda_event_source_mapping" "notifier" {
  event_source_arn = aws_dynamodb_table.jobs.stream_arn
  function_name    = aws_lambda_function.python["notifier"].arn

  starting_position = "LATEST"
  batch_size        = 10
  enabled           = false

  function_response_types = [
    "ReportBatchItemFailures"
  ]
}
