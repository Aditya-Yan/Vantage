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

---

## ADR-006 — `venv` + `pip` instead of `uv`

**Date:** 2026-09-02
**Status:** Accepted

**Decision**
The Python worker uses the standard library's `venv` with `pip` for dependency management. `pyproject.toml` is the single source of dependency truth; the environment is created with `python3 -m venv .venv` and populated with `pip install -e ".[dev]"`.

**Reason**
User decision. Master plan §3 mandates `uv` and §9 1B says to create the project with it. `uv` was not installed on the development machine, and the user chose not to add it. This is a deliberate, recorded deviation from the mandated stack — not an oversight.

**Alternatives considered**
- Install `uv` via the official standalone installer — spec-compliant, rejected by user preference.
- Install `uv` via Homebrew — same, rejected.

**Consequences**
- **No lockfile.** `uv.lock` would have provided reproducible installs for free. `pyproject.toml` pins version floors, but exact resolution is not captured, so two setups at different times may resolve different versions.
- Reproducible installs are **deferred to Phase 11**, where deployment actually needs them. A `pip freeze` artifact or `pip-tools` can be introduced then. Generating one now would be maintenance with no consumer.
- Dependency installation is slower. This affects `make setup` and any future CI, not the inner development loop.
- The Python toolchain is not pinned per-project; the system Python 3.12.2 is used directly.
- Fully reversible: `uv` can adopt the existing `pyproject.toml` later with no code changes.

---

## ADR-007 — Vitest and React Testing Library for frontend tests

**Date:** 2026-09-02
**Status:** Accepted

**Decision**
The web app uses Vitest with React Testing Library and `jsdom`. Test files live in `apps/web/__tests__/`. `npm test` runs `vitest run` (single pass); `npm run test:watch` is the watch mode.

**Reason**
User decision, filling a genuine specification gap: §9 requires "frontend test passes" but §3's tech stack names no JavaScript test runner. Vitest keeps `make verify` fast, which matters because it gates every checkpoint. The setup follows the official Next.js Vitest guide bundled with the installed version.

**Alternatives considered**
- Jest — Next.js's traditional default, heavier and slower to start, more configuration for ESM/TS.
- Playwright only — closer to §9's literal "placeholder page loads", but browser tests are slow and brittle as a checkpoint gate.

**Consequences**
- Playwright is deferred to Phase 9 for E2E, per §25. The two coexist without conflict.
- Vitest globals are disabled in favor of explicit imports, so React Testing Library's automatic cleanup does not self-register. `apps/web/vitest.setup.ts` wires `cleanup()` into `afterEach` explicitly. Without it, renders accumulate across tests and queries match duplicate elements.
- `vite-tsconfig-paths` was installed per the Next.js guide, then removed: the installed Vite resolves tsconfig paths natively via `resolve.tsconfigPaths`, and warned that the plugin was redundant.

---

## ADR-008 — structlog for structured logging

**Date:** 2026-09-02
**Status:** Accepted

**Decision**
The worker uses `structlog`, configured in `recruiting_intel/logging_config.py` with a JSON renderer, contextvar-based correlation-ID binding, and a redaction processor.

**Reason**
User decision. §3 requires "structured logging" without naming a library; §26 requires correlation identifiers (`scan_run_id`, `discovery_id`, `job_id`, `research_task_id`, `company_id`) to travel with every important operation. structlog's contextvar binding delivers that directly. The stdlib alternative meant hand-rolling roughly the same machinery.

**Alternatives considered**
- Stdlib `logging` with a custom JSON formatter — zero dependencies, but correlation IDs across async boundaries require hand-written contextvars plumbing to write, test, and maintain.

**Consequences**
- The module is named `logging_config.py`, **not** `logging/`, so it can never shadow the standard library module for anything importing inside the package. A small deviation from the plan's proposed path, made for a concrete reason.
- Redaction is enforced as a processor on every event rather than at each call site, so a secret cannot be logged by accident. It catches both `SecretStr` instances and values whose key names them sensitive — the latter covers a secret already unwrapped to `str`, which is the case most likely to leak.
- `bind_context()` drops `None` values, so an unknown identifier stays absent rather than being logged as null.

