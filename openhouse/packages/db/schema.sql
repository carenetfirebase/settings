-- =============================================================================
-- OPENHOUSE AI — Phase 1 schema
-- Postgres 15 / Supabase.  Extensions: pgvector, pg_trgm, pgcrypto.
-- RLS is enabled on every table.  Nothing here is reachable with the anon key
-- except by explicit policy; visitor-facing reads go through server route
-- handlers that apply a public projection, and RLS is defence in depth.
--
-- Architecture doc: §6 (schema), §2 (roles), §14 (privacy/security).
-- =============================================================================

create extension if not exists "pgcrypto";
create extension if not exists "vector";
create extension if not exists "pg_trgm";

-- -----------------------------------------------------------------------------
-- 0. Enumerated domains
--
-- These are Postgres enums rather than check constraints because they are
-- referenced from generated TypeScript types; adding a value is a migration,
-- which is the friction we want on a vocabulary the Truth Engine branches on.
-- -----------------------------------------------------------------------------

create type org_role            as enum ('member', 'admin', 'owner');

create type property_type       as enum (
  'detached', 'semi_detached', 'townhouse', 'condo_apartment',
  'condo_townhouse', 'duplex', 'mobile', 'land', 'other');

create type property_status     as enum ('draft', 'published', 'unpublished', 'archived');

create type fact_data_type      as enum (
  'year', 'text', 'enum', 'number', 'boolean', 'money', 'dimension', 'date');

create type fact_visibility     as enum ('public', 'agent_only');

create type claim_source_type   as enum (
  'agent_input', 'document', 'mls', 'seller_disclosure',
  'public_data', 'ai_extraction');

create type claim_status        as enum ('pending', 'accepted', 'rejected', 'superseded');

create type fact_status         as enum (
  'verified', 'unknown', 'not_applicable', 'pending_review', 'conflicted');

create type verification_level  as enum (
  'agent_confirmed', 'document_verified', 'seller_provided',
  'agent_commentary', 'public_source');

create type unknown_reason      as enum (
  'seller_does_not_know', 'no_documentation', 'not_applicable', 'will_follow_up');

create type conflict_severity   as enum ('soft', 'hard');

create type conflict_status     as enum ('open', 'resolved', 'obsolete');

create type document_type       as enum (
  'mls_sheet', 'seller_disclosure', 'invoice', 'permit', 'floor_plan',
  'tax_statement', 'survey', 'condo_documents', 'warranty',
  'inspection_report', 'title', 'other');

create type document_status     as enum (
  'uploaded', 'classifying', 'extracting_text', 'chunking',
  'extracting_facts', 'ready', 'failed');

create type commentary_scope    as enum ('property', 'room', 'feature');

create type commentary_author   as enum ('agent', 'seller');

create type inclusion_kind      as enum ('included', 'excluded', 'negotiable');

create type audio_mode          as enum ('private', 'group', 'silent');

create type tour_mode           as enum ('quick', 'full', 'explore');

create type session_state       as enum ('active', 'paused', 'ended');

create type retrieval_path      as enum (
  'structured', 'document', 'commentary', 'public', 'unknown', 'boundary_refusal');

create type lead_action_type    as enum (
  'showing_requested', 'documents_requested', 'agent_contact_requested',
  'property_saved', 'property_shared', 'contact_submitted');

create type access_tag_kind     as enum ('qr', 'nfc');

create type question_state      as enum ('open', 'answered', 'dismissed');

-- -----------------------------------------------------------------------------
-- 1. Helper functions used by policies
--
-- Defined before the tables so every policy below can lean on them.  They are
-- security definer and pinned to an empty search_path: a policy helper that can
-- be shadowed by a caller-controlled search_path is an authentication bypass.
-- -----------------------------------------------------------------------------

create or replace function app_current_agent() returns uuid
  language sql stable as $$ select auth.uid() $$;

create table if not exists organizations (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  slug          text not null unique,
  brand         jsonb not null default '{}'::jsonb,   -- accent colour, logo path
  created_at    timestamptz not null default now()
);

