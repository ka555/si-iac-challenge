# SNS topic for alerts (if email is provided)
resource "aws_sns_topic" "alerts" {
  count = var.notification_email != "" ? 1 : 0
  name  = "s3-list-api-alerts-${random_id.suffix.hex}"

  tags = {
    Name = "s3-list-api-alerts"
  }
}

resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main_dashboard" {
  dashboard_name = "${local.function_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.s3_list_function.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.s3_list_function.function_name],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.s3_list_function.function_name],
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Lambda Function Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiName", aws_api_gateway_rest_api.s3_list_api.name],
            ["AWS/ApiGateway", "Latency", "ApiName", aws_api_gateway_rest_api.s3_list_api.name],
            ["AWS/ApiGateway", "4XXError", "ApiName", aws_api_gateway_rest_api.s3_list_api.name],
            ["AWS/ApiGateway", "5XXError", "ApiName", aws_api_gateway_rest_api.s3_list_api.name],
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "API Gateway Metrics"
          period  = 300
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 12
        width  = 24
        height = 6

        properties = {
          query  = "SOURCE '${aws_cloudwatch_log_group.lambda_logs.name}' | fields @timestamp, @message | sort @timestamp desc | limit 100"
          region = var.aws_region
          title  = "Recent Lambda Logs"
        }
      }
    ]
  })
}

# Lambda Error Rate Alarm
resource "aws_cloudwatch_metric_alarm" "lambda_error_rate" {
  alarm_name          = "${local.function_name}-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  threshold           = "5" # 5% error rate
  alarm_description   = "This metric monitors lambda error rate"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.alerts[0].arn] : []

  metric_query {
    id          = "error_rate"
    return_data = true

    metric {
      metric_name = "Errors"
      namespace   = "AWS/Lambda"
      period      = "300"
      stat        = "Sum"

      dimensions = {
        FunctionName = aws_lambda_function.s3_list_function.function_name
      }
    }
  }

  metric_query {
    id          = "invocation_count"
    return_data = false

    metric {
      metric_name = "Invocations"
      namespace   = "AWS/Lambda"
      period      = "300"
      stat        = "Sum"

      dimensions = {
        FunctionName = aws_lambda_function.s3_list_function.function_name
      }
    }
  }

  tags = {
    Name = "${local.function_name}-error-rate-alarm"
  }
}

# Lambda Duration Alarm
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "${local.function_name}-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = "10000" # 10 seconds
  alarm_description   = "This metric monitors lambda duration"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.alerts[0].arn] : []

  dimensions = {
    FunctionName = aws_lambda_function.s3_list_function.function_name
  }

  tags = {
    Name = "${local.function_name}-duration-alarm"
  }
}

# API Gateway 5XX Error Alarm
resource "aws_cloudwatch_metric_alarm" "api_gateway_5xx_errors" {
  alarm_name          = "${local.api_name}-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors API Gateway 5XX errors"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.alerts[0].arn] : []

  dimensions = {
    ApiName = aws_api_gateway_rest_api.s3_list_api.name
    Stage   = aws_api_gateway_stage.s3_list_stage.stage_name
  }

  tags = {
    Name = "${local.api_name}-5xx-errors-alarm"
  }
}

# API Gateway High Latency Alarm (Warning)
resource "aws_cloudwatch_metric_alarm" "api_gateway_latency" {
  alarm_name          = "${local.api_name}-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "Latency"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Average"
  threshold           = "2000" # 2 seconds
  alarm_description   = "This metric monitors API Gateway latency"
  treat_missing_data  = "notBreaching"

  # Only send to SNS if email is configured, otherwise just create alarm
  alarm_actions = var.notification_email != "" ? [aws_sns_topic.alerts[0].arn] : []

  dimensions = {
    ApiName = aws_api_gateway_rest_api.s3_list_api.name
    Stage   = aws_api_gateway_stage.s3_list_stage.stage_name
  }

  tags = {
    Name = "${local.api_name}-latency-alarm"
  }
}

# Lambda Throttle Alarm
resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  alarm_name          = "${local.function_name}-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors lambda throttles"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.alerts[0].arn] : []

  dimensions = {
    FunctionName = aws_lambda_function.s3_list_function.function_name
  }

  tags = {
    Name = "${local.function_name}-throttles-alarm"
  }
}

# Custom metric filter for Lambda errors in logs
resource "aws_cloudwatch_log_metric_filter" "lambda_error_filter" {
  name           = "${local.function_name}-error-filter"
  log_group_name = aws_cloudwatch_log_group.lambda_logs.name
  pattern        = "[timestamp, request_id, level=\"ERROR\", ...]"

  metric_transformation {
    name      = "LambdaErrors"
    namespace = "Custom/Lambda"
    value     = "1"

    default_value = "0"
  }
}

# Custom metric for application-specific errors
resource "aws_cloudwatch_metric_alarm" "custom_lambda_errors" {
  alarm_name          = "${local.function_name}-custom-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "LambdaErrors"
  namespace           = "Custom/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Custom metric for Lambda application errors"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.alerts[0].arn] : []

  tags = {
    Name = "${local.function_name}-custom-errors"
  }
}

# Log insights queries for troubleshooting
resource "aws_cloudwatch_query_definition" "lambda_errors_query" {
  name = "${local.function_name}-error-analysis"

  log_group_names = [
    aws_cloudwatch_log_group.lambda_logs.name
  ]

  query_string = <<EOF
fields @timestamp, @message, @requestId
| filter @message like /ERROR/
| sort @timestamp desc
| limit 20
EOF
}

resource "aws_cloudwatch_query_definition" "lambda_performance_query" {
  name = "${local.function_name}-performance-analysis"

  log_group_names = [
    aws_cloudwatch_log_group.lambda_logs.name
  ]

  query_string = <<EOF
fields @timestamp, @duration, @billedDuration, @maxMemoryUsed
| filter @type = "REPORT"
| sort @timestamp desc
| limit 50
EOF
}