#!/bin/bash
#
# Splunk Enterprise installation (single instance, Amazon Linux 2023).
#
# Plain S3 payload - NO Terraform interpolation. All configuration arrives via
# environment variables exported by bootstrap.sh.tpl:
#   BOOTSTRAP_DIR          (required) local dir where the S3 bootstrap files were synced
#   SPLUNK_PASSWORD_PARAM  (required) SSM Parameter Store name holding the admin password
#   SPLUNK_RPM_PATH        (required) local path of the Splunk Enterprise x86_64 RPM
#   TIMEZONE               (optional) default Asia/Kolkata
#   BUCKET                 (optional) unused here, kept for bootstrap compatibility
#
# NOTE: deliberately no `set -x`, so the admin password never lands in the log.

set -euo pipefail

exec > >(tee /var/log/splunk-install.log | logger -t splunk-userdata -s 2>/dev/console) 2>&1

trap 'echo "[BOOTSTRAP ERROR] Splunk installation failed at line $LINENO 🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴"; date' ERR

echo "===== Splunk installation started ====="
echo "[BOOTSTRAP_PROGRESS] 0% - Splunk installation started"
date

# --------------------------------------------------
# Validate injected configuration
# --------------------------------------------------
: "${BOOTSTRAP_DIR:?BOOTSTRAP_DIR not set by bootstrap}"
: "${SPLUNK_PASSWORD_PARAM:?SPLUNK_PASSWORD_PARAM not set by bootstrap}"

TIMEZONE="${TIMEZONE:-Asia/Kolkata}"

SPLUNK_HOME="/opt/splunk"
WORK_USER="ssm-user"
WORK_HOME="/home/${WORK_USER}"
SPLUNK_APP="lab_ingestion"
SPLUNK_APP_HOME="${SPLUNK_HOME}/etc/apps/${SPLUNK_APP}"

if [ "$(uname -m)" != "x86_64" ]; then
    echo "[BOOTSTRAP ERROR] this script expects an x86_64 instance (got $(uname -m))."
    exit 1
fi

id "${WORK_USER}" >/dev/null 2>&1 || {
    echo "[BOOTSTRAP ERROR] ${WORK_USER} does not exist."
    exit 1
}

