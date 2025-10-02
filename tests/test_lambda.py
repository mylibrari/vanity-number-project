#!/usr/bin/env python3
"""
Test suite for the Vanity Numbers Lambda functions
Run with: python3 test_lambda.py
"""

import unittest
import json
import sys
import os
from unittest.mock import Mock, patch, MagicMock

# Add the lambda directory to the path
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'lambda'))

# Import the functions to test
import lambda_function
import api_lambda

class TestVanityNumbersLambda(unittest.TestCase):
    """Test cases for the main vanity numbers Lambda function"""
    
    def test_phone_keypad_mapping(self):
        """Test that phone keypad mapping is correct"""
        expected_keypad = {
            '2': 'ABC', '3': 'DEF', '4': 'GHI', '5': 'JKL',
            '6': 'MNO', '7': 'PQRS', '8': 'TUV', '9': 'WXYZ'
        }
        self.assertEqual(lambda_function.PHONE_KEYPAD, expected_keypad)
    
    def test_extract_phone_number_connect_format(self):
        """Test extracting phone number from Amazon Connect event"""
        event = {
            'Details': {
                'ContactData': {
                    'CustomerEndpoint': {
                        'Address': '+18004384357'
                    }
                }
            }
        }
        result = lambda_function.extract_phone_number(event)
        self.assertEqual(result, '8004384357')
    
    def test_extract_phone_number_test_format(self):
        """Test extracting phone number from test event"""
        event = {
            'phoneNumber': '800-438-4357'
        }
        result = lambda_function.extract_phone_number(event)
        self.assertEqual(result, '8004384357')
    
    def test_extract_phone_number_with_country_code(self):
        """Test extracting phone number with country code"""
        event = {
            'phoneNumber': '+1 (800) 438-4357'
        }
        result = lambda_function.extract_phone_number(event)
        self.assertEqual(result, '8004384357')
    
    def test_extract_phone_number_invalid(self):
        """Test extracting invalid phone number"""
        event = {
            'phoneNumber': '123'  # Too short
        }
        result = lambda_function.extract_phone_number(event)
        self.assertIsNone(result)
    
    def test_generate_combinations_simple(self):
        """Test generating letter combinations for simple digits"""
        result = lambda_function.generate_combinations('23')
        expected = ['AD', 'AE', 'AF', 'BD', 'BE', 'BF', 'CD', 'CE', 'CF']
        self.assertEqual(result, expected)
    
    def test_generate_combinations_with_non_letter_digits(self):
        """Test generating combinations with digits that don't map to letters"""
        result = lambda_function.generate_combinations('21')  # 1 has no letters
        expected = ['A1', 'B1', 'C1']
        self.assertEqual(result, expected)
    
    def test_calculate_quality_score_with_common_word(self):
        """Test quality scoring with common words"""
        score = lambda_function.calculate_quality_score('800-GET-HELP')
        # Should get points for "GET" (150) and "HELP" (200)
        self.assertGreater(score, 300)
    
    def test_calculate_quality_score_consonant_vowel_pattern(self):
        """Test quality scoring for pronounceable patterns"""
        score = lambda_function.calculate_quality_score('800-BABABA')
        # Should get points for consonant-vowel alternation
        self.assertGreater(score, 0)
    
    def test_calculate_quality_score_repetitive_letters(self):
        """Test quality scoring penalizes repetitive letters"""
        score = lambda_function.calculate_quality_score('800-AAAAAA')
        # Should be penalized for consecutive same letters
        self.assertLess(score, 0)
    
    def test_rank_vanity_numbers(self):
        """Test ranking vanity numbers by quality"""
        vanity_numbers = [
            '800-123-AAAA',  # Low quality
            '800-GET-HELP',  # High quality
            '800-ABC-DEFG'   # Medium quality
        ]
        ranked = lambda_function.rank_vanity_numbers(vanity_numbers)
        # GET-HELP should be ranked first
        self.assertEqual(ranked[0], '800-GET-HELP')
    
    def test_format_for_speech(self):
        """Test formatting vanity numbers for text-to-speech"""
        vanity_numbers = ['800-GET-HELP', '800-BET-HELP']
        result = lambda_function.format_for_speech(vanity_numbers)
        # Should contain formatted numbers with pauses
        self.assertIn('8 0 0', result)
        self.assertIn('GET', result)
        self.assertIn('HELP', result)
    
    def test_create_connect_response(self):
        """Test creating Amazon Connect response format"""
        message = "Test message"
        result = lambda_function.create_connect_response(message)
        expected = {
            'statusCode': 200,
            'body': json.dumps({
                'speech': message
            })
        }
        self.assertEqual(result, expected)
    
    @patch('lambda_function.dynamodb')
    @patch('lambda_function.extract_phone_number')
    @patch('lambda_function.generate_vanity_numbers')
    @patch('lambda_function.rank_vanity_numbers')
    def test_lambda_handler_success(self, mock_rank, mock_generate, mock_extract, mock_dynamodb):
        """Test successful lambda handler execution"""
        # Setup mocks
        mock_extract.return_value = '8004384357'
        mock_generate.return_value = ['800-GET-HELP', '800-BET-HELP']
        mock_rank.return_value = ['800-GET-HELP', '800-BET-HELP']
        
        # Mock DynamoDB table
        mock_table = Mock()
        mock_dynamodb.Table.return_value = mock_table
        
        event = {'test': 'event'}
        context = Mock()
        
        result = lambda_function.lambda_handler(event, context)
        
        # Check response format
        self.assertEqual(result['statusCode'], 200)
        self.assertIn('body', result)
        body = json.loads(result['body'])
        self.assertIn('speech', body)
    
    @patch('lambda_function.extract_phone_number')
    def test_lambda_handler_no_phone_number(self, mock_extract):
        """Test lambda handler when no phone number is found"""
        mock_extract.return_value = None
        
        event = {'test': 'event'}
        context = Mock()
        
        result = lambda_function.lambda_handler(event, context)
        
        # Should return error message
        self.assertEqual(result['statusCode'], 200)
        body = json.loads(result['body'])
        self.assertIn('couldn\'t process', body['speech'])

