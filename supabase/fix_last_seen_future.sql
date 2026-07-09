-- ============================================================================
--  Fix "everyone shows online forever": last_seen_at was written as local time
--  tagged +00 (UTC), so it lands in the FUTURE (e.g. +5:30h in Sri Lanka). Then
--  `last_seen_at > now() - 3 min` is always true → the dashboard shows stale
--  users as online forever.
--
--  The app is being fixed to store UTC. This one-off clears any rows whose
--  last_seen_at is in the future (impossible), and marks anyone whose heartbeat
--  is not genuinely fresh as offline, so the dashboard corrects immediately.
--
--  Run in the Supabase SQL Editor.
-- ============================================================================

-- Preview the offenders (future timestamps).
select full_name, is_online, last_seen_at, (last_seen_at - now()) as ahead_by
  from public.profiles
 where last_seen_at > now();

-- Any future last_seen_at is bogus → treat as offline and null the timestamp so
-- it can't keep them online. The real value re-populates on their next login.
update public.profiles
   set is_online   = false,
       last_seen_at = null
 where last_seen_at > now();

-- Also drop anyone genuinely stale (older than 3 min) still flagged online.
update public.profiles
   set is_online = false
 where is_online is true
   and (last_seen_at is null or last_seen_at < now() - interval '3 minutes');

-- Verify: nobody should count as online except truly-fresh sessions.
select full_name, is_online, last_seen_at,
       (is_online is true
        and last_seen_at is not null
        and last_seen_at > now() - interval '3 minutes') as counts_as_online
  from public.profiles
 order by (is_online is true) desc;
