#!/usr/bin/env bash
# run-on-all-servers.sh
#
# Linux replacement for loop-through-all-sqlmonitor-servers.ps1 (and the
# fleet-loop half of Run-MultiServerScript.ps1).
#
# Reads the fleet from dbo.instance_details on the inventory server and runs a
# query or a .sql file against each instance, using the Credential-Manager
# resolved fleet login. Prints a success/failure summary and records every
# failure in dbo.sma_errorlog.
#
# Usage:
#   run-on-all-servers.sh --query "select @@servername"
#   run-on-all-servers.sh --file ../../DDLs/SCH-usp_active_requests_count.sql
#   run-on-all-servers.sh --file a.sql --file b.sql --servers 'SRV1,SRV2'
#
# Options:
#   --query Q        T-SQL to run (repeatable, runs before --file entries)
#   --file  F        .sql file to run (repeatable)
#   --servers LIST   comma-separated sql_instance filter; default is every
#                    enabled, available, non-alias instance
#   --database D     database to connect to; default is instance_details.[database]
#   --continue       keep going after a failure (default)
#   --stop-on-error  abort at the first failing instance
#   --verbose

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/sqlmonitor.sh
. "${SCRIPT_DIR}/../lib/sqlmonitor.sh"

APP_NAME='run-on-all-servers.sh'

QUERIES=()
FILES=()
SERVER_FILTER=''
FORCE_DATABASE=''
STOP_ON_ERROR=0

while [ $# -gt 0 ]; do
    case "$1" in
        --query)         QUERIES+=("$2"); shift 2 ;;
        --file)          FILES+=("$2"); shift 2 ;;
        --servers)       SERVER_FILTER="$2"; shift 2 ;;
        --database)      FORCE_DATABASE="$2"; shift 2 ;;
        --continue)      STOP_ON_ERROR=0; shift ;;
        --stop-on-error) STOP_ON_ERROR=1; shift ;;
        --verbose)       SQLMONITOR_VERBOSE=1; shift ;;
        -h|--help)       sed -n '2,26p' "$0"; exit 0 ;;
        *)               sm_die "Unknown argument '$1'." ;;
    esac
done

if [ "${#QUERIES[@]}" -eq 0 ] && [ "${#FILES[@]}" -eq 0 ]; then
    sm_die "Nothing to run. Pass --query and/or --file."
fi

for f in ${FILES[@]+"${FILES[@]}"}; do
    [ -r "$f" ] || sm_die "SQL file '$f' is not readable."
done

sm_init
sm_resolve_all_server_login

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
where id.is_enabled = 1 and id.is_alias = 0 and id.is_available = 1
$server_predicate
SQL

sm_info "Get list of SQLInstances from dbo.instance_details.."
fleet="$(sm_inv_tsv "$APP_NAME" "$QRY_FLEET")" || sm_die "Could not read dbo.instance_details."
[ -n "$fleet" ] || { sm_warn "No instances matched."; exit 0; }

success=0
failed=0
failed_servers=()

while IFS=$'\t' read -r sql_instance sql_instance_port database; do
    [ -n "$sql_instance" ] || continue
    sql_instance_port="$(sm_nullable "$sql_instance_port")"
    [ -n "$FORCE_DATABASE" ] && database="$FORCE_DATABASE"

    target="$sql_instance"
    [ -n "$sql_instance_port" ] && target="${sql_instance},${sql_instance_port}"

    sm_info "Working on [$target].."
    instance_failed=0

    for q in ${QUERIES[@]+"${QUERIES[@]}"}; do
        if ! out="$(sm_fleet_sql "$target" "$database" "$APP_NAME" exec "$q" 2>&1)"; then
            instance_failed=1
            sm_error "  query failed: ${out//$'\n'/ }"
            sm_errorlog "$APP_NAME" 'inline query' "$sql_instance" "${out//$'\n'/ }" "$APP_NAME"
            [ "$STOP_ON_ERROR" -eq 1 ] && sm_die "Stopping at first error."
            break
        fi
        [ -n "$out" ] && printf '%s\n' "$out"
    done

    if [ "$instance_failed" -eq 0 ]; then
        for f in ${FILES[@]+"${FILES[@]}"}; do
            sm_info "  execute file '$f'.."
            args=(-S "$target" -d "$database" -C -b
                  -l "$SQLMONITOR_LOGIN_TIMEOUT" -t "$SQLMONITOR_QUERY_TIMEOUT"
                  -H "$APP_NAME" -i "$f")
            if [ -n "$ALL_SERVER_LOGIN" ]; then
                args+=(-U "$ALL_SERVER_LOGIN")
                password="$ALL_SERVER_PASSWORD"
            elif [ -n "$INVENTORY_LOGIN" ]; then
                args+=(-U "$INVENTORY_LOGIN")
                password="$INVENTORY_PASSWORD"
            else
                args+=(-E)
                password=''
            fi

            if ! out="$(SQLCMDPASSWORD="$password" "$SQLCMD" "${args[@]}" 2>&1)"; then
                instance_failed=1
                sm_error "  file '$f' failed: ${out//$'\n'/ }"
                sm_errorlog "$APP_NAME" "$f" "$sql_instance" "${out//$'\n'/ }" "$APP_NAME"
                [ "$STOP_ON_ERROR" -eq 1 ] && sm_die "Stopping at first error."
                break
            fi
            [ -n "$out" ] && printf '%s\n' "$out"
        done
    fi

    if [ "$instance_failed" -eq 0 ]; then
        success=$((success + 1))
    else
        failed=$((failed + 1))
        failed_servers+=("$target")
    fi
done <<< "$fleet"

sm_info "Successful servers: $success"
if [ "$failed" -gt 0 ]; then
    sm_error "Failed servers ($failed): ${failed_servers[*]}"
fi
[ "$failed" -eq 0 ]
