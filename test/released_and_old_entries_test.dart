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

  group('a completed "Other" process is read-only', () {
    // An "Other" item still being worked shows an appeal state and offers
    // actions. Once the yard records the outcome the process is OVER: the row
    // becomes a completed, read-only record with a _CompletedChip instead.
    // Only a [FINAL:OTHER] entry produces that.
    bool isFinalOther(String? notes) =>
        (notes ?? '').trim().toUpperCase().startsWith('[FINAL:OTHER]');

    /// Mirrors `_finalOtherLabel` -- the outcome text shown on the chip.
    String finalOtherLabel(String? notes) {
      final n = (notes ?? '').trim();
      final m = RegExp(r'^\[FINAL:OTHER\]\s*—\s*(.+)$',
              caseSensitive: false)
          .firstMatch(n);
      if (m != null) {
        final t = m.group(1)!.trim();
        if (t.isNotEmpty) return t;
      }
      return 'Other';
    }

    test('the seeded tag marks the row completed', () {
      expect(isFinalOther('[FINAL:OTHER] — Donated to a charity'), isTrue);
      expect(isFinalOther('Receipt No: RCP/1 | Date: 2026-01-01'), isFalse);
    });

    // ⚠️ The separator is an EM DASH. A hyphen still marks the row completed,
    // but the label falls back to a bare "Other" and the outcome is lost --
    // a silent failure that looks like working data.
    test('an em dash carries the outcome text; a hyphen loses it', () {
      expect(finalOtherLabel('[FINAL:OTHER] — Handed over to the Police'),
          'Handed over to the Police');
      expect(finalOtherLabel('[FINAL:OTHER] - Handed over to the Police'),
          'Other');
    });

    test('a tag with no outcome text falls back to "Other"', () {
      expect(finalOtherLabel('[FINAL:OTHER]'), 'Other');
    });

    test('both routes into the completed state are distinguishable', () {
      // The yard reaches this state two ways and they look identical
      // afterwards, so the outcome text is what tells them apart.
      expect(finalOtherLabel('[FINAL:OTHER] — Released on appeal ruling'),
          contains('appeal'));
      expect(finalOtherLabel('[FINAL:OTHER] — Transferred to Government Use'),
          isNot(contains('appeal')));
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
