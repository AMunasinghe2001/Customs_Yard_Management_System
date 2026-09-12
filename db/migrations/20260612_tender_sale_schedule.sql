-- ============================================================================
--  Tender sale schedule — a tender now carries the date/time its sale runs.
--  After the sale date (+1 grace day) any package in the tender that was not
--  marked SOLD becomes eligible to be re-tendered (unlimited times) under a new
--  tender number. Tendered-but-unsold packages are surfaced on a dedicated view.
-- ============================================================================

alter table public.tenders
  add column if not exists sale_date date,
  add column if not exists sale_time text; -- sale start time, e.g. '10:00'

-- Done.
