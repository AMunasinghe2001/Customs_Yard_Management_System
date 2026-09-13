-- ============================================================================
--  The committee round happens ONCE, and only after the committee has valued.
--
--  postgres/38 stopped Central Disposal running a FIFTH round with no
--  committee. It left two gaps, and CED/GL1/OA/07/2025 (Ceramic Floor Tiles)
--  fell through both:
--
--    1. A committee that EXISTS was enough to re-open the pool -- even one
--       that had not yet set a value. So the committee round could run
--       before the committee had priced anything, and the Committee Value
--       cell then offered "Enter Value" for a round that was already over.
--
--    2. Once a committee existed there was NO cap at all. Round 6, 7, 8...
--       were all permitted. A package gets exactly one committee round; if
--       it fails, the DG rules on the goods.
--
--  The rule, stated whole:
--
--      rounds 1-4   Central Disposal, on its own
--      round  5     ONLY once the ADG has SUBMITTED the committee's value
--      round  6+    never -- the package is exhausted
--
--  Enforced at the DATABASE, not just filtered from a view. The view decides
--  what Central Disposal is OFFERED; a trigger decides what can be WRITTEN,
--  and only the trigger holds against a direct insert or a stale screen.
--
--  Safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

-- Dropped and recreated rather than replaced: postgres/38 did the same, and
-- `create or replace` refuses a view whose column set differs.
drop view if exists public.unsold_retender_pool;

-- ⚠️ Rebuilt from the LIVE definition, not from postgres/38's source file.
-- A later migration had added `unsold`, `latest_unsold` and `valued` to the
-- view after 38 was written; the first draft of this file copied 38 and
-- silently dropped all three, and the Unsold Tenders page fell over with
-- "column t.valued does not exist". Only the round rule in the WHERE clause
-- is meant to change here.
create view public.unsold_retender_pool as
with rounds as (
  select ti.forfeited_package_id                     as fp_id,
         ti.tender_sale_id,
         ti.sold,
         ti.unsold,
         ts.created_at                               as round_created,
         (ts.sale_date::date
            + coalesce(ts.sale_time, '00:00')::time) as sale_moment
    from public.tender_sale_items ti
    join public.tender_sales ts on ts.id = ti.tender_sale_id
), agg as (
  select fp_id,
         count(*)                       as round_count,
         bool_or(sold)                  as ever_sold,
         max(round_created)             as latest_round_created
    from rounds group by fp_id
), latest as (
  select distinct on (r.fp_id)
         r.fp_id, r.tender_sale_id, r.sale_moment,
         r.unsold                       as latest_unsold
    from rounds r
   order by r.fp_id, r.round_created desc
)
select
  fp.id                                    as forfeited_package_id,
  fp.package_id,
  fp.item_id,
  fp.sr_number,
  fp.consignee_name,
  fp.yard,
  fp.entry_qty,
  fp.source,
  fp.forfeited_at,
  p.case_number,
  coalesce(pi.item_name,
           (select i2.item_name from public.package_items i2
             where i2.package_id = fp.package_id
             order by i2.created_at limit 1))  as item_name,
  a.round_count,
  l.sale_moment                            as latest_sale_moment,
  (l.sale_moment < now())                  as round_moment_passed,
  exists (select 1 from public.tender_committees tc
           where tc.forfeited_package_id = fp.id)  as has_committee,
  exists (select 1 from public.tender_revaluations tr
           where tr.forfeited_package_id = fp.id
             and tr.tender_sale_id is null)          as valued
from public.forfeited_packages fp
join agg a                        on a.fp_id = fp.id
join latest l                     on l.fp_id = fp.id
left join public.package_items pi on pi.id = fp.item_id
left join public.packages p       on p.id = fp.package_id
where not a.ever_sold
  and l.latest_unsold
  and coalesce(fp.source, '') <> 'perishable'
  and not exists (select 1 from public.exhausted_unsold e
                   where e.forfeited_package_id = fp.id)
  -- Four rounds on Central Disposal's own authority. A FIFTH only once the
  -- ADG has SUBMITTED the committee's value -- an appointed but unvalued
  -- committee is not enough, because the round is priced at that value and
  -- there is nothing to price it at yet. And NEVER a sixth: the committee
  -- round is the last one there is.
  and (a.round_count < 4
       or (a.round_count = 4
           and exists (select 1 from public.tender_committees tc
                        where tc.forfeited_package_id = fp.id
                          and tc.submitted_value is not null)))
;

grant select on public.unsold_retender_pool to public;

comment on view public.unsold_retender_pool is
  'Packages Central Disposal may still re-tender. Four rounds on its own; a '
  'fifth only once the ADG has submitted the committee value; never a sixth '
  '-- see migration 031.';


create or replace function public.tender_sale_items_enforce_round_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_rounds    int;
  v_submitted boolean;
begin
  select count(*) into v_rounds
    from public.tender_sale_items
   where forfeited_package_id = new.forfeited_package_id;

  -- v_rounds already exist; this insert would be round v_rounds + 1.
  if v_rounds >= 5 then
    raise exception
      'This package has already had its committee round (round 5). A sixth '
      'tender is not permitted: the goods are exhausted and pass to Unsold '
      'Goods for the DG to rule on.'
      using errcode = '22023';
  end if;

  if v_rounds = 4 then
    select exists (select 1 from public.tender_committees tc
                    where tc.forfeited_package_id = new.forfeited_package_id
                      and tc.submitted_value is not null)
      into v_submitted;
    if not v_submitted then
      raise exception
        'Round 5 is the committee round and may only be run at the '
        'committee value. Top Management has not yet submitted one for this '
        'package.'
        using errcode = '22023';
    end if;
  end if;

  return new;
end;
$fn$;

drop trigger if exists tender_sale_items_enforce_round_limit
  on public.tender_sale_items;
create trigger tender_sale_items_enforce_round_limit
  before insert on public.tender_sale_items
  for each row execute function public.tender_sale_items_enforce_round_limit();


do $$
declare
  v_fp uuid;
  v_ts uuid;
  v_ok boolean;
begin
  select id into v_ts from public.tender_sales limit 1;

  -- A package at 5 rounds must refuse a 6th.
  select tsi.forfeited_package_id into v_fp
    from public.tender_sale_items tsi
   group by tsi.forfeited_package_id having count(*) = 5 limit 1;
  if v_fp is not null then
    v_ok := false;
    begin
      insert into public.tender_sale_items
        (tender_sale_id, forfeited_package_id, yard, sold)
      values (v_ts, v_fp, 'GL1', false);
    exception when others then v_ok := true;
    end;
    if not v_ok then
      raise exception 'a SIXTH round was accepted';
    end if;
  end if;

  -- A package at 4 rounds whose committee has NOT submitted must refuse a 5th.
  select tsi.forfeited_package_id into v_fp
    from public.tender_sale_items tsi
    join public.tender_committees tc
      on tc.forfeited_package_id = tsi.forfeited_package_id
   where tc.submitted_value is null
   group by tsi.forfeited_package_id having count(*) = 4 limit 1;
  if v_fp is not null then
    v_ok := false;
    begin
      insert into public.tender_sale_items
        (tender_sale_id, forfeited_package_id, yard, sold)
      values (v_ts, v_fp, 'GL1', false);
    exception when others then v_ok := true;
    end;
    if not v_ok then
      raise exception 'a 5th round ran before the committee had valued';
    end if;
  end if;

  raise notice
    'verified: no sixth round, and no fifth before the committee submits';
end $$;
