-- Metrics substrate, resume-metric views, and research queue infrastructure.
--
-- Metrics are a product feature, not reporting afterthought. Two rules are
-- structural here:
--   1. metric_events is append-only. Nothing updates or deletes a measurement.
--   2. daily_metric_snapshots preserves aggregates so history survives the
--      raw-payload purge and feed-retention cleanup (MASTER_PLAN 7, 29).

-- ---------------------------------------------------------------------------
-- metric_events
-- ---------------------------------------------------------------------------
create table metric_events (
    id bigint generated always as identity primary key,
    event_name text not null,
    entity_type text,
    entity_id uuid,
    numeric_value numeric(18, 6),
    metadata_json jsonb not null default '{}'::jsonb,
    occurred_at timestamptz not null default now(),

    constraint metric_events_name_not_blank check (length(trim(event_name)) > 0)
);

create index metric_events_name_time_idx on metric_events (event_name, occurred_at desc);
create index metric_events_entity_idx on metric_events (entity_type, entity_id);
create index metric_events_time_idx on metric_events (occurred_at desc);

comment on table metric_events is
    'Append-only instrumentation. Written through the metrics service, never by ad-hoc SQL from business logic.';

-- Append-only is enforced, not merely intended: a measurement that can be
-- edited after the fact is not a measurement.
create or replace function reject_metric_event_mutation()
returns trigger
language plpgsql
as $$
begin
    raise exception 'metric_events is append-only (attempted %)', tg_op;
end;
$$;

create trigger metric_events_no_update
    before update or delete on metric_events
    for each row execute function reject_metric_event_mutation();

-- ---------------------------------------------------------------------------
-- daily_metric_snapshots
-- ---------------------------------------------------------------------------
-- Once a day is snapshotted, that row is never recomputed from data that may
-- since have been pruned.
create table daily_metric_snapshots (
    id bigint generated always as identity primary key,
    snapshot_date date not null,
    metric_name text not null,
    metric_value numeric(18, 6) not null,
    metadata_json jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),

    constraint daily_metric_snapshots_date_metric_key
        unique (snapshot_date, metric_name)
);

create index daily_metric_snapshots_metric_idx
    on daily_metric_snapshots (metric_name, snapshot_date desc);

-- ---------------------------------------------------------------------------
-- resume_metrics view
-- ---------------------------------------------------------------------------
-- Counts of what actually exists. On an empty system every value is 0 -- that
-- is a true measurement, not a placeholder. Derived rates that would divide by
-- zero return NULL rather than a fabricated 0%: "no data yet" and "0%" are
-- different claims, and only one of them is honest here.
create view resume_metrics as
with counts as (
    select
        (select count(*) from companies) as total_companies,
        (select count(*) from companies where target_company)
            as target_companies,
        (select count(*) from source_configs where enabled)
            as active_source_configs,
        (select count(*) from scan_runs) as total_scans,
        (select count(*) from scan_runs where status = 'SUCCESS')
            as successful_scans,
        (select count(*) from discoveries) as total_discoveries,
        (select count(*) from jobs) as total_canonical_jobs,
        (select count(*) from jobs where archived_at is null)
            as active_jobs,
        (select count(*) from job_sources) as total_job_sources,
        (select count(*) from classifications) as total_classifications,
        (select count(*) from classifications where method <> 'LLM_FALLBACK')
            as non_llm_classifications,
        (select count(*) from classifications where method = 'LLM_FALLBACK')
            as llm_classifications,
        (select count(*) from recruiters) as total_recruiters,
        (select count(*) from recruiters where email_status = 'PUBLISHED')
            as recruiters_published_email,
        (select count(*) from recruiters where email_status = 'INFERRED')
            as recruiters_inferred_email,
        (select count(*) from recruiters where research_status = 'COMPLETED')
            as completed_research_tasks,
        (select count(*) from email_drafts) as total_email_drafts,
        (select coalesce(sum(llm_cost), 0) from classifications)
            as classification_llm_cost
)
select
    total_companies,
    target_companies,
    active_source_configs,
    total_scans,
    successful_scans,
    total_discoveries,
    total_canonical_jobs,
    active_jobs,
    total_job_sources,

    -- Duplicate discoveries collapsed: sources attached beyond the first per
    -- job. Zero when nothing has been ingested.
    greatest(total_job_sources - total_canonical_jobs, 0)
        as duplicates_collapsed,

    total_classifications,
    non_llm_classifications,
    llm_classifications,
    total_recruiters,
    recruiters_published_email,
    recruiters_inferred_email,
    completed_research_tasks,
    total_email_drafts,
    classification_llm_cost,

    -- NULL until there is something to divide by.
    case when total_scans > 0
        then round(100.0 * successful_scans / total_scans, 2)
    end as scan_success_pct,
    case when total_classifications > 0
        then round(100.0 * non_llm_classifications / total_classifications, 2)
    end as non_llm_classification_pct,
    case when total_job_sources > 0
        then round(100.0 * greatest(total_job_sources - total_canonical_jobs, 0)
                   / total_job_sources, 2)
    end as duplicate_suppression_pct,
    case when total_recruiters > 0
        then round(100.0 * recruiters_published_email / total_recruiters, 2)
    end as published_email_coverage_pct,
    case when total_recruiters > 0
        then round(100.0 * recruiters_inferred_email / total_recruiters, 2)
    end as inferred_email_coverage_pct
