-- ============================================================================
--  Pinpoint why GL1/SR/108/2026 forfeit rows are missing from the yard's
--  Forfeited table. Run BOTH blocks and share the output.
-- ============================================================================

-- ── A. Each forfeit FP row + WHY getForfeitedPackages might drop it ──────────
--  in_tender   = its id is inside tenders.forfeited_package_ids
--  is_gone     = it has a SOLD tender_sale_item OR a destroyed destruction_item
--  is_requested= it has a disposal_request_items row
select fp.id as fp_id,
       pi.item_name,
       fp.appeal_hold,
       fp.appeal_decision,
       exists (
         select 1 from public.tenders t
          where to_jsonb(t.forfeited_package_ids) ? fp.id::text
       ) as in_tender,
       exists (
         select 1 from public.tender_sale_items tsi
          where tsi.forfeited_package_id = fp.id and tsi.sold = true
       ) or exists (
         select 1 from public.destruction_items di
          where di.forfeited_package_id = fp.id and di.destroyed = true
       ) as is_gone,
       exists (
         select 1 from public.disposal_request_items dri
          where dri.forfeited_package_id = fp.id
       ) as is_requested
  from public.forfeited_packages fp
  join public.packages p on p.id = fp.package_id
  left join public.package_items pi on pi.id = fp.item_id
 where p.sr_number = 'GL1/SR/108/2026'
   and fp.source = 'forfeit'
 order by pi.item_name;

-- ── B. Any [FINAL:...] warehouse entry on the Palm Oil item? ────────────────
--  (_itemHasFinalDisposition would skip the row if one exists.)
select we.id, we.package_item_id, pi.item_name, we.return_notes
  from public.warehouse_entries we
  join public.packages p on p.id = we.package_id
  join public.package_items pi on pi.id = we.package_item_id
 where p.sr_number = 'GL1/SR/108/2026'
   and pi.item_name = 'Palm Oil'
   and upper(coalesce(we.return_notes, '')) like '[FINAL:%';
