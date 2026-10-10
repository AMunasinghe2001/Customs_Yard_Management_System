import 'dart:ui' show ImageFilter;

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
    barrierLabel:
        barrierLabel ?? (barrierDismissible ? 'Dismiss' : null) ?? 'Dialog',
    barrierColor: barrierColor ?? Colors.black.withOpacity(0.65),
    transitionDuration: const Duration(milliseconds: 160),
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    pageBuilder: (ctx, _, __) => builder(ctx),
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      // ⚠️ The blur belongs HERE, not in the dialog's own widget. This file
      // promised "dimmed AND blurred" from the day it was written, but only
      // ever faded and scaled -- so the one-tap calendar, which blurs in its
      // own `showGeneralDialog`, was the only popup in the app with a frosted
      // page behind it. Every other popup arrived over a flat dim.
      //
      // ⚠️ Animated with `t`, not a constant sigma. A BackdropFilter at full
      // strength on frame one snaps the whole page out of focus before the
      // dialog is visible; ramping it with the same curve lets the background
      // settle back as the popup grows.
      final t = curved.value;
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 2.5 * t, sigmaY: 2.5 * t),
        child: FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}
