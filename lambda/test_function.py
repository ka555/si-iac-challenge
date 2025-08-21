import json
import pytest
import os
from unittest.mock import patch, MagicMock
from moto import mock_s3
import boto3

# Import the lambda function
from list_s3_contents import lambda_handler, list_bucket_objects, create_response


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

    @mock_s3
    def test_lambda_handler_success(self):
        """Test successful lambda execution"""
        # Create mock S3 bucket and objects
        s3_client = boto3.client('s3', region_name='us-east-1')
        s3_client.create_bucket(Bucket=self.test_bucket)

        # Add test objects
        s3_client.put_object(Bucket=self.test_bucket, Key='test1.txt', Body=b'content1')
        s3_client.put_object(Bucket=self.test_bucket, Key='test2.txt', Body=b'content2')

        # Create test event
        event = {
            'queryStringParameters': {
                'prefix': '',
                'max_keys': '100'
            }
        }

        # Mock context
        context = MagicMock()
        context.function_name = 'test-function'

        # Execute lambda
        response = lambda_handler(event, context)

        # Assertions
        assert response['statusCode'] == 200
        body = json.loads(response['body'])
        assert body['bucket_name'] == self.test_bucket
        assert body['object_count'] == 2
        assert len(body['objects']) == 2

    @mock_s3
    def test_lambda_handler_with_prefix(self):
        """Test lambda with prefix filter"""
        # Create mock S3 bucket and objects
        s3_client = boto3.client('s3', region_name='us-east-1')
        s3_client.create_bucket(Bucket=self.test_bucket)

        # Add test objects with different prefixes
        s3_client.put_object(Bucket=self.test_bucket, Key='docs/file1.txt', Body=b'content1')
        s3_client.put_object(Bucket=self.test_bucket, Key='images/file2.jpg', Body=b'content2')
        s3_client.put_object(Bucket=self.test_bucket, Key='docs/file3.txt', Body=b'content3')

        # Test with prefix
        event = {
            'queryStringParameters': {
                'prefix': 'docs/',
                'max_keys': '100'
            }
        }

        context = MagicMock()
        response = lambda_handler(event, context)

        # Assertions
        assert response['statusCode'] == 200
        body = json.loads(response['body'])
        assert body['object_count'] == 2
        assert body['prefix'] == 'docs/'

        # Check that only docs files are returned
        for obj in body['objects']:
            assert obj['key'].startswith('docs/')

    def test_lambda_handler_missing_bucket_env(self):
        """Test lambda when BUCKET_NAME env var is missing"""
        del os.environ['BUCKET_NAME']

        event = {'queryStringParameters': None}
        context = MagicMock()

        response = lambda_handler(event, context)

        assert response['statusCode'] == 500
        body = json.loads(response['body'])
        assert 'error' in body
        assert 'Bucket name not configured' in body['message']

    def test_lambda_handler_no_query_params(self):
        """Test lambda with no query parameters"""
        with patch('list_s3_contents.list_bucket_objects') as mock_list:
            mock_list.return_value = {
                'bucket_name': self.test_bucket,
                'prefix': '',
                'object_count': 0,
                'objects': []
            }

            event = {'queryStringParameters': None}
            context = MagicMock()

            response = lambda_handler(event, context)

            assert response['statusCode'] == 200
            mock_list.assert_called_once_with(self.test_bucket, '', 100)

    def test_lambda_handler_invalid_max_keys(self):
        """Test lambda with invalid max_keys parameter"""
        with patch('list_s3_contents.list_bucket_objects') as mock_list:
            mock_list.return_value = {
                'bucket_name': self.test_bucket,
                'prefix': '',
                'object_count': 0,
                'objects': []
            }

            event = {
                'queryStringParameters': {
                    'max_keys': '2000'  # Above AWS limit
                }
            }
            context = MagicMock()

            response = lambda_handler(event, context)

            # Should clamp to 1000
            assert response['statusCode'] == 200
            mock_list.assert_called_once_with(self.test_bucket, '', 1000)

    @patch('list_s3_contents.s3_client')
    def test_lambda_handler_s3_access_denied(self, mock_s3):
        """Test lambda when S3 access is denied"""
        from botocore.exceptions import ClientError

        mock_s3.list_objects_v2.side_effect = ClientError(
            {'Error': {'Code': 'AccessDenied', 'Message': 'Access Denied'}},
            'ListObjectsV2'
        )

        event = {'queryStringParameters': None}
        context = MagicMock()

        response = lambda_handler(event, context)

        assert response['statusCode'] == 403
        body = json.loads(response['body'])
        assert body['error'] == 'Access denied'

    @patch('list_s3_contents.s3_client')
    def test_lambda_handler_bucket_not_found(self, mock_s3):
        """Test lambda when bucket doesn't exist"""
        from botocore.exceptions import ClientError

        mock_s3.list_objects_v2.side_effect = ClientError(
            {'Error': {'Code': 'NoSuchBucket', 'Message': 'Bucket not found'}},
            'ListObjectsV2'
        )

        event = {'queryStringParameters': None}
        context = MagicMock()

        response = lambda_handler(event, context)

        assert response['statusCode'] == 404
        body = json.loads(response['body'])
        assert body['error'] == 'Bucket not found'

    def test_create_response(self):
        """Test response creation function"""
        body = {'message': 'test'}
        response = create_response(200, body)

        assert response['statusCode'] == 200
        assert 'Content-Type' in response['headers']
        assert response['headers']['Content-Type'] == 'application/json'
        assert 'Access-Control-Allow-Origin' in response['headers']
        assert json.loads(response['body']) == body

    def test_create_response_with_custom_headers(self):
        """Test response creation with custom headers"""
        body = {'message': 'test'}
        custom_headers = {'X-Custom-Header': 'custom-value'}

        response = create_response(200, body, custom_headers)

        assert response['headers']['X-Custom-Header'] == 'custom-value'
        assert response['headers']['Content-Type'] == 'application/json'  # Should still have default


# Integration-style tests (would require actual AWS resources)
class TestIntegration:
    """Integration tests that would run against real AWS resources in CI/CD"""

    @pytest.mark.integration
    def test_real_s3_integration(self):
        """Test against real S3 bucket (requires AWS credentials)"""
        # This would be skipped in unit tests but run in integration testing
        pytest.skip("Integration test - requires real AWS resources")

    @pytest.mark.integration
    def test_api_gateway_integration(self):
        """Test the full API Gateway -> Lambda -> S3 flow"""
        pytest.skip("Integration test - requires deployed infrastructure")


if __name__ == '__main__':
    # Run tests when script is executed directly
    # Usage: python3 -m pytest test_function.py -v
    pytest.main(['-v', __file__])