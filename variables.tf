#############################################
# Customizable Variables for cloud_breach_s3
#############################################

#-----------------------------------------
# AWS Configuration
#-----------------------------------------

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to use for authentication"
  type        = string
  default     = "default"
}

#-----------------------------------------
# Network Configuration
#-----------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the reverse proxy (use your IP for security)"
  type        = list(string)
  default     = ["0.0.0.0/0"] # WARNING: Open to all - restrict in production!
}

#-----------------------------------------
# EC2 Configuration
#-----------------------------------------

variable "ec2_instance_type" {
  description = "Instance type for the reverse proxy EC2"
  type        = string
  default     = "t2.micro" # Free tier eligible
}

variable "ssh_key_name" {
  description = "Name of existing SSH key pair (leave empty to disable SSH)"
  type        = string
  default     = ""
}

variable "enable_ssh" {
  description = "Enable SSH access to the EC2 instance"
  type        = bool
  default     = false
}

#-----------------------------------------
# Security Configuration (Vulnerability Toggles)
#-----------------------------------------

variable "use_imdsv2" {
  description = "Use IMDSv2 (secure) instead of IMDSv1 (vulnerable). Set to false for vulnerable scenario."
  type        = bool
  default     = false # Default: vulnerable (IMDSv1)
}

variable "enable_bucket_versioning" {
  description = "Enable versioning on the S3 bucket"
  type        = bool
  default     = false
}

#-----------------------------------------
# Customization Options
#-----------------------------------------

variable "custom_proxy_message" {
  description = "Custom message to display on the reverse proxy error page"
  type        = string
  default     = "This server is configured to proxy requests to the EC2 metadata service. Please modify your request's 'host' header and try again."
}

variable "enable_logging" {
  description = "Enable CloudWatch logging for the proxy"
  type        = bool
  default     = false
}

#-----------------------------------------
# Difficulty Settings
#-----------------------------------------

variable "difficulty" {
  description = "Scenario difficulty: easy, medium, hard"
  type        = string
  default     = "easy"

  validation {
    condition     = contains(["easy", "medium", "hard"], var.difficulty)
    error_message = "Difficulty must be one of: easy, medium, hard"
  }
}
