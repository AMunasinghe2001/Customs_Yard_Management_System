-- ============================================================================
--  'perishable' becomes a real forfeited_packages source.
--
--  The app already SHOWS a 'perishable' source: getRequestableExpiredPackages
--  builds one on the fly for goods that have no forfeited_packages row. But the
--  column's CHECK constraint allowed only forfeit / abandoned / other / detain,
--  so the moment a perishable genuinely reached a sale -- and therefore needed
--  a real row -- it had to be filed under 'forfeit'.
--
--  ⚠️ That is what made the Appeal Directorate unable to tell them apart. A
--  perishable has NO appeal window (that is the whole point of the nature), yet
--  it sat in the appeal list wearing a Forfeit badge, indistinguishable from
--  goods that genuinely have 30 days to run.
--
--  Widening the constraint lets the source say what the goods actually are, so
--  every screen that reads it can filter honestly instead of guessing from the
--  item's nature through a join.
-- ============================================================================

set lock_timeout = '5s';

alter table public.forfeited_packages
  drop constraint if exists forfeited_packages_source_check;

alter table public.forfeited_packages
  add constraint forfeited_packages_source_check
  check (source = any (array[
    'forfeit'::text,
    'abandoned'::text,
    'other'::text,
    'detain'::text,
    'perishable'::text
  ]));

-- Re-file the rows that were forced under 'forfeit' only because the
-- constraint left nowhere else to put them. The ITEM's nature is the
-- authority: it is what routes goods to a special sale in the first place.
update public.forfeited_packages fp
   set source = 'perishable'
  from public.package_items pi
 where pi.id = fp.item_id
   and pi.nature = 'perishable'
   and fp.source <> 'perishable';

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
do $verify$
declare
  v_mislabelled int;
  v_perishable  int;
  v_allowed     boolean;
begin
  -- 1. No perishable item may still be filed under another source.
  select count(*) into v_mislabelled
    from public.forfeited_packages fp
    join public.package_items pi on pi.id = fp.item_id
   where pi.nature = 'perishable'
     and fp.source <> 'perishable';
  if v_mislabelled > 0 then
    raise exception '% perishable rows still carry the wrong source',
      v_mislabelled;
  end if;

  -- 2. …and nothing else may claim the new source.
  select count(*) into v_mislabelled
    from public.forfeited_packages fp
    join public.package_items pi on pi.id = fp.item_id
   where fp.source = 'perishable'
     and pi.nature <> 'perishable';
  if v_mislabelled > 0 then
    raise exception '% non-perishable rows claim the perishable source',
      v_mislabelled;
  end if;

  -- 3. The constraint really does accept it now.
  select count(*) into v_perishable
    from public.forfeited_packages where source = 'perishable';

  select true into v_allowed
    from pg_constraint
   where conrelid = 'public.forfeited_packages'::regclass
     and conname = 'forfeited_packages_source_check'
     and pg_get_constraintdef(oid) like '%perishable%';
  if not coalesce(v_allowed, false) then
    raise exception 'the source constraint does not allow perishable';
  end if;

  raise notice 'OK: % rows re-filed as perishable', v_perishable;
end
$verify$;
