const { SQSClient, SendMessageCommand } = require('@aws-sdk/client-sqs');

const sqsClient = new SQSClient({});
const SQS_QUEUE_URL = process.env.SQS_QUEUE_URL;

/**
 * Normalize data from different formats (JSON/TXT) into a single internal flat format.
 * 
 * This function ensures that regardless of input format (JSON with nested structure
 * or plain TXT), all data is normalized to a flat, consistent structure with:
 * - tenant_id: Identifies the tenant (from JSON or X-Tenant-ID header)
 * - log_id: Unique log identifier (from JSON or generated)
 * - text: The actual log content (extracted from JSON or raw body)
 * - source: Origin format (json_upload or text_upload)
 * - timestamp: ISO 8601 timestamp of ingestion
 * 
 * Both JSON and TXT inputs converge to this same flat structure, eliminating
 * format differences and ensuring consistent processing downstream.
 * 
 * @param {string} tenant_id - Tenant identifier (required)
 * @param {string} log_id - Log identifier (required)
 * @param {string} text - Log text content (required)
 * @param {string} source - Source format indicator ('json_upload' or 'text_upload')
 * @returns {Object} Flat object with normalized fields (no nesting)
 */
function normalizeToInternalFormat(tenant_id, log_id, text, source) {
    return {
        tenant_id: tenant_id,
        log_id: log_id,
        text: text,
        source: source,
        timestamp: new Date().toISOString()
    };
}

/**
 * Parse and validate JSON payload, then normalize to internal flat format.
 * 
 * Expected JSON format:
 * {
 *     "tenant_id": "acme",
 *     "log_id": "123",
 *     "text": "User 555-0199 accessed..."
 * }
 * 
 * This function extracts data from JSON structure and normalizes it to the
 * same flat format used for TXT inputs, ensuring format consistency.
 * 
 * @param {string} body - JSON string payload
 * @returns {Object} Normalized flat object matching internal format
 * @throws {Error} If JSON is invalid or required fields are missing
 */
function handleJsonPayload(body) {
    let data;
    try {
        data = JSON.parse(body);
    } catch (error) {
        throw new Error(`Invalid JSON format: ${error.message}`);
    }
    
    // Validate required fields
    if (!data.tenant_id || !data.log_id || !data.text) {
        throw new Error('Missing required fields: tenant_id, log_id, text');
    }
    
    if (typeof data.tenant_id !== 'string' || !data.tenant_id.trim()) {
        throw new Error('tenant_id must be a non-empty string');
    }
    
    if (typeof data.log_id !== 'string' || !data.log_id.trim()) {
        throw new Error('log_id must be a non-empty string');
    }
    
    if (typeof data.text !== 'string') {
        throw new Error('text must be a string');
    }
    
    return normalizeToInternalFormat(
        data.tenant_id.trim(),
        data.log_id.trim(),
        data.text,
        'json_upload'
    );
}

/**
 * Parse and validate TXT payload, then normalize to internal flat format.
 * 
 * Expected format:
 * - Header: X-Tenant-ID: acme (required)
 * - Header: X-Log-ID: 123 (optional, auto-generated if missing)
 * - Body: Raw text content
 * 
 * This function extracts tenant_id from header and uses body as text,
 * then normalizes to the same flat format used for JSON inputs,
 * ensuring both formats converge to identical structure.
 * 
 * @param {string} body - Raw text body
 * @param {Object} headers - Request headers (case-insensitive)
 * @returns {Object} Normalized flat object matching internal format
 * @throws {Error} If required header is missing
 */
function handleTextPayload(body, headers) {
    // Headers are already lowercased in handler
    const tenant_id = headers['x-tenant-id'];
    
    if (!tenant_id || !tenant_id.trim()) {
        throw new Error('Missing required header: X-Tenant-ID');
    }
    
    // Generate log_id from timestamp if not provided
    let log_id = headers['x-log-id'];
    if (!log_id) {
        log_id = `log_${Date.now()}`;
    }
    
    return normalizeToInternalFormat(
        tenant_id.trim(),
        log_id.trim(),
        body,
        'text_upload'
    );
}

/**
 * Publish normalized message to SQS queue.
 * This is non-blocking and async.
 * 
 * @param {Object} message - Normalized message object
 * @returns {Promise} SQS send message promise
 */
async function publishToSQS(message) {
    if (!SQS_QUEUE_URL) {
        throw new Error('SQS_QUEUE_URL environment variable not set');
    }
    
    const command = new SendMessageCommand({
        QueueUrl: SQS_QUEUE_URL,
        MessageBody: JSON.stringify(message)
    });
    
    return sqsClient.send(command);
}

/**
 * Lambda handler for API Gateway /ingest endpoint.
 * 
 * Handles both JSON and TXT payloads:
 * - JSON: Content-Type: application/json
 * - TXT: Content-Type: text/plain with X-Tenant-ID header
 * 
 * @param {Object} event - API Gateway event
 * @param {Object} context - Lambda context
 * @returns {Promise<Object>} API Gateway response
 */
exports.handler = async (event) => {
    try {
        // Extract headers (normalize to lowercase for case-insensitive matching)
        const headers = {};
        if (event.headers) {
            Object.keys(event.headers).forEach(key => {
                headers[key.toLowerCase()] = event.headers[key];
            });
        }
        const content_type = headers['content-type'] || '';
        
        // Get request body
        let body = event.body || '';
        if (event.isBase64Encoded) {
            body = Buffer.from(body, 'base64').toString('utf-8');
        }
        
        let normalized_message;
        
        // Determine payload type and normalize to single internal flat format
        // Both JSON and TXT inputs converge to the same flat structure here
        if (content_type.includes('application/json')) {
            // JSON input: Extract from structured JSON, normalize to flat format
            normalized_message = handleJsonPayload(body);
        } else if (content_type.includes('text/plain') || content_type.includes('text/')) {
            // TXT input: Extract tenant from header, body as text, normalize to flat format
            normalized_message = handleTextPayload(body, headers);
        } else {
            return {
                statusCode: 400,
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    error: 'Unsupported Content-Type. Use application/json or text/plain'
                })
            };
        }
        
        // Publish to SQS (async, non-blocking)
        await publishToSQS(normalized_message);
        
        // Return 202 Accepted immediately (non-blocking)
        return {
            statusCode: 202,
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                message: 'Request accepted for processing',
                tenant_id: normalized_message.tenant_id,
                log_id: normalized_message.log_id
            })
        };
    
    } catch (error) {
        // Validation errors (400)
        if (error.message.includes('Missing') || 
            error.message.includes('must be') || 
            error.message.includes('Invalid')) {
            return {
                statusCode: 400,
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    error: error.message
                })
            };
        }
        
        // Internal server errors (500)
        console.error('Error processing request:', error);
        return {
            statusCode: 500,
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                error: 'Internal server error',
                message: error.message
            })
        };
    }
};
