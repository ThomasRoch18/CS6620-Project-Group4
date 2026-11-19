# Person 3 starter kit: dashboard + alerting

Copy these folders into the team repo (`dashboard/`, `lambdas/notifier/`, `setup/`, `scripts/`, `docs/`).

## Before you start
- Start the Learner Lab and copy credentials into `~/.aws/credentials` (AWS Details > AWS CLI),
  or run everything from the lab terminal. Credentials expire with the session.
- Edit `ALERT_EMAIL` in `setup/config.sh`.

## Steps (about 30 minutes of commands, the rest is building and demo prep)
1. `bash setup/01-create-resources.sh`
   Creates the DynamoDB table (GSIs + stream + TTL), SAST/pentest queues with DLQs, S3 bucket with CORS,
   and findings/ops SNS topics. **Confirm both subscription emails.**
2. `bash setup/02-deploy-notifier.sh`
   Deploys the notifier Lambda and attaches it to the stream (filtered to status COMPLETE).
3. `bash setup/03-alarms.sh`
   DLQ-not-empty alarms for both queues and a notifier error alarm, all to the ops topic.
4. Run the dashboard locally first:
   `cd dashboard && pip install -r requirements.txt`, set the env vars from `.env.example`
   (values are in `setup/.state`), then `python app.py`.
5. `bash setup/04-launch-dashboard.sh`
   Uploads the app to S3 and launches a t3.micro that runs it on port 80. Wait ~2 minutes.
   Then re-run step 2 so alert emails link to the dashboard.

## Demo script for the video
1. Submit a snippet in the browser. Show the item in DynamoDB (QUEUED) and the message in SQS
   (Send and receive messages > Poll).
2. `python scripts/fake_complete.py <scanId> --high 2` (stands in for Person 2's worker).
   Dashboard moves to Complete and shows the report.
3. Show the notifier's CloudWatch logs (`alert_sent`) and the email arriving.
4. `python scripts/fake_complete.py <otherScanId> --fail "Task exited with code 1"` to show a failed scan.
5. Alarm: send 1 message straight to `ush-dev-sast-dlq`, wait ~1-2 minutes, show the alarm go to ALARM
   and the ops email.

## Troubleshooting
- Dashboard not loading: on the instance, `sudo journalctl -u ush-dashboard -n 50` and
  `sudo cat /var/log/cloud-init-output.log` (connect with EC2 Instance Connect).
- No alert email: subscription not confirmed, HIGH = 0, or the item was already COMPLETE before.
- Zip upload fails in the browser: check the bucket CORS rule from step 1.
- AccessDenied: the resource is not using LabRole / LabInstanceProfile.

## Teardown (protect the budget)
Terminate the instance, then delete the queues, topics, table, Lambda and bucket when you are done for the day,
or leave only the free-tier-cheap ones (DynamoDB on-demand, SQS, SNS cost almost nothing idle).
