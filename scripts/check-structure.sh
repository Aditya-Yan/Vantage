#!/bin/sh
# Repository structural verification.
#
# Asserts that the constitution documents, Claude Code configuration, directory
# layout, and secret hygiene are all intact. Dependency-free POSIX sh, so it
# runs before any toolchain is installed.
#
# Called by scripts/verify.sh and scripts/verify-fast.sh (ADR-005, ADR-009).
# Renamed from check-phase0.sh in Phase 1: it now checks structure that must
# hold in every phase, not Phase 0's transient state.
#
# Usage: ./scripts/check-structure.sh

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT" || exit 1

PASS=0
FAIL=0

ok() {
    PASS=$((PASS + 1))
    printf '  ok    %s\n' "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    printf '  FAIL  %s\n' "$1"
}

section() {
    printf '\n%s\n' "$1"
}

# A file must exist and contain something.
check_file() {
    if [ ! -f "$1" ]; then
        fail "$1 (missing)"
    elif [ ! -s "$1" ]; then
        fail "$1 (empty)"
    else
        ok "$1"
    fi
}

check_dir() {
    if [ -d "$1" ]; then
        ok "$1"
    else
        fail "$1 (missing)"
    fi
}

# Fixed-string search, so patterns need no escaping.
check_contains() {
    if [ ! -f "$1" ]; then
        fail "$3 (file $1 missing)"
    elif grep -qF "$2" "$1"; then
        ok "$3"
    else
        fail "$3"
    fi
}

printf 'Repository structural verification\n'
printf 'Repository: %s\n' "$ROOT"

# ---------------------------------------------------------------------------
section 'Required documents'
# ---------------------------------------------------------------------------
check_file README.md
check_file CLAUDE.md
check_file .env.example
check_file .gitignore
check_file docs/ARCHITECTURE.md
check_file docs/DATA_MODEL.md
check_file docs/METRICS.md
check_file docs/TESTING.md
check_file docs/DECISIONS.md
check_file docs/PHASE_STATUS.md
check_file docs/MASTER_PLAN.md

# ---------------------------------------------------------------------------
section 'Claude Code configuration'
# ---------------------------------------------------------------------------
check_file .claude/settings.json
check_file .claude/skills/phase-check/SKILL.md
check_file .claude/agents/adapter-auditor.md
check_file .claude/agents/test-auditor.md

# settings.json must be valid JSON.
if command -v python3 >/dev/null 2>&1; then
    if python3 -m json.tool .claude/settings.json >/dev/null 2>&1; then
        ok '.claude/settings.json parses as JSON'
    else
        fail '.claude/settings.json parses as JSON'
    fi
else
    printf '  skip  .claude/settings.json JSON parse (python3 unavailable)\n'
fi

# The Stop hook was deferred from Phase 0 until verify-fast.sh existed
# (ADR-002). It exists from Phase 1 onward, and must point at a real script.
if grep -qF 'verify-fast.sh' .claude/settings.json 2>/dev/null; then
    ok '.claude/settings.json wires the Stop hook to verify-fast.sh (ADR-002)'
else
    fail '.claude/settings.json wires the Stop hook to verify-fast.sh (ADR-002)'
fi

# Both subagents are read-only auditors and must say so.
for agent in adapter-auditor test-auditor; do
    check_contains ".claude/agents/${agent}.md" 'read-only' "${agent} declares itself read-only"
done

# ---------------------------------------------------------------------------
section 'Directory skeleton'
# ---------------------------------------------------------------------------
check_dir apps
check_dir services
check_dir supabase/migrations
check_dir scripts
check_dir tests/fixtures/jobs
check_dir tests/fixtures/research
check_dir tests/fixtures/dedupe

# Both applications exist from Phase 1 onward. Phase 0 asserted the opposite
# (ADR-003, generators own these directories); that assertion inverted when the
# generators ran. See ADR-009.
check_dir apps/web
check_dir services/worker
check_file apps/web/package.json
check_file services/worker/pyproject.toml
check_file Makefile

