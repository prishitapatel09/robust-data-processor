# Simple script to upload Lambda function via S3
# Usage: .\scripts\upload_lambda_simple.ps1 -BucketName "your-bucket" -ZipFile "worker.zip" -FunctionName "robust-data-processor-worker-production"

param(
    [Parameter(Mandatory=$true)]
    [string]$BucketName,
    
    [Parameter(Mandatory=$true)]
    [string]$ZipFile,
    
    [Parameter(Mandatory=$true)]
    [string]$FunctionName,
    
    [Parameter(Mandatory=$false)]
    [string]$Region = "ap-south-1"
)

Write-Host "Uploading Lambda function via S3..." -ForegroundColor Green
Write-Host "Bucket: $BucketName" -ForegroundColor Cyan
Write-Host "Zip File: $ZipFile" -ForegroundColor Cyan
Write-Host "Function: $FunctionName" -ForegroundColor Cyan
Write-Host "Region: $Region" -ForegroundColor Cyan
Write-Host ""

# Check if zip file exists
if (-not (Test-Path $ZipFile)) {
    Write-Host "Error: $ZipFile not found in current directory" -ForegroundColor Red
    exit 1
}

# Upload to S3
Write-Host "Step 1: Uploading $ZipFile to S3..." -ForegroundColor Yellow
aws s3 cp $ZipFile "s3://$BucketName/$ZipFile" --region $Region
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to upload to S3" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Uploaded to S3 successfully!" -ForegroundColor Green
Write-Host ""

# Update Lambda function
Write-Host "Step 2: Updating Lambda function from S3..." -ForegroundColor Yellow
aws lambda update-function-code --function-name $FunctionName --s3-bucket $BucketName --s3-key $ZipFile --region $Region
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to update Lambda function" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Lambda function updated successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Done! Your Lambda function is now updated! 🚀" -ForegroundColor Green

