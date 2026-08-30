import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/widgets/error_view.dart';

/// The error panel has one job beyond looking tidy: tell the truth about WHAT
/// failed. It used to call anything containing "connection" a network problem
/// and print "check your internet connection", which sent people to look at
/// their router while the real cause was a SQL bug — and it truncated the
/// message to whatever followed the last colon, throwing away the SQLSTATE.
void main() {
  Future<void> pump(WidgetTester tester, Object error) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: ErrorView(error: error, onRetry: () {})),
    ));
    await tester.pumpAndSettle();
  }

  group('classification', () {
    testWidgets('a SQL error is NOT reported as a network problem',
        (tester) async {
      await pump(tester,
          'Severity.error 42601: syntax error at or near "\$2"');

      expect(find.textContaining('internet'), findsNothing);
      expect(find.textContaining('database rejected'), findsOneWidget);
    });

    testWidgets('a missing column is a database fault', (tester) async {
      await pump(tester,
          'Severity.error 42703: column t.profiles.role does not exist');
      expect(find.textContaining('database rejected'), findsOneWidget);
      expect(find.textContaining('internet'), findsNothing);
    });

    testWidgets('a type-cast failure is a database fault', (tester) async {
      await pump(tester,
          "type 'DateTime' is not a subtype of type 'String' in type cast");
      expect(find.textContaining('database rejected'), findsOneWidget);
    });

    testWidgets('an unreachable server IS a network problem', (tester) async {
      await pump(tester,
          const SocketException('Connection refused', osError: OSError('', 1225)));
      expect(find.textContaining('did not answer'), findsOneWidget);
    });

    testWidgets('a host lookup failure is a network problem', (tester) async {
      await pump(tester, 'SocketException: Failed host lookup: "db.local"');
      expect(find.textContaining('did not answer'), findsOneWidget);
    });

    testWidgets('a permission error says so, not "something went wrong"',
        (tester) async {
      await pump(tester,
          'Severity.error 42501: permission denied for table packages');
      expect(find.textContaining('Not permitted'), findsOneWidget);
      expect(find.textContaining('internet'), findsNothing);
    });
  });

  group('the message itself', () {
    testWidgets('is shown in full, not truncated at the last colon',
        (tester) async {
      // The old code did error.toString().split(':').last, which would leave
      // only ' syntax error at or near "$2"' — losing the SQLSTATE that says
      // what actually went wrong.
      await pump(tester,
          'Severity.error 42601: syntax error at or near "\$2"');

      expect(find.textContaining('42601'), findsOneWidget,
          reason: 'the SQLSTATE was dropped');
      expect(find.textContaining('syntax error at or near'), findsOneWidget);
    });

    testWidgets('strips the Dart wrapper but keeps the content',
        (tester) async {
      await pump(tester, Exception('relation "email_otps" does not exist'));
      expect(find.textContaining('email_otps'), findsOneWidget);
      // "Exception: " is noise to the reader.
      expect(find.textContaining('Exception:'), findsNothing);
    });

    testWidgets('offers a retry', (tester) async {
      await pump(tester, 'anything');
      expect(find.text('Try Again'), findsOneWidget);
    });
  });
}
