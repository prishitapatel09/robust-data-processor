# Package Lambda functions for deployment (PowerShell) - Node.js
# Run this script from the project root

Write-Host "Packaging Lambda functions..." -ForegroundColor Green

# Clean previous packages
if (Test-Path "ingestion.zip") { Remove-Item "ingestion.zip" }
if (Test-Path "worker.zip") { Remove-Item "worker.zip" }

# Package Ingestion Lambda
Write-Host "Packaging Ingestion Lambda..." -ForegroundColor Yellow
Push-Location "lambda\ingestion"
if (Test-Path "node_modules") { Remove-Item "node_modules" -Recurse -Force }
npm install --production --silent
Get-ChildItem -Path . -Exclude "node_modules\**" | Compress-Archive -DestinationPath "..\..\ingestion.zip" -Force
Pop-Location

# Package Worker Lambda
Write-Host "Packaging Worker Lambda..." -ForegroundColor Yellow
Push-Location "lambda\worker"
if (Test-Path "node_modules") { Remove-Item "node_modules" -Recurse -Force }
npm install --production --silent
Get-ChildItem -Path . -Recurse -Exclude "node_modules\**" | Compress-Archive -DestinationPath "..\..\worker.zip" -Force
Pop-Location

Write-Host "Packaging complete!" -ForegroundColor Green
Write-Host "Files created: ingestion.zip, worker.zip" -ForegroundColor Green
