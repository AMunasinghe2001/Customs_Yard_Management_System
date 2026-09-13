import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Appeal Directorate's two tables label a package "On Appeal Hold" or
/// "Decided · Sell" — and its Details popup said nothing about the appeal at
/// all. Not the date the goods were forfeited, not the deadline, not whether a
/// hold was placed, not what was ruled or when. An officer opening a row could
/// not check the very thing that page exists for.
String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final dialog = _read('lib/widgets/package_details_dialog.dart');
  final appeal = _read('lib/screens/appeal/appeal_dashboard_screen.dart');

  group('the popup carries the appeal record', () {
    test('the Appeal screen passes the forfeited row', () {
      // ⚠️ Without this the dialog has NO appeal data to show — every field
      // below lives on ForfeitedPackageModel, and the screen was passing only
      // the package.
      expect(appeal, contains('tenderHistoryFor: f,'));
    });

    test('a section renders it', () {
      expect(dialog, contains('class _AppealHistorySection'));
      expect(dialog, contains('_AppealHistorySection('));
    });
  });

  group('it shows what the officer came to check', () {
    final section = dialog.substring(
        dialog.indexOf('class _AppealHistorySection'),
        dialog.indexOf('class _DisposalExpenseBreakdown'));

    test('the dates', () {
      expect(section, contains("label: 'Forfeited on'"));
      expect(section, contains("label: 'Appeal deadline'"));
      expect(section, contains("label: 'Decided on'"));
    });

    test('the hold, and why it was placed', () {
      expect(section, contains("label: 'Hold placed on'"));
      expect(section, contains("label: 'Reason for the hold'"));
    });

    test('the ruling and its note', () {
      expect(section, contains("label: 'Ruling'"));
      expect(section, contains('note!.trim()'));
    });

    test('the state is worded as the tables word it', () {
      // An officer reading "On Appeal Hold" in the table must meet the same
      // phrase in the popup, not a synonym.
      expect(section, contains("'On Appeal Hold'"));
      expect(section, contains("'In appeal window'"));
      expect(section, contains("Decided · "));
    });
  });

  group('a ruling is per ITEM', () {
    final section = dialog.substring(
        dialog.indexOf('class _AppealHistorySection'),
        dialog.indexOf('class _DisposalExpenseBreakdown'));

    test('it reads this item\'s decision, not the package\'s', () {
      // ⚠️ Rulings live in item_appeal_decisions, keyed by item. One SR can
      // hold an item ruled DESTROY beside one ruled RE-EXPORT — showing the
      // package's own field would report one of them for both.
      expect(section, contains('f.itemAppealDecisions[itemId]'));
      expect(section, contains("raw?['decision'] as String?"));
    });

    test('the package fields remain the fallback', () {
      // Rows decided before per-item rulings existed still carry theirs at
      // package level.
      expect(section, contains('?? f.appealDecision'));
      // ⚠️ A ternary, not `??`: the JSON key may be present-but-null, which
      // `??` on the parsed DateTime would not catch.
      expect(section, contains(': f.appealDecidedAt;'));
    });
  });

  group('the deadline is only red while it still means something', () {
    final section = dialog.substring(
        dialog.indexOf('class _AppealHistorySection'),
        dialog.indexOf('class _DisposalExpenseBreakdown'));

    test('a decided appeal does not flag its passed deadline', () {
      // Once a ruling is in, a deadline in the past is history — colouring it
      // red would report a problem that has already been dealt with.
      expect(section, contains('!decided &&'));
      expect(section, contains('!f.appealHold &&'));
    });
  });

  group('a ruling outranks the item status', () {
    test('the destruction panel is withheld when the appeal ruled otherwise',
        () {
      // ⚠️ CED/GL1/SR/03/2025 held Latex Gloves whose status still read
      // `destroyed` while the Directorate had ruled SALE — so a row the
      // Decided Goods table labels "Decided · Sell" opened showing a
      // DESTRUCTION STATUS panel. The status is what the yard recorded before
      // the appeal; the ruling is the later word.
      expect(dialog, contains('_appealRuledAwayFromDestruction'));
      expect(dialog, contains("decision != 'DESTROY'"));
    });

    test('a DESTROY ruling still shows it', () {
      // The panel is right there — withholding it would hide the costs of a
      // destruction the Directorate itself ordered.
      final fn = dialog.substring(
          dialog.indexOf('bool _appealRuledAwayFromDestruction'),
          dialog.indexOf('class _AppealHistorySection'));
      expect(fn, contains("if (decision.isEmpty) return false;"),
          reason: 'no ruling must leave the status to decide, as before');
    });
  });

  group('the seed cannot rule on goods that no longer exist', () {
    test('already-destroyed items are excluded from appeal rulings', () {
      // An appeal cannot order goods re-exported after they have been
      // destroyed. Seven seeded rows did exactly that.
      final seed = File('tool/seed_test_data.dart').readAsStringSync();
      expect(seed, contains("('destroyed', 'supposed to be destroyed')"));
    });
  });
}
