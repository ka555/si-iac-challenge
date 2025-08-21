import json
import boto3
import logging
import os
from datetime import datetime
from botocore.exceptions import ClientError, NoCredentialsError

# Configure logging
logger = logging.getLogger()
log_level = os.environ.get('LOG_LEVEL', 'INFO')
logger.setLevel(getattr(logging, log_level))

# Initialize S3 client
s3_client = boto3.client('s3')

def lambda_handler(event, context):
    """
    Lambda function to list contents of an S3 bucket

    Args:
        event: API Gateway event object
        context: Lambda context object

    Returns:
        dict: API Gateway response object
    """

    # Log the incoming event for debugging
    logger.info(f"Received event: {json.dumps(event, default=str)}")

    try:
        # Get bucket name from environment variable
        bucket_name = os.environ.get('BUCKET_NAME')
        if not bucket_name:
            logger.error("BUCKET_NAME environment variable not set")
            return create_response(500, {
                'error': 'Internal server error',
                'message': 'Bucket name not configured'
            })

        # Get query parameters
        query_params = event.get('queryStringParameters') or {}
        prefix = query_params.get('prefix', '')
        max_keys = int(query_params.get('max_keys', 100))

        # Validate max_keys parameter
        if max_keys > 1000:
            max_keys = 1000  # AWS limit
            logger.warning(f"max_keys reduced to 1000 (AWS limit)")

        logger.info(f"Listing objects in bucket: {bucket_name}, prefix: '{prefix}', max_keys: {max_keys}")

        # List objects in the bucket
        response = list_bucket_objects(bucket_name, prefix, max_keys)

        logger.info(f"Successfully listed {len(response.get('objects', []))} objects")

        return create_response(200, response)

    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']

        logger.error(f"AWS ClientError: {error_code} - {error_message}")

        if error_code == 'NoSuchBucket':
            return create_response(404, {
                'error': 'Bucket not found',
                'message': f'The specified bucket does not exist'
            })
        elif error_code == 'AccessDenied':
            return create_response(403, {
                'error': 'Access denied',
                'message': 'Insufficient permissions to access the bucket'
            })
        else:
            return create_response(500, {
                'error': 'AWS service error',
                'message': f'An error occurred while accessing AWS services'
            })

    except NoCredentialsError:
        logger.error("AWS credentials not found")
        return create_response(500, {
            'error': 'Internal server error',
            'message': 'AWS credentials not configured'
        })

    except ValueError as e:
        logger.error(f"Value error: {str(e)}")
        return create_response(400, {
            'error': 'Invalid request',
            'message': str(e)
        })

    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}", exc_info=True)
        return create_response(500, {
            'error': 'Internal server error',
            'message': 'An unexpected error occurred'
        })


def list_bucket_objects(bucket_name, prefix='', max_keys=100):
    """
    List objects in S3 bucket with optional prefix filter

    Args:
        bucket_name (str): Name of the S3 bucket
        prefix (str): Prefix to filter objects
        max_keys (int): Maximum number of objects to return

    Returns:
        dict: Response containing bucket contents and metadata
    """

    try:
        # Prepare list_objects_v2 parameters
        list_params = {
            'Bucket': bucket_name,
            'MaxKeys': max_keys
        }

        if prefix:
            list_params['Prefix'] = prefix

        # List objects
        response = s3_client.list_objects_v2(**list_params)

        # Process the response
        objects = []
        total_size = 0

        if 'Contents' in response:
            for obj in response['Contents']:
                # Convert datetime to string for JSON serialization
                last_modified = obj['LastModified'].isoformat()

                object_info = {
                    'key': obj['Key'],
                    'size': obj['Size'],
                    'last_modified': last_modified,
                    'etag': obj['ETag'].strip('"'),  # Remove quotes from ETag
                    'storage_class': obj.get('StorageClass', 'STANDARD')
                }

                # Add owner info if available
                if 'Owner' in obj:
                    object_info['owner'] = {
                        'id': obj['Owner'].get('ID'),
                        'display_name': obj['Owner'].get('DisplayName')
                    }

                objects.append(object_info)
                total_size += obj['Size']

        # Prepare response
        result = {
            'bucket_name': bucket_name,
            'prefix': prefix,
            'object_count': len(objects),
            'total_size_bytes': total_size,
            'total_size_mb': round(total_size / (1024 * 1024), 2),
            'is_truncated': response.get('IsTruncated', False),
            'objects': objects,
            'timestamp': datetime.utcnow().isoformat() + 'Z'
        }

        # Add continuation token if results are truncated
        if response.get('IsTruncated'):
            result['next_continuation_token'] = response.get('NextContinuationToken')
            logger.info(f"Results truncated. NextContinuationToken available.")

        # Add common prefixes if any (for folder-like structure)
        if 'CommonPrefixes' in response:
            result['common_prefixes'] = [cp['Prefix'] for cp in response['CommonPrefixes']]

        return result

    except Exception as e:
        logger.error(f"Error listing bucket objects: {str(e)}")
        raise


def create_response(status_code, body, headers=None):
    """
    Create API Gateway response object

    Args:
        status_code (int): HTTP status code
        body (dict): Response body
        headers (dict): Optional headers

    Returns:
        dict: API Gateway response object
    """

    default_headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',  # Enable CORS
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,OPTIONS'
    }

    if headers:
        default_headers.update(headers)

    response = {
        'statusCode': status_code,
        'headers': default_headers,
        'body': json.dumps(body, default=str)
    }

    return response


def format_file_size(size_bytes):
    """
    Format file size in human readable format

    Args:
        size_bytes (int): Size in bytes

    Returns:
        str: Formatted size string
    """
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if size_bytes < 1024.0:
            return f"{size_bytes:.2f} {unit}"
        size_bytes /= 1024.0
    return f"{size_bytes:.2f} PB"


# Health check function for monitoring
def health_check():
    """
    Simple health check function

    Returns:
        dict: Health status
    """
    try:
        # Test AWS credentials and S3 access
        sts_client = boto3.client('sts')
        identity = sts_client.get_caller_identity()

        return {
            'status': 'healthy',
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'aws_account': identity.get('Account'),
            'aws_user_id': identity.get('UserId')
        }
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        return {
            'status': 'unhealthy',
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'error': str(e)
        }


# For local testing
if __name__ == "__main__":
    # Test event
    test_event = {
        'queryStringParameters': {
            'prefix': '',
            'max_keys': '10'
        }
    }

    # Mock context
    class MockContext:
        def __init__(self):
            self.function_name = 'test-function'
            self.memory_limit_in_mb = 128
            self.invoked_function_arn = 'arn:aws:lambda:us-east-1:123456789012:function:test'
            self.aws_request_id = 'test-request-id'

    context = MockContext()

    # Set environment variable for testing
    os.environ['BUCKET_NAME'] = 'test-bucket'

    result = lambda_handler(test_event, context)
    print(json.dumps(result, indent=2))