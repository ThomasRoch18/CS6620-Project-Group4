# ---------------------------------------
# ECR - SAST Docker Repository
# ---------------------------------------
resource "aws_ecr_repository" "sast" {
  name                 = "${var.project_name}-sast"
  image_tag_mutability = "MUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "${var.project_name}-sast"
  }
}

# ---------------------------------------
# ECR - PenTest Docker Repository
# ---------------------------------------
resource "aws_ecr_repository" "pentest" {
  name                 = "${var.project_name}-pentest"
  image_tag_mutability = "MUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "${var.project_name}-pentest"
  }
}

# ---------------------------------------
# ECS Cluster - PenTest Workers
# ---------------------------------------
resource "aws_ecs_cluster" "pentest" {
  name = "${var.project_name}-pentest-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = {
    Name = "${var.project_name}-pentest-cluster"
  }
}

# ---------------------------------------
# ECS Fargate PenTest Task Definition
# ---------------------------------------

resource "aws_ecs_task_definition" "pentest" {
  family                   = "${var.project_name}-pentest"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"

  # 0.5 vCPU and 1 GB RAM
  cpu    = "512"
  memory = "1024"

  execution_role_arn = aws_iam_role.services["ecs_execution"].arn
  task_role_arn      = aws_iam_role.services["pentest"].arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "pentest-worker"
      image     = "${aws_ecr_repository.pentest.repository_url}:latest"
      essential = true

      environment = [
        {
          name  = "ARTIFACTS_BUCKET"
          value = aws_s3_bucket.artifacts.id
        },
        {
          name  = "JOBS_TABLE"
          value = aws_dynamodb_table.jobs.name
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"

        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.pentest.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "pentest"
        }
      }
    }
  ])

  tags = {
    Name = "${var.project_name}-pentest-task"
  }
}
