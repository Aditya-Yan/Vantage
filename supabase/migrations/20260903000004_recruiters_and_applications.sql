-- Recruiter research, email discovery, applications, and outreach drafts.
--
-- The governing rule in this layer: a fact does not exist merely because a
-- model asserted it. Important recruiter facts carry provenance in
-- recruiter_evidence, and unknown information stays UNKNOWN.

-- ---------------------------------------------------------------------------
-- recruiters
-- ---------------------------------------------------------------------------
create table recruiters (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references companies (id) on delete cascade,

    name text not null,
    title text,
    location text,
    discipline text[] not null default '{}',
    candidate_scope candidate_scope[] not null default '{}',
    profile_url text,

    email text,
    email_status email_status not null default 'UNKNOWN',
    email_confidence numeric(4, 3),

    -- Computed by code from extracted facts, never chosen by a model
    -- (MASTER_PLAN 20). The breakdown is stored so the UI can explain rankings.
    relevance_score numeric(6, 2),
    score_breakdown_json jsonb not null default '{}'::jsonb,

    research_status research_status not null default 'NOT_STARTED',
    first_found_at timestamptz not null default now(),
    last_verified_at timestamptz,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint recruiters_name_not_blank check (length(trim(name)) > 0),
    constraint recruiters_email_confidence_range
        check (email_confidence is null or email_confidence between 0 and 1),
    -- UNKNOWN means unknown: no address, no confidence. And a known status
    -- must actually carry an address.
    constraint recruiters_email_status_consistent check (
        (email_status = 'UNKNOWN' and email is null and email_confidence is null)
        or (email_status <> 'UNKNOWN' and email is not null)
    )
);

-- Idempotent research: re-running for the same job must not duplicate people.
create unique index recruiters_company_profile_key
    on recruiters (company_id, lower(profile_url))
    where profile_url is not null;

-- Fallback identity when no public profile URL was found.
create unique index recruiters_company_name_title_key
    on recruiters (company_id, lower(name), lower(coalesce(title, '')))
    where profile_url is null;

create index recruiters_company_idx on recruiters (company_id);
create index recruiters_ranking_idx
    on recruiters (company_id, relevance_score desc nulls last);
create index recruiters_email_status_idx on recruiters (email_status);

create trigger recruiters_set_updated_at
    before update on recruiters
    for each row execute function set_updated_at();

comment on column recruiters.email_status is
    'PUBLISHED / INFERRED / UNKNOWN. An inferred address is never presented as guaranteed.';
comment on column recruiters.relevance_score is
    'Deterministic arithmetic over extracted facts. An LLM never chooses ordering.';

-- ---------------------------------------------------------------------------
-- recruiter_evidence
-- ---------------------------------------------------------------------------
-- Every important recruiter fact carries a source. Facts requiring evidence:
-- current company, current title, recruiting discipline, candidate scope, and
-- location where relevant (MASTER_PLAN 19).
create table recruiter_evidence (
    id uuid primary key default gen_random_uuid(),
    recruiter_id uuid not null references recruiters (id) on delete cascade,

    source_url text not null,
    source_type text not null,
    fact_type text not null,
    fact_value text not null,
    confidence numeric(4, 3) not null,
    retrieved_at timestamptz not null default now(),

    constraint recruiter_evidence_confidence_range check (confidence between 0 and 1),
    constraint recruiter_evidence_source_url_not_blank
        check (length(trim(source_url)) > 0)
);

-- The same fact from the same source is one piece of evidence, not two.
create unique index recruiter_evidence_dedupe_key
    on recruiter_evidence (recruiter_id, fact_type, lower(source_url));

create index recruiter_evidence_recruiter_idx on recruiter_evidence (recruiter_id);

comment on table recruiter_evidence is
    'Provenance for recruiter facts. A fact asserted by a model with no source is not stored as fact.';

-- ---------------------------------------------------------------------------
-- email_patterns
-- ---------------------------------------------------------------------------
-- Company-level address-format evidence, used to justify INFERRED emails.
create table email_patterns (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references companies (id) on delete cascade,

    pattern text not null,
    example_count integer not null default 0,

    -- Confidence must reflect BOTH how many examples were seen and how many
    -- independent sources they came from (MASTER_PLAN 20).
    independent_source_count integer not null default 0,
    confidence numeric(4, 3) not null default 0,

    last_updated_at timestamptz not null default now(),
    created_at timestamptz not null default now(),

    constraint email_patterns_confidence_range check (confidence between 0 and 1),
    constraint email_patterns_counts_non_negative
        check (example_count >= 0 and independent_source_count >= 0),
    constraint email_patterns_sources_not_exceeding_examples
        check (independent_source_count <= example_count)
);

create unique index email_patterns_company_pattern_key
    on email_patterns (company_id, lower(pattern));

-- ---------------------------------------------------------------------------
-- applications
-- ---------------------------------------------------------------------------
create table applications (
    id uuid primary key default gen_random_uuid(),

    -- One application record per job.
    job_id uuid not null unique references jobs (id) on delete cascade,

    status application_status not null default 'NOT_APPLIED',
    applied_at timestamptz,
    emailed_at timestamptz,
    ignored_at timestamptz,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    -- State and timestamps must agree. These are pure state transitions and
    -- must never require an LLM to validate.
    constraint applications_status_timestamps_consistent check (
        (status = 'NOT_APPLIED'
            and applied_at is null and emailed_at is null and ignored_at is null)
        or (status = 'APPLIED_NOT_EMAILED'
            and applied_at is not null and emailed_at is null)
        or (status = 'APPLIED_EMAILED'
            and applied_at is not null and emailed_at is not null)
        or (status = 'IGNORED' and ignored_at is not null)
    )
);

create index applications_status_idx on applications (status);

create trigger applications_set_updated_at
    before update on applications
    for each row execute function set_updated_at();

-- ---------------------------------------------------------------------------
-- email_drafts
-- ---------------------------------------------------------------------------
-- Generated on demand and stored. Nothing here records a "sent" state,
-- because the system does not send (MASTER_PLAN 22).
create table email_drafts (
    id uuid primary key default gen_random_uuid(),
    job_id uuid not null references jobs (id) on delete cascade,
    recruiter_id uuid not null references recruiters (id) on delete cascade,

    resume_version text,
    subject text not null,
    body text not null,

    model text not null,
    prompt_version text not null,
    input_tokens integer,
    output_tokens integer,
    estimated_cost numeric(10, 6),

    created_at timestamptz not null default now(),

    constraint email_drafts_subject_not_blank check (length(trim(subject)) > 0),
    constraint email_drafts_body_not_blank check (length(trim(body)) > 0),
    constraint email_drafts_usage_non_negative check (
        coalesce(input_tokens, 0) >= 0
        and coalesce(output_tokens, 0) >= 0
        and coalesce(estimated_cost, 0) >= 0
    )
);

create index email_drafts_job_idx on email_drafts (job_id, created_at desc);
create index email_drafts_recruiter_idx on email_drafts (recruiter_id);
