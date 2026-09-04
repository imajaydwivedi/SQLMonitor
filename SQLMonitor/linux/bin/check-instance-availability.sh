#!/usr/bin/env bash
# check-instance-availability.sh
#
# Linux replacement for check-instance-availability.ps1 and the
# "(dba) Check-InstanceAvailability" SQL Agent job.
#
# Probes every enabled instance in dbo.instance_details, then flips
# dbo.instance_details.is_available accordingly and records every failure in
# dbo.sma_errorlog. Driven by sqlmonitor-check-instance-availability.timer,
# because SQL Agent on Linux has no CmdExec/PowerShell subsystem.
#
# Usage:
#   check-instance-availability.sh [--threads N] [--skip-not-onboarded] [--verbose]

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/sqlmonitor.sh
. "${SCRIPT_DIR}/../lib/sqlmonitor.sh"

APP_NAME='check-instance-availability.sh'
JOB_NAME='(dba) Check-InstanceAvailability'

SKIP_NOT_ONBOARDED=0
PROBE_TIMEOUT_SECONDS="${PROBE_TIMEOUT_SECONDS:-1200}"

while [ $# -gt 0 ]; do
    case "$1" in
        --threads)             SQLMONITOR_THREADS="$2"; shift 2 ;;
        --skip-not-onboarded)  SKIP_NOT_ONBOARDED=1; shift ;;
        --verbose)             SQLMONITOR_VERBOSE=1; shift ;;
        -h|--help)             sed -n '2,14p' "$0"; exit 0 ;;
        *)                     sm_die "Unknown argument '$1'." ;;
    esac
done

sm_init

# The login used to probe each instance. The Windows script hardcoded
# grafana/grafana; keep that default but let operators override it.
: "${PROBE_LOGIN:=grafana}"
: "${PROBE_PASSWORD:=grafana}"

start_epoch=$(date +%s)

sm_info "Get all SQLInstances in SQLMonitor server [$INVENTORY_SERVER].[dbo].[instance_details].."

onboarded_filter='and (s.is_onboarded = 1 or s.is_onboarded is null)'
if [ "$SKIP_NOT_ONBOARDED" -eq 1 ]; then
    onboarded_filter='and s.is_onboarded = 1'
fi

read -r -d '' QRY_INSTANCES <<SQL || true
select distinct [sql_instance] = id.sql_instance,
       [sql_instance_port] = isnull(id.sql_instance_port,''),
       [database] = id.[database]
from dbo.instance_details id
outer apply (select s.is_onboarded from dbo.sma_servers s
             where s.is_decommissioned = 0 and s.server = id.sql_instance
            ) s
where id.is_enabled = 1 and id.is_alias = 0
and id.host_name <> CONVERT(varchar,COALESCE(SERVERPROPERTY('ComputerNamePhysicalNetBIOS'),SERVERPROPERTY('ServerName')))
$onboarded_filter
SQL

instances="$(sm_inv_tsv "$APP_NAME" "$QRY_INSTANCES")" || sm_die "Could not read dbo.instance_details from [$INVENTORY_SERVER]."

if [ -z "$instances" ]; then
    sm_warn "No SQLServers to check availability."
    exit 0
fi

sm_info "Below SQLInstances found in dbo.instance_details-"
printf '%s\n' "$instances" | awk -F'\t' '{printf "  %s\n", $1}'

RESULT_DIR="$(mktemp -d "${SQLMONITOR_WORK_DIR}/check-availability.XXXXXX")"
trap 'rm -rf "$RESULT_DIR"' EXIT

