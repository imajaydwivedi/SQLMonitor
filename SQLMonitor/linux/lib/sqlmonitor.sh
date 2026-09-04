#!/usr/bin/env bash
# sqlmonitor.sh - shared helpers for the SQLMonitor Linux inventory lane.
#
# This is the bash equivalent of what the Windows lane got from dbatools:
# connection handling, credential lookup, logging and dbo.sma_errorlog writes.
#
# Source it, do not execute it:
#
#     . "$(dirname "$0")/../lib/sqlmonitor.sh"
#     sm_init
#
# Requires bash 4.3 or newer (sm_parallel uses `wait -n`) and relies only on
# sqlcmd, coreutils and curl. No PowerShell, no dbatools, no WMI.

if [ -n "${_SQLMONITOR_LIB_LOADED:-}" ]; then
    return 0
fi
_SQLMONITOR_LIB_LOADED=1

# ---------------------------------------------------------------------------
# Defaults. Every one of these can be overridden by the config file or by an
# already-exported environment variable of the same name.
# ---------------------------------------------------------------------------
: "${SQLMONITOR_CONF:=/etc/sqlmonitor/inventory.conf}"
: "${SQLMONITOR_HOME:=/opt/sqlmonitor}"
: "${SQLMONITOR_WORK_DIR:=/var/opt/sqlmonitor/work}"
: "${SQLMONITOR_LOG_DIR:=/var/log/sqlmonitor}"

: "${INVENTORY_SERVER:=localhost}"
: "${INVENTORY_DATABASE:=DBA}"
: "${CREDENTIAL_MANAGER_DATABASE:=DBA}"

# Login used to reach the inventory server itself.
: "${INVENTORY_LOGIN:=}"
: "${INVENTORY_PASSWORD:=}"
: "${INVENTORY_PASSWORD_FILE:=}"

# Login used to reach the rest of the fleet. Its password is resolved through
# the Credential Manager on the inventory server (dbo.usp_get_credential).
: "${ALL_SERVER_LOGIN:=}"
: "${ALL_SERVER_PASSWORD:=}"

: "${SQLMONITOR_QUERY_TIMEOUT:=300}"
: "${SQLMONITOR_LOGIN_TIMEOUT:=15}"
: "${SQLMONITOR_THREADS:=4}"
: "${SQLMONITOR_VERBOSE:=0}"

# ---------------------------------------------------------------------------
# Logging - mirrors the "yyyyMMMdd_HHmm LEVEL:     message" shape the
# PowerShell collectors used, so existing log greps keep working.
# ---------------------------------------------------------------------------
sm_log() {
    local level="$1"; shift
    printf '%s %-10s %s\n' "$(date +%Y%b%d_%H%M)" "${level}:" "$*"
}
sm_info()    { sm_log 'INFO' "$@"; }
sm_warn()    { sm_log 'WARNING' "$@" >&2; }
sm_error()   { sm_log 'ERROR' "$@" >&2; }
sm_verbose() { [ "${SQLMONITOR_VERBOSE}" != "0" ] && sm_log 'VERBOSE' "$@" || true; }

sm_die() {
    sm_error "$@"
    exit 1
}

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
sm_load_conf() {
    if [ -r "$SQLMONITOR_CONF" ]; then
        # shellcheck disable=SC1090
        . "$SQLMONITOR_CONF"
        sm_verbose "Loaded config '$SQLMONITOR_CONF'."
    else
        sm_verbose "No config at '$SQLMONITOR_CONF'; using defaults and environment."
    fi

    if [ -z "$INVENTORY_PASSWORD" ] && [ -n "$INVENTORY_PASSWORD_FILE" ]; then
        [ -r "$INVENTORY_PASSWORD_FILE" ] \
            || sm_die "INVENTORY_PASSWORD_FILE '$INVENTORY_PASSWORD_FILE' is not readable."
        INVENTORY_PASSWORD="$(< "$INVENTORY_PASSWORD_FILE")"
    fi
}

# ---------------------------------------------------------------------------
# sqlcmd discovery. mssql-tools18 first, then the older package, then PATH.
# ---------------------------------------------------------------------------
sm_find_sqlcmd() {
    if [ -n "${SQLCMD:-}" ] && [ -x "$SQLCMD" ]; then
        printf '%s' "$SQLCMD"
        return 0
    fi
    local candidate
    for candidate in /opt/mssql-tools18/bin/sqlcmd /opt/mssql-tools/bin/sqlcmd; do
        if [ -x "$candidate" ]; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    if command -v sqlcmd >/dev/null 2>&1; then
        command -v sqlcmd
        return 0
    fi
    return 1
}

