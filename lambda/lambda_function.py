import json
import boto3
import logging
from typing import List, Dict, Tuple
from datetime import datetime
import re

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize DynamoDB client
dynamodb = boto3.resource('dynamodb')
table_name = 'vanity-numbers'

# Phone keypad mapping
PHONE_KEYPAD = {
    '2': 'ABC', '3': 'DEF', '4': 'GHI', '5': 'JKL',
    '6': 'MNO', '7': 'PQRS', '8': 'TUV', '9': 'WXYZ'
}

# Common English words for scoring (simplified list - in production would use larger dictionary)
COMMON_WORDS = {
    'HELP', 'CALL', 'CARE', 'LOVE', 'GOOD', 'BEST', 'FAST', 'EASY', 'COOL', 'NICE',
    'FOOD', 'BOOK', 'PLAY', 'WORK', 'HOME', 'SHOP', 'DEAL', 'SALE', 'FREE', 'GIFT',
    'CAKE', 'BIKE', 'GAME', 'TALK', 'WALK', 'RICH', 'LUCK', 'HOPE', 'LIFE', 'TIME'
}

def lambda_handler(event, context):
    """
    Main Lambda handler for Amazon Connect integration
    """
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        # Extract phone number from Amazon Connect event
        phone_number = extract_phone_number(event)
        if not phone_number:
            return create_connect_response("Sorry, I couldn't process your phone number.")
        
        logger.info(f"Processing phone number: {phone_number}")
        
        # Generate vanity numbers
        vanity_numbers = generate_vanity_numbers(phone_number)
        
        # Get best 5 vanity numbers
        best_vanity_numbers = rank_vanity_numbers(vanity_numbers)[:5]
        
        # Save to DynamoDB
        save_to_dynamodb(phone_number, best_vanity_numbers)
        
        # Return top 3 for Amazon Connect to speak
        top_3_formatted = format_for_speech(best_vanity_numbers[:3])
        
        return create_connect_response(
            f"Your phone number can be remembered as: {top_3_formatted}"
        )
        
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        return create_connect_response("Sorry, there was an error processing your request.")

def extract_phone_number(event: Dict) -> str:
    """
    Extract phone number from Amazon Connect event
    """
    try:
        # Amazon Connect passes customer endpoint in different formats
        customer_number = None
        
        # Try different event structures
        if 'Details' in event and 'ContactData' in event['Details']:
            contact_data = event['Details']['ContactData']
            if 'CustomerEndpoint' in contact_data:
                customer_number = contact_data['CustomerEndpoint']['Address']
        
        # Alternative structure
        elif 'customerNumber' in event:
            customer_number = event['customerNumber']
            
        # For testing purposes
        elif 'phoneNumber' in event:
            customer_number = event['phoneNumber']
            
        if customer_number:
            # Clean phone number - remove +1, spaces, dashes, etc.
            cleaned = re.sub(r'[^\d]', '', customer_number)
            # Take last 10 digits for US numbers
            if len(cleaned) >= 10:
                return cleaned[-10:]
                
        return None
        
    except Exception as e:
        logger.error(f"Error extracting phone number: {str(e)}")
        return None

def generate_vanity_numbers(phone_number: str) -> List[str]:
    """
    Generate all possible vanity number combinations
    """
    # Take last 7 digits (excluding area code for vanity conversion)
    # In production, you might want to convert area code too
    digits = phone_number[-7:]  # Last 7 digits
    area_code = phone_number[:3]
    
    logger.info(f"Generating vanity numbers for digits: {digits}")
    
    combinations = generate_combinations(digits)
    
    # Format as full phone numbers
    vanity_numbers = []
    for combo in combinations[:100]:  # Limit to prevent timeout
        vanity_number = f"{area_code}-{combo[:3]}-{combo[3:]}"
        vanity_numbers.append(vanity_number)
    
    return vanity_numbers

