// The ONLY file that calls the provided SAST code (sast/backend/scanner.js).
// If the function names in scanner.js are different, fix them here.

const path = require("path");

// In the Docker image the provided code is copied to ./sast.
// On your laptop, set SAST_SCANNER_PATH=../../sast/backend/scanner
const scannerPath = process.env.SAST_SCANNER_PATH || "./sast/scanner";
const scanner = require(path.resolve(__dirname, scannerPath));

// Runs the provided scanner on a code snippet.
async function scanCode(code) {
  return scanner.scanCode(code); // TODO: check the real function name
}

// Counts findings by severity, e.g. { HIGH: 2, MEDIUM: 1, LOW: 0 }.
// This summary is saved in DynamoDB for the dashboard and alerts.
function countSeverities(result) {
  const findings = result; // scanCode returns a list of findings
  const counts = { HIGH: 0, MEDIUM: 0, LOW: 0 };
  for (const finding of findings) {
    const severity = String(finding.severity).toUpperCase();
    counts[severity] = (counts[severity] || 0) + 1;
  }
  return counts;
}

module.exports = { scanCode, countSeverities };
