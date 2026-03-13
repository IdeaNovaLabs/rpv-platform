terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}

module "rpv" {
  source = "../../"

  environment = "dev"
  aws_region  = "us-east-1"

  # RDS
  db_instance_class = "db.t4g.micro"
  db_username       = "rpv_dev"

  # ECS
  bot_cpu    = 256
  bot_memory = 512
  bot_image  = ""  # Will be set after ECR push

  # Secrets - use dummy values for local dev
  openrouter_api_key  = var.openrouter_api_key
  meta_app_secret     = var.meta_app_secret
  meta_whatsapp_token = var.meta_whatsapp_token
}

variable "openrouter_api_key" {
  type      = string
  sensitive = true
  default   = "sk-or-dev-placeholder"
}

variable "meta_app_secret" {
  type      = string
  sensitive = true
  default   = "dev-secret-placeholder"
}

variable "meta_whatsapp_token" {
  type      = string
  sensitive = true
  default   = ""
}

output "bot_url" {
  value = module.rpv.bot_url
}
