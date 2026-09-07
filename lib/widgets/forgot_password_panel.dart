import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../core/providers.dart';
import '../core/theme.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/security_policy.dart';

/// "I forgot my password", in three steps: name the account, prove you can
/// read its mailbox, then set a new password.
///
/// Shared by the Officer and DC/SDDC portals so both behave identically — the
/// accent is the only thing either passes in.
///
/// ⚠️ Step one never reports whether the identifier matched. Saying "no such
/// account" would let anyone test which usernames and addresses are real, so
/// it moves to the code step either way; a code simply never arrives for an
/// account that does not exist. See `reset_email_for_identifier`.
class ForgotPasswordPanel extends ConsumerStatefulWidget {
  final Color accent;

  /// Pre-fills the identifier with whatever was already typed on the login
  /// form, so the officer does not type it twice.
  final String initialIdentifier;

  /// Called when the panel is finished with: `true` once the password has
  /// been changed, `false` when the officer goes back to sign in.
  ///
  /// ⚠️ The panel does NOT pop a route -- it is part of the page, not a
  /// dialog over it. The login screen decides what to show next.
  final void Function(bool changed) onClose;

  const ForgotPasswordPanel({
    super.key,
    required this.accent,
    required this.onClose,
    this.initialIdentifier = '',
  });

  @override
  ConsumerState<ForgotPasswordPanel> createState() =>
      _ForgotPasswordPanelState();
}

enum _Step { identify, verify, reset }

