#!/bin/bash
# Script Hash: ${script_hash}
# Common Hash: ${common_hash}
# Diagnostic Helper Hash: ${logs_hash}
set -euxo pipefail
exec > >(tee /var/log/splunk_bootstrap.log | logger -t splunk_bootstrap -s 2>/dev/console) 2>&1
trap 'echo "[BOOTSTRAP ERROR] Splunk host bootstrap failed at line $LINENO"' ERR

echo "[BOOTSTRAP_PROGRESS] 0% - Splunk host bootstrap started"
BUCKET="${s3_bucket}"

export BUCKET
export TIMEZONE="${timezone}"
export SPLUNK_PASSWORD_PARAM="${password_param}"
export BOOTSTRAP_DIR="/tmp/bootstrap"

s3_download() {
    local key="$1"
    local dest="$2"
    for i in {1..5}; do
        aws s3 cp "s3://$BUCKET/$key" "$dest" && return 0
        echo "S3 copy failed for $key, retrying in 5 seconds... ($i/5)"
        sleep 5
    done
    echo "[BOOTSTRAP ERROR] Failed to download $key after 5 attempts."
    return 1
}

install_ssm_user_script() {
    local key="$1"
    local dest="/home/ssm-user/$key"
    s3_download "$key" "$dest"
    if [ -f "$dest" ]; then
        chmod 700 "$dest"
        chown "ssm-user:ssm-user" "$dest"
        echo "Script saved to $dest"
    else
        echo "[BOOTSTRAP ERROR] Failed to save $key."
        return 1
    fi
}

echo "[BOOTSTRAP_PROGRESS] 5% - checking AWS CLI"
if ! command -v aws &> /dev/null; then
    echo "Installing AWS CLI..."
    dnf install -y awscli2 || dnf install -y aws-cli
fi

echo "[BOOTSTRAP_PROGRESS] 10% - running shared Linux setup"
s3_download "linux-setup.sh" "/tmp/linux-setup.sh"
chmod +x /tmp/linux-setup.sh
/tmp/linux-setup.sh
echo "[BOOTSTRAP_PROGRESS] 30% - shared Linux setup finished"

echo "[BOOTSTRAP_PROGRESS] 35% - installing SSM log helper"
install_ssm_user_script "userdata-logs.sh"
echo "[BOOTSTRAP_PROGRESS] 40% - SSM log helper installed"

echo "[BOOTSTRAP_PROGRESS] 45% - downloading Splunk package"
s3_download \
    "splunk/10.4.3/splunk-10.4.3-4174a2deda5d.x86_64.rpm" \
    "/tmp/splunk.rpm"
export SPLUNK_RPM_PATH="/tmp/splunk.rpm"

mkdir -p "$BOOTSTRAP_DIR/apps"
aws s3 sync "s3://$BUCKET/apps/" "$BOOTSTRAP_DIR/apps/" || echo "No optional apps to sync."
echo "[BOOTSTRAP_PROGRESS] 60% - package and optional apps staged"

echo "[BOOTSTRAP_PROGRESS] 65% - running Splunk installation"
s3_download "splunk-install.sh" "/tmp/splunk-install.sh"
chmod +x /tmp/splunk-install.sh
/tmp/splunk-install.sh
echo "[BOOTSTRAP_PROGRESS] 95% - Splunk installation finished"

rm -f /tmp/linux-setup.sh /tmp/splunk-install.sh /tmp/splunk.rpm
rm -rf "$BOOTSTRAP_DIR"
echo "[BOOTSTRAP_COMPLETE] 100% - Splunk host bootstrap completed"
date
