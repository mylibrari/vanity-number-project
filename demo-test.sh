#!/bin/bash
set -e

# Terraform working directory
TERRAFORM_DIR="terraform"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Step 1: Fix Web App Data Loading Issues
echo -e "${BLUE} Fixing Web App Data Loading Issues${NC}"
echo ""

# Get configuration values from Terraform
API_URL=$(terraform -chdir=$TERRAFORM_DIR output -raw api_gateway_url)
BUCKET_NAME=$(terraform -chdir=$TERRAFORM_DIR output -raw web_app_bucket_name)
WEB_APP_URL=$(terraform -chdir=$TERRAFORM_DIR output -raw web_app_url)
REST_API_ID=$(terraform -chdir=$TERRAFORM_DIR output -raw api_gateway_rest_api_id)
LAMBDA_NAME=$(terraform -chdir=$TERRAFORM_DIR output -raw lambda_function_name 2>/dev/null)

echo -e "${YELLOW} Current Configuration:${NC}"
echo "API URL: $API_URL"
echo "Bucket: $BUCKET_NAME"
echo "Web App URL: $WEB_APP_URL"
echo "Lambda Function: $LAMBDA_NAME"
echo ""

# Ensure web-app directory exists
mkdir -p web-app

# Download the web app index.html
echo -e "${YELLOW} Downloading index.html from S3 bucket...${NC}"
aws s3 cp s3://$BUCKET_NAME/index.html web-app/index.html

echo -e "${YELLOW} Updating API URL inside index.html...${NC}"
sed -i "s|https://ki7ywrkip6.execute-api.us-east-1.amazonaws.com/prod/recent-calls|$API_URL|g" web-app/index.html

# Upload fixed file back to S3 (no ACLs since bucket owner enforced)
echo -e "${YELLOW} Uploading fixed index.html back to S3...${NC}"
aws s3 cp web-app/index.html s3://$BUCKET_NAME/index.html

# Clean up local copy
rm web-app/index.html

echo -e "${GREEN}✅ Web app updated successfully!${NC}"
echo -e "🌐 Test it here: ${WEB_APP_URL}"
echo ""

# Step 2: Create Demo Data for Dashboard
echo -e "${BLUE}📊 Creating Demo Data for Web Dashboard${NC}"

# Famous phone numbers that make great vanity numbers
DEMO_NUMBERS=(
    "9004384357"  # 800-GET-HELP
    "8772255374"  # 877-CALL-FAIR  
    "8006282537"  # 800-MATTERS
    "5552665464"  # 555-BOOKING
    "8007653968"  # 800-POKEMON
    "8004663872"  # 800-FLOWERS
    "8002255937"  # 800-CALL-WER
    "7777464637"  # 777-PLUMBER
)

if [ -z "$LAMBDA_NAME" ]; then
    echo -e "${RED} Terraform not deployed. Run terraform apply first.${NC}"
    exit 1
fi

echo -e "${YELLOW}🎭 Simulating phone calls over time...${NC}"

for number in "${DEMO_NUMBERS[@]}"; do
    echo -e "${BLUE}📞 Simulating call from: $number${NC}"
    
    # Create test event
    cat > demo_event.json << EOF
{
  "phoneNumber": "$number",
  "Details": {
    "ContactData": {
      "CustomerEndpoint": {
        "Address": "+1$number"
      }
    }
  }
}
EOF
    
    # Invoke Lambda to create realistic data
    aws lambda invoke \
        --function-name "$LAMBDA_NAME" \
        --payload fileb://demo_event.json \
        --region us-east-1 \
        demo_response.json > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        SPEECH=$(jq -r '.body.speech' demo_response.json 2>/dev/null)
        echo -e "${GREEN}✅ Added: $SPEECH${NC}"
    else
        echo -e "${RED} Failed to add demo data for $number${NC}"
    fi
    
    # Small delay to create realistic timestamps
    sleep 2
done

# Clean up temp files
rm -f demo_event.json demo_response.json

echo ""
echo -e "${GREEN} Demo data created!${NC}"
echo -e "${YELLOW} Check your web dashboard:${NC}"
echo "$WEB_APP_URL"
echo ""
echo -e "${YELLOW}📊 Or test the API directly:${NC}"
echo "curl $API_URL"
