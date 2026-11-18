// Deliberately insecure sample with one example of each of the 10 vulnerability
// types the SAST scanner looks for. Used to test the "10/10 detected"
// success criterion. If one isn't detected, compare it with the patterns in
// scanner.js and adjust the example.

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

// 1. Hardcoded secret
const apiKey = "sk_live_51H8xYzABCDEF1234567890abcdef";
const password = "admin123";

function routes(app, db, User) {
  // 2. SQL injection
  app.get("/user", (req, res) => {
    db.query("SELECT * FROM users WHERE id = " + req.query.id);
  });

  // 3. NoSQL injection
  app.post("/login", (req, res) => {
    User.find(req.body); // user input goes straight into the query
  });

  // 4. Cross-site scripting (XSS)
  app.get("/search", (req, res) => {
    const page = { innerHTML: "" };
    page.innerHTML = req.query.q; // user input inserted as HTML
    res.send(page.innerHTML);
  });

  // 5. Path traversal
  app.get("/file", (req, res) => {
    fs.readFile(path.join(__dirname, req.query.name), (err, data) => res.send(data));
  });

  // 6. Insecure function
  app.post("/calc", (req, res) => {
    res.send(String(eval(req.body.expression)));
  });
}

// 7. Hardcoded IP address
const dbHost = "192.168.1.50";

// 8. Weak randomness used for a security token
const sessionToken = Math.random().toString(36).substring(2);

// 9. Sensitive data in logs
console.log("User password is: " + password);

// 10. Weak cryptography
const hash = crypto.createHash("md5").update(password).digest("hex");

module.exports = { routes, apiKey, dbHost, sessionToken, hash };