sm_require() {
    local bin
    for bin in "$@"; do
        command -v "$bin" >/dev/null 2>&1 || sm_die "Required command '$bin' not found in PATH."
    done
}

sm_init() {
    sm_load_conf
    SQLCMD="$(sm_find_sqlcmd)" \
        || sm_die "sqlcmd not found. Install mssql-tools18 (https://learn.microsoft.com/sql/linux/sql-server-linux-setup-tools) or set SQLCMD."
    export SQLCMD
    mkdir -p "$SQLMONITOR_WORK_DIR" "$SQLMONITOR_LOG_DIR" 2>/dev/null || true
    sm_verbose "Using sqlcmd at '$SQLCMD'."
}

# ---------------------------------------------------------------------------
# T-SQL literal escaping. Always run user/DB-sourced values through this before
# interpolating them into a query.
# ---------------------------------------------------------------------------
sm_sql_escape() {
    printf '%s' "${1//\'/\'\'}"
}

# ---------------------------------------------------------------------------
# Core sqlcmd wrapper.
#
#   sm_sql <server> <database> <app-name> <mode> <query> [user] [password]
#
# mode is one of:
#   exec   - run for side effects, stop on error (-b), no result formatting
#   tsv    - return rows as tab-separated values, no header, trimmed
#   scalar - return the first column of the first row
#
# When user/password are empty the inventory login from the config is used.
# There is deliberately no Windows-integrated-auth (-E) path: it does not work
# on SQL Server on Linux.
# ---------------------------------------------------------------------------
sm_sql() {
    local server="$1" database="$2" appname="$3" mode="$4" query="$5"
    local user="${6-}" password="${7-}"

    if [ -z "$user" ]; then
        user="$INVENTORY_LOGIN"
        password="$INVENTORY_PASSWORD"
    fi

    local -a args=(
        -S "$server"
        -d "$database"
        -C                                   # trust server certificate
        -l "$SQLMONITOR_LOGIN_TIMEOUT"
        -t "$SQLMONITOR_QUERY_TIMEOUT"
        -H "$appname"                        # workstation name, as the old jobs did
    )

    if [ -n "$user" ]; then
        args+=(-U "$user")
    else
        # No SQL login configured: fall back to whatever sqlcmd picks up from
        # SQLCMDUSER/SQLCMDPASSWORD, or Kerberos if the host has a ticket.
        args+=(-E)
    fi

    case "$mode" in
        exec)
            args+=(-b -Q "$query")
            ;;
        tsv)
            args+=(-b -h -1 -W -s $'\t' -Q "SET NOCOUNT ON; $query")
            ;;
        scalar)
            args+=(-b -h -1 -W -Q "SET NOCOUNT ON; $query")
            ;;
        *)
            sm_die "sm_sql: unknown mode '$mode'."
            ;;
    esac

    if [ -n "$user" ] && [ -n "$password" ]; then
        SQLCMDPASSWORD="$password" "$SQLCMD" "${args[@]}"
    else
        "$SQLCMD" "${args[@]}"
    fi
}

# Convenience wrappers against the inventory server.
sm_inv_exec() {
    local appname="$1" query="$2" database="${3:-$INVENTORY_DATABASE}"
    sm_sql "$INVENTORY_SERVER" "$database" "$appname" exec "$query"
}

sm_inv_tsv() {
    local appname="$1" query="$2" database="${3:-$INVENTORY_DATABASE}"
    sm_sql "$INVENTORY_SERVER" "$database" "$appname" tsv "$query" \
        | sed '/^$/d'
}

sm_inv_scalar() {
    local appname="$1" query="$2" database="${3:-$INVENTORY_DATABASE}"
    sm_sql "$INVENTORY_SERVER" "$database" "$appname" scalar "$query" \
        | sed '/^$/d' | head -n 1
}

