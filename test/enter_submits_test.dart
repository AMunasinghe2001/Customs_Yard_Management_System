import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cus_yard_management/core/theme.dart';

/// Every login and sign-up field should submit on Enter, so an OTP can be
/// typed and confirmed without reaching for the mouse.
///
/// The behaviour test proves `onFieldSubmitted` really fires; the source scan
/// proves no screen was missed, which is the part that kept regressing — the
/// coverage was uneven across the seven portals.
void main() {
  testWidgets('pressing Enter in a field fires its submit handler',
      (tester) async {
    var submitted = 0;
    final ctrl = TextEditingController();

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: TextFormField(
          controller: ctrl,
          onFieldSubmitted: (_) => submitted++,
        ),
      ),
    ));

    await tester.enterText(find.byType(TextFormField), '123456');
    expect(submitted, 0, reason: 'typing alone must not submit');

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(submitted, 1, reason: 'Enter did not submit');
  });

  test('no auth screen is missing an Enter handler', () {
    // Walks the real screens rather than a fixture: a new portal added later
    // without keyboard submit should fail here.
    final dir = Directory('lib/screens');
    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('login_screen.dart') ||
            f.path.endsWith('signup_screen.dart'))
        // auth/signup_screen.dart is dead code: nothing imports or routes it.
        .where((f) => !f.path.replaceAll(r'\', '/').endsWith(
            'screens/auth/signup_screen.dart'))
        .toList();

    expect(files, isNotEmpty, reason: 'no auth screens found');

    // The fields that carry the flow. A screen may not have all of them.
    final interesting = RegExp(
        r'_(otpCtrl|passwordCtrl|emailCtrl|idCtrl|confirmCtrl|newPassCtrl|'
        r'confirmPassCtrl|usernameCtrl|firstNameCtrl|lastNameCtrl|salaryCtrl)');

    final problems = <String>[];
    for (final f in files) {
      final src = f.readAsStringSync();
      for (final m in RegExp(r'(TextFormField|TextField)\(').allMatches(src)) {
        // Slice the widget from its '(' to the matching ')'.
        var i = src.indexOf('(', m.start);
        var depth = 0;
        var j = i;
        while (j < src.length) {
          if (src[j] == '(') depth++;
          if (src[j] == ')') {
            depth--;
            if (depth == 0) break;
          }
          j++;
        }
        final body = src.substring(i, j);
        final ctrl = RegExp(r'controller: (\w+),').firstMatch(body);
        if (ctrl == null) continue;
        final name = ctrl.group(1)!;
        if (!interesting.hasMatch(name)) continue;
        if (body.contains('onFieldSubmitted') || body.contains('onSubmitted')) {
          continue;
        }
        final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
        problems.add('${f.path.split('screens')[1]}:$line  $name');
      }
    }

    expect(problems, isEmpty,
        reason: 'these fields do not submit on Enter:\n${problems.join('\n')}');
  });
}
