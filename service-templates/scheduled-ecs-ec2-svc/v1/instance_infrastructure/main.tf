resource "aws_cloudwatch_event_rule" "scheduled-event-rule" {
  name = "${var.service.name}-scheduled-event-rule"
  schedule_expression = var.service_instance.inputs.schedule_expression
}

resource "aws_cloudwatch_event_target" "ecs-cluster-event-target" {
  arn  = var.environment.outputs.ClusterArn
  rule = aws_cloudwatch_event_rule.scheduled-event-rule.name
  ecs_target {
    task_count = var.service_instance.inputs.desired_count
    task_definition_arn = aws_ecs_task_definition.scheduled-task-definition.arn
  }
  input = "{}"
  role_arn = aws_iam_role.scheduled-task-def-events-role.arn
}

resource "aws_iam_role" "scheduled-task-def-task-role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "scheduled-task-def-task-role-policy" {
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sns:Publish"
        Effect = "Allow"
        Resource = var.environment.outputs.SNSTopic
      }
    ]
  })
  role   = aws_iam_role.scheduled-task-def-task-role.id
}

resource "aws_iam_role" "scheduled-task-def-events-role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "scheduled-task-def-events-role-policy" {
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "ecs:RunTask",
        Effect = "Allow",
        Condition = { "ArnEquals": { "ecs:cluster": var.environment.outputs.ClusterArn } },
        Resource = aws_ecs_task_definition.scheduled-task-definition.arn
      },
      {
        Action = "iam:PassRole"
        Effect = "Allow",
        Resource = var.environment.outputs.ServiceTaskDefExecutionRole
      },
      {
        Action = "iam:PassRole"
        Effect = "Allow",
        Resource = aws_iam_role.scheduled-task-def-task-role.arn
      }
    ]
  })
  name = "ScheduledECSEC2TaskScheduledTaskDefEventsRoleDefaultPolicy"
  role   = aws_iam_role.scheduled-task-def-events-role.id
}

resource "aws_cloudwatch_log_group" "scheduled-task-log-group" {
  retention_in_days = 0
}

resource "aws_ecs_task_definition" "scheduled-task-definition" {
  family                   = "${var.service.name}_${var.service_instance.name}"
  container_definitions    = jsonencode([{
    name : "${ var.service_instance.name }-bar",
    image : var.service_instance.inputs.image,
    cpu : lookup(var.task-size, var.service_instance.inputs.task_size).cpu
    memory : lookup(var.task-size, var.service_instance.inputs.task_size).memory
    essential : true,
    logConfiguration : {
      logDriver : "awslogs",
      options : {
        awslogs-group : aws_cloudwatch_log_group.scheduled-task-log-group.name,
        awslogs-stream-prefix : "${var.service.name}/${var.service_instance.name}",
        awslogs-region : local.region
      }
    },
    environment : [
      {
        name : "SNS_TOPIC_ARN",
        value : "{ \"ping\" : \"${var.environment.outputs.SNSTopic}\" }"
      },
      {
        name : "SNS_REGION",
        value : var.environment.outputs.SNSRegion
      }
    ]
  }])
  task_role_arn            = aws_iam_role.scheduled-task-def-task-role.arn
  execution_role_arn       = var.environment.outputs.ServiceTaskDefExecutionRole
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
}