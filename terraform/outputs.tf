output "api_gateway_url" {
  description = "URL of the API Gateway endpoint"
  value       = "https://${aws_api_gateway_rest_api.s3_list_api.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.s3_list_stage.stage_name}"
}

output "api_gateway_endpoint" {
  description = "Full endpoint URL for listing bucket contents"
  value       = "https://${aws_api_gateway_rest_api.s3_list_api.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.s3_list_stage.stage_name}/list-bucket"
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.s3_list_function.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.s3_list_function.arn
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.app_bucket.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.app_bucket.arn
}

output "api_gateway_id" {
  description = "ID of the API Gateway"
  value       = aws_api_gateway_rest_api.s3_list_api.id
}

output "cloudwatch_log_group_lambda" {
  description = "CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

# Useful for testing and debugging
output "test_curl_command" {
  description = "Curl command to test the API"
  value       = "curl -X GET '${aws_api_gateway_rest_api.s3_list_api.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.s3_list_stage.stage_name}/list-bucket'"
}

output "aws_cli_test_command" {
  description = "AWS CLI command to test Lambda function directly"
  value       = "aws lambda invoke --function-name ${aws_lambda_function.s3_list_function.function_name} output.json && cat output.json"
}

# Dashboard URL (if monitoring.tf creates dashboard)
output "cloudwatch_dashboard_url" {
  description = "URL to CloudWatch dashboard"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${local.function_name}-dashboard"
}

output "resource_summary" {
  description = "Summary of created resources"
  value = {
    api_gateway = {
      name  = aws_api_gateway_rest_api.s3_list_api.name
      id    = aws_api_gateway_rest_api.s3_list_api.id
      stage = aws_api_gateway_stage.s3_list_stage.stage_name
    }
    lambda = {
      name    = aws_lambda_function.s3_list_function.function_name
      runtime = aws_lambda_function.s3_list_function.runtime
      timeout = aws_lambda_function.s3_list_function.timeout
    }
    s3_bucket = {
      name       = aws_s3_bucket.app_bucket.id
      versioning = "Enabled"
      encryption = "AES256"
    }
  }
}