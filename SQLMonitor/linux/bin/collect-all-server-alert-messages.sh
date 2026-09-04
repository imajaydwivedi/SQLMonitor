#!/usr/bin/env bash
# collect-all-server-alert-messages.sh
#
# Linux replacement for wrapper-collect_all_server_alert_messages.bat and the
# "(dba) Collect-AllServerAlertMessages" SQL Agent job.
#
# collect_all_server_alert_messages.py is already cross-platform; this wrapper
# just gives it a stable entry point with the right interpreter, working
# directory and failure reporting, the way the .bat did on Windows.
#
# Usage:
#   collect-all-server-alert-messages.sh [--python /path/to/python3] [--verbose]

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/sqlmonitor.sh
. "${SCRIPT_DIR}/../lib/sqlmonitor.sh"

APP_NAME='(dba) Collect-AllServerAlertMessages'
PYTHON_BIN="${PYTHON_BIN:-}"

while [ $# -gt 0 ]; do
    case "$1" in
        --python)  PYTHON_BIN="$2"; shift 2 ;;
        --verbose) SQLMONITOR_VERBOSE=1; shift ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *)         sm_die "Unknown argument '$1'." ;;
    esac
done

sm_init

if [ -z "$PYTHON_BIN" ]; then
    for candidate in "${SQLMONITOR_HOME}/venv/bin/python3" python3 python; do
        if command -v "$candidate" >/dev/null 2>&1; then
            PYTHON_BIN="$(command -v "$candidate")"
            break
        fi
    done
fi
[ -n "$PYTHON_BIN" ] || sm_die "No python interpreter found. Set PYTHON_BIN or pass --python."

script="${SQLMONITOR_HOME}/collect_all_server_alert_messages.py"
[ -f "$script" ] || script="${SCRIPT_DIR}/../../collect_all_server_alert_messages.py"
[ -f "$script" ] || sm_die "collect_all_server_alert_messages.py not found under '$SQLMONITOR_HOME'."

# The script defaults to --inventory_server localhost, which in a container or
# on a separate inventory host means "connect to nothing". Pass the configured
# target through. Credentials reach it via the environment (INVENTORY_LOGIN /
# INVENTORY_PASSWORD, PROBE_LOGIN / PROBE_PASSWORD).
py_args=(
    --inventory_server "$INVENTORY_SERVER"
    --inventory_database "$INVENTORY_DATABASE"
    --app_name "$APP_NAME"
    --threads "$SQLMONITOR_THREADS"
)

sm_info "Running '$script' with '$PYTHON_BIN' against [$INVENTORY_SERVER].."

if "$PYTHON_BIN" -u "$script" "${py_args[@]}"; then
    sm_info "Alert message collection completed."
else
    rc=$?
    err="collect_all_server_alert_messages.py exited with code $rc."
    sm_errorlog 'collect-all-server-alert-messages.sh' "$script" \
        "$INVENTORY_SERVER" "$err" "$APP_NAME"
    sm_die "$err"
fi
