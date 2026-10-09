#!/usr/bin/env bash
# populate-inventory-tables.sh
#
# Linux replacement for the "(dba) Populate Inventory Tables" SQL Agent job.
#
# The Windows job had two CmdExec steps that had to run in order:
#   1. powershell.exe ... Wrapper-GetHostIpAddresses.ps1
#   2. sqlcmd ... EXEC dbo.usp_wrapper_populate_sma_sql_instance
#
# Neither subsystem exists on SQL Server on Linux, so both steps live here and
# are driven by sqlmonitor-populate-inventory-tables.timer. Keeping them in one
# script preserves the ordering the job guaranteed.
#
# Usage:
#   populate-inventory-tables.sh [--no-mail] [--ignore-ping-issue] [--verbose]

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/sqlmonitor.sh
. "${SCRIPT_DIR}/../lib/sqlmonitor.sh"

APP_NAME='(dba) Populate Inventory Tables'
SEND_MAIL=1
IP_ARGS=()

while [ $# -gt 0 ]; do
    case "$1" in
        --no-mail)           SEND_MAIL=0; shift ;;
        --ignore-ping-issue) IP_ARGS+=(--ignore-ping-issue); shift ;;
        --verbose)           SQLMONITOR_VERBOSE=1; IP_ARGS+=(--verbose); shift ;;
        -h|--help)           sed -n '2,17p' "$0"; exit 0 ;;
        *)                   sm_die "Unknown argument '$1'." ;;
    esac
done

sm_init

# --- Step 1: host IP addresses --------------------------------------------
sm_info "Step 1/2: get-host-ip-addresses.sh"
step1_rc=0
"${SCRIPT_DIR}/get-host-ip-addresses.sh" "${IP_ARGS[@]+"${IP_ARGS[@]}"}" || step1_rc=$?

if [ "$step1_rc" -ne 0 ]; then
    # Unresolved hosts are logged to dbo.sma_errorlog by step 1. That is not a
    # reason to skip the population itself - the Windows job behaved the same
    # way, since the ps1 step only failed hard on a connection error.
    sm_warn "get-host-ip-addresses.sh exited $step1_rc; continuing to step 2."
fi

# --- Step 2: populate dbo.sma_sql_instance ---------------------------------
sm_info "Step 2/2: dbo.usp_wrapper_populate_sma_sql_instance"
if sm_inv_exec "$APP_NAME" \
        "exec dbo.usp_wrapper_populate_sma_sql_instance @send_mail = ${SEND_MAIL}, @verbose = 0, @truncate_log_table = 1;"; then
    sm_info "Inventory tables populated."
else
    err='dbo.usp_wrapper_populate_sma_sql_instance failed.'
    sm_errorlog 'populate-inventory-tables.sh' 'usp_wrapper_populate_sma_sql_instance' \
        "$INVENTORY_SERVER" "$err" "$APP_NAME"
    sm_die "$err"
fi

exit "$step1_rc"
