import 'package:flutter/material.dart';

import '../core/db/connection_health.dart';
import '../core/theme.dart';

/// A strip across the top of the app while the database cannot be reached.
///
/// ⚠️ Over the internet a dropped link looks exactly like an empty table: the
/// query fails, the page renders nothing, and an officer at a branch office
/// concludes the yard has no packages. Saying so plainly is the difference
/// between "the app is broken" and "my connection dropped".
///
/// Deliberately NOT a dialog. The officer cannot fix anything from here, and a
/// modal over a screen they were reading would take away the one thing still
/// working — the data already on screen. It also never blocks input: a page
/// they can still scroll is worth more than a page they cannot touch.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      child,
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: ValueListenableBuilder<bool>(
          valueListenable: ConnectionHealth.offline,
          builder: (context, offline, _) {
            return AnimatedSlide(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              offset: offline ? Offset.zero : const Offset(0, -1),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                opacity: offline ? 1 : 0,
                child: offline
                    ? const _Bar()
                    : const SizedBox(width: double.infinity),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

class _Bar extends StatelessWidget {
  const _Bar();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        bottom: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: colors.dangerRed,
          child: Row(children: [
            const Icon(Icons.cloud_off_rounded, size: 18, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: ValueListenableBuilder<String?>(
                valueListenable: ConnectionHealth.lastReason,
                builder: (context, reason, _) => Text(
                  reason ?? 'The connection to the office server was lost.',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // No "Retry" button: the next thing the officer does issues a
            // query anyway, and that is what clears the banner. A button that
            // only repeats what the app already does on its own would invite
            // them to press it instead of checking their connection.
            const Text('Reconnecting automatically…',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500)),
          ]),
        ),
      ),
    );
  }
}
