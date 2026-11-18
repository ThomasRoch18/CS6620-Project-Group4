# Scan workers: Milestone 1

This part has two workers:

- **SAST worker** (Lambda): scans a code snippet with the provided scanner.
- **Pentest worker** (Fargate): tests an API with the provided tester.

Both save the full report to **S3** and update the job's status in **DynamoDB**.

Zip uploads and the SSRF guard come later (see "After Milestone 1" at the end).

## How it works

```
SQS message ──> SAST Lambda ───┐
                               ├──> report in S3 + status in DynamoDB
run-task ─────> Pentest task ──┘
```

| Piece | What it does | Course topic |
|---|---|---|
| Dockerfiles | Package each worker with the provided code | T5 Containers |
| ECR | Stores the images | T5 Container registries |
| Lambda | Runs the SAST worker when a message arrives | T4 Lambda |
| SQS + DLQ | Delivers scan requests; retries 3 times, then the DLQ | Scaling guide: message queues |
| Fargate | Runs one pentest container per scan | Scaling guide, T6 Microservices |
| S3 | Stores the full reports | T7 S3 |
| DynamoDB | Stores each job's status | Scaling guide |
| LabRole | Gives the workers permissions, no access keys in code | T7 IAM roles |
| Security group | Keeps the vulnerable test target private | T8 Security groups |
| CloudWatch Logs | Shows what each worker did | T10 Observability |

## What's in the kit

```
.dockerignore              copy this to the repo root
workers/
  shared/jobs.js           status changes in DynamoDB + saving reports to S3
  sast-worker/
    index.js               the Lambda function
    scan-adapter.js        the ONLY file that calls the provided scanner.js
    try-scanner.js         test the scanner on your laptop
    Dockerfile, package.json
  pentest-worker/
    worker.js              runs one pentest, then stops
    test-adapter.js        the ONLY file that calls the provided tester.js
    try-tester.js          test the tester on your laptop
    Dockerfile, package.json
  test-target/Dockerfile   the provided vulnerable API, for the demo
  test-files/vulnerable.js one example of each of the 10 SAST vulnerability types
```

Copy `workers/` and `.dockerignore` into your repo root, next to `sast/` and `pentest/`.

## The agreed formats

**SAST message on the SQS queue:**
```json
{ "scanId": "demo-001", "code": "const password = \"admin123\";" }
```

**Pentest task:** started with the environment variables `SCAN_ID` and `TARGET_URL`.

**DynamoDB item:** the dashboard creates it with `status: "QUEUED"` **before** sending the scan. The workers then change `status`, and add `severityCounts`, `s3ReportKey`, `errorMessage` and `updatedAt`.

**S3 report:** `reports/{scanId}.json`

> The workers only update jobs that already exist. When you test, always create the DynamoDB item first, or the worker will skip the message.

---

## Step 1: Check the provided code's function names

From the repo root:

```bash
cd sast/backend && npm install && cd ../..
cd pentest/backend && npm install && cd ../..
node -e "console.log(require('./sast/backend/scanner'))"
node -e "console.log(require('./pentest/backend/tester'))"
```

This prints the functions each file provides. If the names are different from `scanCode` and `runAllTests`, fix the lines marked `TODO` in `scan-adapter.js` and `test-adapter.js`.

## Step 2: Test on laptop

**SAST:**
```bash
cd workers/sast-worker
SAST_SCANNER_PATH=../../sast/backend/scanner node try-scanner.js ../test-files/vulnerable.js
```
Check that it finds the vulnerabilities, and that **Severity counts** isn't all zeros. If it is, fix the field name marked `TODO` in `countSeverities`.

**Pentest:**
```bash
# Terminal 1
cd pentest/backend && node test-target.js

# Terminal 2
cd workers/pentest-worker
PENTEST_TESTER_PATH=../../pentest/backend/tester node try-tester.js
```
Check that some tests FAIL, and that **Counts** isn't all zeros.

## Step 3: Connect to the Learner Lab

1. Start the Learner Lab, click **AWS Details**, and copy the credentials into `~/.aws/credentials`. They expire every session, so you'll repeat this each time.
2. Set these variables. Run them again in every new terminal window:

