-- ============================================================================
--  Audit-log retention — keep only the last 12 months of activity logs.
--  ---------------------------------------------------------------------------
--  The Admin Panel "Logs" tab only ever shows the last year (filtered in
--  getAllLogs). This migration prunes anything older so the table doesn't grow
--  unbounded. purge_old_audit_logs() is called opportunistically by the app
--  (AuditLogService.recordLog) on each new log write; it can also be scheduled
--  via pg_cron if the project has it enabled.
-- ============================================================================

create or replace function public.purge_old_audit_logs()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted integer;
begin
  delete from public.audit_logs
   where created_at < now() - interval '365 days';
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

grant execute on function public.purge_old_audit_logs() to authenticated;

-- One-off prune of any existing backlog when this migration runs.
select public.purge_old_audit_logs();

-- Optional (only if pg_cron is enabled on the project): run daily at 02:00 UTC.
-- Safe to leave commented out — the app prunes opportunistically regardless.
-- select cron.schedule('purge-audit-logs', '0 2 * * *',
--   $$ select public.purge_old_audit_logs(); $$);

-- Done.
