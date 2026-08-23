-- ============================================================================
--  Expenses are recorded PER GOODS ITEM, and the refund is DERIVED.
--
--  Two changes to the Financials model:
--
--  1. Destruction and advertising costs are incurred goods by goods, not per
--     SR — one SR can hold many items and each is destroyed/advertised on its
--     own. `package_item_id` attributes an expense to a single item so the
--     Financials tab can break the whole ledger down goods by goods.
--
--  2. A REFUND is no longer typed in. It is what is left of the goods'
--     destroying deposit after its destruction and advertising costs:
--
--         refund = destroying_deposit - (destruction + advertising)
--
--     …floored at zero, since a deposit cannot refund more than it held. The
--     'refund' kind stays in the CHECK constraint so historical rows survive,
--     but the app no longer writes it and the Financials tab computes the
--     figure instead.
--
--  Central Disposal already had full write access (policy 2 of
--  20260827_financial_expenses.sql) — they run the destructions and the
--  tender advertising, so they are the ones who post these costs.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

-- 1. ── Attribute an expense to one goods item ───────────────────────────────
alter table public.financial_expenses
  add column if not exists package_item_id uuid
    references public.package_items(id) on delete set null;

create index if not exists financial_expenses_item_idx
  on public.financial_expenses(package_item_id);

-- 2. ── Backfill the yard / SR of any row that names an item but not them ────
--    Keeps older hand-entered rows groupable with the new per-item ones.
update public.financial_expenses fe
   set sr_number = coalesce(fe.sr_number, p.sr_number),
       yard      = coalesce(fe.yard, p.yard)
  from public.package_items pi
  join public.packages p on p.id = pi.package_id
 where pi.id = fe.package_item_id
   and (fe.sr_number is null or fe.yard is null);

-- 3. ── One entry of each kind per goods item ────────────────────────────────
--    Posting a cost twice for the same goods would double-count it against
--    that item's deposit, so the app UPSERTS on (package_item_id, kind) and a
--    correction replaces the figure instead of adding a second row.
--
--    Deliberately NOT a partial index: PostgREST can only infer a conflict
--    target from a full unique constraint, so `on_conflict=package_item_id,kind`
--    would fail against a `where`-qualified one. Rows with a null
--    package_item_id are unaffected — nulls never collide in a unique index —
--    so the general (unattributed) expenses stay insertable as before.
--    Any duplicates already in the table would block the constraint, so collapse
--    each (item, kind) group to its most recent row first. Only rows that name
--    an item can collide — nulls never do.
delete from public.financial_expenses fe
 using public.financial_expenses keep
 where fe.package_item_id is not null
   and fe.package_item_id = keep.package_item_id
   and fe.kind            = keep.kind
   and (fe.created_at, fe.id) < (keep.created_at, keep.id);

--    An earlier revision of this migration created it as a partial INDEX; drop
--    that shape before adding the constraint.
drop index if exists public.financial_expenses_item_kind_uniq;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'financial_expenses_item_kind_uniq'
       and conrelid = 'public.financial_expenses'::regclass
  ) then
    alter table public.financial_expenses
      add constraint financial_expenses_item_kind_uniq
      unique (package_item_id, kind);
  end if;
end $$;

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
select kind,
       count(*)                              as entries,
       count(package_item_id)                as attributed_to_goods,
       coalesce(sum(amount), 0)              as total
  from public.financial_expenses
 group by kind
 order by kind;
