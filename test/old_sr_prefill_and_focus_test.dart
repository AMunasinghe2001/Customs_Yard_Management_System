import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Two officer-facing fixes to the SR registration form's "Old Entry" flow
/// and the Register (SR/OA) picker.
///
/// ⚠️ These check for the SUBSTANCE of each behaviour (a helper that exists
/// and is called from the right place, a FocusNode that is created, disposed
/// and requested), not an exact multi-line source match — `dart format`
/// rewraps long call sites whenever nearby code changes width, and this file
/// has been the site of that exact false failure more than once this session.
void main() {
  String read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');
  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

  final src = flat(read('lib/screens/inspection/inspection_screen.dart'));

  group('Old SR Number gets a starting template', () {
    test('a prefill helper exists and uses the signed-in yard prefix', () {
      expect(src, contains('_prefillOldSrTemplate'));
      expect(src, contains('yardSrPrefix('));
      // The template must include the CURRENT year, not a stored one — the
      // whole point is that the old register's year is unknown to this app.
      expect(src, contains('DateTime.now().year'));
    });

    test('it carries the directorate prefix, like every other SR number', () {
      // ⚠️ The first version hand-assembled a literal 'prefix/SR/01/year' string, and left the
      // directorate segment off — 'GL1/SR/01/2026' instead of
      // 'CED/GL1/SR/01/2026'. Reported directly: the New Entry number on the
      // same form shows the CED prefix and the Old SR template did not, so
      // the two fields disagreed about what a valid SR number even looks
      // like. Reusing composeSrNumber is what makes that impossible to
      // reintroduce -- it is the SAME builder the New Entry field calls.
      final body = src.substring(src.indexOf('void _prefillOldSrTemplate'),
          src.indexOf('}', src.indexOf('void _prefillOldSrTemplate')) + 400);
      expect(body, contains('composeSrNumber('),
          reason: 'the template is assembled by hand again, instead of '
              'through the one builder every SR number goes through');
      expect(body, contains('directorateCode: AppSession.currentDirectorate'),
          reason: 'the directorate prefix is missing from the template');
    });

    test('it never overwrites something already typed', () {
      // A real old number must survive a mode toggle or a reload; only an
      // EMPTY field is a candidate for the template.
      final i = src.indexOf('_prefillOldSrTemplate()');
      expect(i, greaterThan(-1));
      final body = src.substring(src.indexOf('void _prefillOldSrTemplate'),
          src.indexOf('}', src.indexOf('void _prefillOldSrTemplate')) + 400);
      expect(body, contains('.text.trim().isNotEmpty) return'),
          reason: 'the template can run over a real old number the officer '
              'already typed');
    });

    test('choosing Old Entry is what triggers it', () {
      // The prefill must be reachable from the Registration Type toggle,
      // not just exist in isolation.
      final toggle = src.substring(src.indexOf("label: 'Registration Type'"),
          src.indexOf("label: 'Registration Type'") + 1200);
      expect(toggle, contains('_prefillOldSrTemplate()'),
          reason: 'switching to Old Entry does not fill the template');
    });
  });

  group('picking SR/OA hands focus to the number field', () {
    test('a dedicated FocusNode exists for the SR number field', () {
      expect(src, contains('_srNumberFocus'));
      expect(src, contains('FocusNode()'));
      expect(src, contains('_srNumberFocus.dispose()'),
          reason: 'the focus node is created but never disposed');
    });

    test('the SR number field actually uses that focus node', () {
      final field = src.substring(src.indexOf('controller: _srNumberCtrl,'),
          src.indexOf('controller: _srNumberCtrl,') + 400);
      expect(field, contains('focusNode: _srNumberFocus'),
          reason: 'the field is not wired to the dedicated focus node, so '
              'requesting it does nothing visible');
    });

    test('the Register dropdown requests that focus after picking', () {
      final registerBlock = src.substring(src.indexOf("label: 'Register',"),
          src.indexOf("label: 'Register',") + 1600);
      expect(registerBlock, contains('_srNumberFocus.requestFocus()'),
          reason: 'choosing SR/OA still leaves the officer to click the '
              'number field themselves');
    });

    test('the generated text is selected, not just focused', () {
      // Focus alone would put the caret at the end; selecting the whole
      // value is what lets typing REPLACE the generated number outright.
      final registerBlock = src.substring(src.indexOf("label: 'Register',"),
          src.indexOf("label: 'Register',") + 1600);
      expect(registerBlock, contains('TextSelection('));
      expect(registerBlock, contains('baseOffset: 0'));
    });
  });
}
