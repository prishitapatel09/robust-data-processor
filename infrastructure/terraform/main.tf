terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# SQS Queue for message broker
resource "aws_sqs_queue" "processing_queue" {
  name                      = "${var.project_name}-queue-${var.environment}"
  visibility_timeout_seconds = 300
  message_retention_period  = 345600
  receive_wait_time_seconds = 20

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# Dead Letter Queue
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.project_name}-dlq-${var.environment}"
  message_retention_period  = 1209600

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# DynamoDB Table with multi-tenant structure
resource "aws_dynamodb_table" "logs_table" {
  name           = "${var.project_name}-logs-${var.environment}"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "tenant_id"
  range_key      = "log_id"

  attribute {
    name = "tenant_id"
    type = "S"
  }

  attribute {
    name = "log_id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# IAM Role for Ingestion Lambda
resource "aws_iam_role" "ingestion_lambda_role" {
  name = "${var.project_name}-ingestion-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ingestion_lambda_basic" {
  role       = aws_iam_role.ingestion_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "ingestion_lambda_sqs" {
  name = "${var.project_name}-ingestion-sqs-policy"
  role = aws_iam_role.ingestion_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.processing_queue.arn
      }
    ]
  })
}

# IAM Role for Worker Lambda
resource "aws_iam_role" "worker_lambda_role" {
  name = "${var.project_name}-worker-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "worker_lambda_basic" {
  role       = aws_iam_role.worker_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "worker_lambda_dynamodb" {
  name = "${var.project_name}-worker-dynamodb-policy"
  role = aws_iam_role.worker_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem"
        ]
        Resource = aws_dynamodb_table.logs_table.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "worker_lambda_sqs" {
  name = "${var.project_name}-worker-sqs-policy"
  role = aws_iam_role.worker_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.processing_queue.arn
      }
    ]
  })
}

# Ingestion Lambda Function
resource "aws_lambda_function" "ingestion" {
  filename         = var.ingestion_zip_path
  function_name    = "${var.project_name}-ingestion-${var.environment}"
  role            = aws_iam_role.ingestion_lambda_role.arn
  handler         = "ingestion_handler.handler"
  source_code_hash = filebase64sha256(var.ingestion_zip_path)
  runtime         = "nodejs20.x"
  timeout         = 30
  memory_size     = 256

  environment {
    variables = {
      SQS_QUEUE_URL = aws_sqs_queue.processing_queue.url
    }
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# Worker Lambda Function
resource "aws_lambda_function" "worker" {
  filename         = var.worker_zip_path
  function_name    = "${var.project_name}-worker-${var.environment}"
  role            = aws_iam_role.worker_lambda_role.arn
  handler         = "worker_handler.handler"
  source_code_hash = filebase64sha256(var.worker_zip_path)
  runtime         = "nodejs20.x"
  timeout         = 900
  memory_size     = 512

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.logs_table.name
    }
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# SQS Event Source Mapping for Worker Lambda
resource "aws_lambda_event_source_mapping" "worker_sqs" {
  event_source_arn = aws_sqs_queue.processing_queue.arn
  function_name    = aws_lambda_function.worker.arn
  batch_size       = 10
  enabled          = true
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.project_name}-api-${var.environment}"
  description = "Robust Data Processor API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# API Gateway Resource for /ingest
resource "aws_api_gateway_resource" "ingest" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "ingest"
}

# POST Method for /ingest
resource "aws_api_gateway_method" "ingest_post" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.ingest.id
  http_method   = "POST"
  authorization = "NONE"
}

# Integration with Lambda
resource "aws_api_gateway_integration" "ingest_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.ingest.id
  http_method = aws_api_gateway_method.ingest_post.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.ingestion.invoke_arn
}

# Lambda Permission for API Gateway
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingestion.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [
    aws_api_gateway_method.ingest_post,
    aws_api_gateway_integration.ingest_integration
  ]

  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = var.environment
}

