-- =============================================================================
-- RLS policy tests.  Run against a database that has supabase-shim.sql and
-- schema.sql applied:  packages/db/test.sh
--
-- These are the Phase 1 exit criterion "RLS tests pass" and the Phase 2
-- criterion "RLS blocks cross-agent access (tested, not assumed)".  Every
-- assertion below is a claim the architecture makes in §2 or §14.
-- =============================================================================

\set ON_ERROR_STOP on
set client_min_messages = notice;

create or replace function assert(ok boolean, what text) returns void
  language plpgsql as $$
begin
  if ok then
    raise notice 'ok    %', what;
  else
    raise exception 'FAIL  %', what;
  end if;
end $$;

create or replace function assert_denied(stmt text, what text) returns void
  language plpgsql as $$
begin
  execute stmt;
  raise exception 'FAIL  % (statement succeeded and should not have)', what;
exception
  when insufficient_privilege or check_violation then
    raise notice 'ok    %', what;
end $$;

-- ---------------------------------------------------------------- fixtures --
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'sarah@example.test'),
  ('22222222-2222-2222-2222-222222222222', 'rival@example.test'),
  ('33333333-3333-3333-3333-333333333333', 'teammate@example.test');

insert into profiles (id, full_name, email) values
  ('11111111-1111-1111-1111-111111111111', 'Sarah Thompson', 'sarah@example.test'),
  ('22222222-2222-2222-2222-222222222222', 'Rival Agent',    'rival@example.test'),
  ('33333333-3333-3333-3333-333333333333', 'Teammate',       'teammate@example.test');

insert into organizations (id, name, slug) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Thompson Real Estate Group', 'thompson');

insert into org_memberships (org_id, agent_id, role) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'owner'),
  ('aaaaaaaa-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', 'member');

-- The catalog comes from the generated seed, which test.sh loads first.
do $$
begin
  perform assert(
    (select count(*) from fact_definitions) >= 300,
    'the generated fact catalog is loaded');
  perform assert(
    exists (select 1 from fact_definitions where key = 'mechanical.furnace.install_year'),
    'the catalog carries the keys the engine resolves by name');
  perform assert(
    (select coverage_weight from fact_definitions where key = 'basement.suite_status') = 10,
    'the most-asked fact carries the weight the engine expects');
  perform assert(
    not exists (select 1 from fact_definitions where is_disclosure and coverage_weight < 6),
    'every disclosure fact carries real weight');
end $$;

insert into properties (id, org_id, agent_id, slug, status, address_line1, city,
                        province, property_type, list_price)
values
  ('bbbbbbbb-0000-0000-0000-000000000001',
   'aaaaaaaa-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111',
   'maple-crescent-123', 'published', '123 Maple Crescent', 'Calgary', 'AB',
   'detached', 899900),
  ('bbbbbbbb-0000-0000-0000-000000000002',
   null, '22222222-2222-2222-2222-222222222222',
   'rival-listing', 'published', '9 Elsewhere Ave', 'Calgary', 'AB', 'detached', 500000),
  ('bbbbbbbb-0000-0000-0000-000000000003',
   'aaaaaaaa-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111',
   'unpublished-draft', 'draft', '5 Draft Road', 'Calgary', 'AB', 'detached', 400000);

insert into property_facts (property_id, fact_key, value_normalized, value_display,
                            status, verification_level, visibility)
values
  ('bbbbbbbb-0000-0000-0000-000000000001', 'mechanical.furnace.install_year',
   '2019'::jsonb, '2019', 'verified', 'document_verified', 'public'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'mechanical.furnace.install_year',
   '2001'::jsonb, '2001', 'verified', 'document_verified', 'public');

-- ------------------------------------------------------- structural checks --
do $$
declare bad text;
begin
  select string_agg(c.relname, ', ') into bad
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
  where c.relkind = 'r' and not c.relrowsecurity;
  perform assert(bad is null, 'every table has row level security enabled');

  select string_agg(c.relname, ', ') into bad
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
  left join pg_policy p on p.polrelid = c.oid
  where c.relkind = 'r'
  group by c.relname having count(p.polname) = 0;
  perform assert(bad is null, 'every table has at least one policy');
end $$;

-- --------------------------------------------------------- agent isolation --
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

do $$
begin
  perform assert((select count(*) from properties) = 2,
    'Sarah sees her own two properties and nothing else');
  perform assert(not exists (select 1 from properties where slug = 'rival-listing'),
    'Sarah cannot see a rival agent''s property');
  perform assert((select count(*) from property_facts) = 1,
    'Sarah sees only facts on properties she can edit');
end $$;

set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$
begin
  perform assert((select count(*) from properties) = 1,
    'the rival agent sees only their own property');
  perform assert(
    (select count(*) from property_facts
     where property_id = 'bbbbbbbb-0000-0000-0000-000000000001') = 0,
    'the rival agent cannot read Sarah''s facts');
