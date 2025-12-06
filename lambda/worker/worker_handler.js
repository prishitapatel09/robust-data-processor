const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, GetCommand, PutCommand } = require('@aws-sdk/lib-dynamodb');

const dynamoClient = new DynamoDBClient({});
const dynamodb = DynamoDBDocumentClient.from(dynamoClient);

const TABLE_NAME = process.env.DYNAMODB_TABLE_NAME || 'robust-data-processor-logs';

/**
 * Simulate heavy CPU-bound processing.
 * Sleep for 0.05s per character.
 * 
 * In this case, we'll simulate processing by:
 * 1. Sleeping for 0.05s per character
 * 2. Creating a simple transformation (e.g., redacting sensitive data)
 * 
 * @param {string} text - Text to process
 * @returns {Promise<string>} Processed text
 */
function simulateHeavyProcessing(text) {
    return new Promise((resolve) => {
        // Calculate sleep time (0.05s per character)
        const sleepTime = text.length * 50; // 50ms per character = 0.05s
        
        // Simulate processing: Redact phone numbers as an example
        setTimeout(() => {
            // Simple phone number redaction pattern
            const phonePattern = /\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/g;
            const processedText = text.replace(phonePattern, '[REDACTED]');
            resolve(processedText);
        }, sleepTime);
    });
}

/**
 * Check if this log_id has already been processed (idempotency check).
 * Prevents duplicate processing if worker crashes and message is retried.
 * 
 * @param {string} tenant_id - Tenant identifier
 * @param {string} log_id - Log identifier
 * @returns {Promise<boolean>} True if already processed, false otherwise
 */
async function checkIfAlreadyProcessed(tenant_id, log_id) {
    try {
        const command = new GetCommand({
            TableName: TABLE_NAME,
            Key: {
                tenant_id: tenant_id,
                log_id: log_id
            },
            ProjectionExpression: 'log_id' // Only fetch the key
        });
        
        const response = await dynamodb.send(command);
        return !!response.Item;
    } catch (error) {
        console.error(`Error checking if processed: ${error.message}`);
        // If check fails, proceed with processing (fail-open)
        return false;
    }
}

/**
 * Store processed log in DynamoDB with multi-tenant isolation.
 * 
 * Structure:
 * - Partition Key: tenant_id (strictly isolates tenants)
 * - Sort Key: log_id (unique within tenant)
 * 
 * @param {Object} message - Normalized message object
 * @param {string} processedText - Processed text
 * @returns {Promise<void>}
 */
async function storeProcessedLog(message, processedText) {
    const tenant_id = message.tenant_id;
    const log_id = message.log_id;
    
    const item = {
        tenant_id: tenant_id,
        log_id: log_id,
        source: message.source,
        original_text: message.text,
        modified_data: processedText,
        processed_at: new Date().toISOString(),
        ingestion_timestamp: message.timestamp || '',
        text_length: message.text.length
    };
    
    // Use PutItem with conditional expression to prevent overwrites
    // This ensures idempotency
    try {
        const command = new PutCommand({
            TableName: TABLE_NAME,
            Item: item,
            ConditionExpression: 'attribute_not_exists(log_id)'
        });
        
        await dynamodb.send(command);
    } catch (error) {
        if (error.name === 'ConditionalCheckFailedException') {
            // Item already exists, which is fine (idempotency)
            console.log(`Log ${log_id} for tenant ${tenant_id} already processed (skipping)`);
        } else {
            console.error(`Error storing log: ${error.message}`);
            throw error;
        }
    }
}

/**
 * Worker Lambda handler triggered by SQS events.
 * 
 * This function:
 * 1. Processes messages from SQS
 * 2. Simulates heavy processing
 * 3. Stores results in DynamoDB with tenant isolation
 * 4. Handles batch processing (SQS can send multiple records)
 * 
 * @param {Object} event - SQS event with Records array
 * @param {Object} context - Lambda context
 * @returns {Promise<Object>} Processing results
 */
exports.handler = async (event) => {
    let recordsProcessed = 0;
    let recordsFailed = 0;
    
    // Process each record in the batch
    for (const record of event.Records || []) {
        try {
            // Parse SQS message
            const messageBody = record.body || '';
            const message = JSON.parse(messageBody);
            
            const tenant_id = message.tenant_id;
            const log_id = message.log_id;
            const text = message.text || '';
            
            if (!tenant_id || !log_id || !text) {
                console.error(`Invalid message format: ${JSON.stringify(message)}`);
                recordsFailed++;
                continue;
            }
            
            // Check if already processed (idempotency)
            const alreadyProcessed = await checkIfAlreadyProcessed(tenant_id, log_id);
            if (alreadyProcessed) {
                console.log(`Log ${log_id} for tenant ${tenant_id} already processed, skipping`);
                recordsProcessed++;
                continue;
            }
            
            // Simulate heavy processing
            console.log(`Processing log ${log_id} for tenant ${tenant_id} (${text.length} chars)...`);
            const processedText = await simulateHeavyProcessing(text);
            
            // Store in DynamoDB
            await storeProcessedLog(message, processedText);
            
            console.log(`Successfully processed log ${log_id} for tenant ${tenant_id}`);
            recordsProcessed++;
        
        } catch (error) {
            console.error(`Error processing record: ${error.message}`);
            recordsFailed++;
            // Don't throw exception - let SQS handle retries via visibility timeout
            continue;
        }
    }
    
    return {
        statusCode: 200,
        processed: recordsProcessed,
        failed: recordsFailed
    };
};
