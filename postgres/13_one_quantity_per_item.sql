-- ============================================================================
--  An item has ONE quantity. 241 forfeited rows disagreed with theirs.
--
--  `forfeited_packages.entry_qty` is how many units this forfeit covers. For a
--  PARTIAL forfeit it is legitimately smaller than the item's own quantity --
--  the yard forfeits 2 of 48 and the rest is released. But it can never be
--  LARGER, and where the whole item was forfeited it must simply match.
--
--  The seed set them from two different numbers. The item row was inserted
--  with a jitter (`base + rng(30) - 15`) while the forfeited row was given the
--  un-jittered base, so one Truck Tyres item read 51 in its own record and 40
--  in its tender history -- and the popup printed both at once:
--
--      Value (total)   LKR 1,734,000.00  ·  @ 34,000.00 × 51
--      Valuation Tender          LKR 57,799,120  (@ 1,444,978 × 40)
--
--  ⚠️ 120 rows claimed MORE than the item had, which is not a partial forfeit
--  at all -- it is a quantity that cannot exist. Those are the ones that must
--  move, and they move DOWN to the item's own figure.
--
--  Rows where entry_qty is genuinely smaller are LEFT ALONE: a partial forfeit
--  is a real thing and this migration must not flatten it into a full one.
--  The seed's own jitter means some of those are accidents too, but nothing in
--  the data distinguishes an accidental 40-of-51 from a deliberate one, and
--  guessing would destroy real partial forfeits to tidy up seed noise.
-- ============================================================================

set lock_timeout = '5s';

update public.forfeited_packages fp
   set entry_qty = pi.quantity,
       updated_at = now()
  from public.package_items pi
 where pi.id = fp.item_id
   and fp.entry_qty > pi.quantity;

-- ── Verify ──────────────────────────────────────────────────────────────────
do $verify$
declare
  impossible int;
  partials   int;
  exact      int;
begin
  -- ⚠️ Nothing may forfeit more units than the item has.
  select count(*) into impossible
    from public.forfeited_packages fp
    join public.package_items pi on pi.id = fp.item_id
   where fp.entry_qty > pi.quantity;
  if impossible <> 0 then
    raise exception '% forfeited row(s) still claim more than their item holds',
      impossible;
  end if;

  select count(*) into partials
    from public.forfeited_packages fp
    join public.package_items pi on pi.id = fp.item_id
   where fp.entry_qty < pi.quantity;
  select count(*) into exact
    from public.forfeited_packages fp
    join public.package_items pi on pi.id = fp.item_id
   where fp.entry_qty = pi.quantity;

  raise notice
    'entry_qty: % exact, % partial (left as-is -- a partial forfeit is real)',
    exact, partials;
end
$verify$;
