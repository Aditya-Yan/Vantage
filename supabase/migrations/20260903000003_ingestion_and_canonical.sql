-- Ingestion and canonical job layer.
--
-- The load-bearing property of this migration: discoveries are MANY, jobs are
-- ONE. job_sources is the bridge. The unique constraints here are what make
-- "3 discoveries -> 1 canonical job -> 1 research task" hold under concurrent
-- ingestion, which application-layer checks alone cannot guarantee.

-- ---------------------------------------------------------------------------
-- source_configs
-- ---------------------------------------------------------------------------
create table source_configs (
    id uuid primary key default gen_random_uuid(),

    -- Nullable: community trackers span many companies.
    company_id uuid references companies (id) on delete cascade,

    source_type source_type not null,
    source_identifier text not null,
    url text,
    poll_interval_minutes integer not null default 15,
    enabled boolean not null default true,

    -- Per-source settings: GitHub extraction strategy, subreddit list, etc.
    config_json jsonb not null default '{}'::jsonb,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint source_configs_poll_interval_positive
        check (poll_interval_minutes > 0),
    constraint source_configs_identifier_not_blank
        check (length(trim(source_identifier)) > 0)
);

-- One config per (type, identifier): re-registering the same Greenhouse board
-- must not create a second source that would double every discovery.
create unique index source_configs_type_identifier_key
    on source_configs (source_type, lower(source_identifier));

create index source_configs_enabled_idx on source_configs (enabled)
    where enabled;
create index source_configs_company_idx on source_configs (company_id);

create trigger source_configs_set_updated_at
    before update on source_configs
    for each row execute function set_updated_at();

-- ---------------------------------------------------------------------------
-- scan_runs
-- ---------------------------------------------------------------------------
-- One row per poll attempt. The basis of every discovery and reliability
-- metric, so failures are recorded here rather than only logged.
create table scan_runs (
    id uuid primary key default gen_random_uuid(),
    source_config_id uuid not null references source_configs (id) on delete cascade,
    started_at timestamptz not null default now(),
    finished_at timestamptz,
    status scan_status not null default 'RUNNING',
    items_seen integer not null default 0,
    discoveries_created integer not null default 0,
    http_requests integer not null default 0,
    error_type text,
    error_message text,
    duration_ms integer,

    constraint scan_runs_counts_non_negative check (
        items_seen >= 0
        and discoveries_created >= 0
        and http_requests >= 0
        and coalesce(duration_ms, 0) >= 0
    ),
    -- A finished scan must say when. An unfinished one must not.
    constraint scan_runs_finished_consistent check (
        (status = 'RUNNING' and finished_at is null)
        or (status <> 'RUNNING' and finished_at is not null)
    )
);

create index scan_runs_source_started_idx
    on scan_runs (source_config_id, started_at desc);
create index scan_runs_status_idx on scan_runs (status, started_at desc);

-- ---------------------------------------------------------------------------
-- jobs  (created before discoveries: discoveries reference it)
-- ---------------------------------------------------------------------------
-- Exactly one row per real opening.
create table jobs (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references companies (id) on delete restrict,

    -- Exactly as published, from the most authoritative source among the
    -- merged discoveries. NEVER overwritten with a normalized display title
    -- (MASTER_PLAN 0.15). Classification lives in the adjacent columns.
    raw_title text not null,

    role_family role_family,
    role_subfamily text,
    classification_confidence numeric(4, 3),
    classification_method classification_method,

    location text,
    compensation_min numeric(12, 2),
    compensation_max numeric(12, 2),
    compensation_currency text,
    compensation_period text,

    application_url text,

    -- Dedupe Level 1: trusted external posting identity.
    ats_type source_type,
    ats_job_id text,

    published_at timestamptz,
    first_seen_at timestamptz not null default now(),
    last_seen_at timestamptz not null default now(),

    -- Three-day feed policy (MASTER_PLAN 29). Archival, never deletion.
    visibility_expires_at timestamptz,
    archived_at timestamptz,

    research_status research_status not null default 'NOT_STARTED',

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint jobs_raw_title_not_blank check (length(trim(raw_title)) > 0),
    constraint jobs_confidence_range
        check (classification_confidence is null
               or classification_confidence between 0 and 1),
    constraint jobs_compensation_ordered check (
        compensation_min is null
        or compensation_max is null
        or compensation_min <= compensation_max
    ),
    -- An ATS identity is only usable as a dedupe key when both halves exist.
    constraint jobs_ats_identity_complete check (
        (ats_type is null and ats_job_id is null)
        or (ats_type is not null and ats_job_id is not null)
    )
);

-- Dedupe Level 1 -- trusted external posting identity. This constraint, not
-- application code, is what prevents two canonical jobs when Greenhouse and a
-- GitHub tracker report the same posting concurrently.
create unique index jobs_ats_identity_key
    on jobs (ats_type, ats_job_id)
    where ats_type is not null and ats_job_id is not null;

-- Dedupe Level 2 -- canonicalized official application URL.
create unique index jobs_application_url_key
    on jobs (application_url)
    where application_url is not null;

-- Level 3 (deterministic fingerprint) is deliberately absent: it encodes
-- normalization rules that do not exist until Phase 6 (ADR-017).

