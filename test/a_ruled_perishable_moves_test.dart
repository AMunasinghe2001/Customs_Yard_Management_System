// A destroy ruling that moved the goods nowhere.
//
// ⚠️ THE RULE, given directly: a perishable leaves Perishable Goods the
// MOMENT the destroy decision arrives. It then sits on Destroyed Goods as
// awaiting, until it is actually destroyed — and only then does that table
// say Destroyed.
//
// CED/GL1/SR/22/2025 (Live Ornamental Fish) was ruled `destroy` and did
// neither. Two separate gaps lined up:
//
//   * A ruling lives in `unsold_proposals` and never touches
//     `package_items.status`, which is the only thing `perishable_rows`
//     filtered on (migrations 039/040) — so it stayed.
//   * `disposition_rows` turned a PROPOSAL into a row for `re_export` only
//     — so it never arrived.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final view = File('postgres/70_disposition_rows_released_status.sql')
      .readAsStringSync();
  final mig = File('migrations/044_a_ruled_perishable_leaves_the_page.sql')
      .readAsStringSync();
  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
  final v = flat(view);
  final m = flat(mig);

  group('a destroy ruling reaches Destroyed Goods', () {
    test('Source 3 emits it, as it always did for re-export', () {
      expect(v, contains("where up.proposal in ('re_export', 'destroy')"));
    });

    test('the ruling picks the right page', () {
      expect(v,
          contains("case up.proposal when 'destroy' then 'DESTROYED' "
              "else 'RE-EXPORTED' end as final_tag"));
    });

    test('it arrives AWAITING, not already destroyed', () {
      // ⚠️ is_destroyed reads destruction_items — the record of the ACT. A
      // proposal row has none, so the page shows "Mark Destroyed" until
      // somebody presses it.
      expect(v, contains('from public.destruction_items di'));
    });

    test('a ruling does not duplicate a Final Disposition', () {
      // An item can reach this page by ruling OR by a disposition recorded
      // on the item (Source 2); one with both would be listed twice.
      expect(v, contains('select 1 from public.package_items pi2 '
          'where pi2.id = fp.item_id'));
    });
  });

  group('and it leaves Perishable Goods', () {
    test('the view drops an item once it is ruled', () {
      expect(m, contains("coalesce(trim(up.proposal), '''') <> ''''"));
    });

    test('EVERY ruling is dropped, because every ruling has a page', () {
      // ⚠️ This first dropped only destroy and re_export, on my reading
      // that the other four had nowhere to go. Wrong: Government Use,
      // Auction, Converted and Removed from the Premises all exist — they
      // read `exhausted_unsold`, which I had not looked in.
      expect(m, contains("coalesce(trim(up.proposal), '''') <> ''''"));
      expect(m.contains("up.proposal in (''destroy'', ''re_export'')"), isFalse,
          reason: 'only two rulings are dropped again');
    });

    test('the base view is named as a CTE, not nested as a subquery', () {
      // ⚠️ perishable_rows now BEGINS with its own `WITH agg AS (...)`.
      expect(m, contains("'with base as (%s) '"));
    });

    test('the migration proves nothing falls between the pages', () {
      // Either route counts: disposition_rows, or the four Final Outcome
      // pages via unsold_all_routes.
      expect(m, contains('a ruled perishable reaches no page at all'));
      expect(m, contains('from public.unsold_all_routes u'));
    });

    test('and proves no item is listed twice', () {
      expect(m, contains('item(s) listed twice under one outcome'));
    });

    test('the wrap is re-runnable', () {
      // postgres/70 recreates disposition_rows, and this file is re-applied
      // after it; a second wrap would nest the view inside itself.
      expect(m, contains("if body like '%044_ruled%' then"));
    });

    test('the marker is a BLOCK comment', () {
      // ⚠️ The statement is built as one line, so `--` swallows the select,
      // the wrap and the closing paren — Postgres then reports only
      // "syntax error at or near )".
      expect(m, contains('/* 044_ruled:'));
    });
  });

  group('046 undoes 045, which listed every ruled perishable twice', () {
    // ⚠️ MY MISTAKE, caught with a screenshot: Converted Goods showed
    // "Liquid Milk Cartons" twice, and marking one Delivered marked both --
    // because they were two rows for ONE proposal.
    //
    // 045 added a perishable branch to `exhausted_unsold`, reasoning that a
    // perishable cannot satisfy its `tender_count > 3`. True, but the four
    // pages do not read that view: they read `unsold_all_routes`, which is
    // `exhausted_unsold UNION ALL unsold_perishables` -- and the perishable
    // arm had carried them since migration 017.
    final m46 = flat(File(
            'migrations/046_undo_045_the_perishable_route_already_existed.sql')
        .readAsStringSync());

    test('045 is gone from the tree', () {
      expect(
          File('migrations/045_a_ruled_perishable_reaches_its_outcome_page.sql')
              .existsSync(),
          isFalse);
    });

    test("it refuses to run while 045's branch is still in the view", () {
      expect(m46, contains("body like '%045_perishable%'"));
    });

    test('it rebuilds from the source files rather than unwrapping the view',
        () {
      // ⚠️ My first attempt recovered the pre-045 body with a regex over
      // pg_get_viewdef. 045's own branch also ended in `) b2`, so a greedy
      // match ran past the real closing paren and produced a body that still
      // parsed, still had 18 columns, and returned ZERO rows.
      expect(m46, contains('postgres/23_exhausted_unsold_view.sql'));
      expect(m46, contains('migrations/016_perishable_flag_on_outcome_views'));
      // It still READS the stored definition -- but only to refuse to run
      // while 045 is present. It never rebuilds the view from it.
      expect(m46, isNot(contains('create or replace view public.exhausted_unsold')),
          reason: 'the definition comes from the source files, not the DB');
      expect(m46, contains('RUN THE SOURCE FILES'));
    });

    test('a column count alone is not accepted as proof', () {
      // The broken rebuild had all 18 columns and no rows at all.
      expect(m46, contains('exhausted_unsold returns no rows at all'));
    });

    test('it proves one ruling is one row on the view the pages read', () {
      expect(m46, contains('from public.unsold_all_routes'));
      expect(m46, contains('listed twice on the outcome pages'));
    });

    test('and that no ruled perishable is stranded by the removal', () {
      expect(m46, contains('ruled perishable(s) reach no page'));
    });
  });

  group('044 checks the view the pages actually read', () {
    test('its stranding check uses unsold_all_routes, not exhausted_unsold',
        () {
      // ⚠️ Checking `exhausted_unsold` alone is exactly what made 045
      // look necessary.
      expect(m, contains('not exists (select 1 from public.unsold_all_routes'));
      expect(m, isNot(contains('not exists (select 1 from public.exhausted_unsold')));
    });
  });
}
