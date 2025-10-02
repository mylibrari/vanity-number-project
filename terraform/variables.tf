
variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"  # Required for Amazon Connect
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "connect_instance_id" {
  description = "Amazon Connect instance ID (if available)"
  type        = string
  default     = ""
}

variable "phone_number" {
  description = "Phone number for Amazon Connect (if available)"
  type        = string
  default     = ""
}