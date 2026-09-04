# SQLMonitor Linux inventory - local test workspace.
#
#   make up          start the SQL Server instances and the tools container
#   make bootstrap   create DBA, apply the DDLs, seed inventory, link servers
#   make install     run SQLMonitor/linux/install-inventory.sh against it
#   make verify      prove the inventory is actually collecting
#   make timers      run the six timer-driven tasks on their schedules
#   make reset       destroy everything including the data volumes
#
# `make all` does up -> bootstrap -> install -> verify.

SHELL     := /bin/bash
COMPOSE   := docker compose
TOOLS     := $(COMPOSE) exec -T tools
# `docker compose exec` does not run a shell, so anything needing the
# container's env (SA_PASSWORD, INVENTORY_SERVER) must go through bash -c.
TOOLSH    := $(COMPOSE) exec -T tools bash -c
INVENTORY := sqlmonitor-inventory
LINUX_DIR := /repo/SQLMonitor/linux
SQLCMD    := /opt/mssql-tools18/bin/sqlcmd

# Loaded so recipes can reach SA_PASSWORD etc. without re-declaring them.
ifneq (,$(wildcard ./.env))
include .env
export
endif

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@awk 'BEGIN{FS=":.*##"; printf "\nTargets:\n"} /^[a-zA-Z_-]+:.*?##/ {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""

# ---------------------------------------------------------------- lifecycle --
.PHONY: env
env:
	@test -f .env || { \
	  echo "No .env found. Creating one from .env.example - review it, then re-run."; \
	  cp .env.example .env; exit 1; }

.PHONY: up
up: env ## Start SQL Server instances + tools, wait until healthy
	$(COMPOSE) up -d --build
	@echo "Waiting for containers to report healthy.."
	@for i in $$(seq 1 60); do \
	  st=$$($(COMPOSE) ps --format '{{.Service}} {{.Health}}' 2>/dev/null | grep -E 'inventory|monitored' || true); \
	  echo "$$st" | grep -q 'starting' || { echo "$$st"; break; }; \
	  sleep 5; \
	done
	@$(COMPOSE) ps

.PHONY: down
down: ## Stop containers, keep data volumes
	$(COMPOSE) down

.PHONY: reset
reset: ## Stop containers AND delete data volumes (full clean slate)
	$(COMPOSE) down -v --remove-orphans

.PHONY: ps
ps: ## Show container status
	@$(COMPOSE) ps

.PHONY: logs
logs: ## Tail SQL Server error logs
	$(COMPOSE) logs -f --tail=100 inventory monitored1

# ----------------------------------------------------------------- bootstrap --
.PHONY: bootstrap
bootstrap: ## Create DBA, apply DDLs, seed inventory, create linked servers
	$(TOOLS) bash $(LINUX_DIR)/test/bootstrap/bootstrap.sh

.PHONY: install
install: ## Run install-inventory.sh (systemd step skipped - no systemd in a container)
	$(TOOLS) bash -c 'install -d -m 0750 /etc/sqlmonitor && \
	  sed -e "s|^INVENTORY_SERVER=.*|INVENTORY_SERVER=$$INVENTORY_SERVER|" \
	      -e "s|^INVENTORY_LOGIN=.*|INVENTORY_LOGIN=sqlmonitor_inventory|" \
	      -e "s|^ALL_SERVER_LOGIN=.*|ALL_SERVER_LOGIN=|" \
	      -e "s|^INVENTORY_PASSWORD_FILE=.*|INVENTORY_PASSWORD_FILE=/etc/sqlmonitor/inventory.password|" \
	      $(LINUX_DIR)/sqlmonitor-inventory.conf.sample > /etc/sqlmonitor/inventory.conf && \
	  printf "%s" "$$SA_PASSWORD" > /etc/sqlmonitor/inventory.password && \
	  chmod 0640 /etc/sqlmonitor/inventory.password'
	$(TOOLS) bash $(LINUX_DIR)/install-inventory.sh --skip systemd --verbose
	$(TOOLS) install -o root -g sqlmonitor -m 0750 $(LINUX_DIR)/test/tools/run-timers.sh /opt/sqlmonitor/bin/
	@# The two Database Mail jobs cannot work here - see the file's header.
	$(TOOLSH) '$(SQLCMD) -S "$$INVENTORY_SERVER" -U sa -P "$$SA_PASSWORD" -C -b -i $(LINUX_DIR)/test/bootstrap/04-disable-mail-jobs.sql'

.PHONY: dry-run
dry-run: ## install-inventory.sh --dry-run (shows what it would do)
	$(TOOLS) bash $(LINUX_DIR)/install-inventory.sh --dry-run --verbose --skip systemd

.PHONY: all
all: up bootstrap install verify ## up -> bootstrap -> install -> verify

# -------------------------------------------------------------------- tasks --
.PHONY: timers
timers: ## Run the six timer-driven tasks on their schedules (Ctrl-C to stop)
	$(COMPOSE) exec tools bash /opt/sqlmonitor/bin/run-timers.sh

.PHONY: timers-once
timers-once: ## Run each timer-driven task exactly once
	$(TOOLS) bash /opt/sqlmonitor/bin/run-timers.sh --once

.PHONY: run
run: ## Run one task: make run TASK=check-instance-availability
	@test -n "$(TASK)" || { echo "Usage: make run TASK=<script-name-without-.sh>"; exit 1; }
	$(TOOLS) bash /opt/sqlmonitor/bin/$(TASK).sh --verbose

.PHONY: jobs
jobs: ## Start every (dba) SQLMonitor Agent job once, then show outcomes
	$(TOOLS) bash $(LINUX_DIR)/test/tools/status.sh jobs

.PHONY: job-status
job-status: ## Show last outcome of every (dba) SQLMonitor Agent job
	$(TOOLS) bash $(LINUX_DIR)/test/tools/status.sh status


# ------------------------------------------------------------------ verify --
.PHONY: verify
verify: ## Prove the inventory is collecting: jobs, all_server_* rows, errors
	$(TOOLS) bash $(LINUX_DIR)/test/verify.sh

.PHONY: errors
errors: ## Show the most recent dbo.sma_errorlog entries
	$(TOOLS) bash $(LINUX_DIR)/test/tools/status.sh errors

.PHONY: data
data: ## Show row counts in the all_server_* collection tables
	$(TOOLS) bash $(LINUX_DIR)/test/tools/status.sh data


# ------------------------------------------------------------------- shell --
.PHONY: sh
sh: ## Interactive shell in the tools container
	$(COMPOSE) exec tools bash

.PHONY: sql
sql: ## sqlcmd against the inventory DBA database
	$(COMPOSE) exec tools bash -c '$(SQLCMD) -S "$$INVENTORY_SERVER" -d DBA -U sa -P "$$SA_PASSWORD" -C'

.PHONY: sql-monitored
sql-monitored: ## sqlcmd against monitored1's DBA database
	$(COMPOSE) exec tools bash -c '$(SQLCMD) -S monitored1 -d DBA -U sa -P "$$SA_PASSWORD" -C'

# ----------------------------------------------------------------- grafana --
.PHONY: grafana
grafana: ## Start Grafana on http://localhost:3000 (admin/admin)
	$(COMPOSE) --profile grafana up -d grafana
	@echo "Grafana: http://localhost:$(or $(GRAFANA_PORT),3000)  (admin / $(or $(GRAFANA_ADMIN_PASSWORD),admin))"
	@echo "Import dashboards from ../../../Grafana-Dashboards/*.json"
