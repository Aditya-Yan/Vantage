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
        lint lint-worker lint-web typecheck verify verify-fast clean

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
	@echo "  worker CLI:     $(VENV)/bin/worker health"

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
