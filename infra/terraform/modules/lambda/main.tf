variable "name_prefix" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "database_url" {
  type      = string
  sensitive = true
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda" {
  name = "${var.name_prefix}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "lambda_secrets" {
  name = "${var.name_prefix}-lambda-secrets"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue"
      ]
      Resource = ["*"]
    }]
  })
}

# Security Group for Lambda
resource "aws_security_group" "lambda" {
  name        = "${var.name_prefix}-lambda-sg"
  description = "Security group for Lambda functions"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-lambda-sg"
  }
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "crawler" {
  name              = "/aws/lambda/${var.name_prefix}-crawler"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "outbound" {
  name              = "/aws/lambda/${var.name_prefix}-outbound"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "followup" {
  name              = "/aws/lambda/${var.name_prefix}-followup"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "relatorio" {
  name              = "/aws/lambda/${var.name_prefix}-relatorio"
  retention_in_days = 14
}

# Lambda Functions
# Note: Actual deployment will be done separately (SAM, CDK, or manual)
# This creates the placeholder resources

resource "aws_lambda_function" "crawler" {
  function_name = "${var.name_prefix}-crawler"
  role          = aws_iam_role.lambda.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.11"
  timeout       = 300
  memory_size   = 256

  # Placeholder - actual code deployed separately
  filename = data.archive_file.placeholder.output_path

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      ENVIRONMENT = var.environment
    }
  }

  depends_on = [aws_cloudwatch_log_group.crawler]
}

resource "aws_lambda_function" "outbound" {
  function_name = "${var.name_prefix}-outbound"
  role          = aws_iam_role.lambda.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.11"
  timeout       = 120
  memory_size   = 256

  filename = data.archive_file.placeholder.output_path

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      ENVIRONMENT = var.environment
    }
  }

  depends_on = [aws_cloudwatch_log_group.outbound]
}

resource "aws_lambda_function" "followup" {
  function_name = "${var.name_prefix}-followup"
  role          = aws_iam_role.lambda.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.11"
  timeout       = 120
  memory_size   = 256

  filename = data.archive_file.placeholder.output_path

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      ENVIRONMENT = var.environment
    }
  }

  depends_on = [aws_cloudwatch_log_group.followup]
}

resource "aws_lambda_function" "relatorio" {
  function_name = "${var.name_prefix}-relatorio"
  role          = aws_iam_role.lambda.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.11"
  timeout       = 60
  memory_size   = 128

  filename = data.archive_file.placeholder.output_path

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      ENVIRONMENT = var.environment
    }
  }

  depends_on = [aws_cloudwatch_log_group.relatorio]
}

# Placeholder zip for initial deployment
data "archive_file" "placeholder" {
  type        = "zip"
  output_path = "${path.module}/placeholder.zip"

  source {
    content  = "def lambda_handler(event, context): return {'statusCode': 200}"
    filename = "handler.py"
  }
}

# Outputs
output "crawler_lambda_arn" {
  value = aws_lambda_function.crawler.arn
}

output "outbound_lambda_arn" {
  value = aws_lambda_function.outbound.arn
}

output "followup_lambda_arn" {
  value = aws_lambda_function.followup.arn
}

output "relatorio_lambda_arn" {
  value = aws_lambda_function.relatorio.arn
}

output "lambda_role_arn" {
  value = aws_iam_role.lambda.arn
}
