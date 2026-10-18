# ==============================================================================
# ECS Fargate Cluster, Task Definitions, and Services
# ==============================================================================

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${var.project_name}-ecs-cluster"
  }
}

# CloudWatch Log Groups for Container logs
resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${var.project_name}-backend"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-backend-logs"
  }
}

resource "aws_cloudwatch_log_group" "ml_engine" {
  name              = "/ecs/${var.project_name}-ml-engine"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-ml-engine-logs"
  }
}

# Security Group for ECS Tasks
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project_name}-ecs-tasks-sg"
  description = "Security group for ECS Fargate tasks"
  vpc_id      = aws_vpc.main.id

  # Inbound to Backend from ALB on port 8000
  ingress {
    description     = "Allow HTTP from ALB to Backend"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Inbound to ML Engine from Backend on port 9000
  ingress {
    description = "Allow Backend to call ML Engine"
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    self        = true
  }

  # Outbound to all (via NAT gateway for Bedrock, S3, Docker registries)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ecs-tasks-sg"
  }
}

# Private Service Discovery (Cloud Map) so backend reaches ML engine via DNS
resource "aws_service_discovery_private_dns_namespace" "internal" {
  name        = "iac.local"
  description = "Private DNS namespace for internal ECS microservice communication"
  vpc         = aws_vpc.main.id
}

resource "aws_service_discovery_service" "ml_engine" {
  name = "ml-engine"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.internal.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

# Task Definition for ML Validation Engine
resource "aws_ecs_task_definition" "ml_engine" {
  family                   = "${var.project_name}-ml-engine"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ml_engine_cpu
  memory                   = var.ml_engine_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "ml-engine"
      image     = "${aws_ecr_repository.ml_engine.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 9000
          hostPort      = 9000
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "ML_API_HOST", value = "0.0.0.0" },
        { name = "ML_API_PORT", value = "9000" },
        { name = "USE_AWS_BEDROCK", value = "true" },
        { name = "BEDROCK_MODEL_ID", value = var.bedrock_model_id },
        { name = "AWS_REGION", value = var.aws_region },
        { name = "USE_AWS_CLOUDWATCH", value = "true" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ml_engine.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ml-engine"
        }
      }
    }
  ])
}

# ECS Service for ML Validation Engine
resource "aws_ecs_service" "ml_engine" {
  name            = "${var.project_name}-ml-engine-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.ml_engine.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.ml_engine.arn
  }
}

# Task Definition for FastAPI Backend
resource "aws_ecs_task_definition" "backend" {
  family                   = "${var.project_name}-backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.backend_cpu
  memory                   = var.backend_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "backend"
      image     = "${aws_ecr_repository.backend.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "APP_NAME", value = "Intelligent IaC Validation Backend" },
        { name = "MONGODB_URI", value = "mongodb://${var.documentdb_master_username}:${var.documentdb_master_password}@${aws_docdb_cluster.docdb.endpoint}:27017/?tls=true&tlsCAFile=global-bundle.pem&replicaSet=rs0&readPreference=secondaryPreferred&retryWrites=false" },
        { name = "MONGODB_DATABASE", value = "iac_validation_db" },
        { name = "DOCUMENTDB_TLS", value = "true" },
        { name = "DOCUMENTDB_INSECURE_TLS", value = "true" },
        { name = "AI_ENGINE_URL", value = "http://ml-engine.iac.local:9000" },
        { name = "AI_ENGINE_MOCK", value = "false" },
        { name = "USE_S3_STORAGE", value = "true" },
        { name = "S3_BUCKET_NAME", value = aws_s3_bucket.storage.id },
        { name = "AWS_REGION", value = var.aws_region }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backend.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "backend"
        }
      }
    }
  ])
}

# ECS Service for FastAPI Backend
resource "aws_ecs_service" "backend" {
  name            = "${var.project_name}-backend-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"
    container_port   = 8000
  }

  depends_on = [
    aws_lb_listener.http,
    aws_ecs_service.ml_engine,
  ]
}
