#!/usr/bin/env bash
# ==============================================================================
# Automated Deployment Script for Intelligent IaC Assurance to AWS (Bash)
# ==============================================================================
set -euo pipefail

REGION="${1:-us-east-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=========================================================="
echo " Intelligent IaC Assurance - AWS Deployment Automation"
echo "=========================================================="

# 1. Check AWS authentication
aws sts get-caller-identity --output json > /dev/null || {
    echo "ERROR: AWS CLI is not authenticated. Please run 'aws configure' first."
    exit 1
}

# 2. Extract Terraform outputs
TF_DIR="${SCRIPT_DIR}/terraform"
cd "${TF_DIR}"
if [ ! -f "terraform.tfstate" ]; then
    echo "--> Running terraform init & apply..."
    terraform init
    terraform apply -auto-approve
fi

BACKEND_ECR="$(terraform output -raw ecr_backend_url)"
ML_ECR="$(terraform output -raw ecr_ml_engine_url)"
FRONTEND_BUCKET="$(terraform output -raw s3_frontend_bucket)"
CLOUDFRONT_DOMAIN="$(terraform output -raw cloudfront_domain_name)"
ALB_DNS="$(terraform output -raw alb_dns_name)"
cd "${ROOT_DIR}"

# 3. ECR Login
echo "--> Logging into Amazon ECR..."
REGISTRY="${BACKEND_ECR%%/*}"
aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${REGISTRY}"

# 4. Build and Push Backend
echo "--> Building & pushing Backend image..."
docker build -t "${BACKEND_ECR}:latest" -f Dockerfile.backend .
docker push "${BACKEND_ECR}:latest"

# 5. Build and Push ML Engine
echo "--> Building & pushing ML Engine image..."
docker build -t "${ML_ECR}:latest" -f Dockerfile.ml .
docker push "${ML_ECR}:latest"

# 6. Build and Deploy React Frontend
echo "--> Building & syncing React Frontend to S3..."
cd "${ROOT_DIR}/Frontend"
VITE_API_BASE_URL="" npm run build
aws s3 sync dist "s3://${FRONTEND_BUCKET}" --delete
cd "${ROOT_DIR}"

# 7. Force ECS New Deployment
echo "--> Forcing ECS Service deployment..."
aws ecs update-service --cluster "iac-assurance-cluster" --service "iac-assurance-ml-engine-service" --force-new-deployment --region "${REGION}" > /dev/null
aws ecs update-service --cluster "iac-assurance-cluster" --service "iac-assurance-backend-service" --force-new-deployment --region "${REGION}" > /dev/null

echo "=========================================================="
echo " DEPLOYMENT COMPLETED SUCCESSFULLY!"
echo " Web App URL: https://${CLOUDFRONT_DOMAIN}"
echo " Backend API: http://${ALB_DNS}"
echo "=========================================================="
