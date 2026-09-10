import 'dart:ui';

import 'package:flutter/material.dart';

/// `showDialog` with the app's own backdrop: the page behind is dimmed AND
/// blurred, and the dialog scales in.
///
/// ⚠️ Flutter's `showDialog` cannot do this. It dims the barrier but has no
/// hook for a transition, so a blur needs `showGeneralDialog`. The one-tap
/// calendar had already been written that way, which is exactly why it stood
/// out: every other popup in the app — every yard page, every directorate —
/// arrived over a flat grey sheet while that one blurred. Rather than leave
/// one popup styled differently, this gives all of them the same entrance.
///
/// The signature mirrors `showDialog` on purpose, so a call site changes by
/// its name alone and nothing else has to be re-read.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    // showGeneralDialog asserts a label exists whenever the barrier can be
    // tapped away, and "Dismiss" is what a screen reader should announce.
    barrierLabel:
        barrierLabel ?? (barrierDismissible ? 'Dismiss' : null) ?? 'Dialog',
    barrierColor: barrierColor ?? Colors.black.withOpacity(0.65),
    transitionDuration: const Duration(milliseconds: 180),
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    pageBuilder: (ctx, _, __) => builder(ctx),
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      final t = Curves.easeOut.transform(animation.value);
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 2.5 * t, sigmaY: 2.5 * t),
        child: Opacity(
          opacity: t,
          // A small scale-up, not a slide: a dialog that travels reads as a
          // page change, and these are all interruptions of one.
          child: Transform.scale(scale: 0.98 + 0.02 * t, child: child),
        ),
      );
    },
  );
}