def generate_combinations(digits: str) -> List[str]:
    """
    Generate letter combinations for phone digits
    """
    if not digits:
        return ['']
    
    result = []
    
    def backtrack(index: int, current: str):
        if index == len(digits):
            result.append(current)
            return
            
        digit = digits[index]
        if digit in PHONE_KEYPAD:
            for letter in PHONE_KEYPAD[digit]:
                backtrack(index + 1, current + letter)
        else:
            # Keep digits that don't have letters (0, 1)
            backtrack(index + 1, current + digit)
    
    backtrack(0, '')
    return result

def rank_vanity_numbers(vanity_numbers: List[str]) -> List[str]:
    """
    Rank vanity numbers by quality score
    Best = contains real words, pronounceable, memorable
    """
    scored_numbers = []
    
    for vanity_number in vanity_numbers:
        score = calculate_quality_score(vanity_number)
        scored_numbers.append((vanity_number, score))
    
    # Sort by score (highest first)
    scored_numbers.sort(key=lambda x: x[1], reverse=True)
    
    return [number for number, score in scored_numbers]

def calculate_quality_score(vanity_number: str) -> int:
    """
    Calculate quality score for a vanity number
    Higher score = better vanity number
    """
    score = 0
    
    # Remove formatting for analysis
    letters_only = re.sub(r'[^\w]', '', vanity_number.split('-', 1)[1])  # Remove area code
    
    # Check for common words (highest points)
    for word in COMMON_WORDS:
        if word in letters_only:
            score += 50 * len(word)
    
    # Check for partial words or patterns
    # Consecutive vowels/consonants pattern (pronounceable)
    vowels = 'AEIOU'
    consonant_vowel_pattern = 0
    for i in range(len(letters_only) - 1):
        if (letters_only[i] in vowels) != (letters_only[i+1] in vowels):
            consonant_vowel_pattern += 1
    score += consonant_vowel_pattern * 5
    
    # Penalize too many same letters in a row
    consecutive_same = 0
    for i in range(len(letters_only) - 2):
        if letters_only[i] == letters_only[i+1] == letters_only[i+2]:
            consecutive_same += 1
    score -= consecutive_same * 10
    
    # Bonus for memorable patterns
    if len(set(letters_only)) < len(letters_only) * 0.6:  # Some repetition
        score += 10
        
    return score

def save_to_dynamodb(phone_number: str, vanity_numbers: List[str]):
    """
    Save vanity numbers to DynamoDB
    """
    try:
        table = dynamodb.Table(table_name)
        
        # Create item
        item = {
            'phoneNumber': phone_number,
            'vanityNumbers': vanity_numbers,
            'timestamp': datetime.now().isoformat(),
            'ttl': int(datetime.now().timestamp()) + (30 * 24 * 60 * 60)  # 30 days TTL
        }
        
        table.put_item(Item=item)
        logger.info(f"Saved vanity numbers for {phone_number}")
        
    except Exception as e:
        logger.error(f"Error saving to DynamoDB: {str(e)}")
        # Don't fail the whole request if DB save fails
        pass

def format_for_speech(vanity_numbers: List[str]) -> str:
    """
    Format vanity numbers for text-to-speech
    """
    if not vanity_numbers:
        return "No vanity numbers found"
    
    # Add pauses between numbers for better speech
    formatted = []
    for i, number in enumerate(vanity_numbers):
        # Format for speech: "8 0 0, GET HELP"
        parts = number.split('-')
        area_code = ' '.join(parts[0])
        vanity_part = ' '.join(parts[1]) + ', ' + ' '.join(parts[2])
        formatted.append(f"{area_code}, {vanity_part}")
    
    return ' ... Next option: '.join(formatted)

def create_connect_response(message: str) -> Dict:
    """
    Create response for Amazon Connect
    """
    return {
        'statusCode': 200,
        'body': json.dumps({
            'speech': message
        })
    }

# For testing locally
if __name__ == "__main__":
    # Test event
    test_event = {
        'phoneNumber': '8004384357'  # 800-GET-HELP
    }
    
    result = lambda_handler(test_event, None)
    print(json.dumps(result, indent=2))