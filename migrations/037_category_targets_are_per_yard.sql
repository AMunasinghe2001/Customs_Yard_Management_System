-- 037  A category's target warehouse/zone belongs to the YARD, not to the
--      shared category row — and the yard may set it.
--
-- ⚠️ THE BUG THIS FIXES, reported from Yard Administration → Items: editing a
-- package category and pressing "Save Changes" appeared to work — the dialog
-- closed with no error — and nothing changed.
--
-- The cause is RLS, and the failure is silent by design. The policies on
-- `package_categories` are:
--
--     package_categories_ict_update  UPDATE  using/with check auth_user_is_ict()
--     package_categories_read_all    SELECT  using true
--
-- A yard SDDC is not ICT, so the UPDATE matched no rows. Postgres reports that
-- as `UPDATE 0`, not as an error — there is nothing for the client to catch,
-- so the dialog closed as if it had saved. Reproduced:
--
--     set role yard_app;
--     select sr_auth.begin_session('<sddc id>','authenticated');
--     select public.auth_user_is_ict();   ->  f
--     update package_categories set description = description;  ->  UPDATE 0
--
-- ⚠️ Simply granting the yard UPDATE on that table would be wrong. There is no
-- `yard` column on `package_categories`: it is ONE shared list, and `name` is
-- globally unique. A Grey Line 1 officer renaming "Vehicle Parts and Tyres"
-- would rename it for every yard in the country, and pointing it at their own
-- warehouse would point every other yard at a warehouse they cannot even see.
--
-- So the row is split by who owns what:
--
--   * name + description  stay on package_categories, ICT-owned. One national
--     list of what a category IS.
--   * target warehouse + zone move to package_category_targets, keyed by
--     (category, yard). Where a category's goods go is a fact about ONE yard's
--     warehouses, and each yard sets its own.

begin;

create table if not exists public.package_category_targets (
  category_id         uuid not null
                        references public.package_categories(id) on delete cascade,
  yard                text not null,
  target_warehouse_id uuid references public.warehouses(id) on delete set null,
  target_zone         text,
  updated_at          timestamptz not null default now(),
  updated_by          uuid references sr_auth.users(id),
  primary key (category_id, yard)
);

comment on table public.package_category_targets is
  'Where each yard sends a category''s goods. The category itself (name, '
  'description) is national and ICT-owned; the destination is per-yard and the '
  'yard sets it. See migration 037.';

create index if not exists package_category_targets_yard_idx
  on public.package_category_targets (yard);

alter table public.package_category_targets enable row level security;

-- ⚠️ Separate policies per command, never one `for all`. A single `for all`
-- policy also governs SELECT, and its USING clause would hide every other
-- yard's row from the directorates that need to read them.
drop policy if exists pct_read_all on public.package_category_targets;
create policy pct_read_all on public.package_category_targets
  for select using (true);

-- A yard writes only its OWN row. `auth_user_yard()` is the same function the
-- warehouse policies use, so a category target is scoped exactly as the
-- warehouse it points at already is.
drop policy if exists pct_yard_insert on public.package_category_targets;
create policy pct_yard_insert on public.package_category_targets
  for insert with check (
    yard = (select public.auth_user_yard()) or (select public.auth_user_is_ict())
  );

drop policy if exists pct_yard_update on public.package_category_targets;
create policy pct_yard_update on public.package_category_targets
  for update using (
    yard = (select public.auth_user_yard()) or (select public.auth_user_is_ict())
  ) with check (
    yard = (select public.auth_user_yard()) or (select public.auth_user_is_ict())
  );

drop policy if exists pct_yard_delete on public.package_category_targets;
create policy pct_yard_delete on public.package_category_targets
  for delete using (
    yard = (select public.auth_user_yard()) or (select public.auth_user_is_ict())
  );

grant select, insert, update, delete on public.package_category_targets to yard_app;

-- ⚠️ A target must point at a warehouse in the SAME yard as the row claims.
-- Without this a yard could set its own row to another yard's warehouse, which
-- the RLS above would allow — it only checks WHOSE row is written, not where
-- the row points.
create or replace function public.package_category_target_is_sane()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $fn$
begin
  if new.target_warehouse_id is not null then
    if (select w.yard from public.warehouses w where w.id = new.target_warehouse_id)
         is distinct from new.yard then
      raise exception
        'that warehouse is not in %', new.yard using errcode = '23514';
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$fn$;

