# Vantage

A personal recruiting-intelligence platform for software-engineering job discovery.

Vantage watches a curated universe of high-value SWE employers plus public job-discovery sources, converts heterogeneous raw observations into exactly one canonical record per real opening, automatically researches relevant recruiters for genuinely new openings, ranks them deterministically from evidence, and generates outreach drafts after the user applies.

> **Status: Phase 0 of 12 complete.** This repository currently contains the project constitution, documentation, and scaffold only. There is no runnable application yet — Phase 1 delivers the toolchain. See [Roadmap](#roadmap).

---

## What it does

```
Target companies  →  Job sources  →  Discoveries  →  Normalize
                                                        ↓
                                              Company whitelist filter
                                                        ↓
                                              Role classification
                                                        ↓
                                              Verify · Deduplicate
                                                        ↓
                                                 Canonical job
                                                    ↙       ↘
                                            Notify      Research queue
                                                              ↓
                                                    Recruiter research
                                                    (public sources only)
                                                              ↓
                                                    Evidence · Email discovery
                                                              ↓
                                                    Deterministic ranking
                                                              ↓
                                                            UI
                                                              ↓
                                                    User applies → email draft
```

The design goal is a system worth discussing in an engineering interview: heterogeneous ingestion, event-driven processing, deduplication across sources, asynchronous queues, evidence-backed research with provenance, a hybrid deterministic/LLM architecture, and honest operational metrics.

Full detail in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

### The design decision that matters most

A **discovery** is one raw observation from one source. A **job** is the canonical record of one real opening. Many discoveries collapse into one job.

Recruiter research is triggered by the creation of a new canonical job and by nothing else. Seeing the same posting on Greenhouse, in a GitHub tracker, and on Reddit produces one job, one research task, and one notification. This is what keeps the system cheap, and it is what makes the deduplication metrics meaningful rather than decorative.

---

## Tech stack

| Layer | Technology |
| --- | --- |
| Web | Next.js, TypeScript, React, Tailwind, shadcn/ui |
| Worker | Python 3.12+, `uv`, Pydantic, `httpx` |
| Database | Supabase PostgreSQL, migrations in `supabase/migrations` |
| Queue | Supabase Queues / pgmq |
| Storage | Supabase Storage (private bucket, resume files) |

One Python worker codebase with three entrypoints — `ingestion`, `research`, `maintenance`. No microservices.

Every external capability sits behind an interface (`LLMProvider`, `EmbeddingProvider`, `SearchProvider`, `NotificationProvider`, `JobSourceAdapter`), and every model name lives in configuration. No business logic depends on a specific vendor.

---

## Operating principles

**Deterministic code is preferred to model calls.** LLMs are used for exactly four things: ambiguous role classification, recruiter research reasoning, email draft generation, and occasional offline company scoring. They are never used for ATS parsing, whitelist lookup, URL normalization, strong-ID deduplication, ranking arithmetic, state transitions, or metrics. All model output consumed by the application is schema-validated at runtime and rejected if malformed.

**Published job titles are preserved exactly.** A title is evidence. Classification results live in separate fields, never overwriting what the employer actually wrote.

**Classification optimizes for recall.** Missing a strong opportunity costs more than surfacing an occasional irrelevant one.

**Facts require provenance.** Recruiter information carries a stored source. Unknown information stays unknown. Email addresses are labeled `PUBLISHED`, `INFERRED`, or `UNKNOWN`, and an inferred address is never presented as certain.

**Metrics are never fabricated.** Every number displayed traces to stored data. If the data does not support a figure, the figure is not shown.

---

## Data ethics

This project uses **public information only.**

- **LinkedIn** is public-information enrichment only. No authentication, no session cookies, no account automation, no CAPTCHA or login-wall bypass, no proxy rotation, no aggressive retry after denial. When access is blocked, the system records the outcome and continues without it. Authenticated LinkedIn access is permanently out of scope.
- **Reddit** is a secondary signal. A Reddit claim can never directly create a canonical job; it must first be verified against an official ATS posting or company careers page.
- **Recruiter research** is limited to professionally relevant public information — name, title, company, professional location, recruiting discipline, candidate scope, public professional URLs, and work email. Unrelated personal information is not collected.
- **The system never sends email.** It generates drafts. The user reviews and sends manually. No code path transmits outreach.

---

## Roadmap

| Phase | Scope | Status |
| --- | --- | --- |
| 0 | Project constitution and scaffold | **Complete** |
| 1 | Development foundation — Next.js app, Python worker, `make verify` | Not started |
| 2 | Supabase schema and metrics core | Not started |
| 3 | Company registry and precomputed target filter | Not started |
| 4A | Greenhouse adapter | Not started |
| 4B | Lever and Ashby adapters | Not started |
| 4C | GitHub community trackers | Not started |
| 4D | Reddit secondary signal | Not started |
| 4E | Custom career pages and long-tail fallback | Not started |
| 5 | Role classification engine | Not started |
| 6 | Canonicalization, deduplication, research trigger | Not started |
| 7 | Automatic recruiter research | Not started |
| 8 | Email discovery, confidence, recruiter ranking | Not started |
| 9 | Primary user interface | Not started |
| 10 | Email draft generation | Not started |
| 11 | Notifications, scheduling, production deployment | Not started |
| 12 | Hardening, evaluation, resume-metric mode | Not started |

Each phase ends at a checkpoint: tests and lint run, documentation updates, a local commit, and a written report. Phases are not started without explicit approval.

---

## Development

Not yet runnable. Phase 1 creates the toolchain and these commands:

```bash
make setup     # install frontend and worker dependencies
make dev       # run the local development stack
make test      # frontend + Python tests
make lint      # ESLint + ruff
make verify    # everything: lint, typecheck, all tests
```

Phase 0 verifies itself structurally:

```bash
./scripts/check-phase0.sh
```

Tests never depend on external service availability or paid APIs — every adapter and provider is exercised through committed fixtures and mocks.

---

## Documentation

| Document | Contents |
| --- | --- |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Data flow, components, provider interfaces, non-negotiable constraints |
| [docs/DATA_MODEL.md](docs/DATA_MODEL.md) | Entities, fields, enum vocabularies, relationships |
| [docs/METRICS.md](docs/METRICS.md) | Metric catalogue by group, with the phase that introduces each |
| [docs/TESTING.md](docs/TESTING.md) | Test strategy, layers, and the permanent deduplication regression test |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Architecture decision records |