-- profiles mirrors auth.users; Supabase convention.
create table if not exists profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  full_name     text,
  email         text,
  phone         text,
  license_number text,
  brokerage     text,
  headshot_path text,
  brand         jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now()
);

create table if not exists org_memberships (
  org_id        uuid not null references organizations(id) on delete cascade,
  agent_id      uuid not null references profiles(id) on delete cascade,
  role          org_role not null default 'member',
  created_at    timestamptz not null default now(),
  primary key (org_id, agent_id)
);
create index on org_memberships (agent_id);

create or replace function app_is_org_member(target_org uuid) returns boolean
  language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.org_memberships m
    where m.org_id = target_org and m.agent_id = auth.uid())
$$;

create or replace function app_is_org_admin(target_org uuid) returns boolean
  language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.org_memberships m
    where m.org_id = target_org and m.agent_id = auth.uid()
      and m.role in ('admin', 'owner'))
$$;

-- -----------------------------------------------------------------------------
-- 2. Properties
-- -----------------------------------------------------------------------------

create table if not exists properties (
  id                uuid primary key default gen_random_uuid(),
  org_id            uuid references organizations(id) on delete set null,
  agent_id          uuid not null references profiles(id) on delete restrict,
  slug              text not null unique,
  status            property_status not null default 'draft',

  address_line1     text not null,
  address_line2     text,
  city              text not null,
  province          text not null,
  postal_code       text,
  country           text not null default 'CA',
  latitude          double precision,
  longitude         double precision,

  property_type     property_type not null,
  list_price        numeric(12,2),
  bedrooms          integer,
  bathrooms         numeric(3,1),
  living_area_sqft  integer,
  lot_size_sqft     integer,
  year_built        integer,
  mls_number        text,

  -- Denormalised catalog predicate inputs.  applies_when is evaluated against
  -- this blob so a condo is never scored against roof or septic facts (§6.2).
  applicability     jsonb not null default '{}'::jsonb,

  seller_contact_id uuid,               -- seller role is post-MVP; column is not
  is_demo           boolean not null default false,
  published_at      timestamptz,
  current_snapshot_id uuid,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index on properties (agent_id);
create index on properties (org_id);
create index on properties (status) where status = 'published';

create or replace function app_can_edit_property(target_property uuid) returns boolean
  language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.properties p
    where p.id = target_property
      and (p.agent_id = auth.uid()
           or (p.org_id is not null and public.app_is_org_member(p.org_id))))
$$;

create or replace function app_property_is_published(target_property uuid) returns boolean
  language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.properties p
    where p.id = target_property and p.status = 'published')
$$;

create table if not exists rooms (
  id            uuid primary key default gen_random_uuid(),
  property_id   uuid not null references properties(id) on delete cascade,
  key           text not null,                -- 'kitchen', 'bedroom_primary'
  name          text not null,
  floor_label   text,
  sort_order    integer not null default 0,
  dimensions    jsonb,                        -- { w, l, unit }
  adjacency     text[] not null default '{}', -- room keys reachable from here (§11.4)
  description   text,
  created_at    timestamptz not null default now(),
  unique (property_id, key)
);

create table if not exists property_media (
  id            uuid primary key default gen_random_uuid(),
  property_id   uuid not null references properties(id) on delete cascade,
  room_id       uuid references rooms(id) on delete set null,
  storage_path  text not null,
  kind          text not null default 'photo',   -- photo | floor_plan | video
  caption       text,
  sort_order    integer not null default 0,
  is_hero       boolean not null default false,
  visibility    fact_visibility not null default 'public',
  created_at    timestamptz not null default now()
);
create index on property_media (property_id, sort_order);

-- -----------------------------------------------------------------------------
-- 3. Fact catalog (global) and the two-tier fact model (§0.2)
-- -----------------------------------------------------------------------------

