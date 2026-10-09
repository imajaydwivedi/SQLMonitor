#!/usr/bin/env bash
# update-sqlmonitor-ip.sh
#
# Linux replacement for Update-SQLMonitorIP.ps1 and the
# "(dba) Update-SQLMonitorIP" SQL Agent job.
#
# Checks whether the public Grafana host still answers on its port; if it does
# not, the box's public IP has probably rotated, so push the new one to No-IP
# dynamic DNS. The No-IP password comes from the Credential Manager on the
# inventory server, never from the command line.
#
# Test-NetConnection is replaced by bash's /dev/tcp, Invoke-RestMethod by curl.
#
# Usage:
#   update-sqlmonitor-ip.sh [--username U] [--hostname H] [--port N] [--verbose]

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/sqlmonitor.sh
. "${SCRIPT_DIR}/../lib/sqlmonitor.sh"

APP_NAME='(dba) Update-SQLMonitorIP'

while [ $# -gt 0 ]; do
    case "$1" in
        --username) NOIP_USERNAME="$2"; shift 2 ;;
        --hostname) NOIP_HOSTNAME="$2"; shift 2 ;;
        --port)     NOIP_CHECK_PORT="$2"; shift 2 ;;
        --verbose)  SQLMONITOR_VERBOSE=1; shift ;;
        -h|--help)  sed -n '2,16p' "$0"; exit 0 ;;
        *)          sm_die "Unknown argument '$1'." ;;
    esac
done

sm_init
sm_require curl

: "${NOIP_CHECK_PORT:=3000}"
[ -n "${NOIP_USERNAME:-}" ] || sm_die "NOIP_USERNAME is required (config file or --username)."
[ -n "${NOIP_HOSTNAME:-}" ] || sm_die "NOIP_HOSTNAME is required (config file or --hostname)."

sm_info "Test connectivity to '$NOIP_HOSTNAME' on port $NOIP_CHECK_PORT.."

is_ok=0
if timeout 10 bash -c "exec 3<>/dev/tcp/${NOIP_HOSTNAME}/${NOIP_CHECK_PORT}" 2>/dev/null; then
    is_ok=1
fi

if [ "$is_ok" -eq 1 ]; then
    sm_info "Connectivity to '$NOIP_HOSTNAME' on port $NOIP_CHECK_PORT is fine."
    exit 0
fi

sm_warn "Connectivity test failed; refreshing dynamic DNS."

sm_info "Fetch [$NOIP_USERNAME] password from Credential Manager [$INVENTORY_SERVER].[$CREDENTIAL_MANAGER_DATABASE].."
noip_password="$(sm_get_credential "$NOIP_USERNAME")"
[ -n "$noip_password" ] || sm_die "Credential Manager returned no password for '$NOIP_USERNAME'."

sm_info "Find out public ip of system.."
public_ip="$(curl --fail --silent --show-error --max-time 20 https://ipinfo.io/ip 2>/dev/null)"
if [ -z "$public_ip" ]; then
    public_ip="$(curl --fail --silent --show-error --max-time 20 https://api.ipify.org 2>/dev/null)"
fi
[ -n "$public_ip" ] || sm_die "Could not determine the public IP address."
sm_info "Ip => '$public_ip'"

sm_info "Calling the No-IP dynamic update endpoint for '$NOIP_HOSTNAME'.."
# Credentials go in the Authorization header via --user, not in the URL, so
# they never reach the process table or an access log.
status_code="$(curl --silent --show-error --max-time 30 \
    --user "${NOIP_USERNAME}:${noip_password}" \
    --user-agent 'SQLMonitor update-sqlmonitor-ip.sh' \
    --get \
    --data-urlencode "hostname=${NOIP_HOSTNAME}" \
    --data-urlencode "myip=${public_ip}" \
    --write-out '%{http_code}' \
    --output "${SQLMONITOR_WORK_DIR}/noip-response.txt" \
    'https://dynupdate.no-ip.com/nic/update')"

response="$(cat "${SQLMONITOR_WORK_DIR}/noip-response.txt" 2>/dev/null)"
rm -f "${SQLMONITOR_WORK_DIR}/noip-response.txt"

case "$response" in
    good*|nochg*)
        sm_info "Dynamic DNS Update went successful (http $status_code, '$response')."
        ;;
    *)
        err="Dynamic DNS Update failed with http status '$status_code' and response '$response'."
        sm_error "$err"
        sm_errorlog 'update-sqlmonitor-ip.sh' "$NOIP_HOSTNAME" \
            "$INVENTORY_SERVER" "$err" "$APP_NAME"
        exit 1
        ;;
esac
