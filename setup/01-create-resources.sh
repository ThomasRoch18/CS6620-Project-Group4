#!/usr/bin/env bash
# Creates DynamoDB, SQS (+DLQs), S3 and SNS by hand for Person 3's dev account.
set -euo pipefail
source "$(dirname "$0")/config.sh"

echo "== DynamoDB table $TABLE_NAME (with GSIs and stream)"
if ! aws dynamodb describe-table --table-name "$TABLE_NAME" >/dev/null 2>&1; then
  aws dynamodb create-table --table-name "$TABLE_NAME" --billing-mode PAY_PER_REQUEST \
    --attribute-definitions AttributeName=scanId,AttributeType=S AttributeName=teamId,AttributeType=S \
      AttributeName=createdAt,AttributeType=S AttributeName=activeStatus,AttributeType=S AttributeName=updatedAt,AttributeType=S \
    --key-schema AttributeName=scanId,KeyType=HASH \
    --global-secondary-indexes '[
      {"IndexName":"GSI1","KeySchema":[{"AttributeName":"teamId","KeyType":"HASH"},{"AttributeName":"createdAt","KeyType":"RANGE"}],"Projection":{"ProjectionType":"ALL"}},
      {"IndexName":"GSI2","KeySchema":[{"AttributeName":"activeStatus","KeyType":"HASH"},{"AttributeName":"updatedAt","KeyType":"RANGE"}],"Projection":{"ProjectionType":"ALL"}}]' \
    --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES \
    --tags $TAGS_CLI >/dev/null
  aws dynamodb wait table-exists --table-name "$TABLE_NAME"
  aws dynamodb update-time-to-live --table-name "$TABLE_NAME" --time-to-live-specification Enabled=true,AttributeName=ttl >/dev/null
fi
save STREAM_ARN "$(aws dynamodb describe-table --table-name "$TABLE_NAME" --query Table.LatestStreamArn --output text)"

make_queue() {  # $1 = sast | pentest
  local dlq="${P}-$1-dlq" q="${P}-$1-queue"
  local dlq_url dlq_arn q_url
  dlq_url=$(aws sqs create-queue --queue-name "$dlq" --attributes MessageRetentionPeriod=1209600 --query QueueUrl --output text)
  dlq_arn=$(aws sqs get-queue-attributes --queue-url "$dlq_url" --attribute-names QueueArn --query Attributes.QueueArn --output text)
  local redrive="{\\\"deadLetterTargetArn\\\":\\\"$dlq_arn\\\",\\\"maxReceiveCount\\\":\\\"3\\\"}"
  echo "{\"VisibilityTimeout\":\"180\",\"RedrivePolicy\":\"$redrive\"}" > /tmp/q-attrs.json
  q_url=$(aws sqs create-queue --queue-name "$q" --attributes file:///tmp/q-attrs.json --query QueueUrl --output text)
  local upper; upper=$(echo "$1" | tr a-z A-Z)
  save "${upper}_QUEUE_URL" "$q_url"
  save "${upper}_DLQ_NAME" "$dlq"
}
echo "== SQS queues with DLQs"
make_queue sast
make_queue pentest

echo "== S3 bucket $REPORTS_BUCKET"
if ! aws s3api head-bucket --bucket "$REPORTS_BUCKET" 2>/dev/null; then
  aws s3api create-bucket --bucket "$REPORTS_BUCKET" >/dev/null
fi
aws s3api put-public-access-block --bucket "$REPORTS_BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
# CORS lets the browser PUT zips with a presigned URL. Tighten AllowedOrigins to the dashboard URL later.
aws s3api put-bucket-cors --bucket "$REPORTS_BUCKET" --cors-configuration \
  '{"CORSRules":[{"AllowedMethods":["PUT"],"AllowedOrigins":["*"],"AllowedHeaders":["*"],"MaxAgeSeconds":3000}]}'
aws s3api put-bucket-tagging --bucket "$REPORTS_BUCKET" --tagging \
  "TagSet=[{Key=Project,Value=unified-security-hub},{Key=Environment,Value=${ENV_NAME}}]"

echo "== SNS topics"
save FINDINGS_TOPIC_ARN "$(aws sns create-topic --name "${P}-findings" --query TopicArn --output text)"
save OPS_TOPIC_ARN "$(aws sns create-topic --name "${P}-ops" --query TopicArn --output text)"
for t in "$FINDINGS_TOPIC_ARN" "$OPS_TOPIC_ARN"; do
  aws sns subscribe --topic-arn "$t" --protocol email --notification-endpoint "$ALERT_EMAIL" >/dev/null
done

echo
echo "Done. Confirm the 2 subscription emails sent to $ALERT_EMAIL."
echo "Values saved to setup/.state:"; cat "$(dirname "$0")/.state"
