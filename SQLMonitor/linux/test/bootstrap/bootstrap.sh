#!/usr/bin/env bash
# bootstrap.sh - bring the test rig's SQL Server instances up to the point where
# SQLMonitor/linux/install-inventory.sh can run.
#
# Runs INSIDE the tools container (`make bootstrap`). Idempotent: re-running it
# re-applies the DDLs, which are all CREATE-OR-ALTER / guarded.
#
# Order matters and is not obvious, so it is spelled out here rather than
# buried in a Makefile:
#
#   every instance      1. DBA database + logins           (01-instance-common.sql)
#                       2. DDLs/SCH-Create-All-Objects.sql (tables, views, partitioning)
#                       3. DDLs/SCH-usp_*.sql              (collection + reporting procs)
#   inventory only      4. Credential-Manager/*.sql        (dbo.usp_get_credential et al)
#                       5. SCH-Create-Inventory-Specific-Objects.sql (all_server_* tables)
#                       6. 02-inventory-seed.sql           (sma_params, instance_details)
#                       7. 03-linked-servers.sql           (inventory -> each monitored)

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-/repo}"
DDL_DIR="${REPO_ROOT}/DDLs"
CM_DIR="${REPO_ROOT}/Credential-Manager"

INVENTORY_SERVER="${INVENTORY_SERVER:-inventory}"
MONITORED_SERVERS="${MONITORED_SERVERS:-monitored1}"
INVENTORY_DATABASE="${INVENTORY_DATABASE:-DBA}"
SA_PASSWORD="${SA_PASSWORD:?SA_PASSWORD is required}"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-grafana}"

INVENTORY_LOGIN="${INVENTORY_LOGIN:-sqlmonitor_inventory}"
INVENTORY_PASSWORD="${INVENTORY_PASSWORD:-$SA_PASSWORD}"
DBA_EMAIL="${DBA_EMAIL:-sqlmonitor-test@example.invalid}"

# sp_WhoIsActive and the First Responder Kit are what Install-SQLMonitor.ps1
# steps 1 and 4 install. Without them dbo.WhoIsActive / dbo.BlitzIndex* never
# exist, and every (dba) Get-AllServerStableInfo run logs "Invalid object name"
# into dbo.sma_errorlog. Set to 0 for a faster bootstrap and a noisier log.
INSTALL_OPTIONAL_TOOLS="${INSTALL_OPTIONAL_TOOLS:-1}"

SQLCMD="${SQLCMD:-/opt/mssql-tools18/bin/sqlcmd}"

log()  { printf '%s %-9s %s\n' "$(date +%Y%b%d_%H%M%S)" 'INFO:' "$*"; }
warn() { printf '%s %-9s %s\n' "$(date +%Y%b%d_%H%M%S)" 'WARNING:' "$*" >&2; }
die()  { printf '%s %-9s %s\n' "$(date +%Y%b%d_%H%M%S)" 'ERROR:' "$*" >&2; exit 1; }

# --- sqlcmd wrappers -------------------------------------------------------
sa() {   # sa <server> <database> <sqlcmd args...>
    local server="$1" db="$2"; shift 2
    SQLCMDPASSWORD="$SA_PASSWORD" "$SQLCMD" -S "$server" -d "$db" -U sa -C -b \
        -l 15 -t 300 -H bootstrap.sh "$@"
}

wait_for() {
    local server="$1" i
    log "Waiting for [$server] to accept logins.."
    for i in $(seq 1 60); do
        if sa "$server" master -Q "SELECT 1" >/dev/null 2>&1; then
            log "  [$server] ready after ~$((i * 5))s"
            return 0
        fi
        sleep 5
    done
    die "[$server] never became ready."
}

