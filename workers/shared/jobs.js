// Helpers used by BOTH workers:
//   - change a job's status in DynamoDB
//   - save a scan report to S3
//
// A job moves through these statuses:
//
//   QUEUED --> RUNNING --> COMPLETE
//                     \--> FAILED

const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, UpdateCommand } = require("@aws-sdk/lib-dynamodb");
const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");

// Names come from environment variables, so nothing is hardcoded.
const TABLE_NAME = process.env.TABLE_NAME;
const BUCKET_NAME = process.env.BUCKET_NAME;

// No access keys in the code: on AWS, the SDK automatically uses the
// temporary credentials of the role the worker runs as (LabRole).
const db = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const s3 = new S3Client({});

function now() {
  return new Date().toISOString();
}

// Runs one DynamoDB update.
// Returns true if it worked, or false if its condition was not met
// (for example, the job had already finished).
async function runUpdate(params) {
  try {
    await db.send(new UpdateCommand({ TableName: TABLE_NAME, ...params }));
    return true;
  } catch (err) {
    if (err.name === "ConditionalCheckFailedException") return false;
    throw err; // any other error is a real problem
  }
}

// About the updates below:
// - Each one has a ConditionExpression. DynamoDB only makes the change if
//   the condition is true. This is a "conditional write": it stops a retried
//   message from overwriting a job that has already finished.
// - "status" is a reserved word in DynamoDB, so we write #status and say
//   what it means in ExpressionAttributeNames.
// - activeStatus only exists while a job is QUEUED or RUNNING, so the
//   sweeper can quickly find jobs that are stuck.

// QUEUED -> RUNNING
// (RUNNING is also allowed, because a retry finds the job still RUNNING.)
function markRunning(scanId) {
  return runUpdate({
    Key: { scanId },
    UpdateExpression: "SET #status = :running, activeStatus = :running, updatedAt = :now",
    ConditionExpression: "#status = :queued OR #status = :running",
    ExpressionAttributeNames: { "#status": "status" },
    ExpressionAttributeValues: { ":queued": "QUEUED", ":running": "RUNNING", ":now": now() },
  });
}

// RUNNING -> COMPLETE, saving the summary counts and where the report is.
function markComplete(scanId, severityCounts, s3ReportKey) {
  return runUpdate({
    Key: { scanId },
    UpdateExpression:
      "SET #status = :complete, severityCounts = :counts, s3ReportKey = :key, updatedAt = :now REMOVE activeStatus",
    ConditionExpression: "#status = :running",
    ExpressionAttributeNames: { "#status": "status" },
    ExpressionAttributeValues: {
      ":running": "RUNNING",
      ":complete": "COMPLETE",
      ":counts": severityCounts,
      ":key": s3ReportKey,
      ":now": now(),
    },
  });
}

// QUEUED or RUNNING -> FAILED, with a short reason for the dashboard.
function markFailed(scanId, reason) {
  return runUpdate({
    Key: { scanId },
    UpdateExpression: "SET #status = :failed, errorMessage = :reason, updatedAt = :now REMOVE activeStatus",
    ConditionExpression: "#status = :queued OR #status = :running",
    ExpressionAttributeNames: { "#status": "status" },
    ExpressionAttributeValues: {
      ":queued": "QUEUED",
      ":running": "RUNNING",
      ":failed": "FAILED",
      ":reason": reason,
      ":now": now(),
    },
  });
}

// Saves the full report to S3 as reports/{scanId}.json and returns that key.
async function saveReport(scanId, type, result) {
  const key = `reports/${scanId}.json`;
  const report = { scanId, type, scannedAt: now(), result };
  await s3.send(
    new PutObjectCommand({
      Bucket: BUCKET_NAME,
      Key: key,
      Body: JSON.stringify(report, null, 2),
      ContentType: "application/json",
    })
  );
  return key;
}

module.exports = { markRunning, markComplete, markFailed, saveReport };
