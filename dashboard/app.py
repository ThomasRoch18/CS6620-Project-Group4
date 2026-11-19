"""Unified Security Hub dashboard (Flask).

Creates scan jobs in DynamoDB, enqueues them on SQS, and shows status and reports.
Follows docs/contracts.md. All resource names come from environment variables.
"""
import json
import os
import time
import uuid
from datetime import datetime, timezone
from urllib.parse import urlparse

import boto3
from botocore.exceptions import ClientError
from flask import Flask, abort, jsonify, redirect, render_template, request, url_for

REGION = os.environ.get("AWS_REGION", "us-east-1")
TABLE_NAME = os.environ["TABLE_NAME"]
REPORTS_BUCKET = os.environ["REPORTS_BUCKET"]
SAST_QUEUE_URL = os.environ["SAST_QUEUE_URL"]
PENTEST_QUEUE_URL = os.environ["PENTEST_QUEUE_URL"]
DEFAULT_TEAM = os.environ.get("DEFAULT_TEAM", "team-a")
TTL_DAYS = int(os.environ.get("TTL_DAYS", "30"))
MAX_SNIPPET_BYTES = 200_000  # keeps the SQS message well under its size limit

table = boto3.resource("dynamodb", region_name=REGION).Table(TABLE_NAME)
sqs = boto3.client("sqs", region_name=REGION)
s3 = boto3.client("s3", region_name=REGION)

app = Flask(__name__)


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def create_job(scan_id, scan_type, target, team_id):
    """Write the job as QUEUED. Fails if the scanId already exists."""
    ts = now_iso()
    table.put_item(
        Item={
            "scanId": scan_id,
            "teamId": team_id,
            "type": scan_type,
            "target": target,
            "status": "QUEUED",
            "activeStatus": "ACTIVE",  # sparse GSI2 key, removed when the job finishes
            "createdAt": ts,
            "updatedAt": ts,
            "attempts": 0,
            "ttl": int(time.time()) + TTL_DAYS * 86400,
        },
        ConditionExpression="attribute_not_exists(scanId)",
    )


def mark_failed(scan_id, message):
    """Used only when the job could not be queued; workers and the reconciler handle the rest."""
    try:
        table.update_item(
            Key={"scanId": scan_id},
            UpdateExpression="SET #s = :f, errorMessage = :m, updatedAt = :u REMOVE activeStatus",
            ConditionExpression="#s IN (:q, :r)",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={":f": "FAILED", ":m": message, ":u": now_iso(),
                                       ":q": "QUEUED", ":r": "RUNNING"},
        )
    except ClientError:
        pass


def enqueue(scan_id, queue_url, message):
    try:
        sqs.send_message(QueueUrl=queue_url, MessageBody=json.dumps(message))
    except ClientError as exc:
        mark_failed(scan_id, f"Could not queue scan: {exc.response['Error']['Code']}")
        raise


@app.get("/health")
def health():
    # No AWS calls here, so an AWS hiccup never takes the instance out of the ALB.
    return "ok", 200


@app.get("/")
def index():
    return render_template("index.html", team=DEFAULT_TEAM, error=request.args.get("error"))


@app.post("/scans/sast")
def submit_sast():
    team = request.form.get("teamId") or DEFAULT_TEAM
    code = request.form.get("code", "")
    if not code.strip():
        return redirect(url_for("index", error="Paste some JavaScript to scan."))
    if len(code.encode()) > MAX_SNIPPET_BYTES:
        return redirect(url_for("index", error="That snippet is over 200 KB. Upload it as a zip instead."))
    scan_id = str(uuid.uuid4())
    preview = code.strip().splitlines()[0][:80]
    create_job(scan_id, "SAST", f"Snippet: {preview}", team)
    enqueue(scan_id, SAST_QUEUE_URL,
            {"scanId": scan_id, "type": "SAST", "mode": "snippet", "code": code, "teamId": team})
    return redirect(url_for("scan_detail", scan_id=scan_id))


@app.post("/scans/pentest")
def submit_pentest():
    team = request.form.get("teamId") or DEFAULT_TEAM
    target = request.form.get("targetUrl", "").strip()
    parsed = urlparse(target)
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        return redirect(url_for("index", error="Enter a full API URL starting with http:// or https://."))
    scan_id = str(uuid.uuid4())
    create_job(scan_id, "PENTEST", target, team)
    enqueue(scan_id, PENTEST_QUEUE_URL,
            {"scanId": scan_id, "type": "PENTEST", "targetUrl": target, "teamId": team})
    return redirect(url_for("scan_detail", scan_id=scan_id))


@app.post("/api/uploads")
def presign_upload():
    """Zip scan, step 1: give the browser a short-lived URL to PUT the zip straight into S3."""
    scan_id = str(uuid.uuid4())
    key = f"uploads/{scan_id}.zip"
    url = s3.generate_presigned_url(
        "put_object",
        Params={"Bucket": REPORTS_BUCKET, "Key": key, "ContentType": "application/zip"},
        ExpiresIn=300,
    )
    return jsonify({"scanId": scan_id, "uploadUrl": url, "s3Key": key})


@app.post("/api/scans/zip")
def submit_zip():
    """Zip scan, step 2: the upload finished, so create the job and enqueue only the S3 key."""
    body = request.get_json(force=True)
    scan_id = body.get("scanId", "")
    team = body.get("teamId") or DEFAULT_TEAM
    try:
        uuid.UUID(scan_id)
    except ValueError:
        return jsonify({"error": "Invalid scan id."}), 400
    key = f"uploads/{scan_id}.zip"
    try:
        s3.head_object(Bucket=REPORTS_BUCKET, Key=key)
    except ClientError:
        return jsonify({"error": "Upload not found. Upload the zip again."}), 400
    create_job(scan_id, "SAST", key, team)
    enqueue(scan_id, SAST_QUEUE_URL,
            {"scanId": scan_id, "type": "SAST", "mode": "zip", "s3Key": key, "teamId": team})
    return jsonify({"scanId": scan_id, "redirect": url_for("scan_detail", scan_id=scan_id)})


@app.get("/scans")
def scan_list():
    team = request.args.get("team") or DEFAULT_TEAM
    resp = table.query(
        IndexName="GSI1",
        KeyConditionExpression="teamId = :t",
        ExpressionAttributeValues={":t": team},
        ScanIndexForward=False,  # newest first
        Limit=50,
    )
    return render_template("scans.html", scans=resp.get("Items", []), team=team)


def load_scan(scan_id):
    item = table.get_item(Key={"scanId": scan_id}).get("Item")
    if not item:
        abort(404)
    return item


@app.get("/scans/<scan_id>")
def scan_detail(scan_id):
    item = load_scan(scan_id)
    report = None
    if item.get("status") == "COMPLETE" and item.get("s3ReportKey"):
        try:
            obj = s3.get_object(Bucket=REPORTS_BUCKET, Key=item["s3ReportKey"])
            report = json.loads(obj["Body"].read())
        except (ClientError, ValueError):
            report = None
    return render_template("scan.html", scan=item,
                           report_json=json.dumps(report, indent=2) if report else None)


@app.get("/api/scans/<scan_id>")
def scan_status(scan_id):
    item = load_scan(scan_id)
    return jsonify({"scanId": scan_id, "status": item.get("status"), "updatedAt": item.get("updatedAt")})


@app.template_filter("sev")
def sev_filter(item, level):
    return int((item.get("severityCounts") or {}).get(level, 0))


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "5000")), debug=True)
