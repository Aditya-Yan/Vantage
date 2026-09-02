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

## Commands

Available from **Phase 1**, when the toolchain is created:

| Command | Scope |
| --- | --- |
| `make setup` | Install frontend and worker dependencies |
| `make dev` | Run the local development stack |
| `make test` | Frontend tests + Python tests |
| `make lint` | ESLint + ruff |
| `make verify` | Everything: lint, typecheck, and all tests |
| `scripts/verify.sh` | Full verification, used at phase checkpoints |
| `scripts/verify-fast.sh` | Quick subset, suitable for a Stop hook |

Phase 0 has no test runner. Its structural acceptance criteria are checked by `scripts/check-phase0.sh`, which becomes an input to `scripts/verify.sh` in Phase 1.
