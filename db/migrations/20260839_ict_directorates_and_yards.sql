-- ============================================================================
--  ICT Directorate: the 'ict' role, plus yards & directorate categories as DATA
--
--  Three things, all provisioned from the ICT portal at run time:
--
--   1. `profiles.role` gains 'ict'. The ICT portal's screens already exist in
--      the app, but no migration ever widened the CHECK constraint — so every
--      ICT sign-up failed at the profile INSERT with a check violation that the
--      UI mis-reported as "Network problem". This is that fix.
--
--   2. `public.directorates` — the head-office divisions a yard belongs to
--      (CED, PSD, RTF, B/A, ACD, EXD, PRD, SSD). More can be added later from
--      the portal; nothing here hard-codes the list beyond the seed.
--
--   3. `public.yards` + `public.yard_directorates` — the yards themselves and
--      the MANY-TO-MANY link to directorates. Many-to-many is required, not
--      incidental: NNR belongs to both CED and PSD, and Katunayaka/Rathmalana/
--      Mattala belong to both B/A and ACD.
--
--  The SR number becomes `<DIRECTORATE>/<YARD>/SR/<NN>/<YYYY>`
--  (e.g. CED/GL1/SR/25/2026). Because a yard can sit under two directorates,
--  the prefix is decided by the SIGNED-IN USER's directorate, which is why
--  `profiles` gains a `directorate` column here.
--
--  Idempotent — safe to re-run.
-- ============================================================================

set lock_timeout = '5s';

-- ── 1. The 'ict' role ───────────────────────────────────────────────────────
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check
  check (role in ('admin', 'officer', 'disposal', 'appeal', 'valuation',
                  'executive', 'ict'));

