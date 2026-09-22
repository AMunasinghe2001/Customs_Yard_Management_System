-- ==========================================================================
--  The `updates` bucket: where the installer and appcast.xml are published.
--
--  ⚠️ RUN THIS IN THE SUPABASE SQL EDITOR (Dashboard -> SQL Editor).
--  It touches the `storage` schema, which belongs to Supabase, so the app's
--  `yard_app` account cannot run it -- and should not be able to.
--
--  ⚠️ THIS FILE IS NOT PART OF install_all.ps1. The office and local servers
--  are plain PostgreSQL with no `storage` schema at all; running it there
--  would fail on every statement. It is a one-time Supabase-only setup.
--
--  WHAT IT SETS UP
--  ---------------
--  A bucket that ANYONE may read and only a signed-in user may write:
--
--      SELECT   public   -- every officer's app fetches the feed unsigned
--      INSERT   auth'd   -- only ICT, from the dashboard or a script
--      UPDATE   auth'd
--      DELETE   auth'd
--
--  ⚠️ PUBLIC READ IS DELIBERATE AND IS NOT A LEAK. The app checks for
--  updates BEFORE anybody signs in -- there is no session to authenticate
--  with at that point. The bucket holds only what we hand out anyway: the
--  installer and a version number. Never put a .env, a certificate, a dump
--  or anything else in here.
--
--  ⚠️ PUBLIC WRITE WOULD BE REMOTE CODE EXECUTION. Whoever can replace the
--  .exe in this bucket decides what every officer's PC downloads and runs
--  as an administrator. That is the whole reason for the write policies
--  below, and the reason the feed URL is https:// and compiled in.
--
--  Safe to re-run: every step is guarded.
-- ==========================================================================

-- ── 1. The bucket ─────────────────────────────────────────────────────────
--
-- `public = true` is what makes the object URL work without a token:
--     https://<ref>.supabase.co/storage/v1/object/public/updates/appcast.xml
insert into storage.buckets (id, name, public)
values ('updates', 'updates', true)
on conflict (id) do update set public = true;

-- ── 2. Read: everybody, signed in or not ──────────────────────────────────
--
-- ⚠️ `to public` covers the `anon` role, which is what an app that has not
-- signed in uses. Restricting this to `authenticated` would mean the update
-- check only ever worked AFTER login -- exactly backwards for a client that
-- may be too old to log in at all.
drop policy if exists "updates are publicly readable" on storage.objects;
create policy "updates are publicly readable"
  on storage.objects for select
  to public
  using (bucket_id = 'updates');

-- ── 3. Write: signed-in users only ────────────────────────────────────────
--
-- Three separate policies rather than FOR ALL, so that a later change to
-- one -- say, allowing a release robot to INSERT but never DELETE -- does
-- not have to unpick the others.
drop policy if exists "only signed-in users publish updates" on storage.objects;
create policy "only signed-in users publish updates"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'updates');

drop policy if exists "only signed-in users replace updates" on storage.objects;
create policy "only signed-in users replace updates"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'updates')
  with check (bucket_id = 'updates');

drop policy if exists "only signed-in users remove updates" on storage.objects;
create policy "only signed-in users remove updates"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'updates');

-- ── 4. Verify ─────────────────────────────────────────────────────────────
do $verify$
declare
  v_public boolean;
  n_read   int;
  n_write  int;
begin
  select public into v_public from storage.buckets where id = 'updates';
  if v_public is null then
    raise exception 'the `updates` bucket was not created';
  end if;
  if not v_public then
    raise exception 'the `updates` bucket is not public - the app cannot '
                    'read the feed before anybody signs in';
  end if;

  select count(*) into n_read from pg_policies
   where schemaname = 'storage' and tablename = 'objects'
     and cmd = 'SELECT' and qual like '%updates%';

  select count(*) into n_write from pg_policies
   where schemaname = 'storage' and tablename = 'objects'
     and cmd in ('INSERT', 'UPDATE', 'DELETE')
     and coalesce(qual, '') || coalesce(with_check, '') like '%updates%';

  if n_read = 0 then
    raise exception 'no public read policy on the updates bucket';
  end if;
  if n_write < 3 then
    raise exception 'expected 3 write policies on the updates bucket, got %',
      n_write;
  end if;

  raise notice 'PASS: `updates` is public, % read and % write policy(ies)',
    n_read, n_write;
  raise notice 'Upload the .exe FIRST, then appcast.xml.';
end $verify$;

-- ==========================================================================
--  AFTER RUNNING THIS
--  ------------------
--  1. Dashboard -> Storage -> updates -> Upload file
--         SLCustoms-SR-Setup-<version>.exe     (first)
--         appcast.xml                          (second)
--
--  2. Prove the feed is reachable WITHOUT a token -- this is exactly what
--     the app does, and a private bucket answers 400 rather than 404:
--
--         curl -I https://knqpwufqpcoevjaxuihp.supabase.co/storage/v1/object/public/updates/appcast.xml
--
--     Expect `HTTP/2 200`.
--
--  ⚠️ Supabase's Free tier pauses a project after 7 days with no activity,
--  and a paused project serves nothing -- the update check then fails
--  silently on every PC. The app treats that as "no update", which is the
--  safe way to fail, but it does mean a paused project quietly stops
--  delivering releases.
-- ==========================================================================
