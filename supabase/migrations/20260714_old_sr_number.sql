-- ============================================================================
--  Old-entry SR registration
-- ----------------------------------------------------------------------------
--  Package Registration now has two modes: "New Entry" (normal) and
--  "Old Entry". An Old Entry captures the SR number the goods carried in the
--  previous/legacy register, stored here alongside the freshly generated SR.
--  NULL for every normal (new) registration.
-- ============================================================================

alter table public.packages
  add column if not exists old_sr_number text;
r