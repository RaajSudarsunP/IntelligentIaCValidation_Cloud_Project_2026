# DocumentDB Subnet Group (Private Subnets)
resource "aws_docdb_subnet_group" "docdb" {
  name        = "${var.project_name}-docdb-subnet-group"
  subnet_ids  = aws_subnet.private[*].id
  description = "Subnet group for DocumentDB cluster in private subnets"

  tags = {
    Name = "${var.project_name}-docdb-subnet-group"
  }
}

# DocumentDB Security Group
resource "aws_security_group" "docdb" {
  name        = "${var.project_name}-docdb-sg"
  description = "Allow inbound MongoDB/DocumentDB traffic from ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MongoDB from ECS Backend"
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-docdb-sg"
  }
}

# DocumentDB Cluster Parameter Group
resource "aws_docdb_cluster_parameter_group" "docdb" {
  family      = "docdb5.0"
  name        = "${var.project_name}-docdb-params"
  description = "DocumentDB cluster parameter group with TLS enabled"

  parameter {
    name  = "tls"
    value = "enabled"
  }
}

# DocumentDB Cluster
resource "aws_docdb_cluster" "docdb" {
  cluster_identifier              = "${var.project_name}-db-cluster"
  engine                          = "docdb"
  engine_version                  = "5.0.0"
  master_username                 = var.documentdb_master_username
  master_password                 = var.documentdb_master_password
  db_subnet_group_name            = aws_docdb_subnet_group.docdb.name
  db_cluster_parameter_group_name = aws_docdb_cluster_parameter_group.docdb.name
  vpc_security_group_ids          = [aws_security_group.docdb.id]
  backup_retention_period         = 7
  preferred_backup_window         = "07:00-09:00"
  skip_final_snapshot             = true
  deletion_protection             = false
  storage_encrypted               = true

  tags = {
    Name = "${var.project_name}-docdb-cluster"
  }
}

# DocumentDB Cluster Instance
resource "aws_docdb_cluster_instance" "docdb_instance" {
  count              = 1
  identifier         = "${var.project_name}-docdb-instance-${count.index + 1}"
  cluster_identifier = aws_docdb_cluster.docdb.id
  instance_class     = var.documentdb_instance_class

  tags = {
    Name = "${var.project_name}-docdb-instance-${count.index + 1}"
  }
}
