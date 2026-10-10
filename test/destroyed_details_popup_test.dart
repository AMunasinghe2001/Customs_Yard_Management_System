import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ⚠️ Both files are normalised to LF. They are CRLF on disk, so a search for
/// a line-terminated marker never matches and every "read to the end of this
/// function" window silently became the whole file — which is how the first
/// version of these tests passed while the screen was still wrong.
String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final dialog = _read('lib/widgets/package_details_dialog.dart');
  final disposal = _read('lib/screens/disposal/disposal_dashboard_screen.dart');

  /// The body of `_showDestroyedDetails`, to the next top-level declaration.
  ///
  /// ⚠️ NOT to the first `\n}`. That matches the closing brace of the
  /// PARAMETER LIST — the handler takes named arguments — so the window was
  /// 151 characters and every assertion below it was passing on text it had
  /// never seen. A fixed character count is no better: the comments inside
  /// this function have already outgrown two of them.
  String handler() {
    final at = disposal.indexOf('Future<void> _showDestroyedDetails(');
    expect(at, greaterThan(-1), reason: 'the handler was renamed');
    final next = RegExp(r'\n(?=class |Future<|void |String |Widget )')
        .firstMatch(disposal.substring(at + 10));
    expect(next, isNotNull, reason: 'no declaration follows the handler');
    return disposal.substring(at, at + 10 + next!.start);
  }

  group('the status shown is the ITEM the row was opened for', () {
    test('the table row names its item to the dialog', () {
      // ⚠️ Passing only highlightEntry was NOT enough, which is why the first
      // attempt at this fix changed nothing on screen. The dialog resolves an
      // item from the entry with `orElse: () => p.items.first`, so a
      // package-level entry (packageItemId null) silently picked the FIRST
      // item — and in CED/GL1/SR/03/2025 that is Latex Gloves, already
      // destroyed, while the row clicked was the pending Aluminium Foil
      // Rolls. highlightItemId skips the fallback entirely.
      expect(handler(), contains('highlightItemId: r.item?.id'));
    });

    test('the section is given the highlighted item', () {
      // CED/GL1/SR/01/2025 holds two items: Ceramic Sanitaryware, already
      // destroyed, and an Engine Cylinder Block still pending. The section
      // asked `package.items.any(destroyed)`, so opening the PENDING row
      // reported DESTROYED — contradicting the very table it was clicked
      // from.
      expect(dialog, contains('item: highlightedItem,'));
      expect(dialog, contains('final PackageItem? item;'));
    });

    test('it reads that item, not any sibling', () {
      final at = dialog.indexOf('final bool isDestroyed;');
      expect(at, greaterThan(-1), reason: 'the per-item branch is gone');
      final body = dialog.substring(at, at + 700);
      expect(body, contains('if (item != null)'));
      expect(body, contains('e.packageItemId == item!.id'),
          reason: 'a sibling warehouse entry would still leak in');
    });

    test('a whole-package view still works', () {
      // The section is used without an item elsewhere; that path must remain.
      final at = dialog.indexOf('final bool isDestroyed;');
      final body = dialog.substring(at, at + 900);
      expect(body, contains('} else {'));
      expect(body, contains('package.items.any'));
    });
  });

  group('the details popup opens at once', () {
    test('the ledger is not awaited before showing it', () {
      // ⚠️ The handler awaited srFinancialsProvider — "the heaviest query in
      // the app" by its own comment — BEFORE calling showAppDialog. The
      // button sat dead for about two seconds with no sign the tap had
      // registered, people clicked again, and when the await returned both
      // dialogs opened stacked.
      expect(handler().contains('await ref.read(srFinancialsProvider.future)'),
          isFalse,
          reason: 'the heavy query is awaited before the popup again');
      expect(handler(), contains('showAppDialog('));
    });

    test('the costs fill in once the ledger arrives', () {
      // Opening instantly is only right if the figure still appears.
      final flat = handler().replaceAll(RegExp(r'\s+'), ' ');
      expect(flat, contains('dialogRef .watch(srFinancialsProvider)'));
      expect(flat, contains('srFinancials: sr'));
    });

    test('it reads valueOrNull, so a slow ledger never blocks the popup', () {
      // A ledger error or a cold fetch costs the costs section and nothing
      // else — which is what the old try/catch was reaching for.
      expect(handler(), contains('valueOrNull'));
    });
  });

  group('no in-flight guard is ever reintroduced', () {
    // ⚠️ Two were tried and BOTH killed the page. Each held a flag across
    // `await showAppDialog(...)`, which does not return until the dialog is
    // DISMISSED — so the flag stayed set for the popup's whole life, and any
    // early `return` before the dialog (a `!context.mounted` check, an error
    // path) left it set for good. Every button on the table then did nothing,
    // twenty and thirty presses on.
    //
    // The double-popup that prompted them is a symptom of a stalled frame
    // swallowing the first tap. Fix the stall; never trade a working button
    // for it.
    test('the Details handler holds no flag', () {
      expect(handler().contains('_destroyedPopupOpening'), isFalse);
      expect(handler().contains('} finally {'), isFalse,
          reason: 'a finally around the dialog await holds it until close');
    });

    test('the Costs handler holds no flag', () {
      final at = disposal.indexOf('class _RecordCostsButton');
      expect(at, greaterThan(-1));
      // ⚠️ Comment lines stripped first. The note explaining WHY there is no
      // guard names the old `static bool _opening`, and a plain substring
      // search matched its own documentation.
      final costs = disposal
          .substring(at, at + 3000)
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(costs.contains('static bool _opening'), isFalse);
      expect(costs.contains('if (_opening) return;'), isFalse);
    });
  });
}
