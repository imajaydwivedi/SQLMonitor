#!/usr/bin/env bash
# sqlserver-versions-update.sh
#
# Linux replacement for sqlserver-versions-update.ps1 and the
# "(dba) Update-SqlServerVersions" SQL Agent job.
#
# Downloads BrentOzarULTD/SQL-Server-First-Responder-Kit SqlServerVersions.sql
# and applies it to the inventory instance, keeping dbo.SqlServerVersions
# current with CU metadata.
#
# Usage:
#   sqlserver-versions-update.sh [--server S] [--database D] [--url URL] [--verbose]

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/sqlmonitor.sh
. "${SCRIPT_DIR}/../lib/sqlmonitor.sh"

APP_NAME='(dba) Update-SqlServerVersions'
TARGET_DATABASE='master'
TARGET_SERVER=''

while [ $# -gt 0 ]; do
    case "$1" in
        --server)   TARGET_SERVER="$2"; shift 2 ;;
        --database) TARGET_DATABASE="$2"; shift 2 ;;
        --url)      SQL_SERVER_VERSIONS_URL="$2"; shift 2 ;;
        --verbose)  SQLMONITOR_VERBOSE=1; shift ;;
        -h|--help)  sed -n '2,13p' "$0"; exit 0 ;;
        *)          sm_die "Unknown argument '$1'." ;;
    esac
done

sm_init
sm_require curl

: "${SQL_SERVER_VERSIONS_URL:=https://raw.githubusercontent.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/dev/SqlServerVersions.sql}"
[ -n "$TARGET_SERVER" ] || TARGET_SERVER="$INVENTORY_SERVER"

script_file="$(mktemp "${SQLMONITOR_WORK_DIR}/SqlServerVersions.XXXXXX.sql")"
trap 'rm -f "$script_file"' EXIT

sm_info "Fetch file from Internet.."
if ! curl --fail --silent --show-error --location --retry 3 --retry-delay 5 \
        --max-time 120 -o "$script_file" "$SQL_SERVER_VERSIONS_URL"; then
    sm_die "Download of '$SQL_SERVER_VERSIONS_URL' failed."
fi

if [ ! -s "$script_file" ]; then
    sm_die "Downloaded file is empty; refusing to run it against [$TARGET_SERVER]."
fi

sm_info "Execute query against [$TARGET_SERVER].[$TARGET_DATABASE].."

sqlcmd_args=(
    -S "$TARGET_SERVER"
    -d "$TARGET_DATABASE"
    -C -b
    -l "$SQLMONITOR_LOGIN_TIMEOUT"
    -t "$SQLMONITOR_QUERY_TIMEOUT"
    -H "$APP_NAME"
    -i "$script_file"
)
if [ -n "$INVENTORY_LOGIN" ]; then
    sqlcmd_args+=(-U "$INVENTORY_LOGIN")
else
    sqlcmd_args+=(-E)
fi

if SQLCMDPASSWORD="$INVENTORY_PASSWORD" "$SQLCMD" "${sqlcmd_args[@]}"; then
    sm_info "SqlServerVersions applied successfully."
else
    err="Applying SqlServerVersions.sql to [$TARGET_SERVER].[$TARGET_DATABASE] failed."
    sm_errorlog 'sqlserver-versions-update.sh' "$SQL_SERVER_VERSIONS_URL" \
        "$TARGET_SERVER" "$err" "$APP_NAME"
    sm_die "$err"
fi
