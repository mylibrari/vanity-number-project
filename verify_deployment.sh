#!/bin/bash
set -e

# Terraform working directory
TERRAFORM_DIR="terraform"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo " Verifying Vanity Numbers Deployment..."
echo ""

echo -e "${YELLOW} Checking Terraform Outputs...${NC}"

# Query outputs safely
LAMBDA_FUNCTION_NAME=$(terraform -chdir=$TERRAFORM_DIR output -raw lambda_function_name 2>/dev/null || echo "")
API_GATEWAY_URL=$(terraform -chdir=$TERRAFORM_DIR output -raw api_gateway_url 2>/dev/null || echo "")
WEB_APP_URL=$(terraform -chdir=$TERRAFORM_DIR output -raw web_app_url 2>/dev/null || echo "")
BUCKET_NAME=$(terraform -chdir=$TERRAFORM_DIR output -raw web_app_bucket_name 2>/dev/null || echo "")

echo -e "Lambda: ${LAMBDA_FUNCTION_NAME:-N/A}"
echo -e "API Gateway: ${API_GATEWAY_URL:-N/A}"
echo -e "Web App: ${WEB_APP_URL:-N/A}"
echo -e "S3 Bucket: ${BUCKET_NAME:-N/A}"
echo ""

# Verify Lambda exists
if [ -n "$LAMBDA_FUNCTION_NAME" ]; then
    echo -e "${YELLOW} Checking Lambda function...${NC}"
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Lambda function is deployed!${NC}"
    else
        echo -e "${RED} Lambda function not found!${NC}"
    fi
fi

# Verify API Gateway works
if [ -n "$API_GATEWAY_URL" ]; then
    echo -e "${YELLOW} Testing API Gateway endpoint...${NC}"
    if curl -s --fail "$API_GATEWAY_URL" >/dev/null; then
        echo -e "${GREEN}✅ API Gateway is responding!${NC}"
    else
        echo -e "${RED} API Gateway is not reachable!${NC}"
    fi
fi

# Verify Web App works
if [ -n "$WEB_APP_URL" ]; then
    echo -e "${YELLOW} Testing Web App URL...${NC}"
    if curl -s --fail "$WEB_APP_URL" >/dev/null; then
        echo -e "${GREEN}✅ Web App is accessible!${NC}"
    else
        echo -e "${RED} Web App is not reachable!${NC}"
    fi
fi

echo ""
echo -e "${GREEN} Verification complete!${NC}"
