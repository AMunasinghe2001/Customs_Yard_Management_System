-- ============================================================================
--  Who does the DB think is online right now, and how fresh is their heartbeat?
--  The Admin Dashboard treats a profile as online only when is_online = true
--  AND last_seen_at is within the last 3 minutes (AppShell beats every 2 min).
--
--  Run in the Supabase SQL Editor.
-- ============================================================================
select full_name,
       role,
       is_online,
       last_seen_at,
       (now() - last_seen_at)                       as since_last_seen,
       (is_online is true
        and last_seen_at is not null
        and last_seen_at > now() - interval '3 minutes') as counts_as_online
  from public.profiles
 order by (is_online is true) desc, last_seen_at desc nulls last;
