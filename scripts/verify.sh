#!/bin/sh
# Full verification. Run at every phase checkpoint.
#
# Runs every step even when one fails, then reports a summary. A partial pass
# must not hide behind the first error — the whole point of a checkpoint gate is
# knowing everything that is broken, not just the first thing.
#
# Usage: ./scripts/verify.sh

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT" || exit 1

WORKER_DIR="services/worker"
WEB_DIR="apps/web"
VENV="$WORKER_DIR/.venv"

FAILURES=""
STEPS=0

run_step() {
    label=$1
    shift
    STEPS=$((STEPS + 1))
    printf '\n=== %s ===\n' "$label"
    # The status prefix is passed as an argument, not embedded in the format
    # string: a format beginning with "--" is parsed as an option by some
    # printf implementations (bash's builtin among them).
    if "$@"; then
        printf '%s\n' "--- PASS: $label"
    else
        printf '%s\n' "--- FAIL: $label"
        FAILURES="$FAILURES\n  - $label"
    fi
}

# Missing dependencies are a hard failure, never a silent skip: a verification
# run that reports success because it did nothing is worse than one that fails.
require() {
    if [ ! -e "$1" ]; then
        printf '\n=== %s ===\n' "$2"
        printf 'Missing: %s\n' "$1"
        printf "Run 'make setup' first.\n"
        printf '%s\n' "--- FAIL: $2"
        FAILURES="$FAILURES\n  - $2 (missing $1; run 'make setup')"
        STEPS=$((STEPS + 1))
        return 1
    fi
    return 0
}

printf 'Full verification\n'
printf 'Repository: %s\n' "$ROOT"

# -- Structure ---------------------------------------------------------------
run_step 'structure' ./scripts/check-structure.sh

# -- Python worker -----------------------------------------------------------
if require "$VENV/bin/ruff" 'worker lint (ruff)'; then
    run_step 'worker lint (ruff)' sh -c "cd '$WORKER_DIR' && .venv/bin/ruff check ."
fi

if require "$VENV/bin/pytest" 'worker tests (pytest)'; then
    run_step 'worker tests (pytest)' sh -c "cd '$WORKER_DIR' && .venv/bin/pytest"
fi

if require "$VENV/bin/worker" 'worker CLI (health)'; then
    run_step 'worker CLI (health)' sh -c "'$VENV/bin/worker' health >/dev/null"
fi

# -- Database integration ----------------------------------------------------
# These tests need a real Postgres: foreign keys, check constraints, and
# partial unique indexes cannot be verified against a mock without testing the
# mock instead of the schema.
#
# When the database is down they are skipped -- but never quietly. A suite that
# silently skips is indistinguishable from one that passes, and that is the
# more dangerous failure. DB_UNVERIFIED is reported in the summary.
DB_UNVERIFIED=0
if [ -x "$VENV/bin/pytest" ]; then
    printf '\n=== db integration tests ===\n'
    if "$VENV/bin/python" -c "
import sys
sys.path.insert(0, '$WORKER_DIR/src')
from recruiting_intel.db import is_reachable
sys.exit(0 if is_reachable() else 1)
" 2>/dev/null; then
        if (cd "$WORKER_DIR" && .venv/bin/pytest -m integration -q); then
            printf '%s\n' "--- PASS: db integration tests"
        else
            printf '%s\n' "--- FAIL: db integration tests"
            FAILURES="$FAILURES\n  - db integration tests"
        fi
    else
        DB_UNVERIFIED=1
        printf '!!!  SKIPPED: Postgres unreachable at 127.0.0.1:54322\n'
        printf '!!!  The database schema is UNVERIFIED by this run.\n'
        printf "!!!  Start it with:  make db-up && make db-reset\n"
        printf '%s\n' "--- SKIP: db integration tests"
    fi
    STEPS=$((STEPS + 1))
fi

# -- Web app -----------------------------------------------------------------
if require "$WEB_DIR/node_modules" 'web lint (eslint)'; then
    run_step 'web lint (eslint)'   sh -c "cd '$WEB_DIR' && npm run --silent lint"
    run_step 'web typecheck (tsc)' sh -c "cd '$WEB_DIR' && npm run --silent typecheck"
    run_step 'web tests (vitest)'  sh -c "cd '$WEB_DIR' && npm run --silent test"
fi

# -- Summary -----------------------------------------------------------------
printf '\n========================================\n'
if [ -n "$FAILURES" ]; then
    printf 'VERIFICATION FAILED (%s steps run)\n' "$STEPS"
    # shellcheck disable=SC2059
    printf "$FAILURES\n"
    exit 1
fi

if [ "$DB_UNVERIFIED" -ne 0 ]; then
    # Not a failure -- the code that ran did pass -- but the run is incomplete,
    # and saying "all green" here would be untrue.
    printf 'VERIFICATION PASSED WITH GAPS (%s steps)\n' "$STEPS"
    printf '  Database schema was NOT verified (Postgres unreachable).\n'
    printf '  A phase checkpoint requires these tests to have actually run.\n'
    exit 0
fi

printf 'VERIFICATION PASSED (%s steps, all green)\n' "$STEPS"
exit 0
