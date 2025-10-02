
output "lambda_function_arn" {
  description = "ARN of the vanity numbers Lambda function"
  value       = aws_lambda_function.vanity_numbers_lambda.arn
}

output "lambda_function_name" {
  description = "Name of the vanity numbers Lambda function"
  value       = aws_lambda_function.vanity_numbers_lambda.function_name
}

output "api_lambda_function_arn" {
  description = "ARN of the API Lambda function"
  value       = aws_lambda_function.api_lambda.arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.vanity_numbers.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.vanity_numbers.arn
}

output "web_app_bucket_name" {
  description = "Name of the S3 bucket hosting the web app"
  value       = aws_s3_bucket.web_app.bucket
}

output "web_app_url" {
  description = "URL of the hosted web application"
  value       = "http://${aws_s3_bucket.web_app.bucket}.s3-website-${data.aws_region.current.name}.amazonaws.com"
}

output "api_gateway_url" {
  description = "URL of the API Gateway endpoint"
  value       = "${aws_api_gateway_deployment.vanity_api_deployment.invoke_url}/recent-calls"
}

output "api_gateway_rest_api_id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.vanity_api.id
}

output "region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

# Instructions for Amazon Connect setup
output "connect_setup_instructions" {
  description = "Instructions for setting up Amazon Connect"
  value = <<-EOT
    
    ===== AMAZON CONNECT SETUP INSTRUCTIONS =====
    
    1. Create Amazon Connect Instance:
       - Go to AWS Console > Amazon Connect
       - Click 'Add an instance'
       - Choose 'Store users in Amazon Connect'
       - Provide instance alias: 'vanity-numbers-${random_id.bucket_suffix.hex}'
       - Create administrator account
    
    2. Claim Phone Number:
       - In Connect console, go to 'Phone numbers'
       - Click 'Claim a number'
       - Choose your country and number type
       - Select a phone number
    
    3. Create Contact Flow:
       - Go to 'Contact flows'
       - Click 'Create contact flow'
       - Import the contact flow from connect-flow.json
       - Update Lambda function ARN to: ${aws_lambda_function.vanity_numbers_lambda.arn}
       - Save and publish the flow
    
    4. Associate Contact Flow with Phone Number:
       - Go to 'Phone numbers'
       - Edit your claimed number
       - Set contact flow to your vanity numbers flow
       - Save
    
    ===== LAMBDA FUNCTION ARN FOR CONNECT =====
    ${aws_lambda_function.vanity_numbers_lambda.arn}
    
    ===== WEB DASHBOARD URL =====
    http://${aws_s3_bucket.web_app.bucket}.s3-website-${data.aws_region.current.name}.amazonaws.com
    
    ===== API ENDPOINT =====
    ${aws_api_gateway_deployment.vanity_api_deployment.invoke_url}/recent-calls
    
  EOT
}

# Terraform configuration info
output "terraform_version_info" {
  description = "Terraform version information"
  value = {
    terraform_version = ">=1.0"
    aws_provider      = "~>5.0"
    region           = data.aws_region.current.name
  }
}

# Resource counts for monitoring
output "resource_summary" {
  description = "Summary of deployed resources"
  value = {
    lambda_functions = 2
    dynamodb_tables  = 1
    s3_buckets      = 1
    api_gateways    = 1
    iam_roles       = 2
    cloudwatch_logs = 1
  }
}