# ==============================================================================
# EC2 Instances for Backend API + ML Engine (Dockerless Deployment)
# ==============================================================================

# Get latest Amazon Linux 2023 AMI
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Key pair for SSH access
resource "aws_key_pair" "deployer" {
  key_name   = "${var.project_name}-deployer-key"
  public_key = var.ssh_public_key
}

# Security Group for EC2 Instances
resource "aws_security_group" "ec2_instances" {
  name        = "${var.project_name}-ec2-sg"
  description = "Security group for EC2 backend and ML engine instances"
  vpc_id      = aws_vpc.main.id

  # SSH access
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Backend port from ALB
  ingress {
    description     = "Backend API from ALB"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # ML Engine port from within VPC (backend -> ML engine)
  ingress {
    description = "ML Engine from VPC"
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ec2-sg"
  }
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ec2/${var.project_name}-backend"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-backend-logs"
  }
}

resource "aws_cloudwatch_log_group" "ml_engine" {
  name              = "/ec2/${var.project_name}-ml-engine"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-ml-engine-logs"
  }
}

# ==============================================================================
# ML Engine EC2 Instance
# ==============================================================================
resource "aws_instance" "ml_engine" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.small"
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.ec2_instances.id]
  subnet_id              = aws_subnet.public[0].id
  iam_instance_profile   = aws_iam_instance_profile.ec2_app.name

  associate_public_ip_address = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = base64encode(<<-USERDATA
#!/bin/bash
set -ex

# System updates
dnf update -y
dnf install -y python3.11 python3.11-pip git

# Create app directory
mkdir -p /opt/iac-app
cd /opt/iac-app

# Clone the project
git clone https://github.com/RaajSudarsunP/IntelligentIaCValidation_Cloud_Project_2026.git app
cd app

# Install Python dependencies for ML engine
python3.11 -m pip install fastapi uvicorn boto3 botocore python-hcl2 pyyaml checkov

# Set environment variables
cat > /opt/iac-app/ml-engine.env <<'ENV'
ML_API_HOST=0.0.0.0
ML_API_PORT=9000
USE_AWS_BEDROCK=true
BEDROCK_MODEL_ID=${var.bedrock_model_id}
AWS_DEFAULT_REGION=${var.aws_region}
USE_AWS_CLOUDWATCH=true
ENV

# Create systemd service
cat > /etc/systemd/system/ml-engine.service <<'SERVICE'
[Unit]
Description=IaC ML Validation Engine
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/iac-app/app
EnvironmentFile=/opt/iac-app/ml-engine.env
ExecStart=/usr/bin/python3.11 -m uvicorn src.ml_model.api:app --host 0.0.0.0 --port 9000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable ml-engine
systemctl start ml-engine
USERDATA
  )

  tags = {
    Name = "${var.project_name}-ml-engine"
    Role = "ml-engine"
  }
}

# ==============================================================================
# Backend EC2 Instance (with MongoDB)
# ==============================================================================
resource "aws_instance" "backend" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.small"
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.ec2_instances.id]
  subnet_id              = aws_subnet.public[1].id
  iam_instance_profile   = aws_iam_instance_profile.ec2_app.name

  associate_public_ip_address = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = base64encode(<<-USERDATA
#!/bin/bash
set -ex

# System updates
dnf update -y
dnf install -y python3.11 python3.11-pip git

# Install MongoDB 7 Community
cat > /etc/yum.repos.d/mongodb-org-7.0.repo <<'REPO'
[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/amazon/2023/mongodb-org/7.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://pgp.mongodb.com/server-7.0.asc
REPO
dnf install -y mongodb-org || dnf install -y mongodb-mongosh-shared-openssl3
# If MongoDB can't be installed on AL2023, use mongomock (fallback already built in)
systemctl start mongod 2>/dev/null || true
systemctl enable mongod 2>/dev/null || true

# Create app directory
mkdir -p /opt/iac-app
cd /opt/iac-app

# Clone the project
git clone https://github.com/RaajSudarsunP/IntelligentIaCValidation_Cloud_Project_2026.git app
cd app

# Install Python dependencies for Backend
python3.11 -m pip install fastapi uvicorn pymongo mongomock boto3 botocore python-hcl2 pyyaml

# Set environment variables
cat > /opt/iac-app/backend.env <<ENV
APP_NAME=Intelligent IaC Validation Backend
MONGODB_URI=mongodb://localhost:27017
MONGODB_DATABASE=iac_validation_db
AI_ENGINE_URL=http://${aws_instance.ml_engine.private_ip}:9000
AI_ENGINE_MOCK=false
USE_S3_STORAGE=true
S3_BUCKET_NAME=${aws_s3_bucket.storage.id}
AWS_DEFAULT_REGION=${var.aws_region}
ENV

# Create systemd service
cat > /etc/systemd/system/backend.service <<'SERVICE'
[Unit]
Description=IaC Backend FastAPI Server
After=network.target mongod.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/iac-app/app
EnvironmentFile=/opt/iac-app/backend.env
ExecStart=/usr/bin/python3.11 -m uvicorn src.backend.main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable backend
systemctl start backend
USERDATA
  )

  depends_on = [aws_instance.ml_engine]

  tags = {
    Name = "${var.project_name}-backend"
    Role = "backend"
  }
}

# Register Backend EC2 instance with ALB Target Group
resource "aws_lb_target_group_attachment" "backend" {
  target_group_arn = aws_lb_target_group.backend.arn
  target_id        = aws_instance.backend.id
  port             = 8000
}