---

## ADR-009 — `check-phase0.sh` renamed to `check-structure.sh`, assertions inverted

**Date:** 2026-09-02
**Status:** Accepted — supersedes the operational half of ADR-005

**Decision**
`scripts/check-phase0.sh` is renamed to `scripts/check-structure.sh`. Three groups of assertions changed:

1. `apps/web/` and `services/worker/` must now **exist** (with `package.json` and `pyproject.toml`); Phase 0 asserted they must not.
2. `.claude/settings.json` must now **declare** the Stop hook; Phase 0 asserted it must not.
3. The `PHASE_STATUS.md` check is phase-agnostic — it asserts required headings rather than a specific phase number.

Both verify scripts call it.

**Reason**
The Phase 0 script encoded Phase 0's transient state as permanent assertions. Two of them enforced ADR-003 (generators own those directories) and one enforced ADR-002 (hook deferred). Phase 1 does exactly what those ADRs said it would, so the script would have failed the moment this phase ran. The phase-number grep had the same defect: it would have passed accidentally, since "Phase 0" still appears in the completed-phases list.

**Alternatives considered**
- Delete the script and fold its checks into `verify.sh` — loses a standalone, dependency-free structural check that runs before any toolchain exists.
- Keep it Phase-0-specific and write a second script per phase — duplication that would drift.

**Consequences**
- The script now checks invariants that hold in every phase, so it does not need rewriting at each checkpoint.
- It must still be updated when the repository structure genuinely changes, and when new ADRs are added (it asserts the ADR list is present).
- ADR-005's rationale stands; only its "fold into verify.sh" instruction is superseded — the script is *called by* verify.sh rather than absorbed into it.

---

## ADR-010 — Provider interfaces deferred to first implementation

**Date:** 2026-09-02
**Status:** Accepted

**Decision**
The five provider interfaces named in §3 (`LLMProvider`, `EmbeddingProvider`, `SearchProvider`, `NotificationProvider`, `JobSourceAdapter`) are **not** created in Phase 1. Each is written in the phase that first implements it: `JobSourceAdapter` in Phase 4A, `EmbeddingProvider` and `LLMProvider` in Phase 5, `SearchProvider` in Phase 7, `NotificationProvider` in Phase 11.

**Reason**
Engineering Priorities favor simple interfaces and warn against premature optimization. An abstract base class written against zero implementations encodes guesses about a shape that is not yet known, and those guesses tend to be wrong in ways that are then worked around rather than fixed.

**Alternatives considered**
- Define all five as empty protocols now — satisfies §3's structure literally, but the definitions would carry no real constraints and would likely be rewritten when the first concrete implementation appeared.

**Consequences**
- The repository does not match §3's provider list until Phase 7. Recorded here so this reads as a decision, not an omission.
- The architectural requirement is unchanged: business logic must never depend directly on a vendor, and model names stay in configuration. Only the timing of the abstraction moves.

---

## ADR-011 — No monorepo tooling

**Date:** 2026-09-02
**Status:** Accepted

**Decision**
`apps/web` and `services/worker` are two independent projects coordinated by a root `Makefile`. No npm workspaces, Turborepo, Nx, or equivalent.

**Reason**
The two halves share no dependencies, no build graph, and no language. Workspace tooling solves cross-package linking and task orchestration, neither of which this repository has.

**Alternatives considered**
- npm workspaces — would still not span the Python side, so the Makefile would remain necessary anyway.

**Consequences**
- Each project is set up and run in its own directory; the Makefile is the only place that knows about both.
- The Makefile targets GNU Make 3.81 (the version macOS ships), so `.ONESHELL` is unavailable and each recipe line runs in its own shell.
- If a third component ever shares JavaScript dependencies with the web app, this decision should be revisited.
