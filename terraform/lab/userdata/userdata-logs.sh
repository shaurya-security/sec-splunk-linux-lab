#!/usr/bin/env bash
# Report per-stage progress for the Linux user-data workflows.
set -uo pipefail

readonly ERROR_MARKER='[BOOTSTRAP ERROR]'
readonly LEGACY_ERROR_MARKER='🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴'
readonly PROGRESS_MARKER='[BOOTSTRAP_PROGRESS]'
readonly COMPLETE_MARKER='[BOOTSTRAP_COMPLETE]'
readonly CONTEXT_LINES=10
readonly LOG_DIR='/var/log'

C_RESET=''
C_BOLD=''
C_DIM=''
C_CYAN=''
C_BLUE=''
C_GREEN=''
C_YELLOW=''
C_RED=''
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_CYAN=$'\033[36m'
  C_BLUE=$'\033[34m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
fi

print_rule() {
  local char="${1:-─}"
  local index
  printf '%s' "$C_DIM"
  for ((index = 0; index < 68; index++)); do printf '%s' "$char"; done
  printf '%s\n' "$C_RESET"
}

print_banner() {
  print_rule '═'
  printf '%s%s  %s%s\n' "$C_BOLD" "$C_CYAN" "$1" "$C_RESET"
  print_rule '═'
}

print_status() {
  local status="$1"
  local message="$2"
  local color="$C_BLUE"
  case "$status" in
    COMPLETED) color="$C_GREEN" ;;
    IN_PROGRESS|NOT_STARTED|UNKNOWN) color="$C_YELLOW" ;;
    FAILED|INCOMPLETE|UNREADABLE) color="$C_RED" ;;
  esac
  printf '  %s%-14s%s %s\n' "$color" "$status" "$C_RESET" "$message"
}

print_progress() {
  local progress_text="$1"
  local percent stage filled index

  if [[ "$progress_text" =~ ^([0-9]{1,3})%[[:space:]]*-[[:space:]]*(.*)$ ]]; then
    percent="${BASH_REMATCH[1]}"
    stage="${BASH_REMATCH[2]}"
    ((percent > 100)) && percent=100
    filled=$((percent * 20 / 100))
    printf '  Progress        ['
    for ((index = 0; index < 20; index++)); do
      if ((index < filled)); then
        printf '%s█%s' "$C_GREEN" "$C_RESET"
      else
        printf '%s░%s' "$C_DIM" "$C_RESET"
      fi
    done
    printf '] %3s%%  %s\n' "$percent" "$stage"
  elif [[ -n "$progress_text" ]]; then
    printf '  Progress        %s\n' "$progress_text"
  else
    printf '  Progress        %s\n' 'not reported by this log version'
  fi
}

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
    splunk-server) printf 'splunk\n' ;;
    linux-endpoint-01) printf 'linux-endpoint\n' ;;
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
  local error_lines error_count progress_line complete_line progress_text age_seconds

  printf '\n%s--- %s%s\n' "$C_CYAN" "$log_file" "$C_RESET"
  if [[ ! -e "$log_file" ]]; then
    if [[ "$USERDATA_ACTIVE" == true ]]; then
      print_status NOT_STARTED 'cloud-final is active; log has not been created yet'
      PENDING=$((PENDING + 1))
    elif [[ "$BOOT_FINISHED" == true ]]; then
      print_status FAILED 'expected log is missing after cloud-init finished'
      PROBLEMS=$((PROBLEMS + 1))
    else
      print_status UNKNOWN 'log is missing and user-data state is unknown'
      PROBLEMS=$((PROBLEMS + 1))
    fi
    return
  fi
  if [[ ! -r "$log_file" ]]; then
    print_status UNREADABLE "not readable by user $(id -un)"
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
    print_status FAILED "$error_count error marker(s) found"
    PROBLEMS=$((PROBLEMS + error_count))
    while IFS= read -r line_num; do
      local start_line=$((line_num - CONTEXT_LINES / 2))
      ((start_line < 1)) && start_line=1
      local end_line=$((line_num + CONTEXT_LINES / 2))
      printf '%s' "$C_RED"
      sed -n "${start_line},${end_line}p" "$log_file"
      printf '%s\n' "$C_RESET"
    done <<< "$error_lines"
  elif [[ -n "$complete_line" ]]; then
    print_status COMPLETED 'completion marker found'
    COMPLETED=$((COMPLETED + 1))
  elif [[ "$USERDATA_ACTIVE" == true ]]; then
    print_status IN_PROGRESS "cloud-final active; last log write ${age_seconds}s ago"
    PENDING=$((PENDING + 1))
  elif [[ "$BOOT_FINISHED" == true ]]; then
    print_status INCOMPLETE "no completion marker; last log write ${age_seconds}s ago"
    PROBLEMS=$((PROBLEMS + 1))
  else
    print_status UNKNOWN "no terminal marker; cloud-init state unknown; last log write ${age_seconds}s ago"
    PENDING=$((PENDING + 1))
  fi

  if [[ -n "$complete_line" ]]; then
    progress_text="${complete_line#*] }"
  elif [[ -n "$progress_line" ]]; then
    progress_text="${progress_line#*] }"
  else
    progress_text=''
  fi
  print_progress "$progress_text"
}

