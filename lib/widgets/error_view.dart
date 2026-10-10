import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:gap/gap.dart';
import '../core/theme.dart';

/// How an error should be presented: what it most likely is, and what the
/// person looking at it can do about it.
enum _Kind {
  /// The server could not be reached at all.
  network,

  /// The database answered, but rejected the query — a bug in the app, not
  /// anything the user can fix by checking their Wi-Fi.
  database,

  /// Permission / row-level security.
  permission,

  /// The query was still running when its time ran out and was cancelled.
  ///
  /// ⚠️ NOT a [database] fault. Postgres reports a cancelled statement as
  /// `57014: canceling statement due to user request`, carrying the same
  /// "Severity.error" every genuine SQL error does -- so it was classified as
  /// "the database rejected this request", which blamed a bug in the app for
  /// what is really a slow or busy moment the user can simply retry.
  timeout,

  /// Anything else.
  unknown,
}

/// Shows [error] in a snackbar, worded the way [ErrorView] would word it.
///
/// ⚠️ Use this instead of `Text('Error: $e')`. Dumping the raw object puts
/// driver text in front of an officer -- "Severity.error 57014: canceling
/// statement due to user request" tells them nothing they can act on, and
/// reads like the app is broken when the honest answer is "that took too long,
/// try again". The full-page [ErrorView] already knows how to say each kind of
/// failure; a snackbar for the same cause should say the same thing.
///
/// [action] names what the user was doing ("Save the valuation"), so the
/// message can lead with it rather than with the failure.
void showErrorSnack(BuildContext context, Object error, {String? action}) {
  final kind = ErrorView.classifyForTest(error);
  final (icon, tint, title, _) = ErrorView.wordingForTest(kind, context);
  // `unknown` is where a plain `Exception('...')` the app itself threw lands
  // -- that message was written for the user to read, not driver noise, so
  // show it instead of the generic "Something went wrong" that told them
  // nothing. Every other kind keeps the short, worded title: those details
  // ARE driver text, which is exactly what this snackbar exists to hide.
  final lead = kind == ErrorView.unknownForTest
      ? ErrorView.detailForTest(error)
      : (action == null ? title : '$action failed — ${title.toLowerCase()}');
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      backgroundColor: tint,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
      content: Row(children: [
        Icon(icon, color: Colors.white, size: 18),
        const Gap(10),
        Expanded(
            child: Text(lead,
                style: const TextStyle(fontWeight: FontWeight.w600))),
      ]),
    ));
}

/// A one-line failure notice for a small panel.
///
/// ⚠️ The full [ErrorView] is a 64px icon in 40px of padding -- right for a
/// page that failed, far too big for a dashboard card. Those cards fell back
/// to `Text('Error: $e')`, which puts driver text on the dashboard. This says
/// the same thing [ErrorView] would, in one line.
class InlineError extends StatelessWidget {
  final Object error;
  const InlineError(this.error, {super.key});

