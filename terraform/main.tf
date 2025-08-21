terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "strategic-imperatives-challenge"
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = "devops-team"
    }
  }
}

# Random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  function_name = "s3-list-function-${random_id.suffix.hex}"
  bucket_name   = "si-challenge-bucket-${random_id.suffix.hex}"
  api_name      = "s3-list-api-${random_id.suffix.hex}"
}

# S3 Bucket for storing files
resource "aws_s3_bucket" "app_bucket" {
  bucket = local.bucket_name
}

resource "aws_s3_bucket_versioning" "app_bucket_versioning" {
  bucket = aws_s3_bucket.app_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app_bucket_encryption" {
  bucket = aws_s3_bucket.app_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "app_bucket_pab" {
  bucket = aws_s3_bucket.app_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Add some sample objects for testing
resource "aws_s3_object" "sample_files" {
  count   = 3
  bucket  = aws_s3_bucket.app_bucket.id
  key     = "sample-file-${count.index + 1}.txt"
  content = "This is sample content for file ${count.index + 1}"

  metadata = {
    purpose = "testing"
    created = timestamp()
  }
}

# Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/list_s3_contents.py"
  output_path = "${path.module}/lambda_function.zip"
}

# Lambda function
resource "aws_lambda_function" "s3_list_function" {
  filename      = data.archive_file.lambda_zip.output_path
  function_name = local.function_name
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "list_s3_contents.lambda_handler"
  runtime       = "python3.9"
  timeout       = 30
  memory_size   = 128

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.app_bucket.id
      LOG_LEVEL   = var.log_level
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    aws_cloudwatch_log_group.lambda_logs,
  ]

  tags = {
    Name = local.function_name
  }
}

# CloudWatch log group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "s3_list_api" {
  name        = local.api_name
  description = "API for listing S3 bucket contents"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  # Enable request validation
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "execute-api:Invoke"
        Resource  = "*"
      }
    ]
  })
}

# API Gateway resource
resource "aws_api_gateway_resource" "list_bucket_resource" {
  rest_api_id = aws_api_gateway_rest_api.s3_list_api.id
  parent_id   = aws_api_gateway_rest_api.s3_list_api.root_resource_id
  path_part   = "list-bucket"
}

# API Gateway method
resource "aws_api_gateway_method" "list_bucket_method" {
  rest_api_id   = aws_api_gateway_rest_api.s3_list_api.id
  resource_id   = aws_api_gateway_resource.list_bucket_resource.id
  http_method   = "GET"
  authorization = "NONE"

  request_parameters = {
    "method.request.querystring.prefix" = false
  }
}

# API Gateway integration
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.s3_list_api.id
  resource_id = aws_api_gateway_resource.list_bucket_resource.id
  http_method = aws_api_gateway_method.list_bucket_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.s3_list_function.invoke_arn
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_list_function.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.s3_list_api.execution_arn}/*/*"
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "s3_list_deployment" {
  depends_on = [
    aws_api_gateway_method.list_bucket_method,
    aws_api_gateway_integration.lambda_integration,
  ]

  rest_api_id = aws_api_gateway_rest_api.s3_list_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.list_bucket_resource.id,
      aws_api_gateway_method.list_bucket_method.id,
      aws_api_gateway_integration.lambda_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway stage
resource "aws_api_gateway_stage" "s3_list_stage" {
  deployment_id = aws_api_gateway_deployment.s3_list_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.s3_list_api.id
  stage_name    = var.environment

  xray_tracing_enabled = true

  tags = {
    Name = "${local.api_name}-${var.environment}"
  }
}

# API Gateway method settings for throttling, caching, and basic monitoring
resource "aws_api_gateway_method_settings" "settings" {
  rest_api_id = aws_api_gateway_rest_api.s3_list_api.id
  stage_name  = aws_api_gateway_stage.s3_list_stage.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled    = true
    data_trace_enabled = false

    # Throttling settings
    throttling_rate_limit  = 1000
    throttling_burst_limit = 2000

    # Caching
    caching_enabled      = true
    cache_ttl_in_seconds = 300
  }

  depends_on = [aws_api_gateway_account.api_gateway_account]
}