#!/bin/zsh
# CommitGuard for macOS - memory-pressure watchdog.
# macOS has no Windows-style commit limit. This watches the OS-reported free
# memory percentage and RSS of individual processes instead.

set -u

INTERVAL_SEC=30
FREE_PCT_WARN=20
FREE_PCT_CRITICAL=10
PROC_RSS_GB=8
COOLDOWN_MIN=15
TEST_NOTIFICATION=false
ONCE=false

usage() {
  print "Usage: $0 [--interval seconds] [--free-pct-warn percent] [--free-pct-critical percent] [--proc-rss-gb gigabytes] [--cooldown-min minutes] [--test-notification] [--once]"
}

while (( $# )); do
  case "$1" in
    --interval) INTERVAL_SEC="$2"; shift 2 ;;
    --free-pct-warn) FREE_PCT_WARN="$2"; shift 2 ;;
    --free-pct-critical) FREE_PCT_CRITICAL="$2"; shift 2 ;;
    --proc-rss-gb) PROC_RSS_GB="$2"; shift 2 ;;
    --cooldown-min) COOLDOWN_MIN="$2"; shift 2 ;;
    --test-notification) TEST_NOTIFICATION=true; shift ;;
    --once) ONCE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) print -u2 "Unknown option: $1"; usage; exit 2 ;;
  esac
done

for value in "$INTERVAL_SEC" "$FREE_PCT_WARN" "$FREE_PCT_CRITICAL" "$PROC_RSS_GB" "$COOLDOWN_MIN"; do
  [[ "$value" =~ ^[0-9]+$ ]] || { print -u2 "All numeric options must be non-negative integers."; exit 2; }
done
(( FREE_PCT_CRITICAL < FREE_PCT_WARN && FREE_PCT_WARN <= 100 )) || { print -u2 "Critical free-memory threshold must be lower than warning threshold (0-100)."; exit 2; }

SCRIPT_DIR="${0:A:h}"
LOG_PATH="${COMMIT_GUARD_LOG_PATH:-$SCRIPT_DIR/commit-guard-macos.log}"
LOCK_DIR="${TMPDIR:-/tmp}/commitguard-macos.lock"
typeset -A LAST_ALERT

write_log() {
  print "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_PATH"
  if [[ -f "$LOG_PATH" ]] && (( $(stat -f %z "$LOG_PATH") > 1048576 )); then
    tail -n 200 "$LOG_PATH" > "${LOG_PATH}.tmp" && mv "${LOG_PATH}.tmp" "$LOG_PATH"
  fi
}

notify() {
  local title="$1" body="$2"
  /usr/bin/osascript -e "display notification \"${body//\"/\\\"}\" with title \"${title//\"/\\\"}\"" >/dev/null 2>&1 || write_log "notification failed: $title"
}

if $TEST_NOTIFICATION; then
  notify "CommitGuard test" "Notifications are working."
  write_log "test notification requested"
  exit 0
fi

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  print "CommitGuard is already running."
  exit 0
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT INT TERM

should_alert() {
  local key="$1"
  local now last
  now=$(/bin/date +%s)
  last=${LAST_ALERT[$key]:-0}
  if (( now - last < COOLDOWN_MIN * 60 )); then return 1; fi
  LAST_ALERT[$key]=$now
  return 0
}

free_memory_pct() {
  /usr/bin/memory_pressure -Q 2>/dev/null | /usr/bin/awk '/System-wide memory free percentage/ { gsub(/%/, "", $NF); print $NF; exit }'
}

top_processes() {
  /bin/ps -axo pid=,rss=,comm= | /usr/bin/sort -nrk2 | /usr/bin/head -3 | /usr/bin/awk '{ printf "%s(PID %s) %.1fGB%s", $3, $1, $2 / 1048576, (NR == 3 ? "" : ", ") }'
}

find_large_process() {
  local threshold_kb=$(( PROC_RSS_GB * 1048576 ))
  /bin/ps -axo pid=,rss=,comm= | /usr/bin/awk -v threshold="$threshold_kb" '$2 >= threshold { print $1 "\t" $2 "\t" $3; exit }'
}

write_log "CommitGuard macOS started (interval=${INTERVAL_SEC}s warn-free=${FREE_PCT_WARN}% critical-free=${FREE_PCT_CRITICAL}% proc-rss=${PROC_RSS_GB}GB)"
last_heartbeat=$(/bin/date +%s)

while true; do
  free_pct="$(free_memory_pct)"
  if [[ "$free_pct" =~ ^[0-9]+$ ]]; then
    used_pct=$(( 100 - free_pct ))
    top="$(top_processes)"
    if (( free_pct <= FREE_PCT_CRITICAL )) && should_alert critical; then
      notify "Memory pressure CRITICAL: ${used_pct}% used" "Only ${free_pct}% memory free. Top: ${top}"
      write_log "CRITICAL free=${free_pct}% top: $top"
    elif (( free_pct <= FREE_PCT_WARN )) && should_alert warn; then
      notify "Memory pressure warning: ${used_pct}% used" "Only ${free_pct}% memory free. Top: ${top}"
      write_log "WARN free=${free_pct}% top: $top"
    fi

    large="$(find_large_process)"
    if [[ -n "$large" ]]; then
      pid="${large%%$'\t'*}"; rest="${large#*$'\t'}"; rss="${rest%%$'\t'*}"; name="${rest#*$'\t'}"
      if should_alert "proc-$pid"; then
        gb=$(( rss / 1048576 ))
        notify "Possible memory leak: $name" "PID ${pid} is using ${gb}GB RSS (threshold ${PROC_RSS_GB}GB)."
        write_log "LEAK-SUSPECT ${name} PID=${pid} rss=${gb}GB free=${free_pct}%"
      fi
    fi

    if (( $(/bin/date +%s) - last_heartbeat >= 3600 )); then
      write_log "heartbeat free=${free_pct}% top: $top"
      last_heartbeat=$(/bin/date +%s)
    fi
  else
    write_log "memory_pressure did not return a free-memory percentage"
  fi
  $ONCE && exit 0
  sleep "$INTERVAL_SEC"
done
