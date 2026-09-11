import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../core/providers.dart';
import '../core/security_policy.dart';
import '../core/supabase_client.dart';
import '../core/theme.dart';
import 'app_dialog.dart';

/// Forces a password change before the app can be used.
///
/// ⚠️ This is the ONLY way out of an expired password, and it has to exist on
/// every portal that can sign in. Migration 018 makes the database treat an
/// expired session as signed-out — `auth.uid()` is null and `auth.role()` is
/// 'anon', so every RLS policy denies it — while leaving
/// `auth.change_password` working, because that function takes the user id as
/// an argument instead of asking who is calling.
///
/// A portal without this dialog would therefore let its officers sign in to a
/// completely empty app with no way to fix it. The four directorate portals
/// already had a password stage of their own; the yard and admin screens did
/// not, and three real yard officers are already past 90 days.
///
/// Not dismissible, and it offers no "later": "later" is what the 90 days
/// already were.
class MandatoryPasswordChangeDialog extends ConsumerStatefulWidget {
  const MandatoryPasswordChangeDialog({super.key, required this.accent});

  /// The portal's colour, so the dialog belongs to the door it appears on.
  final Color accent;

  /// Shows the dialog and resolves true once the password has been changed.
  ///
  /// Returns false if the officer backed out, which signs them out — an
  /// expired session can do nothing anyway, and leaving it signed in would
  /// strand them on an empty dashboard.
  static Future<bool> show(BuildContext context, {required Color accent}) async {
    final changed = await showAppDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MandatoryPasswordChangeDialog(accent: accent),
    );
    return changed ?? false;
  }

  @override
  ConsumerState<MandatoryPasswordChangeDialog> createState() =>
      _MandatoryPasswordChangeDialogState();
}

class _MandatoryPasswordChangeDialogState
    extends ConsumerState<MandatoryPasswordChangeDialog> {
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final next = _newCtrl.text;
    // The database enforces this too (password_policy_violation); checking
    // here just saves a round trip.
    final violation = PasswordPolicy.violation(next);
    if (violation != null) {
      setState(() => _error = violation);
      return;
    }
    if (next != _confirmCtrl.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Works even though the session is otherwise locked: change_password
      // is SECURITY DEFINER and identifies the caller from the session
      // variable, not from auth.uid(). It also drops the connection pool, so
      // the next query re-asks the database and comes back unlocked.
      await ref.read(authServiceProvider).changePassword(next);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _cancel() async {
    // An expired session can read nothing, so staying signed in would only
    // strand them on an empty dashboard.
    try {
      await ref.read(authServiceProvider).signOut();
    } catch (_) {
      // Either way the officer goes back to the sign-in page.
    }
    if (!mounted) return;
    ref.read(currentProfileProvider.notifier).state = null;
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PopScope(
      // No escape hatch: the session cannot do anything until this is done.
      canPop: false,
      child: Dialog(
        backgroundColor: colors.cardDark,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: widget.accent.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.lock_reset_rounded,
                        color: widget.accent, size: 22),
                  ),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Password Expired',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: colors.textPrimary)),
                        Text('Set a new one to continue',
                            style: TextStyle(
                                fontSize: 12.5, color: colors.textSecondary)),
                      ],
                    ),
                  ),
                ]),
                const Gap(18),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.warningAmber.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: colors.warningAmber.withOpacity(0.35)),
                  ),
                  child: Row(children: [
                    Icon(Icons.info_outline_rounded,
                        size: 18, color: colors.warningAmber),
                    const Gap(8),
                    Expanded(
                      child: Text(
                        'Your password is more than 90 days old. Until it is '
                        'changed, this account cannot read any records.',
                        style: TextStyle(
                            fontSize: 12.5, color: colors.textSecondary),
                      ),
                    ),
                  ]),
                ),
                const Gap(16),
                TextField(
                  controller: _newCtrl,
                  obscureText: _obscureNew,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    helperText: 'Minimum 8 characters',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureNew
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded),
                      onPressed: () =>
                          setState(() => _obscureNew = !_obscureNew),
                    ),
                  ),
                ),
                const Gap(12),
                TextField(
                  controller: _confirmCtrl,
                  obscureText: _obscureConfirm,
                  onSubmitted: (_) => _busy ? null : _submit(),
                  decoration: InputDecoration(
                    labelText: 'Confirm New Password',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirm
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const Gap(12),
                  Text(_error!,
                      style: TextStyle(
                          color: colors.dangerRed,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                ],
                const Gap(20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _busy ? null : _cancel,
                      child: Text('Sign out',
                          style: TextStyle(color: colors.textMuted)),
                    ),
                    const Gap(8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: widget.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 14)),
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_circle_rounded, size: 18),
                      label: Text(_busy ? 'Updating...' : 'Update & Continue'),
                      onPressed: _busy ? null : _submit,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