# --------------------------------------------------
# Instance metadata (IMDSv2)
# --------------------------------------------------
IMDS_TOKEN=$(curl -s -S -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 300" || true)

imds() {
    curl -s -S -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" \
        "http://169.254.169.254/latest/meta-data/$1" || true
}

REGION="$(imds placement/region)"

[ -n "$REGION" ] || {
    echo "[BOOTSTRAP ERROR] could not determine AWS region from IMDS."
    exit 1
}

# --------------------------------------------------
echo "[BOOTSTRAP_PROGRESS] 10% - configuration and instance metadata validated"


# System preparation
# --------------------------------------------------
dnf update -y
dnf install -y tar gzip unzip net-tools util-linux

hostnamectl set-hostname splunk-server

# Splunk health check warns when Transparent Huge Pages are enabled.
cat > /etc/systemd/system/disable-thp.service <<'EOF'
[Unit]
Description=Disable Transparent Huge Pages for Splunk
After=sysinit.target local-fs.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled; echo never > /sys/kernel/mm/transparent_hugepage/defrag'

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now disable-thp.service || \
    echo "WARNING: could not disable THP"

# --------------------------------------------------
echo "[BOOTSTRAP_PROGRESS] 20% - system preparation started"


# Admin password from SSM Parameter Store
# (retries because a fresh instance-profile can take a moment to become usable)
# --------------------------------------------------
SPLUNK_PASSWORD=""

for _ in {1..12}; do
    if SPLUNK_PASSWORD="$(aws ssm get-parameter \
            --region "${REGION}" \
            --name "${SPLUNK_PASSWORD_PARAM}" \
            --with-decryption \
            --query 'Parameter.Value' \
            --output text 2>/dev/null)"; then
        break
    fi

    SPLUNK_PASSWORD=""
    sleep 10
done

if [ "${#SPLUNK_PASSWORD}" -lt 8 ]; then
    echo "[BOOTSTRAP ERROR] could not read ${SPLUNK_PASSWORD_PARAM} from SSM, or it is shorter than 8 characters."
    echo "Check the instance role (ssm:GetParameter, plus kms:Decrypt if using a CMK)."
    exit 1
fi

# --------------------------------------------------
echo "[BOOTSTRAP_PROGRESS] 35% - SSM admin password retrieved"


# Splunk package
# --------------------------------------------------
cd /tmp

: "${SPLUNK_RPM_PATH:?SPLUNK_RPM_PATH not set by bootstrap}"

RPM_FILE="${SPLUNK_RPM_PATH}"

if [ ! -f "${RPM_FILE}" ]; then
    echo "[BOOTSTRAP ERROR] Splunk RPM not found at ${RPM_FILE}"
    exit 1
fi

echo "Using Splunk RPM: ${RPM_FILE}"
echo "[BOOTSTRAP_PROGRESS] 40% - installing Splunk package"

dnf install -y "${RPM_FILE}"
echo "[BOOTSTRAP_PROGRESS] 50% - Splunk package installed"

id splunk &>/dev/null || useradd -r -m -d "${SPLUNK_HOME}" splunk

mkdir -p \
    "${SPLUNK_HOME}/var/log/splunk" \
    "${SPLUNK_HOME}/var/log/introspection" \
    "${SPLUNK_HOME}/var/log/watchdog" \
    "${SPLUNK_HOME}/var/log/client_events" \
    "${SPLUNK_HOME}/var/run/splunk" \
    "${SPLUNK_HOME}/var/lib/splunk"

chown -R splunk:splunk "${SPLUNK_HOME}/var"

chown -R splunk:splunk "${SPLUNK_HOME}"

# --------------------------------------------------
# Audit log access for Splunk
#
# Amazon Linux 2023 protects /var/log/audit with root-only permissions and
# auditd creates a fresh root-only audit.log on every rotation. To survive
# rotation, access is granted at the source:
#   - auditd.conf log_group = splunk-audit  -> auditd itself applies the group
#     (and group-read mode) to every audit.log it creates
#   - /var/log/audit is group splunk-audit, 0750 (group traverse). This is
#     deliberately NOT an ACL: chmod on a directory recomputes the ACL mask
#     and can silently disable a named-user ACL entry.
#   - Splunkd gets the group via a systemd drop-in (added further below)
# --------------------------------------------------
AUDIT_GROUP="splunk-audit"
AUDIT_DIR="/var/log/audit"
AUDIT_LOG="${AUDIT_DIR}/audit.log"
AUDITD_CONF="/etc/audit/auditd.conf"

# True if a process running as splunk + splunk-audit (what Splunkd will have)
# can read the current audit.log.
audit_readable_by_splunk() {
    setpriv \
        --reuid="$(id -u splunk)" \
        --regid="$(id -g splunk)" \
        --groups="$(getent group "${AUDIT_GROUP}" | cut -d: -f3)" \
        test -r "${AUDIT_LOG}"
}

AUDIT_CONFIGURED=false

if [ -d "${AUDIT_DIR}" ] && [ -f "${AUDIT_LOG}" ] && [ -f "${AUDITD_CONF}" ]; then
    echo "Configuring persistent read-only audit log access for Splunk..."

    if ! getent group "${AUDIT_GROUP}" >/dev/null; then
        groupadd --system "${AUDIT_GROUP}"
    fi

    usermod -aG "${AUDIT_GROUP}" splunk

    # Make auditd apply the group itself (idempotent edit).
    if grep -Eq '^[[:space:]]*log_group[[:space:]]*=' "${AUDITD_CONF}"; then
        sed -i -E "s|^[[:space:]]*log_group[[:space:]]*=.*|log_group = ${AUDIT_GROUP}|" "${AUDITD_CONF}"
    else
        echo "log_group = ${AUDIT_GROUP}" >> "${AUDITD_CONF}"
    fi

    # `systemctl restart auditd` is refused by design; SIGHUP makes auditd
    # re-read auditd.conf.
    systemctl kill --signal=HUP auditd.service || \
        echo "WARNING: could not signal auditd to reload its config"
    sleep 2

    # Directory + existing logs, in case the reload did not re-apply them.
    chgrp "${AUDIT_GROUP}" "${AUDIT_DIR}"
    chmod 0750 "${AUDIT_DIR}"
    chgrp "${AUDIT_GROUP}" "${AUDIT_DIR}"/audit.log*
    chmod 0640 "${AUDIT_DIR}"/audit.log*

    if audit_readable_by_splunk; then
        echo "OK      : splunk (+${AUDIT_GROUP}) can read ${AUDIT_LOG}"
        AUDIT_CONFIGURED=true
    else
        echo "WARNING : splunk (+${AUDIT_GROUP}) still cannot read ${AUDIT_LOG}"
    fi

    # Prove persistence: force a rotation (SIGUSR1) and re-test the NEW file.
    # Harmless on a fresh lab box; it just creates audit.log.1.
    if [ "${AUDIT_CONFIGURED}" = true ]; then
        echo "Forcing an audit log rotation to verify access persists..."
        systemctl kill --signal=USR1 auditd.service || true
        sleep 3

        ls -l "${AUDIT_DIR}"

        if audit_readable_by_splunk; then
            echo "OK      : access to the rotated ${AUDIT_LOG} persists"
        else
            echo "WARNING : access to ${AUDIT_LOG} was LOST after rotation"
            echo "          check 'log_group' in ${AUDITD_CONF} and your auditd version"
            AUDIT_CONFIGURED=false
        fi
    fi
else
    echo "WARNING: audit log or ${AUDITD_CONF} not found; audit log access not configured."
fi

# --------------------------------------------------
# Splunk lab ingestion configuration
#
# Keep Splunk-side configuration in an app so the instance is reproducible
# from userdata/Terraform. No manual Splunk Web configuration is required
# for the indexes, local audit monitor, or Universal Forwarder receiver.
#
# Indexes:
#   linux_audit       -> audit events generated by the Splunk server itself
#   linux_endpoint    -> future Linux endpoint telemetry from Universal Forwarder
#   windows_endpoint  -> future Windows endpoint telemetry from Universal Forwarder
#
# Local source:
#   /var/log/audit/audit.log -> linux_audit / linux_audit
#
# Future endpoint flow:
#   Linux/Windows UF -> TCP/9997 -> this Splunk Enterprise instance
# --------------------------------------------------
echo "Configuring Splunk lab ingestion..."

mkdir -p "${SPLUNK_APP_HOME}/default"

cat > "${SPLUNK_APP_HOME}/default/app.conf" <<'EOF'
[install]
is_configured = 1

[ui]
is_visible = 0
label = Lab Ingestion

[launcher]
author = lab
description = Lab indexes, local audit ingestion, and Universal Forwarder receiver
version = 1.0.0
EOF

cat > "${SPLUNK_APP_HOME}/default/indexes.conf" <<'EOF'
[linux_audit]
homePath = $SPLUNK_DB/linux_audit/db
coldPath = $SPLUNK_DB/linux_audit/colddb
thawedPath = $SPLUNK_DB/linux_audit/thaweddb

[linux_endpoint]
homePath = $SPLUNK_DB/linux_endpoint/db
coldPath = $SPLUNK_DB/linux_endpoint/colddb
thawedPath = $SPLUNK_DB/linux_endpoint/thaweddb

[windows_endpoint]
homePath = $SPLUNK_DB/windows_endpoint/db
coldPath = $SPLUNK_DB/windows_endpoint/colddb
thawedPath = $SPLUNK_DB/windows_endpoint/thaweddb
EOF

cat > "${SPLUNK_APP_HOME}/default/inputs.conf" <<'EOF'
# Future Linux/Windows endpoint Universal Forwarders connect here.
[splunktcp://9997]
disabled = false

# Splunk server's own Linux audit telemetry.
[monitor:///var/log/audit/audit.log]
disabled = false
index = linux_audit
sourcetype = linux_audit
host = splunk-server
EOF

mkdir -p \
    "${SPLUNK_HOME}/var/lib/splunk/linux_audit/db" \
    "${SPLUNK_HOME}/var/lib/splunk/linux_audit/colddb" \
    "${SPLUNK_HOME}/var/lib/splunk/linux_audit/thaweddb" \
    "${SPLUNK_HOME}/var/lib/splunk/linux_endpoint/db" \
    "${SPLUNK_HOME}/var/lib/splunk/linux_endpoint/colddb" \
    "${SPLUNK_HOME}/var/lib/splunk/linux_endpoint/thaweddb" \
    "${SPLUNK_HOME}/var/lib/splunk/windows_endpoint/db" \
    "${SPLUNK_HOME}/var/lib/splunk/windows_endpoint/colddb" \
    "${SPLUNK_HOME}/var/lib/splunk/windows_endpoint/thaweddb"

chown -R splunk:splunk \
    "${SPLUNK_APP_HOME}" \
    "${SPLUNK_HOME}/var/lib/splunk/linux_audit" \
    "${SPLUNK_HOME}/var/lib/splunk/linux_endpoint" \
    "${SPLUNK_HOME}/var/lib/splunk/windows_endpoint"

# --------------------------------------------------
# Pre-start configuration
# --------------------------------------------------
mkdir -p "${SPLUNK_HOME}/etc/system/local"

# Seeds the admin account on first start; Splunk deletes this file afterwards.
umask 077

printf '[user_info]\nUSERNAME = admin\nPASSWORD = %s\n' "${SPLUNK_PASSWORD}" \
    > "${SPLUNK_HOME}/etc/system/local/user-seed.conf"

umask 022

unset SPLUNK_PASSWORD

# Splunk Web over HTTPS (self-signed cert) on 8000.
cat > "${SPLUNK_HOME}/etc/system/local/web.conf" <<'EOF'
[settings]
enableSplunkWebSSL = true
httpport = 8000
EOF

# Optional apps staged in S3 (e.g. Splunk Add-on for Microsoft Windows later).
shopt -s nullglob

for pkg in "${BOOTSTRAP_DIR}"/apps/*.tgz "${BOOTSTRAP_DIR}"/apps/*.spl; do
    echo "Installing app package: ${pkg}"
    tar -xzf "${pkg}" -C "${SPLUNK_HOME}/etc/apps"
done

shopt -u nullglob

# Dashboard timezone for the admin user.
mkdir -p "${SPLUNK_HOME}/etc/users/admin/user-prefs/local"

cat > "${SPLUNK_HOME}/etc/users/admin/user-prefs/local/user-prefs.conf" <<EOF
[general]
tz = ${TIMEZONE}
EOF

chown -R splunk:splunk "${SPLUNK_HOME}/etc"

# --------------------------------------------------
echo "[BOOTSTRAP_PROGRESS] 75% - Splunk configuration and optional apps prepared"


# First start
# Accepts license, consumes user-seed.conf, then hand over to systemd.
# --------------------------------------------------

echo "Verifying Splunk runtime permissions..."

for dir in \
    "${SPLUNK_HOME}/var/log/splunk" \
    "${SPLUNK_HOME}/var/log/introspection" \
    "${SPLUNK_HOME}/var/log/watchdog" \
    "${SPLUNK_HOME}/var/log/client_events" \
    "${SPLUNK_HOME}/var/run/splunk" \
    "${SPLUNK_HOME}/var/lib/splunk"; do

    if ! runuser -u splunk -- test -w "${dir}"; then
        echo "[BOOTSTRAP ERROR] splunk user cannot write ${dir}"
        ls -ld "${dir}"
        exit 1
    fi
done

echo "OK      : Splunk runtime directories are writable"

runuser -u splunk -- "${SPLUNK_HOME}/bin/splunk" \
    start --accept-license --answer-yes --no-prompt

runuser -u splunk -- "${SPLUNK_HOME}/bin/splunk" stop

rm -f "${SPLUNK_HOME}/etc/system/local/user-seed.conf"

"${SPLUNK_HOME}/bin/splunk" enable boot-start \
    -systemd-managed 1 \
    -user splunk \
    --accept-license \
    --answer-yes \
    --no-prompt

# Splunk's generated systemd unit explicitly sets Group=splunk
# and clears supplementary groups. Add the audit-read group back
# through a systemd drop-in rather than modifying Splunk's generated unit.
mkdir -p /etc/systemd/system/Splunkd.service.d

cat > /etc/systemd/system/Splunkd.service.d/audit-access.conf <<'EOF'
[Service]
SupplementaryGroups=splunk-audit
EOF

systemctl daemon-reload
systemctl enable Splunkd
systemctl start Splunkd
echo "[BOOTSTRAP_PROGRESS] 85% - Splunk service started"

# Verify the effective Splunk configuration from the running installation.
if runuser -u splunk -- "${SPLUNK_HOME}/bin/splunk" btool indexes list linux_audit --debug 2>/dev/null |
        grep -q "${SPLUNK_APP_HOME}/default/indexes.conf"; then
    echo "OK      : linux_audit index configuration loaded"
else
    echo "WARNING : could not verify linux_audit index configuration with btool"
fi

if runuser -u splunk -- "${SPLUNK_HOME}/bin/splunk" btool inputs list --debug 2>/dev/null |
        grep -q "${SPLUNK_APP_HOME}/default/inputs.conf"; then
    echo "OK      : lab ingestion inputs configuration loaded"
else
    echo "WARNING : could not verify inputs configuration with btool"
fi


# --------------------------------------------------
# Verify audit access from the RUNNING Splunkd process
# (a `sudo -u splunk` test would only prove /etc/group membership, not the
# groups systemd actually gave the daemon)
# --------------------------------------------------
if [ -f "${AUDIT_LOG}" ]; then
    SPLUNKD_PID="$(systemctl show Splunkd -p MainPID --value)"
    AUDIT_GID="$(getent group "${AUDIT_GROUP}" | cut -d: -f3)"

    if [ "${SPLUNKD_PID:-0}" != "0" ] && \
       grep -E '^Groups:' "/proc/${SPLUNKD_PID}/status" | tr -s ' \t' '\n' | grep -x "${AUDIT_GID}" >/dev/null; then
        echo "OK      : running Splunkd process holds group ${AUDIT_GROUP} (gid ${AUDIT_GID})"
    else
        echo "WARNING : running Splunkd process does NOT hold group ${AUDIT_GROUP}"
        AUDIT_CONFIGURED=false
    fi

    if audit_readable_by_splunk; then
        echo "OK      : Splunk can read ${AUDIT_LOG}"
    else
        echo "WARNING : Splunk cannot read ${AUDIT_LOG}"
        AUDIT_CONFIGURED=false
    fi
fi

# --------------------------------------------------
echo "[BOOTSTRAP_PROGRESS] 90% - checking Splunk configuration and audit access"


# Wait for Splunk Web
# --------------------------------------------------
CODE="000"

for _ in {1..60}; do
    CODE="$(curl -sk \
        -o /dev/null \
        -w '%{http_code}' \
        https://localhost:8000/en-US/account/login || true)"

    [ "${CODE}" = "200" ] && break

    sleep 5
done

ALL_OK=true

if systemctl is-active --quiet Splunkd; then
    echo "OK      : Splunkd"
else
    echo "FAILED  : Splunkd"
    ALL_OK=false
fi

if [ "${CODE}" != "200" ]; then
    echo "WARNING: Splunk Web did not return HTTP 200 on :8000 (got ${CODE})."
    ALL_OK=false
fi

# --------------------------------------------------
echo "[BOOTSTRAP_PROGRESS] 95% - Splunk Web health check finished"


# Summary
# --------------------------------------------------
INSTALLED_VERSION="$(
    runuser -u splunk -- "${SPLUNK_HOME}/bin/splunk" version 2>/dev/null |
        head -n 1 ||
        echo unknown
)"

PUBLIC_IP="$(imds public-ipv4)"
DASHBOARD_HOST="${PUBLIC_IP:-$(hostname)}"

# Fetch the current password from SSM specifically for the local
# convenience file. This is intentionally separate from the password
# used to seed Splunk above.
CURRENT_PASSWORD=""

if CURRENT_PASSWORD="$(aws ssm get-parameter \
        --region "${REGION}" \
        --name "${SPLUNK_PASSWORD_PARAM}" \
        --with-decryption \
        --query 'Parameter.Value' \
        --output text 2>/dev/null)"; then

    :
else
    CURRENT_PASSWORD="UNAVAILABLE"
fi

INFO_FILE="${WORK_HOME}/splunk-info.txt"

{
    echo "================================================================="
    echo "                 Splunk Installation Information"
    echo "================================================================="
    echo
    echo "Install date : $(date)"
    echo "Hostname     : $(hostname)"
    echo "Version      : ${INSTALLED_VERSION}"
    echo "Timezone     : ${TIMEZONE}"
    echo
    echo "Web UI       : https://${DASHBOARD_HOST}:8000  (self-signed cert)"
    echo "Username     : admin"
    echo "Password     : ${CURRENT_PASSWORD}"
    echo
    echo "Splunk home  : ${SPLUNK_HOME}"
    echo "Service      : systemctl status Splunkd"
    echo "Install log  : /var/log/splunk-install.log"
    echo
    echo "Audit log    : ${AUDIT_LOG}"
    echo "Audit access : ${AUDIT_GROUP} (auditd log_group, verified across rotation: ${AUDIT_CONFIGURED})"
    echo
    echo "Splunk input : TCP/9997 (Universal Forwarder receiver)"
    echo "Indexes      : linux_audit, linux_endpoint, windows_endpoint"
    echo
    if [ "$ALL_OK" = true ]; then
        echo "Services     : all running"
    else
        echo "Services     : degraded - journalctl -u Splunkd ; tail ${SPLUNK_HOME}/var/log/splunk/splunkd.log"
    fi
    echo "================================================================="
} > "$INFO_FILE"

unset CURRENT_PASSWORD

chmod 600 "$INFO_FILE"
chown "${WORK_USER}:${WORK_USER}" "$INFO_FILE"

if [ "$ALL_OK" = true ]; then
    echo "[BOOTSTRAP_COMPLETE] 100% - Splunk installation completed and services are healthy"
else
    echo "[BOOTSTRAP_COMPLETE] 100% - Splunk installation script finished with service health warnings"
fi
echo "===== Splunk installation finished ====="
