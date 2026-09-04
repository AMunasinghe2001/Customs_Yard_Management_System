import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The back control for every auth screen (sign in, sign up, OTP, password
/// reset).
///
/// It used to sit inline, immediately left of the page title, which pushed the
/// heading off-centre and forced every subtitle to carry a matching 48px left
/// pad just to line up under it. Here it is lifted out of the text column and
/// pinned to the top-left corner of the page instead, so the title starts at
/// the panel's own margin and the layout reads clean.
///
/// Drop it straight into the `Stack` that each auth screen already uses for its
/// theme toggle -- it positions itself:
///
/// ```dart
/// body: Stack(children: [ ...page..., const AuthBackButton() ]),
/// ```
///
/// The corner it occupies is the dark hero panel on the split-screen layouts,
/// so the chip is deliberately painted for a dark ground (frosted white over a
/// blur) rather than from the theme's text colours, which would vanish there in
/// light mode.
class AuthBackButton extends StatefulWidget {
  /// Where the arrow goes. Defaults to the portal chooser at `/`.
  final VoidCallback? onPressed;

  /// Tooltip / semantic label for the control.
  final String tooltip;

  const AuthBackButton({super.key, this.onPressed, this.tooltip = 'Back'});

  @override
  State<AuthBackButton> createState() => _AuthBackButtonState();
}

class _AuthBackButtonState extends State<AuthBackButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 24,
      left: 24,
      child: Tooltip(
        message: widget.tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: ClipOval(
            child: BackdropFilter(
              // Frosts the hero gradient behind the chip so the arrow keeps its
              // contrast wherever on the artwork the corner happens to land.
              filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(_hovered ? 0.22 : 0.10),
                  border: Border.all(
                    color: Colors.white.withOpacity(_hovered ? 0.55 : 0.28),
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: widget.onPressed ?? () => context.go('/'),
                    child: Icon(
                      Icons.arrow_back_rounded,
                      size: 20,
                      color: Colors.white.withOpacity(_hovered ? 1 : 0.85),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
