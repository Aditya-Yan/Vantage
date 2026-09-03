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

printf 'VERIFICATION PASSED (%s steps, all green)\n' "$STEPS"
exit 0