```bash
export AWS_REGION=us-east-1
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export ROLE_ARN=arn:aws:iam::$ACCOUNT_ID:role/LabRole
export REGISTRY=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
export TABLE=ush-scans
export BUCKET=ush-reports-$ACCOUNT_ID
```

## Step 4: Create the resources

```bash
# DynamoDB table, with scanId as the key
aws dynamodb create-table --table-name $TABLE \
  --attribute-definitions AttributeName=scanId,AttributeType=S \
  --key-schema AttributeName=scanId,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

# S3 bucket for reports (names must be unique across AWS, so it includes your account ID)
aws s3 mb s3://$BUCKET

# Dead-letter queue, then the SAST queue that sends failed messages there after 3 tries
aws sqs create-queue --queue-name ush-sast-dlq
DLQ_URL=$(aws sqs get-queue-url --queue-name ush-sast-dlq --query QueueUrl --output text)
DLQ_ARN=$(aws sqs get-queue-attributes --queue-url $DLQ_URL --attribute-names QueueArn --query Attributes.QueueArn --output text)
cat > sast-queue.json <<EOF
{"VisibilityTimeout":"90","RedrivePolicy":"{\"deadLetterTargetArn\":\"$DLQ_ARN\",\"maxReceiveCount\":\"3\"}"}
EOF
aws sqs create-queue --queue-name ush-sast-queue --attributes file://sast-queue.json
export SAST_QUEUE_URL=$(aws sqs get-queue-url --queue-name ush-sast-queue --query QueueUrl --output text)
export SAST_QUEUE_ARN=$(aws sqs get-queue-attributes --queue-url $SAST_QUEUE_URL --attribute-names QueueArn --query Attributes.QueueArn --output text)

# ECR repositories for the three images
aws ecr create-repository --repository-name ush-sast-worker
aws ecr create-repository --repository-name ush-pentest-worker
aws ecr create-repository --repository-name ush-test-target
```

**What the visibility timeout means:** when Lambda takes a message, SQS hides it for 90 seconds. If Lambda finishes, the message is deleted. If it fails, the message reappears and is tried again. It has to be longer than the Lambda's 60-second time limit.

## Step 5: Build the images and push them to ECR

Install **Docker Desktop** first if you don't have it. Then, from the **repo root**:

```bash
aws ecr get-login-password | docker login --username AWS --password-stdin $REGISTRY

docker build --platform linux/amd64 --provenance=false -f workers/sast-worker/Dockerfile -t $REGISTRY/ush-sast-worker:v1 .
docker build --platform linux/amd64 -f workers/pentest-worker/Dockerfile -t $REGISTRY/ush-pentest-worker:v1 .
docker build --platform linux/amd64 -f workers/test-target/Dockerfile -t $REGISTRY/ush-test-target:v1 .

docker push $REGISTRY/ush-sast-worker:v1
docker push $REGISTRY/ush-pentest-worker:v1
docker push $REGISTRY/ush-test-target:v1
```

- `--platform linux/amd64`: your Mac has an Apple chip, but AWS runs these on Intel-style (x86) machines, so you build for that.
- `--provenance=false`: newer Docker versions add extra data to images that Lambda doesn't accept.

## Step 6: Create the SAST Lambda

```bash
aws lambda create-function --function-name ush-sast-worker \
  --package-type Image --code ImageUri=$REGISTRY/ush-sast-worker:v1 \
  --role $ROLE_ARN --timeout 60 --memory-size 1024 \
  --environment "Variables={TABLE_NAME=$TABLE,BUCKET_NAME=$BUCKET}"

aws lambda wait function-active-v2 --function-name ush-sast-worker

# Trigger the Lambda from the queue, one message at a time
aws lambda create-event-source-mapping --function-name ush-sast-worker \
  --event-source-arn $SAST_QUEUE_ARN --batch-size 1
```

To update it later, push the image with a new tag (like `v2`) and run:
```bash
aws lambda update-function-code --function-name ush-sast-worker --image-uri $REGISTRY/ush-sast-worker:v2
```

