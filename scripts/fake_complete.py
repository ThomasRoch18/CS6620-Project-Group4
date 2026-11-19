"""Stand-in for the real workers (Person 2) so the dashboard and alerts can be demoed now.

Usage:
  python scripts/fake_complete.py <scanId> [--high 2 --medium 3 --low 1]
  python scripts/fake_complete.py <scanId> --fail "Task exited with code 1"

It moves the job QUEUED -> RUNNING -> COMPLETE (or FAILED) using the same conditional
writes as contracts.md, and uploads a sample report to S3.
"""
import argparse
import json
import os
import time
from datetime import datetime, timezone

import boto3

REGION = os.environ.get("AWS_REGION", "us-east-1")
table = boto3.resource("dynamodb", region_name=REGION).Table(os.environ["TABLE_NAME"])
s3 = boto3.client("s3", region_name=REGION)
bucket = os.environ["REPORTS_BUCKET"]


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def transition(scan_id, frm, to, extra_set="", values=None, remove_active=False):
    values = dict(values or {})
    values.update({":from": frm, ":to": to, ":u": now()})
    expr = "SET #s = :to, updatedAt = :u" + extra_set + (" REMOVE activeStatus" if remove_active else "")
    table.update_item(Key={"scanId": scan_id}, UpdateExpression=expr,
                      ConditionExpression="#s = :from", ExpressionAttributeNames={"#s": "status"},
                      ExpressionAttributeValues=values)
    print(f"{scan_id}: {frm} -> {to}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scan_id")
    ap.add_argument("--high", type=int, default=2)
    ap.add_argument("--medium", type=int, default=3)
    ap.add_argument("--low", type=int, default=1)
    ap.add_argument("--fail")
    a = ap.parse_args()

    item = table.get_item(Key={"scanId": a.scan_id})["Item"]
    started = now()
    transition(a.scan_id, "QUEUED", "RUNNING", ", attempts = attempts + :one", {":one": 1})
    time.sleep(2)
    if a.fail:
        transition(a.scan_id, "RUNNING", "FAILED", ", errorMessage = :m", {":m": a.fail}, remove_active=True)
        return
    counts = {"HIGH": a.high, "MEDIUM": a.medium, "LOW": a.low}
    key = f"reports/{a.scan_id}.json"
    report = {"scanId": a.scan_id, "type": item["type"], "target": item["target"], "startedAt": started,
              "completedAt": now(), "summary": counts,
              "results": {"note": "Sample report from fake_complete.py; real workers put scanner output here."}}
    s3.put_object(Bucket=bucket, Key=key, Body=json.dumps(report, indent=2), ContentType="application/json")
    transition(a.scan_id, "RUNNING", "COMPLETE", ", severityCounts = :c, s3ReportKey = :k",
               {":c": counts, ":k": key}, remove_active=True)


if __name__ == "__main__":
    main()