drop trigger if exists package_category_targets_sane on public.package_category_targets;
create trigger package_category_targets_sane
  before insert or update on public.package_category_targets
  for each row execute function public.package_category_target_is_sane();

-- A view the app can read without joining by hand: every category, with THIS
-- yard's target resolved.
--
-- ⚠️ security_invoker, so the caller's own RLS applies. A SECURITY DEFINER
-- view would hand every yard's targets to whoever asked.
create or replace view public.package_categories_for_yard
with (security_invoker = true) as
  select c.id,
         c.name,
         c.description,
         c.created_at,
         t.target_warehouse_id,
         t.target_zone,
         -- ⚠️ The warehouse NAME, resolved here rather than embedded by the
         -- client. The query builder resolves `warehouses(name)` through
         -- pg_constraint, and a view has no foreign keys — the embed would
         -- throw "no unique foreign key between ... and warehouses". Joining
         -- it into the view is the honest fix; faking an FK entry is not.
         w.name as target_warehouse_name
    from public.package_categories c
    left join public.package_category_targets t
           on t.category_id = c.id
          and t.yard = (select public.auth_user_yard())
    left join public.warehouses w
           on w.id = t.target_warehouse_id;

grant select on public.package_categories_for_yard to yard_app;

commit;

-- ---------------------------------------------------------------------------
-- Verification.
-- ---------------------------------------------------------------------------

-- 1. A yard SDDC can now set a target, which is the reported bug.
do $v1$
declare v_sddc uuid; v_yard text; v_cat uuid; v_wh uuid;
begin
  select p.id, p.yard into v_sddc, v_yard
    from public.profiles p where p.role = 'admin' and p.yard is not null limit 1;
  if v_sddc is null then
    raise notice 'SKIP: no yard admin in this database to test as';
    return;
  end if;
  select id into v_cat from public.package_categories limit 1;
  select id into v_wh from public.warehouses where yard = v_yard limit 1;

  perform sr_auth.begin_session(v_sddc::text, 'authenticated');
  set local role yard_app;

  insert into public.package_category_targets (category_id, yard, target_warehouse_id, target_zone)
  values (v_cat, v_yard, v_wh, 'A')
  on conflict (category_id, yard) do update
    set target_warehouse_id = excluded.target_warehouse_id,
        target_zone         = excluded.target_zone;

  if not exists (select 1 from public.package_category_targets
                  where category_id = v_cat and yard = v_yard) then
    raise exception 'FAIL: the yard still cannot save a category target';
  end if;

  reset role;
  delete from public.package_category_targets where category_id = v_cat and yard = v_yard;
  raise notice 'PASS: a yard can set its own category target';
end $v1$;

-- 2. A yard cannot write ANOTHER yard's row.
do $v2$
declare v_sddc uuid; v_yard text; v_cat uuid; ok boolean := false;
begin
  select p.id, p.yard into v_sddc, v_yard
    from public.profiles p where p.role = 'admin' and p.yard is not null limit 1;
  if v_sddc is null then
    raise notice 'SKIP: no yard admin to test as';
    return;
  end if;
  select id into v_cat from public.package_categories limit 1;

  perform sr_auth.begin_session(v_sddc::text, 'authenticated');
  set local role yard_app;
  begin
    insert into public.package_category_targets (category_id, yard, target_zone)
    values (v_cat, v_yard || '-OTHER', 'A');
  exception when insufficient_privilege or check_violation then
    ok := true;
  end;
  reset role;

  if not ok and exists (select 1 from public.package_category_targets
                         where category_id = v_cat and yard = v_yard || '-OTHER') then
    delete from public.package_category_targets where yard = v_yard || '-OTHER';
    raise exception 'FAIL: a yard wrote another yard''s category target';
  end if;
  raise notice 'PASS: a yard cannot write another yard''s target';
end $v2$;

-- 3. The name stays ICT's. This is what the split is FOR.
do $v3$
declare v_sddc uuid; ok boolean := false;
begin
  select p.id into v_sddc
    from public.profiles p where p.role = 'admin' and p.yard is not null limit 1;
  if v_sddc is null then
    raise notice 'SKIP: no yard admin to test as';
    return;
  end if;
  perform sr_auth.begin_session(v_sddc::text, 'authenticated');
  set local role yard_app;
  update public.package_categories set name = name || '!';
  if not found then ok := true; end if;
  reset role;

  if not ok then
    raise exception 'FAIL: a yard renamed a national category';
  end if;
  raise notice 'PASS: the category name is still ICT-only';
end $v3$;
