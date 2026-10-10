-- ============================================================================
--  DIAGNOSTIC for GL1/SR/108/2026 — read-only, run each block and share output.
--  Tells us exactly why Palm Oil keeps getting sold.
-- ============================================================================

-- ── A. The package's items (id, name, status) ───────────────────────────────
select pi.id as item_id, pi.item_name, pi.status, pi.quantity
  from public.package_items pi
  join public.packages p on p.id = pi.package_id
 where p.sr_number = 'GL1/SR/108/2026'
 order by pi.item_name;

-- ── B. The forfeited_packages rows for this SR (item_id null = package-level) ─
select fp.id as fp_id, fp.item_id, fp.entry_qty, fp.source,
       pi.item_name as fp_item_name
  from public.forfeited_packages fp
  join public.packages p on p.id = fp.package_id
  left join public.package_items pi on pi.id = fp.item_id
 where p.sr_number = 'GL1/SR/108/2026'
 order by fp.source, fp.entry_qty;

-- ── C. The tender_sale_items rows — does each carry package_item_id? ─────────
select tsi.id as tsi_id, tsi.forfeited_package_id, tsi.package_item_id,
       tsi.sold, tsi.sold_price,
       pi.item_name as tsi_item_name
  from public.tender_sale_items tsi
  join public.forfeited_packages fp on fp.id = tsi.forfeited_package_id
  join public.packages p on p.id = fp.package_id
  left join public.package_items pi on pi.id = tsi.package_item_id
 where p.sr_number = 'GL1/SR/108/2026'
 order by tsi.sold desc;

-- ── D. Which RPC version is live? ───────────────────────────────────────────
--  has_item_scope = the per-item coalesce is present.
--  has_guard      = the latest "ambiguous_sale_item" safety net is present
--                   (this is the version that REFUSES to bulk-sell).
select proname,
       position('v_tsi_item_id'      in pg_get_functiondef(oid)) > 0 as has_item_scope,
       position('ambiguous_sale_item' in pg_get_functiondef(oid)) > 0 as has_guard
  from pg_proc
 where proname = 'disposal_mark_sale_item_sold';
