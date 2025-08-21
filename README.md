# Strategic Imperatives DevOps Challenge

## Solution Overview

This solution deploys a serverless application on AWS that lists S3 bucket contents via API Gateway. The infrastructure is provisioned using Terraform with a complete CI/CD pipeline and monitoring setup.

**Architecture**: Internet → API Gateway → Lambda Function → S3 Bucket

## Project Structure

```
.
├── terraform/              # Infrastructure as Code (Terraform)
│   ├── main.tf             # Main infrastructure resources
│   ├── variables.tf        # Input variables
│   ├── outputs.tf          # Output values
│   ├── iam.tf              # IAM roles and policies
│   └── monitoring.tf       # CloudWatch monitoring
├── lambda/                 # Lambda function code
│   ├── list_s3_contents.py # Main function
│   ├── test_function.py    # Unit tests
│   └── requirements.txt    # Python dependencies
├── .github/workflows/      # CI/CD pipeline
│   └── deploy.yml          # GitHub Actions workflow
├── scripts/                # Deployment scripts
│   ├── deploy.sh           # Manual deployment
│   └── rollback.sh         # Rollback script
├── Makefile                # Automation commands
└── README.md               # This file
```

1. **Prerequisites**
    - AWS CLI configured
    - Terraform >= 1.0
    - Python 3.9+

2. **Setup**
   ```bash
   pyenv install 3.9.19
   pyenv local 3.9.19
   python --version
   ```

3. **Deploy (Choose your method)**
   ```bash
   # Method 1: Using Make (Recommended)
   make setup          # Verify prerequisites
   make dev-up         # Deploy to development
   
   # Method 2: Manual Terraform
   cd terraform
   terraform init
   terraform plan -var="environment=dev"
   terraform apply
   ```

4. **Test**
   ```bash
   # Using Make
   make test-api
   
   # Or manual
   curl $(terraform output -raw api_gateway_endpoint)
   cd lambda && python3 -m pytest test_function.py -v
   ```

## Infrastructure as Code (Terraform)

### Components Provisioned

**API Gateway**
- REST API with `/list-bucket` endpoint
- Request throttling (1000 requests/sec, 2000 burst)
- CloudWatch logging enabled
- Caching configured (5 minutes TTL)

**Lambda Function**
- Python 3.9 runtime
- 128MB memory, 30 second timeout
- Environment variables & error handling

**S3 Bucket**
- Private bucket with versioning enabled
- Server-side encryption
- Public access blocked
- Sample files for testing

**IAM Roles & Policies**
- Lambda execution role with least privilege
- S3 read-only permissions for specified bucket
- CloudWatch logging permissions
- Resource-based bucket policy

## CI/CD Pipeline

### Tool Choice: GitHub Actions
**Justification**: Native GitHub integration, no additional infrastructure required, supports multi-environment deployments, built-in secrets management.

### Pipeline Stages

1. **Validate**
    - Terraform format check and validation
    - Python code linting and testing
    - Security scanning with tfsec

2. **Plan**
    - Generate Terraform execution plan
    - Review infrastructure changes
    - Artifact storage for deployment

3. **Deploy**
    - Development: Auto-deploy on develop branch
    - Staging: Auto-deploy on main branch
    - Production: Manual approval required

4. **Test**
    - Automated Smoke tests against deployed API
    - Automated Health checks and validation
    - Automated Integration testing

5. **Rollback**
    - Automatic rollback on deployment failure
    - Manual rollback capability via scripts
    - State backup and recovery

### Deployment Strategy
- **Environment Separation**: dev → staging → prod promotion
- **Validation Gates**: Automated testing and manual approvals
- **Rollback**: Previous version restoration within 5 minutes

## Observability and Monitoring

### Dashboarding

**CloudWatch Dashboards** displaying:
- API Gateway: Request count, latency (P50/P95), error rates, throttling
- Lambda: Invocations, duration, errors, concurrent executions
- S3: Request metrics, error rates
- Custom business metrics: Bucket listing success rates

### Alerting Strategy

**Critical Alerts** (immediate response required):
- Lambda error rate > 5% over 5 minutes
- API Gateway 5xx errors > 10 in 5 minutes
- Lambda function timeouts or memory exhaustion

**Warning Alerts** (monitoring required):
- API latency > 2 seconds (P95)
- Throttling detected
- Unusual traffic patterns (>200% baseline)