## Step 7: Test the SAST worker

```bash
# 1. Create the job, standing in for Jay's dashboard
aws dynamodb put-item --table-name $TABLE --item '{
  "scanId": {"S": "demo-001"}, "status": {"S": "QUEUED"},
  "activeStatus": {"S": "QUEUED"}, "type": {"S": "SAST"} }'

# 2. Send the scan request
aws sqs send-message --queue-url $SAST_QUEUE_URL \
  --message-body '{"scanId":"demo-001","code":"const password = \"admin123\";"}'

# 3. Watch the logs (press Ctrl+C to stop)
aws logs tail /aws/lambda/ush-sast-worker --follow

# 4. Check the report and the status
aws s3 cp s3://$BUCKET/reports/demo-001.json -
aws dynamodb get-item --table-name $TABLE --key '{"scanId":{"S":"demo-001"}}'
```

You should see `"status": "COMPLETE"` and the severity counts. You can show the same things in the AWS Console (Lambda → Monitor, S3, DynamoDB → Explore items) for your video.

**Optional: retries and the DLQ.** Send a broken message. It fails 3 times, about 90 seconds apart, then lands in the DLQ:
```bash
aws sqs send-message --queue-url $SAST_QUEUE_URL --message-body 'not json'
# About 5 minutes later:
aws sqs get-queue-attributes --queue-url $DLQ_URL --attribute-names ApproximateNumberOfMessages
```

## Step 8: Set up the pentest worker and test target on Fargate

This uses the account's **default VPC**.

```bash
# Find the default VPC, one of its subnets, and its default security group
VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
export SUBNET=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC_ID --query 'Subnets[0].SubnetId' --output text)
export SG=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values=$VPC_ID Name=group-name,Values=default --query 'SecurityGroups[0].GroupId' --output text)
NET="awsvpcConfiguration={subnets=[$SUBNET],securityGroups=[$SG],assignPublicIp=ENABLED}"

# A cluster to run tasks in, and log groups for CloudWatch
aws ecs create-cluster --cluster-name ush-cluster
aws logs create-log-group --log-group-name /ecs/ush-pentest-worker
aws logs create-log-group --log-group-name /ecs/ush-test-target
```

**Why these network settings:**
- `assignPublicIp=ENABLED`: the default VPC has no NAT Gateway, so the task needs a public IP to download its image from ECR. In Thomas's VPC, tasks run in private subnets and go through the NAT instead.
- **The default security group** only allows traffic from other resources in the same group. Nothing on the internet can reach the vulnerable test target, but the pentest worker (in the same group) can.

Now describe each container in a **task definition**: which image, how much CPU and memory, which role, and where logs go.

```bash
cat > pentest-task.json <<EOF
{
  "family": "ush-pentest-worker",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256", "memory": "512",
  "executionRoleArn": "$ROLE_ARN",
  "taskRoleArn": "$ROLE_ARN",
  "containerDefinitions": [{
    "name": "pentest-worker",
    "image": "$REGISTRY/ush-pentest-worker:v1",
    "environment": [
      {"name": "TABLE_NAME", "value": "$TABLE"},
      {"name": "BUCKET_NAME", "value": "$BUCKET"}
    ],
    "logConfiguration": {"logDriver": "awslogs", "options": {
      "awslogs-group": "/ecs/ush-pentest-worker",
      "awslogs-region": "$AWS_REGION",
      "awslogs-stream-prefix": "worker"}}
  }]
}
EOF

cat > target-task.json <<EOF
{
  "family": "ush-test-target",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256", "memory": "512",
  "executionRoleArn": "$ROLE_ARN",
  "containerDefinitions": [{
    "name": "test-target",
    "image": "$REGISTRY/ush-test-target:v1",
    "portMappings": [{"containerPort": 4000}],
    "logConfiguration": {"logDriver": "awslogs", "options": {
      "awslogs-group": "/ecs/ush-test-target",
      "awslogs-region": "$AWS_REGION",
      "awslogs-stream-prefix": "target"}}
  }]
}
EOF

aws ecs register-task-definition --cli-input-json file://pentest-task.json
aws ecs register-task-definition --cli-input-json file://target-task.json
```

