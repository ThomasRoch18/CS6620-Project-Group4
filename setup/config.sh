# Shared settings for all setup scripts. Edit ALERT_EMAIL before running.
export AWS_REGION="${AWS_REGION:-us-east-1}"
export ENV_NAME="${ENV_NAME:-dev}"
export ALERT_EMAIL="${ALERT_EMAIL:-you@northeastern.edu}"
export ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export P="ush-${ENV_NAME}"
export TABLE_NAME="${P}-scans"
export REPORTS_BUCKET="${P}-reports-${ACCOUNT_ID}"
export LAB_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/LabRole"
export TAGS_CLI="Key=Project,Value=unified-security-hub Key=Environment,Value=${ENV_NAME} Key=ManagedBy,Value=manual"
STATE_FILE="$(dirname "${BASH_SOURCE[0]}")/.state"
save() { grep -v "^export $1=" "$STATE_FILE" 2>/dev/null > "$STATE_FILE.tmp" || true; echo "export $1=\"$2\"" >> "$STATE_FILE.tmp"; mv "$STATE_FILE.tmp" "$STATE_FILE"; export "$1=$2"; }
if [ -f "$STATE_FILE" ]; then source "$STATE_FILE"; fi
