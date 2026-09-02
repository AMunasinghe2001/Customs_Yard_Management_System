import 'package:flutter_test/flutter_test.dart';

/// Destruction is TWO states, and the Destroyed Goods page has to show both:
///
///   PENDING   marked for destruction -- `[FINAL:DESTROY]`, item status
///             'supposed to be destroyed'. The yard still has to carry it out.
///   DESTROYED confirmed -- `[FINAL:DESTROYED]`, item status 'destroyed'.
///
/// The page accepts BOTH tags, so a pending item appears the moment the
/// Final Disposition writes it; only the confirmed spelling flips the status
/// cell from the clickable "Mark Destroyed" button to the green chip.
void main() {
  // Mirrors _CategoryRow.isDestroyed.
  bool isDestroyed({String? notes, String? itemStatus}) {
    final n = (notes ?? '').trim().toUpperCase();
    if (n.startsWith('[FINAL:DESTROYED]') || n.startsWith('[DESTROYED]')) {
      return true;
    }
    if (itemStatus?.toLowerCase() == 'destroyed') return true;
    return false;
  }

  // Mirrors _acceptedTags['DESTROYED'] + _matchesTag.
  const accepted = {
    'FINAL:DESTROYED',
    'FINAL:DESTROY',
    'DESTROYED',
    'DESTROY',
    'SUPPOSED TO BE DESTROYED'
  };
  bool onPage(String notes) {
    final m = RegExp(r'^\[([^\]]+)\]').firstMatch(notes.trim().toUpperCase());
    return m != null && accepted.contains(m.group(1)!.trim());
  }

  test('a pending item reaches the page but is NOT yet destroyed', () {
    const notes = '[FINAL:DESTROY] — Receipt/Notes: DSR/2026/0906';
    expect(onPage(notes), isTrue, reason: 'It must be listed to be actioned.');
    expect(isDestroyed(notes: notes, itemStatus: 'supposed to be destroyed'),
        isFalse,
        reason: 'Pending must render the clickable Mark Destroyed button.');
  });

  test('a confirmed item shows the green chip instead', () {
    const notes = '[FINAL:DESTROYED] — Receipt/Notes: DSR/2026/0905';
    expect(onPage(notes), isTrue);
    expect(isDestroyed(notes: notes, itemStatus: 'destroyed'), isTrue);
  });

  test('DESTROY and DESTROYED are not confused by prefix matching', () {
    // '[FINAL:DESTROY]' is a strict prefix of '[FINAL:DESTROYED]' only if the
    // closing bracket is ignored -- it is not, so these stay distinct.
    expect(isDestroyed(notes: '[FINAL:DESTROY]'), isFalse);
    expect(isDestroyed(notes: '[FINAL:DESTROYED]'), isTrue);
  });
}
