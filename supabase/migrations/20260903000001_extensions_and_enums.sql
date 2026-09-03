-- Extensions and enum vocabularies.
--
-- These vocabularies are fixed by docs/DATA_MODEL.md. Adding a value is a
-- decision-record-worthy change; native enums are used (ADR-016) so invalid
-- values are rejected at write time rather than discovered later in a report.

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Role classification
-- ---------------------------------------------------------------------------
-- Which families are TARGETED is configuration, kept separate from which
-- family a job IS. This type answers only the latter.
create type role_family as enum (
    'SOFTWARE_ENGINEERING',
    'ML_ENGINEERING',
    'DATA_ENGINEERING',
    'QUANT_DEVELOPMENT',
    'DATA_SCIENCE',
    'SECURITY_ENGINEERING',
    'SRE_INFRASTRUCTURE',
    'HARDWARE',
    'ELECTRICAL_ENGINEERING',
    'MECHANICAL_ENGINEERING',
    'PRODUCT',
    'IT',
    'OTHER'
);

-- Which stage of the classification ladder decided. Drives the
-- "classified without an LLM" metric, so the distinction is load-bearing.
create type classification_method as enum (
    'COMPANY_ALIAS',
    'DETERMINISTIC_RULES',
    'DESCRIPTION_SIGNALS',
    'EMBEDDING',
    'LLM_FALLBACK',
    'MANUAL'
);

-- ---------------------------------------------------------------------------
-- Ingestion
-- ---------------------------------------------------------------------------
-- Reddit and other unofficial discoveries begin PENDING and require a match to
-- an official ATS posting or careers page before canonicalization eligibility
-- (MASTER_PLAN 15). Only VERIFIED continues.
create type verification_status as enum (
    'PENDING',
    'VERIFIED',
    'REJECTED',
    -- Official ATS sources need no verification step.
    'NOT_REQUIRED'
);

create type source_type as enum (
    'GREENHOUSE',
    'LEVER',
    'ASHBY',
    'GITHUB_TRACKER',
    'REDDIT',
    'CAREER_PAGE',
    'OTHER'
);

create type scan_status as enum (
    'RUNNING',
    'SUCCESS',
    'FAILED',
    'PARTIAL'
);

create type research_status as enum (
    'NOT_STARTED',
    'QUEUED',
    'IN_PROGRESS',
    'COMPLETED',
    'FAILED'
);

-- ---------------------------------------------------------------------------
-- Recruiters
-- ---------------------------------------------------------------------------
-- An inferred address is never described as guaranteed, and syntax or domain
-- validation never promotes INFERRED to PUBLISHED (MASTER_PLAN 20).
create type email_status as enum (
    'PUBLISHED',
    'INFERRED',
    'UNKNOWN'
);

-- Class-year specificity is never invented; absent explicit support the value
-- stays UNKNOWN (MASTER_PLAN 19).
create type candidate_scope as enum (
    'UNDERGRADUATE',
    'UNIVERSITY',
    'INTERN',
    'NEW_GRAD',
    'MASTERS',
    'MBA',
    'EXPERIENCED',
    'UNKNOWN'
);

-- ---------------------------------------------------------------------------
-- Applications
-- ---------------------------------------------------------------------------
create type application_status as enum (
    'NOT_APPLIED',
    'APPLIED_NOT_EMAILED',
    'APPLIED_EMAILED',
    'IGNORED'
);

-- ---------------------------------------------------------------------------
-- Shared trigger: keep updated_at honest
-- ---------------------------------------------------------------------------
create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;
