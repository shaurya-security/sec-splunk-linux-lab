#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/linux-endpoint-forwarder.log | logger -t linux-endpoint-forwarder -s 2>/dev/console) 2>&1

trap 'echo "ERROR: Linux endpoint forwarder setup failed at line ${LINENO}"' ERR

: "${SPLUNK_PRIVATE_IP:?SPLUNK_PRIVATE_IP was not supplied}"
: "${UF_S3_URI:?UF_S3_URI was not supplied}"
: "${UF_PACKAGE_KEY:?UF_PACKAGE_KEY was not supplied}"

readonly SPLUNK_HOME="/opt/splunkforwarder"
readonly DOWNLOAD_PATH="/tmp/splunkforwarder.rpm"
readonly REGION="$(TOKEN=$(curl -fsS -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 300' http://169.254.169.254/latest/api/token) && curl -fsS -H "X-aws-ec2-metadata-token: ${TOKEN}" http://169.254.169.254/latest/meta-data/placement/region)"
readonly APP_DIR="${SPLUNK_HOME}/etc/apps/lab_endpoint/local"
readonly DEPLOY_SERVER="${SPLUNK_PRIVATE_IP}:9997"

# Wait for the Splunk receiver to be ready before installing/configuring UF.
for attempt in {1..60}; do
  if timeout 3 bash -c "</dev/tcp/${SPLUNK_PRIVATE_IP}/9997" 2>/dev/null; then
    break
  fi
  if [[ "${attempt}" -eq 60 ]]; then
    echo "ERROR: Splunk receiver did not become reachable."
    exit 1
  fi
  sleep 10
done

aws s3 cp "${UF_S3_URI}" "${DOWNLOAD_PATH}" --region "${REGION}"
if [[ "${UF_PACKAGE_KEY}" != *.rpm ]]; then
  echo "ERROR: linux_uf_package_key must identify an RPM package."
  exit 1
fi
dnf install -y "${DOWNLOAD_PATH}"
rm -f "${DOWNLOAD_PATH}"

mkdir -p "${APP_DIR}"
cat > "${APP_DIR}/outputs.conf" <<EOF_OUTPUTS
[tcpout]
defaultGroup = splunk_receiver

[tcpout:splunk_receiver]
server = ${DEPLOY_SERVER}
useACK = true
EOF_OUTPUTS

cat > "${APP_DIR}/inputs.conf" <<'EOF_INPUTS'
[monitor:///var/log/messages]
disabled = false
index = linux_endpoint
sourcetype = linux_messages

[monitor:///var/log/secure]
disabled = false
index = linux_endpoint
sourcetype = linux_secure
EOF_INPUTS

"${SPLUNK_HOME}/bin/splunk" start --accept-license --answer-yes --no-prompt
"${SPLUNK_HOME}/bin/splunk" enable boot-start -user root
systemctl enable SplunkForwarder
systemctl restart SplunkForwarder

echo "Linux Universal Forwarder configured for ${DEPLOY_SERVER}."
