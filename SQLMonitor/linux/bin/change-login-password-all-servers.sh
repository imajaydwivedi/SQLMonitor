#!/usr/bin/env bash
# change-login-password-all-servers.sh
#
# Linux replacement for Wrapper-ChangeLoginPasswordAllServers.ps1.
#
# Reads the new password for each named login from the Credential Manager on
# the inventory server, then resets that login on every enabled instance in
# dbo.instance_details (check_policy off -> ALTER LOGIN -> check_policy on).
#
# Passwords are passed to sqlcmd as :setvar-free T-SQL built inside the script
# and never appear on a command line or in the process table.
#
# Usage:
#   change-login-password-all-servers.sh --logins 'grafana,sqlmonitor_fleet'
#                                        [--servers 'SRV1,SRV2'] [--dry-run]
#                                        [--verbose]

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/sqlmonitor.sh
. "${SCRIPT_DIR}/../lib/sqlmonitor.sh"

APP_NAME='change-login-password-all-servers.sh'
JOB_NAME='(dba) Change-LoginPasswordAllServers'

LOGINS=''
SERVER_FILTER=''
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --logins)  LOGINS="$2"; shift 2 ;;
        --servers) SERVER_FILTER="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        --verbose) SQLMONITOR_VERBOSE=1; shift ;;
        -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
        *)         sm_die "Unknown argument '$1'." ;;
    esac
done

[ -n "$LOGINS" ] || sm_die "--logins is required."

sm_init
sm_resolve_all_server_login

IFS=',' read -r -a login_list <<< "$LOGINS"

# --- resolve every new password up front -----------------------------------
declare -A login_password=()
for login in "${login_list[@]}"; do
    [ -n "$login" ] || continue
    sm_info "Fetch password for login [$login] from Credential Manager.."
    pw="$(sm_get_credential "$login")"
    [ -n "$pw" ] || sm_die "Credential Manager has no password for login [$login]."
    login_password[$login]="$pw"
done

server_predicate=''
if [ -n "$SERVER_FILTER" ]; then
    IFS=',' read -r -a _servers <<< "$SERVER_FILTER"
    server_predicate="and id.sql_instance in ($(sm_csv_literals "${_servers[@]}"))"
fi

read -r -d '' QRY_FLEET <<SQL || true
select distinct id.sql_instance,
       [sql_instance_port] = isnull(id.sql_instance_port,''),
       id.[database]
from dbo.instance_details id
where id.is_enabled = 1 and id.is_alias = 0
$server_predicate
SQL

sm_info "Get list of SQLInstances from dbo.instance_details.."
fleet="$(sm_inv_tsv "$APP_NAME" "$QRY_FLEET")" || sm_die "Could not read dbo.instance_details."
[ -n "$fleet" ] || { sm_warn "No instances matched."; exit 0; }

success=0
failed=0

while IFS=$'\t' read -r sql_instance sql_instance_port database; do
    [ -n "$sql_instance" ] || continue
    sql_instance_port="$(sm_nullable "$sql_instance_port")"
    target="$sql_instance"
    [ -n "$sql_instance_port" ] && target="${sql_instance},${sql_instance_port}"

    sm_info "Working on [$target].."

    if ! err="$(sm_fleet_sql "$target" master "$APP_NAME" scalar 'select 1;' 2>&1)"; then
        failed=$((failed + 1))
        sm_error "  connection failed: ${err//$'\n'/ }"
        sm_errorlog "$APP_NAME" 'connect' "$sql_instance" "${err//$'\n'/ }" "$JOB_NAME"
        continue
    fi

    for login in "${login_list[@]}"; do
        [ -n "$login" ] || continue
        sm_info "  login [$login].."

        if [ "$DRY_RUN" -eq 1 ]; then
            sm_info "  --dry-run: would reset [$login] on [$target]."
            continue
        fi

        stmt="use [master];
alter login [$(sm_sql_escape "$login")] with check_policy = off;
alter login [$(sm_sql_escape "$login")] with password = N'$(sm_sql_escape "${login_password[$login]}")';
alter login [$(sm_sql_escape "$login")] with check_policy = on;"

        if out="$(sm_fleet_sql "$target" master "$APP_NAME" exec "$stmt" 2>&1)"; then
            success=$((success + 1))
        else
            failed=$((failed + 1))
            sm_error "  reset of [$login] failed: ${out//$'\n'/ }"
            sm_errorlog "$APP_NAME" "alter login [$login]" "$sql_instance" "${out//$'\n'/ }" "$JOB_NAME"
        fi
    done
done <<< "$fleet"

sm_info "Completed. $success reset(s) succeeded, $failed failure(s)."
[ "$failed" -eq 0 ]
