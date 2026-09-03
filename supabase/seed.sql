-- Development seed data.
--
-- A small, representative slice for local development and integration tests.
-- Phase 3 builds the real company registry through the offline scoring
-- pipeline; these scores are HAND-WRITTEN PLACEHOLDERS, not measurements, and
-- must not be presented as scoring output. score_version records that.
--
-- Loaded automatically by `supabase db reset`.

-- ---------------------------------------------------------------------------
-- Companies
-- ---------------------------------------------------------------------------
-- Chosen to exercise the cases the pipeline must handle: multi-alias
-- identities, a company whose engineering titles are non-standard, and one
-- below any plausible target threshold so the whitelist filter has something
-- to exclude.
insert into companies (
    canonical_name, domain,
    prestige_score, compensation_score, technical_reputation_score,
    selectivity_score, internship_quality_score, career_value_score,
    overall_score, target_company, score_version, scored_at
) values
    ('Meta', 'meta.com',
     95, 95, 92, 90, 93, 94, 93.2, true, 'seed-placeholder', now()),
    ('Stripe', 'stripe.com',
     92, 93, 95, 93, 90, 92, 92.5, true, 'seed-placeholder', now()),
    ('Anthropic', 'anthropic.com',
     94, 92, 96, 95, 88, 93, 93.0, true, 'seed-placeholder', now()),
    ('Ramp', 'ramp.com',
     80, 85, 84, 82, 78, 81, 81.6, true, 'seed-placeholder', now()),
    -- Below threshold: exercises exclusion.
    ('Example Staffing Co', 'example-staffing.test',
     20, 25, 15, 20, 18, 19, 19.4, false, 'seed-placeholder', now());

-- ---------------------------------------------------------------------------
-- Aliases
-- ---------------------------------------------------------------------------
-- One posting may name the employer any of these ways.
insert into company_aliases (company_id, alias)
select id, alias
from companies
cross join lateral (values ('Meta Platforms'), ('Facebook'), ('FB')) as a (alias)
where canonical_name = 'Meta';

insert into company_aliases (company_id, alias)
select id, 'Stripe, Inc.' from companies where canonical_name = 'Stripe';

insert into company_aliases (company_id, alias)
select id, 'Anthropic PBC' from companies where canonical_name = 'Anthropic';

-- ---------------------------------------------------------------------------
-- Company-specific role aliases
-- ---------------------------------------------------------------------------
-- Real titles that do not contain "Software Engineer" but are SWE roles at
-- these specific companies. This is exactly the case Phase 5 must not miss.
insert into company_role_aliases (
    company_id, title_pattern, role_family, role_subfamily,
    confidence, source, manually_approved
)
select id, 'Production Engineer', 'SOFTWARE_ENGINEERING', 'infrastructure',
       0.950, 'seed:known-convention', true
from companies where canonical_name = 'Meta';

insert into company_role_aliases (
    company_id, title_pattern, role_family, role_subfamily,
    confidence, source, manually_approved
)
select id, 'Member of Technical Staff', 'SOFTWARE_ENGINEERING', 'general',
       0.900, 'seed:known-convention', true
from companies where canonical_name = 'Anthropic';

-- ---------------------------------------------------------------------------
-- Source configs
-- ---------------------------------------------------------------------------
-- Disabled: Phase 4A implements the adapters that would poll them. Enabling a
-- source before its adapter exists would produce failed scans, not data.
insert into source_configs (
    company_id, source_type, source_identifier, url,
    poll_interval_minutes, enabled
)
select id, 'GREENHOUSE', 'stripe', 'https://boards.greenhouse.io/stripe', 15, false
from companies where canonical_name = 'Stripe';

insert into source_configs (
    company_id, source_type, source_identifier, url,
    poll_interval_minutes, enabled
)
select id, 'LEVER', 'ramp', 'https://jobs.lever.co/ramp', 15, false
from companies where canonical_name = 'Ramp';

-- A community tracker spans many companies, so it has no company_id.
insert into source_configs (
    company_id, source_type, source_identifier, url,
    poll_interval_minutes, enabled, config_json
) values (
    null, 'GITHUB_TRACKER', 'SimplifyJobs/Summer2026-Internships',
    'https://github.com/SimplifyJobs/Summer2026-Internships',
    15, false,
    '{"extraction_strategy": "readme_table"}'::jsonb
);

-- No discoveries, jobs, recruiters, or metric events are seeded. Those must
-- come from the pipeline, so that every count in resume_metrics traces to real
-- system activity rather than to fixtures.
