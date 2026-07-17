#############################################
# CloudGoat-style cloud_breach_s3 Scenario
# A customizable "vulnerable by design" AWS environment
# Simulates the Capital One breach scenario
#############################################

terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Environment = "cloudgoat"
      Scenario    = "cloud_breach_s3"
      ManagedBy   = "terraform"
    }
  }
}

# Random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

locals {
  scenario_name = "cloud-breach-s3-${random_string.suffix.result}"
}

#############################################
# VPC and Networking
#############################################

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.scenario_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.scenario_name}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.scenario_name}-public-subnet"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.scenario_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

data "aws_availability_zones" "available" {
  state = "available"
}

#############################################
# Security Group for EC2 (Reverse Proxy)
#############################################

resource "aws_security_group" "reverse_proxy" {
  name        = "${local.scenario_name}-reverse-proxy-sg"
  description = "Security group for vulnerable reverse proxy"
  vpc_id      = aws_vpc.main.id

  # HTTP access from anywhere (intentionally permissive for the scenario)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "HTTP access"
  }

  # SSH access (optional, for debugging)
  dynamic "ingress" {
    for_each = var.enable_ssh ? [1] : []
    content {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
      description = "SSH access"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name = "${local.scenario_name}-reverse-proxy-sg"
  }
}

#############################################
# IAM Role for EC2 (with S3 access)
#############################################

resource "aws_iam_role" "ec2_role" {
  name = "${local.scenario_name}-banking-WAF-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.scenario_name}-banking-WAF-Role"
  }
}

# Policy granting S3 access (intentionally overly permissive)
resource "aws_iam_role_policy" "ec2_s3_access" {
  name = "${local.scenario_name}-s3-access-policy"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.cardholder_data.arn,
          "${aws_s3_bucket.cardholder_data.arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = "s3:ListAllMyBuckets"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${local.scenario_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

#############################################
# S3 Bucket with "Sensitive" Data
#############################################

resource "aws_s3_bucket" "cardholder_data" {
  bucket        = "${local.scenario_name}-cardholder-data"
  force_destroy = true

  tags = {
    Name        = "${local.scenario_name}-cardholder-data"
    Sensitivity = "Confidential"
  }
}

resource "aws_s3_bucket_versioning" "cardholder_data" {
  bucket = aws_s3_bucket.cardholder_data.id
  versioning_configuration {
    status = var.enable_bucket_versioning ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_public_access_block" "cardholder_data" {
  bucket = aws_s3_bucket.cardholder_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload sample sensitive data files
resource "aws_s3_object" "cardholder_data_primary" {
  bucket  = aws_s3_bucket.cardholder_data.id
  key     = "cardholder_data_primary.csv"
  content = <<-EOF
card_number,cardholder_name,expiry_date,cvv,credit_limit,ssn
4532-XXXX-XXXX-1234,John Smith,12/25,XXX,$15000,XXX-XX-1234
4916-XXXX-XXXX-5678,Jane Doe,03/26,XXX,$25000,XXX-XX-5678
5425-XXXX-XXXX-9012,Bob Johnson,08/24,XXX,$10000,XXX-XX-9012
4539-XXXX-XXXX-3456,Alice Williams,11/27,XXX,$50000,XXX-XX-3456
5500-XXXX-XXXX-7890,Charlie Brown,06/25,XXX,$8000,XXX-XX-7890
EOF

  tags = {
    Sensitivity = "Confidential"
    DataType    = "PII"
  }
}

resource "aws_s3_object" "cardholder_data_secondary" {
  bucket  = aws_s3_bucket.cardholder_data.id
  key     = "cardholder_data_secondary.csv"
  content = <<-EOF
account_id,balance,last_transaction,credit_score,address
ACC-001,$12,450.00,2024-01-15,750,123 Main St - City - ST 12345
ACC-002,$8,320.50,2024-01-14,680,456 Oak Ave - Town - ST 67890
ACC-003,$45,000.00,2024-01-13,720,789 Pine Rd - Village - ST 11223
ACC-004,$3,200.75,2024-01-12,800,321 Elm St - Metro - ST 44556
ACC-005,$67,890.25,2024-01-11,650,654 Maple Dr - County - ST 77889
EOF

  tags = {
    Sensitivity = "Confidential"
    DataType    = "Financial"
  }
}

resource "aws_s3_object" "goat_flag" {
  bucket  = aws_s3_bucket.cardholder_data.id
  key     = "FLAG.txt"
  content = <<-EOF
Congratulations! You have successfully completed the cloud_breach_s3 scenario!

You exploited:
1. A misconfigured reverse proxy server
2. Instance Metadata Service (IMDS) exposure
3. Overly permissive IAM role attached to EC2

Key Takeaways:
- Always use IMDSv2 with session tokens
- Configure reverse proxies to only allow specific Host headers
- Apply least privilege principle to IAM roles
- Use VPC endpoints for S3 access

Flag: CLOUDGOAT{${random_string.suffix.result}_BREACH_COMPLETE}
EOF

  tags = {
    Type = "CTF-Flag"
  }
}

#############################################
# EC2 Instance (Vulnerable Reverse Proxy)
#############################################

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "reverse_proxy" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.ec2_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.reverse_proxy.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  key_name               = var.ssh_key_name != "" ? var.ssh_key_name : null

  # INTENTIONALLY using IMDSv1 (vulnerable configuration)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = var.use_imdsv2 ? "required" : "optional" # "optional" = IMDSv1 allowed
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh.tpl", {
    custom_message = var.custom_proxy_message
  }))

  tags = {
    Name = "${local.scenario_name}-reverse-proxy"
  }
}

#############################################
# CloudWatch Log Group (for monitoring)
#############################################

resource "aws_cloudwatch_log_group" "proxy_logs" {
  count             = var.enable_logging ? 1 : 0
  name              = "/cloud-breach-s3/${local.scenario_name}/proxy"
  retention_in_days = 7

  tags = {
    Name = "${local.scenario_name}-proxy-logs"
  }
}