- `cpu` 256 and `memory` 512 are the smallest Fargate size (a quarter of a CPU, 0.5 GB), which keeps costs low.
- `executionRoleArn` is what ECS uses to pull the image and write logs. `taskRoleArn` is what your code uses for S3 and DynamoDB. Both are LabRole, because the Learner Lab doesn't let you create roles.

Start the test target as a **service**, which keeps one copy running:

```bash
aws ecs create-service --cluster ush-cluster --service-name ush-test-target \
  --task-definition ush-test-target --desired-count 1 --launch-type FARGATE \
  --network-configuration "$NET"
```

Wait about a minute, then get its private IP address:

```bash
TASK=$(aws ecs list-tasks --cluster ush-cluster --service-name ush-test-target --query 'taskArns[0]' --output text)
export TARGET_IP=$(aws ecs describe-tasks --cluster ush-cluster --tasks $TASK \
  --query "tasks[0].attachments[0].details[?name=='privateIPv4Address'].value" --output text)
echo $TARGET_IP
```

## Step 9: Test the pentest worker

```bash
# 1. Create the job
aws dynamodb put-item --table-name $TABLE --item '{
  "scanId": {"S": "demo-002"}, "status": {"S": "QUEUED"},
  "activeStatus": {"S": "QUEUED"}, "type": {"S": "PENTEST"} }'

# 2. Start one pentest task (later, the dispatcher Lambda will do this)
aws ecs run-task --cluster ush-cluster --launch-type FARGATE \
  --task-definition ush-pentest-worker --started-by demo-002 \
  --network-configuration "$NET" \
  --overrides '{"containerOverrides":[{"name":"pentest-worker","environment":[
    {"name":"SCAN_ID","value":"demo-002"},
    {"name":"TARGET_URL","value":"http://'$TARGET_IP':4000/api/users"}]}]}'

# 3. Watch the logs (it takes 30-60 seconds to start)
aws logs tail /ecs/ush-pentest-worker --follow

# 4. Check the report and the status
aws s3 cp s3://$BUCKET/reports/demo-002.json -
aws dynamodb get-item --table-name $TABLE --key '{"scanId":{"S":"demo-002"}}'
```

The report should show some tests FAILED against the vulnerable target, and the status should be `COMPLETE`. You can also watch the task start and stop in the ECS Console.

## Step 10: Clean up

```bash
aws ecs update-service --cluster ush-cluster --service ush-test-target --desired-count 0
```

This stops the test target. The Lambda, SQS, DynamoDB and S3 cost almost nothing when nobody uses them, and pentest tasks stop by themselves.

---

## Troubleshooting

| Problem | What to do |
|---|---|
| `Cannot find module './sast/scanner'` | The provided file has a different name. Check `sast/backend/` and fix the path in the adapter. |
| Lambda: `image manifest ... not supported` | Rebuild with `--provenance=false`. |
| `exec format error` | Rebuild with `--platform linux/amd64`. |
| ECS: `CannotPullContainerError` | The task can't reach ECR. Check `assignPublicIp=ENABLED` in the default VPC. |
| `ExpiredToken` | Your Learner Lab credentials expired. Copy new ones from AWS Details. |
| `AccessDenied` mentioning LabRole | A Learner Lab limit. Note which action was denied; this makes a good "challenge" for your video. |
| Job stays QUEUED | The DynamoDB item is missing or the `scanId` doesn't match. Look for "skipped" in the logs. |
| Pentest can't reach the target | Both tasks must use the same security group, and `TARGET_IP` must be the current IP (it changes if the target restarts). |

## After Milestone 1

- **Zip uploads:** scan a whole repo uploaded to S3.
- **SSRF guard:** stop users from scanning internal addresses (Week 4).
- **Dispatcher Lambda:** starts a pentest task for each message on the pentest queue.
- **Reconciler and sweeper:** mark crashed or stuck jobs FAILED, using `markFailed()` from `shared/jobs.js`.
