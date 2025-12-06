# Load test script - Send 1000 requests per minute
# Usage: .\scripts\load_test.ps1 -ApiUrl "https://your-api-url/ingest" -TotalRequests 1000

param(
    [Parameter(Mandatory=$true)]
    [string]$ApiUrl,
    
    [Parameter(Mandatory=$false)]
    [int]$TotalRequests = 1000,
    
    [Parameter(Mandatory=$false)]
    [int]$ConcurrentRequests = 50
)

Write-Host "Starting load test..." -ForegroundColor Green
Write-Host "API URL: $ApiUrl" -ForegroundColor Cyan
Write-Host "Total Requests: $TotalRequests" -ForegroundColor Cyan
Write-Host "Concurrent Requests: $ConcurrentRequests" -ForegroundColor Cyan
Write-Host ""

$startTime = Get-Date
$successCount = 0
$failureCount = 0

$scriptBlock = {
    param($url, $requestId)
    
    # Alternate between JSON and TXT
    if ($requestId % 2 -eq 0) {
        # JSON request
        $body = @{
            tenant_id = "acme"
            log_id = "load-$requestId"
            text = "Test log message number $requestId"
        } | ConvertTo-Json
        
        try {
            $response = Invoke-RestMethod -Uri $url -Method Post -ContentType "application/json" -Body $body -TimeoutSec 5
            return @{ Success = $true; RequestId = $requestId }
        } catch {
            return @{ Success = $false; RequestId = $requestId; Error = $_.Exception.Message }
        }
    } else {
        # TXT request
        $headers = @{
            "Content-Type" = "text/plain"
            "X-Tenant-ID" = "beta_inc"
        }
        $body = "Test log message number $requestId"
        
        try {
            $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body -TimeoutSec 5
            return @{ Success = $true; RequestId = $requestId }
        } catch {
            return @{ Success = $false; RequestId = $requestId; Error = $_.Exception.Message }
        }
    }
}

# Create jobs
Write-Host "Sending requests..." -ForegroundColor Yellow
$jobs = 1..$TotalRequests | ForEach-Object {
    Start-Job -ScriptBlock $scriptBlock -ArgumentList $ApiUrl, $_
}

# Wait for all jobs and collect results
$results = $jobs | Wait-Job | Receive-Job
$jobs | Remove-Job

# Count successes and failures
$results | ForEach-Object {
    if ($_.Success) {
        $script:successCount++
    } else {
        $script:failureCount++
        if ($failureCount -le 10) {
            Write-Host "Failed request $($_.RequestId): $($_.Error)" -ForegroundColor Red
        }
    }
}

$endTime = Get-Date
$duration = ($endTime - $startTime).TotalSeconds
$rpm = [math]::Round(($TotalRequests / $duration) * 60, 2)

Write-Host ""
Write-Host "Load test complete!" -ForegroundColor Green
Write-Host "Duration: $([math]::Round($duration, 2)) seconds" -ForegroundColor Cyan
Write-Host "Requests Per Minute: $rpm" -ForegroundColor Cyan
Write-Host "Successful: $successCount" -ForegroundColor Green
Write-Host "Failed: $failureCount" -ForegroundColor $(if ($failureCount -eq 0) { "Green" } else { "Red" })
Write-Host "Success Rate: $([math]::Round(($successCount / $TotalRequests) * 100, 2))%" -ForegroundColor Cyan

