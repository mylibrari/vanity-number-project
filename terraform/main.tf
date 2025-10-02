
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# DynamoDB Table for storing vanity numbers
resource "aws_dynamodb_table" "vanity_numbers" {
  name           = "vanity-numbers"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "phoneNumber"

  attribute {
    name = "phoneNumber"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  global_secondary_index {
    name               = "TimestampIndex"
    hash_key           = "timestamp"
    projection_type    = "ALL"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    Name        = "vanity-numbers-table"
    Environment = var.environment
    Project     = "vanity-phone-numbers"
  }
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "vanity-numbers-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for Lambda function
resource "aws_iam_role_policy" "lambda_policy" {
  name = "vanity-numbers-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.vanity_numbers.arn,
          "${aws_dynamodb_table.vanity_numbers.arn}/*"
        ]
      }
    ]
  })
}

# Create deployment package for Lambda
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

# Lambda function
resource "aws_lambda_function" "vanity_numbers_lambda" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "vanity-numbers-converter"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = 60
  memory_size     = 512

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.vanity_numbers.name
    }
  }

  tags = {
    Name        = "vanity-numbers-lambda"
    Environment = var.environment
    Project     = "vanity-phone-numbers"
  }
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.vanity_numbers_lambda.function_name}"
  retention_in_days = 7
}

# Lambda permission for Amazon Connect
resource "aws_lambda_permission" "allow_connect" {
  statement_id  = "AllowExecutionFromConnect"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.vanity_numbers_lambda.function_name
  principal     = "connect.amazonaws.com"
  
  # In production, you would specify the Connect instance ARN
  # source_arn = "arn:aws:connect:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/${var.connect_instance_id}/*"
}

# S3 bucket for web app hosting (bonus feature)
resource "aws_s3_bucket" "web_app" {
  bucket = "vanity-numbers-web-app-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "vanity-numbers-web-app"
    Environment = var.environment
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "web_app_versioning" {
  bucket = aws_s3_bucket.web_app.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "web_app_encryption" {
  bucket = aws_s3_bucket.web_app.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "web_app_pab" {
  bucket = aws_s3_bucket.web_app.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# S3 bucket policy for web hosting
resource "aws_s3_bucket_policy" "web_app_policy" {
  bucket = aws_s3_bucket.web_app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = "s3:GetObject"
        Resource = "${aws_s3_bucket.web_app.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.web_app_pab]
}

resource "aws_s3_bucket_website_configuration" "web_app_website" {
  bucket = aws_s3_bucket.web_app.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

# API Gateway for web app to access DynamoDB
resource "aws_api_gateway_rest_api" "vanity_api" {
  name        = "vanity-numbers-api"
  description = "API for vanity numbers web app"
}

# API Gateway resource
resource "aws_api_gateway_resource" "vanity_api_resource" {
  parent_id   = aws_api_gateway_rest_api.vanity_api.root_resource_id
  path_part   = "recent-calls"
  rest_api_id = aws_api_gateway_rest_api.vanity_api.id
}

# API Gateway method
resource "aws_api_gateway_method" "vanity_api_method" {
  authorization = "NONE"
  http_method   = "GET"
  resource_id   = aws_api_gateway_resource.vanity_api_resource.id
  rest_api_id   = aws_api_gateway_rest_api.vanity_api.id
}

# API Gateway CORS method (OPTIONS)
resource "aws_api_gateway_method" "vanity_api_options" {
  authorization = "NONE"
  http_method   = "OPTIONS"
  resource_id   = aws_api_gateway_resource.vanity_api_resource.id
  rest_api_id   = aws_api_gateway_rest_api.vanity_api.id
}

# CORS integration
resource "aws_api_gateway_integration" "vanity_api_options_integration" {
  http_method = aws_api_gateway_method.vanity_api_options.http_method
  resource_id = aws_api_gateway_resource.vanity_api_resource.id
  rest_api_id = aws_api_gateway_rest_api.vanity_api.id
  type        = "MOCK"
  
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

# CORS method response
resource "aws_api_gateway_method_response" "vanity_api_options_response" {
  rest_api_id = aws_api_gateway_rest_api.vanity_api.id
  resource_id = aws_api_gateway_resource.vanity_api_resource.id
  http_method = aws_api_gateway_method.vanity_api_options.http_method
  status_code = "200"
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# CORS integration response
resource "aws_api_gateway_integration_response" "vanity_api_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.vanity_api.id
  resource_id = aws_api_gateway_resource.vanity_api_resource.id
  http_method = aws_api_gateway_method.vanity_api_options.http_method
  status_code = aws_api_gateway_method_response.vanity_api_options_response.status_code
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# API Gateway method response for GET
resource "aws_api_gateway_method_response" "vanity_api_method_response" {
  rest_api_id = aws_api_gateway_rest_api.vanity_api.id
  resource_id = aws_api_gateway_resource.vanity_api_resource.id
  http_method = aws_api_gateway_method.vanity_api_method.http_method
  status_code = "200"
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

# API Gateway integration response for GET
resource "aws_api_gateway_integration_response" "vanity_api_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.vanity_api.id
  resource_id = aws_api_gateway_resource.vanity_api_resource.id
  http_method = aws_api_gateway_method.vanity_api_method.http_method
  status_code = "200"
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
  
  depends_on = [aws_api_gateway_integration.vanity_api_integration]
}
resource "aws_lambda_function" "api_lambda" {
  filename         = data.archive_file.api_lambda_zip.output_path
  function_name    = "vanity-numbers-api"
  role            = aws_iam_role.api_lambda_role.arn
  handler         = "api_lambda.lambda_handler"
  runtime         = "python3.9"
  timeout         = 30

  source_code_hash = data.archive_file.api_lambda_zip.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.vanity_numbers.name
    }
  }
}

data "archive_file" "api_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/api_lambda.py"
  output_path = "${path.module}/api_lambda.zip"
}

# IAM role for API Lambda
resource "aws_iam_role" "api_lambda_role" {
  name = "vanity-numbers-api-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "api_lambda_policy" {
  name = "vanity-numbers-api-lambda-policy"
  role = aws_iam_role.api_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:Scan",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.vanity_numbers.arn,
          "${aws_dynamodb_table.vanity_numbers.arn}/*"
        ]
      }
    ]
  })
}

# API Gateway integration
resource "aws_api_gateway_integration" "vanity_api_integration" {
  http_method             = aws_api_gateway_method.vanity_api_method.http_method
  resource_id             = aws_api_gateway_resource.vanity_api_resource.id
  rest_api_id             = aws_api_gateway_rest_api.vanity_api.id
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api_lambda.invoke_arn
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.vanity_api.execution_arn}/*/*"
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "vanity_api_deployment" {
  depends_on = [
    aws_api_gateway_method.vanity_api_method,
    aws_api_gateway_method.vanity_api_options,
    aws_api_gateway_integration.vanity_api_integration,
    aws_api_gateway_integration.vanity_api_options_integration,
    aws_api_gateway_method_response.vanity_api_method_response,
    aws_api_gateway_method_response.vanity_api_options_response,
    aws_api_gateway_integration_response.vanity_api_integration_response,
    aws_api_gateway_integration_response.vanity_api_options_integration_response,
  ]

  rest_api_id = aws_api_gateway_rest_api.vanity_api.id
  stage_name  = "prod"
  
  # Force deployment on every apply
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.vanity_api_resource.id,
      aws_api_gateway_method.vanity_api_method.id,
      aws_api_gateway_integration.vanity_api_integration.id,
    ]))
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

# All outputs are defined in outputs.tf