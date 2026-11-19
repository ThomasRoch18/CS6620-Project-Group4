#!/usr/bin/env bash
# CloudWatch alarms that publish to the ops SNS topic.
set -euo pipefail
source "$(dirname "$0")/config.sh"
for dlq in "$SAST_DLQ_NAME" "$PENTEST_DLQ_NAME"; do
  aws cloudwatch put-metric-alarm --alarm-name "${dlq}-not-empty" \
    --alarm-description "Scans are landing in the DLQ: workers are failing repeatedly" \
    --namespace AWS/SQS --metric-name ApproximateNumberOfMessagesVisible --dimensions Name=QueueName,Value="$dlq" \
    --statistic Maximum --period 60 --evaluation-periods 1 --threshold 0 --comparison-operator GreaterThanThreshold \
    --treat-missing-data notBreaching --alarm-actions "$OPS_TOPIC_ARN" --ok-actions "$OPS_TOPIC_ARN"
done
aws cloudwatch put-metric-alarm --alarm-name "${NOTIFIER_NAME}-errors" \
  --alarm-description "Notifier Lambda is throwing errors, so alerts may be missed" \
  --namespace AWS/Lambda --metric-name Errors --dimensions Name=FunctionName,Value="$NOTIFIER_NAME" \
  --statistic Sum --period 60 --evaluation-periods 1 --threshold 0 --comparison-operator GreaterThanThreshold \
  --treat-missing-data notBreaching --alarm-actions "$OPS_TOPIC_ARN"
echo "Alarms created:"; aws cloudwatch describe-alarms --alarm-name-prefix "$P" --query 'MetricAlarms[].[AlarmName,StateValue]' --output table
