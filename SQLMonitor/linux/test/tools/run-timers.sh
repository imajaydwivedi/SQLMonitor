#!/usr/bin/env bash
# run-timers.sh - stand-in for the systemd timers, for the container test rig.
#
# In production the six non-T-SQL inventory tasks are systemd timers
# (SQLMonitor/linux/systemd/*.timer). A container has no systemd, and cron
# cannot express a 10-second interval, so this supervisor runs one background
# loop per task on exactly the intervals the timers declare.
#
# It is a TEST HARNESS, not a scheduler to ship. It has no persistence, no
# catch-up after downtime, and no jitter - all things systemd gives you free.
#
# Usage:
#   run-timers.sh              # run every task loop in the foreground
#   run-timers.sh --once       # run each task exactly once, then exit
#   run-timers.sh --only check-instance-availability,populate-inventory-tables

set -uo pipefail

BIN_DIR="${BIN_DIR:-/opt/sqlmonitor/bin}"
LOG_DIR="${SQLMONITOR_LOG_DIR:-/var/log/sqlmonitor}"

# task<TAB>interval-seconds  -- mirrors SQLMonitor/linux/systemd/*.timer
#
#   check-instance-availability     OnUnitActiveSec=2min
#   stop-stuck-sqlmonitor-jobs      OnUnitActiveSec=1h
#   collect-all-server-alert-messages OnUnitActiveSec=10s
#   populate-inventory-tables       OnCalendar daily 09:00  -> 1h here, so a
#                                   test run actually exercises it
#   sqlserver-versions-update       OnCalendar Wed,Fri 00:00 -> 6h here
#   update-sqlmonitor-ip            opt-in; omitted (needs No-IP credentials)
TASKS=(
    "check-instance-availability|120"
    "collect-all-server-alert-messages|10"
    "stop-stuck-sqlmonitor-jobs|3600"
    "populate-inventory-tables|3600"
    "sqlserver-versions-update|21600"
)

ONCE=0
ONLY=''

while [ $# -gt 0 ]; do
    case "$1" in
        --once)    ONCE=1; shift ;;
        --only)    ONLY="$2"; shift 2 ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *)         echo "Unknown argument '$1'" >&2; exit 1 ;;
    esac
done

log() { printf '%s %-9s [timers] %s\n' "$(date +%Y%b%d_%H%M%S)" 'INFO:' "$*"; }

selected() {
    [ -z "$ONLY" ] && return 0
    [[ ",${ONLY}," == *",$1,"* ]]
}

mkdir -p "$LOG_DIR" 2>/dev/null || true

run_task() {
    local name="$1" script="${BIN_DIR}/$1.sh" rc=0
    if [ ! -x "$script" ]; then
        log "SKIP $name (no $script - run 'make install' first)"
        return 0
    fi
    log "RUN  $name"
    "$script" >>"${LOG_DIR}/${name}.log" 2>&1 || rc=$?
    if [ "$rc" -eq 0 ]; then
        log "OK   $name"
    else
        log "FAIL $name (exit $rc) - tail ${LOG_DIR}/${name}.log"
    fi
    return 0
}

if [ "$ONCE" -eq 1 ]; then
    for entry in "${TASKS[@]}"; do
        name="${entry%%|*}"
        selected "$name" && run_task "$name"
    done
    log 'single pass complete'
    exit 0
fi

pids=()
cleanup() {
    log 'stopping timer loops..'
    for p in ${pids[@]+"${pids[@]}"}; do kill "$p" 2>/dev/null || true; done
    wait 2>/dev/null || true
    exit 0
}
trap cleanup INT TERM

for entry in "${TASKS[@]}"; do
    name="${entry%%|*}"
    interval="${entry##*|}"
    selected "$name" || continue
    log "scheduling $name every ${interval}s"
    (
        while true; do
            run_task "$name"
            sleep "$interval"
        done
    ) &
    pids+=($!)
done

[ "${#pids[@]}" -gt 0 ] || { log 'nothing scheduled'; exit 1; }
log "${#pids[@]} timer loop(s) running - Ctrl-C to stop"
wait
