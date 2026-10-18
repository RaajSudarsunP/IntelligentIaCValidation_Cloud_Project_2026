output "alb_dns_name" {
  description = "The public DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "cloudfront_domain_name" {
  description = "The public CloudFront CDN domain name (Access the Frontend application here)"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "s3_storage_bucket" {
  description = "Name of the S3 bucket storing IaC templates and validation reports"
  value       = aws_s3_bucket.storage.id
}

output "s3_frontend_bucket" {
  description = "Name of the S3 bucket hosting frontend static assets"
  value       = aws_s3_bucket.frontend.id
}

output "ecr_backend_url" {
  description = "ECR Repository URL for pushing Backend container images"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_ml_engine_url" {
  description = "ECR Repository URL for pushing ML Engine container images"
  value       = aws_ecr_repository.ml_engine.repository_url
}

output "documentdb_cluster_endpoint" {
  description = "Endpoint of the Amazon DocumentDB cluster"
  value       = aws_docdb_cluster.docdb.endpoint
}
