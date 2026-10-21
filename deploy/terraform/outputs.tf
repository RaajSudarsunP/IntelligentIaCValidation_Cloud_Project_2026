output "alb_dns_name" {
  description = "The public DNS name of the Application Load Balancer (Backend API)"
  value       = "http://${aws_lb.main.dns_name}"
}

output "frontend_website_url" {
  description = "The S3 static website URL for the Frontend"
  value       = "http://${aws_s3_bucket_website_configuration.frontend.website_endpoint}"
}

output "s3_storage_bucket" {
  description = "Name of the S3 bucket storing IaC templates and validation reports"
  value       = aws_s3_bucket.storage.id
}

output "s3_frontend_bucket" {
  description = "Name of the S3 bucket hosting frontend static assets"
  value       = aws_s3_bucket.frontend.id
}

output "backend_ec2_public_ip" {
  description = "Public IP of the Backend EC2 instance"
  value       = aws_instance.backend.public_ip
}

output "ml_engine_ec2_public_ip" {
  description = "Public IP of the ML Engine EC2 instance"
  value       = aws_instance.ml_engine.public_ip
}

output "backend_ec2_private_ip" {
  description = "Private IP of the Backend EC2 instance"
  value       = aws_instance.backend.private_ip
}

output "ml_engine_ec2_private_ip" {
  description = "Private IP of the ML Engine EC2 instance"
  value       = aws_instance.ml_engine.private_ip
}