from counts;

comment on view resume_metrics is
    'Counts traceable to stored data. Rates are NULL when the denominator is zero -- "no data yet" is not "0%".';

-- ---------------------------------------------------------------------------
-- Snapshot function
-- ---------------------------------------------------------------------------
-- Captures today's resume_metrics counts durably. Phase 11 schedules it daily;
-- nothing calls it automatically yet. Idempotent: re-running the same day
-- overwrites that day's row rather than erroring or duplicating.
create or replace function capture_daily_metric_snapshot(
    p_snapshot_date date default current_date
)
returns integer
language plpgsql
as $$
declare
    v_row jsonb;
    v_key text;
    v_value jsonb;
    v_count integer := 0;
begin
    select to_jsonb(rm) into v_row from resume_metrics rm;

    for v_key, v_value in select * from jsonb_each(v_row)
    loop
        -- Skip NULL rates: an absent measurement must not be snapshotted as 0.
        if v_value is not null and jsonb_typeof(v_value) = 'number' then
            insert into daily_metric_snapshots
                (snapshot_date, metric_name, metric_value)
            values
                (p_snapshot_date, v_key, (v_value #>> '{}')::numeric)
            on conflict (snapshot_date, metric_name)
                do update set metric_value = excluded.metric_value,
                              created_at = now();
            v_count := v_count + 1;
        end if;
    end loop;

    return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- Research queue (pgmq)
-- ---------------------------------------------------------------------------
-- Prepared here, consumed in Phase 6. Only the insertion of a genuinely NEW
-- canonical job may enqueue a task, and exactly one.
create extension if not exists pgmq;

select pgmq.create('research_tasks');

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------
-- Deny by default now; the worker connects with the service role and bypasses
-- RLS. UI policies arrive in Phase 9, full review in Phase 12D (ADR-015).
alter table companies enable row level security;
alter table company_aliases enable row level security;
alter table company_role_aliases enable row level security;
alter table source_configs enable row level security;
alter table scan_runs enable row level security;
alter table discoveries enable row level security;
alter table jobs enable row level security;
alter table job_sources enable row level security;
alter table classifications enable row level security;
alter table recruiters enable row level security;
alter table recruiter_evidence enable row level security;
alter table email_patterns enable row level security;
alter table applications enable row level security;
alter table email_drafts enable row level security;
alter table metric_events enable row level security;
alter table daily_metric_snapshots enable row level security;
