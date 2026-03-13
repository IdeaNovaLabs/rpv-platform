variable "name_prefix" {
  type = string
}

variable "environment" {
  type = string
}

variable "crawler_lambda_arn" {
  type = string
}

variable "outbound_lambda_arn" {
  type = string
}

variable "followup_lambda_arn" {
  type = string
}

variable "relatorio_lambda_arn" {
  type = string
}

variable "esaj_cluster_arn" {
  type = string
}

variable "esaj_task_definition" {
  type = string
}

variable "esaj_subnet_ids" {
  type = list(string)
}

variable "esaj_security_group" {
  type = string
}

# IAM Role for EventBridge
resource "aws_iam_role" "eventbridge" {
  name = "${var.name_prefix}-eventbridge-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "scheduler.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "eventbridge_lambda" {
  name = "${var.name_prefix}-eventbridge-lambda"
  role = aws_iam_role.eventbridge.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["lambda:InvokeFunction"]
      Resource = [
        var.crawler_lambda_arn,
        var.outbound_lambda_arn,
        var.followup_lambda_arn,
        var.relatorio_lambda_arn
      ]
    }]
  })
}

resource "aws_iam_role_policy" "eventbridge_ecs" {
  name = "${var.name_prefix}-eventbridge-ecs"
  role = aws_iam_role.eventbridge.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["ecs:RunTask"]
        Resource = [var.esaj_task_definition]
      },
      {
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = ["*"]
      }
    ]
  })
}

# Crawler Schedule (6h daily)
resource "aws_scheduler_schedule" "crawler" {
  name       = "${var.name_prefix}-crawler"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(0 6 * * ? *)"
  schedule_expression_timezone = "America/Sao_Paulo"

  target {
    arn      = var.crawler_lambda_arn
    role_arn = aws_iam_role.eventbridge.arn
  }
}

# ESAJ Batch Schedule (7h daily)
resource "aws_scheduler_schedule" "esaj" {
  name       = "${var.name_prefix}-esaj"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(0 7 * * ? *)"
  schedule_expression_timezone = "America/Sao_Paulo"

  target {
    arn      = var.esaj_cluster_arn
    role_arn = aws_iam_role.eventbridge.arn

    ecs_parameters {
      task_definition_arn = var.esaj_task_definition
      launch_type         = "FARGATE"

      network_configuration {
        subnets          = var.esaj_subnet_ids
        security_groups  = [var.esaj_security_group]
        assign_public_ip = false
      }
    }
  }
}

# Outbound Schedule (9h weekdays)
resource "aws_scheduler_schedule" "outbound" {
  name       = "${var.name_prefix}-outbound"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(0 9 ? * MON-FRI *)"
  schedule_expression_timezone = "America/Sao_Paulo"

  target {
    arn      = var.outbound_lambda_arn
    role_arn = aws_iam_role.eventbridge.arn
  }
}

# Follow-up Schedule (10h weekdays)
resource "aws_scheduler_schedule" "followup" {
  name       = "${var.name_prefix}-followup"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(0 10 ? * MON-FRI *)"
  schedule_expression_timezone = "America/Sao_Paulo"

  target {
    arn      = var.followup_lambda_arn
    role_arn = aws_iam_role.eventbridge.arn
  }
}

# Daily Report Schedule (18h weekdays)
resource "aws_scheduler_schedule" "relatorio" {
  name       = "${var.name_prefix}-relatorio"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(0 18 ? * MON-FRI *)"
  schedule_expression_timezone = "America/Sao_Paulo"

  target {
    arn      = var.relatorio_lambda_arn
    role_arn = aws_iam_role.eventbridge.arn
  }
}

# Outputs
output "scheduler_role_arn" {
  value = aws_iam_role.eventbridge.arn
}