-- ── 2. Directorates ─────────────────────────────────────────────────────────
create table if not exists public.directorates (
  code        text primary key,
  name        text not null,
  -- What goes in front of the SR number. Kept separate from `code` because
  -- "B/A" is the real prefix but a slash is awkward as a key elsewhere.
  sr_prefix   text not null,
  sort_order  int  not null default 100,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

insert into public.directorates (code, name, sr_prefix, sort_order) values
  ('CED', 'Customs Enforcement Directorate',        'CED', 10),
  ('PSD', 'Port & Shipping Directorate',            'PSD', 20),
  ('RTF', 'Revenue Task Force',                     'RTF', 30),
  ('BA',  'Baggage / Airport',                      'B/A', 40),
  ('ACD', 'Air Cargo Directorate',                  'ACD', 50),
  ('EXD', 'Export Directorate',                     'EXD', 60),
  ('PRD', 'Preventive Directorate',                 'PRD', 70),
  ('SSD', 'Social Protection & Security Directorate','SSD', 80)
on conflict (code) do nothing;

-- ── 3. Yards ────────────────────────────────────────────────────────────────
--  `code` matches the value already stored in `profiles.yard` and every
--  `*.yard` column, so existing rows keep resolving with no data change.
create table if not exists public.yards (
  code        text primary key,
  name        text not null,
  -- The yard's own segment of the SR number (the middle part).
  sr_prefix   text not null,
  sort_order  int  not null default 100,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

-- Seeded from lib/core/yards.dart (kYards) so the table starts out matching
-- the app exactly. Order preserved: GL1 stays first (the historical default).
insert into public.yards (code, name, sr_prefix, sort_order) values
  ('GL1',     'Grey Line 1',    'GL1',      10),
  ('GL2',     'Grey Line 2',    'GL2',      20),
  ('RCT',     'RCT',            'RCT',      30),
  ('CVT',     'CVT',            'CVT',      40),
  ('BQ',      'BQ',             'BQ',       50),
  ('NNR',     'NNR',            'NNR',      60),
  ('JCT',     'JCT',            'JCT',      70),
  ('PREV',    'Preventive',     'PREV',     80),
  ('BAGG',    'Baggage Office', 'BAGG',     90),
  ('RTF',     'RTF',            'RTF',     100),
  ('BIA',     'BIA',            'BIA',     110),
  ('HMB',     'HMB',            'HMB',     120),
  ('TRINCO',  'Trinco',         'TRINCO',  130),
  ('KURU',    'Kurunegala',     'KURU',    140),
  ('CSL',     'CSL',            'CSL',     150),
  ('DAMB',    'Dambulla',       'DAMB',    160),
  ('MIDIGO',  'Midigo',         'MIDIGO',  170),
  ('KALK',    'Kalkisiri',      'KALK',    180),
  ('TRANSCO', 'Transco',        'TRANSCO', 190),
  ('SEREN',   'Serendib',       'SEREN',   200),
  ('TRIGO',   'Trigo',          'TRIGO',   210)
on conflict (code) do nothing;

-- Yards named in the directorate mapping that had no kYards entry yet.
insert into public.yards (code, name, sr_prefix, sort_order) values
  ('CRT',     'CRT',            'CRT',     220),
  ('MIDCO',   'Midco',          'MIDCO',   230),
  ('LAKSIRI', 'Laksiri Seva',   'LAKSIRI', 240),
  ('BO',      'BO',             'BO',      250),
  ('MOBILE',  'Mobile',         'MOBILE',  260),
  ('MAINOFF', 'Main Office',    'MAINOFF', 270),
  ('KAT',     'Katunayaka',     'KAT',     280),
  ('MATT',    'Mattala',        'MATT',    290),
  ('RATH',    'Rathmalana',     'RATH',    300),
  ('PALALI',  'Palali',         'PALALI',  310),
  ('TRIO',    'Trio',           'TRIO',    320),
  ('ACE',     'ACE',            'ACE',     330),
  ('ASIAN',   'Asian',          'ASIAN',   340)
on conflict (code) do nothing;

-- ── 4. Which yards sit under which directorate (many-to-many) ───────────────
create table if not exists public.yard_directorates (
  yard_code        text not null references public.yards(code) on delete cascade,
  directorate_code text not null references public.directorates(code) on delete cascade,
  created_at       timestamptz not null default now(),
  primary key (yard_code, directorate_code)
);

create index if not exists yard_directorates_dir_idx
  on public.yard_directorates (directorate_code);

insert into public.yard_directorates (yard_code, directorate_code) values
  -- CED
  ('GL1', 'CED'), ('GL2', 'CED'), ('RCT', 'CED'), ('CRT', 'CED'),
  ('NNR', 'CED'), ('BQ', 'CED'),  ('JCT', 'CED'),
  -- PSD  (NNR is deliberately in BOTH CED and PSD)
  ('TRINCO', 'PSD'), ('MIDCO', 'PSD'), ('TRANSCO', 'PSD'),
  ('LAKSIRI', 'PSD'), ('NNR', 'PSD'), ('CSL', 'PSD'), ('BO', 'PSD'),
  -- RTF
  ('MOBILE', 'RTF'), ('MAINOFF', 'RTF'),
  -- B/A  (Katunayaka, Mattala, Rathmalana are in BOTH B/A and ACD)
  ('KAT', 'BA'), ('MATT', 'BA'), ('RATH', 'BA'), ('PALALI', 'BA'),
  -- ACD
  ('KAT', 'ACD'), ('RATH', 'ACD'), ('MATT', 'ACD'),
  -- EXD
  ('TRIO', 'EXD'), ('ACE', 'EXD'), ('ASIAN', 'EXD')
on conflict (yard_code, directorate_code) do nothing;

-- ── 5. The signed-in user's directorate ─────────────────────────────────────
--  A yard can belong to two directorates, so the yard alone cannot decide the
--  SR prefix. The USER's directorate does — chosen at registration.
--
--  Nullable and unconstrained by a FK on purpose: pre-existing accounts have no
--  directorate, and the app falls back to the yard's sole directorate (or to no
--  prefix at all) rather than refusing to work.
alter table public.profiles
  add column if not exists directorate text;

comment on column public.profiles.directorate is
  'Head-office directorate (public.directorates.code) this account registers '
  'under. Decides the SR-number prefix, since one yard may sit under several.';

-- ── 6. Reading the lists ────────────────────────────────────────────────────
--  Every signed-in user needs the yard/directorate lists: the login pickers,
--  the SR form, the "All Yards" filters. These are reference data with nothing
--  yard-private in them, so SELECT is open to any authenticated user.
alter table public.directorates      enable row level security;
alter table public.yards             enable row level security;
alter table public.yard_directorates enable row level security;

drop policy if exists directorates_read on public.directorates;
create policy directorates_read on public.directorates
  for select using (true);

drop policy if exists yards_read on public.yards;
create policy yards_read on public.yards
  for select using (true);

drop policy if exists yard_directorates_read on public.yard_directorates;
create policy yard_directorates_read on public.yard_directorates
  for select using (true);

-- ── 7. Only the ICT Directorate may change them ─────────────────────────────
create or replace function public.auth_user_is_ict()
returns boolean
language sql
stable
security definer
set search_path = public
as $fn$
  select exists (
    select 1 from public.profiles p
     where p.id = auth.uid()
       and p.role = 'ict'
       and p.is_active
  );
$fn$;

grant execute on function public.auth_user_is_ict() to authenticated, anon;

drop policy if exists directorates_ict_write on public.directorates;
create policy directorates_ict_write on public.directorates
  for all using (public.auth_user_is_ict())
  with check (public.auth_user_is_ict());

drop policy if exists yards_ict_write on public.yards;
create policy yards_ict_write on public.yards
  for all using (public.auth_user_is_ict())
  with check (public.auth_user_is_ict());

drop policy if exists yard_directorates_ict_write on public.yard_directorates;
create policy yard_directorates_ict_write on public.yard_directorates
  for all using (public.auth_user_is_ict())
  with check (public.auth_user_is_ict());

-- ── 8. ICT reads and writes every profile ───────────────────────────────────
--  Provisioning yard admins/officers is the portal's whole purpose, and those
--  accounts live in other yards than the ICT user's own.
drop policy if exists profiles_ict_read on public.profiles;
create policy profiles_ict_read on public.profiles
  for select using (public.auth_user_is_ict());

drop policy if exists profiles_ict_write on public.profiles;
create policy profiles_ict_write on public.profiles
  for all using (public.auth_user_is_ict())
  with check (public.auth_user_is_ict());

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
select pg_get_constraintdef(oid) as role_check
  from pg_constraint where conname = 'profiles_role_check';

select d.code, d.sr_prefix, count(yd.yard_code) as yards
  from public.directorates d
  left join public.yard_directorates yd on yd.directorate_code = d.code
 group by d.code, d.sr_prefix, d.sort_order
 order by d.sort_order;
