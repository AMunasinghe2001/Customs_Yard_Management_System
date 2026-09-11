import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final wh =
      File('lib/screens/warehouses/warehouses_screen.dart').readAsStringSync();
  final services = File('lib/services/services.dart').readAsStringSync();
  final providers = File('lib/core/providers.dart').readAsStringSync();
  final view =
      File('migrations/015_warehouse_rows_appeal_state.sql').readAsStringSync();

  group('the Warehouse Charge column shows the cost', () {
    test('a zero bill is not the same as a free stay', () {
      // calculatePackageCharge returns 0 for forfeited / confiscated /
      // abandoned / destroyed goods — a BILLING rule. Showing "—" for all
      // of them hid the cost of most rows in the table.
      expect(wh, contains('spaceCostFor('));
      expect(wh, contains('final charge = billed > 0 ? billed : spaceCost;'));
    });

    test('only an Unsold ruling carries no figure', () {
      expect(wh, contains('unsoldRuling'));
      expect(wh, contains("'Not charged'"));
      expect(wh, contains('unsoldProposalsProvider'));
    });

    test('an unbilled figure does not borrow the money colour', () {
      expect(wh, contains('billed > 0'));
      expect(wh, contains('context.colors.textSecondary'));
    });

    test('the column says what it holds', () {
      expect(wh, contains("Text('Warehouse Charge')"));
      expect(wh, isNot(contains("Text('Charge')")));
    });
  });

  group('the status chips cover every disposition', () {
    test('Other sits beside Detain, Forfeit and Abandoned', () {
      expect(wh, contains("'Other',"));
    });

    test('"Other" means everything else, not a literal value', () {
      // The three named chips cover Detain, Forfeit and Abandoned. Every
      // other disposition an SR can carry — "supposed to be destroyed" is
      // 22 rows in one yard — belongs here, and matching the word
      // literally returned an empty table.
      expect(services, contains("status.toLowerCase() == 'other'"));
      expect(services,
          contains("const ['Detain', 'Forfeit', 'Abandoned']"));
      // ⚠️ Three negated matches, not `not.in`: the compat layer binds a
      // filter's value as ONE parameter, so an IN list never matches.
      expect(services, contains("q.not('item_status', 'ilike', named)"));
    });

    test('the status match is case-insensitive', () {
      // The SR form has written this column both ways — "Other" and
      // "other" — and an exact match returned half the goods.
      expect(services, contains("q.ilike('item_status', status)"));
    });
  });

  group('appeal state is its own filter', () {
    test('it narrows in SQL, not after the page arrives', () {
      // The pager takes its total from the server; filtering the twenty
      // rows on screen would leave it counting rows just removed.
      expect(services, contains("q.eq('appeal_state', appeal)"));
      expect(providers, contains('final String appeal;'));
      expect(wh, contains('appeal: appealFilter'));
    });

    test('the four states are resolved once, in the view', () {
      expect(view, contains("then 'hold'"));
      expect(view, contains("then 'decided'"));
      expect(view, contains("then 'appealing'"));
      expect(view, contains("else 'enabled'"));
      // An entry with no item has no appeal to be in any state.
      expect(view, contains('when r.package_item_id is null then null'));
    });

    test('goods still inside their 30 days are not "enabled"', () {
      // ⚠️ The window was missing, so goods still appealing fell through
      // to 'enabled' — and the filter returned rows whose own chip read
      // "Appealing". Same rule as isWithinAppealWindow: entry date + 30.
      expect(view, contains("interval '30 days'"));
      expect(view, contains('admitted_at'));
    });

    test('"enabled" is named for what it enables, not for appealing', () {
      // An appeal may only be lodged INSIDE the first 30 days. The green
      // chip marks goods whose window has CLOSED — what is enabled is the
      // YARD's action, not an appeal.
      expect(wh, contains("'In appeal window'"));
      expect(wh, contains("'Window closed — actionable'"));
      expect(wh, isNot(contains("'Appeal enabled'")));
    });

    test('the view wraps postgres/48 instead of retyping it', () {
      expect(view, contains('The inner query is postgres/48 verbatim'));
    });
  });

  test('the catch-all chip is labelled as one', () {
    // Named like the three beside it, a reader takes "OTHER" for a status
    // called Other and then cannot explain why every row reads "supposed
    // to be destroyed".
    expect(wh, contains("'OTHER STATUSES'"));
    expect(wh, contains('Everything that is not Detain, Forfeit'));
  });
}