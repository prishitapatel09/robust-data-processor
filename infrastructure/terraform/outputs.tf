output "api_endpoint" {
  description = "API Gateway endpoint URL"
  value       = "${aws_api_gateway_deployment.api_deployment.invoke_url}/ingest"
}

output "sqs_queue_url" {
  description = "SQS Queue URL"
  value       = aws_sqs_queue.processing_queue.url
}

output "dynamodb_table_name" {
  description = "DynamoDB Table Name"
  value       = aws_dynamodb_table.logs_table.name
}

output "ingestion_lambda_arn" {
  description = "Ingestion Lambda Function ARN"
  value       = aws_lambda_function.ingestion.arn
}

output "worker_lambda_arn" {
  description = "Worker Lambda Function ARN"
  value       = aws_lambda_function.worker.arn
}

