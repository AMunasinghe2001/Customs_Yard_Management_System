import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../core/session_reset.dart';
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
/// Two modes, one form. With [expired] false it is the WARNING shown in the
/// last days before the 90-day limit: the same fields, plus "Skip for now".
/// With [expired] true the limit has passed, Skip is gone, and the only ways
/// out are a new password or signing out.
///
/// ⚠️ The warning half is not cosmetic. Without it the first an officer hears
/// of the rotation is the morning they cannot work — the yard portals had
/// only the hard stop, so yard staff got no notice at all while the four
/// directorate portals warned for a week.
///
/// Returns nothing: [onDone] fires once the password has been changed,
/// [onSkip] when the officer defers it (warning mode only), and [onSignOut]
/// when they back out.
class PasswordExpiredStage extends ConsumerStatefulWidget {
  const PasswordExpiredStage({
    super.key,
    required this.accent,
    required this.onDone,
    required this.onSignOut,
    required this.signInRoute,
    this.expired = true,
    this.daysLeft = 0,
    this.onSkip,
  });

  /// The portal's colour, so the step belongs to the door it appears on.
  final Color accent;

  /// Called after the new password has been accepted.
  final VoidCallback onDone;

  /// Called when the officer chooses to sign out instead.
  final VoidCallback onSignOut;

  /// The portal's own sign-in route. ⚠️ Signing out rebuilds the
  /// ProviderScope, which builds a NEW router starting at its
  /// initialLocation — the portal picker. Without this the officer sets a new
  /// password and lands on the home page. See core/session_reset.dart.
  final String signInRoute;

  /// Whether the 90 days have already passed. False = the warning phase.
  final bool expired;

  /// Days remaining, shown in the warning. Ignored when [expired].
  final int daysLeft;

  /// Called when the officer defers the change. ⚠️ Required in warning mode
  /// and never offered when [expired] — see the note on the button.
  final VoidCallback? onSkip;

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
      // ⚠️ End the session and send them back to the sign-in form rather
      // than straight into the app. Two reasons, and the first is a real
      // bug: the profile in currentProfileProvider was read BEFORE the
      // change, so its passwordUpdatedAt is still the old one and
      // isPasswordExpired stays true. Carrying it into the app meant the
      // router's expiry guard bounced the officer to '/' -- they changed
      // their password and landed on the home page.
      //
      // Re-reading the profile here would fix that one symptom, but signing
      // in again is what the officer expects of a password change anyway,
      // and it proves the new password actually works while they are still
      // in front of the form that can correct it.
      // ⚠️ Set BEFORE signing out: signOut() schedules the ProviderScope
      // rebuild, and the new router reads this as its starting route.
      pendingLandingRoute = widget.signInRoute;
      try {
        await ref.read(authServiceProvider).signOut();
      } catch (_) {
        // The profile is cleared either way; the stale session cannot
        // authorise anything once the provider is null.
      }
      if (!mounted) return;
      ref.read(currentProfileProvider.notifier).state = null;
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
        Builder(builder: (context) {
          final tone = widget.expired ? colors.dangerRed : colors.warningAmber;
          final d = widget.daysLeft;
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: tone.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: tone.withOpacity(0.4)),
            ),
            child: Row(children: [
              Icon(
                  widget.expired
                      ? Icons.lock_clock_rounded
                      : Icons.warning_amber_rounded,
                  color: tone,
                  size: 18),
              const Gap(10),
              Expanded(
                child: Text(
                  widget.expired
                      ? 'Your password has passed its 90-day limit. Until it '
                          'is changed, this account cannot read any records.'
                      : 'Your password expires in $d '
                          '${d == 1 ? 'day' : 'days'}. Set a new one now, or '
                          'skip and change it later.',
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
              ),
            ]),
          );
        }).animate().fadeIn(duration: 300.ms),
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
                    style: TextStyle(color: colors.dangerRed, fontSize: 13)),
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
              icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility,
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
        PasswordMatchBar(password: _newCtrl.text, confirm: _confirmCtrl.text),
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
        // ⚠️ "Skip for now" appears ONLY in the warning phase. Once expired,
        // carrying on is not an option to withhold politely — migration 018
        // has already shut the session out of every record but this form, so
        // a Skip button would lead to an empty app and look like a fault.
        Center(
          child: TextButton(
            onPressed:
                _busy ? null : (widget.expired ? _signOut : widget.onSkip),
            child: Text(widget.expired ? 'Sign out' : 'Skip for now',
                style: TextStyle(
                    color: colors.textMuted, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}
