variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name prefix for resources"
  type        = string
  default     = "robust-data-processor"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "ingestion_zip_path" {
  description = "Path to ingestion Lambda deployment package"
  type        = string
  default     = "../../ingestion.zip"
}

variable "worker_zip_path" {
  description = "Path to worker Lambda deployment package"
  type        = string
  default     = "../../worker.zip"
}

