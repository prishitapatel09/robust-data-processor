#!/bin/bash
# Package Lambda functions for deployment (Node.js)

set -e

echo "Packaging Lambda functions..."

# Clean previous packages
rm -f ingestion.zip worker.zip

# Package Ingestion Lambda
echo "Packaging Ingestion Lambda..."
cd lambda/ingestion
rm -rf node_modules
npm install --production --silent
zip -r ../../ingestion.zip . -x "node_modules/**" "*.zip"
cd ../..

# Package Worker Lambda
echo "Packaging Worker Lambda..."
cd lambda/worker
rm -rf node_modules
npm install --production --silent
zip -r ../../worker.zip . -x "node_modules/**" "*.zip"
cd ../..

echo "Packaging complete!"
echo "Files created: ingestion.zip, worker.zip"
