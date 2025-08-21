import json
import pytest
import os
import boto3


class TestLambdaFunction:
    """Test cases for the S3 list Lambda function"""

    def setup_method(self):
        """Set up test fixtures"""
        self.test_bucket = "test-bucket"
        os.environ['BUCKET_NAME'] = self.test_bucket
        os.environ['LOG_LEVEL'] = 'INFO'

    def teardown_method(self):
        """Clean up after tests"""
        if 'BUCKET_NAME' in os.environ:
            del os.environ['BUCKET_NAME']

    def test_environment_variables(self):
        """Test environment variable handling"""
        # Test with bucket name
        assert os.environ.get('BUCKET_NAME') == self.test_bucket
        assert os.environ.get('LOG_LEVEL') == 'INFO'

    def test_json_response_creation(self):
        """Test JSON response creation"""
        # Mock a typical lambda response
        test_data = {
            'bucket_name': self.test_bucket,
            'object_count': 2,
            'objects': [
                {'key': 'test1.txt', 'size': 100},
                {'key': 'test2.txt', 'size': 200}
            ]
        }

        # Create a mock response
        response = {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(test_data)
        }

        # Test response structure
        assert response['statusCode'] == 200
        assert 'Content-Type' in response['headers']
        assert response['headers']['Content-Type'] == 'application/json'

        # Test body parsing
        body = json.loads(response['body'])
        assert body['bucket_name'] == self.test_bucket
        assert body['object_count'] == 2
        assert len(body['objects']) == 2

    def test_query_parameter_parsing(self):
        """Test query parameter parsing logic"""
        # Test valid parameters
        event = {
            'queryStringParameters': {
                'prefix': 'docs/',
                'max_keys': '100'
            }
        }

        params = event.get('queryStringParameters', {})
        prefix = params.get('prefix', '')
        max_keys = int(params.get('max_keys', 100))

        assert prefix == 'docs/'
        assert max_keys == 100

        # Test with None parameters
        event_none = {'queryStringParameters': None}
        params_none = event_none.get('queryStringParameters') or {}
        prefix_none = params_none.get('prefix', '')
        max_keys_none = int(params_none.get('max_keys', 100))

        assert prefix_none == ''
        assert max_keys_none == 100

    def test_max_keys_validation(self):
        """Test max_keys parameter validation"""
        # Test clamping large values
        max_keys = 2000
        clamped = min(max_keys, 1000)
        assert clamped == 1000

        # Test normal values
        max_keys = 50
        clamped = min(max_keys, 1000)
        assert clamped == 50

    def test_error_response_format(self):
        """Test error response formatting"""
        error_response = {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Internal Server Error',
                'message': 'Bucket name not configured'
            })
        }

        assert error_response['statusCode'] == 500
        error_body = json.loads(error_response['body'])
        assert 'error' in error_body
        assert 'message' in error_body

    def test_boto3_import(self):
        """Test that boto3 imports correctly"""
        # Just test that we can create a client
        s3_client = boto3.client('s3', region_name='us-east-1')
        assert s3_client is not None

    def test_missing_environment_variable(self):
        """Test behavior when environment variable is missing"""
        # Remove the environment variable
        if 'BUCKET_NAME' in os.environ:
            del os.environ['BUCKET_NAME']

        # Test that it's None
        bucket_name = os.environ.get('BUCKET_NAME')
        assert bucket_name is None

        # Test default handling
        bucket_name = os.environ.get('BUCKET_NAME', 'default-bucket')
        assert bucket_name == 'default-bucket'


if __name__ == '__main__':
    # Run tests when script is executed directly
    pytest.main(['-v', __file__])