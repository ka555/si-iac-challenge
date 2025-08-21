#!/bin/bash

set -e

ENVIRONMENT=${1:-dev}
BACKUP_STATE_KEY=${2:-""}
TERRAFORM_DIR="$(dirname "$0")/../terraform"

echo "Starting rollback for ${ENVIRONMENT} environment"

if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
    echo "Error: Environment must be one of: dev, staging, prod"
    exit 1
fi

if [ "$ENVIRONMENT" = "prod" ]; then
    echo "DANGER: You are about to rollback PRODUCTION!"
    read -p "Type 'ROLLBACK PRODUCTION' to confirm: " CONFIRM
    if [ "$CONFIRM" != "ROLLBACK PRODUCTION" ]; then
        echo "Rollback cancelled."
        exit 0
    fi
fi

cd "$TERRAFORM_DIR"

terraform init

echo "Current resources in $ENVIRONMENT:"
terraform state list

if [ -n "$BACKUP_STATE_KEY" ]; then
    echo "Restoring from backup state: $BACKUP_STATE_KEY"
    echo "Note: State restoration logic would be implemented here based on your backend"
else
    echo "No backup state specified. Performing infrastructure destroy..."

    BACKUP_FILE="state-backup-${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S).tfstate"
    terraform state pull > "$BACKUP_FILE"
    echo "Current state backed up to: $BACKUP_FILE"

    terraform plan -destroy \
        -var="environment=$ENVIRONMENT" \
        -out="destroy-plan"

    echo "Resources to be destroyed:"
    terraform show destroy-plan | grep -E "will be destroyed|Plan:"

    read -p "Proceed with destroying all resources? (type 'destroy' to confirm): " DESTROY_CONFIRM
    if [ "$DESTROY_CONFIRM" != "destroy" ]; then
        echo "Rollback cancelled."
        rm -f destroy-plan
        exit 0
    fi

    terraform apply destroy-plan
    rm -f destroy-plan
fi

echo "Verifying rollback completion..."

REMAINING_RESOURCES=$(terraform state list | wc -l)
if [ "$REMAINING_RESOURCES" -eq 0 ]; then
    echo "All resources successfully removed"
else
    echo "Warning: $REMAINING_RESOURCES resources still exist"
    terraform state list
fi

echo "Rollback completed for $ENVIRONMENT environment"

echo "Post-rollback recommendations:"
echo "1. Verify all AWS resources have been cleaned up in the console"
echo "2. Check CloudWatch logs for any remaining log groups"
echo "3. Ensure IAM roles have been removed"
echo "4. Review S3 buckets for any orphaned resources"

if [ -f "$BACKUP_FILE" ]; then
    echo "5. State backup saved to: $BACKUP_FILE"
fi