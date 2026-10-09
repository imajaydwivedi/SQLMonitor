#!/usr/bin/env bash
# remove-inventory.sh
#
# Linux replacement for the inventory half of Remove-SQLMonitor.ps1.
#
# Stops and removes the systemd timers, drops the inventory SQL Agent jobs, and
# optionally removes the installed files, the config and the service account.
# The DBA database and its data are never touched - dropping those stays a
# deliberate manual act.
#
# Usage:
#   ./remove-inventory.sh [--purge-files] [--purge-config] [--purge-user]
#                         [--keep-jobs] [--dry-run] [--verbose]

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/sqlmonitor.sh
. "${SCRIPT_DIR}/lib/sqlmonitor.sh"

APP_NAME='remove-inventory.sh'
SERVICE_USER='sqlmonitor'
SYSTEMD_DIR='/etc/systemd/system'

PURGE_FILES=0
PURGE_CONFIG=0
PURGE_USER=0
KEEP_JOBS=0
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --purge-files)  PURGE_FILES=1; shift ;;
        --purge-config) PURGE_CONFIG=1; shift ;;
        --purge-user)   PURGE_USER=1; shift ;;
        --keep-jobs)    KEEP_JOBS=1; shift ;;
        --dry-run)      DRY_RUN=1; shift ;;
        --verbose)      SQLMONITOR_VERBOSE=1; shift ;;
        -h|--help)      sed -n '2,14p' "$0"; exit 0 ;;
        *)              sm_die "Unknown argument '$1'." ;;
    esac
done

sm_init
[ "$(id -u)" -eq 0 ] || sm_die "Run this as root."

run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        sm_info "  [dry-run] $*"
        return 0
    fi
    "$@"
}

# --- timers ----------------------------------------------------------------
sm_info 'Stopping and disabling SQLMonitor timers..'
while IFS= read -r unit; do
    [ -n "$unit" ] || continue
    sm_info "  $unit"
    run systemctl disable --now "$unit" >/dev/null 2>&1 || true
done < <(systemctl list-unit-files --no-pager --no-legend 'sqlmonitor-*.timer' 2>/dev/null | awk '{print $1}')

for f in "${SYSTEMD_DIR}"/sqlmonitor-*.timer "${SYSTEMD_DIR}/sqlmonitor@.service"; do
    [ -e "$f" ] || continue
    run rm -f "$f"
done
run systemctl daemon-reload

# --- SQL Agent jobs --------------------------------------------------------
if [ "$KEEP_JOBS" -eq 0 ]; then
    sm_info 'Dropping (dba) SQLMonitor inventory jobs..'
    INVENTORY_JOBS=(
        '(dba) Get-AllServerStableInfo'
        '(dba) Get-AllServerVolatileInfo'
        '(dba) Get-AllServerCollectionLatencyInfo'
        '(dba) Get-AllServerSqlAgentJobs'
        '(dba) Get-AllServerDiskSpace'
        '(dba) Get-AllServerLogSpaceConsumers'
        '(dba) Get-AllServerTempdbSpaceUsage'
        '(dba) Get-AllServerAgHealthState'
        '(dba) Get-AllServerServices'
        '(dba) Get-AllServerBackups'
        '(dba) Get-AllServerAlertHistory'
        '(dba) Get-AllServerDashboardMail'
        '(dba) Compute-AllServerVolatileInfoHistoryHourly'
        '(dba) Collect Login Expiration Info'
        '(dba) Send Login Expiry EMails'
        '(dba) Check-InstanceAvailability'
        '(dba) Update-SqlServerVersions'
        '(dba) Populate Inventory Tables'
        '(dba) Stop-StuckSQLMonitorJobs'
        '(dba) Update-SQLMonitorIP'
        '(dba) Collect-AllServerAlertMessages'
    )
    drop_sql=''
    for job in "${INVENTORY_JOBS[@]}"; do
        drop_sql+="
if exists (select * from msdb.dbo.sysjobs_view where name = N'$(sm_sql_escape "$job")')
begin
    print 'Dropping job [$(sm_sql_escape "$job")]';
    exec msdb.dbo.sp_delete_job @job_name = N'$(sm_sql_escape "$job")', @delete_unused_schedule = 1;
end
"
    done

    if [ "$DRY_RUN" -eq 1 ]; then
        sm_info '  [dry-run] would drop 21 inventory jobs.'
    else
        sm_inv_exec "$APP_NAME" "$drop_sql" msdb \
            || sm_warn 'Could not drop every inventory job; check the output above.'
    fi
else
    sm_info '--keep-jobs given; leaving SQL Agent jobs in place.'
fi

# --- files -----------------------------------------------------------------
if [ "$PURGE_FILES" -eq 1 ]; then
    sm_info "Removing '$SQLMONITOR_HOME', '$SQLMONITOR_WORK_DIR' and '$SQLMONITOR_LOG_DIR'.."
    for d in "$SQLMONITOR_HOME" "$SQLMONITOR_WORK_DIR" "$SQLMONITOR_LOG_DIR"; do
        case "$d" in
            /|/usr|/etc|/var|/opt|'') sm_die "Refusing to remove '$d'." ;;
        esac
        run rm -rf -- "$d"
    done
else
    sm_info "Leaving files under '$SQLMONITOR_HOME' (pass --purge-files to remove)."
fi

# --- config ----------------------------------------------------------------
if [ "$PURGE_CONFIG" -eq 1 ]; then
    sm_info "Removing '$SQLMONITOR_CONF' and /etc/sqlmonitor.."
    run rm -rf -- /etc/sqlmonitor
else
    sm_info "Leaving '$SQLMONITOR_CONF' (pass --purge-config to remove)."
fi

# --- service account -------------------------------------------------------
if [ "$PURGE_USER" -eq 1 ]; then
    if id -u "$SERVICE_USER" >/dev/null 2>&1; then
        sm_info "Removing service user '$SERVICE_USER'.."
        run userdel "$SERVICE_USER" || sm_warn "Could not remove user '$SERVICE_USER'."
    fi
else
    sm_info "Leaving service user '$SERVICE_USER' (pass --purge-user to remove)."
fi

sm_info 'Inventory removal complete. The DBA database was not touched.'
