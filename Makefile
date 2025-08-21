.PHONY: help init plan apply destroy test lint security-scan clean setup

ENV ?= dev
REGION ?= us-east-1
EMAIL ?=

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $1, $2}'

setup: ## Setup development environment
	@if ! command -v terraform >/dev/null; then echo "Error: Terraform not found"; exit 1; fi
	@if ! command -v aws >/dev/null; then echo "Error: AWS CLI not found"; exit 1; fi
	@echo "Installing Python dependencies..."
	@cd lambda && pip install -r requirements.txt
	@echo "✅ Setup completed"

init: ## Initialize Terraform
	@cd terraform && terraform init

lint: ## Validate and format Terraform code
	@cd terraform && terraform fmt -recursive
	@cd terraform && terraform validate

lambda-zip: ## Create Lambda function zip file
	@cd terraform && \
	if [ ! -f "lambda_function.zip" ] || [ "../lambda/list_s3_contents.py" -nt "lambda_function.zip" ]; then \
		zip lambda_function.zip -j ../lambda/list_s3_contents.py; \
	fi

plan: init lint lambda-zip ## Create Terraform plan
	@cd terraform && terraform plan \
		-var="environment=$(ENV)" \
		-var="aws_region=$(REGION)" \
		$(if $(EMAIL),-var="notification_email=$(EMAIL)") \
		-out="$(ENV)-plan.tfplan"

apply: ## Apply Terraform plan
	@if [ ! -f "terraform/$(ENV)-plan.tfplan" ]; then echo "Error: Plan file not found. Run 'make plan ENV=$(ENV)' first"; exit 1; fi
	@if [ "$(ENV)" = "prod" ]; then read -p "Type 'yes' to confirm production deployment: " confirm && [ "$confirm" = "yes" ] || exit 1; fi
	@cd terraform && terraform apply "$(ENV)-plan.tfplan"

destroy: ## Destroy infrastructure
	@if [ "$(ENV)" = "prod" ]; then read -p "Type 'DESTROY PRODUCTION' to confirm: " confirm && [ "$confirm" = "DESTROY PRODUCTION" ] || exit 1; else read -p "Type 'destroy' to confirm: " confirm && [ "$confirm" = "destroy" ] || exit 1; fi
	@cd terraform && terraform destroy \
		-var="environment=$(ENV)" \
		-var="aws_region=$(REGION)" \
		$(if $(EMAIL),-var="notification_email=$(EMAIL)") \
		-auto-approve

test: ## Run tests for Lambda function
	@echo "Installing test dependencies if needed..."
	@cd lambda && pip install -q pytest moto boto3 2>/dev/null || true
	@cd lambda && python3 -m pytest test_function.py -v

security-scan: ## Run security scans
	@if command -v tfsec >/dev/null; then tfsec terraform/ || true; fi
	@if command -v checkov >/dev/null; then checkov -d terraform/ --framework terraform || true; fi

test-api: ## Test the deployed API endpoint
	@echo "Getting API endpoint..."
	@cd terraform && terraform output api_gateway_endpoint
	@echo "Testing API..."
	@cd terraform && curl -s $$(terraform output -raw api_gateway_endpoint) | jq .

clean: ## Clean up temporary files
	@rm -f terraform/*.tfplan
	@rm -f terraform/lambda_function.zip
	@rm -f lambda/*.pyc
	@rm -rf lambda/__pycache__
	@rm -f response.json

dev-up: ENV=dev
dev-up: plan apply

staging-up: ENV=staging
staging-up: plan apply

prod-up: ENV=prod
prod-up: plan apply

dev-down: ENV=dev
dev-down: destroy