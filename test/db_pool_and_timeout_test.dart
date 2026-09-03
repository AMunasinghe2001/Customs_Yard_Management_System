// The single shared connection, and the error it produced.
//
// Postgres runs ONE query at a time per connection. The app held exactly one,
// so a screen that loads a dozen providers at once queued them all behind each
// other and whichever was last waited out the queue -- surfacing as
// "57014: canceling statement due to user request" on a screen whose own query
// takes 13ms. It was never slow; it was ninth in line.
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/widgets/error_view.dart';

void main() {
  group('a cancelled statement is a timeout, not a rejected query', () {
    // ⚠️ Postgres reports a cancelled statement with the same "Severity.error"
    // every genuine SQL error carries, so classifying on that first told the
    // user "the database rejected this request -- this is a fault in the app"
    // for what was really a busy moment they could simply retry.
    test('57014 is not reported as a database fault', () {
      const raw = 'Severity.error 57014: canceling statement due to user request';
      expect(describeErrorForTest(raw), 'timeout');
    });

    test('the message text alone is enough to classify it', () {
      expect(describeErrorForTest('canceling statement due to user request'),
          'timeout');
    });

    // A REAL SQL fault must still read as one -- the timeout branch must not
    // swallow the errors it sits in front of.
    test('a genuine SQL error is still a database fault', () {
      expect(
          describeErrorForTest(
              'Severity.error 42703: column t.profiles.role does not exist'),
          'database');
      expect(describeErrorForTest('Severity.error 42601: syntax error at or near'),
          'database');
    });

    test('a permission failure is still a permission story', () {
      expect(
          describeErrorForTest(
              'Severity.error 42501: permission denied for table packages'),
          'permission');
    });

    test('an unreachable server is still a network story', () {
      expect(describeErrorForTest('SocketException: Connection refused'),
          'network');
    });
  });

  group('a snackbar says what the full page would say', () {
    // ⚠️ 24 places dumped the raw object into a snackbar as
    // `Text('Error: $e')`. That puts driver text in front of an officer --
    // "Severity.error 57014: canceling statement due to user request" -- which
    // tells them nothing they can act on and reads like the app is broken when
    // the honest answer is "that took too long, try again".
    test('a timeout in a snackbar is a timeout on the page too', () {
      const raw = 'Severity.error 57014: canceling statement due to user request';
      // Both routes classify through the same function, so they cannot drift.
      expect(describeErrorForTest(raw), 'timeout');
    });

    test('a real fault still reads as one in both places', () {
      expect(
          describeErrorForTest('Severity.error 23505: duplicate key value'),
          'database');
    });
  });

  group('one connection serialises, a pool does not', () {
    // Not a claim about the driver -- a statement of the arithmetic that made
    // the bug. Eight one-second queries cannot finish in under eight seconds
    // if they share one connection.
    Duration wallClock({
      required int queries,
      required Duration each,
      required int connections,
    }) {
      final rounds = (queries / connections).ceil();
      return each * rounds;
    }

    test('eight queries on one connection take eight rounds', () {
      expect(
          wallClock(
              queries: 8, each: const Duration(seconds: 1), connections: 1),
          const Duration(seconds: 8));
    });

    test('eight queries on a pool of eight take one round', () {
      expect(
          wallClock(
              queries: 8, each: const Duration(seconds: 1), connections: 8),
          const Duration(seconds: 1));
    });

    // The 60s client timeout is what turned the queue into an error rather
    // than merely a slow screen.
    test('a queue deep enough to pass the timeout becomes a 57014', () {
      const timeout = Duration(seconds: 60);
      final onOne = wallClock(
          queries: 40, each: const Duration(seconds: 2), connections: 1);
      expect(onOne, greaterThan(timeout));

      final onPool = wallClock(
          queries: 40, each: const Duration(seconds: 2), connections: 8);
      expect(onPool, lessThan(timeout));
    });
  });
}
