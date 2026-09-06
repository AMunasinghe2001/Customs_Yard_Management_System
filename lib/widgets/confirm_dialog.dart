import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../core/theme.dart';
import 'styled_form_dialog.dart';

/// "Are you sure?" — in the same chrome as every other dialog in the app.
///
/// ⚠️ There were six different dialog shapes in this codebase, and two of them
/// sat on ONE screen: the tender page opened `StyledFormDialog` for its forms
/// (gradient header, icon box, uppercase label) and a bare `AlertDialog` for
/// its confirmations (plain title row, no header). Beside each other they read
/// as two different products, and the confirmation — the one that asks the
/// officer to commit to something irreversible — was the plainer of the two.
///
/// This wraps [StyledFormDialog] so a confirmation is drawn as the same kind
/// of moment as the form that led to it.
class ConfirmDialog extends StatelessWidget {
  /// Small uppercase label above the title, e.g. "CONFIRM".
  final String label;

  /// The question, e.g. "Mark as Unsold".
  final String title;
  final IconData icon;

  /// What is about to happen, in a sentence.
  final String message;

  /// The button that commits. Named for the action, never "OK".
  final String confirmLabel;

  /// The colour of the header and the commit button.
  ///
  /// ⚠️ Red is for DESTRUCTION — something that cannot be undone. An outcome
  /// being recorded is not a failure and should not be dressed as one; those
  /// pass amber or the portal's own accent.
  final Color accent;

  const ConfirmDialog({
    super.key,
    required this.label,
    required this.title,
    required this.icon,
    required this.message,
    required this.confirmLabel,
    required this.accent,
  });

  /// Shows the dialog and resolves true only if the officer confirmed.
  ///
  /// Returns false on a dismiss, so a caller can treat the result as a plain
  /// bool without worrying about the null a barrier tap would otherwise give.
  static Future<bool> show(
    BuildContext context, {
    required String label,
    required String title,
    required IconData icon,
    required String message,
    required String confirmLabel,
    required Color accent,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmDialog(
        label: label,
        title: title,
        icon: icon,
        message: message,
        confirmLabel: confirmLabel,
        accent: accent,
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    return StyledFormDialog(
      label: label,
      title: title,
      icon: icon,
      headerAccentColor: accent,
      // Narrower than a form: this holds one sentence, and a 460px box around
      // it reads as though something is missing.
      width: 420,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel',
              style: TextStyle(color: context.colors.textMuted)),
        ),
        const Gap(8),
        StyledDialogPrimaryButton(
          labelText: confirmLabel,
          accentColor: accent,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
      child: Text(
        message,
        style: TextStyle(
            color: context.colors.textSecondary, fontSize: 13, height: 1.45),
      ),
    );
  }
}