end $$;

-- RLS filters an UPDATE rather than raising on it, so the assertion is that
-- the row is untouched afterwards.
update properties set list_price = 1
  where id = 'bbbbbbbb-0000-0000-0000-000000000001';
reset role;
do $$
begin
  perform assert(
    (select list_price from properties
     where id = 'bbbbbbbb-0000-0000-0000-000000000001') = 899900,
    'a cross-agent UPDATE changes nothing');
end $$;

-- Team member reaches org properties, and only org properties.
set role authenticated;
set request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
do $$
begin
  perform assert((select count(*) from properties) = 2,
    'a team member sees the org''s two properties');
  perform assert(not exists (select 1 from properties where slug = 'rival-listing'),
    'a team member does not inherit other orgs');
end $$;

-- An agent may not insert a property owned by someone else.
select assert_denied($$
  insert into properties (agent_id, slug, address_line1, city, province, property_type)
  values ('22222222-2222-2222-2222-222222222222', 'smuggled', '1 X', 'Calgary', 'AB', 'detached')
$$, 'an agent cannot create a property under another agent''s id');

-- ---------------------------------------------------- anonymous visitor --
reset role;
set role anon;
reset request.jwt.claim.sub;

do $$
begin
  perform assert((select count(*) from properties) = 2,
    'anon sees published properties only');
  perform assert(not exists (select 1 from properties where slug = 'unpublished-draft'),
    'anon cannot see a draft property');
  perform assert((select count(*) from property_facts) = 0,
    'anon cannot read fact tables at all — the tour reads a server-built fact pack');
  perform assert((select count(*) from documents) = 0,
    'anon cannot read documents');
  perform assert((select count(*) from answer_ledger) = 0,
    'anon cannot read the answer ledger');
  perform assert((select count(*) from leads) = 0,
    'anon cannot read leads');
end $$;

reset role;

-- ------------------------------------------------- snapshot immutability --
insert into property_snapshots (id, property_id, content_hash, fact_pack, attested_by)
values ('cccccccc-0000-0000-0000-000000000001',
        'bbbbbbbb-0000-0000-0000-000000000001', 'sha256:test', '{}'::jsonb,
        '11111111-1111-1111-1111-111111111111');

do $$
begin
  begin
    update property_snapshots set content_hash = 'sha256:tampered'
    where id = 'cccccccc-0000-0000-0000-000000000001';
    raise exception 'FAIL  a published snapshot could be rewritten';
  exception when raise_exception then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'ok    a published snapshot cannot be rewritten, even as owner';
  end;

  begin
    delete from property_snapshots
    where id = 'cccccccc-0000-0000-0000-000000000001';
    raise exception 'FAIL  a published snapshot could be deleted';
  exception when raise_exception then
    if sqlerrm like 'FAIL%' then raise; end if;
    raise notice 'ok    a published snapshot cannot be deleted, even as owner';
  end;
end $$;

-- ------------------------------------------------------- schema invariants --
do $$
begin
  begin
    insert into fact_claims (property_id, fact_key, source_type, value_raw)
    values ('bbbbbbbb-0000-0000-0000-000000000001',
            'mechanical.furnace.install_year', 'ai_extraction', '2019');
    raise exception 'FAIL  an uncited extraction claim was accepted';
  exception when check_violation then
    raise notice 'ok    an extracted claim with no source page is rejected by the database';
  end;

  begin
    insert into disclosures (property_id, title, detail, visibility)
    values ('bbbbbbbb-0000-0000-0000-000000000001', 'Leak', 'Basement water 2021',
            'agent_only');
    raise exception 'FAIL  a disclosure could be hidden from visitors';
  exception when check_violation then
    raise notice 'ok    a disclosure cannot be marked agent_only';
  end;
end $$;

-- property_facts.version drives the answer ledger's reconstruction (§6.2).
do $$
declare v1 integer; v2 integer; v3 integer;
begin
  select version into v1 from property_facts
   where property_id = 'bbbbbbbb-0000-0000-0000-000000000001';
  update property_facts set value_normalized = '2020'::jsonb
   where property_id = 'bbbbbbbb-0000-0000-0000-000000000001';
  select version into v2 from property_facts
   where property_id = 'bbbbbbbb-0000-0000-0000-000000000001';
  update property_facts set notes = 'cosmetic edit'
   where property_id = 'bbbbbbbb-0000-0000-0000-000000000001';
  select version into v3 from property_facts
   where property_id = 'bbbbbbbb-0000-0000-0000-000000000001';
  perform assert(v2 = v1 + 1, 'changing a fact value bumps its version');
  perform assert(v3 = v2, 'editing a note does not bump the version');
end $$;

\echo ''
\echo 'RLS tests passed.'
