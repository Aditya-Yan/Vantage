# Metrics

Instrumentation is a product requirement, not a reporting afterthought.

## Governing rules

1. **Metrics are added in the phase that builds the stage.** Analytics are never retrofitted at the end.
2. **No metric is fabricated or estimated.** Every displayed number traces to stored data. A metric with no supporting data is not shown — it is not shown as zero either, unless zero is the true measurement.
3. **Historical aggregates survive retention cleanup.** `daily_metric_snapshots` captures values before raw discoveries or heavy payloads are purged. Snapshotted rows are not recomputed from pruned data.
4. **Business logic calls semantic methods**, never raw SQL: `metrics.scan_started(...)`, `metrics.discovery_created(...)`, `metrics.duplicate_collapsed(...)`. The metrics library owns the append-only event writes.
5. **Uncalibrated scores are not probabilities.** Confidence values are reported as what they are.
6. **Correlation, not causation.** Outcome metrics stored next to outreach data do not imply the outreach caused the outcome.

## Storage

`metric_events` is the append-only substrate (event name, entity type, entity ID, optional numeric value, metadata, timestamp). `daily_metric_snapshots` holds the durable aggregates. SQL views compute the reporting surface; a `resume_metrics` view exposes the subset suitable for external summary.

---

## Catalogue

The phase column is when the metric first has real data behind it. Infrastructure for all of them lands in Phase 2.

### Scale — introduced Phase 2 (infrastructure), populated 3 onward

| Metric | Supporting data |
| --- | --- |
| Target companies monitored | `companies.target_company` |
| Active source configurations | `source_configs.enabled` |
| Career pages monitored | `source_configs` by type |
| GitHub repositories monitored | `source_configs` by type |
| Raw postings processed | `scan_runs.items_seen` |
| Discoveries created | `discoveries` |
| Unique canonical jobs created | `jobs` |
| Qualifying jobs surfaced | `jobs` passing the relevance filter |
| Recruiters discovered | `recruiters` |
| Research tasks processed | queue + `metric_events` |
| Email drafts generated | `email_drafts` |

### Discovery — Phase 4A

| Metric | Supporting data |
| --- | --- |
| Successful scans, scan success rate | `scan_runs.status` |
| Average and p95 scan duration | `scan_runs.duration_ms` |
| Requests per scan | `scan_runs.http_requests` |
| New discoveries per scan | `scan_runs.discoveries_created` |
| Jobs discovered per source | `job_sources.source_type` |
| Source overlap | multiple `job_sources` per `job_id` |
| Median and p95 first-seen delay | `jobs.first_seen_at` − `published_at`, **only where `published_at` exists** |

### Community-source lead time — Phase 4C

Comparing official-source `first_seen_at` against community-source `first_seen_at` for the same canonical job yields median lead time versus community trackers, and the percentage detected first.

**Display only when comparable timing data actually exists.** Jobs seen by just one source class contribute nothing and must not be silently counted as wins.

### Deduplication — Phase 6

| Metric | Supporting data |
| --- | --- |
| Raw discoveries vs. canonical jobs | table counts |
| Duplicate discoveries collapsed | `job_sources` beyond the first per job |
| Duplicate suppression percentage | derived |
| Cross-source merges | distinct `source_type` per job |
| Matches by level: URL normalization, ATS ID, fingerprint, fuzzy | dedupe decision events |
| Manual false-merge corrections | correction events |
| Research calls avoided through dedupe | suppressed-trigger events |

Suppression percentage is the headline here, and it is only credible because research is triggered exclusively by new canonical jobs.

### Classification — Phase 5

| Metric | Supporting data |
| --- | --- |
| Jobs classified; accepted vs. rejected | `classifications` |
| Breakdown by method: company alias, rules, description, embedding, LLM | `classifications.method` |
| Non-LLM classification percentage | derived — a primary efficiency metric |
| LLM fallback percentage | derived |
| Average classification confidence | `classifications.confidence` |
| Manual correction rate; false-positive and false-negative corrections | `manually_corrected` |
| LLM tokens and classification cost | `llm_tokens`, `llm_cost` |

### Research — Phase 7

| Metric | Supporting data |
| --- | --- |
| Tasks enqueued, completed, success rate, retry rate | queue + events |
| Queue wait time | enqueue → dequeue |
| Median and p95 research duration | events |
| Recruiters found per job; jobs with ≥1 and ≥3 recruiters | `recruiters` per `job_id` |
| Evidence sources per recruiter | `recruiter_evidence` |
| Public LinkedIn attempted / successful / blocked-and-stopped | source outcome events |

The LinkedIn triad is an honesty metric: blocked attempts are recorded and reported, not hidden.

### Email discovery — Phase 8

| Metric | Supporting data |
| --- | --- |
| Published, inferred, and unknown coverage | `recruiters.email_status` |
| Average email-pattern evidence count | `email_patterns.example_count` |
| Average inferred-email confidence | `recruiters.email_confidence` |
| Companies with an established pattern | `email_patterns` |

Published and inferred coverage are always reported separately. Combining them into one "email coverage" figure would misrepresent inference as observation.

### Product usage — Phase 9

Jobs opened, marked applied, ignored, emailed. Detection-to-view, detection-to-application, and application-to-draft times. Percentage of qualifying jobs applied to.

### Application outcomes — optional, post-MVP

Recruiter replies and reply rate, online assessments, interviews, offers. Recorded manually by the user if at all.

### Reliability — Phase 11

Worker jobs completed and failed, retry success rate, queue backlog, oldest queue item age, source-specific error rate, HTTP rate-limit events, research-provider error rate, uptime and health checks.

### Cost and efficiency — Phase 5 onward

| Metric | Supporting data |
| --- | --- |
| Total LLM calls; calls by purpose | call events |
| Input and output tokens; estimated cost | provider usage where available |
| LLM cost per canonical job | derived |
| LLM cost per research task | derived |
| Classification calls avoided through deterministic routing | derived from method distribution |
| Duplicate research calls avoided | dedupe suppression events |

Cost is recorded from reported provider usage. Where a provider does not report tokens, the fields stay null rather than being estimated.

---

## The `/metrics` page — Phase 9

Groups: Scale, Discovery, Classification, Deduplication, Research, Email Coverage, Reliability, Cost, User/Application. Live values from actual data.

## Resume-metric mode — Phase 12

A dedicated view surfaces candidate summary bullets built **only** from measured values. Templates exist; numbers are never populated unless traceable to stored metrics. If the underlying data does not support a bullet, that bullet does not appear.
