-- Company registry: the precomputed target filter.
--
-- Scored offline and occasionally (MASTER_PLAN 11). Routine ingestion only ever
-- READS this layer -- company whitelist membership must never cost an LLM call.

-- ---------------------------------------------------------------------------
-- companies
-- ---------------------------------------------------------------------------
create table companies (
    id uuid primary key default gen_random_uuid(),
    canonical_name text not null,
    domain text,

    -- Dimension scores, 0-100. Weights that combine them are configuration,
    -- not schema: there is no single permanent definition of prestige.
    prestige_score numeric(5, 2),
    compensation_score numeric(5, 2),
    technical_reputation_score numeric(5, 2),
    selectivity_score numeric(5, 2),
    internship_quality_score numeric(5, 2),
    career_value_score numeric(5, 2),
    overall_score numeric(5, 2),

    -- Derived from overall_score against a configurable threshold, but manual
    -- overrides win. The user ultimately controls the whitelist.
    target_company boolean not null default false,
    manual_override boolean not null default false,

    score_version text,
    scored_at timestamptz,
    scoring_rationale text,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint companies_canonical_name_not_blank
        check (length(trim(canonical_name)) > 0),
    constraint companies_scores_in_range check (
        coalesce(prestige_score, 0) between 0 and 100
        and coalesce(compensation_score, 0) between 0 and 100
        and coalesce(technical_reputation_score, 0) between 0 and 100
        and coalesce(selectivity_score, 0) between 0 and 100
        and coalesce(internship_quality_score, 0) between 0 and 100
        and coalesce(career_value_score, 0) between 0 and 100
        and coalesce(overall_score, 0) between 0 and 100
    )
);

-- Company identity is case-insensitive: "Meta" and "meta" are one company.
create unique index companies_canonical_name_key
    on companies (lower(canonical_name));

create unique index companies_domain_key
    on companies (lower(domain))
    where domain is not null;

-- The whitelist lookup that runs on every discovery.
create index companies_target_idx on companies (target_company)
    where target_company;

create trigger companies_set_updated_at
    before update on companies
    for each row execute function set_updated_at();

comment on table companies is
    'Precomputed target-company registry. Scored offline; routine scans only read it.';
comment on column companies.manual_override is
    'When true, target_company was set by the user and must not be recomputed from scores.';

-- ---------------------------------------------------------------------------
-- company_aliases
-- ---------------------------------------------------------------------------
-- Resolves "Meta", "Meta Platforms", and "Facebook" to one company.
create table company_aliases (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references companies (id) on delete cascade,
    alias text not null,
    created_at timestamptz not null default now(),

    constraint company_aliases_alias_not_blank
        check (length(trim(alias)) > 0)
);

-- Globally unique: an alias must resolve to exactly one company, or the
-- whitelist filter becomes ambiguous.
create unique index company_aliases_alias_key
    on company_aliases (lower(alias));

create index company_aliases_company_idx on company_aliases (company_id);

-- ---------------------------------------------------------------------------
-- company_role_aliases
-- ---------------------------------------------------------------------------
-- Company-specific title conventions. A title does not mean the same thing
-- everywhere: "Production Engineer" and "Member of Technical Staff" are
-- company-dependent (MASTER_PLAN 17, 5A).
create table company_role_aliases (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references companies (id) on delete cascade,
    title_pattern text not null,
    role_family role_family not null,
    role_subfamily text,
    confidence numeric(4, 3) not null,

    -- Provenance for the rule itself.
    source text not null,

    -- LLM output is never auto-promoted into a permanent rule; a pattern
    -- becomes an alias only after explicit approval (MASTER_PLAN 5G).
    manually_approved boolean not null default false,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint company_role_aliases_confidence_range
        check (confidence between 0 and 1),
    constraint company_role_aliases_pattern_not_blank
        check (length(trim(title_pattern)) > 0)
);

create unique index company_role_aliases_company_pattern_key
    on company_role_aliases (company_id, lower(title_pattern));

create index company_role_aliases_approved_idx
    on company_role_aliases (company_id)
    where manually_approved;

create trigger company_role_aliases_set_updated_at
    before update on company_role_aliases
    for each row execute function set_updated_at();

comment on column company_role_aliases.manually_approved is
    'Only approved rules are applied automatically. LLM suggestions land unapproved.';