main() {
  local role cloud_final_state log_name
  local -a log_names
  local problems=0 scanned=0 completed=0 pending=0 expected=0

  role="$(select_role "${1:-auto}")" || return $?
  cloud_final_state="$(systemctl is-active cloud-final.service 2>/dev/null || true)"
  USERDATA_ACTIVE=false
  BOOT_FINISHED=false
  PROBLEMS=0
  COMPLETED=0
  PENDING=0
  SCANNED=0
  case "$cloud_final_state" in
    active|activating) USERDATA_ACTIVE=true ;;
  esac
  [[ -e /var/lib/cloud/instance/boot-finished ]] && BOOT_FINISHED=true

  print_banner 'USER-DATA BOOTSTRAP STATUS'
  printf '%sHost:%s %s   %sRole:%s %s   %scloud-final:%s %s\n' \
    "$C_BOLD" "$C_RESET" "$(hostname -s 2>/dev/null || hostname)" \
    "$C_BOLD" "$C_RESET" "$role" "$C_BOLD" "$C_RESET" "${cloud_final_state:-unknown}"
  printf 'Started: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"

  case "$role" in
    splunk) log_names=(splunk_bootstrap.log splunk-install.log) ;;
    linux-endpoint) log_names=(linux-endpoint-bootstrap.log linux-endpoint-forwarder.log) ;;
  esac

  expected="${#log_names[@]}"
  for log_name in "${log_names[@]}"; do scan_log "$log_name"; done

  problems="$PROBLEMS"
  completed="$COMPLETED"
  pending="$PENDING"
  scanned="$SCANNED"
  print_rule '─'
  if ((problems > 0)); then
    print_status FAILED "$problems problem(s); $scanned log(s) scanned"
    printf '\n'
    return 1
  elif ((completed == expected)); then
    print_status COMPLETED "$completed/$expected logs have completion markers"
    if [[ "$USERDATA_ACTIVE" == true ]]; then
      printf '%sNote:%s cloud-final reports active, but every expected log is complete.\n' "$C_DIM" "$C_RESET"
    fi
  elif [[ "$USERDATA_ACTIVE" == true ]]; then
    print_status IN_PROGRESS "$completed/$expected logs complete; $pending pending"
  elif [[ "$BOOT_FINISHED" == true ]]; then
    print_status INCOMPLETE "$completed/$expected logs have completion markers; cloud-init has finished"
    printf '\n'
    return 1
  else
    print_status UNKNOWN "$completed/$expected logs complete; $pending pending"
  fi
  printf 'Finished: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
  printf '\n'
}

main "${1:-auto}"
