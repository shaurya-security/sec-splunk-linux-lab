#!/bin/bash
# Script Hash: ${script_hash}
# Common Hash: ${common_hash}
set -euxo pipefail
exec > >(tee /var/log/splunk_bootstrap.log | logger -t splunk_bootstrap -s 2>/dev/console) 2>&1

BUCKET="${s3_bucket}"

# --------------------------------------------------
# Config consumed by splunk-install.sh (and linux-setup.sh)
# No secrets here: the admin password is read from SSM by splunk-install.sh.
# --------------------------------------------------
export BUCKET
export TIMEZONE="${timezone}"
export SPLUNK_PASSWORD_PARAM="${password_param}"
export BOOTSTRAP_DIR="/tmp/bootstrap"

# --------------------------------------------------
# Helper: download a file from S3 with retries
# --------------------------------------------------
s3_download() {
    local key="$1"
    local dest="$2"
    for i in {1..5}; do
        aws s3 cp "s3://$BUCKET/$key" "$dest" && return 0
        echo "S3 copy failed for $key, retrying in 5 seconds... ($i/5)"
        sleep 5
    done
    echo "❌ Failed to download $key after 5 attempts."
    return 1
}


# --------------------------------------------------
# Helper: fetch a helper script into ssm-user's home dir
# --------------------------------------------------
install_ssm_user_script() {
    local key="$1"
    local dest="/home/ssm-user/$key"
    s3_download "$key" "$dest"
    if [ -f "$dest" ]; then
        chmod 700 "$dest"
        chown "ssm-user:ssm-user" "$dest"
        echo "✅ Script saved to $dest"
    else
        echo "❌ Failed to save $key."
    fi
}

# --------------------------------------------------
# Step 1: Ensure AWS CLI Installation
# --------------------------------------------------
if ! command -v aws &> /dev/null; then
    echo "📦 Installing AWS CLI..."
    dnf install -y awscli2 || dnf install -y aws-cli
fi

# --------------------------------------------------
# Step 2: Download and run linux-setup.sh from S3
# --------------------------------------------------
echo "📦 Running common bootstrap..."
s3_download "linux-setup.sh" "/tmp/linux-setup.sh"
chmod +x /tmp/linux-setup.sh
/tmp/linux-setup.sh

# --------------------------------------------------
# Step 3: Install ssm-user helper scripts
# --------------------------------------------------

echo "📦 Setting Up Userdata Error Finder..."
install_ssm_user_script "userdata-logs.sh"

# --------------------------------------------------
# Step 4: Download optional Splunk apps, then run splunk-install.sh from S3
# --------------------------------------------------

echo "📦 Downloading Splunk RPM from S3..."

s3_download \
    "splunk/10.4.3/splunk-10.4.3-4174a2deda5d.x86_64.rpm" \
    "/tmp/splunk.rpm"

export SPLUNK_RPM_PATH="/tmp/splunk.rpm"

# Apps (e.g. Splunk Add-on for Microsoft Windows) live under apps/ in the bucket.
# An empty prefix is fine.
mkdir -p "$BOOTSTRAP_DIR/apps"
aws s3 sync "s3://$BUCKET/apps/" "$BOOTSTRAP_DIR/apps/" || echo "No optional apps to sync."

echo "🔐 Running Splunk installation..."
s3_download "splunk-install.sh" "/tmp/splunk-install.sh"
chmod +x /tmp/splunk-install.sh
/tmp/splunk-install.sh

# --------------------------------------------------
# Step 5: Cleanup
# --------------------------------------------------
rm -f /tmp/linux-setup.sh /tmp/splunk-install.sh /tmp/splunk.rpm
rm -rf "$BOOTSTRAP_DIR"

echo "===== Bootstrap Complete ====="
date
