#!/usr/bin/env bash
# Deploys the notifier Lambda and connects it to the DynamoDB stream.
set -euo pipefail
source "$(dirname "$0")/config.sh"
FN="${P}-notifier"
SRC="$(cd "$(dirname "$0")/../lambdas/notifier" && pwd)"
(cd "$SRC" && rm -f /tmp/notifier.zip && zip -q /tmp/notifier.zip handler.py)

ENV_VARS="Variables={FINDINGS_TOPIC_ARN=$FINDINGS_TOPIC_ARN,DASHBOARD_URL=${DASHBOARD_URL:-}}"
if aws lambda get-function --function-name "$FN" >/dev/null 2>&1; then
  aws lambda update-function-code --function-name "$FN" --zip-file fileb:///tmp/notifier.zip >/dev/null
  aws lambda wait function-updated --function-name "$FN"
  aws lambda update-function-configuration --function-name "$FN" --environment "$ENV_VARS" >/dev/null
else
  aws lambda create-function --function-name "$FN" --runtime python3.12 --handler handler.handler \
    --role "$LAB_ROLE_ARN" --zip-file fileb:///tmp/notifier.zip --timeout 30 \
    --environment "$ENV_VARS" --tags Project=unified-security-hub,Environment="$ENV_NAME" >/dev/null
  aws lambda wait function-active --function-name "$FN"
fi

if [ -z "$(aws lambda list-event-source-mappings --function-name "$FN" --event-source-arn "$STREAM_ARN" --query 'EventSourceMappings[0].UUID' --output text | grep -v None)" ]; then
  # The filter means the Lambda is only invoked for records whose new status is COMPLETE.
  aws lambda create-event-source-mapping --function-name "$FN" --event-source-arn "$STREAM_ARN" \
    --starting-position LATEST --batch-size 10 --maximum-retry-attempts 3 \
    --filter-criteria '{"Filters":[{"Pattern":"{\"dynamodb\":{\"NewImage\":{\"status\":{\"S\":[\"COMPLETE\"]}}}}"}]}' >/dev/null
fi
save NOTIFIER_NAME "$FN"
echo "Notifier $FN deployed and attached to the stream."
