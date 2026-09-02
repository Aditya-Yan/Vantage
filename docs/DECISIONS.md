# Architecture Decision Records

Lightweight ADRs. Append new entries; **never silently rewrite a prior decision.** To reverse one, add a new record that supersedes it by number and say so explicitly.

Format: Date / Decision / Reason / Alternatives considered / Consequences.

---

## ADR-001 — Project constitution documents remain untracked

**Date:** 2026-09-02
**Status:** Accepted

**Decision**
`CLAUDE.md`, `CLAUDE.local.md`, `docs/MASTER_PLAN.md`, and `docs/PHASE_STATUS.md` stay in `.gitignore` and are not committed. All other documentation (`ARCHITECTURE.md`, `DATA_MODEL.md`, `METRICS.md`, `TESTING.md`, this file) and `README.md` are tracked normally.

**Reason**
User decision. These files are private development instruments rather than project deliverables, and the master plan in particular is not intended for a public repository.

**Alternatives considered**
- Track `CLAUDE.md` and `PHASE_STATUS.md` while keeping `MASTER_PLAN.md` private — closer to the master plan's §4 repository structure, rejected in favor of keeping all three private.
- Track everything — simplest and fully consistent with §4, rejected because it would publish the full specification.

**Consequences**
- The master plan's §31 principle "use Git history as implementation state" holds only for code and public documentation. It does **not** hold for phase state.
- **Phase state must always be read from `docs/PHASE_STATUS.md` on disk, never inferred from `git log`.** A checkpoint commit will not contain the status update that accompanies it.
- Phase 0's own constitution documents are absent from the initial commit. This is intended, not an omission.
- A fresh clone of this repository will not contain the operating instructions. `README.md` and `docs/ARCHITECTURE.md` must therefore carry enough context to stand alone.

---

## ADR-002 — `.claude/settings.json` created empty in Phase 0; hooks deferred to Phase 1

**Date:** 2026-09-02
**Status:** Accepted

**Decision**
Phase 0 creates `.claude/settings.json` as valid minimal settings (`{}`) plus the `.claude/skills/phase-check/` and `.claude/agents/` structures. No hooks of any kind are configured, and nothing references `scripts/verify-fast.sh`. Phase 1 creates and verifies `scripts/verify-fast.sh` first, and only then adds the lightweight Stop hook.

**Reason**
User decision, resolving a conflict in the specification: §4 lists `.claude/settings.json` in the repository structure, but Phase 0's action list (items 1–15) does not include it, and §5 explicitly defers the Stop/verification hook until "Phase 1 has working tooling." Creating the file satisfies the structural requirement; leaving it hookless respects the deferral.

**Alternatives considered**
- Ship deterministic safety deny-rules in Phase 0 — plausible, since §5 describes a safety hook, but not required by the Phase 0 action list and better decided alongside the rest of the hook configuration.
- Defer the file entirely to Phase 1 — strictly matches the Phase 0 action list but leaves the §4 structure incomplete.

**Consequences**
- A hook that references a nonexistent script cannot fire, so the failure mode is avoided by construction.
- The destructive-operation guardrails from §5's safety hook are, for now, enforced by the operating rules in `CLAUDE.md` rather than by configuration.
- Phase 1 must remember to add the Stop hook after `verify-fast.sh` passes. Tracked in `PHASE_STATUS.md`.

---

## ADR-003 — Phase 0 scaffolds top-level directories only

**Date:** 2026-09-02
**Status:** Accepted

**Decision**
Phase 0 creates `apps/`, `services/`, `supabase/migrations/`, `scripts/`, and `tests/fixtures/{jobs,research,dedupe}/` with `.gitkeep` files. It does **not** create anything inside `apps/web/` or `services/worker/`.

**Reason**
User decision. §4 shows populated `apps/web/` and `services/worker/` trees, but those directories are generated in Phase 1 by `create-next-app` and `uv`. Pre-seeding them with placeholder files would conflict with the generators — `create-next-app` in particular is unhappy with a non-empty target.

**Alternatives considered**
- Create the full §4 tree with `.gitkeep` throughout — literal compliance with the structure diagram, rejected because it fights the Phase 1 tooling.
- Create the worker tree but not the web tree, since `uv` tolerates existing directories — rejected as an inconsistent halfway position.

**Consequences**
- The repository after Phase 0 does not visually match §4's diagram. It will after Phase 1.
- Phase 1 owns the internal layout of both applications and can follow each generator's conventions without working around placeholder files.

---

## ADR-004 — "Agent-Reach" deferred to Phase 7 pending identification

**Date:** 2026-09-02
**Status:** Accepted — open question

**Decision**
No action in Phase 0 beyond recording the gap. Before Phase 7 begins, the concrete project referred to as "Agent-Reach" must be identified, its current documentation inspected, and a specific released version or commit pinned. If it cannot be identified, Phase 7 proceeds without it using the `SearchProvider` interface directly, and this record is superseded.

**Reason**
The master plan references Agent-Reach in §16 (as the last rung of the long-tail source fallback ladder) and §19 (recruiter research), and Phase 0 explicitly says not to install it. But no repository, package name, vendor, or version appears anywhere in the specification. It cannot be integrated as specified without further information.

**Alternatives considered**
- Guess at a package matching the name — rejected outright. Installing an unverified dependency based on a name match is a supply-chain risk.
- Ask now — unnecessary; Phase 0 forbids installing it, so the question is not yet blocking.

**Consequences**
- Not a Phase 0 or Phase 1–6 blocker.
- Phase 7 planning must open with this question. Recorded in `PHASE_STATUS.md` as a known future blocker.
- The architecture already isolates the risk: §19 requires Agent-Reach to sit behind a provider interface, so domain logic never couples to it and its absence is survivable.

---

## ADR-005 — Phase 0 adds a structural verification script

**Date:** 2026-09-02
**Status:** Accepted

**Decision**
Phase 0 includes `scripts/check-phase0.sh`, a dependency-free POSIX shell script asserting the phase's structural acceptance criteria. It becomes an input to `scripts/verify.sh` when that is built in Phase 1.

**Reason**
Phase 0's acceptance criteria (§8) are stated as assertions with no runner behind them — `pytest` and the verify scripts both arrive in Phase 1. `CLAUDE.md` requires that every important implementation have an automated way to verify it. A small shell script closes the gap without pulling any Phase 1 tooling forward.

**Alternatives considered**
- Verify Phase 0 by manual inspection only — consistent with the literal action list, but leaves the phase unverifiable by a future session and breaks the project's own verification rule.
- Pull `pytest` forward from Phase 1 — a larger scope violation for a purely structural check.

**Consequences**
- Phase 0 is re-verifiable at any time by any session, which matters because its output is the constitution every later phase depends on.
- One file beyond the literal Phase 0 action list. Deliberate and recorded here.
- The script must be kept current as the repository structure evolves, or retired into `verify.sh` in Phase 1.