class _ForgotPasswordPanelState extends ConsumerState<ForgotPasswordPanel> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _idCtrl =
      TextEditingController(text: widget.initialIdentifier);
  final _otpCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  _Step _step = _Step.identify;
  bool _busy = false;
  bool _resending = false;
  String? _error;
  String? _info;

  /// The address the code went to. Empty when the identifier matched nothing —
  /// which the officer is deliberately not told, so the flow continues and
  /// simply fails at the code step.
  String _email = '';

  bool _obscurePass = true;
  bool _obscureConfirm = true;

  /// The code is short-lived, and the countdown says so rather than leaving
  /// the officer to discover it by failing.
  static const int _codeLifetimeSeconds = 120;
  int _secondsLeft = 0;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    _idCtrl.dispose();
    _otpCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _ticker?.cancel();
    setState(() => _secondsLeft = _codeLifetimeSeconds);
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _secondsLeft = _secondsLeft > 0 ? _secondsLeft - 1 : 0);
      if (_secondsLeft == 0) t.cancel();
    });
  }

  String _friendly(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('no verification code')) {
      return 'That code has already been used. Tap "Resend code" for a new one.';
    }
    if (s.contains('expired')) {
      return 'That code has expired. Tap "Resend code" for a new one.';
    }
    if (s.contains('too many attempts')) {
      return 'Too many incorrect attempts. Tap "Resend code" for a new one.';
    }
    if (s.contains('incorrect') || s.contains('invalid')) {
      return 'That code is not correct. Check the email and try again.';
    }
    if (s.contains('reset_not_available')) {
      return 'This account can no longer be reset. Contact the ICT Directorate.';
    }
    // The server returns the policy's own wording (password_policy_violation),
    // so pass it through rather than restating a rule that can drift.
    if (s.contains('password must') || s.contains('password contains')) {
      return e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    }
    return 'Something went wrong. Please try again.';
  }

  // ── Step 1: name the account ───────────────────────────────────────────
  Future<void> _sendCode({bool isResend = false}) async {
    if (!isResend && !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      if (isResend) {
        _resending = true;
      } else {
        _busy = true;
      }
      _error = null;
      _info = null;
    });
    try {
      final email = await ref
          .read(authServiceProvider)
          .startPasswordReset(_idCtrl.text.trim());
      if (!mounted) return;
      setState(() {
        _email = email ?? '';
        _step = _Step.verify;
        // Deliberately the same words whether or not the account exists.
        _info = 'If that account exists, a code has been sent to its '
            'registered email.';
      });
      _startCountdown();
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _resending = false;
        });
      }
    }
  }

  // ── Step 2: prove you can read the mailbox ─────────────────────────────
  void _checkCode() {
    final code = _otpCtrl.text.trim();
    if (code.length < 4) {
      setState(() => _error = 'Enter the 6-digit code from the email.');
      return;
    }
    // The code is verified for real when the password is saved, against the
    // address the ACCOUNT is registered to. Moving on here only means the
    // field is filled -- a wrong code fails at the next step, with the
    // password already typed rather than lost.
    setState(() {
      _error = null;
      _info = null;
      _step = _Step.reset;
    });
  }

  // ── Step 3: set the new password ───────────────────────────────────────
  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).finishPasswordReset(
            identifier: _idCtrl.text.trim(),
            email: _email,
            otp: _otpCtrl.text.trim(),
            newPassword: _passCtrl.text,
          );
      if (!mounted) return;
      // Straight back to the login form, which is where they now have to go.
      // The panel is part of the page, so it hands control back rather than
      // popping a route that was never pushed.
      widget.onClose(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendly(e);
        // A bad code sends them back a step with the password kept, so only
        // the code has to be retyped.
        if (_error!.contains('code')) _step = _Step.verify;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final (String label, String title, IconData icon) = switch (_step) {
      _Step.identify => ('FORGOT PASSWORD', 'Reset your password',
          Icons.lock_reset_rounded),
      _Step.verify => ('FORGOT PASSWORD', 'Check your email',
          Icons.mark_email_read_rounded),
      _Step.reset => ('FORGOT PASSWORD', 'Choose a new password',
          Icons.password_rounded),
    };

    // ⚠️ Laid out INLINE, in the sign-in panel -- not in a dialog over it.
    // Resetting a password is the same act as signing in: the officer is
    // getting into their account. A modal made it read as an interruption,
    // dimmed the page behind it, and gave the three steps a different shape
    // from the one they had just been using.
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The same back-arrow-and-heading row the sign-in panel uses, so the
          // step reads as the next page of one flow.
          Row(children: [
            IconButton(
              icon: Icon(Icons.arrow_back_rounded,
                  color: context.colors.textSecondary),
              tooltip: 'Back to sign in',
              onPressed: _busy ? null : () => widget.onClose(false),
            ),
            const Gap(8),
            Expanded(
              child: Text(title,
                  style: Theme.of(context).textTheme.headlineMedium),
            ),
          ]).animate().fadeIn(duration: 400.ms),
          const Gap(8),
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: Text(label,
                style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800)),
          ).animate().fadeIn(delay: 100.ms),
          const Gap(28),
          if (_info != null) ...[
            _Banner(
                text: _info!,
                color: context.colors.successGreen,
                icon: Icons.check_circle_outline),
            const Gap(14),
          ],
          if (_error != null) ...[
            _Banner(
                text: _error!,
                color: context.colors.dangerRed,
                icon: Icons.error_outline),
            const Gap(14),
          ],
          if (_step == _Step.identify) ..._identifyFields(context),
          if (_step == _Step.verify) ..._verifyFields(context, accent),
          if (_step == _Step.reset) ..._resetFields(context),
          const Gap(28),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Icon(switch (_step) {
                      _Step.identify => Icons.send_rounded,
                      _Step.verify => Icons.arrow_forward_rounded,
                      _Step.reset => Icons.check_rounded,
                    }),
              label: Text(
                  switch (_step) {
                    _Step.identify => _busy ? 'Sending...' : 'Send code',
                    _Step.verify => 'Continue',
                    _Step.reset => _busy ? 'Saving...' : 'Save password',
                  },
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              onPressed: _busy
                  ? null
                  : switch (_step) {
                      _Step.identify => _sendCode,
                      _Step.verify => _checkCode,
                      _Step.reset => _save,
                    },
            ),
          ),
          const Gap(12),
          TextButton(
            onPressed: _busy ? null : () => widget.onClose(false),
            child: const Text('Back to sign in'),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms).slideX(begin: 0.06);
  }

  List<Widget> _identifyFields(BuildContext context) => [
        Text(
          'Enter your username or email address. A one-time code will be sent '
          'to the address your account is registered to.',
          style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
        ),
        const Gap(16),
        TextFormField(
          controller: _idCtrl,
          autofocus: true,
          onFieldSubmitted: (_) => _busy ? null : _sendCode(),
          decoration: InputDecoration(
            labelText: 'Username or Email',
            prefixIcon:
                Icon(Icons.person_outline, color: context.colors.textMuted),
          ),
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Username or email required'
              : null,
        ),
      ];

  List<Widget> _verifyFields(BuildContext context, Color accent) => [
        Row(children: [
          Icon(Icons.mark_email_read_outlined,
              size: 18, color: context.colors.textMuted),
          const Gap(10),
          Expanded(
            child: Text(
              _email.isEmpty
                  ? 'Enter the 6-digit code from the email.'
                  : 'Enter the 6-digit code sent to $_email',
              style:
                  TextStyle(color: context.colors.textSecondary, fontSize: 13),
            ),
          ),
        ]),
        const Gap(16),
        TextFormField(
          controller: _otpCtrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          style: const TextStyle(
              fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.w700),
          decoration: const InputDecoration(labelText: 'OTP Code *'),
          onFieldSubmitted: (_) => _checkCode(),
        ),
        const Gap(12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.timer_outlined,
                  size: 16,
                  color: _secondsLeft > 0
                      ? context.colors.textMuted
                      : context.colors.dangerRed),
              const Gap(6),
              Text(
                _secondsLeft > 0
                    ? 'Code expires in '
                        '${(_secondsLeft ~/ 60).toString().padLeft(2, '0')}:'
                        '${(_secondsLeft % 60).toString().padLeft(2, '0')}'
                    : 'Code expired',
                style: TextStyle(
                    color: _secondsLeft > 0
                        ? context.colors.textMuted
                        : context.colors.dangerRed,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600),
              ),
            ]),
            TextButton(
              onPressed:
                  _resending || _busy ? null : () => _sendCode(isResend: true),
              child: Text(_resending ? 'Sending...' : 'Resend code',
                  style: TextStyle(color: accent, fontSize: 13)),
            ),
          ],
        ),
      ];

  List<Widget> _resetFields(BuildContext context) => [
        Text(
          'Choose a new password. You will be returned to the sign-in page to '
          'use it.',
          style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
        ),
        const Gap(16),
        TextFormField(
          controller: _passCtrl,
          autofocus: true,
          obscureText: _obscurePass,
          decoration: InputDecoration(
            labelText: 'New Password *',
            prefixIcon:
                Icon(Icons.lock_outline, color: context.colors.textMuted),
            suffixIcon: IconButton(
              icon: Icon(
                  _obscurePass
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  size: 20,
                  color: context.colors.textMuted),
              onPressed: () => setState(() => _obscurePass = !_obscurePass),
            ),
          ),
          validator: (v) {
            final t = v ?? '';
            if (t.isEmpty) return 'New password required';
            // The same rule auth.change_password enforces, checked here so it
            // is reported on the field rather than as a save failure.
            return PasswordPolicy.violation(t);
          },
        ),
        const Gap(14),
        TextFormField(
          controller: _confirmCtrl,
          obscureText: _obscureConfirm,
          onFieldSubmitted: (_) => _busy ? null : _save(),
          decoration: InputDecoration(
            labelText: 'Confirm New Password *',
            prefixIcon:
                Icon(Icons.lock_outline, color: context.colors.textMuted),
            suffixIcon: IconButton(
              icon: Icon(
                  _obscureConfirm
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  size: 20,
                  color: context.colors.textMuted),
              onPressed: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
          validator: (v) {
            if ((v ?? '').isEmpty) return 'Confirm the new password';
            if (v != _passCtrl.text) return 'The passwords do not match';
            return null;
          },
        ),
      ];
}

class _Banner extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;
  const _Banner({required this.text, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const Gap(10),
        Expanded(
          child: Text(text, style: TextStyle(color: color, fontSize: 12.5)),
        ),
      ]),
    );
  }
}
