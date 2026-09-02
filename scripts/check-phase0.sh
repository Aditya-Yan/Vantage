#!/bin/sh
# Phase 0 structural verification.
#
# Checks the Phase 0 acceptance criteria from docs/MASTER_PLAN.md section 8.
# Dependency-free POSIX sh: no pytest, no node, no uv. Phase 0 predates all of them.
#
# Becomes an input to scripts/verify.sh in Phase 1. See ADR-005.
#
# Usage: ./scripts/check-phase0.sh

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

printf 'Phase 0 structural verification\n'
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

# settings.json must be valid JSON. Phase 0 declares no hooks (ADR-002):
# a hook referencing scripts/verify-fast.sh cannot exist before Phase 1 builds it.
if command -v python3 >/dev/null 2>&1; then
    if python3 -m json.tool .claude/settings.json >/dev/null 2>&1; then
        ok '.claude/settings.json parses as JSON'
    else
        fail '.claude/settings.json parses as JSON'
    fi
else
    printf '  skip  .claude/settings.json JSON parse (python3 unavailable)\n'
fi

if grep -qF '"hooks"' .claude/settings.json 2>/dev/null; then
    fail '.claude/settings.json declares no hooks (deferred to Phase 1, ADR-002)'
else
    ok '.claude/settings.json declares no hooks (deferred to Phase 1, ADR-002)'
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

# Phase 1 generators (create-next-app, uv) own these. Pre-seeding them fights
# the tooling, so Phase 0 must leave them alone (ADR-003).
for d in apps/web services/worker; do
    if [ -d "$d" ]; then
        fail "$d not pre-created (owned by Phase 1 generators, ADR-003)"
    else
        ok "$d not pre-created (owned by Phase 1 generators, ADR-003)"
    fi
done

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
check_contains docs/PHASE_STATUS.md 'Phase 0' 'reports Phase 0'

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
for adr in ADR-001 ADR-002 ADR-003 ADR-004 ADR-005; do
    check_contains docs/DECISIONS.md "$adr" "$adr recorded"
done

# ---------------------------------------------------------------------------
printf '\n----------------------------------------\n'
printf 'passed: %s   failed: %s\n' "$PASS" "$FAIL"

if [ "$FAIL" -gt 0 ]; then
    printf 'PHASE 0 VERIFICATION FAILED\n'
    exit 1
fi

printf 'PHASE 0 VERIFICATION PASSED\n'
exit 0
