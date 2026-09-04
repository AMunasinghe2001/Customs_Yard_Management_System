import 'package:flutter/material.dart';

import '../core/theme.dart';

/// The close button in a dialog's top-right corner.
///
/// ⚠️ It is RED everywhere, and it exists as one widget so it cannot stop
/// being red in one dialog and not another.
///
/// Every one of these used to be `Colors.white.withOpacity(0.7)`, which works
/// on the yard's and ICT's headers because those are solid and dark. The other
/// directorates give their dialogs a PALE tinted header — the disposal green,
/// the appeal purple — and a 70%-white cross on a pale wash is very close to
/// invisible: the only way out of the dialog was a control you had to already
/// know was there.
///
/// Red is not decoration here. Close is the one destructive-feeling action in
/// a form full of fields, and it is the control someone reaches for in a hurry.
class DialogCloseButton extends StatelessWidget {
  const DialogCloseButton({super.key, this.onPressed, this.prominent = false});

  /// Defaults to popping the route, which is what every caller wanted.
  final VoidCallback? onPressed;

  /// Draws the cross inside a soft red disc with a border.
  ///
  /// ⚠️ For a dialog with a PALE header. On a dark header a bare red cross
  /// reads perfectly well and a disc would be a second box in the corner —
  /// which is why the yard's and ICT's dialogs pass false and keep the shape
  /// they always had, changing only the colour.
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final red = context.colors.dangerRed;
    final icon = Icon(Icons.close_rounded,
        size: prominent ? 20 : 24,
        color: prominent ? red : red.withOpacity(0.85));

    return Tooltip(
      message: 'Close',
      child: IconButton(
        onPressed: onPressed ?? () => Navigator.pop(context),
        splashRadius: prominent ? 20 : 24,
        icon: prominent
            ? Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: red.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: red.withOpacity(0.35)),
                ),
                child: icon,
              )
            : icon,
      ),
    );
  }
}
