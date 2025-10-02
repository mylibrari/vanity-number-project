#!/bin/bash

# Vanity Numbers Deployment Verification Script
# Run this after terraform apply to verify everything is working

set -e

echo " Verifying Vanity Numbers Deployment..."
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if we're in the right directory
if [ ! -f "main.tf" ]; then
    echo -e "${RED} Error: Run this script from the terraform directory${NC}"
    exit 1
fi

echo -e "${YELLOW} Checking Terraform Resources...${NC}"

# Get Terraform outputs
LAMBDA_FUNCTION_NAME=$(terraform output -raw lambda_function_name 2>/dev/null || echo "")
API_GATEWAY_URL=$(terraform output -raw api_gateway_url 2>/dev/null || echo "")
WEB_APP_URL=$(terraform output -raw web_app_url 2>/dev/null || echo "")
BUCKET_NAME=$(terraform output -raw web_app_bucket_name 2>/dev/null || echo "")

if [ -z "$LAMBDA_FUNCTION_NAME" ]; then
    echo -e "${RED} Terraform outputs not found. Run 'terraform apply' first.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Lambda Function: $LAMBDA_FUNCTION_NAME${NC}"
echo -e "${GREEN}✅ API Gateway URL: $API_GATEWAY_URL${NC}"
echo -e "${GREEN}✅ Web App URL: $WEB_APP_URL${NC}"
echo -e "${GREEN}✅ S3 Bucket: $BUCKET_NAME${NC}"
echo ""

echo -e "${YELLOW} Testing Lambda Function...${NC}"

# Test Lambda function
cat > test_event.json << EOF
{
  "phoneNumber": "8004384357"
}
EOF

# Invoke Lambda function
echo "Invoking Lambda function..."
if aws lambda invoke \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --payload fileb://test_event.json \
    --region us-east-1 \
    response.json > /dev/null 2>&1; then
    
    echo -e "${GREEN}✅ Lambda function executed successfully${NC}"
    
    # Check response
    if grep -q "GET" response.json 2>/dev/null; then
        echo -e "${GREEN}✅ Lambda returned vanity numbers (found 'GET' in response)${NC}"
    else
        echo -e "${YELLOW} Lambda response doesn't contain expected vanity numbers${NC}"
        echo "Response: $(cat response.json)"
    fi
else
    echo -e "${RED} Lambda function test failed${NC}"
fi

# Clean up test files
rm -f test_event.json response.json

echo ""
echo -e "${YELLOW} Testing API Gateway...${NC}"

# Test API Gateway
if curl -s "$API_GATEWAY_URL" > api_response.json; then
    if [ -s api_response.json ]; then
        echo -e "${GREEN}✅ API Gateway responding${NC}"
        
        # Check if it's valid JSON
        if jq . api_response.json > /dev/null 2>&1; then
            echo -e "${GREEN}✅ API returning valid JSON${NC}"
            
            # Check for calls array
            if jq -e '.calls' api_response.json > /dev/null 2>&1; then
                echo -e "${GREEN}✅ API response has correct structure${NC}"
            else
                echo -e "${YELLOW} API response missing 'calls' array${NC}"
            fi
        else
            echo -e "${RED} API returning invalid JSON${NC}"
            echo "Response: $(cat api_response.json)"
        fi
    else
        echo -e "${RED} API Gateway returned empty response${NC}"
    fi
else
    echo -e "${RED} API Gateway not responding${NC}"
fi

rm -f api_response.json

echo ""
echo -e "${YELLOW} Checking S3 Web App...${NC}"

# Check if web app files exist
if aws s3 ls "s3://$BUCKET_NAME/index.html" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Web app uploaded to S3${NC}"
else
    echo -e "${YELLOW} Web app not found in S3. Upload it manually:${NC}"
    echo "  aws s3 cp ../web-app/index.html s3://$BUCKET_NAME/index.html"
fi

# Test web app accessibility
echo "Testing web app accessibility..."
if curl -s -I "$WEB_APP_URL" | grep -q "200 OK"; then
    echo -e "${GREEN}✅ Web app accessible${NC}"
else
    echo -e "${YELLOW} Web app not accessible yet (S3 might need time to propagate)${NC}"
fi

echo ""
echo -e "${YELLOW} Resource Summary:${NC}"
echo "• DynamoDB Table: vanity-numbers"
echo "• Lambda Functions: 2 (converter + api)"
echo "• S3 Bucket: $BUCKET_NAME"
echo "• API Gateway: vanity-numbers-api"
echo ""

echo -e "${YELLOW} Important URLs:${NC}"
echo "• Web Dashboard: $WEB_APP_URL"
echo "• API Endpoint: $API_GATEWAY_URL"
echo "• Lambda ARN (for Connect): $(terraform output -raw lambda_function_arn)"
echo ""


echo -e "${GREEN} Verification complete!${NC}"

# Check overall status
ERRORS=0

# Check if Lambda test passed
if ! grep -q "GET" response.json 2>/dev/null && [ -f response.json ]; then
    ERRORS=$((ERRORS + 1))
fi

# Check if API is working
if ! curl -s "$API_GATEWAY_URL" | jq -e '.calls' > /dev/null 2>&1; then
    ERRORS=$((ERRORS + 1))
fi

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN} All systems operational! Ready for Amazon Connect setup.${NC}"
else
    echo -e "${YELLOW} Some issues detected. Check the logs above for details.${NC}"
fi