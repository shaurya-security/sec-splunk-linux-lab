#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/linux-endpoint-bootstrap.log | logger -t linux-endpoint-bootstrap -s 2>/dev/console) 2>&1
trap 'echo "[BOOTSTRAP ERROR] Linux endpoint bootstrap failed at line $LINENO"' ERR

S3_BUCKET="${s3_bucket}"
SPLUNK_PRIVATE_IP="${splunk_private_ip}"
UF_S3_URI="s3://${s3_bucket}/${uf_s3_prefix}/${uf_package_key}"
UF_PACKAGE_KEY="${uf_package_key}"

hostnamectl set-hostname "${hostname}"

if ! command -v aws >/dev/null 2>&1; then
  dnf install -y awscli2 || dnf install -y aws-cli
fi

TOKEN="$(curl -fsS -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 300' \
  http://169.254.169.254/latest/api/token)"
REGION="$(curl -fsS -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/region)"
export SPLUNK_PRIVATE_IP UF_S3_URI UF_PACKAGE_KEY REGION

s3_download() {
  local key="$1"
  local destination="$2"
  local attempt
  for attempt in {1..5}; do
    if aws s3 cp "s3://$S3_BUCKET/$key" "$destination" --region "$REGION"; then
      return 0
    fi
    echo "S3 download failed for $key; retrying ($attempt/5)."
    sleep 5
  done
  echo "[BOOTSTRAP ERROR] Failed to download $key."
  return 1
}

s3_download "linux-setup.sh" "/tmp/linux-setup.sh"
chmod 700 /tmp/linux-setup.sh
/tmp/linux-setup.sh

s3_download "linux-endpoint.sh" "/tmp/linux-endpoint.sh"
chmod 700 /tmp/linux-endpoint.sh
/tmp/linux-endpoint.sh

s3_download "userdata-logs.sh" "/home/ssm-user/userdata-logs.sh"
chmod 700 /home/ssm-user/userdata-logs.sh
chown ssm-user:ssm-user /home/ssm-user/userdata-logs.sh

rm -f /tmp/linux-setup.sh /tmp/linux-endpoint.sh
echo "===== Linux endpoint bootstrap complete ($(hostname)) ====="