# apply_file <server> <db> <file> [stop_on_error]
#
# stop_on_error defaults to 1 (sqlcmd -b). Pass 0 for scripts that are NOT
# idempotent. Two of the shipped scripts drop objects and then recreate them
# with unguarded CREATEs, so a SECOND run raises Msg 2714 partway through; with
# -b sqlcmd stops there, after the drops and before the recreates, leaving the
# database in a worse state than before. Continuing past the error is correct
# for those, which is why the caller asserts the result afterwards.
apply_file() {
    local server="$1" db="$2" file="$3" stop_on_error="${4:-1}" out rc=0
    [ -r "$file" ] || { warn "  missing: $file"; return 0; }

    local -a extra=()
    [ "$stop_on_error" = "1" ] && extra+=(-b)

    out="$(sa "$server" "$db" "${extra[@]+"${extra[@]}"}" -i "$file" 2>&1)" || rc=$?

    if [ "$stop_on_error" != "1" ]; then
        # Report the errors, but do not treat them as fatal - the caller checks
        # the end state instead.
        local noise
        noise="$(printf '%s\n' "$out" | grep -cE '^Msg ' || true)"
        [ "$noise" != "0" ] && log "    $(basename "$file") - $noise message(s), continuing (non-idempotent script)"
        return 0
    fi

    if [ "$rc" -ne 0 ]; then
        warn "  FAILED $(basename "$file")"
        printf '%s\n' "$out" | grep -iE '^Msg|Level 1[1-9]|Level 2[0-5]' | head -5 >&2
        return 1
    fi
    return 0
}

apply_glob() {
    local server="$1" db="$2"; shift 2
    local label="$1"; shift
    local file applied=0 failed=0
    log "  $label"
    for file in "$@"; do
        [ -r "$file" ] || continue
        if apply_file "$server" "$db" "$file"; then
            applied=$((applied + 1))
        else
            failed=$((failed + 1))
        fi
    done
    log "    $applied applied, $failed failed"
    return "$failed"
}

# Procs that read the all_server_* tables, which only ever exist on the
# inventory server (SCH-Create-Inventory-Specific-Objects.sql creates them).
# Applying these to a monitored instance fails with Msg 207/208 by design, so
# they are skipped there and applied to the inventory AFTER the inventory
# tables exist.
INVENTORY_ONLY_PROCS=(
    SCH-usp_GetAllServerInfo.sql
    SCH-usp_GetAllServerCollectedData.sql
    SCH-usp_GetAllServerDashboardMail.sql
    SCH-usp_check_instance_availability.sql
    SCH-usp_collect_all_server_login_expiration_info.sql
    SCH-usp_compute_LAMA_targets.sql
    SCH-usp_populate_sma_sql_instance.sql
    SCH-usp_send_login_expiry_emails.sql
    SCH-usp_wrapper_populate_sma_sql_instance.sql
    SCH-usp_wrapper_GetAllServerInfo.sql
    SCH-usp_wrapper_GetAllServerCollectedData.sql
    SCH-usp_compute_all_server_volatile_info_history_hourly.sql
)

is_inventory_only_proc() {
    local base="$1" p
    for p in "${INVENTORY_ONLY_PROCS[@]}"; do
        [ "$base" = "$p" ] && return 0
    done
    return 1
}

# --- per-instance common ---------------------------------------------------
bootstrap_instance() {
    local server="$1" is_inventory="$2"
    log "=== [$server] ==="

    log "  01-instance-common.sql"
    sa "$server" master \
        -v GrafanaPassword="$GRAFANA_PASSWORD" \
           InventoryLogin="$INVENTORY_LOGIN" \
           InventoryPassword="$INVENTORY_PASSWORD" \
        -i "${SCRIPT_DIR}/01-instance-common.sql" >/dev/null \
        || die "01-instance-common.sql failed on [$server]"

    log "  SCH-Create-All-Objects.sql"
    apply_file "$server" "$INVENTORY_DATABASE" "${DDL_DIR}/SCH-Create-All-Objects.sql" \
        || die "SCH-Create-All-Objects.sql failed on [$server]"

    # Procs use deferred name resolution, so filename order is good enough.
    local files=() f
    for f in "${DDL_DIR}"/SCH-usp_*.sql; do
        [ -r "$f" ] || continue
        # Inventory-only procs need the all_server_* tables, which do not
        # exist yet on either instance at this point. On the inventory they are
        # applied later (after SCH-Create-Inventory-Specific-Objects.sql); on a
        # monitored instance they are never needed.
        if is_inventory_only_proc "$(basename "$f")"; then
            continue
        fi
        files+=("$f")
    done
    apply_glob "$server" "$INVENTORY_DATABASE" "stored procedures (${#files[@]} files)" \
        "${files[@]}" || warn "  some procs failed on [$server] (see above)"

    # Upstream's own grafana setup: the read-only login plus EXECUTE on the
    # reporting procs the inventory calls over the linked server. Without these
    # grants the Get-AllServer* jobs log "EXECUTE permission was denied on
    # usp_avg_disk_latency_ms" for every monitored instance.
    log "  DCL-[grafana-login].sql"
    apply_file "$server" master "${DDL_DIR}/DCL-[grafana-login].sql" \
        || warn "  grafana grants partially failed on [$server]"

    # DCL-[grafana-login].sql hardcodes the password 'grafana'; re-assert the
    # configured one so the linked servers keep working.
    sa "$server" master -Q "ALTER LOGIN [grafana] WITH PASSWORD = N'$(printf '%s' "$GRAFANA_PASSWORD" | sed "s/'/''/g")';" >/dev/null 2>&1 \
        || warn "  could not re-assert the grafana password on [$server]"

    install_optional_tools "$server"
    prime_collectors "$server"
}

