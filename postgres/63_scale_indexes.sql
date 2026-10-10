-- ============================================================================
--  63 · Scale indexes — the columns 100 clients actually filter on
--
--  The schema already indexes its foreign keys well (see 19 and 31). What it
--  does NOT index is the two columns almost every screen narrows by:
--
--      yard        — 23 separate `.eq('yard', ...)` call sites in services.dart
--      status      — the Goods History / disposition filters
--
--  With one user that costs nothing: a 200-row sequential scan is sub-millisecond
--  and the planner is right to prefer it. The reason to add them now is that
--  the cost is multiplied by CLIENTS, not by rows — 100 PCs each re-running a
--  yard-filtered dashboard query on every notification is the same scan a
--  hundred times over, and each one holds a connection while it runs.
--
--  ── The shape is deliberate ────────────────────────────────────────────────
--  Nearly every one of these queries is "this yard, newest first, one page":
--
--      .eq('yard', ...).order('created_at', ascending: false).range(0, 49)
--
--  so the index is (yard, created_at DESC), not two separate indexes. A
--  composite in that order lets Postgres seek straight to the yard and then
--  walk the rows already in order — the ORDER BY and the LIMIT both come free.
--  Two single-column indexes would still force a sort of every matching row.
--
--  ⚠️ CONCURRENTLY, so this can be run on the live server without locking the
--  tables against writers. That is also why each statement is separate and why
--  this file must NOT be wrapped in a transaction — CREATE INDEX CONCURRENTLY
--  is rejected inside one.
--
--  Idempotent — safe to re-run.
-- ============================================================================

-- ── The workhorse: yard + newest-first ──────────────────────────────────────
--  audit_logs is the biggest table (739 rows and the fastest-growing — every
--  action writes one) and the Activity Logs tab is pure "this yard, newest
--  first, paged", so it benefits most.
create index concurrently if not exists audit_logs_yard_created_idx
  on public.audit_logs (yard, created_at desc);

--  The per-record history popup: "what happened to THIS package".
--  Without it, opening one package's history scans every log row in the system.
create index concurrently if not exists audit_logs_entity_idx
  on public.audit_logs (entity_type, entity_id, created_at desc);

--  "What did this officer do" — the ICT user-activity view.
create index concurrently if not exists audit_logs_user_idx
  on public.audit_logs (user_id, created_at desc);

-- ── packages: the two filters every goods screen combines ───────────────────
--  `status` had NO index at all despite being the primary filter on Goods
--  History, and `yard` none despite scoping nearly every screen.
create index concurrently if not exists packages_yard_created_idx
  on public.packages (yard, created_at desc);

create index concurrently if not exists packages_status_yard_idx
  on public.packages (status, yard);

-- ── The child tables the dashboards join and filter by yard ────────────────
--  These already have their package_id foreign keys indexed (31_*), which
--  serves the JOIN. What they lacked is the yard narrowing that the
--  cross-yard Disposal and Executive views apply BEFORE joining.
create index concurrently if not exists package_items_yard_idx
  on public.package_items (yard);

create index concurrently if not exists warehouse_entries_yard_idx
  on public.warehouse_entries (yard);

create index concurrently if not exists forfeited_packages_yard_created_idx
  on public.forfeited_packages (yard, created_at desc);

--  Forfeited goods are looked up by SR number from the Appeal and Disposal
--  search boxes constantly.
create index concurrently if not exists forfeited_packages_sr_number_idx
  on public.forfeited_packages (sr_number);

-- ── Tender / disposal / destruction: all yard-scoped, all dashboard tables ──
create index concurrently if not exists tender_bids_yard_idx
  on public.tender_bids (yard);

create index concurrently if not exists tender_sales_yard_created_idx
  on public.tender_sales (yard, created_at desc);

create index concurrently if not exists tender_sale_items_yard_idx
  on public.tender_sale_items (yard);

create index concurrently if not exists tender_revaluations_yard_idx
  on public.tender_revaluations (yard);

create index concurrently if not exists tender_committees_yard_idx
  on public.tender_committees (yard);

create index concurrently if not exists destructions_yard_created_idx
  on public.destructions (yard, created_at desc);

create index concurrently if not exists destruction_items_yard_idx
  on public.destruction_items (yard);

--  disposal_requests already has a yard index (27_*); status was missing, and
--  the Disposal queue filters on exactly that.
create index concurrently if not exists disposal_requests_status_idx
  on public.disposal_requests (status, yard);

-- ── profiles: the login and the officer lists ───────────────────────────────
--  Every signed-in client reads its own profile, and the admin screens list
--  "officers in this yard".
create index concurrently if not exists profiles_yard_idx
  on public.profiles (yard);

-- ── financial_expenses: the SR roll-up ──────────────────────────────────────
--  sr_expense_summary groups by sr_number; without this it scans the table.
create index concurrently if not exists financial_expenses_sr_number_idx
  on public.financial_expenses (sr_number);

-- ── Make the planner aware of all of the above ─────────────────────────────
--  A brand-new index is invisible to the planner until the table's statistics
--  are refreshed. Without this the first minutes after deployment still
--  sequential-scan, which looks like the indexes "did nothing".
analyze public.audit_logs;
analyze public.packages;
analyze public.package_items;
analyze public.warehouse_entries;
analyze public.forfeited_packages;
analyze public.tender_bids;
analyze public.tender_sales;
analyze public.tender_sale_items;
analyze public.destructions;
analyze public.destruction_items;
analyze public.disposal_requests;
analyze public.profiles;
analyze public.financial_expenses;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
--  Every index above should appear, and none should be invalid. An index left
--  INVALID means a CONCURRENTLY build failed partway and must be dropped and
--  rebuilt — it is NOT used by queries while in that state.
select i.indexrelid::regclass as index_name,
       i.indisvalid          as is_valid
from   pg_index i
join   pg_class c on c.oid = i.indexrelid
where  c.relname like '%_yard%idx'
   or  c.relname like 'audit_logs_%_idx'
   or  c.relname like 'packages_%_idx'
order  by 1;
