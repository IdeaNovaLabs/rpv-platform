variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "domain" {
  description = "Base domain for the application"
  type        = string
  default     = "rpvcapital.com.br"
}

# RDS
variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_username" {
  description = "RDS master username"
  type        = string
  default     = "rpv_admin"
  sensitive   = true
}

# ECS Bot
variable "bot_image" {
  description = "Docker image for bot"
  type        = string
  default     = ""
}

variable "bot_cpu" {
  description = "CPU units for bot (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "bot_memory" {
  description = "Memory for bot in MB"
  type        = number
  default     = 512
}

# Secrets (passed via environment or tfvars)
variable "openrouter_api_key" {
  description = "OpenRouter API Key"
  type        = string
  sensitive   = true
}

variable "meta_app_secret" {
  description = "Meta App Secret for webhook validation"
  type        = string
  sensitive   = true
}

variable "meta_whatsapp_token" {
  description = "Meta WhatsApp API Token"
  type        = string
  sensitive   = true
  default     = ""
}

variable "meta_phone_number_id" {
  description = "Meta Phone Number ID"
  type        = string
  default     = ""
}
