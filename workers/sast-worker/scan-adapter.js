
const path = require("path");
const { pathToFileURL } = require("url");

// In the Docker image the provided code is copied to ./sast.
// On your laptop, set SAST_SCANNER_PATH=../../sast/backend/scanner
const scannerPath = process.env.SAST_SCANNER_PATH || "./sast/scanner";

// The provided scanner is an ES module, so it has to be loaded with
// import() instead of require()
let scannerPromise;
function loadScanner() {
  if (!scannerPromise) {
    const file = path.resolve(__dirname, scannerPath + ".js");
    scannerPromise = import(pathToFileURL(file).href);
  }
  return scannerPromise;
}

// Runs the provided scanner on a code snippet.
async function scanCode(code) {
  const scanner = await loadScanner();
  return scanner.scanCode(code);
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
