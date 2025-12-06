# Upload Lambda functions via S3 (for large zip files)
# Usage: .\scripts\upload_via_s3.ps1 -BucketName "your-bucket-name"

param(
    [Parameter(Mandatory=$true)]
    [string]$BucketName,
    
    [Parameter(Mandatory=$false)]
    [string]$Region = "us-east-1"
)

Write-Host "Uploading Lambda functions via S3..." -ForegroundColor Green
Write-Host "Bucket: $BucketName" -ForegroundColor Cyan
Write-Host "Region: $Region" -ForegroundColor Cyan
Write-Host ""

# Check if zip files exist
if (-not (Test-Path "worker.zip")) {
    Write-Host "Error: worker.zip not found in current directory" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path "ingestion.zip")) {
    Write-Host "Error: ingestion.zip not found in current directory" -ForegroundColor Red
    exit 1
}

# Upload Worker Lambda
Write-Host "Uploading worker.zip to S3..." -ForegroundColor Yellow
aws s3 cp worker.zip "s3://$BucketName/worker.zip" --region $Region
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error uploading worker.zip to S3" -ForegroundColor Red
    exit 1
}

Write-Host "Updating Worker Lambda function..." -ForegroundColor Yellow
aws lambda update-function-code `
    --function-name robust-data-processor-worker-production `
    --s3-bucket $BucketName `
    --s3-key worker.zip `
    --region $Region
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error updating Worker Lambda" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Worker Lambda updated successfully!" -ForegroundColor Green
Write-Host ""

# Upload Ingestion Lambda
Write-Host "Uploading ingestion.zip to S3..." -ForegroundColor Yellow
aws s3 cp ingestion.zip "s3://$BucketName/ingestion.zip" --region $Region
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error uploading ingestion.zip to S3" -ForegroundColor Red
    exit 1
}

Write-Host "Updating Ingestion Lambda function..." -ForegroundColor Yellow
aws lambda update-function-code `
    --function-name robust-data-processor-ingestion-production `
    --s3-bucket $BucketName `
    --s3-key ingestion.zip `
    --region $Region
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error updating Ingestion Lambda" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Ingestion Lambda updated successfully!" -ForegroundColor Green
Write-Host ""

Write-Host "All Lambda functions updated successfully via S3! 🚀" -ForegroundColor Green

