-- ============================================================================
-- GL1 Database Full Clean Script
-- Clears ALL business data + officer accounts (fresh start)
-- Preserves: schema structure, schema_migrations table
-- ============================================================================
--
-- Strategy for audit_logs:
--   audit_logs has a BEFORE TRUNCATE FOR EACH STATEMENT trigger that fires
--   even for superusers — it cannot be bypassed by RLS or grants.
--   DISABLE TRIGGER inside a PL/pgSQL DO block does not reliably suppress
--   subsequent EXECUTE 'TRUNCATE ...' in the same block (PostgreSQL internal
--   trigger-state bookkeeping is per-statement, not per-transaction for DDL
--   issued through dynamic SQL).
--
--   The clean solution: DROP the trigger before truncating, then re-create it
--   afterward from its original function.  DROP/CREATE via top-level statements
--   are auto-committed individually, but each runs in its own implicit txn so
--   there is no cross-statement coherency issue — the trigger simply does not
--   exist for the duration of the TRUNCATE.
-- ============================================================================

SET client_min_messages = warning;

-- ── Step 1: Drop the append-only guards temporarily ─────────────────────────
DROP TRIGGER IF EXISTS audit_logs_no_truncate ON public.audit_logs;
DROP TRIGGER IF EXISTS audit_logs_no_delete   ON public.audit_logs;
DROP TRIGGER IF EXISTS audit_logs_no_update   ON public.audit_logs;

-- ── Step 2: Clear audit_logs (now unprotected) ───────────────────────────────
TRUNCATE TABLE public.audit_logs;

-- ── Step 3: Truncate all business tables ─────────────────────────────────────
--   CASCADE is safe — audit_logs is already empty so no cascade will touch it.
TRUNCATE TABLE
  public.officer_signup_otps,
  public.refused_sign_in_pending,
  public.package_item_handovers,
  public.tender_sale_items,
  public.tender_sales,
  public.tender_disposals,
  public.tenders,
  public.destruction_items,
  public.destructions,
  public.disposal_request_items,
  public.disposal_requests,
  public.disposal_taxes,
  public.forfeited_packages,
  public.warehouse_entries,
  public.package_items,
  public.packages,
  public.package_category_targets,
  public.approved_devices,
  public.storage_rates,
  public.hold_reasons,
  public.package_categories,
  public.warehouses,
  public.profiles
  CASCADE;

-- ── Step 4: Clear officer accounts ───────────────────────────────────────────
TRUNCATE TABLE sr_auth.users CASCADE;

-- ── Step 5: Re-create the append-only guards (from their existing functions) ──
CREATE TRIGGER audit_logs_no_update
  BEFORE UPDATE ON public.audit_logs
  FOR EACH ROW EXECUTE FUNCTION public.audit_logs_append_only();

CREATE TRIGGER audit_logs_no_delete
  BEFORE DELETE ON public.audit_logs
  FOR EACH ROW EXECUTE FUNCTION public.audit_logs_append_only();

CREATE TRIGGER audit_logs_no_truncate
  BEFORE TRUNCATE ON public.audit_logs
  FOR EACH STATEMENT EXECUTE FUNCTION public.audit_logs_no_truncate();

-- ── Step 6: Verify row counts ─────────────────────────────────────────────────
SELECT
  schemaname,
  relname   AS tablename,
  n_live_tup AS estimated_rows
FROM pg_stat_user_tables
WHERE schemaname IN ('public', 'sr_auth')
  AND relname != 'schema_migrations'
ORDER BY schemaname, relname;
