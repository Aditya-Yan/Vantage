# Recruiting Intelligence Platform — developer commands.
#
# Written for GNU Make 3.81 (the version macOS ships). No .ONESHELL, which
# requires 3.82+; every recipe line runs in its own shell.
#
# Python is always invoked through explicit venv paths rather than a bare
# `python`/`pytest`, so targets behave identically whether or not the calling
# shell has the virtualenv activated.

WORKER_DIR := services/worker
WEB_DIR    := apps/web
VENV       := $(WORKER_DIR)/.venv
PY         := $(VENV)/bin/python
PIP        := $(VENV)/bin/pip
PYTEST     := $(VENV)/bin/pytest
RUFF       := $(VENV)/bin/ruff

.DEFAULT_GOAL := help
.PHONY: help setup setup-worker setup-web dev test test-worker test-web \
        lint lint-worker lint-web typecheck verify verify-fast clean \
        db-up db-down db-reset db-status db-psql db-studio test-db

help:
	@echo "Recruiting Intelligence Platform"
	@echo ""
	@echo "  make setup      install worker and web dependencies"
	@echo "  make dev        run the web dev server (http://localhost:3000)"
	@echo "  make test       worker tests + web tests"
	@echo "  make lint       ruff + eslint"
	@echo "  make typecheck  tsc --noEmit"
	@echo "  make verify     full verification (used at phase checkpoints)"
	@echo "  make clean      remove build artifacts and caches"
	@echo ""
	@echo "  Database (local Supabase; needs Docker running):"
	@echo "  make db-up      start the local stack"
	@echo "  make db-reset   drop, re-apply migrations, re-seed"
	@echo "  make db-status  show stack status and URLs"
	@echo "  make db-psql    open psql against the local database"
	@echo "  make db-studio  print the Supabase Studio URL"
	@echo "  make db-down    stop the local stack"
	@echo "  make test-db    run only the DB integration tests"
	@echo ""
	@echo "  worker CLI:     $(VENV)/bin/worker health"
	@echo "                  $(VENV)/bin/worker db check"
	@echo "                  $(VENV)/bin/worker metrics show"

# -- Setup -------------------------------------------------------------------

setup: setup-worker setup-web
	@echo "Setup complete. Run 'make verify'."

setup-worker:
	@echo "==> Python worker"
	test -d $(VENV) || python3 -m venv $(VENV)
	$(PIP) install --quiet --upgrade pip
	cd $(WORKER_DIR) && .venv/bin/pip install --quiet -e ".[dev]"

setup-web:
	@echo "==> Web app"
	cd $(WEB_DIR) && (npm ci --silent || npm install --silent)

# -- Development -------------------------------------------------------------

# The worker has no long-running process until Phase 4A introduces ingestion;
# until then `make dev` runs the web app only.
dev:
	cd $(WEB_DIR) && npm run dev

# -- Test / lint -------------------------------------------------------------

test: test-worker test-web

test-worker:
	@echo "==> pytest"
	cd $(WORKER_DIR) && .venv/bin/pytest

test-web:
	@echo "==> vitest"
	cd $(WEB_DIR) && npm test

lint: lint-worker lint-web

lint-worker:
	@echo "==> ruff"
	cd $(WORKER_DIR) && .venv/bin/ruff check .

lint-web:
	@echo "==> eslint"
	cd $(WEB_DIR) && npm run lint

typecheck:
	@echo "==> tsc"
	cd $(WEB_DIR) && npm run typecheck

# -- Database ----------------------------------------------------------------
# Local Supabase stack. Requires Docker to be running. Migrations live in
# supabase/migrations/ and are applied by the CLI -- never hand-edit a database.

LOCAL_DB_URL := postgresql://postgres:postgres@127.0.0.1:54322/postgres

db-up:
	@docker info > /dev/null 2>&1 || (echo "Docker is not running. Start Docker Desktop first." && exit 1)
	supabase start

db-down:
	supabase stop

# Drops the local database, re-applies every migration from scratch, and
# re-seeds. This is the "migration applies from clean database" path.
db-reset:
	@docker info > /dev/null 2>&1 || (echo "Docker is not running. Start Docker Desktop first." && exit 1)
	supabase db reset

db-status:
	supabase status

# Falls back to the psql inside the Supabase container, since a local psql is
# not guaranteed to be installed.
db-psql:
	@if command -v psql > /dev/null 2>&1; then \
		psql "$(LOCAL_DB_URL)"; \
	else \
		echo "Local psql not found; using the container's."; \
		if [ -t 0 ]; then TTY=-it; else TTY=-i; fi; \
		docker exec $$TTY supabase_db_$(shell basename $(CURDIR)) psql -U postgres; \
	fi

db-studio:
	@echo "Supabase Studio: http://127.0.0.1:54323"

test-db:
	cd $(WORKER_DIR) && .venv/bin/pytest -m integration -v

# -- Verification ------------------------------------------------------------
# One definition of "verified" lives in scripts/verify.sh.

verify:
	./scripts/verify.sh

verify-fast:
	./scripts/verify-fast.sh

# -- Housekeeping ------------------------------------------------------------

clean:
	rm -rf $(WEB_DIR)/.next
	find $(WORKER_DIR) -type d -name __pycache__ -prune -exec rm -rf {} +
	rm -rf $(WORKER_DIR)/.pytest_cache $(WORKER_DIR)/.ruff_cache
	@echo "Cleaned. Virtualenv and node_modules kept; use 'make setup' to rebuild."
