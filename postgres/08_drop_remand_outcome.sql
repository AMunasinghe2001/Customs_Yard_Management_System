-- ============================================================================
--  'remand' is not an outcome this system has.
--
--  The DG's final outcomes are the things the department can actually DO with
--  goods nothing would buy: destroy them, take them into government use, send
--  them to auction, re-export them, convert them, or remove them from the
--  premises. "Remand" is a COURT's act, not a disposal -- there is no yard
--  action behind it, no page that carries it out, and nothing that ever
--  changes as a result of choosing it.
--
--  ⚠️ It was offered in the decision dialog, given its own outcome tab, its
--  own nav entry and its own report. An officer choosing it would have been
--  choosing a dead end: the goods would leave Unsold Goods, appear on a page
--  named Remanded, and then stay there for ever because nothing acts on them.
--
--  Anything already filed under it is re-filed as 'remove_from_premises',
--  which is the nearest real outcome: the goods leave, and the record says so.
-- ============================================================================

set lock_timeout = '5s';

update public.unsold_proposals
   set proposal = 'remove_from_premises',
       note = coalesce(nullif(trim(note), ''), 'Removed from the premises')
             || ' (was recorded as remand)'
 where proposal = 'remand';

alter table public.unsold_proposals
  drop constraint if exists unsold_proposals_proposal_check;

alter table public.unsold_proposals
  add constraint unsold_proposals_proposal_check
  check (proposal = any (array[
    'destroy'::text,
    'government_use'::text,
    'auction'::text,
    're_export'::text,
    'convert'::text,
    'remove_from_premises'::text
  ]));

reset lock_timeout;

-- ── VERIFY ──────────────────────────────────────────────────────────────────
do $verify$
declare
  v_left    int;
  v_allowed boolean;
  v_moved   int;
begin
  -- 1. Nothing may still be filed under it.
  select count(*) into v_left
    from public.unsold_proposals where proposal = 'remand';
  if v_left > 0 then
    raise exception '% rows still carry the remand outcome', v_left;
  end if;

  -- 2. …and the constraint must refuse it from now on.
  select (pg_get_constraintdef(oid) not like '%remand%') into v_allowed
    from pg_constraint
   where conrelid = 'public.unsold_proposals'::regclass
     and conname = 'unsold_proposals_proposal_check';
  if not coalesce(v_allowed, false) then
    raise exception 'the constraint still allows remand';
  end if;

  select count(*) into v_moved
    from public.unsold_proposals
   where note like '%(was recorded as remand)';

  raise notice 'OK: remand removed, % row(s) re-filed as remove_from_premises',
    v_moved;
end
$verify$;
