#!/usr/bin/env bash
# install-inventory.sh
#
# Install the SQLMonitor inventory server on SQL Server on Linux.
#
# This is the Linux replacement for the inventory half of Install-SQLMonitor.ps1
# (steps 33-51 and 57). It exists as a separate installer, rather than a Linux
# branch inside the PowerShell one, because the two lanes genuinely differ:
# SQL Agent on Linux has no CmdExec or PowerShell subsystem, so a third of the
# inventory jobs cannot be SQL Agent jobs at all and become systemd timers.
#
# Run it ON the inventory host, as root.
#
# Steps (all run by default; pick with --only / --skip):
#   1  preflight              connectivity, platform, SQL Agent, tooling
#   2  service-account        create the 'sqlmonitor' system user and dirs
#   3  files                  copy bin/, lib/, DDLs/ and the python collectors
#   4  config                 install /etc/sqlmonitor/inventory.conf
#   5  inventory-objects      DDLs/SCH-Create-Inventory-Specific-Objects.sql
#   6  drop-legacy-jobs       DDLs/SCH-Drop-Inventory-CmdExec-Jobs.sql
#   7  agent-jobs             the T-SQL-subsystem (dba) Get-AllServer* jobs
#   8  systemd                install and enable the timers
#   9  verify                 assert nothing is left on CmdExec/PowerShell
#
# Usage:
#   ./install-inventory.sh [--conf FILE] [--only STEP,STEP] [--skip STEP,STEP]
#                          [--dry-run] [--verbose]

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=lib/sqlmonitor.sh
. "${SCRIPT_DIR}/lib/sqlmonitor.sh"

APP_NAME='install-inventory.sh'
SERVICE_USER='sqlmonitor'
SYSTEMD_DIR='/etc/systemd/system'

ALL_STEPS=(preflight service-account files config inventory-objects
           drop-legacy-jobs agent-jobs systemd verify)

ONLY=''
SKIP=''
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --conf)    SQLMONITOR_CONF="$2"; shift 2 ;;
        --only)    ONLY="$2"; shift 2 ;;
        --skip)    SKIP="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        --verbose) SQLMONITOR_VERBOSE=1; shift ;;
        -h|--help) sed -n '2,29p' "$0"; exit 0 ;;
        *)         sm_die "Unknown argument '$1'." ;;
    esac
done

sm_init

# Reject typos in --only/--skip rather than silently running everything or
# nothing.
validate_steps() {
    local list="$1" label="$2" step known
    [ -n "$list" ] || return 0
    IFS=',' read -r -a _requested <<< "$list"
    for step in "${_requested[@]}"; do
        [ -n "$step" ] || continue
        known=0
        for candidate in "${ALL_STEPS[@]}"; do
            [ "$step" = "$candidate" ] && { known=1; break; }
        done
        [ "$known" -eq 1 ] || sm_die "$label: unknown step '$step'. Known steps: ${ALL_STEPS[*]}"
    done
}
validate_steps "$ONLY" '--only'
validate_steps "$SKIP" '--skip'

should_run() {
    local step="$1"
    if [ -n "$ONLY" ]; then
        [[ ",${ONLY}," == *",${step},"* ]] || return 1
    fi
    if [ -n "$SKIP" ]; then
        [[ ",${SKIP}," == *",${step},"* ]] && return 1
    fi
    return 0
}

run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        sm_info "  [dry-run] $*"
        return 0
    fi
    "$@"
}

apply_sql_file() {
    local file="$1" database="${2:-$INVENTORY_DATABASE}"
    [ -r "$file" ] || sm_die "SQL file '$file' is not readable."

    if [ "$DRY_RUN" -eq 1 ]; then
        sm_info "  [dry-run] apply '$(basename "$file")' to [$INVENTORY_SERVER].[$database]"
        return 0
    fi

    local -a args=(
        -S "$INVENTORY_SERVER" -d "$database" -C -b
        -l "$SQLMONITOR_LOGIN_TIMEOUT" -t "$SQLMONITOR_QUERY_TIMEOUT"
        -H "$APP_NAME" -i "$file"
    )
    if [ -n "$INVENTORY_LOGIN" ]; then args+=(-U "$INVENTORY_LOGIN"); else args+=(-E); fi

    sm_info "  apply $(basename "$file") -> [$database]"
    SQLCMDPASSWORD="$INVENTORY_PASSWORD" "$SQLCMD" "${args[@]}" \
        || sm_die "Applying '$file' failed."
}

