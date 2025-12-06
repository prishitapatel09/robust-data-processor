# Test API endpoints
# Usage: .\scripts\test_api.ps1 -ApiUrl "https://your-api-url/ingest"

param(
    [Parameter(Mandatory=$true)]
    [string]$ApiUrl
)

Write-Host "Testing Robust Data Processor API..." -ForegroundColor Green
Write-Host "API URL: $ApiUrl" -ForegroundColor Cyan
Write-Host ""

# Test 1: JSON Ingestion
Write-Host "Test 1: JSON Ingestion" -ForegroundColor Yellow
$jsonBody = @{
    tenant_id = "acme"
    log_id = "test-json-001"
    text = "User 555-0199 accessed the system at 10:00 AM"
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Uri $ApiUrl -Method Post -ContentType "application/json" -Body $jsonBody
    Write-Host "✓ JSON test passed" -ForegroundColor Green
    Write-Host "  Response: $($response | ConvertTo-Json)" -ForegroundColor Gray
} catch {
    Write-Host "✗ JSON test failed: $_" -ForegroundColor Red
}
Write-Host ""

# Test 2: TXT Ingestion
Write-Host "Test 2: TXT Ingestion" -ForegroundColor Yellow
$headers = @{
    "Content-Type" = "text/plain"
    "X-Tenant-ID" = "beta_inc"
}
$txtBody = "User 555-0123 accessed the database at 11:30 AM"

try {
    $response = Invoke-RestMethod -Uri $ApiUrl -Method Post -Headers $headers -Body $txtBody
    Write-Host "✓ TXT test passed" -ForegroundColor Green
    Write-Host "  Response: $($response | ConvertTo-Json)" -ForegroundColor Gray
} catch {
    Write-Host "✗ TXT test failed: $_" -ForegroundColor Red
}
Write-Host ""

Write-Host "Testing complete!" -ForegroundColor Green
Write-Host "Check DynamoDB console to verify data was stored." -ForegroundColor Cyan

