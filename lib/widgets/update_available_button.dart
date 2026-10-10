import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/update_check.dart';
import 'update_banner.dart';

/// An "Update" button that exists only while there is an update.
///
/// ⚠️ IT SHOWS NOTHING WHEN THERE IS NOTHING TO DO. The previous control was
/// a permanent "Check for Updates" button sitting beside Sign Out, which is
/// a question no officer ever wants to ask: almost every press answered
/// "nothing new", so the button was noise on every screen for the sake of
/// the rare day it had news.
///
/// The app already knows the answer. `fetchAvailableUpdate()` runs at
/// start-up and publishes to [availableUpdate], and the gold strip reads the
/// same value — so this is the strip's information offered a second way, for
/// an officer who dismissed it or is deep in a page where the strip is out
/// of sight.
///
/// ⚠️ Pressing it UPDATES, it does not check. [startUpdate] hands the work
/// to WinSparkle, which downloads the installer, shows its own progress and
/// launches it. Nothing lands in Downloads for the officer to find.
///
/// Renders as a zero-size box when idle, so a caller can place it in a
/// column without guarding it — and the gap that would sit beside it is the
/// caller's to manage, which is why [trailing] exists.
class UpdateAvailableButton extends StatelessWidget {
  const UpdateAvailableButton({
    super.key,
    required this.builder,
    this.trailing,
  });

  /// Draws the button in whatever shape the surrounding header wants: the
  /// yard shell's white-on-navy panel and the ICT console's outlined toolbar
  /// button look nothing alike, and neither should be bent to match the
  /// other for the sake of sharing this.
  final Widget Function(BuildContext context, AvailableUpdate update,
      VoidCallback onPressed) builder;

  /// Placed after the button, and omitted with it. Usually the gap that
  /// separates it from the next control.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AvailableUpdate?>(
      valueListenable: availableUpdate,
      builder: (context, update, _) {
        if (update == null) return const SizedBox.shrink();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            builder(context, update, () => startUpdate(context, update)),
            if (trailing != null) trailing!,
          ],
        );
      },
    );
  }
}

/// The label every portal shows, so the version is never left off.
///
/// ⚠️ It names the VERSION. "Update" alone tells an officer nothing about
/// what they are about to install, and the same words would appear whether
/// the release was a typo fix or a month of work.
String updateButtonLabel(AvailableUpdate update) =>
    'Update to ${update.version}';

/// The colour a portal should use for it.
///
/// Gold, matching the strip: nothing is wrong, there is simply something
/// newer. A danger colour would read as a fault.
Color updateButtonAccent(BuildContext context) => context.colors.primaryGold;
