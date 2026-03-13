terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    # Configure in environments/*/backend.tfvars
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "rpv-capital"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Local values
locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  name_prefix = "rpv-${var.environment}"
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"

  name_prefix = local.name_prefix
  environment = var.environment
}

# RDS Module
module "rds" {
  source = "./modules/rds"

  name_prefix        = local.name_prefix
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  db_instance_class  = var.db_instance_class
  db_name            = "rpv_capital"
  db_username        = var.db_username
}

# ECS Cluster
module "ecs" {
  source = "./modules/ecs"

  name_prefix        = local.name_prefix
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  # Bot service
  bot_image          = var.bot_image
  bot_cpu            = var.bot_cpu
  bot_memory         = var.bot_memory

  # Environment variables
  database_url       = module.rds.connection_string
  openrouter_api_key = var.openrouter_api_key
  meta_app_secret    = var.meta_app_secret
}

# Lambda Functions
module "lambda" {
  source = "./modules/lambda"

  name_prefix        = local.name_prefix
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  database_url       = module.rds.connection_string
}

# EventBridge Scheduler
module "eventbridge" {
  source = "./modules/eventbridge"

  name_prefix = local.name_prefix
  environment = var.environment

  # Lambda ARNs
  crawler_lambda_arn    = module.lambda.crawler_lambda_arn
  outbound_lambda_arn   = module.lambda.outbound_lambda_arn
  followup_lambda_arn   = module.lambda.followup_lambda_arn
  relatorio_lambda_arn  = module.lambda.relatorio_lambda_arn

  # ECS Task for ESAJ
  esaj_cluster_arn      = module.ecs.cluster_arn
  esaj_task_definition  = module.ecs.esaj_task_definition_arn
  esaj_subnet_ids       = module.vpc.private_subnet_ids
  esaj_security_group   = module.ecs.esaj_security_group_id
}

# Secrets Manager
resource "aws_secretsmanager_secret" "openrouter" {
  name        = "${local.name_prefix}-openrouter-api-key"
  description = "OpenRouter API Key"
}

resource "aws_secretsmanager_secret" "meta" {
  name        = "${local.name_prefix}-meta-credentials"
  description = "Meta WhatsApp Cloud API credentials"
}

# Outputs
output "bot_url" {
  description = "Bot webhook URL"
  value       = module.ecs.bot_url
}

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = module.rds.endpoint
  sensitive   = true
}

output "dashboard_url" {
  description = "Dashboard URL (Amplify)"
  value       = "https://dashboard.${var.domain}"
}
