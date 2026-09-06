-- ============================================================================
--  destruction_items.undestroyed -- the column the app has been writing to and
--  the database has never had.
--
--  ⚠️ This is a live bug, not a tidy-up. `markDestructionItemUndestroyed()`
--  writes {'undestroyed': true, 'undestroyed_at': ...}, and DestructionItemModel
--  reads json['undestroyed'] -- but neither column exists, so:
--
--    * pressing "Mark Undestroyed" fails outright, and
--    * the model's `undestroyed` was permanently false, which meant the ONLY
--      way anything reached the Undestroyed pool was the auto-lapse that has
--      just been removed.
--
--  Adding the pair makes the button work and gives the pool its real entry
--  route: an officer deciding, rather than a deadline passing.
--
--  Mirrors tender_sale_items.unsold / unsold_at, which the tender side already
--  has -- see the check constraint there.
--
--  Safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

alter table public.destruction_items
  add column if not exists undestroyed boolean not null default false,
  add column if not exists undestroyed_at timestamptz;

-- ⚠️ The pair must stay consistent: undestroyed means a moment, and a moment
-- means undestroyed. A row with one and not the other cannot be read.
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'destruction_items_undestroyed_pair'
  ) then
    alter table public.destruction_items
      add constraint destruction_items_undestroyed_pair
      check ((undestroyed and undestroyed_at is not null)
             or (not undestroyed and undestroyed_at is null));
  end if;
end
$$;

-- ⚠️ And an item cannot be both. Destroyed and undestroyed are the two
-- outcomes of one decision, not two independent flags.
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'destruction_items_one_outcome'
  ) then
    alter table public.destruction_items
      add constraint destruction_items_one_outcome
      check (not (destroyed and undestroyed));
  end if;
end
$$;

create index if not exists idx_destruction_items_undestroyed
  on public.destruction_items (undestroyed)
  where undestroyed;

-- ── Verify ────────────────────────────────────────────────────────────────
do $verify$
declare
  n_cols int;
  n_cons int;
begin
  select count(*) into n_cols from information_schema.columns
   where table_schema = 'public' and table_name = 'destruction_items'
     and column_name in ('undestroyed', 'undestroyed_at');
  if n_cols <> 2 then
    raise exception 'expected both undestroyed columns, found %', n_cols;
  end if;

  select count(*) into n_cons from pg_constraint
   where conname in ('destruction_items_undestroyed_pair',
                     'destruction_items_one_outcome');
  if n_cons <> 2 then
    raise exception 'expected both check constraints, found %', n_cons;
  end if;

  -- The constraints must actually hold on the data already there.
  if exists (select 1 from public.destruction_items
              where destroyed and undestroyed) then
    raise exception 'existing rows are both destroyed AND undestroyed';
  end if;

  raise notice 'OK: destruction_items can record an undestroyed outcome';
  raise notice '    rows: %  destroyed: %  undestroyed: %',
    (select count(*) from public.destruction_items),
    (select count(*) from public.destruction_items where destroyed),
    (select count(*) from public.destruction_items where undestroyed);
end
$verify$;
