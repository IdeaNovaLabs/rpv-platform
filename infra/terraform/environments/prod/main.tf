terraform {
  backend "s3" {
    bucket         = "rpv-capital-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "rpv-capital-terraform-locks"
  }
}

module "rpv" {
  source = "../../"

  environment = "prod"
  aws_region  = "us-east-1"
  domain      = "rpvcapital.com.br"

  # RDS - larger instance for prod
  db_instance_class = "db.t4g.small"
  db_username       = "rpv_prod"

  # ECS - more resources for prod
  bot_cpu    = 512
  bot_memory = 1024
  bot_image  = var.bot_image

  # Secrets from environment/tfvars
  openrouter_api_key  = var.openrouter_api_key
  meta_app_secret     = var.meta_app_secret
  meta_whatsapp_token = var.meta_whatsapp_token
}

variable "bot_image" {
  type        = string
  description = "ECR image URI for bot"
}

variable "openrouter_api_key" {
  type      = string
  sensitive = true
}

variable "meta_app_secret" {
  type      = string
  sensitive = true
}

variable "meta_whatsapp_token" {
  type      = string
  sensitive = true
}

output "bot_url" {
  value = module.rpv.bot_url
}

output "dashboard_url" {
  value = module.rpv.dashboard_url
}
