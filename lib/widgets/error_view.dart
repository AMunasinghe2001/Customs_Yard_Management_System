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

  /// Anything else.
  unknown,
}

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
  static _Kind _classify(Object error) {
    final s = error.toString().toLowerCase();

    // Postgres SQLSTATEs and driver errors. Checked BEFORE the network branch
    // because their text often contains the word "connection".
    if (error is SocketException &&
        (s.contains('refused') || s.contains('unreachable'))) {
      return _Kind.network;
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

    final (icon, tint, title, advice) = switch (kind) {
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
      _Kind.unknown => (
          Iconsax.danger,
          context.colors.dangerRed,
          'Something went wrong',
          'The details below say what failed.',
        ),
    };

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
