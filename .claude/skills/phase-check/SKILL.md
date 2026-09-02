---
name: phase-check
description: Run the phase checkpoint procedure for the Recruiting Intelligence Platform. Verifies the current phase's acceptance criteria, runs tests and lint, checks for committed secrets, confirms documentation is updated, and produces the required checkpoint report. Use when a phase's implementation is finished, when the user asks for a checkpoint or phase report, or when asked to verify the current phase is complete.
---

# Phase Checkpoint

Verify that the currently approved phase is genuinely complete and produce the required checkpoint report.

**This skill never begins another phase.** It reports and stops. Starting the next phase requires explicit user instruction, given after they have read the report.

## Procedure

Work through all nine steps in order. Do not skip a step because it looks likely to pass.

### 1. Read the current phase

Read `docs/PHASE_STATUS.md` **from disk**. Do not infer phase state from `git log` — the status file is untracked by design (see ADR-001 in `docs/DECISIONS.md`), so git history does not reflect it.

Note the current phase, current subphase, and which phases are approved.

### 2. Read that phase's acceptance criteria

Read only the relevant phase section of `docs/MASTER_PLAN.md`. Do not re-read the whole plan.

Extract the phase's acceptance tests and its STOP POINT requirements verbatim, then check each one individually. A criterion you cannot verify is a criterion that failed — report it as such rather than assuming.

### 3. Run the tests

Run the phase-appropriate suite. From Phase 1 onward this is `make verify`; before that, `scripts/check-phase0.sh`.

Report the actual command and its actual result. If tests fail, say so plainly and include the failure output. Never report a phase as complete over failing tests.

### 4. Run lint and type checking

Frontend: ESLint and TypeScript. Worker: `ruff`. Report real results.

### 5. Inspect uncommitted changes

Run `git status` and `git diff`. Identify anything unexpected, anything unrelated to the current phase, and any pre-existing user changes that must not be swept into the checkpoint commit.

### 6. Verify no secrets are committed

Check that:

- No `.env` file is tracked. `.env.example` contains variable **names only**, with no values.
- No API keys, tokens, session cookies, private credentials, or resume files are tracked.
- `CLAUDE.md`, `CLAUDE.local.md`, `docs/MASTER_PLAN.md`, and `docs/PHASE_STATUS.md` are still ignored (`git check-ignore`).
- Nothing in the diff logs a secret or embeds a credential.

### 7. Verify documentation is current

- `docs/PHASE_STATUS.md` reflects reality
- New architectural decisions are appended to `docs/DECISIONS.md` — appended, never rewritten in place
- `docs/ARCHITECTURE.md`, `docs/DATA_MODEL.md`, `docs/METRICS.md`, and `docs/TESTING.md` are updated if this phase changed what they describe
- Metrics introduced this phase are recorded in `docs/METRICS.md`

### 8. Produce the checkpoint report

Use this structure exactly:

```
PHASE X COMPLETE

Implemented
- ...

Architecture / schema changes
- ...

Automated verification
- command: ...
- result: PASS/FAIL
- tests: X passing

Manual test for you
1. ...
2. ...
3. ...

Metrics now recording
- ...

Known limitations / blocked live integrations
- ...

Files worth reviewing
- ...

Git
- commit: <hash if created>
- no remote push performed

NEXT PHASE
Phase X+1: <name>

I have NOT started the next phase.
```

Report honestly. Skipped steps, blocked live integrations, and missing verification all belong in the report. A checkpoint that hides a gap is worse than one that fails.

### 9. Stop

The local checkpoint commit (`phase-X: <short description>`) may be created **after** verification passes. Never push. Never continue into the next phase.

## Non-negotiables to spot-check

While reviewing the diff, confirm the phase did not violate any of these:

- Raw job titles preserved exactly; never overwritten with a normalized display title
- Discoveries never trigger recruiter research — only new canonical job insertion does
- Reddit discoveries require verification against an official source before canonicalization
- LinkedIn access is anonymous and public only; no auth, cookies, CAPTCHA bypass, or proxy rotation
- LLM output is schema-validated at runtime; LLMs are absent from parsing, whitelist lookup, URL normalization, strong-ID dedupe, ranking arithmetic, state transitions, and metrics
- Recruiter facts carry provenance; unknown stays `UNKNOWN`; inferred emails are never described as guaranteed
- No code path sends email
- No metric is fabricated or estimated