# sp_WhoIsActive + First Responder Kit, then one run of each so their output
# tables (dbo.WhoIsActive, dbo.BlitzIndex*) actually exist for the inventory to
# read over the linked server.
install_optional_tools() {
    local server="$1" whoisactive
    [ "$INSTALL_OPTIONAL_TOOLS" = "1" ] || { log "  optional tools skipped (INSTALL_OPTIONAL_TOOLS=0)"; return 0; }

    whoisactive="$(ls -1 "${DDL_DIR}"/DDL-\[sp_WhoIsActive_v2200*\].sql 2>/dev/null | head -1)"
    [ -n "$whoisactive" ] || whoisactive="$(ls -1 "${DDL_DIR}"/DDL-\[sp_WhoIsActive_v*\].sql 2>/dev/null | tail -1)"

    if [ -n "$whoisactive" ]; then
        log "  sp_WhoIsActive ($(basename "$whoisactive"))"
        apply_file "$server" "$INVENTORY_DATABASE" "$whoisactive" || warn "    sp_WhoIsActive failed"
    fi

    # 2.2 MB of T-SQL; skip it when it is already there so a re-run of
    # `make bootstrap` takes seconds rather than minutes.
    local has_frk
    has_frk="$(sa "$server" "$INVENTORY_DATABASE" -h -1 -W -Q \
        "set nocount on; select case when object_id('dbo.sp_BlitzIndex') is null then 0 else 1 end;" 2>/dev/null | sed '/^$/d' | head -1)"
    if [ "$has_frk" = "1" ]; then
        log "  First Responder Kit already installed - skipping"
    else
        log "  First Responder Kit (2.2 MB, takes a minute)"
        apply_file "$server" "$INVENTORY_DATABASE" "${DDL_DIR}/FirstResponderKit-Install-All-Scripts.sql" \
            || warn "    First Responder Kit failed"
    fi

    # One run of each, so the output tables exist.
    # @recipients is mandatory: without it the proc does
    #   raiserror('@recipients is mandatory parameter', 20, -1)
    # which is fatal and kills the connection.
    if sa "$server" "$INVENTORY_DATABASE" -Q "EXEC dbo.usp_run_WhoIsActive @recipients = '${DBA_EMAIL}';" >/dev/null 2>&1; then
        log "    OK   usp_run_WhoIsActive"
    else
        log "    FAIL usp_run_WhoIsActive"
    fi
    # dbo.BlitzIndex plus the three per-mode tables the inventory reads.
    local spec
    for spec in "0|BlitzIndex" "0|BlitzIndex_Mode0" "1|BlitzIndex_Mode1" "4|BlitzIndex_Mode4"; do
        local mode="${spec%%|*}" tbl="${spec#*|}"
        sa "$server" "$INVENTORY_DATABASE" -Q "
if object_id('dbo.${tbl}') is null
    exec dbo.sp_BlitzIndex @Mode = ${mode}, @GetAllDatabases = 1, @OutputDatabaseName = '${INVENTORY_DATABASE}', @OutputSchemaName = 'dbo', @OutputTableName = '${tbl}';" \
            >/dev/null 2>&1 \
            && log "    OK   sp_BlitzIndex -> dbo.${tbl}" \
            || log "    FAIL sp_BlitzIndex -> dbo.${tbl}"
    done
}

