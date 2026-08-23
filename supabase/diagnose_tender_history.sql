-- ============================================================================
--  Why does the Tender History show fewer rounds in one portal than another?
--
--  The section joins three things, each with its own RLS:
--      tender_sales        → the ROUND ORDER (and how many rounds exist)
--      tender_revaluations → each round's price
--      tender_committees   → the committee round's price + its members
--
--  If a role cannot read one of them, that part silently disappears. Run this
--  in the SQL editor (which bypasses RLS) to see the TRUTH, then compare with
--  what the app shows for the same SR.
--
--  NOTE: the Supabase SQL editor only displays the LAST statement's results.
--  Select ONE query below (highlight it) and press Run, or run query 5 alone —
--  it summarises all four sources on one line per package.
-- ============================================================================

-- === 1. Rounds per package (what the history SHOULD list) ===
select p.sr_number,
       pi.item_name                                as goods,
       count(distinct tsi.tender_sale_id)          as rounds,
       min(ts.created_at)::date                    as first_round,
       max(ts.created_at)::date                    as last_round,
       string_agg(distinct ts.sale_number, ', '
                  order by ts.sale_number)         as sale_numberskoo
  from public.forfeited_packages fp
  join public.packages p            on p.id  = fp.package_id
  left join public.package_items pi on pi.id = fp.item_id
  join public.tender_sale_items tsi on tsi.forfeited_package_id = fp.id
  join public.tender_sales ts       on ts.id = tsi.tender_sale_id
 group by p.sr_number, pi.item_name
 order by rounds desc, p.sr_number;

--
-- === 2. Price recorded per round (tender_revaluations) ===
select p.sr_number,
       pi.item_name              as goods,
       ts.sale_number,
       ts.created_at::date       as round_date,
       tr.valuation_cost         as revaluation,
       tr.note
  from public.tender_revaluations tr
  join public.forfeited_packages fp on fp.id = tr.forfeited_package_id
  join public.packages p            on p.id  = fp.package_id
  left join public.package_items pi on pi.id = fp.item_id
  left join public.tender_sales ts  on ts.id = tr.tender_sale_id
 order by p.sr_number, ts.created_at;

--
-- === 3. Committees: members + the ADG submission ===
--  If `members` is empty or this returns no row for an SR, the popup has
--  nothing to list — the committee was never appointed for it.
select p.sr_number,
       pi.item_name                          as goods,
       jsonb_array_length(coalesce(tc.members, '[]'::jsonb)) as member_count,
       tc.members,
       tc.committee_value,
       tc.submitted_value,
       tc.submitted_at
  from public.tender_committees tc
  join public.forfeited_packages fp on fp.id = tc.forfeited_package_id
  join public.packages p            on p.id  = fp.package_id
  left join public.package_items pi on pi.id = fp.item_id
 order by p.sr_number;

--
-- === 4. Bids per round ===
select p.sr_number,
       pi.item_name        as goods,
       ts.sale_number,
       count(*)            as bids,
       min(b.amount)       as lowest,
       max(b.amount)       as highest
  from public.tender_bids b
  join public.forfeited_packages fp on fp.id = b.forfeited_package_id
  join public.packages p            on p.id  = fp.package_id
  left join public.package_items pi on pi.id = fp.item_id
  left join public.tender_sales ts  on ts.id = b.tender_sale_id
 group by p.sr_number, pi.item_name, ts.sale_number, ts.created_at
 order by p.sr_number, ts.created_at;

--
-- === 5. The unsold packages, and what each source gives them ===
--  A quick cross-check: rounds vs prices vs committee, one line per package.
select p.sr_number,
       pi.item_name                                   as goods,
       (select count(distinct t.tender_sale_id)
          from public.tender_sale_items t
         where t.forfeited_package_id = fp.id)        as rounds,
       (select count(*) from public.tender_revaluations r
         where r.forfeited_package_id = fp.id)        as prices,
       (select count(*) from public.tender_bids b
         where b.forfeited_package_id = fp.id)        as bids,
       (select jsonb_array_length(coalesce(c.members, '[]'::jsonb))
          from public.tender_committees c
         where c.forfeited_package_id = fp.id)        as committee_members,
       up.proposal                                    as dg_decision
  from public.forfeited_packages fp
  join public.packages p            on p.id  = fp.package_id
  left join public.package_items pi on pi.id = fp.item_id
  left join public.unsold_proposals up on up.forfeited_package_id = fp.id
 where exists (select 1 from public.tender_sale_items t
                where t.forfeited_package_id = fp.id)
 order by rounds desc, p.sr_number;