create table if not exists fact_definitions (
  key                text primary key,          -- 'mechanical.furnace.install_year'
  label              text not null,
  section            text not null,             -- 'A'..'L'
  category           text not null,
  data_type          fact_data_type not null,
  unit               text,
  enum_options       jsonb,
  applies_when       jsonb not null default '{}'::jsonb,
  default_visibility fact_visibility not null default 'public',
  is_disclosure      boolean not null default false,
  coverage_weight    integer not null default 5 check (coverage_weight between 1 and 10),
  answers_questions  text[] not null default '{}',
  room_scoped        boolean not null default false,
  help_text          text,
  catalog_version    integer not null default 1,
  created_at         timestamptz not null default now()
);
create index on fact_definitions (section);
create index on fact_definitions (category);

create table if not exists question_templates (
  id            uuid primary key default gen_random_uuid(),
  question      text not null,
  normalized    text not null,                  -- lowercased, punctuation stripped
  fact_keys     text[] not null,
  category      text not null,
  frequency     integer not null default 1,     -- learned; seeded by hand (§7.4)
  is_seed       boolean not null default true,
  created_at    timestamptz not null default now()
);
create index on question_templates using gin (normalized gin_trgm_ops);
create unique index on question_templates (normalized);

create table if not exists documents (
  id              uuid primary key default gen_random_uuid(),
  property_id     uuid not null references properties(id) on delete cascade,
  storage_path    text not null,
  original_name   text not null,
  mime_type       text not null,
  byte_size       bigint not null,
  doc_type        document_type not null default 'other',
  doc_type_source text not null default 'ai',   -- ai | agent
  status          document_status not null default 'uploaded',
  visibility      fact_visibility not null default 'agent_only',
  page_count      integer,
  -- An inspection report may only be uploaded with an explicit authorisation
  -- confirmation (§14.2).
  authorization_confirmed boolean not null default false,
  error_message   text,
  uploaded_by     uuid references profiles(id),
  created_at      timestamptz not null default now(),
  processed_at    timestamptz
);
create index on documents (property_id, status);

create table if not exists document_pages (
  id            uuid primary key default gen_random_uuid(),
  document_id   uuid not null references documents(id) on delete cascade,
  page_number   integer not null,
  text          text not null default '',
  layout        jsonb,                          -- word boxes from OCR
  created_at    timestamptz not null default now(),
  unique (document_id, page_number)
);

create table if not exists document_chunks (
  id            uuid primary key default gen_random_uuid(),
  document_id   uuid not null references documents(id) on delete cascade,
  property_id   uuid not null references properties(id) on delete cascade,
  page_number   integer not null,
  bbox          jsonb,
  content       text not null,
  token_count   integer,
  -- Denormalised from documents so the ANN query can pre-filter on visibility.
  -- Post-filtering an ANN result set silently drops recall (§6.3).
  visibility    fact_visibility not null default 'agent_only',
  embedding     vector(1536),
  tsv           tsvector generated always as (to_tsvector('english', content)) stored,
  created_at    timestamptz not null default now()
);
create index on document_chunks using hnsw (embedding vector_cosine_ops);
create index on document_chunks (property_id, visibility);
create index on document_chunks using gin (tsv);

create table if not exists fact_claims (
  id                    uuid primary key default gen_random_uuid(),
  property_id           uuid not null references properties(id) on delete cascade,
  fact_key              text not null references fact_definitions(key) on delete restrict,
  room_id               uuid references rooms(id) on delete cascade,
  value_raw             text,
  value_normalized      jsonb,
  source_type           claim_source_type not null,
  source_document_id    uuid references documents(id) on delete set null,
  source_page           integer,
  source_bbox           jsonb,
  source_snippet        text,
  extraction_confidence numeric(4,3),
  asserted_by           uuid references profiles(id),
  asserted_at           timestamptz not null default now(),
  status                claim_status not null default 'pending',
  superseded_by         uuid references fact_claims(id) on delete set null,
  -- Never extract without a citation (§8.1).  A document-sourced claim with no
  -- page was invented by the model, so the database refuses it outright.
  constraint claim_document_requires_citation check (
    source_type not in ('document', 'ai_extraction') or source_page is not null)
);
create index on fact_claims (property_id, fact_key);
create index on fact_claims (property_id, status);
create index on fact_claims (source_document_id);

