variable "aws_region" {
  description = "The AWS region to deploy resources into"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment name (e.g. dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Project name identifier used for prefixing resources"
  type        = string
  default     = "iac-assurance"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "documentdb_master_username" {
  description = "Master username for Amazon DocumentDB cluster"
  type        = string
  default     = "iacadmin"
}

variable "documentdb_master_password" {
  description = "Master password for Amazon DocumentDB cluster (min 8 chars)"
  type        = string
  sensitive   = true
  default     = "P@ssw0rdIaC2026!"
}

variable "documentdb_instance_class" {
  description = "DocumentDB instance class (e.g. db.t3.medium or db.t4g.medium)"
  type        = string
  default     = "db.t3.medium"
}

variable "backend_cpu" {
  description = "CPU units for the Backend ECS Task (256 = 0.25 vCPU, 512 = 0.5 vCPU, 1024 = 1 vCPU)"
  type        = number
  default     = 512
}

variable "backend_memory" {
  description = "Memory in MiB for the Backend ECS Task"
  type        = number
  default     = 1024
}

variable "ml_engine_cpu" {
  description = "CPU units for the ML Validation Engine ECS Task"
  type        = number
  default     = 1024
}

variable "ml_engine_memory" {
  description = "Memory in MiB for the ML Validation Engine ECS Task"
  type        = number
  default     = 2048
}

variable "bedrock_model_id" {
  description = "Amazon Bedrock model ID for LLM reasoning and recommendations"
  type        = string
  default     = "anthropic.claude-3-5-sonnet-20241022-v2:0"
}