# ---------------------------------------------------------------------------
# Credential Manager - the bash counterpart of the
# "exec dbo.usp_get_credential ... | Select -Expand password" block that every
# inventory PowerShell script carried.
# ---------------------------------------------------------------------------
sm_get_credential() {
    local user_name="$1"
    local server_ip="${2:-*}"
    [ -n "$user_name" ] || sm_die "sm_get_credential: user name is required."

    local query
    query="declare @password varchar(256);
exec dbo.usp_get_credential @server_ip = '$(sm_sql_escape "$server_ip")',
    @user_name = '$(sm_sql_escape "$user_name")',
    @password = @password output;
select @password;"

    sm_inv_scalar 'sqlmonitor-credential-lookup' "$query" "$CREDENTIAL_MANAGER_DATABASE"
}

# Resolve ALL_SERVER_PASSWORD once per process, if a fleet login is configured.
sm_resolve_all_server_login() {
    if [ -z "$ALL_SERVER_LOGIN" ]; then
        sm_warn "ALL_SERVER_LOGIN is not set; fleet connections will use the inventory login."
        return 0
    fi
    if [ -n "$ALL_SERVER_PASSWORD" ]; then
        return 0
    fi
    sm_info "Fetch [$ALL_SERVER_LOGIN] password from Credential Manager [$INVENTORY_SERVER].[$CREDENTIAL_MANAGER_DATABASE].."
    ALL_SERVER_PASSWORD="$(sm_get_credential "$ALL_SERVER_LOGIN")"
    [ -n "$ALL_SERVER_PASSWORD" ] \
        || sm_die "Credential Manager returned no password for login [$ALL_SERVER_LOGIN]."
}

# Run a query against a fleet instance using the resolved fleet credential.
sm_fleet_sql() {
    local server="$1" database="$2" appname="$3" mode="$4" query="$5"
    if [ -n "$ALL_SERVER_LOGIN" ]; then
        sm_sql "$server" "$database" "$appname" "$mode" "$query" \
            "$ALL_SERVER_LOGIN" "$ALL_SERVER_PASSWORD"
    else
        sm_sql "$server" "$database" "$appname" "$mode" "$query"
    fi
}

# ---------------------------------------------------------------------------
# dbo.sma_errorlog - the inventory-side error sink. Never let a logging failure
# take down the caller.
# ---------------------------------------------------------------------------
sm_errorlog() {
    local function_name="$1" call_arguments="$2" server="$3" error="$4" program="$5"
    local query
    query="insert dbo.sma_errorlog (function_name, function_call_arguments, server, error, executor_program_name)
select '$(sm_sql_escape "$function_name")', '$(sm_sql_escape "$call_arguments")',
       '$(sm_sql_escape "$server")', '$(sm_sql_escape "$error")', '$(sm_sql_escape "$program")';"

    if ! sm_inv_exec 'sqlmonitor-errorlog' "$query" >/dev/null 2>&1; then
        sm_warn "Could not write to dbo.sma_errorlog for server '$server'."
    fi
}

# ---------------------------------------------------------------------------
# Bounded parallel fan-out. Replaces PoshRSJob's -Throttle.
#
#   sm_parallel <max_jobs> <command> [fixed args...] < list-of-lines
#
# Each input line is appended as the final argument. Returns non-zero if any
# child failed.
# ---------------------------------------------------------------------------
sm_parallel() {
    local max_jobs="$1"; shift
    local rc=0 line running=0

    while IFS= read -r line; do
        [ -n "$line" ] || continue
        "$@" "$line" &
        running=$((running + 1))
        if [ "$running" -ge "$max_jobs" ]; then
            wait -n 2>/dev/null || rc=1
            running=$((running - 1))
        fi
    done

    while [ "$running" -gt 0 ]; do
        wait -n 2>/dev/null || rc=1
        running=$((running - 1))
    done

    return "$rc"
}

# Render a value as a T-SQL nvarchar literal, or NULL when it is empty.
sm_sql_nstring() {
    if [ -z "${1-}" ]; then
        printf 'NULL'
    else
        printf "N'%s'" "$(sm_sql_escape "$1")"
    fi
}

# Build a T-SQL "'a','b','c'" literal list from the arguments.
sm_csv_literals() {
    local out='' item
    for item in "$@"; do
        out+="${out:+,}'$(sm_sql_escape "$item")'"
    done
    printf '%s' "$out"
}

# Trim leading/trailing whitespace - sqlcmd -W already right-trims, but NULLs
# come back as the literal "NULL" which callers usually want as empty.
sm_nullable() {
    local value="$1"
    if [ "$value" = "NULL" ]; then
        printf ''
    else
        printf '%s' "$value"
    fi
}