# ---------------------------------------------------------------------------
# 1. preflight
# ---------------------------------------------------------------------------
if should_run preflight; then
    sm_info '=== Step 1/9: preflight ==='

    if [ "${BASH_VERSINFO[0]}" -lt 4 ] \
       || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 3 ]; }; then
        sm_die "bash 4.3 or newer is required (found ${BASH_VERSION})."
    fi
    [ "$(id -u)" -eq 0 ] || sm_die "Run this installer as root."
    sm_require systemctl install id

    platform="$(sm_inv_scalar "$APP_NAME" \
        "select convert(varchar(50), SERVERPROPERTY('HostPlatform'));" master)" \
        || sm_die "Cannot connect to [$INVENTORY_SERVER]. Check INVENTORY_LOGIN / INVENTORY_PASSWORD_FILE in '$SQLMONITOR_CONF'."

    sm_info "  inventory instance [$INVENTORY_SERVER] host platform: ${platform:-unknown}"
    if [ "$platform" != 'Linux' ]; then
        sm_die "This installer targets SQL Server on Linux; [$INVENTORY_SERVER] reports '${platform:-unknown}'. Use Install-SQLMonitor.ps1 for a Windows inventory server."
    fi

    # sys.dm_server_services needs VIEW SERVER STATE and is not guaranteed to
    # report Agent on every build, so only a definitive "0" is fatal.
    agent_running="$(sm_inv_scalar "$APP_NAME" \
        "select case when exists (select * from sys.dm_server_services where servicename like 'SQL Server Agent%' and status_desc = 'Running') then 1 else 0 end;" master 2>/dev/null)"
    case "$agent_running" in
        1) sm_info '  SQL Server Agent is running.' ;;
        0) sm_die "SQL Server Agent is not running. Enable it with: sudo /opt/mssql/bin/mssql-conf set sqlagent.enabled true && sudo systemctl restart mssql-server" ;;
        *) sm_warn '  could not determine SQL Server Agent status; continuing.' ;;
    esac

    db_exists="$(sm_inv_scalar "$APP_NAME" \
        "select case when db_id('$(sm_sql_escape "$INVENTORY_DATABASE")') is null then 0 else 1 end;" master)"
    [ "$db_exists" = '1' ] || sm_die "Database [$INVENTORY_DATABASE] does not exist on [$INVENTORY_SERVER]."
    sm_info "  database [$INVENTORY_DATABASE] is present."
fi

# ---------------------------------------------------------------------------
# 2. service-account
# ---------------------------------------------------------------------------
if should_run service-account; then
    sm_info '=== Step 2/9: service account and directories ==='

    if id -u "$SERVICE_USER" >/dev/null 2>&1; then
        sm_info "  user '$SERVICE_USER' already exists."
    else
        nologin_shell=/usr/sbin/nologin
        [ -x "$nologin_shell" ] || nologin_shell=/sbin/nologin
        [ -x "$nologin_shell" ] || nologin_shell=/bin/false
        sm_info "  creating system user '$SERVICE_USER' (shell $nologin_shell)."
        run useradd --system --no-create-home --shell "$nologin_shell" "$SERVICE_USER" \
            || sm_die "Could not create user '$SERVICE_USER'."
    fi

    for d in "$SQLMONITOR_HOME" "$SQLMONITOR_WORK_DIR" "$SQLMONITOR_LOG_DIR" /etc/sqlmonitor; do
        run install -d -o root -g "$SERVICE_USER" -m 0750 "$d"
    done
    run chown -R "root:${SERVICE_USER}" "$SQLMONITOR_WORK_DIR" "$SQLMONITOR_LOG_DIR"
    run chmod 0770 "$SQLMONITOR_WORK_DIR" "$SQLMONITOR_LOG_DIR"