**Actionable vs Noisy Alerts**:
- Actionable: Affect user experience or indicate system failure
- Noisy: Filtered using metrics, thresholds, and time windows
- Implementation: CloudWatch composite alarms and metric filters

### Tools Used
- **AWS CloudWatch**: Metrics, logs, dashboards, alarms
- **AWS X-Ray**: Distributed tracing (enabled)
- **Custom Log Queries**: CloudWatch Insights for troubleshooting
- **SNS Integration**: Email/Slack notifications for critical alerts

## Security Considerations

### Implemented Security Measures

1. **Identity & Access Management**
    - Least privilege IAM policies
    - Resource-based S3 bucket policies
    - No hardcoded credentials

2. **Data Protection**
    - S3 server-side encryption
    - HTTPS only (TLS 1.2+) for API Gateway
    - No sensitive data in logs

3. **Network Security**
    - Private S3 bucket (public access blocked)
    - API Gateway rate limiting and throttling
    - Request validation enabled

4. **Monitoring & Compliance**
    - Comprehensive CloudWatch logging
    - API access logging
    - X-Ray tracing for audit trails

### Security Hardening Recommendations

**Short-term (Production Ready)**:
- Deploy Lambda in VPC with private subnets
- Add AWS WAF for API Gateway protection
- Implement API key authentication
- Enable AWS Config for compliance monitoring

**Medium-term (Enhanced Security)**:
- AWS Secrets Manager for sensitive configuration
- VPC Flow Logs for network monitoring
- AWS CloudTrail for API audit logging
- Lambda environment variables encryption

**Long-term (Enterprise Security)**:
- AWS Security Hub integration
- Regular penetration testing
- SAST/DAST integration in CI/CD
- AWS GuardDuty for threat detection
- Compliance frameworks (SOC 2, PCI DSS)

### Additional Access Controls
- Multi-factor authentication for admin access
- Resource tagging for cost allocation and governance
- Regular access reviews and key rotation

## Usage

### Make Commands (Recommended)

**Environment Management:**
```bash
make help           # Show all available commands
make setup          # Verify prerequisites (AWS CLI, Terraform, etc.)
make dev-up         # Deploy to development environment  
make staging-up     # Deploy to staging environment
make prod-up        # Deploy to production environment
make dev-down       # Destroy development environment
```

**Development & Testing:**
```bash
make test           # Run Lambda function unit tests
make test-api       # Test the deployed API endpoint
make lint           # Validate and format Terraform code
make security-scan  # Run security scans (tfsec, checkov)
make clean          # Clean up temporary files
```

**Fine-grained Control:**
```bash
make init           # Initialize Terraform
make plan ENV=dev   # Create Terraform plan for specific environment
make apply ENV=dev  # Apply Terraform plan for specific environment
make destroy ENV=dev # Destroy specific environment (with confirmation)
```

### Manual Terraform Commands
```bash
# Deploy to specific environment with custom settings
cd terraform
terraform plan -var="environment=staging" -var="notification_email=admin@company.com"
terraform apply

# Test the API
API_URL=$(terraform output -raw api_gateway_endpoint)
curl "$API_URL"                    # List all objects
curl "$API_URL?prefix=sample"      # Filter by prefix
curl "$API_URL?max_keys=5"         # Limit results
```

### Testing
```bash
# Run Python tests locally
cd lambda
python3 -m pytest test_function.py -v

# Test Lambda directly via AWS CLI
aws lambda invoke --function-name $(terraform output -raw lambda_function_name) output.json
cat output.json
```

## Troubleshooting

**Common Issues**:
- Permission denied: Check IAM roles and AWS credentials
- Lambda timeout: Increase timeout or optimize code
- API throttling: Adjust throttle limits in API Gateway
- Deployment failures: Check CloudWatch logs for details

**Debug Commands**:
```bash
# View Lambda logs
aws logs tail /aws/lambda/$(terraform output -raw lambda_function_name) --follow

# Check API Gateway logs  
aws logs describe-log-groups --log-group-name-prefix API-Gateway

# Test function directly
aws lambda invoke --function-name $(terraform output -raw lambda_function_name) --payload '{}' response.json
```


**Infrastructure**: Fully automated with Terraform  
**Security**: Production-ready with additional hardening recommendations  
**Monitoring**: Comprehensive observability with actionable alerting  
**CI/CD**: Complete pipeline with validation and rollback capabilities

# This is a test comment