#!/bin/bash

set -e

ENVIRONMENT=${1:-dev}
AWS_REGION=${2:-us-east-1}
NOTIFICATION_EMAIL=${3:-""}
TERRAFORM_DIR="$(dirname "$0")/../terraform"

if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
    echo "Error: Environment must be one of: dev, staging, prod"
    exit 1
fi

echo "Starting deployment to ${ENVIRONMENT} environment"
echo "Region: $AWS_REGION"

if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed"
    exit 1
fi

if ! aws sts get-caller-identity &> /dev/null; then
    echo "Error: AWS credentials not configured or invalid"
    exit 1
fi

if ! command -v terraform &> /dev/null; then
    echo "Error: Terraform is not installed"
    exit 1
fi

cd "$TERRAFORM_DIR"

terraform init

if ! terraform fmt -check; then
    terraform fmt
fi

terraform validate

PLAN_FILE="${ENVIRONMENT}-plan-$(date +%Y%m%d-%H%M%S)"

terraform plan \
    -var="environment=$ENVIRONMENT" \
    -var="aws_region=$AWS_REGION" \
    -var="notification_email=$NOTIFICATION_EMAIL" \
    -out="$PLAN_FILE"

if [ "$ENVIRONMENT" = "prod" ]; then
    echo "WARNING: You are about to deploy to PRODUCTION!"
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo "Deployment cancelled."
        rm "$PLAN_FILE"
        exit 0
    fi
fi

terraform apply "$PLAN_FILE"
rm "$PLAN_FILE"

API_URL=$(terraform output -raw api_gateway_endpoint)
LAMBDA_NAME=$(terraform output -raw lambda_function_name)
BUCKET_NAME=$(terraform output -raw s3_bucket_name)

echo "Deployment completed successfully!"
echo "Environment: $ENVIRONMENT"
echo "API Gateway URL: $API_URL"
echo "Lambda Function: $LAMBDA_NAME"
echo "S3 Bucket: $BUCKET_NAME"

sleep 30

if curl -f -s "$API_URL" > /dev/null; then
    echo "API endpoint test passed"
else
    echo "API endpoint test failed"
fi

if aws lambda invoke \
    --function-name "$LAMBDA_NAME" \
    --payload '{"queryStringParameters": {"max_keys": "5"}}' \
    --region "$AWS_REGION" \
    response.json > /dev/null 2>&1; then
    echo "Lambda function test passed"
    rm -f response.json
else
    echo "Lambda function test failed"
fi

echo "Test your API:"
echo "curl '$API_URL'"
echo "curl '$API_URL?prefix=sample'"