fi

# ---------------------------------------------------------------------------
# 3. files
# ---------------------------------------------------------------------------
if should_run files; then
    sm_info '=== Step 3/9: files ==='

    run install -d -o root -g "$SERVICE_USER" -m 0750 \
        "${SQLMONITOR_HOME}/bin" "${SQLMONITOR_HOME}/lib" "${SQLMONITOR_HOME}/DDLs"

    for f in "${SCRIPT_DIR}"/bin/*.sh; do
        run install -o root -g "$SERVICE_USER" -m 0750 "$f" "${SQLMONITOR_HOME}/bin/"
    done
    run install -o root -g "$SERVICE_USER" -m 0640 \
        "${SCRIPT_DIR}/lib/sqlmonitor.sh" "${SQLMONITOR_HOME}/lib/"

    # DDLs the runtime scripts reference by path.
    run install -o root -g "$SERVICE_USER" -m 0640 \
        "${REPO_ROOT}/DDLs/QRY-UPDATE-[SQLAgentJobsThreshold].sql" "${SQLMONITOR_HOME}/DDLs/"

    # Python collectors that stayed python.
    for f in collect_all_server_alert_messages.py check-instance-availability.py; do
        if [ -f "${REPO_ROOT}/SQLMonitor/${f}" ]; then
            run install -o root -g "$SERVICE_USER" -m 0640 \
                "${REPO_ROOT}/SQLMonitor/${f}" "${SQLMONITOR_HOME}/"
        fi
    done

    sm_info "  installed into '$SQLMONITOR_HOME'."
fi

# ---------------------------------------------------------------------------
# 4. config
# ---------------------------------------------------------------------------
if should_run config; then
    sm_info '=== Step 4/9: configuration ==='

    if [ -f "$SQLMONITOR_CONF" ]; then
        sm_info "  '$SQLMONITOR_CONF' already exists - left untouched."
    else
        run install -o root -g "$SERVICE_USER" -m 0640 \
            "${SCRIPT_DIR}/sqlmonitor-inventory.conf.sample" "$SQLMONITOR_CONF"
        sm_warn "  wrote a template to '$SQLMONITOR_CONF'. Edit it before enabling the timers."
    fi

    if [ -n "$INVENTORY_PASSWORD_FILE" ] && [ -f "$INVENTORY_PASSWORD_FILE" ]; then
        run chown "root:${SERVICE_USER}" "$INVENTORY_PASSWORD_FILE"
        run chmod 0640 "$INVENTORY_PASSWORD_FILE"
    fi
fi

# ---------------------------------------------------------------------------
# 5. inventory-objects
# ---------------------------------------------------------------------------
if should_run inventory-objects; then
    sm_info '=== Step 5/9: inventory database objects ==='
    apply_sql_file "${REPO_ROOT}/DDLs/SCH-Create-Inventory-Specific-Objects.sql" "$INVENTORY_DATABASE"
fi

# ---------------------------------------------------------------------------
# 6. drop-legacy-jobs
# ---------------------------------------------------------------------------
if should_run drop-legacy-jobs; then
    sm_info '=== Step 6/9: drop CmdExec/PowerShell inventory jobs ==='
    apply_sql_file "${REPO_ROOT}/DDLs/SCH-Drop-Inventory-CmdExec-Jobs.sql" msdb
fi

# ---------------------------------------------------------------------------
# 7. agent-jobs
# ---------------------------------------------------------------------------
INVENTORY_JOB_FILES=(
    "SCH-Job-[(dba) Get-AllServerStableInfo].sql"
    "SCH-Job-[(dba) Get-AllServerVolatileInfo].sql"
    "SCH-Job-[(dba) Get-AllServerCollectionLatencyInfo].sql"
    "SCH-Job-[(dba) Get-AllServerSqlAgentJobs].sql"
    "SCH-Job-[(dba) Get-AllServerDiskSpace].sql"
    "SCH-Job-[(dba) Get-AllServerLogSpaceConsumers].sql"
    "SCH-Job-[(dba) Get-AllServerTempdbSpaceUsage].sql"
    "SCH-Job-[(dba) Get-AllServerAgHealthState].sql"
    "SCH-Job-[(dba) Get-AllServerServices].sql"
    "SCH-Job-[(dba) Get-AllServerBackups].sql"
    "SCH-Job-[(dba) Get-AllServerAlertHistory].sql"
    "SCH-Job-[(dba) Get-AllServerDashboardMail].sql"
    "SCH-Job-[(dba) Compute-AllServerVolatileInfoHistoryHourly].sql"
    "SCH-Job-[(dba) Collect Login Expiration Info].sql"
    "SCH-Job-[(dba) Send Login Expiry EMails].sql"
)

if should_run agent-jobs; then
    sm_info '=== Step 7/9: inventory SQL Agent jobs (TSQL subsystem) ==='
    for job in "${INVENTORY_JOB_FILES[@]}"; do
        apply_sql_file "${REPO_ROOT}/DDLs/${job}" msdb
    done
fi

# ---------------------------------------------------------------------------
# 8. systemd
# ---------------------------------------------------------------------------
if should_run systemd; then
    sm_info '=== Step 8/9: systemd units ==='

    run install -o root -g root -m 0644 "${SCRIPT_DIR}/systemd/sqlmonitor@.service" "${SYSTEMD_DIR}/"
    for timer in "${SCRIPT_DIR}"/systemd/*.timer; do
        run install -o root -g root -m 0644 "$timer" "${SYSTEMD_DIR}/"
    done
    run systemctl daemon-reload

    # update-sqlmonitor-ip is opt-in: it only makes sense with No-IP configured.
    for timer in sqlmonitor-check-instance-availability \
                 sqlmonitor-sqlserver-versions-update \
                 sqlmonitor-populate-inventory-tables \
                 sqlmonitor-stop-stuck-sqlmonitor-jobs \
                 sqlmonitor-collect-all-server-alert-messages; do
        run systemctl enable --now "${timer}.timer" \
            || sm_warn "  could not enable ${timer}.timer"
    done

    if [ -n "${NOIP_USERNAME:-}" ] && [ -n "${NOIP_HOSTNAME:-}" ]; then
        run systemctl enable --now sqlmonitor-update-sqlmonitor-ip.timer \
            || sm_warn '  could not enable sqlmonitor-update-sqlmonitor-ip.timer'
    else
        sm_info '  NOIP_USERNAME/NOIP_HOSTNAME not set - leaving sqlmonitor-update-sqlmonitor-ip.timer disabled.'
    fi
fi

# ---------------------------------------------------------------------------
# 9. verify
# ---------------------------------------------------------------------------
if should_run verify; then
    sm_info '=== Step 9/9: verify ==='

    if [ "$DRY_RUN" -eq 1 ]; then
        sm_info '  [dry-run] skipping verification.'
        exit 0
    fi

    bad="$(sm_inv_scalar "$APP_NAME" "select count(*)
from msdb.dbo.sysjobs j
join msdb.dbo.sysjobsteps s on s.job_id = j.job_id
join msdb.dbo.syscategories c on c.category_id = j.category_id
where c.name = N'(dba) SQLMonitor' and s.subsystem in (N'CmdExec', N'PowerShell');" msdb)"

    if [ "$bad" != '0' ]; then
        sm_error "  $bad (dba) SQLMonitor job step(s) still use CmdExec/PowerShell and will never run on Linux."
        sm_error "  Run DDLs/SCH-Drop-Inventory-CmdExec-Jobs.sql to see which."
        exit 1
    fi
    sm_info '  no CmdExec/PowerShell job steps remain.'

    sm_info '  active timers:'
    systemctl list-timers --no-pager 'sqlmonitor-*' 2>/dev/null | sed 's/^/    /'

    sm_info 'Inventory server installed. Next: create the linked servers with'
    sm_info "  DDLs/SCH-Linked-Servers-Sample-Linux.sql (one per monitored instance)."
fi
