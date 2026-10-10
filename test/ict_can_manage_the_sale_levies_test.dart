// The levy editor lives in the ICT console, so ICT must be able to write to
// the table behind it.
//
// ⚠️ It could not. Adding a levy failed with
//
//     new row violates row-level security policy for table "disposal_taxes"
//
// because the only write policies required `auth_user_is_disposal()`, while
// the screen that offers the control is ICT's and the Disposal portal has no
// screen for it at all. The page and the database disagreed about whose job
// this is.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql =
      File('migrations/049_ict_owns_the_sale_levies.sql').readAsStringSync();

  group('ICT owns the sale levies', () {
    test('the migration grants ICT insert, update and delete', () {
      for (final p in const [
        'disposal_taxes_ict_insert',
        'disposal_taxes_ict_update',
        'disposal_taxes_ict_delete',
      ]) {
        expect(sql, contains(p));
      }
      expect(sql, contains('public.auth_user_is_ict()'));
    });

    test('it does NOT take Disposal\'s access away', () {
      // ⚠️ The levies decide what is charged on a sale Central Disposal
      // conducts. Removing their ability to correct a rate mid-process
      // would be a bigger change than the one asked for, made silently in
      // a migration about something else.
      expect(sql, contains('Disposal lost its access to the levies'),
          reason: 'the verification must check Disposal is still allowed');
      expect(sql, isNot(contains('drop policy if exists disposal_taxes_manage')),
          reason: 'that would revoke Disposal without saying so');
    });

    test('reading stays open to every signed-in user', () {
      // Every sale screen needs the rates to show a total.
      expect(sql, contains('every sale total needs them'));
    });

    test('the policies are per-command, not one FOR ALL', () {
      // ⚠️ A single ALL policy cannot later be narrowed for one verb --
      // say, letting ICT add a levy but never delete one -- and that is
      // the shape a rate table tends to grow into.
      expect(sql, contains('for insert to authenticated'));
      expect(sql, contains('for update to authenticated'));
      expect(sql, contains('for delete to authenticated'));
    });

    test('it is safe to re-run', () {
      expect(sql, contains('drop policy if exists disposal_taxes_ict_insert'));
      expect(sql, contains("to_regclass('public.disposal_taxes') is null"));
    });
  });

  group('the levy editor is ICT-only', () {
    test('the tab is mounted only in the ICT console', () {
      // If a Disposal screen ever gains one, this migration is the place
      // that has to be revisited.
      final ict =
          File('lib/screens/ict/ict_dashboard_screen.dart').readAsStringSync();
      expect(ict, contains('SystemRatesTab('));

      final disposalDir = Directory('lib/screens/disposal');
      for (final f in disposalDir.listSync().whereType<File>()) {
        expect(f.readAsStringSync(), isNot(contains('SystemRatesTab')),
            reason: '${f.path} also edits levies - revisit migration 049');
      }
    });
  });
}
