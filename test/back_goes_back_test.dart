import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/widgets/styled_dropdown.dart';
import 'package:cus_yard_management/core/theme.dart';
import 'package:flutter/material.dart';

/// The back arrow returns to the PREVIOUS page, not to a fixed one.
///
/// ⚠️ Every one of these used to `context.go()` somewhere hard-coded — the
/// portal chooser, or a sign-in page — so an officer who had reached the
/// screen from somewhere else was thrown out to the front door instead of back
/// to where they were.
void main() {
  const backButton = 'lib/widgets/auth_back_button.dart';

  group('the arrow pops history when there is any', () {
    final src = File(backButton).readAsStringSync();

    test('it pops rather than navigating to a fixed route', () {
      expect(src, contains('context.canPop()'));
      expect(src, contains('context.pop()'));
    });

    test('and falls back only when there is nothing to pop', () {
      // A deep link, a fresh launch, or a go() that replaced the stack all
      // leave no history — the arrow must still do something sensible.
      expect(src, contains('context.go(widget.fallbackRoute)'));
      expect(src, contains("this.fallbackRoute = '/'"));
    });
  });

  group('no auth screen hard-codes a plain back destination', () {
    // The signup screens: their back arrow should pop, with the sign-in page
    // only as the fallback.
    const signups = [
      ('lib/screens/admin/admin_signup_screen.dart', '/admin/login'),
      ('lib/screens/appeal/appeal_signup_screen.dart', '/appeal/login'),
      ('lib/screens/disposal/disposal_signup_screen.dart', '/disposal/login'),
      ('lib/screens/executive/executive_signup_screen.dart', '/executive/login'),
      ('lib/screens/ict/ict_signup_screen.dart', '/ict/login'),
      ('lib/screens/valuation/valuation_signup_screen.dart', '/valuation/login'),
    ];

    for (final (path, fallback) in signups) {
      test('${path.split('/').last} uses a fallback, not a jump', () {
        final src = File(path).readAsStringSync();
        expect(src, contains("fallbackRoute: '$fallback'"),
            reason: '$path must name where to go only when history is empty');
        // ⚠️ Scoped to the AuthBackButton. The "Sign In" link lower down
        // the form navigates to the same route on purpose — that is a
        // deliberate destination, not a back gesture.
        final i = src.indexOf('AuthBackButton(');
        expect(i, greaterThan(-1), reason: '$path has no back button');
        final end = (i + 300) < src.length ? i + 300 : src.length;
        expect(src.substring(i, end).contains('onPressed:'), isFalse,
            reason: '$path back arrow still jumps to a fixed page');
      });
    }
  });

  group('the login screens still end the session on the way out', () {
    // ⚠️ These keep an onPressed — not to choose a destination, but because
    // leaving a half-finished sign-in must sign out first. Popping alone
    // would leave the expired session alive.
    const logins = [
      'lib/screens/login/login_screen.dart',
      'lib/screens/admin/admin_login_screen.dart',
      'lib/screens/ict/ict_login_screen.dart',
      'lib/screens/disposal/disposal_login_screen.dart',
      'lib/screens/appeal/appeal_login_screen.dart',
      'lib/screens/valuation/valuation_login_screen.dart',
      'lib/screens/executive/executive_login_screen.dart',
    ];

    for (final path in logins) {
      test('${path.split('/').last} signs out before leaving', () {
        final src = File(path).readAsStringSync();
        expect(src, contains('abandonSignIn(ref)'),
            reason: '$path must not leave a live session behind');
      });
    }
  });

  group('the Position dropdown matches the fields under it', () {
    const signups = [
      'lib/screens/appeal/appeal_signup_screen.dart',
      'lib/screens/disposal/disposal_signup_screen.dart',
      'lib/screens/valuation/valuation_signup_screen.dart',
      'lib/screens/executive/executive_signup_screen.dart',
      'lib/screens/ict/ict_signup_screen.dart',
    ];

    for (final path in signups) {
      test('${path.split('/').last} sizes it like a TextFormField', () {
        // ⚠️ This used to assert the OPPOSITE: `isDense: false` and
        // `vertical: 16` on every one of these dropdowns.
        //
        // That was a per-screen workaround for a bug in the widget itself.
        // StyledDropdownFormField forced `labelStyle: fontSize 12`, and a
        // smaller label makes the decorator reserve less height — so the
        // dropdown came out shorter than the fields under it whatever padding
        // the screen passed. Five screens each carried their own correction.
        //
        // The widget now takes the theme's label and padding like any other
        // field, so the fix is in ONE place and the screens must not restate
        // it. A screen that reintroduces an override is the regression.
        final src = File(path).readAsStringSync();
        final i = src.indexOf('StyledDropdownFormField<String>(');
        expect(i, greaterThan(-1), reason: '$path has no Position dropdown');
        final end = (i + 1200) < src.length ? i + 1200 : src.length;
        // ⚠️ Comment lines stripped before matching: the note explaining WHY
        // the override was removed names `isDense: false`, and a plain search
        // matched its own documentation.
        final block = src
            .substring(i, end)
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        expect(block, contains("label: 'Position *'"));
        expect(block.contains('isDense: false'), isFalse,
            reason: '$path forces its dropdown out of the shared height');
        expect(block.contains('vertical: 16'), isFalse,
            reason: '$path sets its own dropdown padding again');
      });
    }

    test('the helper line is drawn outside the decorator', () {
      // ⚠️ The ripple must cover the WHOLE field — icon, value, arrow and
      // the padding between — and only the decorator knows that shape. But
      // the decorator also draws the helper line under the box, so an
      // InkWell around it washed grey over text outside the border.
      //
      // Two earlier attempts were wrong: killing the ink lost the click
      // animation, and moving the InkWell into the decorator's child shrank
      // the ripple to the value text alone. Taking the helper line OFF the
      // decoration and rendering it as a sibling leaves the decorator equal
      // to the box, so the ink is too.
      //
      // The geometry itself is asserted by the widget tests below.
      final src =
          File('lib/widgets/styled_dropdown.dart').readAsStringSync();
      expect(src, contains('helperText: null'),
          reason: 'the helper line must not be inside the ink');
      expect(src.contains('splashColor: Colors.transparent'), isFalse,
          reason: 'the click animation must be back');
    });
  });

  group('back steps through STAGES, not out of the screen', () {
    // ⚠️ The OTP and password-expiry steps are `setState` stages of ONE
    // route, not routes of their own — so `canPop()` is false there and the
    // arrow fell straight through to the portal chooser. From a stage, back
    // must mean back to the credentials form.
    const staged = [
      'lib/screens/disposal/disposal_login_screen.dart',
      'lib/screens/appeal/appeal_login_screen.dart',
      'lib/screens/valuation/valuation_login_screen.dart',
      'lib/screens/executive/executive_login_screen.dart',
      'lib/screens/ict/ict_login_screen.dart',
    ];

    for (final path in staged) {
      test('${path.split('/').last} returns to the form first', () {
        final src = File(path).readAsStringSync();
        expect(src, contains('if (_passwordStage || _otpStage)'),
            reason: '$path leaves the screen instead of the stage');
        expect(src, contains("? 'Back to sign in'"),
            reason: '$path must say where the arrow actually goes');
      });
    }

    for (final path in const [
      'lib/screens/login/login_screen.dart',
      'lib/screens/admin/admin_login_screen.dart',
    ]) {
      test('${path.split('/').last} returns to the form first', () {
        final src = File(path).readAsStringSync();
        expect(src, contains('if (_expiredProfile != null)'),
            reason: '$path leaves the screen instead of the stage');
      });
    }

    test('leaving a stage still ends the session', () {
      // Stepping back from the expiry stage must not keep the live session
      // that stage was running inside.
      for (final path in [
        ...staged,
        'lib/screens/login/login_screen.dart',
        'lib/screens/admin/admin_login_screen.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect('abandonSignIn(ref)'.allMatches(src).length,
            greaterThanOrEqualTo(1),
            reason: '$path must sign out on the way back');
      }
    });
  });

  group('the dropdown menu hangs off the field box', () {
    final src = File('lib/widgets/styled_dropdown.dart').readAsStringSync();

    test('it measures the decorator, not the whole widget', () {
      // ⚠️ The render box is the InkWell around an InputDecorator, and the
      // decorator includes the helper line UNDER the box — so the menu
      // opened below that line, detached from the field's border.
      expect(src, contains('_fieldBoxHeight('));
      expect(src, contains('offset.dy + anchorHeight'));
    });

    test('and falls back to the full height when there is no decorator', () {
      // The chip variant has no InputDecorator at all.
      expect(src, contains('return (h != null && h > 0 && h <= fullHeight)'));
    });
  });

  group('the click animation covers the whole field', () {
  testWidgets('the ink covers the whole field box', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Form(
          child: Column(children: [
            StyledDropdownFormField<String>(
              value: null,
              label: 'Position *',
              helperText: 'Only one DC and one SDDC account can exist',
              isDense: false,
              prefixIcon: const Icon(Icons.badge_outlined),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              options: const [
                StyledDropdownOption('a', 'Alpha'),
                StyledDropdownOption('b', 'Beta'),
              ],
              onChanged: (_) {},
            ),
            TextFormField(
              decoration: const InputDecoration(labelText: 'Branch Email *'),
            ),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final whole = tester.getRect(find.byType(StyledDropdownFormField<String>));
    final ink = tester.getRect(find.byType(InkWell).first);
    final decorator = tester.getRect(find.byType(InputDecorator).first);
    final tf = tester.getRect(find.byType(TextFormField));

    // The ripple must span the box exactly — icon, value, arrow and padding.
    expect(ink.width, whole.width,
        reason: 'the ink must be as wide as the field');
    expect(ink.height, decorator.height,
        reason: 'the ink must cover the whole box, not just the value text');

    // And it must stop before the helper line.
    expect(ink.height, lessThan(whole.height),
        reason: 'the helper line must sit outside the ink');

    // Height overall is unchanged: box + helper line.
    expect(whole.height - tf.height, lessThan(30));
  });

  testWidgets('tapping anywhere on the field opens the menu', (tester) async {
    String? picked;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Form(
          child: StyledDropdownFormField<String>(
            value: null,
            label: 'Position *',
            helperText: 'a helper line',
            prefixIcon: const Icon(Icons.badge_outlined),
            options: const [
              StyledDropdownOption('a', 'Alpha'),
              StyledDropdownOption('b', 'Beta'),
            ],
            onChanged: (v) => picked = v,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Tap near the left edge, over the prefix icon.
    final box = tester.getRect(find.byType(InputDecorator).first);
    await tester.tapAt(Offset(box.left + 20, box.center.dy));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);

    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    expect(picked, 'b');
  });

  testWidgets('the helper text is still shown', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Form(
          child: StyledDropdownFormField<String>(
            value: null,
            label: 'Position *',
            helperText: 'Only one DC and one SDDC account can exist',
            options: const [StyledDropdownOption('a', 'Alpha')],
            onChanged: (_) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Only one DC and one SDDC account can exist'),
        findsOneWidget);
  });  });
}
