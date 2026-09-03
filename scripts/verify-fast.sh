#!/bin/sh
# Fast verification. Wired to the Claude Code Stop hook, so it must stay quick.
#
# Covers the cheap, high-signal checks: repository structure, Python lint, and
# the Python test suite. Deliberately skips `tsc` and the frontend suite, which
# together dominate the runtime. Full coverage lives in scripts/verify.sh and is
# run explicitly at phase checkpoints.
#
# Usage: ./scripts/verify-fast.sh

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT" || exit 1

WORKER_DIR="services/worker"
VENV="$WORKER_DIR/.venv"

FAILED=0

run_step() {
    label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        printf '  ok    %s\n' "$label"
    else
        printf '  FAIL  %s\n' "$label"
        FAILED=1
    fi
}

printf 'Fast verification\n'

# Structure runs quietly unless it fails, in which case the detail is useful.
if ./scripts/check-structure.sh >/dev/null 2>&1; then
    printf '  ok    structure\n'
else
    printf '  FAIL  structure\n'
    ./scripts/check-structure.sh 2>&1 | grep -E '^  FAIL' || true
    FAILED=1
fi

# A missing venv means the toolchain was never set up. Report it rather than
# passing by omission.
if [ -x "$VENV/bin/ruff" ] && [ -x "$VENV/bin/pytest" ]; then
    run_step 'worker lint (ruff)'    sh -c "cd '$WORKER_DIR' && .venv/bin/ruff check ."
    run_step 'worker tests (pytest)' sh -c "cd '$WORKER_DIR' && .venv/bin/pytest -q"
else
    printf "  FAIL  worker toolchain missing (run 'make setup')\n"
    FAILED=1
fi

if [ "$FAILED" -ne 0 ]; then
    printf 'FAST VERIFICATION FAILED\n'
    exit 1
fi

printf 'FAST VERIFICATION PASSED\n'
exit 0