create index jobs_company_idx on jobs (company_id);
create index jobs_feed_idx on jobs (first_seen_at desc)
    where archived_at is null;
create index jobs_research_status_idx on jobs (research_status)
    where research_status <> 'COMPLETED';
create index jobs_role_family_idx on jobs (role_family);

create trigger jobs_set_updated_at
    before update on jobs
    for each row execute function set_updated_at();

comment on table jobs is
    'Exactly one row per real opening. Insertion here -- and only here -- may enqueue recruiter research.';
comment on column jobs.raw_title is
    'The published title, verbatim. Never replaced with a normalized display title.';

-- ---------------------------------------------------------------------------
-- discoveries
-- ---------------------------------------------------------------------------
-- Every observation from every source, preserved raw.
create table discoveries (
    id uuid primary key default gen_random_uuid(),
    source_config_id uuid not null references source_configs (id) on delete cascade,
    scan_run_id uuid references scan_runs (id) on delete set null,

    external_source_id text,

    raw_company text,
    raw_title text not null,
    raw_description text,
    raw_location text,
    raw_compensation text,
    raw_url text,
    canonicalized_url text,

    published_at timestamptz,
    discovered_at timestamptz not null default now(),
    source_confidence numeric(4, 3),
    verification_status verification_status not null default 'NOT_REQUIRED',

    -- Original response. Subject to its own retention policy (MASTER_PLAN 29).
    payload_json jsonb,

    -- Set only on successful canonicalization. A discovery that fails
    -- filtering, classification, or verification never acquires one.
    canonical_job_id uuid references jobs (id) on delete set null,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint discoveries_raw_title_not_blank
        check (length(trim(raw_title)) > 0),
    constraint discoveries_source_confidence_range
        check (source_confidence is null or source_confidence between 0 and 1),
    -- Something must identify the observation, or re-scanning cannot be
    -- idempotent.
    constraint discoveries_identifiable
        check (external_source_id is not null or canonicalized_url is not null)
);

-- Idempotent ingestion, primary key path: re-observing the same posting from
-- the same source updates rather than inserts.
create unique index discoveries_source_external_id_key
    on discoveries (source_config_id, external_source_id)
    where external_source_id is not null;

-- Fallback for sources with no stable external ID.
create unique index discoveries_source_url_key
    on discoveries (source_config_id, canonicalized_url)
    where external_source_id is null and canonicalized_url is not null;

create index discoveries_canonical_job_idx on discoveries (canonical_job_id);
create index discoveries_scan_run_idx on discoveries (scan_run_id);
create index discoveries_unverified_idx
    on discoveries (verification_status, discovered_at)
    where verification_status = 'PENDING';

create trigger discoveries_set_updated_at
    before update on discoveries
    for each row execute function set_updated_at();

comment on table discoveries is
    'Raw source observations. A discovery NEVER directly triggers recruiter research.';

-- ---------------------------------------------------------------------------
-- job_sources
-- ---------------------------------------------------------------------------
-- Many discoveries support one job. Source overlap and community lead-time
-- metrics are derived from this table.
create table job_sources (
    id uuid primary key default gen_random_uuid(),
    job_id uuid not null references jobs (id) on delete cascade,
    discovery_id uuid not null references discoveries (id) on delete cascade,
    source_type source_type not null,
    source_url text,
    external_source_id text,
    first_seen_at timestamptz not null default now(),

    -- A discovery attaches to a job exactly once. Re-running ingestion must
    -- not inflate the overlap metrics.
    constraint job_sources_job_discovery_key unique (job_id, discovery_id)
);

-- One discovery supports at most one canonical job.
create unique index job_sources_discovery_key on job_sources (discovery_id);

create index job_sources_job_idx on job_sources (job_id);
create index job_sources_type_idx on job_sources (source_type);

-- ---------------------------------------------------------------------------
-- classifications
-- ---------------------------------------------------------------------------
-- The audit trail. Retained so decisions can be reviewed and the Phase 12
-- evaluation set can be built from real history.
create table classifications (
    id uuid primary key default gen_random_uuid(),

    job_id uuid references jobs (id) on delete cascade,
    discovery_id uuid references discoveries (id) on delete cascade,

    role_family role_family not null,
    role_subfamily text,
    confidence numeric(4, 3) not null,
    method classification_method not null,

    -- The signals that drove the decision.
    feature_summary_json jsonb not null default '{}'::jsonb,

    llm_model text,
    llm_tokens integer,
    llm_cost numeric(10, 6),

    manually_corrected boolean not null default false,
    created_at timestamptz not null default now(),

    constraint classifications_confidence_range check (confidence between 0 and 1),
    -- A classification must describe something.
    constraint classifications_has_subject
        check (job_id is not null or discovery_id is not null),
    -- Cost accounting only makes sense for LLM classifications.
    constraint classifications_llm_fields_consistent check (
        method = 'LLM_FALLBACK'
        or (llm_model is null and llm_tokens is null and llm_cost is null)
    ),
    constraint classifications_llm_usage_non_negative check (
        coalesce(llm_tokens, 0) >= 0 and coalesce(llm_cost, 0) >= 0
    )
);

create index classifications_job_idx on classifications (job_id);
create index classifications_discovery_idx on classifications (discovery_id);
-- Drives the "classified without an LLM" metric.
create index classifications_method_idx on classifications (method, created_at desc);
