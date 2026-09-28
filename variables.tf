variable "project_name" {
  description = "Project name used as prefix for all resources."
  type        = string
  default     = "floci-ec2-compliance-check"
}

variable "aws_region" {
  description = "AWS region (simulated by floci)."
  type        = string
  default     = "us-east-1"
}

variable "notification_email" {
  description = "Email address subscribed to the compliance notifications SNS topic."
  type        = string
  default     = "compliance-team@example.com"
}

variable "config_max_execution_frequency" {
  description = "How often AWS Config re-evaluates EC2 instances against the custom rule."
  type        = string
  default     = "One_Hour"
}
