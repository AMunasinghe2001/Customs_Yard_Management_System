-- 038  The yard may name and describe a category, not only route it.
--
-- ⚠️ This REVERSES half of the decision in 037, deliberately and on the
-- Department's instruction.
--
-- 037 split the row: name + description stayed ICT-only, target warehouse and
-- zone became per-yard. The routing half was right and stays. The naming half
-- was not what was wanted: the yard administrator is the person who knows what
-- the category should be called, and making them raise a ticket with ICT to
-- fix a typo is worse than the risk it was guarding.
--
-- ⚠️ The risk is real and is NOT eliminated, only accepted: `package_categories`
-- is one national list with a globally unique `name`, so a rename by Grey Line
-- 1 changes what every yard sees. That is the trade the Department has chosen.
-- What this migration does do is make the change ATTRIBUTABLE — every write is
-- recorded with who made it, so a rename can be traced and reversed.
--
-- What is still refused:
--   * DELETE stays ICT-only. Dropping a category orphans the goods filed under
--     it in every yard, and unlike a rename that cannot be undone by typing the
--     old value back.
--   * Nothing here touches package_category_targets — the per-yard routing from
--     037 is unchanged.

begin;

-- ── Who may rename ──────────────────────────────────────────────────────────
-- Yard administrators (SDDC/DDC) and ICT. Not a plain officer: renaming the
-- national list is an administrative act, and the yard's own admin is the
-- lowest level at which that makes sense.
drop policy if exists package_categories_ict_update   on public.package_categories;
drop policy if exists package_categories_admin_update on public.package_categories;
create policy package_categories_admin_update on public.package_categories
  for update
  using (
    (select public.auth_user_is_ict())
    or (select exists (
          select 1 from public.profiles p
           where p.id = (select sr_auth.uid())
             and p.role = 'admin'
             and p.is_active))
  )
  with check (
    (select public.auth_user_is_ict())
    or (select exists (
          select 1 from public.profiles p
           where p.id = (select sr_auth.uid())
             and p.role = 'admin'
             and p.is_active))
  );

drop policy if exists package_categories_ict_insert   on public.package_categories;
drop policy if exists package_categories_admin_insert on public.package_categories;
create policy package_categories_admin_insert on public.package_categories
  for insert
  with check (
    (select public.auth_user_is_ict())
    or (select exists (
          select 1 from public.profiles p
           where p.id = (select sr_auth.uid())
             and p.role = 'admin'
             and p.is_active))
  );

-- ⚠️ DELETE is NOT widened. Left exactly as 033 set it.

-- ── The old target columns go ───────────────────────────────────────────────
--
-- ⚠️ 037 moved the routing to package_category_targets but left these two
-- columns behind, still holding their old values. That is not merely untidy:
-- the warehouses they point at were deleted with the rest of the data, so the
-- rows already VIOLATE package_categories_target_warehouse_id_fkey. Postgres
-- does not notice until something updates the row — at which point an
-- unrelated rename fails with a foreign key error, which is exactly what this
-- migration's own test hit:
--
--     ERROR: insert or update on table "package_categories" violates foreign
--            key constraint "package_categories_target_warehouse_id_fkey"
--
-- Nothing reads them any more (the app reads package_categories_for_yard), so
-- they are dropped rather than repaired.
alter table public.package_categories
  drop column if exists target_warehouse_id,
  drop column if exists target_zone;

-- ── Attribution ─────────────────────────────────────────────────────────────
-- ⚠️ A rename is now visible to more people, so it must be traceable to one of
-- them. Without this the audit trail would say a national list changed and not
-- who changed it.
alter table public.package_categories
  add column if not exists updated_at timestamptz,
  add column if not exists updated_by uuid references sr_auth.users(id);

create or replace function public.package_category_stamp()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $fn$
begin
  new.updated_at := now();
  new.updated_by := nullif(current_setting('app.current_user_id', true), '')::uuid;
  return new;
end;
$fn$;

drop trigger if exists package_categories_stamp on public.package_categories;
create trigger package_categories_stamp
  before insert or update on public.package_categories
  for each row execute function public.package_category_stamp();

commit;

-- ---------------------------------------------------------------------------
-- Verification.
-- ---------------------------------------------------------------------------

-- 1. A yard admin can rename — the reported request.
do $v1$
declare v_admin uuid; v_cat uuid; v_old text; v_new text;
begin
  select id into v_admin from public.profiles
   where role = 'admin' and is_active and yard is not null limit 1;
  if v_admin is null then
    raise notice 'SKIP: no yard admin to test as';
    return;
  end if;
  select id, name into v_cat, v_old from public.package_categories limit 1;

  perform sr_auth.begin_session(v_admin::text, 'authenticated');
  set local role yard_app;
  update public.package_categories set name = v_old || ' (m038)' where id = v_cat;
  reset role;

  select name into v_new from public.package_categories where id = v_cat;
  if v_new <> v_old || ' (m038)' then
    raise exception 'FAIL: a yard admin still cannot rename a category';
  end if;

  update public.package_categories set name = v_old where id = v_cat;
  raise notice 'PASS: a yard admin can rename a category';
end $v1$;

-- 2. The rename is attributed.
do $v2$
declare v_admin uuid; v_cat uuid; v_old text; v_by uuid;
begin
  select id into v_admin from public.profiles
   where role = 'admin' and is_active and yard is not null limit 1;
  if v_admin is null then
    raise notice 'SKIP: no yard admin to test as';
    return;
  end if;
  select id, name into v_cat, v_old from public.package_categories limit 1;

  perform sr_auth.begin_session(v_admin::text, 'authenticated');
  set local role yard_app;
  update public.package_categories set description = 'm038 probe' where id = v_cat;
  reset role;

  select updated_by into v_by from public.package_categories where id = v_cat;
  if v_by is distinct from v_admin then
    raise exception 'FAIL: the change was not attributed (updated_by=%)', v_by;
  end if;
  raise notice 'PASS: a category change records who made it';
end $v2$;

-- 3. DELETE is still ICT's alone.
do $v3$
declare v_admin uuid; v_cat uuid; n int;
begin
  select id into v_admin from public.profiles
   where role = 'admin' and is_active and yard is not null limit 1;
  if v_admin is null then
    raise notice 'SKIP: no yard admin to test as';
    return;
  end if;
  select id into v_cat from public.package_categories limit 1;

  perform sr_auth.begin_session(v_admin::text, 'authenticated');
  set local role yard_app;
  delete from public.package_categories where id = v_cat;
  get diagnostics n = row_count;
  reset role;

  if n <> 0 then
    raise exception 'FAIL: a yard admin deleted a national category';
  end if;
  raise notice 'PASS: deleting a category is still ICT only';
end $v3$;
