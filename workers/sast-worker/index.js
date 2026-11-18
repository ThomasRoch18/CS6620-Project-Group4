// SAST worker: a Lambda function triggered by the SAST SQS queue.
//
// For each scan request it:
//   1. marks the job RUNNING
//   2. runs the provided SAST scanner on the code
//   3. saves the report to S3
//   4. marks the job COMPLETE
//
// If something unexpected goes wrong, the error makes Lambda report a
// failure, so SQS sends the message again later. After 3 tries, SQS moves
// the message to the dead-letter queue (DLQ).

const { markRunning, markComplete, markFailed, saveReport } = require("./shared/jobs");
const { scanCode, countSeverities } = require("./scan-adapter");

// Lambda calls this with messages from SQS. The queue trigger is set to
// batch size 1, so there is one message each time.
exports.handler = async (event) => {
  for (const record of event.Records) {
    const message = JSON.parse(record.body); // e.g. { "scanId": "...", "code": "..." }
    await runScan(message);
  }
};

async function runScan({ scanId, code }) {
  console.log(`Scan ${scanId}: received`);

  // 1. QUEUED -> RUNNING. If this doesn't work, the job is already
  //    finished or doesn't exist, so there is nothing to do.
  const started = await markRunning(scanId);
  if (!started) {
    console.log(`Scan ${scanId}: skipped (already finished or not found)`);
    return;
  }

  // Bad input: retrying would fail the same way, so mark FAILED now.
  if (typeof code !== "string" || code.trim() === "") {
    await markFailed(scanId, "No code was provided");
    console.log(`Scan ${scanId}: FAILED (no code)`);
    return;
  }

  // 2-4. Scan, save the report, mark COMPLETE.
  const result = await scanCode(code);
  const reportKey = await saveReport(scanId, "SAST", result);
  const counts = countSeverities(result);
  await markComplete(scanId, counts, reportKey);
  console.log(`Scan ${scanId}: COMPLETE`, JSON.stringify(counts));
}
