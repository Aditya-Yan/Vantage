# Testing Strategy

Every important implementation must have an automated way to verify it. Testing grows with each phase; a phase is not complete until its acceptance tests pass.

## Governing rules

1. **External service availability never determines whether tests pass.** Every adapter and provider is exercised through saved fixtures or mocks. A test suite that fails because Greenhouse is down is a broken test suite.
2. **No paid API calls in automated tests.** LLM, embedding, and search providers are mocked. Live validation is a separate, explicitly invoked step.
3. **Fixtures are committed** under `tests/fixtures/`, organized by concern (`jobs/`, `research/`, `dedupe/`).
4. **Idempotency is tested, not assumed.** Anything that writes gets a rerun test.
5. **Malformed provider output is a test case, not an edge case.** Every schema boundary has a rejection test.

---

## Layers

### Unit tests

Pure logic, no I/O:

- URL canonicalization (tracking-parameter stripping, identity-bearing parameter preservation)
- Company alias resolution
- Role classification rules and feature scoring
- Embedding-routing / threshold logic
- Score calculations
- Email pattern inference and confidence
- Recruiter ranking arithmetic and score breakdown
- Schema validation

### Adapter fixture tests

Every external adapter requires saved fixtures. Per adapter, cover at minimum: normal response, salary present, salary missing, multiple locations, remote roles, unusual titles, missing descriptions, malformed rows, and error responses (timeout, 429, 500).

### Database integration tests

Against a local Supabase instance:

- Migrations apply cleanly from an empty database, and a reset reproduces the same schema
- Foreign keys hold
- Invalid enum values and invalid state transitions are rejected at write time
- Upserts are idempotent
- Queue creation and message semantics
- RLS where applicable

### Pipeline integration tests

The full path with external calls mocked:

```
raw ATS job → discovery → classification → canonical job
            → queue → mocked research → recruiter → UI
```

### End-to-end — Phase 9 onward

View new job → expand → mark applied → generate draft → mark emailed.

---

## The permanent deduplication regression test

This test is never deleted, weakened, or skipped. Three source fixtures representing the **same** job must produce:

```
3 discoveries
1 canonical job
3 job_sources
1 research task
```

Rerun the identical fixtures and the assertions become:

```
still 1 canonical job
still 1 research task    (no additional task enqueued)
```

A companion test asserts that similar-but-genuinely-different roles remain separate — the dedup logic must not pass by merging everything.

---

## Reliability testing — Phase 12

Each of these degrades gracefully rather than crashing or corrupting state: source timeout, 429 rate limit, 500 error, malformed ATS response, worker crash mid-task, queue retry, duplicate queue delivery, malformed LLM JSON, search provider failure, transient database failure, public LinkedIn block.

Repeat execution must not create duplicate jobs, duplicate recruiters, duplicate research tasks, or unintended duplicate notifications.

---

## Classification evaluation — Phase 12

A manually labeled set of real observed postings, scored for precision, recall, false-negative rate, false-positive rate, and LLM fallback rate.

**Recall is the priority metric.** The system is tuned so that missing a strong SWE opportunity is treated as more costly than surfacing an occasional irrelevant one.

---

## Tooling

| Layer | Tool |
| --- | --- |
| Python tests | `pytest` with `pytest-asyncio` (asyncio mode `auto`) |
| Python lint | `ruff` |
| Frontend tests | Vitest with React Testing Library and `jsdom` (ADR-007) |
| Frontend lint | ESLint (`eslint-config-next`) |
| Types | `tsc --noEmit`, strict mode plus `noUncheckedIndexedAccess` |

Vitest globals are disabled in favor of explicit imports, so React Testing Library's auto-cleanup is wired up manually in `apps/web/vitest.setup.ts`. Without it, renders accumulate across tests.

## Commands

| Command | Scope |
| --- | --- |
| `make setup` | Create the worker venv, install both toolchains |
| `make dev` | Web dev server at `http://localhost:3000` |
| `make test` | pytest + Vitest |
| `make lint` | ruff + ESLint |
| `make typecheck` | `tsc --noEmit` |
| `make verify` | Everything — delegates to `scripts/verify.sh` |
| `scripts/verify.sh` | Full verification, run at phase checkpoints |
| `scripts/verify-fast.sh` | Quick subset, wired to the Claude Code Stop hook |
| `scripts/check-structure.sh` | Dependency-free structural and secret-hygiene checks |

`scripts/verify.sh` runs **every** step even after one fails, then reports a summary and exits non-zero. A partial pass must not hide behind the first error. Missing dependencies are a hard failure pointing at `make setup`, never a silent skip — a run that reports success because it did nothing is worse than one that fails.

`scripts/verify-fast.sh` covers structure, ruff, and pytest only; `tsc` and the frontend suite dominate the runtime and are left to the full script.
