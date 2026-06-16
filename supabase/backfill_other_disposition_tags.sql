-- Backfill: legacy warehouse "Other" disposition tags → explicit "[OTHER: …]".
--
-- Before the fix, the warehouse Actions "Other" picker recorded a custom
-- disposition using the bare custom text as the tag, e.g. return_notes
-- "[CCCC] — note" and (for a FULL disposal) package_items.status "cccc".
-- These are indistinguishable from a real disposition tag, so the Other
-- Packages table could not detect them. New dispositions are tagged
-- "[OTHER: <text>]" / status "Other: <text>". This script rewrites the
-- known legacy rows to the new scheme.
--
-- ⚠️ Review the SELECTs first. The WHERE clauses below target ONLY tags that
-- are NOT a recognised disposition (release / forfeit / abandoned / re-export /
-- destroy / sold / final). Adjust the explicit tag list if your data differs.
-- Run in the Supabase SQL Editor.

begin;

-- 1. Partial/full "Other" disposition history entries.
--    Matches a leading "[<TAG>]" that is NOT a known disposition and NOT
--    already an "[OTHER…]" / "[FINAL:…]" tag, and rewrites it to
--    "[OTHER: <TAG>] <rest>".
--    Preview:
--      select id, return_notes from warehouse_entries
--      where is_returned = true
--        and return_notes ~ '^\[[^\]]+\]'
--        and upper(return_notes) !~ '^\[(OTHER|FINAL:|RELEASE|RELEASED|FORFEIT|FORFIET|CONFISCATED|ABANDONED|RE-EXPORT|REEXPORT|DESTROY|DESTROYED|SOLD|RECEIPT)'
--        and return_notes !~ '^\[Receipt';
update warehouse_entries
set return_notes = regexp_replace(
      return_notes,
      '^\[([^\]]+)\]',
      '[OTHER: \1]'
    )
where is_returned = true
  and return_notes ~ '^\[[^\]]+\]'
  and upper(return_notes) !~ '^\[(OTHER|FINAL:|RELEASE|RELEASED|FORFEIT|FORFIET|CONFISCATED|ABANDONED|RE-EXPORT|REEXPORT|DESTROY|DESTROYED|SOLD|RECEIPT)'
  and return_notes !~ '^\[Receipt';

-- 2. Full-disposal item statuses left as the bare custom text.
--    A FULL "Other" disposal set package_items.status to the custom text
--    (e.g. 'cccc'). Re-prefix those that are not a known status with "Other: ".
--    Preview:
--      select id, status from package_items
--      where status is not null and trim(status) <> ''
--        and lower(status) not in (
--          'detain','detained','held','forfeit','forfiet','forfeited','confiscated',
--          'abandoned','released','returned','cleared','re-export','re-exported','reexport',
--          'destroy','destroyed','sold','sale','inspecting','pending')
--        and lower(status) not like 'other:%' and lower(status) <> 'other';
update package_items
set status = 'Other: ' || status
where status is not null
  and trim(status) <> ''
  and lower(status) not in (
    'detain','detained','held','forfeit','forfiet','forfeited','confiscated',
    'abandoned','released','returned','cleared','re-export','re-exported','reexport',
    'destroy','destroyed','sold','sale','inspecting','pending')
  and lower(status) not like 'other:%'
  and lower(status) <> 'other';

commit;
