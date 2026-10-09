# The "inventory host" for the test rig.
#
# In production the bash scripts run on the Linux box hosting the inventory SQL
# Server, driven by systemd timers. A container has no systemd, so this image
# supplies the same userland and run-timers.sh stands in for the timers.
#
# It is built FROM the SQL Server image on purpose:
#   * that image is already pulled by the compose stack, so there is no second
#     multi-hundred-MB download and no dependency on packages.microsoft.com
#     being fast the day someone runs `make up`;
#   * it already ships /opt/mssql-tools18/bin/sqlcmd, so the client is exactly
#     the version the server was built with;
#   * it already has bash 5.1, coreutils (timeout), getent, useradd and python3.
#
# Only curl, ping and dig are missing, and those come from the Ubuntu archive.
ARG MSSQL_IMAGE=mcr.microsoft.com/mssql/server:2022-latest
FROM ${MSSQL_IMAGE}

USER root
ARG DEBIAN_FRONTEND=noninteractive

# curl is required by sqlserver-versions-update.sh and update-sqlmonitor-ip.sh.
# ping/dig are optional fallbacks in get-host-ip-addresses.sh (getent, already
# present, is the primary path) - so the build tolerates them being unavailable.
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates \
 && (apt-get install -y --no-install-recommends iputils-ping dnsutils || \
     echo 'WARNING: ping/dig unavailable - get-host-ip-addresses.sh will use getent only') \
 && rm -rf /var/lib/apt/lists/*

ENV PATH="/opt/mssql-tools18/bin:${PATH}" \
    SQLCMD=/opt/mssql-tools18/bin/sqlcmd \
    SQLMONITOR_CONF=/etc/sqlmonitor/inventory.conf

# install-inventory.sh creates this user itself; pre-creating it keeps
# `make bootstrap` usable before `make install` has run.
RUN if ! id -u sqlmonitor >/dev/null 2>&1; then \
        useradd --system --no-create-home --shell /usr/sbin/nologin sqlmonitor; \
    fi \
 && install -d -o root -g sqlmonitor -m 0750 /etc/sqlmonitor \
 && install -d -o root -g sqlmonitor -m 0770 /var/opt/sqlmonitor/work /var/log/sqlmonitor

WORKDIR /repo
SHELL ["/bin/bash", "-c"]
ENTRYPOINT []
CMD ["sleep", "infinity"]
