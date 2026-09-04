-- ============================================================================
--  The years the audit log actually has rows in.
--
--  The Activity Logs year picker offered a hard-coded "this year and the four
--  before it". On a system installed this year, four of those five return nothing;
--  on one that has been running longer, the sixth year back is missing from
--  the very filter meant to find it.
--
--  ⚠️ This is a FUNCTION rather than a query the screen builds, because the
--  honest version of "which years have rows" is a DISTINCT over the whole
--  table. Doing that in Dart means fetching every timestamp in the log to
--  throw all but a handful away -- the same mistake the page itself was making
--  before it was paged in SQL. Postgres answers it from the index.
--
--  The caller adds the current year and the next one on top (see srYears for
--  the same rule on the yard's SR-number filter): on 1 January nothing has
--  been logged yet, and a year the officer is working in must be offered
--  whether or not it has rows.
-- ============================================================================

set lock_timeout = '5s';

create or replace function public.audit_log_years()
returns setof int
language sql
stable
as $$
  select distinct extract(year from created_at)::int as y
    from public.audit_logs
   order by y desc;
$$;

grant execute on function public.audit_log_years() to public;

-- ── Verify ──────────────────────────────────────────────────────────────────
do $verify$
declare
  n_years int;
  n_rows  bigint;
  newest  int;
begin
  select count(*) into n_years from public.audit_log_years();
  select count(*) into n_rows  from public.audit_logs;

  if n_rows > 0 and n_years = 0 then
    raise exception 'audit_log_years() returned nothing for % rows', n_rows;
  end if;

  if n_rows = 0 then
    raise notice 'audit_logs is empty; the function returns no years, which is correct.';
  else
    select max(y) into newest from public.audit_log_years() as t(y);
    -- Every row must fall in one of the years the function names.
    if exists (
      select 1 from public.audit_logs a
       where extract(year from a.created_at)::int
             not in (select y from public.audit_log_years() as t(y))
    ) then
      raise exception 'a log row falls outside the years the function reports';
    end if;
    raise notice 'audit_log_years(): % year(s) over % row(s), newest %',
      n_years, n_rows, newest;
  end if;
end
$verify$;