# Three of the tables the inventory pulls over the linked server are created at
# RUNTIME by their collector proc, not by any DDL file:
#
#     dbo.tempdb_space_usage       <- dbo.usp_TempDbSaver
#     dbo.log_space_consumers      <- dbo.usp_LogSaver
#     dbo.sql_agent_job_thresholds <- dbo.usp_check_sql_agent_jobs
#
# On a real deployment the per-instance collection jobs create them within
# minutes. Nothing in the rig would, so the Get-AllServer* jobs would log
# "Invalid object name 'dbo.tempdb_space_usage'" forever.
#
# Each proc gets its OWN connection: several of these raise severity 20 when a
# mandatory parameter is missing, and a severity-20 raiserror terminates the
# connection - TRY/CATCH cannot contain it, so a single batch would silently
# skip every collector after the first strict one.
prime_collectors() {
    local server="$1" entry name cmd out rc
    log "  priming per-instance collectors"

    local collectors=(
        "usp_TempDbSaver|EXEC dbo.usp_TempDbSaver @data_used_pct_threshold = 0, @kill_spids = 0;"
        # Threshold 0 forces the "log is under pressure" path so the table is
        # created. That path then runs DBCC OPENTRAN ... WITH TABLERESULTS,
        # whose output does not match what the proc expects, so it reports
        # Msg 245. The table is created first, which is all the rig needs -
        # the inventory only fails if dbo.log_space_consumers is ABSENT.
        "usp_LogSaver|EXEC dbo.usp_LogSaver @log_used_pct_threshold = 0;"
        "usp_check_sql_agent_jobs|EXEC dbo.usp_check_sql_agent_jobs @default_mail_recipient = '${DBA_EMAIL}';"
        "usp_collect_wait_stats|EXEC dbo.usp_collect_wait_stats @recipients = '${DBA_EMAIL}';"
        "usp_collect_disk_space|EXEC dbo.usp_collect_disk_space;"
        "usp_collect_file_io_stats|EXEC dbo.usp_collect_file_io_stats @recipients = '${DBA_EMAIL}';"
        "usp_collect_memory_clerks|EXEC dbo.usp_collect_memory_clerks @recipients = '${DBA_EMAIL}';"
    )

    for entry in "${collectors[@]}"; do
        name="${entry%%|*}"
        cmd="${entry#*|}"
        rc=0
        out="$(sa "$server" "$INVENTORY_DATABASE" -Q "$cmd" 2>&1)" || rc=$?
        if [ "$rc" -eq 0 ]; then
            log "    OK   $name"
        else
            log "    FAIL $name: $(printf '%s' "$out" | grep -iE '^Msg|error' | head -1 | cut -c1-110)"
        fi
    done

    sa "$server" "$INVENTORY_DATABASE" -W -s'|' -Q "
set nocount on;
select [runtime_table]=convert(varchar(28),t.name), [rows]=p.row_count
from sys.tables t
join sys.dm_db_partition_stats p on p.object_id=t.object_id and p.index_id in (0,1)
where t.name in ('tempdb_space_usage','log_space_consumers','sql_agent_job_thresholds',
                 'wait_stats','disk_space','file_io_stats','memory_clerks')
order by t.name;" 2>/dev/null | sed '/^$/d;/rows affected/d' | sed 's/^/      /'
}

# --- main ------------------------------------------------------------------
log "REPO_ROOT=$REPO_ROOT  INVENTORY_SERVER=$INVENTORY_SERVER  MONITORED=$MONITORED_SERVERS"
[ -d "$DDL_DIR" ] || die "DDL directory '$DDL_DIR' not found - is the repo mounted at $REPO_ROOT?"

ALL_SERVERS="$INVENTORY_SERVER"
for s in $MONITORED_SERVERS; do ALL_SERVERS="$ALL_SERVERS $s"; done

for s in $ALL_SERVERS; do wait_for "$s"; done

bootstrap_instance "$INVENTORY_SERVER" 1
for s in $MONITORED_SERVERS; do bootstrap_instance "$s" 0; done

# --- inventory-only --------------------------------------------------------
log "=== [$INVENTORY_SERVER] inventory-only objects ==="

# credential_manager.sql creates its table unguarded, so let it continue.
apply_file "$INVENTORY_SERVER" "$INVENTORY_DATABASE" "${CM_DIR}/SCH-[dbo].[credential_manager].sql" 0
apply_glob "$INVENTORY_SERVER" "$INVENTORY_DATABASE" "Credential Manager procs" \
    "${CM_DIR}/SCH-[dbo].[usp_add_credential].sql" \
    "${CM_DIR}/SCH-[dbo].[usp_get_credential].sql" \
    "${CM_DIR}/SCH-[dbo].[usp_update_credential].sql" \
    "${CM_DIR}/SCH-[dbo].[usp_delete_credential].sql" \
    || warn "  Credential Manager partially failed"

