#!/usr/bin/env bash
# Report per-stage progress for the Linux user-data workflows.
set -uo pipefail

readonly ERROR_MARKER='[BOOTSTRAP ERROR]'
readonly LEGACY_ERROR_MARKER='🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴'
readonly PROGRESS_MARKER='[BOOTSTRAP_PROGRESS]'
readonly COMPLETE_MARKER='[BOOTSTRAP_COMPLETE]'
readonly CONTEXT_LINES=10
readonly LOG_DIR='/var/log'

get_error_lines() {
  local log_file="$1"
  grep -n -F -e "$ERROR_MARKER" -e "$LEGACY_ERROR_MARKER" "$log_file" 2>/dev/null \
    | grep -v -E 'trap.*(BOOTSTRAP ERROR|🔴🔴)|^[0-9]+:[+]+ echo .*BOOTSTRAP ERROR' \
    | cut -d: -f1 || true
}

select_role() {
  local requested_role="$1"
  local short_hostname

  case "$requested_role" in
    splunk|linux-endpoint)
      printf '%s\n' "$requested_role"
      return 0
      ;;
    auto)
      ;;
    *)
      printf 'Usage: %s [auto|splunk|linux-endpoint]\n' "$0" >&2
      return 2
      ;;
  esac

  short_hostname="$(hostname -s 2>/dev/null || hostname)"
  case "$short_hostname" in
    splunk-server)
      printf 'splunk\n'
      ;;
    linux-endpoint-01)
      printf 'linux-endpoint\n'
      ;;
    *)
      if [[ -f "$LOG_DIR/linux-endpoint-bootstrap.log" || -f "$LOG_DIR/linux-endpoint-forwarder.log" ]]; then
        printf 'linux-endpoint\n'
      elif [[ -f "$LOG_DIR/splunk_bootstrap.log" || -f "$LOG_DIR/splunk-install.log" ]]; then
        printf 'splunk\n'
      else
        printf 'Unable to identify this host or find known bootstrap logs (hostname: %s).\n' \
          "$short_hostname" >&2
        printf 'Pass an explicit role: %s splunk|linux-endpoint\n' "$0" >&2
        return 2
      fi
      ;;
  esac
}

scan_log() {
  local log_name="$1"
  local log_file="$LOG_DIR/$log_name"
  local error_lines error_count progress_line complete_line age_seconds

  printf '\n--- %s ---\n' "$log_file"
  if [[ ! -e "$log_file" ]]; then
    if [[ "$USERDATA_ACTIVE" == true ]]; then
      printf 'Status: NOT STARTED YET (cloud-final is still running; log has not been created)\n'
    elif [[ "$BOOT_FINISHED" == true ]]; then
      printf 'Status: MISSING after cloud-init finished\n'
      PROBLEMS=$((PROBLEMS + 1))
    else
      printf 'Status: NO LOG / USER-DATA STATE UNKNOWN\n'
      PROBLEMS=$((PROBLEMS + 1))
    fi
    return
  fi
  if [[ ! -r "$log_file" ]]; then
    printf 'Status: UNREADABLE by user %s\n' "$(id -un)"
    PROBLEMS=$((PROBLEMS + 1))
    return
  fi

  SCANNED=$((SCANNED + 1))
  age_seconds=$(( $(date +%s) - $(stat -c %Y "$log_file") ))
  progress_line="$(grep -F "$PROGRESS_MARKER" "$log_file" 2>/dev/null | tail -n 1 || true)"
  complete_line="$(grep -F "$COMPLETE_MARKER" "$log_file" 2>/dev/null | tail -n 1 || true)"
  error_lines="$(get_error_lines "$log_file")"

  if [[ -n "$error_lines" ]]; then
    error_count="$(printf '%s\n' "$error_lines" | wc -l)"
    printf 'Status: FAILED (%s error marker(s))\n' "$error_count"
    PROBLEMS=$((PROBLEMS + error_count))
    while IFS= read -r line_num; do
      local start_line=$((line_num - CONTEXT_LINES / 2))
      ((start_line < 1)) && start_line=1
      local end_line=$((line_num + CONTEXT_LINES / 2))
      sed -n "${start_line},${end_line}p" "$log_file"
      printf '\n'
    done <<< "$error_lines"
  elif [[ -n "$complete_line" ]]; then
    printf 'Status: COMPLETED\n'
  elif [[ "$USERDATA_ACTIVE" == true ]]; then
    printf 'Status: IN_PROGRESS (cloud-final is active; last log write %s seconds ago)\n' "$age_seconds"
  elif [[ "$BOOT_FINISHED" == true ]]; then
    printf 'Status: INCOMPLETE / STOPPED (no completion marker; last log write %s seconds ago)\n' "$age_seconds"
    PROBLEMS=$((PROBLEMS + 1))
  else
    printf 'Status: NOT COMPLETE; cloud-init state is unknown (last log write %s seconds ago)\n' "$age_seconds"
  fi

  if [[ -n "$complete_line" ]]; then
    printf 'Progress: %s\n' "${complete_line#*] }"
  elif [[ -n "$progress_line" ]]; then
    printf 'Progress: %s\n' "${progress_line#*] }"
  else
    printf 'Progress: not reported by this log version\n'
  fi
}

main() {
  local role cloud_final_state log_name
  local -a log_names
  local problems=0 scanned=0

  role="$(select_role "${1:-auto}")" || return $?
  cloud_final_state="$(systemctl is-active cloud-final.service 2>/dev/null || true)"
  USERDATA_ACTIVE=false
  BOOT_FINISHED=false
  PROBLEMS=0
  SCANNED=0
  case "$cloud_final_state" in
    active|activating) USERDATA_ACTIVE=true ;;
  esac
  [[ -e /var/lib/cloud/instance/boot-finished ]] && BOOT_FINISHED=true

  printf 'User-data log scan started: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
  printf 'Detected role: %s\n' "$role"
  printf 'cloud-final state: %s\n' "${cloud_final_state:-unknown}"

  case "$role" in
    splunk) log_names=(splunk_bootstrap.log splunk-install.log) ;;
    linux-endpoint) log_names=(linux-endpoint-bootstrap.log linux-endpoint-forwarder.log) ;;
  esac

  for log_name in "${log_names[@]}"; do
    scan_log "$log_name"
  done

  problems="$PROBLEMS"
  scanned="$SCANNED"
  if ((problems > 0)); then
    printf '\nOverall status: FAILED / INCOMPLETE (%s problem(s), %s log(s) scanned)\n' "$problems" "$scanned"
    return 1
  elif [[ "$USERDATA_ACTIVE" == true ]]; then
    printf '\nOverall status: IN_PROGRESS (%s log(s) scanned; cloud-final is active)\n' "$scanned"
  elif [[ "$BOOT_FINISHED" == true ]]; then
    printf '\nOverall status: COMPLETED (%s log(s) scanned)\n' "$scanned"
  else
    printf '\nOverall status: UNKNOWN (%s log(s) scanned)\n' "$scanned"
  fi
  printf 'Scan finished: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
}

main "${1:-auto}"