create table if not exists property_facts (
  id                  uuid primary key default gen_random_uuid(),
  property_id         uuid not null references properties(id) on delete cascade,
  fact_key            text not null references fact_definitions(key) on delete restrict,
  room_id             uuid references rooms(id) on delete cascade,
  value_normalized    jsonb,
  value_display       text,
  status              fact_status not null default 'pending_review',
  verification_level  verification_level,
  unknown_reason      unknown_reason,
  winning_claim_id    uuid references fact_claims(id) on delete set null,
  confirmed_by        uuid references profiles(id),
  confirmed_at        timestamptz,
  visibility          fact_visibility not null default 'public',
  version             integer not null default 1,
  notes               text,
  updated_at          timestamptz not null default now(),
  -- One resolved truth per (property, fact, room).  Room-scoped facts repeat the
  -- key per room; property-scoped facts use the all-zero uuid sentinel so the
  -- unique index covers both without a partial-index pair.
  room_scope          uuid generated always as
                        (coalesce(room_id, '00000000-0000-0000-0000-000000000000'::uuid)) stored,
  unique (property_id, fact_key, room_scope)
);
create index on property_facts (property_id)
  where visibility = 'public' and status = 'verified';

create table if not exists fact_conflicts (
  id              uuid primary key default gen_random_uuid(),
  property_id     uuid not null references properties(id) on delete cascade,
  fact_key        text not null references fact_definitions(key) on delete restrict,
  room_id         uuid references rooms(id) on delete cascade,
  claim_ids       uuid[] not null,
  severity        conflict_severity not null default 'hard',
  -- Denormalised from the catalog at detection time: a conflict on a weight>=7
  -- fact blocks publish (§7.3), and publish must not depend on a catalog read.
  coverage_weight integer not null default 5,
  blocks_publish  boolean not null default false,
  status          conflict_status not null default 'open',
  resolved_by     uuid references profiles(id),
  resolved_at     timestamptz,
  resolution_note text,
  detected_at     timestamptz not null default now()
);
create index on fact_conflicts (property_id, status);

-- -----------------------------------------------------------------------------
-- 4. Narrative content
-- -----------------------------------------------------------------------------

create table if not exists commentary (
  id            uuid primary key default gen_random_uuid(),
  property_id   uuid not null references properties(id) on delete cascade,
  room_id       uuid references rooms(id) on delete cascade,
  scope         commentary_scope not null default 'property',
  topic         text,
  author        commentary_author not null default 'agent',
  text          text not null,
  audio_path    text,
  visibility    fact_visibility not null default 'public',
  approved      boolean not null default false,
  created_at    timestamptz not null default now()
);
create index on commentary (property_id, scope);

create table if not exists inclusions (
  id            uuid primary key default gen_random_uuid(),
  property_id   uuid not null references properties(id) on delete cascade,
  kind          inclusion_kind not null,
  item          text not null,
  detail        text,
  sort_order    integer not null default 0,
  created_at    timestamptz not null default now()
);
create index on inclusions (property_id, kind);

create table if not exists disclosures (
  id              uuid primary key default gen_random_uuid(),
  property_id     uuid not null references properties(id) on delete cascade,
  fact_key        text references fact_definitions(key) on delete set null,
  title           text not null,
  detail          text not null,
  occurred_on     date,
  remediated      boolean not null default false,
  remediation_detail text,
  document_id     uuid references documents(id) on delete set null,
  reviewed        boolean not null default false,
  -- Disclosures are never agent_only.  A product that can hide a disclosure
  -- manufactures a non-disclosure claim (§12.3), so the column is constrained
  -- rather than defaulted.
  visibility      fact_visibility not null default 'public'
                    check (visibility = 'public'),
  created_at      timestamptz not null default now()
);

