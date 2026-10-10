// The yard's own popups, in one chrome.
//
// ⚠️ Reported directly, with screenshots: "Release Goods to Owner", "Release
// Sold Goods to Buyer" and "Mark as Destroyed" came up in cream and pink
// boxes, while the SR Register Entry popup the officer had just closed was
// the yard's navy. StyledFormDialog has three looks — the yard's navy
// gradient (`yard: true`), the directorate's light tint (the default) and
// ICT's flat panel (`erp: true`) — and these three simply never said which
// they wanted, so they fell to the directorate's.
//
// ⚠️ An accent is NOT a header. Passing `headerAccentColor` alone (gold for a
// hand-over, red for a destruction) tinted the default header instead of
// riding on the yard's bar, which is why they looked like a different kind
// of dialog rather than the same dialog about a different act.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

  group('the yard hand-over form wears the yard chrome', () {
    final f = flat(
        File('lib/widgets/handover_form_dialog.dart').readAsStringSync());

    test('it declares yard, not just an accent', () {
      expect(f, contains("label: 'HAND-OVER',"));
      expect(f, contains('yard: true,'));
    });

    test('the accent survives, for the icon and the commit button', () {
      // Red/gold belongs ON the bar, not instead of it.
      expect(f, contains('headerAccentColor: context.colors.primaryGold,'));
    });
  });

  group('Mark as Destroyed wears the chrome of the page it opens on', () {
    // ⚠️ Two pages reach the same act, and they must NOT match: Destroyed
    // Goods is the yard's page and takes the navy bar; the Disposal
    // portal's destruction tab is a directorate page and keeps the light
    // tint. A navy header there would be the yard's chrome on someone
    // else's page -- the same mistake in reverse, and
    // ict_cannot_edit_personal_details_test.dart guards exactly that.
    ({String label, String title, String accent, bool yard}) destroyDialog(
        String path) {
      final f = flat(File(path).readAsStringSync());
      final i = f.indexOf("label: 'DESTROY GOODS',");
      expect(i, greaterThan(-1), reason: 'the destroy dialog is gone');
      // A window after the label: an explanatory comment sits between the
      // arguments, so they are not adjacent in the source.
      final seg = f.substring(i, i + 700);
      return (
        label: 'DESTROY GOODS',
        title: seg.contains("title: 'Mark as Destroyed',") ? 'ok' : 'missing',
        accent: seg.contains('headerAccentColor: ctx.colors.dangerRed,')
            ? 'red'
            : 'none',
        yard: seg.contains('yard: true,'),
      );
    }

    test("the yard's copy takes the navy bar", () {
      final d = destroyDialog(
          'lib/screens/packages/disposition_category_screen.dart');
      expect(d.title, 'ok');
      expect(d.yard, isTrue);
      expect(d.accent, 'red');
    });

    test("the Disposal portal's copy keeps its own tint", () {
      final d = destroyDialog(
          'lib/screens/disposal/disposal_dashboard_screen.dart');
      expect(d.title, 'ok');
      expect(d.yard, isFalse,
          reason: 'a directorate page took the yard header');
      expect(d.accent, 'red');
    });
  });

  group('no yard-side dialog is left undeclared', () {
    test('every StyledFormDialog on the yard pages names its chrome', () {
      // ⚠️ The default is the DIRECTORATE's look, so "said nothing" and
      // "wanted the directorate" are indistinguishable in the source. On the
      // yard's own pages the answer is always the yard, so leaving it unsaid
      // is how these three drifted.
      final files = <String>[
        ...Directory('lib/screens/packages')
            .listSync(recursive: true)
            .whereType<File>()
            .map((f) => f.path),
        ...Directory('lib/screens/warehouses')
            .listSync(recursive: true)
            .whereType<File>()
            .map((f) => f.path),
        'lib/widgets/handover_form_dialog.dart',
        'lib/widgets/confirm_dialog.dart',
      ].where((p) => p.endsWith('.dart'));

      final offenders = <String>[];
      for (final p in files) {
        final src = File(p).readAsStringSync();
        for (final m in RegExp(r'StyledFormDialog\(').allMatches(src)) {
          var seg = src.substring(
              m.end, (m.end + 1400).clamp(0, src.length));
          final cut = seg.indexOf('child:');
          if (cut > 0) seg = seg.substring(0, cut);
          if (seg.contains('yard:') || seg.contains('erp:')) continue;
          final line =
              '\n'.allMatches(src.substring(0, m.start)).length + 1;
          offenders.add('$p:$line');
        }
      }
      expect(offenders, isEmpty,
          reason: 'undeclared chrome at: ${offenders.join(', ')}');
    });
  });
}
