# ---------------------------------------
# IAM Roles and Trust Policies
# ---------------------------------------

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  service_roles = {
    dashboard     = "ec2.amazonaws.com"
    ecs_execution = "ecs-tasks.amazonaws.com"
    pentest       = "ecs-tasks.amazonaws.com"
    sast          = "lambda.amazonaws.com"
    dispatcher    = "lambda.amazonaws.com"
    reconciler    = "lambda.amazonaws.com"
    notifier      = "lambda.amazonaws.com"
  }

  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # Names for log groups we'll create in monitoring.tf
  ecs_log_group = "/aws/ecs/${var.project_name}-pentest"
}

resource "aws_iam_role" "services" {
  for_each = local.service_roles

  name = "${var.project_name}-${each.key}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = each.value
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.project_name}-${each.key}-role"
  }
}

# EC2 requires an instance profile to use its role
resource "aws_iam_instance_profile" "dashboard" {
  name = "${var.project_name}-dashboard-profile"
  role = aws_iam_role.services["dashboard"].name
}



# ---------------------------------------
# Least-Privilege Permissions
# ---------------------------------------

locals {
  artifacts_arn = aws_s3_bucket.artifacts.arn
  jobs_arn      = aws_dynamodb_table.jobs.arn

  role_statements = {

    # Flask Dashboard
    dashboard = [
      {
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetObject"]
        Resource = [
          "${local.artifacts_arn}/uploads/*",
          "${local.artifacts_arn}/sast-results/*",
          "${local.artifacts_arn}/pentest-results/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Resource = [
          local.jobs_arn,
          "${local.jobs_arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = ["sqs:SendMessage"]
        Resource = [
          aws_sqs_queue.sast.arn,
          aws_sqs_queue.pentest.arn
        ]
      }
    ]

    # SAST Lambda Worker
    sast = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${local.artifacts_arn}/uploads/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = ["${local.artifacts_arn}/sast-results/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem", "dynamodb:GetItem"]
        Resource = [local.jobs_arn]
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = [aws_sqs_queue.sast.arn]
      }
    ]

    # ECS Agent: ECR Image Pull
    ecs_execution = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = [aws_ecr_repository.pentest.arn]
      }
    ]

    # PenTest Container Application
    pentest = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${local.artifacts_arn}/uploads/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = ["${local.artifacts_arn}/pentest-results/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:UpdateItem"]
        Resource = [local.jobs_arn]
      }
    ]

    # PenTest Dispatcher Lambda
    dispatcher = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = [aws_sqs_queue.pentest.arn]
      },
      {
        Effect = "Allow"
        Action = ["ecs:RunTask"]
        Resource = [
          "arn:${local.partition}:ecs:${var.aws_region}:${local.account_id}:task-definition/${var.project_name}-pentest:*"
        ]
        Condition = {
          ArnEquals = {
            "ecs:cluster" = aws_ecs_cluster.pentest.arn
          }
        }
      },
      {
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = [
          aws_iam_role.services["ecs_execution"].arn,
          aws_iam_role.services["pentest"].arn
        ]
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem"]
        Resource = [local.jobs_arn]
      }
    ]

    # Failure Reconciler Lambda
    reconciler = [
      {
        Effect   = "Allow"
        Action   = ["ecs:DescribeTasks"]
        Resource = ["*"]
        Condition = {
          ArnEquals = {
            "ecs:cluster" = aws_ecs_cluster.pentest.arn
          }
        }
      },
      {
        Effect = "Allow"
        Action = ["dynamodb:UpdateItem", "dynamodb:Query"]
        Resource = [
          local.jobs_arn,
          "${local.jobs_arn}/index/*"
        ]
      }
    ]

    # DynamoDB Stream Notifier Lambda
    notifier = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeStream",
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator"
        ]
        Resource = [aws_dynamodb_table.jobs.stream_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:ListStreams"]
        Resource = [local.jobs_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = [aws_sns_topic.scan_notifications.arn]
      }
    ]
  }
}

# ---------------------------------------
# CloudWatch Log Permissions
# ---------------------------------------

locals {
  # Lambda can write only to its own log group.

  lambda_log_statements = {
    for role in ["sast", "dispatcher", "reconciler", "notifier"] :
    role => [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = [
        "arn:${local.partition}:logs:${var.aws_region}:${local.account_id}:log-group:/aws/lambda/${var.project_name}-${role == "sast" ? "sast-worker" : role}:*"
      ]
    }]
  }


  ecs_log_statements = [{
    Effect = "Allow"
    Action = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    Resource = [
      "arn:${local.partition}:logs:${var.aws_region}:${local.account_id}:log-group:${local.ecs_log_group}:*"
    ]
  }]
}

# ---------------------------------------
# Attach a Policy to Each IAM Role
# ---------------------------------------

resource "aws_iam_role_policy" "services" {
  for_each = local.service_roles

  name = "${var.project_name}-${each.key}-policy"
  role = aws_iam_role.services[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = concat(
      local.role_statements[each.key],
      lookup(local.lambda_log_statements, each.key, []),
      each.key == "ecs_execution" ? local.ecs_log_statements : []
    )
  })
}
