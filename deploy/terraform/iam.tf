# ==============================================================================
# IAM Roles & Policies for EC2 Instances
# ==============================================================================

# EC2 Instance Role (used by application code at runtime)
resource "aws_iam_role" "ec2_app_role" {
  name = "${var.project_name}-ec2-app-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Instance Profile for EC2
resource "aws_iam_instance_profile" "ec2_app" {
  name = "${var.project_name}-ec2-app-profile-${var.environment}"
  role = aws_iam_role.ec2_app_role.name
}

# Application Policy: S3, Bedrock, CloudWatch, and SSM
resource "aws_iam_policy" "ec2_app_policy" {
  name        = "${var.project_name}-ec2-app-policy-${var.environment}"
  description = "Allows EC2 instances to interact with S3, Amazon Bedrock, CloudWatch, and SSM"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # S3 Access to storage bucket
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.storage.arn,
          "${aws_s3_bucket.storage.arn}/*"
        ]
      },
      # Amazon Bedrock LLM invocation
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = [
          "arn:aws:bedrock:${var.aws_region}::foundation-model/*",
          "arn:aws:bedrock:${var.aws_region}:*:custom-model/*"
        ]
      },
      # CloudWatch Logs and Metrics
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "cloudwatch:PutMetricData",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      },
      # AWS Config for configuration state collection
      {
        Effect = "Allow"
        Action = [
          "config:GetResourceConfigHistory",
          "config:BatchGetResourceConfig"
        ]
        Resource = "*"
      },
      # SSM for Session Manager access (optional SSH alternative)
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssmmessages:*",
          "ec2messages:*"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_app_policy_attach" {
  role       = aws_iam_role.ec2_app_role.name
  policy_arn = aws_iam_policy.ec2_app_policy.arn
}

# Attach SSM managed policy for Session Manager
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_app_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
