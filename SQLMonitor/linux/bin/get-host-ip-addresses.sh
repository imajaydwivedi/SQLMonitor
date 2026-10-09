#!/usr/bin/env bash
# get-host-ip-addresses.sh
#
# Linux replacement for Wrapper-GetHostIpAddresses.ps1 (step 1 of the
# "(dba) Populate Inventory Tables" job).
#
# Resolves the IP of every non-decommissioned host in dbo.sma_sql_server_hosts
# and republishes the result into dbo.sma_sql_server_hosts_wrapper, which
# dbo.usp_wrapper_populate_sma_sql_instance then consumes.
#
# Test-NetConnection / Test-Connection are replaced by getent (DNS) with a ping
# fallback, so no ICMP is required when DNS already answers.
#
# Usage:
#   get-host-ip-addresses.sh [--ignore-ping-issue] [--keep-log] [--verbose]

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/sqlmonitor.sh
. "${SCRIPT_DIR}/../lib/sqlmonitor.sh"

APP_NAME='get-host-ip-addresses.sh'
JOB_NAME='(dba) Populate Inventory Tables'

IGNORE_PING_ISSUE=0
KEEP_LOG=0

while [ $# -gt 0 ]; do
    case "$1" in
        --ignore-ping-issue) IGNORE_PING_ISSUE=1; shift ;;
        --keep-log)          KEEP_LOG=1; shift ;;
        --verbose)           SQLMONITOR_VERBOSE=1; shift ;;
        -h|--help)           sed -n '2,16p' "$0"; exit 0 ;;
        *)                   sm_die "Unknown argument '$1'." ;;
    esac
done

sm_init
sm_resolve_all_server_login

start_time_utc="$(date -u +'%Y-%m-%d %H:%M:%S')"
log_file="${SQLMONITOR_LOG_DIR}/${APP_NAME}-$(date +%Y%b%d_%H%M).log"
: > "$log_file"
[ "$KEEP_LOG" -eq 1 ] || trap 'rm -f "$log_file"' EXIT

read -r -d '' QRY_HOSTS <<'SQL' || true
select  [sql_instance] = h.server,
        [sql_instance_port] = isnull(id.sql_instance_port,''),
        [inventory_host_name] = h.host_name,
        [hadr_strategy] = isnull(s.hadr_strategy,''),
        [host_fqdn] = coalesce(h.host_name+'.'+asi.domain+'.com', h.host_name)
from dbo.sma_sql_server_hosts h
join dbo.sma_servers s
    on s.server = h.server
left join dbo.instance_details id
    on id.sql_instance = s.server and id.host_name = h.host_name
    and id.is_enabled = 1 and id.is_alias = 0
left join dbo.vw_all_server_info asi
    on asi.srv_name = s.server
where s.is_decommissioned = 0 and h.is_decommissioned = 0
SQL

sm_info "Fetch hosts from [$INVENTORY_SERVER].[$INVENTORY_DATABASE].dbo.sma_sql_server_hosts.."
hosts="$(sm_inv_tsv "$APP_NAME" "$QRY_HOSTS")" \
    || sm_die "Could not read dbo.sma_sql_server_hosts."

if [ -z "$hosts" ]; then
    sm_warn "No hosts found to resolve."
    exit 0
fi

# --- resolve one FQDN to an IPv4 address -----------------------------------
resolve_ip() {
    local fqdn="$1" ip=''

    if command -v getent >/dev/null 2>&1; then
        ip="$(getent ahostsv4 "$fqdn" 2>/dev/null | awk 'NR==1 {print $1}')"
    fi
    if [ -z "$ip" ] && command -v dig >/dev/null 2>&1; then
        ip="$(dig +short +time=2 +tries=1 A "$fqdn" 2>/dev/null | grep -Em1 '^[0-9.]+$')"
    fi
    if [ -z "$ip" ] && command -v ping >/dev/null 2>&1; then
        ip="$(ping -c 1 -W 2 "$fqdn" 2>/dev/null \
              | sed -nE '1s/.*\(([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\).*/\1/p')"
    fi
    printf '%s' "$ip"
}

values=''
success=0
failed=0

while IFS=$'\t' read -r sql_instance sql_instance_port host_name hadr_strategy host_fqdn; do
    [ -n "$sql_instance" ] || continue
    sql_instance_port="$(sm_nullable "$sql_instance_port")"
    hadr_strategy="$(sm_nullable "$hadr_strategy")"
    host_fqdn="$(sm_nullable "$host_fqdn")"
    [ -n "$host_fqdn" ] || host_fqdn="$host_name"

    target="$sql_instance"
    [ -n "$sql_instance_port" ] && target="${sql_instance},${sql_instance_port}"
    sm_info "Working on [$target].[$host_name].." | tee -a "$log_file"

    ip="$(resolve_ip "$host_fqdn")"

    if [ -z "$ip" ] && [ "$IGNORE_PING_ISSUE" -eq 0 ]; then
        failed=$((failed + 1))
        sm_error "Could not resolve '$host_fqdn'." | tee -a "$log_file" >&2
        sm_errorlog "$APP_NAME" 'resolve_ip' "$sql_instance" \
            "Could not resolve host '$host_fqdn'." "$JOB_NAME"
        continue
    fi

    [ -n "$ip" ] && success=$((success + 1))

    values+="${values:+,}
    ($(sm_sql_nstring "$sql_instance"), $(sm_sql_nstring "$sql_instance_port"), $(sm_sql_nstring "$host_name"), $(sm_sql_nstring "$ip"), $(sm_sql_nstring "$hadr_strategy"), $(sm_sql_nstring "$host_fqdn"), '$start_time_utc')"
done <<< "$hosts"

if [ -z "$values" ]; then
    sm_warn "Nothing resolved; leaving dbo.sma_sql_server_hosts_wrapper untouched."
    exit 1
fi

# The PowerShell version relied on Write-DbaDbTableData -AutoCreateTable. Being
# explicit about the shape is both safer and self-documenting.
read -r -d '' DDL_WRAPPER_TABLE <<'SQL' || true
if object_id('dbo.sma_sql_server_hosts_wrapper') is null
begin
    create table dbo.sma_sql_server_hosts_wrapper (
        sql_instance        nvarchar(255) not null,
        sql_instance_port   nvarchar(10)  null,
        host_name           nvarchar(255) not null,
        Ip                  nvarchar(48)  null,
        hadr_strategy       nvarchar(50)  null,
        host_fqdn           nvarchar(500) null,
        collection_time     datetime2(0)  not null
    );
end
SQL

sm_inv_exec "$APP_NAME" "$DDL_WRAPPER_TABLE" >/dev/null \
    || sm_die "Could not ensure dbo.sma_sql_server_hosts_wrapper exists."

sm_info "Publishing $((success + failed)) row(s) into dbo.sma_sql_server_hosts_wrapper.."
sm_inv_exec "$APP_NAME" "set nocount on;
begin tran;
    truncate table dbo.sma_sql_server_hosts_wrapper;
    insert into dbo.sma_sql_server_hosts_wrapper
        (sql_instance, sql_instance_port, host_name, Ip, hadr_strategy, host_fqdn, collection_time)
    values $values;
commit tran;" >/dev/null \
    || sm_die "Insert into dbo.sma_sql_server_hosts_wrapper failed."

sm_info "Done. $success resolved, $failed unresolved."
[ "$failed" -eq 0 ]
