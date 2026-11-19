"""Notifier: DynamoDB stream -> SNS email when a scan completes with HIGH findings.

Only fires on the transition into COMPLETE, so retries or later updates never send duplicates.
"""
import json
import os

import boto3

sns = boto3.client("sns")
TOPIC_ARN = os.environ["FINDINGS_TOPIC_ARN"]
DASHBOARD_URL = os.environ.get("DASHBOARD_URL", "").rstrip("/")


def _str(image, field):
    return (image.get(field) or {}).get("S", "")


def _high(image):
    counts = (image.get("severityCounts") or {}).get("M", {})
    return int((counts.get("HIGH") or {}).get("N", "0"))


def handler(event, context):
    sent = 0
    for record in event.get("Records", []):
        if record.get("eventName") not in ("INSERT", "MODIFY"):
            continue
        new = record["dynamodb"].get("NewImage", {})
        old = record["dynamodb"].get("OldImage", {})
        if _str(new, "status") != "COMPLETE" or _str(old, "status") == "COMPLETE":
            continue
        high = _high(new)
        if high == 0:
            continue

        scan_id = _str(new, "scanId")
        scan_type = "Code check" if _str(new, "type") == "SAST" else "API test"
        target = _str(new, "target")
        link = f"{DASHBOARD_URL}/scans/{scan_id}" if DASHBOARD_URL else f"Scan ID: {scan_id}"
        sns.publish(
            TopicArn=TOPIC_ARN,
            Subject=f"[Security Hub] {high} HIGH finding(s) in {scan_type.lower()}"[:100],
            Message=(
                f"{scan_type} finished with {high} HIGH severity finding(s).\n\n"
                f"Target: {target}\nTeam: {_str(new, 'teamId')}\n\nView the report: {link}\n"
            ),
            MessageAttributes={"severity": {"DataType": "String", "StringValue": "HIGH"}},
        )
        sent += 1
        print(json.dumps({"event": "alert_sent", "scanId": scan_id, "high": high}))
    return {"alertsSent": sent}
