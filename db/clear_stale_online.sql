-- ============================================================================
--  Clear stale "online" flags. A session that closed/crashed without a clean
--  sign-out can leave profiles.is_online = true, so the dashboard shows users
--  as online who aren't. This marks anyone whose last heartbeat is older than
--  3 minutes as offline (the app beats every 2 minutes while open).
--
--  Safe to run anytime. Run in the Supabase SQL Editor.
-- ============================================================================

-- Preview who will be cleared.
select id, full_name, is_online, last_seen_at,
       (now() - last_seen_at) as since_last_seen
  from public.profiles
 where is_online is true
   and (last_seen_at is null
        or last_seen_at < now() - interval '3 minutes');

-- Clear them.
update public.profiles
   set is_online = false
 where is_online is true
   and (last_seen_at is null
        or last_seen_at < now() - interval '3 minutes');
