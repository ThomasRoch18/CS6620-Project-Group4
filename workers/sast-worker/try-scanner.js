// Runs the provided scanner on a file, on your laptop. No AWS needed.
//
//   cd workers/sast-worker
//   SAST_SCANNER_PATH=../../sast/backend/scanner node try-scanner.js ../test-files/vulnerable.js

const fs = require("fs");
const { scanCode, countSeverities } = require("./scan-adapter");

async function main() {
  const file = process.argv[2] || "../test-files/vulnerable.js";
  const result = await scanCode(fs.readFileSync(file, "utf8"));
  console.log(JSON.stringify(result, null, 2));
  console.log("\nSeverity counts:", countSeverities(result));
}

main();