# --- one probe per instance, run under sm_parallel -------------------------
probe_instance() {
    local row="$1"
    local sql_instance sql_instance_port database target
    sql_instance="$(printf '%s' "$row" | cut -f1)"
    sql_instance_port="$(sm_nullable "$(printf '%s' "$row" | cut -f2)")"
    database="$(printf '%s' "$row" | cut -f3)"

    target="$sql_instance"
    [ -n "$sql_instance_port" ] && target="${sql_instance},${sql_instance_port}"

    local safe_name err
    safe_name="$(printf '%s' "$sql_instance" | tr -c 'A-Za-z0-9._-' '_')"

    local rc=0
    err="$(timeout "$PROBE_TIMEOUT_SECONDS" \
             "$SQLCMD" -S "$target" -d "$database" -C \
                 -l "$SQLMONITOR_LOGIN_TIMEOUT" -t "$SQLMONITOR_QUERY_TIMEOUT" \
                 -H "$JOB_NAME" -U "$PROBE_LOGIN" \
                 -b -h -1 -W -Q "SET NOCOUNT ON; select db_name();" 2>&1)" || rc=$?

    if [ "$rc" -eq 0 ]; then
        printf '%s\n' "$sql_instance" > "${RESULT_DIR}/ok.${safe_name}"
    elif [ "$rc" -eq 124 ]; then
        printf '%s\t%s\tTimedOut-Jobs\n' "$sql_instance" 'Query Timed Out' > "${RESULT_DIR}/fail.${safe_name}"
    else
        printf '%s\t%s\tFailed-Jobs\n' "$sql_instance" "${err//$'\n'/ }" > "${RESULT_DIR}/fail.${safe_name}"
    fi
}

sm_info "Probing instances with ${SQLMONITOR_THREADS} threads.."

# SQLCMDPASSWORD is exported so each background probe inherits it without the
# password ever appearing in the process table.
export SQLCMDPASSWORD="$PROBE_PASSWORD"
export RESULT_DIR SQLCMD JOB_NAME PROBE_LOGIN PROBE_TIMEOUT_SECONDS
export SQLMONITOR_LOGIN_TIMEOUT SQLMONITOR_QUERY_TIMEOUT

printf '%s\n' "$instances" | sm_parallel "$SQLMONITOR_THREADS" probe_instance
unset SQLCMDPASSWORD

online_instances=()
offline_instances=()

while IFS= read -r f; do
    [ -n "$f" ] || continue
    online_instances+=("$(cat "$f")")
done < <(find "$RESULT_DIR" -name 'ok.*' -type f 2>/dev/null)

while IFS= read -r f; do
    [ -n "$f" ] || continue
    IFS=$'\t' read -r inst err bucket < "$f"
    offline_instances+=("$inst")
    sm_error "Instance [$inst] is not reachable: $err"
    sm_errorlog "$APP_NAME" "$bucket" "$inst" "$err" "$JOB_NAME"
done < <(find "$RESULT_DIR" -name 'fail.*' -type f 2>/dev/null)

if [ "${#online_instances[@]}" -gt 0 ]; then
    sm_info "Setting [is_available] flag for ${#online_instances[@]} online server(s).."
    csv="$(sm_csv_literals "${online_instances[@]}")"
    sm_inv_exec "$APP_NAME" "update dbo.instance_details set is_available = 1
where is_enabled = 1 and is_available = 0
  and ( sql_instance in ($csv) or source_sql_instance in ($csv) );" \
        || sm_error "Failed to set is_available = 1."
fi

if [ "${#offline_instances[@]}" -gt 0 ]; then
    sm_info "Setting [is_available] flag for ${#offline_instances[@]} offline server(s).."
    csv="$(sm_csv_literals "${offline_instances[@]}")"
    sm_inv_exec "$APP_NAME" "update dbo.instance_details set is_available = 0, last_unavailability_time_utc = SYSUTCDATETIME()
where is_enabled = 1 and is_available = 1
  and ( sql_instance in ($csv) or source_sql_instance in ($csv) );" \
        || sm_error "Failed to set is_available = 0."
fi

sm_info "Execution completed in $(( $(date +%s) - start_epoch )) seconds. ${#online_instances[@]} online, ${#offline_instances[@]} offline."

# Exit non-zero when something was unreachable, so the systemd unit shows the
# failure the way the SQL Agent job step used to.
[ "${#offline_instances[@]}" -eq 0 ]
