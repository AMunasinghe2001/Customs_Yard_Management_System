// Goods that were admitted into no warehouse, and forfeited goods that
// reached no Forfeited table -- both without a single error anywhere.
//
// ⚠️ THE BUG, reported directly: CED/GL1/SR/05/2026 showed its two items in
// the SR popup with no "Storage & Movement" section at all, while
// CED/GL1/SR/02/2026 beside it had one. Neither package had a
// forfeited_packages row, so the Forfeited Goods table read "No forfeited
// packages found" for four plainly-forfeited items.
//
// Nothing in the database refused the writes -- inserting both rows by hand
// as the yard's own user succeeded. The writes were never ATTEMPTED, and
// every path that could have said so was written to stay quiet:
//
//   * `addEntry` inserted without `.select()`, so a refusal returned
//     quietly and the caller reported success.
//   * It also passed `AppSession.currentYard` straight through. Empty is not
//     a yard, and `warehouse_entries` carries a RESTRICTIVE per-yard policy
//     that refuses it -- which is what an expired session produces.
//   * The repair sync wrapped its ENTIRE package loop in one try/catch that
//     only warned, so one failing package silently abandoned the repair for
//     every package after it.
//   * Both "find a target warehouse" branches ended in a bare `if` with no
//     `else`, so an item with no resolvable warehouse was skipped in silence.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _admittedIsTheEntryDate();
  final services = File('lib/services/services.dart').readAsStringSync();
  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
  final f = flat(services);

  group('admitting goods cannot fail quietly', () {
    test('an empty yard is refused before the database has to', () {
      // The policy refuses it anyway; the point is to refuse it where the
      // officer can see it, instead of inside a background sync.
      expect(f, contains('final entryYard = AppSession.currentYard;'));
      expect(f, contains("if (entryYard.isEmpty) {"));
      // ⚠️ Only the first half of the sentence: the literal is split across
      // two adjacent Dart string pieces, so the joined text never appears
      // contiguously in the SOURCE, whatever `dart format` does to it.
      expect(f, contains('Cannot admit goods to a warehouse without a yard'));
    });

    test('the insert is read back, so a refusal is visible', () {
      final fn = f.substring(f.indexOf('Future<void> addEntry('));
      expect(fn.substring(0, 1800), contains(".select('id')"));
      expect(fn.substring(0, 1800), contains('The warehouse entry was not written'));
    });
  });

  group('the repair sync repairs what it still can', () {
    test('one bad package does not abandon the rest', () {
      // ⚠️ The per-package catch, not the outer one. With only the outer
      // catch the loop stopped at the first failure and warned once.
      final fn = f.substring(f.indexOf('syncMissingWarehouseAndForfeitEntries() async'));
      expect(fn.substring(0, 6000),
          contains('Auto-sync skipped one package'));
    });

    test('a refused repair is not mistaken for a repair', () {
      final fn = f.substring(f.indexOf('syncMissingWarehouseAndForfeitEntries() async'));
      expect(fn.substring(0, 6000), contains('refused by policy'));
    });

    test('an item with nowhere to go says so', () {
      // Both call sites: the sync and the package-update path. A bare `if`
      // with no `else` is what made this invisible in the first place.
      expect(f, contains('it stays unwarehoused'));
      expect(f, contains('— not admitted'));
    });
  });
}

// ── The admitted date is the SR's entry date, not the moment of the click ──
//
// ⚠️ Reported directly: the SR popup's Storage & Movement card showed
// "Admitted 16 Sep 2026" for goods whose SR entry date was 8 Jan 2026, and
// "Days so far 1" for goods that had been in the yard since January. The two
// readings are the same bug: `storageDays` counts from `admittedAt`, so an
// admitted date stamped with DateTime.now() resets the clock -- and with it
// the storage charge -- to the day the row happened to be written.
void _admittedIsTheEntryDate() {
  final services = File('lib/services/services.dart').readAsStringSync();
  final inspection =
      File('lib/screens/inspection/inspection_screen.dart').readAsStringSync();
  final models = File('lib/models/models.dart').readAsStringSync();
  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

  group('admitted on the entry date', () {
    test('addEntry takes the date rather than assuming now', () {
      final f = flat(services);
      final fn = f.substring(f.indexOf('Future<void> addEntry('));
      expect(fn.substring(0, 400), contains('DateTime? admittedAt'));
      // now() survives ONLY as the fallback for a caller that has no date.
      expect(fn.substring(0, 2200),
          contains("'admitted_at': (admittedAt ?? DateTime.now())"));
    });

    test('every caller hands it the SR entry date', () {
      // Three: the inspection screen that admits the goods, and the create
      // and update paths that back-fill a missing entry.
      expect(flat(inspection), contains('admittedAt: saved.entryDate'));
      final f = flat(services);
      expect(f, contains('admittedAt: created.entryDate'));
      expect(f, contains('admittedAt: result.entryDate'));
    });

    test('the repair sync back-dates too', () {
      // It inserts directly rather than through addEntry, so it needs the
      // same rule spelled out -- otherwise a repaired row restarts the clock.
      final f = flat(services);
      final fn = f.substring(f.indexOf('syncMissingWarehouseAndForfeitEntries() async'));
      expect(fn.substring(0, 6000),
          contains("'admitted_at': entryDate.toIso8601String()"));
    });

    test('days so far counts from admission to today, inclusive', () {
      final f = flat(models);
      final fn = f.substring(f.indexOf('int get storageDays {'));
      expect(fn.substring(0, 400), contains('returnedAt ?? DateTime.now()'));
      // ⚠️ +1: a package admitted today has been in the yard for one day,
      // not zero -- the yard charges for the day it arrives.
      expect(fn.substring(0, 400), contains('.inDays + 1'));
    });
  });
}