log "  SCH-Create-Inventory-Specific-Objects.sql"
apply_file "$INVENTORY_SERVER" "$INVENTORY_DATABASE" \
    "${DDL_DIR}/SCH-Create-Inventory-Specific-Objects.sql" 0

# The script above is allowed to continue past errors, so verify the end state.
MISSING="$(sa "$INVENTORY_SERVER" "$INVENTORY_DATABASE" -h -1 -W -Q "
set nocount on;
select count(*) from (values ('all_server_stable_info'),('all_server_volatile_info'),
    ('all_server_collection_latency_info'),('sql_agent_jobs_all_servers'),
    ('disk_space_all_servers'),('log_space_consumers_all_servers'),
    ('tempdb_space_usage_all_servers'),('ag_health_state_all_servers'),
    ('services_all_servers'),('backups_all_servers'),('alert_history_all_servers')) t(n)
where object_id('dbo.'+t.n) is null;" 2>/dev/null | sed '/^$/d' | head -1)"
if [ "$MISSING" != "0" ]; then
    die "SCH-Create-Inventory-Specific-Objects.sql left $MISSING inventory table(s) missing. Drop and recreate the DBA database (make reset) and re-run."
fi
log "    all inventory tables present"

# The all_server_* tables now exist, so the inventory-only procs compile.
INV_PROC_FILES=()
for f in "${INVENTORY_ONLY_PROCS[@]}"; do
    [ -r "${DDL_DIR}/${f}" ] && INV_PROC_FILES+=("${DDL_DIR}/${f}")
done
apply_glob "$INVENTORY_SERVER" "$INVENTORY_DATABASE" \
    "inventory-only procs (${#INV_PROC_FILES[@]} files)" "${INV_PROC_FILES[@]}" \
    || die "inventory-only procs failed - the inventory jobs cannot work without them"

log "  02-inventory-seed.sql"
FIRST_MONITORED="$(printf '%s\n' $MONITORED_SERVERS | head -1)"
sa "$INVENTORY_SERVER" "$INVENTORY_DATABASE" \
    -v InventoryHost="$INVENTORY_SERVER" \
       MonitoredHost="$FIRST_MONITORED" \
       DbaEmail="$DBA_EMAIL" \
    -i "${SCRIPT_DIR}/02-inventory-seed.sql" \
    || die "02-inventory-seed.sql failed"

log "  03-linked-servers.sql"
for s in $MONITORED_SERVERS; do
    sa "$INVENTORY_SERVER" master \
        -v LinkedServer="$s" DataSource="${s},1433" \
           RemoteLogin=grafana RemotePassword="$GRAFANA_PASSWORD" \
           Catalog="$INVENTORY_DATABASE" \
        -i "${SCRIPT_DIR}/03-linked-servers.sql" \
        || die "03-linked-servers.sql failed for [$s]"
done

# --- verify ----------------------------------------------------------------
log "=== verification ==="
sa "$INVENTORY_SERVER" "$INVENTORY_DATABASE" -W -s'|' -Q "
SET NOCOUNT ON;
select [check]='tables in DBA',            [value]=convert(varchar(20),count(*)) from sys.tables
union all select 'all_server_* tables',    convert(varchar(20),count(*)) from sys.tables where name like 'all_server%'
union all select 'memory-optimized tables',convert(varchar(20),count(*)) from sys.tables where is_memory_optimized=1
union all select 'stored procedures',      convert(varchar(20),count(*)) from sys.procedures
union all select 'instance_details rows',  convert(varchar(20),count(*)) from dbo.instance_details
union all select 'linked servers',         convert(varchar(20),count(*)) from sys.servers where is_linked=1
union all select 'dba_team_email_id',      max(param_value) from dbo.sma_params where param_key='dba_team_email_id'
union all select 'host_platform',          max(convert(varchar(20),host_platform)) from sys.dm_os_host_info
union all select 'edition',                convert(varchar(40),SERVERPROPERTY('Edition'));
" 2>&1 | grep -vE '^$|rows affected|^-'

log 'Bootstrap complete. Next: make install'
