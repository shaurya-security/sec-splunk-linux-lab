#!/usr/bin/env bash
# Scan bootstrap and Splunk setup logs on Linux instances for standardized
# errors, with legacy Splunk trap markers accepted for existing host logs.
set -uo pipefail

readonly ERROR_MARKER='[BOOTSTRAP ERROR]'
readonly LEGACY_ERROR_MARKER='🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴'
readonly CONTEXT_LINES=10
readonly LOG_NAMES=(
  linux_bootstrap.log
  splunk_bootstrap.log
  splunk-install.log
  linux-endpoint-bootstrap.log
  linux-endpoint-forwarder.log
)
declare -A LOG_PATHS=(
  [linux_bootstrap.log]='/var/log/linux_bootstrap.log'
  [splunk_bootstrap.log]='/var/log/splunk_bootstrap.log'
  [splunk-install.log]='/var/log/splunk-install.log'
  [linux-endpoint-bootstrap.log]='/var/log/linux-endpoint-bootstrap.log'
  [linux-endpoint-forwarder.log]='/var/log/linux-endpoint-forwarder.log'
)

get_error_lines() {
  local log_file="$1"
  grep -n -F -e "$ERROR_MARKER" -e "$LEGACY_ERROR_MARKER" "$log_file" 2>/dev/null \
    | grep -v -E 'trap.*(BOOTSTRAP ERROR|🔴🔴)' \
    | cut -d: -f1 || true
}

main() {
  local failures=0 log_name log_file error_lines error_count line_num start_line end_line current_line

  printf 'Bootstrap log scan started: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
  for log_name in "${LOG_NAMES[@]}"; do
    log_file="${LOG_PATHS[$log_name]}"
    printf '\n--- %s (%s) ---\n' "$log_name" "$log_file"

    if [[ ! -f "$log_file" ]]; then
      printf 'Not present on this instance; skipping.\n'
      continue
    fi

    error_lines="$(get_error_lines "$log_file")"
    if [[ -z "$error_lines" ]]; then
      printf 'No bootstrap error markers found.\n'
      continue
    fi

    error_count="$(printf '%s\n' "$error_lines" | wc -l)"
    printf 'Found %s error marker(s).\n' "$error_count"
    failures=$((failures + error_count))

    while IFS= read -r line_num; do
      start_line=$((line_num - CONTEXT_LINES / 2))
      ((start_line < 1)) && start_line=1
      end_line=$((line_num + CONTEXT_LINES / 2))
      sed -n "${start_line},${end_line}p" "$log_file"
      printf '\n'
    done <<< "$error_lines"
  done

  printf 'Bootstrap log scan completed: %s; error markers found: %s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$failures"
  ((failures == 0))
}

main