create table if not exists renovations (
  id            uuid primary key default gen_random_uuid(),
  property_id   uuid not null references properties(id) on delete cascade,
  room_id       uuid references rooms(id) on delete set null,
  title         text not null,
  completed_year integer,
  cost          numeric(12,2),
  permit_number text,
  contractor    text,
  detail        text,
  document_id   uuid references documents(id) on delete set null,
  visibility    fact_visibility not null default 'public',
  created_at    timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- 5. Tours, tags, open houses, publishing
-- -----------------------------------------------------------------------------

create table if not exists tours (
  id            uuid primary key default gen_random_uuid(),
  property_id   uuid not null references properties(id) on delete cascade,
  mode          tour_mode not null default 'full',
  name          text not null default 'Full tour',
  is_default    boolean not null default false,
  created_at    timestamptz not null default now()
);

create table if not exists tour_stops (
  id            uuid primary key default gen_random_uuid(),
  tour_id       uuid not null references tours(id) on delete cascade,
  room_id       uuid references rooms(id) on delete cascade,
  sort_order    integer not null default 0,
  commentary_id uuid references commentary(id) on delete set null,
  is_highlight  boolean not null default false,
  created_at    timestamptz not null default now()
);
create index on tour_stops (tour_id, sort_order);

create table if not exists access_tags (
  id            uuid primary key default gen_random_uuid(),
  property_id   uuid not null references properties(id) on delete cascade,
  room_id       uuid references rooms(id) on delete cascade,
  kind          access_tag_kind not null,
  token         text not null unique,
  label         text,
  scan_count    integer not null default 0,
  created_at    timestamptz not null default now()
);

create table if not exists open_houses (
  id            uuid primary key default gen_random_uuid(),
  property_id   uuid not null references properties(id) on delete cascade,
  starts_at     timestamptz not null,
  ends_at       timestamptz not null,
  note          text,
  created_at    timestamptz not null default now(),
  check (ends_at > starts_at)
);
create index on open_houses (property_id, starts_at);

create table if not exists property_snapshots (
  id              uuid primary key default gen_random_uuid(),
  property_id     uuid not null references properties(id) on delete cascade,
  content_hash    text not null,
  fact_pack       jsonb not null,
  attested_by     uuid not null references profiles(id),
  attestations    jsonb not null default '{}'::jsonb,  -- the three checkboxes (§9.5)
  fact_count      integer not null default 0,
  created_at      timestamptz not null default now()
);
create index on property_snapshots (property_id, created_at desc);

-- Snapshots are the legal record of what was published.  No UPDATE or DELETE
-- policy is granted anywhere below, and this trigger closes the service-role
-- path too: immutability that depends on nobody using the admin client is not
-- immutability (§6.2).
create or replace function app_snapshots_are_immutable() returns trigger
  language plpgsql as $$
begin
  raise exception 'property_snapshots is append-only';
end $$;

create trigger property_snapshots_immutable
  before update or delete on property_snapshots
  for each row execute function app_snapshots_are_immutable();

-- -----------------------------------------------------------------------------
-- 6. Visitor sessions and the answer ledger
-- -----------------------------------------------------------------------------

create table if not exists leads (
  id            uuid primary key default gen_random_uuid(),
  property_id   uuid not null references properties(id) on delete cascade,
  name          text,
  email         text,
  phone         text,
  -- CASL requires express consent before follow-up email (§14.4).
  consent_email boolean not null default false,
  consent_text  text,
  consent_at    timestamptz,
  created_at    timestamptz not null default now()
);
create index on leads (property_id, created_at desc);

create table if not exists visitor_sessions (
  id                uuid primary key default gen_random_uuid(),
  property_id       uuid not null references properties(id) on delete cascade,
  open_house_id     uuid references open_houses(id) on delete set null,
  snapshot_id       uuid references property_snapshots(id) on delete set null,
  lead_id           uuid references leads(id) on delete set null,
  entry_tag_id      uuid references access_tags(id) on delete set null,
  audio_mode        audio_mode,
  tour_mode         tour_mode,
  state             session_state not null default 'active',
  current_room_id   uuid references rooms(id) on delete set null,
  frame             jsonb not null default '{}'::jsonb,   -- §11.3 conversation frame
  client            jsonb not null default '{}'::jsonb,
  screen_visible_ms integer not null default 0,
  duration_ms       integer not null default 0,
  started_at        timestamptz not null default now(),
  ended_at          timestamptz
);
create index on visitor_sessions (property_id, started_at desc);

create table if not exists session_events (
  id            uuid primary key default gen_random_uuid(),
  session_id    uuid not null references visitor_sessions(id) on delete cascade,
  property_id   uuid not null references properties(id) on delete cascade,
  open_house_id uuid references open_houses(id) on delete set null,
  name          text not null,
  room_id       uuid references rooms(id) on delete set null,
  props         jsonb not null default '{}'::jsonb,
  client        jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now()
);
create index on session_events using brin (created_at);
create index on session_events (property_id, name);

create table if not exists conversation_turns (
  id            uuid primary key default gen_random_uuid(),
  session_id    uuid not null references visitor_sessions(id) on delete cascade,
  role          text not null check (role in ('visitor', 'assistant')),
  text          text not null,
  room_id       uuid references rooms(id) on delete set null,
  -- Transcripts are PII-scrubbed before storage and purged at 90 days (§13.6).
  scrubbed      boolean not null default false,
  created_at    timestamptz not null default now()
);
create index on conversation_turns (session_id, created_at);

create table if not exists answer_ledger (
  id                 uuid primary key default gen_random_uuid(),
  session_id         uuid not null references visitor_sessions(id) on delete cascade,
  property_id        uuid not null references properties(id) on delete cascade,
  turn_id            uuid references conversation_turns(id) on delete set null,
  snapshot_id        uuid references property_snapshots(id) on delete set null,
  question_text      text not null,
  question_category  text,
  resolved_fact_keys text[] not null default '{}',
  fact_versions      jsonb not null default '{}'::jsonb,
  retrieval_path     retrieval_path not null,
  answer_text        text not null,
  validator_flags    jsonb not null default '[]'::jsonb,
  blocked            boolean not null default false,
  latency_ms         integer,
  provider           text,
  model              text,
  created_at         timestamptz not null default now()
);
create index on answer_ledger (property_id, created_at desc);
create index on answer_ledger (session_id);

create table if not exists lead_actions (
  id            uuid primary key default gen_random_uuid(),
  session_id    uuid not null references visitor_sessions(id) on delete cascade,
  property_id   uuid not null references properties(id) on delete cascade,
  lead_id       uuid references leads(id) on delete set null,
  type          lead_action_type not null,
  detail        jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now()
);
create index on lead_actions (property_id, created_at desc);

create table if not exists unanswered_questions (
  id            uuid primary key default gen_random_uuid(),
  property_id   uuid not null references properties(id) on delete cascade,
  session_id    uuid references visitor_sessions(id) on delete set null,
  cluster_id    uuid,
  question_text text not null,
  suggested_fact_key text references fact_definitions(key) on delete set null,
  room_id       uuid references rooms(id) on delete set null,
  state         question_state not null default 'open',
  answer_text   text,
  answered_by   uuid references profiles(id),
  answered_at   timestamptz,
  created_at    timestamptz not null default now()
);
create index on unanswered_questions (property_id, state);

create table if not exists question_clusters (
  id            uuid primary key default gen_random_uuid(),
  property_id   uuid references properties(id) on delete cascade,
  label         text not null,
  centroid      vector(1536),
  member_count  integer not null default 0,
  suggested_fact_key text references fact_definitions(key) on delete set null,
  created_at    timestamptz not null default now()
);

alter table unanswered_questions
  add constraint unanswered_questions_cluster_fk
  foreign key (cluster_id) references question_clusters(id) on delete set null;

create table if not exists audit_log (
  id            uuid primary key default gen_random_uuid(),
  actor_id      uuid references profiles(id),
  property_id   uuid references properties(id) on delete set null,
  action        text not null,
  target_table  text,
  target_id     uuid,
  justification text,
  detail        jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now()
);
create index on audit_log (property_id, created_at desc);
create index on audit_log (actor_id, created_at desc);

-- -----------------------------------------------------------------------------
-- 7. Row level security
--
-- Two audiences reach these tables directly: an authenticated agent, and the
-- server route handlers using the service role (which bypasses RLS and applies
-- its own public projection).  The anon key gets published property chrome and
-- nothing else — no fact table is anon-readable, including verified public
-- facts, because "public" there means "may appear in an answer", not "may be
-- scraped as a dataset".
-- -----------------------------------------------------------------------------

alter table organizations        enable row level security;
alter table profiles             enable row level security;
alter table org_memberships      enable row level security;
alter table properties           enable row level security;
alter table rooms                enable row level security;
alter table property_media       enable row level security;
alter table fact_definitions     enable row level security;
alter table question_templates   enable row level security;
alter table documents            enable row level security;
alter table document_pages       enable row level security;
alter table document_chunks      enable row level security;
alter table fact_claims          enable row level security;
alter table property_facts       enable row level security;
alter table fact_conflicts       enable row level security;
alter table commentary           enable row level security;
alter table inclusions           enable row level security;
alter table disclosures          enable row level security;
alter table renovations          enable row level security;
alter table tours                enable row level security;
alter table tour_stops           enable row level security;
alter table access_tags          enable row level security;
alter table open_houses          enable row level security;
alter table property_snapshots   enable row level security;
alter table leads                enable row level security;
alter table visitor_sessions     enable row level security;
alter table session_events       enable row level security;
alter table conversation_turns   enable row level security;
alter table answer_ledger        enable row level security;
alter table lead_actions         enable row level security;
alter table unanswered_questions enable row level security;
alter table question_clusters    enable row level security;
alter table audit_log            enable row level security;

-- Catalog: readable by any signed-in agent, written by migrations only.
create policy fact_definitions_read on fact_definitions
  for select to authenticated using (true);
create policy question_templates_read on question_templates
  for select to authenticated using (true);

create policy profiles_self_read on profiles
  for select to authenticated using (id = auth.uid());
create policy profiles_self_write on profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy profiles_self_insert on profiles
  for insert to authenticated with check (id = auth.uid());

create policy organizations_member_read on organizations
  for select to authenticated using (app_is_org_member(id));
create policy organizations_admin_write on organizations
  for update to authenticated using (app_is_org_admin(id)) with check (app_is_org_admin(id));

create policy memberships_read on org_memberships
  for select to authenticated using (agent_id = auth.uid() or app_is_org_admin(org_id));
create policy memberships_admin_write on org_memberships
  for all to authenticated using (app_is_org_admin(org_id)) with check (app_is_org_admin(org_id));

create policy properties_owner_all on properties
  for all to authenticated
  using (agent_id = auth.uid() or (org_id is not null and app_is_org_member(org_id)))
  with check (agent_id = auth.uid() or (org_id is not null and app_is_org_member(org_id)));

-- Published chrome only: address, price, the headline numbers.  Anonymous
-- visitors never select from fact tables; the tour reads a fact pack that the
-- server built from the snapshot.
create policy properties_public_read on properties
  for select to anon using (status = 'published');

-- Every per-property table follows the same shape.
create policy rooms_agent_all on rooms
  for all to authenticated using (app_can_edit_property(property_id))
  with check (app_can_edit_property(property_id));
create policy property_media_agent_all on property_media
  for all to authenticated using (app_can_edit_property(property_id))
  with check (app_can_edit_property(property_id));
create policy documents_agent_all on documents
  for all to authenticated using (app_can_edit_property(property_id))
  with check (app_can_edit_property(property_id));
create policy fact_claims_agent_all on fact_claims
  for all to authenticated using (app_can_edit_property(property_id))
  with check (app_can_edit_property(property_id));
create policy property_facts_agent_all on property_facts
  for all to authenticated using (app_can_edit_property(property_id))
  with check (app_can_edit_property(property_id));
create policy fact_conflicts_agent_all on fact_conflicts
  for all to authenticated using (app_can_edit_property(property_id))
  with check (app_can_edit_property(property_id));
create policy commentary_agent_all on commentary
  for all to authenticated using (app_can_edit_property(property_id))
  with check (app_can_edit_property(property_id));
create policy inclusions_agent_all on inclusions
  for all to authenticated using (app_can_edit_property(property_id))
  with check (app_can_edit_property(property_id));
create policy disclosures_agent_all on disclosures
  for all to authenticated using (app_can_edit_property(property_id))
  with check (app_can_edit_property(property_id));
create policy renovations_agent_all on renovations
  for all to authenticated using (app_can_edit_property(property_id))
  with check (app_can_edit_property(property_id));
create policy tours_agent_all on tours
  for all to authenticated using (app_can_edit_property(property_id))
  with check (app_can_edit_property(property_id));
create policy access_tags_agent_all on access_tags
  for all to authenticated using (app_can_edit_property(property_id))
  with check (app_can_edit_property(property_id));
create policy open_houses_agent_all on open_houses
  for all to authenticated using (app_can_edit_property(property_id))
  with check (app_can_edit_property(property_id));
create policy leads_agent_all on leads
  for all to authenticated using (app_can_edit_property(property_id))
  with check (app_can_edit_property(property_id));
create policy visitor_sessions_agent_read on visitor_sessions
  for select to authenticated using (app_can_edit_property(property_id));
create policy session_events_agent_read on session_events
  for select to authenticated using (app_can_edit_property(property_id));
create policy answer_ledger_agent_read on answer_ledger
  for select to authenticated using (app_can_edit_property(property_id));
create policy lead_actions_agent_read on lead_actions
  for select to authenticated using (app_can_edit_property(property_id));
create policy unanswered_questions_agent_all on unanswered_questions
  for all to authenticated using (app_can_edit_property(property_id))
  with check (app_can_edit_property(property_id));
create policy question_clusters_agent_read on question_clusters
  for select to authenticated using (property_id is null or app_can_edit_property(property_id));

create policy tour_stops_agent_all on tour_stops
  for all to authenticated
  using (exists (select 1 from tours t
                 where t.id = tour_id and app_can_edit_property(t.property_id)))
  with check (exists (select 1 from tours t
                      where t.id = tour_id and app_can_edit_property(t.property_id)));

create policy document_pages_agent_all on document_pages
  for all to authenticated
  using (exists (select 1 from documents d
                 where d.id = document_id and app_can_edit_property(d.property_id)))
  with check (exists (select 1 from documents d
                      where d.id = document_id and app_can_edit_property(d.property_id)));

create policy document_chunks_agent_all on document_chunks
  for all to authenticated using (app_can_edit_property(property_id))
  with check (app_can_edit_property(property_id));

create policy conversation_turns_agent_read on conversation_turns
  for select to authenticated
  using (exists (select 1 from visitor_sessions s
                 where s.id = session_id and app_can_edit_property(s.property_id)));

-- Snapshots: insert and select only.  Update and delete are granted to nobody,
-- and the trigger above enforces it for the service role as well.
create policy snapshots_agent_read on property_snapshots
  for select to authenticated using (app_can_edit_property(property_id));
create policy snapshots_agent_insert on property_snapshots
  for insert to authenticated with check (app_can_edit_property(property_id));

-- Audit log is append-only from the application's perspective.
create policy audit_log_agent_read on audit_log
  for select to authenticated using (
    actor_id = auth.uid()
    or (property_id is not null and app_can_edit_property(property_id)));
create policy audit_log_insert on audit_log
  for insert to authenticated with check (actor_id = auth.uid());

-- -----------------------------------------------------------------------------
-- 8. Triggers
-- -----------------------------------------------------------------------------

create or replace function app_touch_updated_at() returns trigger
  language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger properties_touch before update on properties
  for each row execute function app_touch_updated_at();

-- property_facts.version is the anchor of the answer ledger: the ledger records
-- the version used, so we can reconstruct exactly what the AI was permitted to
-- say at any past moment (§6.2).  Bumping it in the application would make that
-- reconstruction depend on every writer remembering to.
create or replace function app_bump_fact_version() returns trigger
  language plpgsql as $$
begin
  if new.value_normalized is distinct from old.value_normalized
     or new.status is distinct from old.status
     or new.visibility is distinct from old.visibility then
    new.version := old.version + 1;
  end if;
  new.updated_at := now();
  return new;
end $$;

create trigger property_facts_version before update on property_facts
  for each row execute function app_bump_fact_version();
