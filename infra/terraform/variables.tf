variable "aws_region" {
  type        = string
  description = "AWS region to deploy into."
  default     = "ap-northeast-1"
}

variable "project_name" {
  type        = string
  description = "Name prefix for AWS resources."
  default     = "aws-research-01-lightweight-runner"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the runner VPC."
  default     = "10.34.0.0/16"
}

variable "public_subnet_cidr" {
  type        = string
  description = "CIDR block for the public subnet that hosts the EC2 runner."
  default     = "10.34.0.0/24"
}

variable "runner_instance_type" {
  type        = string
  description = "EC2 instance type for the GitHub Actions runner."
  default     = "t3.small"
}

variable "runner_arch" {
  type        = string
  description = "GitHub Actions runner architecture package suffix."
  default     = "x64"

  validation {
    condition     = contains(["x64", "arm64"], var.runner_arch)
    error_message = "runner_arch must be x64 or arm64."
  }
}

variable "runner_root_volume_size" {
  type        = number
  description = "Root EBS volume size in GiB. Docker builds need enough local disk."
  default     = 30
}

variable "github_repository" {
  type        = string
  description = "GitHub repository allowed to assume the task 4 OIDC role. Format: owner/repo."
  default     = "ryo1699/Study_AWS-3"
}

variable "github_branch" {
  type        = string
  description = "GitHub branch allowed to assume the task 4 OIDC role."
  default     = "main"
}
