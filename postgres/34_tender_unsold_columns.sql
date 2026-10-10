-- ============================================================================
--  tender_sale_items.unsold -- the other half of the same missing pair.
--
--  ⚠️ Exactly the bug postgres/33 fixes on the destruction side, and found the
--  same way: `markTenderSaleItemUnsold()` writes {'unsold': true, 'unsold_at':
--  ...} and TenderSaleItemModel reads json['unsold'], but neither column
--  exists. So "Mark Unsold" has never worked, and the model's `unsold` was
--  permanently false.
--
--  That went unnoticed because the auto-lapse covered for it: a package
--  reached the Unsold pool when a working-day deadline passed, whether or not
--  anyone had pressed the button. With the deadline gone -- a clock should not
--  decide an outcome, and a public holiday should not change which -- the
--  button is now the ONLY route, so it has to work.
--
--  Safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

alter table public.tender_sale_items
  add column if not exists unsold boolean not null default false,
  add column if not exists unsold_at timestamptz;

-- ⚠️ The pair must stay consistent: unsold means a moment, and a moment means
-- unsold. A row with one and not the other cannot be read.
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'tender_sale_items_unsold_pair'
  ) then
    alter table public.tender_sale_items
      add constraint tender_sale_items_unsold_pair
      check ((unsold and unsold_at is not null)
             or (not unsold and unsold_at is null));
  end if;
end
$$;

-- ⚠️ And an item cannot be both. Sold and unsold are the two outcomes of one
-- decision, not two independent flags.
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'tender_sale_items_one_outcome'
  ) then
    alter table public.tender_sale_items
      add constraint tender_sale_items_one_outcome
      check (not (sold and unsold));
  end if;
end
$$;

create index if not exists idx_tender_sale_items_unsold
  on public.tender_sale_items (unsold)
  where unsold;

-- ── Backfill ──────────────────────────────────────────────────────────────
-- ⚠️ One-shot, and guarded, because the auto-lapse is what used to put these
-- packages in the Unsold pool. Without this, removing the deadline would empty
-- the pool overnight: every package that had lapsed would silently return to
-- "awaiting decision" with nobody told.
--
-- The rule applied is the one the deadline used, at its most conservative:
-- the sale's own end moment has passed by more than a day, and the item was
-- never marked sold. Anything closer than that is left for an officer to
-- decide, which is the point of the change.
do $backfill$
declare
  n int;
begin
  if exists (select 1 from public.app_migration_flags
              where flag = 'tender_unsold_backfilled') then
    raise notice 'backfill already done -- skipping';
    return;
  end if;

  update public.tender_sale_items ti
     set unsold = true,
         unsold_at = now()
    from public.tender_sales ts
   where ts.id = ti.tender_sale_id
     and not ti.sold
     and not ti.unsold
     and ts.sale_date is not null
     and (ts.sale_date::date
          + coalesce(ts.sale_end_time, ts.sale_time, '00:00')::time)
         < (now() - interval '1 day');
  get diagnostics n = row_count;

  insert into public.app_migration_flags(flag) values ('tender_unsold_backfilled');
  raise notice 'backfilled % item(s) that the deadline had already lapsed', n;
end
$backfill$;

-- ── Verify ────────────────────────────────────────────────────────────────
do $verify$
declare
  n_cols int;
  n_cons int;
begin
  select count(*) into n_cols from information_schema.columns
   where table_schema = 'public' and table_name = 'tender_sale_items'
     and column_name in ('unsold', 'unsold_at');
  if n_cols <> 2 then
    raise exception 'expected both unsold columns, found %', n_cols;
  end if;

  select count(*) into n_cons from pg_constraint
   where conname in ('tender_sale_items_unsold_pair',
                     'tender_sale_items_one_outcome');
  if n_cons <> 2 then
    raise exception 'expected both check constraints, found %', n_cons;
  end if;

  if exists (select 1 from public.tender_sale_items
              where sold and unsold) then
    raise exception 'existing rows are both sold AND unsold';
  end if;

  raise notice 'OK: tender_sale_items can record an unsold outcome';
  raise notice '    rows: %  sold: %  unsold: %  undecided: %',
    (select count(*) from public.tender_sale_items),
    (select count(*) from public.tender_sale_items where sold),
    (select count(*) from public.tender_sale_items where unsold),
    (select count(*) from public.tender_sale_items
      where not sold and not unsold);
end
$verify$;
