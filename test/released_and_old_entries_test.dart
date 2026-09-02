// Released Goods and Old Entries: two pages that were empty because nothing
// ever wrote the data they read.
//
// Neither has a table of its own. A release is a warehouse_entries row flipped
// to is_returned, and a migrated package is one whose old_sr_number is set --
// so both pages stayed blank until those were seeded.
import 'package:flutter_test/flutter_test.dart';

/// Mirrors `_isReleaseEntry` in returned_packages_screen.dart.
///
/// ⚠️ A returned entry is not automatically a RELEASE. A note starting with
/// "[" is a disposition tag ([FINAL:DESTROYED], [FINAL:OTHER]...) recorded on
/// the same is_returned flag, and those must NOT appear on Released Goods.
bool isReleaseEntry({required bool isReturned, String? returnNotes}) {
  if (!isReturned) return false;
  final notes = (returnNotes ?? '').trim().toUpperCase();
  if (notes.isEmpty) return true;
  if (!notes.startsWith('[')) return true; // free-text receipt note
  return notes.startsWith('[FINAL:RELEASED]') || notes.startsWith('[RELEASE');
}

/// Mirrors `_extractReceiptNo` — the receipt number is parsed back OUT of the
/// notes string, because there is no receipt column.
String? extractReceiptNo(String? notes) {
  if (notes == null || notes.trim().isEmpty) return null;
  for (final part in notes.split('|')) {
    final text = part.trim();
    if (text.toLowerCase().startsWith('receipt no:')) {
      final idx = text.indexOf(':');
      if (idx != -1) return text.substring(idx + 1).trim();
    }
  }
  return null;
}

void main() {
  group('a released entry reaches the Released Goods page', () {
    // The exact shape the seeder writes, and the shape the release dialog
    // writes: "Receipt No: <no> | Date: <date>".
    const seeded = 'Receipt No: RCP/GL1/2026/4029 | Date: 2026-08-27';

    test('the seeded note is recognised as a release', () {
      expect(isReleaseEntry(isReturned: true, returnNotes: seeded), isTrue);
    });

    test('its receipt number parses back out of the note', () {
      expect(extractReceiptNo(seeded), 'RCP/GL1/2026/4029');
    });

    test('a note that is not returned is never a release', () {
      expect(isReleaseEntry(isReturned: false, returnNotes: seeded), isFalse);
    });

    // ⚠️ This is the trap: writing a released row with a bracketed note would
    // file it as a disposition and it would vanish from the page entirely.
    test('a disposition tag is NOT shown as a release', () {
      expect(
          isReleaseEntry(
              isReturned: true, returnNotes: '[FINAL:DESTROYED] burnt'),
          isFalse);
      expect(
          isReleaseEntry(isReturned: true, returnNotes: '[FINAL:OTHER] x'),
          isFalse);
    });

    test('an explicit release tag still counts', () {
      expect(
          isReleaseEntry(
              isReturned: true, returnNotes: '[FINAL:RELEASED] to owner'),
          isTrue);
    });

    test('a receipt number is absent when the note does not carry one', () {
      expect(extractReceiptNo('Handed over at the gate'), isNull);
      expect(extractReceiptNo(null), isNull);
      expect(extractReceiptNo(''), isNull);
    });

    test('extra notes after the date do not break the receipt', () {
      expect(
          extractReceiptNo(
              'Receipt No: RCP/1 | Date: 2026-01-01 | Notes: collected'),
          'RCP/1');
    });
  });

  group('an old entry is a package carried over from a previous register', () {
    // The old register was kept by hand in a different shape: no directorate
    // prefix, no yard segment. It is deliberately NOT a valid new SR number --
    // that is what makes it recognisably old.
    test('the seeded old number does not look like a current SR number', () {
      const old = 'SR/1780/2021';
      expect(old.split('/').length, lessThan(5));
      expect(old.startsWith('CED/'), isFalse);
    });

    test('the new number keeps the current shape', () {
      const current = 'CED/GL1/OA/02/2024';
      expect(current.split('/').length, 5);
    });
  });
}
