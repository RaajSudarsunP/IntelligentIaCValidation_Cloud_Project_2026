<#
.SYNOPSIS
    Automated Deployment Script for Intelligent IaC Assurance to AWS (Windows PowerShell)
.DESCRIPTION
    Builds Docker containers, pushes images to Amazon ECR, syncs the React Frontend to S3,
    and updates ECS services.
.PARAMETER Region
    The AWS region to deploy into (default: us-east-1)
#>

param (
    [string]$Region = "us-east-1"
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Intelligent IaC Assurance - AWS Deployment Automation" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Check AWS CLI
try {
    $caller = aws sts get-caller-identity --output json | ConvertFrom-Json
    Write-Host "[✓] AWS CLI authenticated as Account: $($caller.Account)" -ForegroundColor Green
} catch {
    Write-Error "AWS CLI is not authenticated. Please run 'aws configure' with your credentials first."
}

# 2. Extract Terraform Outputs
$tfDir = Join-Path $PSScriptRoot "terraform"
if (-not (Test-Path (Join-Path $tfDir "terraform.tfstate"))) {
    Write-Host "[!] Terraform state not found. Running terraform apply first..." -ForegroundColor Yellow
    Push-Location $tfDir
    terraform init
    terraform apply -auto-approve
    Pop-Location
}

Push-Location $tfDir
$backendEcr = (terraform output -raw ecr_backend_url).Trim()
$mlEcr = (terraform output -raw ecr_ml_engine_url).Trim()
$frontendBucket = (terraform output -raw s3_frontend_bucket).Trim()
$cloudfrontDomain = (terraform output -raw cloudfront_domain_name).Trim()
$albDns = (terraform output -raw alb_dns_name).Trim()
Pop-Location

Write-Host "[✓] Backend ECR: $backendEcr" -ForegroundColor Gray
Write-Host "[✓] ML Engine ECR: $mlEcr" -ForegroundColor Gray
Write-Host "[✓] Frontend S3 Bucket: $frontendBucket" -ForegroundColor Gray

# 3. Log in to Amazon ECR
Write-Host "`n--> Authenticating Docker with Amazon ECR..." -ForegroundColor Yellow
$registry = $backendEcr.Split("/")[0]
aws ecr get-login-password --region $Region | docker login --username AWS --password-stdin $registry

# 4. Build and Push Backend Image
Write-Host "`n--> Building Backend Docker image..." -ForegroundColor Yellow
docker build -t "$backendEcr`:latest" -f Dockerfile.backend .
Write-Host "--> Pushing Backend image to ECR..." -ForegroundColor Yellow
docker push "$backendEcr`:latest"

# 5. Build and Push ML Engine Image
Write-Host "`n--> Building ML Engine Docker image..." -ForegroundColor Yellow
docker build -t "$mlEcr`:latest" -f Dockerfile.ml .
Write-Host "--> Pushing ML Engine image to ECR..." -ForegroundColor Yellow
docker push "$mlEcr`:latest"

# 6. Build and Deploy React Frontend
Write-Host "`n--> Building React Frontend for CloudFront CDN..." -ForegroundColor Yellow
Push-Location "Frontend"
$env:VITE_API_BASE_URL = ""
npm run build
Pop-Location

Write-Host "--> Uploading static assets to S3 ($frontendBucket)..." -ForegroundColor Yellow
aws s3 sync "Frontend/dist" "s3://$frontendBucket" --delete

# 7. Update ECS Services to deploy new containers
Write-Host "`n--> Forcing ECS Service deployment with new images..." -ForegroundColor Yellow
aws ecs update-service --cluster "iac-assurance-cluster" --service "iac-assurance-ml-engine-service" --force-new-deployment --region $Region | Out-Null
aws ecs update-service --cluster "iac-assurance-cluster" --service "iac-assurance-backend-service" --force-new-deployment --region $Region | Out-Null

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host " DEPLOYMENT COMPLETED SUCCESSFULLY!" -ForegroundColor Green
Write-Host " App URL (CloudFront): https://$cloudfrontDomain" -ForegroundColor Green
Write-Host " Backend API (Direct ALB): http://$albDns" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
