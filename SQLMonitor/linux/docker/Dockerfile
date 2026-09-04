# sqlmonitor-tools - the deployable image for the Linux inventory lane.
#
# One image serves three roles in Kubernetes, because they all need the same
# things (sqlcmd, bash 4.3+, the DDLs, the bin/*.sh scripts):
#
#   1. the bootstrap Job     - creates DBA, applies the DDLs, seeds, and runs
#                              install-inventory.sh to create the Agent jobs
#   2. the CronJobs          - the five schedulable inventory tasks
#   3. the alerts Deployment - the one task that runs every 10s, which a
#                              CronJob cannot express (its floor is 1 minute)
#
# Built FROM the SQL Server image so sqlcmd is exactly the version the server
# ships, and no separate mssql-tools download is needed at build time.
#
# Layout mirrors a real host install, so no script needs special-casing:
#   /opt/sqlmonitor-src   the repo (what you would `git clone`)
#   /opt/sqlmonitor       where install-inventory.sh installs the runtime copy
#
# Build FROM THE REPO ROOT, so DDLs/ and Credential-Manager/ are in context:
#   docker build -f SQLMonitor/linux/docker/Dockerfile \
#                -t <registry>/sqlmonitor-tools:<tag> .

ARG MSSQL_IMAGE=mcr.microsoft.com/mssql/server:2022-latest
FROM ${MSSQL_IMAGE}

USER root
ARG DEBIAN_FRONTEND=noninteractive

# curl is required by sqlserver-versions-update.sh and update-sqlmonitor-ip.sh.
# ping/dig are optional fallbacks in get-host-ip-addresses.sh (getent, already
# present, is the primary path), so the build tolerates their absence.
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates \
 && (apt-get install -y --no-install-recommends iputils-ping dnsutils || \
     echo 'WARNING: ping/dig unavailable - get-host-ip-addresses.sh will use getent only') \
 # collect_all_server_alert_messages.py and check-instance-availability.py
 # import pyodbc and prettytable. The base image ships python3 but no pip and
 # neither package. Versions match Alerting/requirements.txt.
 && apt-get install -y --no-install-recommends python3-pip \
 && (pip3 install --no-cache-dir --break-system-packages 'pyodbc==5.2.0' 'prettytable==3.12.0' \
     || pip3 install --no-cache-dir 'pyodbc==5.2.0' 'prettytable==3.12.0') \
 && rm -rf /var/lib/apt/lists/*

ENV PATH="/opt/mssql-tools18/bin:${PATH}" \
    SQLCMD=/opt/mssql-tools18/bin/sqlcmd \
    SQLMONITOR_SRC=/opt/sqlmonitor-src \
    SQLMONITOR_HOME=/opt/sqlmonitor \
    SQLMONITOR_CONF=/etc/sqlmonitor/inventory.conf \
    SQLMONITOR_WORK_DIR=/var/opt/sqlmonitor/work \
    SQLMONITOR_LOG_DIR=/var/log/sqlmonitor

RUN if ! id -u sqlmonitor >/dev/null 2>&1; then \
        useradd --system --no-create-home --shell /usr/sbin/nologin sqlmonitor; \
    fi \
 && install -d -o root -g sqlmonitor -m 0750 /etc/sqlmonitor /opt/sqlmonitor \
 && install -d -o root -g sqlmonitor -m 0770 /var/opt/sqlmonitor/work /var/log/sqlmonitor

# --- the repo, laid out exactly as a checkout ------------------------------
# install-inventory.sh derives REPO_ROOT as ${SCRIPT_DIR}/../.., so it must sit
# at <root>/SQLMonitor/linux/ for DDLs/ to resolve.
COPY --chown=root:sqlmonitor DDLs/               /opt/sqlmonitor-src/DDLs/
COPY --chown=root:sqlmonitor Credential-Manager/ /opt/sqlmonitor-src/Credential-Manager/
COPY --chown=root:sqlmonitor SQLMonitor/linux/   /opt/sqlmonitor-src/SQLMonitor/linux/
COPY --chown=root:sqlmonitor SQLMonitor/collect_all_server_alert_messages.py \
                             SQLMonitor/check-instance-availability.py \
                             /opt/sqlmonitor-src/SQLMonitor/

# The test rig is a developer convenience, not part of the deployable image.
RUN rm -rf /opt/sqlmonitor-src/SQLMonitor/linux/test \
 && chmod 0755 /opt/sqlmonitor-src/SQLMonitor/linux/bin/*.sh \
               /opt/sqlmonitor-src/SQLMonitor/linux/install-inventory.sh \
               /opt/sqlmonitor-src/SQLMonitor/linux/remove-inventory.sh

WORKDIR /opt/sqlmonitor-src/SQLMonitor/linux

# Runs as root: install-inventory.sh needs it to create the service account and
# lay files into /opt/sqlmonitor. The CronJobs override this to run as
# sqlmonitor, since they only need to read config and talk to SQL Server.
USER root
ENTRYPOINT []
CMD ["/bin/bash", "-c", "echo 'sqlmonitor-tools: pass a command, e.g. ./install-inventory.sh --dry-run or /opt/sqlmonitor/bin/<task>.sh'; sleep infinity"]