class TestAPILambda(unittest.TestCase):
    """Test cases for the API Lambda function"""
    
    def test_format_phone_number(self):
        """Test phone number formatting"""
        result = api_lambda.format_phone_number('8004384357')
        self.assertEqual(result, '(800) 438-4357')
    
    def test_format_phone_number_invalid(self):
        """Test phone number formatting with invalid input"""
        result = api_lambda.format_phone_number('123')
        self.assertEqual(result, '123')  # Should return as-is
    
    def test_time_ago_days(self):
        """Test time ago calculation for days"""
        from datetime import datetime, timedelta
        past_date = (datetime.now() - timedelta(days=2)).isoformat()
        result = api_lambda.time_ago(past_date)
        self.assertIn('2 days ago', result)
    
    def test_time_ago_hours(self):
        """Test time ago calculation for hours"""
        from datetime import datetime, timedelta
        past_date = (datetime.now() - timedelta(hours=3)).isoformat()
        result = api_lambda.time_ago(past_date)
        self.assertIn('3 hours ago', result)
    
    def test_time_ago_minutes(self):
        """Test time ago calculation for minutes"""
        from datetime import datetime, timedelta
        past_date = (datetime.now() - timedelta(minutes=30)).isoformat()
        result = api_lambda.time_ago(past_date)
        self.assertIn('30 minutes ago', result)
    
    def test_time_ago_invalid(self):
        """Test time ago with invalid timestamp"""
        result = api_lambda.time_ago('invalid-timestamp')
        self.assertEqual(result, 'Unknown')
    
    @patch('api_lambda.dynamodb')
    def test_get_recent_calls_success(self, mock_dynamodb):
        """Test getting recent calls successfully"""
        # Mock DynamoDB response
        mock_table = Mock()
        mock_table.scan.return_value = {
            'Items': [
                {
                    'phoneNumber': '8004384357',
                    'vanityNumbers': ['800-GET-HELP', '800-BET-HELP'],
                    'timestamp': '2025-01-15T10:30:00Z'
                }
            ]
        }
        mock_dynamodb.Table.return_value = mock_table
        
        result = api_lambda.get_recent_calls()
        
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]['phoneNumber'], '(800) 438-4357')
        self.assertEqual(len(result[0]['vanityNumbers']), 2)
    
    @patch('api_lambda.get_recent_calls')
    def test_lambda_handler_success(self, mock_get_calls):
        """Test API lambda handler success"""
        mock_get_calls.return_value = [
            {
                'phoneNumber': '(800) 438-4357',
                'vanityNumbers': ['800-GET-HELP'],
                'timestamp': '2025-01-15T10:30:00Z',
                'timeAgo': '5 minutes ago'
            }
        ]
        
        event = {}
        context = Mock()
        
        result = api_lambda.lambda_handler(event, context)
        
        self.assertEqual(result['statusCode'], 200)
        self.assertIn('Access-Control-Allow-Origin', result['headers'])
        
        body = json.loads(result['body'])
        self.assertIn('calls', body)
        self.assertEqual(len(body['calls']), 1)

class TestIntegration(unittest.TestCase):
    """Integration tests"""
    
    def test_full_vanity_conversion_flow(self):
        """Test the complete vanity number conversion flow"""
        phone_number = '8004384357'  # Should convert to GET-HELP
        
        # Generate vanity numbers
        vanity_numbers = lambda_function.generate_vanity_numbers(phone_number)
        
        # Should generate multiple options
        self.assertGreater(len(vanity_numbers), 10)
        
        # Rank them
        ranked = lambda_function.rank_vanity_numbers(vanity_numbers)
        
        # Should have GET-HELP near the top (it's a real word combination)
        top_5 = ranked[:5]
        get_help_found = any('GET' in vanity and 'HELP' in vanity for vanity in top_5)
        self.assertTrue(get_help_found, f"GET-HELP not in top 5: {top_5}")

if __name__ == '__main__':
    # Create a test suite
    test_suite = unittest.TestSuite()
    
    # Add test classes
    test_suite.addTest(unittest.makeSuite(TestVanityNumbersLambda))
    test_suite.addTest(unittest.makeSuite(TestAPILambda))
    test_suite.addTest(unittest.makeSuite(TestIntegration))
    
    # Run tests
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(test_suite)
    
    # Print summary
    print(f"\n{'='*50}")
    print(f"Tests run: {result.testsRun}")
    print(f"Failures: {len(result.failures)}")
    print(f"Errors: {len(result.errors)}")
    print(f"Success rate: {((result.testsRun - len(result.failures) - len(result.errors)) / result.testsRun * 100):.1f}%")
    print(f"{'='*50}")
    
    # Exit with error code if tests failed
    if result.failures or result.errors:
        sys.exit(1)
    else:
        print("All tests passed! ✅")
        sys.exit(0)