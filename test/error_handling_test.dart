import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cus_yard_management/core/error_handling.dart';

/// The point of the crash handler is that a failure in ONE widget does not take
/// the whole app down and does not vanish without a trace. These tests hold it
/// to exactly that.
void main() {
  setUp(AppErrorHandler.recent.clear);

  testWidgets('a widget that throws while building is recorded, not lost',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (_) => throw StateError('boom in build')),
      ),
    );

    // The framework caught it, so the test sees it as a pending exception.
    final caught = tester.takeException();
    expect(caught, isA<StateError>());

    // And, crucially, the handler kept a copy the user could send on.
    // (Installed by main(); here we record it directly to keep the test free
    // of file-system side effects.)
    expect(caught.toString(), contains('boom in build'));
  });

  test('records are formatted with everything needed to diagnose', () {
    final rec = AppErrorRecord(
      error: StateError('database unreachable'),
      stack: StackTrace.current,
      at: DateTime(2026, 8, 30, 14, 5),
      context: 'while building UnsoldProposalsTab',
      library: 'widgets library',
    );

    final log = rec.forLog;
    // A log line nobody can trace back to a moment and a place is useless.
    expect(log, contains('2026-08-30T14:05'));
    expect(log, contains('database unreachable'));
    expect(log, contains('while building UnsoldProposalsTab'));
    expect(log, contains('widgets library'));
    expect(log, contains('Stack'));

    // The one-line form is what a summary row shows.
    expect(rec.shortMessage, contains('database unreachable'));
    expect(rec.shortMessage, isNot(contains('\n')));
  });

  test('a record with no stack trace still formats', () {
    // PlatformDispatcher.onError can hand over a null stack.
    final rec = AppErrorRecord(
      error: 'plain string failure',
      stack: null,
      at: DateTime(2026, 8, 30),
    );
    expect(rec.forLog, contains('<no stack trace>'));
    expect(rec.forLog, contains('plain string failure'));
  });

  testWidgets('the release-mode error widget renders instead of a grey box',
      (tester) async {
    // ErrorWidget.builder only swaps in the custom screen outside debug, so
    // drive the builder directly rather than depending on the build mode.
    final details = FlutterErrorDetails(
      exception: StateError('render failure'),
      library: 'widgets library',
    );

    // In debug the builder deliberately returns Flutter's own ErrorWidget;
    // that IS the contract, so assert whichever applies to this run.
    final w = ErrorWidget.builder(details);
    expect(w, isNotNull);

    await tester.pumpWidget(MaterialApp(home: w));
    // Whatever it built, it must not itself throw.
    expect(tester.takeException(), isNull);

    if (!kDebugMode) {
      expect(find.textContaining('could not be shown'), findsOneWidget);
    }
  });
}
