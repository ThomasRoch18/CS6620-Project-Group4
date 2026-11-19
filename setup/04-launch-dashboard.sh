#!/usr/bin/env bash
# Packages the dashboard to S3 and launches a t3.micro that installs and runs it on port 80.
# Uses the default VPC for now; Person 1's Terraform moves it behind the ALB in a private subnet later.
set -euo pipefail
source "$(dirname "$0")/config.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
(cd "$ROOT/dashboard" && rm -f /tmp/dashboard.zip && zip -qr /tmp/dashboard.zip . -x '.env*' '__pycache__/*')
aws s3 cp /tmp/dashboard.zip "s3://$REPORTS_BUCKET/deploy/dashboard.zip" >/dev/null

VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
SG_ID=$(aws ec2 describe-security-groups --filters Name=group-name,Values="${P}-dashboard-sg" Name=vpc-id,Values="$VPC_ID" --query 'SecurityGroups[0].GroupId' --output text)
if [ "$SG_ID" = "None" ]; then
  SG_ID=$(aws ec2 create-security-group --group-name "${P}-dashboard-sg" --description "Dashboard HTTP (temporary, until ALB)" --vpc-id "$VPC_ID" --query GroupId --output text)
  aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0 >/dev/null
fi
AMI=$(aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query 'Parameters[0].Value' --output text)

cat > /tmp/user-data.sh << UD
#!/bin/bash
set -eux
dnf install -y python3-pip unzip
mkdir -p /opt/dashboard && cd /opt/dashboard
aws s3 cp s3://$REPORTS_BUCKET/deploy/dashboard.zip . && unzip -o dashboard.zip
pip3 install -r requirements.txt
cat > /etc/ush-dashboard.env << ENV
AWS_REGION=$AWS_REGION
TABLE_NAME=$TABLE_NAME
REPORTS_BUCKET=$REPORTS_BUCKET
SAST_QUEUE_URL=$SAST_QUEUE_URL
PENTEST_QUEUE_URL=$PENTEST_QUEUE_URL
ENV
cat > /etc/systemd/system/ush-dashboard.service << SVC
[Unit]
Description=Security Hub dashboard
After=network-online.target
[Service]
WorkingDirectory=/opt/dashboard
EnvironmentFile=/etc/ush-dashboard.env
ExecStart=/usr/local/bin/gunicorn -w 2 -b 0.0.0.0:80 app:app
Restart=always
[Install]
WantedBy=multi-user.target
SVC
systemctl daemon-reload
systemctl enable --now ush-dashboard
UD

IID=$(aws ec2 run-instances --image-id "$AMI" --instance-type t3.micro \
  --iam-instance-profile Name=LabInstanceProfile --security-group-ids "$SG_ID" \
  --user-data file:///tmp/user-data.sh \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${P}-dashboard},{Key=Project,Value=unified-security-hub},{Key=Environment,Value=${ENV_NAME}}]" \
  --query 'Instances[0].InstanceId' --output text)
aws ec2 wait instance-running --instance-ids "$IID"
IP=$(aws ec2 describe-instances --instance-ids "$IID" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
save DASHBOARD_INSTANCE "$IID"
save DASHBOARD_URL "http://$IP"
echo "Launched $IID. Give it ~2 minutes, then open http://$IP"
echo "Re-run 02-deploy-notifier.sh so alert emails link to the dashboard."