  @override
  Widget build(BuildContext context) {
    final kind = ErrorView.classifyForTest(error);
    final (icon, tint, title, _) = ErrorView.wordingForTest(kind, context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: tint),
        const Gap(8),
        Flexible(
          child: Text(title,
              style: TextStyle(color: tint, fontSize: 12.5,
                  fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}

/// The kind name [ErrorView] would use for [error], for tests.
///
/// Classification decides what the user is TOLD to do -- check the network,
/// call ICT, or just retry -- so it is worth testing on its own, without
/// pumping a widget to read a string off the screen.
String describeErrorForTest(Object error) =>
    ErrorView.classifyForTest(error).name;

/// The standard "this panel failed to load" view.
///
/// ⚠️ It matters that this tells the truth about WHICH kind of failure
/// happened. The first version called anything containing the word
/// "connection" a network problem and showed "check your internet connection"
/// — so a plain SQL error (`column t.profiles.role does not exist`, a syntax
/// error in a generated query) sent people to look at their router while the
/// real cause was a bug in the query builder. It also rendered the message as
/// `error.toString().split(':').last`, which throws away everything before the
/// last colon and turns `PgException 42601: syntax error at or near "$2"` into
/// a bare fragment.
class ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;

  const ErrorView({super.key, required this.error, this.onRetry});

  /// Classifies by the SPECIFIC signals each kind carries, most specific
  /// first — a Postgres error mentioning "connection" must not be read as a
  /// network failure.
  /// Test seam for [describeErrorForTest]; the classifier itself stays private.
  @visibleForTesting
  static _Kind classifyForTest(Object error) => _classify(error);

  /// The `unknown` kind, exposed so callers outside this file (namely
  /// [showErrorSnack]) can compare against it without reaching into the
  /// private enum.
  static const unknownForTest = _Kind.unknown;

  /// Test/call seam for [_detail].
  static String detailForTest(Object error) => _detail(error);

  /// The wording for a kind, so [showErrorSnack] says what the page says.
  static (IconData, Color, String, String) wordingForTest(
          _Kind kind, BuildContext context) =>
      _wordingFor(kind, context);

  static _Kind _classify(Object error) {
    final s = error.toString().toLowerCase();

    // Postgres SQLSTATEs and driver errors. Checked BEFORE the network branch
    // because their text often contains the word "connection".
    if (error is SocketException &&
        (s.contains('refused') || s.contains('unreachable'))) {
      return _Kind.network;
    }
    // ⚠️ Before the database branch: a cancelled statement carries
    // "Severity.error" like any other Postgres error, so checking that first
    // would report a timeout as a fault in the app.
    if (s.contains('57014') ||
        s.contains('canceling statement') ||
        s.contains('cancelling statement') ||
        s.contains('query timed out') ||
        error is TimeoutException) {
      return _Kind.timeout;
    }

    if (s.contains('severity.error') ||
        s.contains('pgexception') ||
        s.contains('postgresexception') ||
        RegExp(r'\b(42\d{3}|22\d{3}|23\d{3}|08\d{3})\b').hasMatch(s) ||
        s.contains('syntax error at or near') ||
        s.contains('does not exist') ||
        s.contains('is not a subtype')) {
      // 42501 is insufficient_privilege — that is a permission story.
      if (s.contains('42501') ||
          s.contains('permission denied') ||
          s.contains('row-level security')) {
        return _Kind.permission;
      }
      return _Kind.database;
    }

    if (error is SocketException ||
        s.contains('socketexception') ||
        s.contains('failed host lookup') ||
        s.contains('timed out') ||
        s.contains('timeout') ||
        s.contains('clientexception') ||
        s.contains('connection refused') ||
        s.contains('connection closed') ||
        s.contains('network is unreachable')) {
      return _Kind.network;
    }

    return _Kind.unknown;
  }

  /// The raw message, cleaned of Dart/driver wrappers but NOT truncated —
  /// whoever reads this needs enough to act on or report.
  static String _detail(Object error) {
    var s = error.toString().trim();
    for (final prefix in const [
      'Exception: ',
      'PgQueryException: ',
      'PostgreSQLException: ',
      'AuthApiException(',
      'AuthException: ',
    ]) {
      if (s.startsWith(prefix)) s = s.substring(prefix.length);
    }
    if (s.endsWith(')')) s = s.substring(0, s.length - 1);
    // The driver prefixes its own severity; the SQLSTATE after it is the
    // useful part, so keep that and drop the noise.
    s = s.replaceFirst(RegExp(r'^Severity\.\w+\s*'), '');
    return s.trim();
  }

  @override
  Widget build(BuildContext context) {
    final kind = _classify(error);
    final detail = _detail(error);

    final (icon, tint, title, advice) = _wordingFor(kind, context);
    return _buildView(context, icon, tint, title, advice, detail);
  }

  /// What each kind of failure is CALLED and what to do about it.
  ///
  /// Shared with [showErrorSnack] so a failure worded one way on a full page
  /// is not worded differently in a snackbar for the same cause.
  static (IconData, Color, String, String) _wordingFor(
      _Kind kind, BuildContext context) {
    return switch (kind) {
      _Kind.network => (
          Iconsax.wifi_square,
          context.colors.warningAmber,
          'Cannot reach the server',
          'The database did not answer. Check that the office server is '
              'running and that this PC is on the network, then try again.',
        ),
      _Kind.database => (
          Iconsax.danger,
          context.colors.dangerRed,
          'The database rejected this request',
          'This is a fault in the app, not in your connection or your data. '
              'Send the details below to the ICT Directorate.',
        ),
      _Kind.permission => (
          Iconsax.lock,
          context.colors.warningAmber,
          'Not permitted',
          'This account is not allowed to see these records. Check you are '
              'signed in to the right portal and yard.',
        ),
      _Kind.timeout => (
          Iconsax.timer_1,
          context.colors.warningAmber,
          'This took too long to load',
          'The server was still working when the request ran out of time. '
              'Nothing has been lost and nothing is broken — this usually '
              'means several screens were loading at once. Try again.',
        ),
      _Kind.unknown => (
          Iconsax.danger,
          context.colors.dangerRed,
          'Something went wrong',
          'The details below say what failed.',
        ),
    };
  }

  Widget _buildView(BuildContext context, IconData icon, Color tint,
      String title, String advice, String detail) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: tint.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 64, color: tint),
            ),
            const Gap(24),
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const Gap(12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Text(
                advice,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 14,
                    height: 1.5),
              ),
            ),
            if (detail.isNotEmpty) ...[
              const Gap(18),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: context.colors.cardDark,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.colors.borderColor),
                  ),
                  // Selectable: the whole point is that it can be copied into
                  // a message to ICT.
                  child: SelectableText(
                    detail,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      height: 1.5,
                      color: context.colors.textMuted,
                    ),
                  ),
                ),
              ),
            ],
            if (onRetry != null) ...[
              const Gap(26),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Iconsax.refresh, size: 18),
                label: const Text('Try Again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
