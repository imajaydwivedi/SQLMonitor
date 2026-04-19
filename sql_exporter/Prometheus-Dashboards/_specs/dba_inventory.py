"""Spec for ``DBA Inventory`` Prometheus port (UID: prom_dba_inventory).

Source dashboard ``DBA Inventory.json`` has 10 data panels, all driven
off the SQLMonitor inventory schema (dbo.servers, dbo.sql_instances,
dbo.sql_cluster_nodes, etc). That schema is *not* exposed to
Prometheus — those tables are live in SQL Server and the exporter does
not publish row-level inventory rows.

Strategy:
  • Panels that *can* be rebuilt from the `mssql_up`, `mssql_service_info`,
    and `mssql_aghealth__*` metrics are implemented as stat/table panels.
  • The rest link back to the original SQL dashboard with
    ``legacy_link_panel`` so the Prometheus dashboard still lists every
    source section and does not pretend inventory data has been ported.
"""
from prom_dashboard import (
    Panel, Target, query_var, legacy_link_panel,
)


UID = "prom_dba_inventory"
TITLE = "DBA Inventory"
TAGS = ["mssql", "sqlmonitor", "Inventory", "prometheus"]


_LEGACY_UID = "dba-inventory"


def variables():
    return [
        query_var("Server", "label_values(mssql_up, instance)",
                  label="SQL Instance", multi=True, include_all=True),
    ]


def panels():
    ps: list[Panel] = []

    # Summary row — real Prometheus data
    ps.append(Panel(
        title="SQL Instances - Online",
        description="Count of SQL Server targets currently scraping "
                     "successfully (mssql_up == 1).",
        type="stat", unit="short",
        grid=(0, 0, 6, 4),
        thresholds_steps=[{"color": "red", "value": None},
                            {"color": "green", "value": 1}],
        targets=[Target('sum(mssql_up == 1)', legend="", ref="A",
                        instant=True)],
    ))
    ps.append(Panel(
        title="SQL Instances - Offline",
        description="Count of SQL Server targets with mssql_up == 0.",
        type="stat", unit="short",
        grid=(6, 0, 6, 4),
        thresholds_steps=[{"color": "green", "value": None},
                            {"color": "red", "value": 1}],
        targets=[Target('sum(mssql_up == 0)', legend="", ref="A",
                        instant=True)],
    ))
    ps.append(Panel(
        title="Availability Groups",
        description="Distinct AG names observed across scrape targets.",
        type="stat", unit="short",
        grid=(12, 0, 6, 4),
        targets=[Target(
            'count(count by (ag_name) (mssql_aghealth__synchronization_health))',
            legend="", ref="A", instant=True)],
    ))
    ps.append(Panel(
        title="Hosts",
        description="Distinct hostnames observed via mssql_service_info.",
        type="stat", unit="short",
        grid=(18, 0, 6, 4),
        targets=[Target(
            'count(count by (host_name) (mssql_service_info))',
            legend="", ref="A", instant=True)],
    ))

    # Combined Info table (instance-level)
    ps.append(Panel(
        title="SQL Servers - Combined Info - FILTERED",
        description=("Per-instance combined info from mssql_service_info "
                     "(host/service/product) and mssql_up for online state."),
        type="table", unit="short",
        grid=(0, 4, 24, 9),
        targets=[
            Target('mssql_service_info{instance=~"$Server"}',
                   legend="", ref="Info", instant=True, format="table"),
            Target('mssql_up{instance=~"$Server"}',
                   legend="", ref="Up", instant=True, format="table"),
        ],
        transformations=[
            {"id": "merge", "options": {}},
            {"id": "organize", "options": {
                "excludeByName": {"Time": True, "__name__": True,
                                    "job": True, "target": True,
                                    "exported_job": True},
                "renameByName": {
                    "instance": "Server",
                    "host_name": "Host",
                    "product_version": "Version",
                    "service_name": "Service",
                    "Value #Info": "Info",
                    "Value #Up":   "Up?",
                },
            }},
        ],
    ))

    # SQL Instance Details → inventory-only (legacy link)
    ps.append(legacy_link_panel(
        "SQLMonitor - Instance Details - FILTERED",
        grid=(0, 13, 24, 7),
        sql_dashboard=_LEGACY_UID,
        note="Inventory-DB columns (alias, linked-server-name, "
             "major/minor version breakdown) are not exposed to "
             "Prometheus. Use the SQL dashboard for the full detail row.",
    ))

    # All Servers - Basic Info → inventory
    ps.append(legacy_link_panel(
        "All Servers - Basic Info",
        grid=(0, 20, 24, 7),
        sql_dashboard=_LEGACY_UID,
        note="dbo.vw_all_servers_basic_info (SMA agents, OS hosts, "
             "service accounts) is not mirrored in Prometheus.",
    ))

    # SQL Servers - Extended Info → inventory
    ps.append(legacy_link_panel(
        "SQL Servers - Extended Info",
        grid=(0, 27, 24, 7),
        sql_dashboard=_LEGACY_UID,
        note="SKU / license / feature matrix — inventory table.",
    ))

    # SQL Server Hosts → inventory
    ps.append(legacy_link_panel(
        "SQL Server Hosts",
        grid=(0, 34, 24, 7),
        sql_dashboard=_LEGACY_UID,
        note="Host-level inventory (IP/FQDN/domain) is only in the "
             "SQLMonitor inventory DB.",
    ))

    # SQL Server Availability Groups
    ps.append(Panel(
        title="SQL Server Availability Groups - Online",
        description=("Per-AG replica count and distinct databases, "
                     "derived from mssql_aghealth__synchronization_health "
                     "labels."),
        type="table", unit="short",
        grid=(0, 41, 24, 9),
        targets=[
            Target(
                'count by (ag_name, ag_listener) '
                '(mssql_aghealth__synchronization_health{instance=~"$Server"})',
                legend="", ref="Replicas", instant=True, format="table"),
            Target(
                'count by (ag_name, database_name) '
                '(mssql_aghealth__synchronization_health{instance=~"$Server"})',
                legend="", ref="Dbs", instant=True, format="table"),
        ],
        transformations=[
            {"id": "merge", "options": {}},
        ],
    ))

    # SQL Clusters → legacy (no cluster-topology metrics)
    ps.append(legacy_link_panel(
        "SQL Clusters",
        grid=(0, 50, 24, 8),
        sql_dashboard=_LEGACY_UID,
        note="WSFC node / resource-group ownership is inventory-only.",
    ))

    # Login Expiry → inventory
    ps.append(legacy_link_panel(
        "SQL Servers - Login Expiry",
        grid=(0, 58, 24, 8),
        sql_dashboard=_LEGACY_UID,
        note="Login-expiry warnings come from the security-collection "
             "SQL Agent job and are stored in the inventory DB.",
    ))

    # Login Email Mapping → inventory
    ps.append(legacy_link_panel(
        "Login Email Mapping",
        grid=(0, 66, 24, 8),
        sql_dashboard=_LEGACY_UID,
        note="dbo.login_email_mapping is an inventory-only lookup table.",
    ))

    # Config Changes → inventory/lama
    ps.append(legacy_link_panel(
        "Config Changes",
        grid=(0, 74, 24, 8),
        sql_dashboard=_LEGACY_UID,
        note="LAMA (Look-At-My-Analysis) config-change deltas come from "
             "dbo.lama_computed_metrics — not exposed to Prometheus.",
    ))

    return ps
