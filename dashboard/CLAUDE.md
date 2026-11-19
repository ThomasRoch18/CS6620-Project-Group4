# CLAUDE.md: Unified Security Hub, Person 3 (dashboard + alerting)

## Project
CS6620 group project. Internal security portal: developers submit JavaScript for SAST, the security
team submits API URLs for pentests. Scans are queued on SQS and run by workers (owned by Person 2).
Results: full report in S3, status in DynamoDB. HIGH findings email the team through SNS.

## My scope
- `dashboard/`: Flask app on EC2 (submit snippet / zip / URL, scan history, scan detail).
- `lambdas/notifier/`: DynamoDB stream -> SNS email on transition into COMPLETE with HIGH > 0.
- `setup/03-alarms.sh`: CloudWatch alarms -> ops SNS topic.
Not mine: workers, dispatcher, reconciler, sweeper (Person 2); Terraform / VPC / ALB / CI (Person 1).

## Rules
- `docs/contracts.md` is the source of truth for SQS messages, DynamoDB fields, S3 paths and
  report JSON. Never change a field name or status value without the team agreeing.
- Every status change is a conditional write (see contracts.md, "Who writes which status").
- No hardcoded names, ARNs or credentials. Everything comes from environment variables.
- AWS Learner Lab: we cannot create IAM roles. Use LabRole (Lambda) and LabInstanceProfile (EC2).
- Region us-east-1. Resource names `ush-{env}-{resource}`.
- Keep the dashboard's `/health` free of AWS calls (it is the ALB health check).

## Layout
- `setup/config.sh` shared settings; `setup/.state` holds created queue URLs / ARNs (git-ignored).
- `setup/01..04-*.sh` create resources, deploy notifier, alarms, launch the dashboard EC2.
- `scripts/fake_complete.py` simulates a worker so the dashboard and alerts can be demoed.

## Run locally
    cd dashboard && pip install -r requirements.txt
    source ../setup/.state && export TABLE_NAME=ush-dev-scans REPORTS_BUCKET=...   # or copy .env.example
    python app.py   # http://localhost:5000

## Good next tasks for Claude Code
- Render SAST findings and pentest results as tables instead of raw JSON (shape comes from
  sast/backend/scanner.js and pentest/backend/tester.js output inside `results`).
- Add a team picker that sets `teamId`.
- Add basic tests for the Flask routes with moto.
