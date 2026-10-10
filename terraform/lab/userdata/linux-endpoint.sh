#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/linux-endpoint-forwarder.log | logger -t linux-endpoint-forwarder -s 2>/dev/console) 2>&1
trap 'echo "[BOOTSTRAP ERROR] Linux endpoint forwarder setup failed at line ${LINENO}"' ERR

echo "[BOOTSTRAP_PROGRESS] 0% - Linux forwarder setup started"
: "${SPLUNK_PRIVATE_IP:?SPLUNK_PRIVATE_IP was not supplied}"
: "${UF_S3_URI:?UF_S3_URI was not supplied}"
: "${UF_PACKAGE_KEY:?UF_PACKAGE_KEY was not supplied}"

readonly SPLUNK_HOME="/opt/splunkforwarder"
readonly DOWNLOAD_PATH="/tmp/splunkforwarder.rpm"
readonly REGION="$(TOKEN=$(curl -fsS -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 300' http://169.254.169.254/latest/api/token) && curl -fsS -H "X-aws-ec2-metadata-token: ${TOKEN}" http://169.254.169.254/latest/meta-data/placement/region)"
readonly APP_DIR="${SPLUNK_HOME}/etc/apps/lab_endpoint/local"
readonly DEPLOY_SERVER="${SPLUNK_PRIVATE_IP}:9997"
readonly AUDIT_GROUP="splunk-audit"
readonly AUDIT_DIR="/var/log/audit"
readonly AUDIT_LOG="${AUDIT_DIR}/audit.log"
readonly AUDITD_CONF="/etc/audit/auditd.conf"

# Wait for the Splunk receiver to be ready before installing/configuring UF.
echo "[BOOTSTRAP_PROGRESS] 5% - waiting for Splunk receiver"
for attempt in {1..60}; do
  if timeout 3 bash -c "</dev/tcp/${SPLUNK_PRIVATE_IP}/9997" 2>/dev/null; then
    break
  fi
  if [[ "${attempt}" -eq 60 ]]; then
    echo "[BOOTSTRAP ERROR] Splunk receiver did not become reachable."
    exit 1
  fi
  sleep 10
done
echo "[BOOTSTRAP_PROGRESS] 20% - Splunk receiver is reachable"

if [[ "${UF_PACKAGE_KEY}" != *.rpm ]]; then
  echo "[BOOTSTRAP ERROR] linux_uf_package_key must identify an RPM package."
  exit 1
fi
aws s3 cp "${UF_S3_URI}" "${DOWNLOAD_PATH}" --region "${REGION}"
echo "[BOOTSTRAP_PROGRESS] 40% - Universal Forwarder package downloaded"
dnf install -y "${DOWNLOAD_PATH}"
rm -f "${DOWNLOAD_PATH}"
echo "[BOOTSTRAP_PROGRESS] 55% - Universal Forwarder installed"

# Collect the same auditd file that the Splunk host monitors. Ensure auditd
# creates group-readable logs, including after log rotation.
dnf install -y audit
systemctl enable --now auditd
if [[ ! -f "${AUDITD_CONF}" ]]; then
  echo "[BOOTSTRAP ERROR] auditd configuration is missing at ${AUDITD_CONF}."
  exit 1
fi

for attempt in {1..10}; do
  [[ -f "${AUDIT_LOG}" ]] && break
  sleep 1
done
if [[ ! -f "${AUDIT_LOG}" ]]; then
  echo "[BOOTSTRAP ERROR] auditd did not create ${AUDIT_LOG}."
  exit 1
fi

echo "[BOOTSTRAP_PROGRESS] 65% - auditd is writing ${AUDIT_LOG}"
if ! getent group "${AUDIT_GROUP}" >/dev/null; then
  groupadd --system "${AUDIT_GROUP}"
fi
if ! id splunkfwd >/dev/null 2>&1; then
  echo "[BOOTSTRAP ERROR] Universal Forwarder account splunkfwd does not exist."
  exit 1
fi
usermod -aG "${AUDIT_GROUP}" splunkfwd

if grep -Eq '^[[:space:]]*log_group[[:space:]]*=' "${AUDITD_CONF}"; then
  sed -i -E "s|^[[:space:]]*log_group[[:space:]]*=.*|log_group = ${AUDIT_GROUP}|" "${AUDITD_CONF}"
else
  echo "log_group = ${AUDIT_GROUP}" >> "${AUDITD_CONF}"
fi
if ! systemctl kill --signal=HUP auditd.service; then
  echo "[BOOTSTRAP ERROR] Could not signal auditd to reload its configuration."
  exit 1
fi
sleep 2

chgrp "${AUDIT_GROUP}" "${AUDIT_DIR}"
chmod 0750 "${AUDIT_DIR}"
chgrp "${AUDIT_GROUP}" "${AUDIT_DIR}"/audit.log*
chmod 0640 "${AUDIT_DIR}"/audit.log*
if ! runuser -u splunkfwd -- test -r "${AUDIT_LOG}"; then
  echo "[BOOTSTRAP ERROR] splunkfwd cannot read ${AUDIT_LOG}."
  exit 1
fi
echo "[BOOTSTRAP_PROGRESS] 75% - Universal Forwarder can read auditd logs"

mkdir -p "${APP_DIR}"
cat > "${APP_DIR}/outputs.conf" <<EOF_OUTPUTS
[tcpout]
defaultGroup = splunk_receiver

[tcpout:splunk_receiver]
server = ${DEPLOY_SERVER}
useACK = true
EOF_OUTPUTS

cat > "${APP_DIR}/inputs.conf" <<'EOF_INPUTS'
[monitor:///var/log/audit/audit.log]
disabled = false
index = linux_endpoint
sourcetype = linux_audit
EOF_INPUTS
echo "[BOOTSTRAP_PROGRESS] 85% - auditd input and forwarder output configured"

"${SPLUNK_HOME}/bin/splunk" start --accept-license --answer-yes --no-prompt
"${SPLUNK_HOME}/bin/splunk" enable boot-start -user root
mkdir -p /etc/systemd/system/SplunkForwarder.service.d
cat > /etc/systemd/system/SplunkForwarder.service.d/audit-access.conf <<'EOF_AUDIT_ACCESS'
[Service]
SupplementaryGroups=splunk-audit
EOF_AUDIT_ACCESS
systemctl daemon-reload
systemctl enable SplunkForwarder
systemctl restart SplunkForwarder
echo "[BOOTSTRAP_COMPLETE] 100% - Linux auditd Universal Forwarder configured for ${DEPLOY_SERVER}"
