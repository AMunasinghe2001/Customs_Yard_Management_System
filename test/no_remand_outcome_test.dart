// 'remand' is not an outcome this system has.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/models/models.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  group('the DG can only choose things the yard can carry out', () {
    // ⚠️ Remand is a COURT's act, not a disposal. No yard action stands behind
    // it and nothing carries it out, so choosing it was a dead end: the goods
    // left Unsold Goods, appeared on a page named Remanded, and stayed there
    // for ever because nothing acts on them.
    test('remand is not an outcome', () {
      expect(kUnsoldProposals, isNot(contains('remand')));
      expect(unsoldProposalLabel('remand'), isNot('Remand'));
    });

    test('the outcomes that remain are all real disposals', () {
      expect(kUnsoldProposals, [
        'destroy',
        'government_use',
        'auction',
        're_export',
        'convert',
        'remove_from_premises',
      ]);
      // Every one of them names something the department actually does.
      for (final p in kUnsoldProposals) {
        expect(unsoldProposalLabel(p), isNotEmpty);
      }
    });
  });

  group('nothing offers it any more', () {
    // ⚠️ It had a decision option, an outcome tab, a nav entry, a route and a
    // report. Leaving any one of them would put an officer back on the dead
    // end, or leave a page that can never be reached.
    const surfaces = {
      'the Central Disposal tab': 'lib/screens/disposal/disposal_dashboard_screen.dart',
      'the nav rail': 'lib/widgets/app_shell.dart',
      'the router': 'lib/core/router.dart',
      'the reports page': 'lib/screens/reports/reports_screen.dart',
      'the outcome styles': 'lib/screens/executive/unsold_shared.dart',
      'the seeder': 'tool/seed_test_data.dart',
    };

    for (final s in surfaces.entries) {
      test('${s.key} does not mention it', () {
        final src = _read(s.value);
        // Comments explaining the removal are fine; code is not.
        final code = src
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//') &&
                !l.trimLeft().startsWith('///'))
            .join('\n');
        expect(code.toLowerCase().contains('remand'), isFalse,
            reason: '${s.key} still offers remand');
      });
    }
  });

  group('the database refuses it too', () {
    test('the migration drops it and re-files what was there', () {
      final sql = _read('postgres/08_drop_remand_outcome.sql');
      expect(sql, contains("set proposal = 'remove_from_premises'"));
      expect(sql, contains('unsold_proposals_proposal_check'));
      // The new constraint must not list it.
      final add = sql.substring(sql.indexOf('add constraint'));
      expect(add.substring(0, add.indexOf(';')).contains('remand'), isFalse);
      // …and it verifies both claims against the live database.
      expect(sql, contains(r'do $verify$'));
      expect(sql, contains('raise exception'));
    });
  });
}