# ---------------------------------------------------------------------------
section 'CLAUDE.md required topics (MASTER_PLAN section 5)'
# ---------------------------------------------------------------------------
check_contains CLAUDE.md '## Project Purpose'              'project purpose'
check_contains CLAUDE.md '## Current Architecture'         'current architecture'
check_contains CLAUDE.md '## Architectural Non-Negotiables' 'non-negotiable data-flow rules'
check_contains CLAUDE.md 'PUBLIC-INFORMATION ENRICHMENT ONLY' 'public-LinkedIn-only restriction'
check_contains CLAUDE.md 'verified against an official ATS' 'Reddit verification requirement'
check_contains CLAUDE.md 'Always preserve the exact published job title' 'raw-title preservation rule'
check_contains CLAUDE.md 'Only insertion of a genuinely NEW canonical job' 'canonical-job-only research trigger'
check_contains CLAUDE.md 'Prefer deterministic software whenever possible' 'LLM-last-resort philosophy'
check_contains CLAUDE.md 'strict structured schemas and runtime validation' 'structured-output requirement'
check_contains CLAUDE.md 'NEVER automatically sends'      'no automatic email sending'
check_contains CLAUDE.md '## Testing Commands'            'testing commands'
check_contains CLAUDE.md '## Repository Layout'           'repository layout'
check_contains CLAUDE.md '## Current Phase'               'current phase'
check_contains CLAUDE.md '## Checkpoint Behavior'         'checkpoint behavior'
check_contains CLAUDE.md 'docs/DECISIONS.md'              'where decisions are recorded'

# ---------------------------------------------------------------------------
section 'Phase status'
# ---------------------------------------------------------------------------
# Phase-agnostic: the file must carry the required headings, whatever phase it
# reports. Asserting a specific phase number would make this script fail on
# every checkpoint.
check_contains docs/PHASE_STATUS.md '## Current phase'   'declares a current phase'
check_contains docs/PHASE_STATUS.md '## Completed phases' 'declares completed phases'
check_contains docs/PHASE_STATUS.md '## Known blockers'   'declares known blockers'

# ---------------------------------------------------------------------------
section 'Secret hygiene'
# ---------------------------------------------------------------------------
# .env.example carries variable names only. Any NAME=value line is a leak.
if [ -f .env.example ]; then
    leaked=$(grep -E '^[A-Za-z_][A-Za-z0-9_]*=.+' .env.example || true)
    if [ -n "$leaked" ]; then
        fail '.env.example contains names only'
        printf '%s\n' "$leaked" | sed 's/^/          /'
    else
        ok '.env.example contains names only'
    fi
fi

if [ -d .git ]; then
    tracked=$(git ls-files 2>/dev/null)

    secrets=$(printf '%s\n' "$tracked" | grep -Ei '(^|/)\.env$|(^|/)\.env\.|\.pem$|\.key$|\.p12$|\.pfx$|cookie|session.*\.json$|credentials\.json$|service-account|resume' | grep -v '^\.env\.example$' || true)
    if [ -n "$secrets" ]; then
        fail 'no secret-like files are tracked'
        printf '%s\n' "$secrets" | sed 's/^/          /'
    else
        ok 'no secret-like files are tracked'
    fi

    # Private development files stay untracked (ADR-001).
    for f in CLAUDE.md CLAUDE.local.md docs/MASTER_PLAN.md docs/PHASE_STATUS.md; do
        if git check-ignore -q "$f" 2>/dev/null; then
            ok "$f is gitignored (ADR-001)"
        else
            fail "$f is gitignored (ADR-001)"
        fi
    done

    for f in CLAUDE.md docs/MASTER_PLAN.md docs/PHASE_STATUS.md; do
        if printf '%s\n' "$tracked" | grep -qxF "$f"; then
            fail "$f is not tracked (ADR-001)"
        else
            ok "$f is not tracked (ADR-001)"
        fi
    done

    # Documentation that should be in the repository.
    for f in README.md .env.example docs/ARCHITECTURE.md docs/DATA_MODEL.md docs/METRICS.md docs/TESTING.md docs/DECISIONS.md; do
        if printf '%s\n' "$tracked" | grep -qxF "$f"; then
            ok "$f is tracked"
        else
            fail "$f is tracked (run git add)"
        fi
    done
else
    printf '  skip  git checks (not a git repository)\n'
fi

# ---------------------------------------------------------------------------
section 'Decision records'
# ---------------------------------------------------------------------------
for adr in ADR-001 ADR-002 ADR-003 ADR-004 ADR-005 \
           ADR-006 ADR-007 ADR-008 ADR-009 ADR-010 ADR-011; do
    check_contains docs/DECISIONS.md "$adr" "$adr recorded"
done

# ---------------------------------------------------------------------------
printf '\n----------------------------------------\n'
printf 'passed: %s   failed: %s\n' "$PASS" "$FAIL"

if [ "$FAIL" -gt 0 ]; then
    printf 'STRUCTURE CHECK FAILED\n'
    exit 1
fi

printf 'STRUCTURE CHECK PASSED\n'
exit 0
