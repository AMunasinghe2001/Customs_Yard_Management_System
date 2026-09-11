import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../core/providers.dart';
import '../core/security_policy.dart';
import '../core/theme.dart';
import 'password_strength_field.dart';

/// The "set a new password" step, drawn INSIDE the sign-in panel.
///
/// ⚠️ A stage, not a dialog. The four directorate portals already showed this
/// as part of their sign-in form; the yard, admin and ICT portals put it in a
/// modal instead, so the same moment in the same flow looked like two
/// different products depending on which door the officer came through. A
/// modal also reads as an interruption to something else, when in fact it IS
/// the sign-in — there is nothing behind it to go back to.
///
/// Returns nothing: [onDone] fires once the password has been changed, and
/// [onSignOut] when the officer backs out.
class PasswordExpiredStage extends ConsumerStatefulWidget {
  const PasswordExpiredStage({
    super.key,
    required this.accent,
    required this.onDone,
    required this.onSignOut,
  });

  /// The portal's colour, so the step belongs to the door it appears on.
  final Color accent;

  /// Called after the new password has been accepted.
  final VoidCallback onDone;

  /// Called when the officer chooses to sign out instead.
  final VoidCallback onSignOut;

  @override
  ConsumerState<PasswordExpiredStage> createState() =>
      _PasswordExpiredStageState();
}

class _PasswordExpiredStageState extends ConsumerState<PasswordExpiredStage> {
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
      // Works even though the session is otherwise locked: change_password is
      // SECURITY DEFINER and identifies the caller from the session variable,
      // not from auth.uid(). It also drops the connection pool, so the next
      // query re-asks the database and comes back unlocked.
      await ref.read(authServiceProvider).changePassword(next);
      if (!mounted) return;
      widget.onDone();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _signOut() async {
    // An expired session can read nothing, so staying signed in would only
    // strand the officer on an empty dashboard.
    try {
      await ref.read(authServiceProvider).signOut();
    } catch (_) {
      // Either way they go back to the sign-in form.
    }
    if (!mounted) return;
    ref.read(currentProfileProvider.notifier).state = null;
    widget.onSignOut();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.warningAmber.withOpacity(0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.warningAmber.withOpacity(0.4)),
          ),
          child: Row(children: [
            Icon(Icons.lock_clock_rounded,
                color: colors.warningAmber, size: 18),
            const Gap(10),
            Expanded(
              child: Text(
                'Your password has passed its 90-day limit. Until it is '
                'changed, this account cannot read any records.',
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
            ),
          ]),
        ).animate().fadeIn(duration: 300.ms),
        const Gap(20),
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.dangerRed.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.dangerRed.withOpacity(0.4)),
            ),
            child: Row(children: [
              Icon(Icons.error_outline, color: colors.dangerRed, size: 18),
              const Gap(10),
              Expanded(
                child: Text(_error!,
                    style:
                        TextStyle(color: colors.dangerRed, fontSize: 13)),
              ),
            ]),
          ),
          const Gap(20),
        ],
        PasswordRequirements(password: _newCtrl.text),
        const Gap(12),
        TextFormField(
          controller: _newCtrl,
          obscureText: _obscureNew,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          onFieldSubmitted: (_) => _busy ? null : _submit(),
          decoration: InputDecoration(
            labelText: 'New Password',
            prefixIcon: Icon(Icons.lock_outline, color: colors.textMuted),
            suffixIcon: IconButton(
              icon: Icon(
                  _obscureNew ? Icons.visibility_off : Icons.visibility,
                  color: colors.textMuted),
              onPressed: () => setState(() => _obscureNew = !_obscureNew),
            ),
          ),
        ),
        PasswordStrengthBar(password: _newCtrl.text),
        const Gap(16),
        TextFormField(
          controller: _confirmCtrl,
          obscureText: _obscureConfirm,
          onChanged: (_) => setState(() {}),
          onFieldSubmitted: (_) => _busy ? null : _submit(),
          decoration: InputDecoration(
            labelText: 'Confirm New Password',
            prefixIcon: Icon(Icons.lock_outline, color: colors.textMuted),
            suffixIcon: IconButton(
              icon: Icon(
                  _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                  color: colors.textMuted),
              onPressed: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
        ),
        PasswordMatchBar(
            password: _newCtrl.text, confirm: _confirmCtrl.text),
        const Gap(24),
        SizedBox(
          height: 54,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: widget.accent, foregroundColor: Colors.white),
            icon: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_circle_rounded),
            label: Text(_busy ? 'Updating...' : 'Update Password & Sign In',
                style: const TextStyle(fontSize: 16)),
            onPressed: _busy ? null : _submit,
          ),
        ),
        const Gap(10),
        // ⚠️ No "skip". An expired password is the one case where carrying on
        // is not an option — the database has already shut the session out of
        // everything but this form.
        Center(
          child: TextButton(
            onPressed: _busy ? null : _signOut,
            child: Text('Sign out',
                style: TextStyle(
                    color: colors.textMuted, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}
