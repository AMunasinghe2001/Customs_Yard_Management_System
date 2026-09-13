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
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}
