# ---------------------------------------
# ECS Task State Changes
# ---------------------------------------

resource "aws_cloudwatch_event_rule" "ecs_task_stopped" {
  name        = "${var.project_name}-ecs-task-stopped"
  description = "Detect stopped PenTest ECS tasks"
  state       = "DISABLED"

  event_pattern = jsonencode({
    source        = ["aws.ecs"]
    "detail-type" = ["ECS Task State Change"]

    detail = {
      clusterArn = [aws_ecs_cluster.pentest.arn]
      lastStatus = ["STOPPED"]
    }
  })
}

resource "aws_cloudwatch_event_target" "ecs_task_stopped" {
  rule      = aws_cloudwatch_event_rule.ecs_task_stopped.name
  target_id = "pentest-reconciler"
  arn       = aws_lambda_function.python["reconciler"].arn
}

resource "aws_lambda_permission" "ecs_eventbridge" {
  statement_id  = "AllowEventBridgeEcsTasks"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.python["reconciler"].function_name

  principal  = "events.amazonaws.com"
  source_arn = aws_cloudwatch_event_rule.ecs_task_stopped.arn
}

# ---------------------------------------
# Scheduled Job Reconciliation
# ---------------------------------------

resource "aws_cloudwatch_event_rule" "reconcile_schedule" {
  name                = "${var.project_name}-reconcile-schedule"
  description         = "Check for stale scanning jobs every five minutes"
  schedule_expression = "rate(5 minutes)"
  state               = "DISABLED"
}

resource "aws_cloudwatch_event_target" "reconcile_schedule" {
  rule      = aws_cloudwatch_event_rule.reconcile_schedule.name
  target_id = "scheduled-reconciler"
  arn       = aws_lambda_function.python["reconciler"].arn
}

resource "aws_lambda_permission" "scheduled_reconciler" {
  statement_id  = "AllowScheduledReconciliation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.python["reconciler"].function_name

  principal  = "events.amazonaws.com"
  source_arn = aws_cloudwatch_event_rule.reconcile_schedule.arn
}
