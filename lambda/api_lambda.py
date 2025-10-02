import json
import boto3
import logging
from datetime import datetime
from decimal import Decimal

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize DynamoDB client
dynamodb = boto3.resource('dynamodb')
table_name = 'vanity-numbers'

def lambda_handler(event, context):
    """
    API Lambda handler to get recent vanity number calls
    """
    try:
        logger.info(f"Received API request: {json.dumps(event)}")
        
        # Get recent calls from DynamoDB
        recent_calls = get_recent_calls()
        
        response = {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'GET,OPTIONS',
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'calls': recent_calls
            }, cls=DecimalEncoder)
        }
        
        return response
        
    except Exception as e:
        logger.error(f"Error processing API request: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'error': 'Internal server error'
            })
        }

def get_recent_calls(limit=5):
    """
    Get the 5 most recent vanity number calls
    """
    try:
        table = dynamodb.Table(table_name)
        
        # Scan table and sort by timestamp (in production, would use GSI)
        response = table.scan(
            ProjectionExpression='phoneNumber, vanityNumbers, #ts',
            ExpressionAttributeNames={'#ts': 'timestamp'}
        )
        
        items = response['Items']
        
        # Sort by timestamp (newest first)
        items.sort(key=lambda x: x.get('timestamp', ''), reverse=True)
        
        # Return top 5
        recent_calls = []
        for item in items[:limit]:
            call_data = {
                'phoneNumber': format_phone_number(item['phoneNumber']),
                'vanityNumbers': item.get('vanityNumbers', [])[:3],  # Top 3
                'timestamp': item.get('timestamp', ''),
                'timeAgo': time_ago(item.get('timestamp', ''))
            }
            recent_calls.append(call_data)
            
        return recent_calls
        
    except Exception as e:
        logger.error(f"Error getting recent calls: {str(e)}")
        return []

def format_phone_number(phone_number):
    """
    Format phone number for display
    """
    if len(phone_number) == 10:
        return f"({phone_number[:3]}) {phone_number[3:6]}-{phone_number[6:]}"
    return phone_number

def time_ago(timestamp_str):
    """
    Calculate time ago from timestamp
    """
    try:
        timestamp = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
        now = datetime.now(timestamp.tzinfo)
        diff = now - timestamp
        
        if diff.days > 0:
            return f"{diff.days} day{'s' if diff.days > 1 else ''} ago"
        elif diff.seconds > 3600:
            hours = diff.seconds // 3600
            return f"{hours} hour{'s' if hours > 1 else ''} ago"
        elif diff.seconds > 60:
            minutes = diff.seconds // 60
            return f"{minutes} minute{'s' if minutes > 1 else ''} ago"
        else:
            return "Just now"
            
    except Exception as e:
        return "Unknown"

class DecimalEncoder(json.JSONEncoder):
    """
    JSON encoder for DynamoDB Decimal types
    """
    def default(self, o):
        if isinstance(o, Decimal):
            return float(o)
        return super(DecimalEncoder, self).default(o)