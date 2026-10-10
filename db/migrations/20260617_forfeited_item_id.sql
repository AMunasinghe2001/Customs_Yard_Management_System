-- ============================================================================
--  Add item_id to forfeited_packages so synthetic abandoned / "Other"
--  disposal-request rows can pin to a SPECIFIC package item.
--
--  Before: a synthetic forfeited_packages row was created per (package, source),
--  with no item_id — so several items of the same package+source collapsed into
--  ONE row. In the Valuation / Central Disposal tables that row then aggregated
--  EVERY package item's quantity (e.g. two rows both showing qty 67), and the
--  details popup showed the wrong/whole package.
--
--  Now: createDisposalRequest() creates one forfeited_packages row per
--  (package, item, source) and stores item_id. The app's coveredItems / qty /
--  HS-code / details-popup logic already prefers forfeited.item_id when present,
--  so each row shows exactly its own item.
--  Idempotent — safe to re-run.
-- ============================================================================

alter table public.forfeited_packages
  add column if not exists item_id uuid references public.package_items(id) on delete set null;

create index if not exists idx_forfeited_packages_item_id
  on public.forfeited_packages(item_id);

-- Done.
