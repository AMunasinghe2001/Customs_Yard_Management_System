import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/services.dart';
import '../../core/providers.dart';
import '../../widgets/styled_dropdown.dart';

/// Creates one of the two institutional Executive Office accounts
/// (DC / SDDC). Position-based, head-office accounts (not personal) — only one
/// per position can exist (enforced by the unique username +
/// executive_position_available RPC).
class ExecutiveSignupScreen extends ConsumerStatefulWidget {
  const ExecutiveSignupScreen({super.key});
  @override
  ConsumerState<ExecutiveSignupScreen> createState() =>
      _ExecutiveSignupScreenState();
}

class _ExecutiveSignupScreenState extends ConsumerState<ExecutiveSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  String? _position; // 'DG' | 'ADG' | 'DC'
  bool _obscurePass = true, _obscureConfirm = true;
  bool _isLoading = false;
  bool _otpSent = false;
  String? _error, _success;

  static const int _otpWindowSeconds = 120;
  static const int _maxResends = 2;
  Timer? _countdownTimer;
  Timer? _lockTimer;
  int _secondsLeft = 0;
  int _resendCount = 0;
  DateTime? _resendLockUntil;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _lockTimer?.cancel();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  String get _username => (_position ?? '').toLowerCase(); // 'dg'|'adg'|'dc'
  // Position keys are already the short titles (DG / ADG).
  String get _shortTitle => _position ?? '';
  // NOTE: stored in profiles.full_name at signup, so accounts created before
  // the "High Panel Officers" rename keep their old "Executive Office (DG)"
  // label until edited.
  String get _fullName => 'High Panel Officers ($_shortTitle)';

  bool get _resendLocked =>
      _resendLockUntil != null && DateTime.now().isBefore(_resendLockUntil!);
  bool get _canResend =>
      _otpSent &&
      !_isLoading &&
      !_resendLocked &&
      _secondsLeft == 0 &&
      _resendCount < _maxResends;

  String get _countdownText {
    final m = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() => _secondsLeft = _otpWindowSeconds);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  Future<void> _sendOtp({bool isResend = false}) async {
    if (_resendLocked) {
      setState(() =>
          _error = 'Too many OTP requests. Please try again after 2 hours.');
      return;
    }
    if (!isResend) {
      if (!_formKey.currentState!.validate()) return;
      if (_position == null) {
        setState(() => _error = 'Please select the position (DG, ADG or DC).');
        return;
      }
    } else if (!_canResend) {
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
      _success = null;
    });
    try {
      if (!isResend) {
        final available = await ref
            .read(adminServiceProvider)
            .isExecutivePositionAvailable(_position!);
        if (!available) {
          setState(() {
            _isLoading = false;
            _error =
                'A ${executivePositionLabel(_position)} account already exists. Only one account per post is allowed.';
          });
          return;
        }
      }
      await ref.read(adminServiceProvider).requestSignupOtp(
            email: _emailCtrl.text.trim(),
            fullName: _fullName,
            badgeNumber: '',
            username: _username,
            jobRole: _position,
            role: 'executive',
          );
      if (isResend) {
        _resendCount++;
        if (_resendCount >= _maxResends) {
          _resendLockUntil = DateTime.now().add(const Duration(hours: 2));
          _lockTimer?.cancel();
          _lockTimer = Timer(const Duration(hours: 2), () {
            if (mounted) {
              setState(() {
                _resendCount = 0;
                _resendLockUntil = null;
              });
            }
          });
        }
      }
      setState(() {
        _otpSent = true;
        _success = isResend
            ? 'A new code was sent to ${_emailCtrl.text.trim()}.'
            : 'Code sent to ${_emailCtrl.text.trim()}.';
      });
      _startCountdown();
    } catch (e) {
      setState(() => _error = _friendlyError(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyAndCreate() async {
    if (_otpCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please enter the OTP code.');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
      _success = null;
    });
    try {
      await ref.read(adminServiceProvider).verifySignupOtp(
            email: _emailCtrl.text.trim(),
            otp: _otpCtrl.text.trim(),
            password: _passwordCtrl.text,
            fullName: _fullName,
            badgeNumber: '',
            username: _username,
            jobRole: _position,
            role: 'executive',
          );
      _countdownTimer?.cancel();
      _lockTimer?.cancel();
      setState(() {
        _success = 'Account verified! Redirecting to Sign In...';
        _otpSent = false;
      });
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) context.go('/executive/login');
    } catch (e) {
      setState(() => _error = _friendlyError(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _editDetails() {
    _countdownTimer?.cancel();
    setState(() {
      _otpSent = false;
      _otpCtrl.clear();
      _error = null;
      _success = null;
    });
  }

  String _friendlyError(String raw) {
    final low = raw.toLowerCase();
    if (low.contains('socketexception') ||
        low.contains('retryablefetch') ||
        low.contains('semaphore') ||
        low.contains('failed host lookup') ||
        low.contains('clientexception') ||
        low.contains('failedtoopensocket') ||
        low.contains('timed out')) {
      return 'Network problem — couldn\'t reach the server. Check your internet connection and try again.';
    }
    if (low.contains('rate limit') ||
        low.contains('429') ||
        low.contains('over_email_send_rate_limit')) {
      return 'Too many email requests. Please wait a few minutes before sending the OTP again.';
    }
    if (low.contains('same_password') ||
        low.contains('different from the old')) {
      return 'A ${executivePositionLabel(_position)} account already exists for this email. Try signing in instead.';
    }
    if (low.contains('duplicate') ||
        low.contains('23505') ||
        low.contains('profiles_username_lower_idx') ||
        low.contains('unique')) {
      return 'A ${executivePositionLabel(_position)} account already exists. Only one account per post is allowed.';
    }
    if (raw.contains('already_registered') ||
        raw.contains('already been registered')) {
      return 'This email is already registered. Please sign in instead.';
    }
    if (low.contains('expired')) {
      return 'This code has expired. Tap "Resend code" to get a new one, then enter it within 2 minutes.';
    }
    if (raw.contains('invalid_otp') ||
        raw.contains('otp') ||
        raw.contains('token')) {
      return 'Invalid or expired code. Use the code from the latest email, or tap "Resend code".';
    }
    return raw
        .replaceAll('Exception: ', '')
        .replaceAll('AuthApiException(', '')
        .replaceAll(')', '');
  }

  Widget _buildResendControl(BuildContext context, Color accent) {
    if (_resendLocked) {
      final u = _resendLockUntil!;
      return Text('Resend after ${_two(u.hour)}:${_two(u.minute)}',
          style: TextStyle(
              color: context.colors.dangerRed,
              fontSize: 12,
              fontWeight: FontWeight.w600));
    }
    if (_resendCount >= _maxResends) {
      return Text('Resend limit reached',
          style: TextStyle(color: context.colors.textMuted, fontSize: 12));
    }
    final remaining = _maxResends - _resendCount;
    return TextButton(
      onPressed: _canResend ? () => _sendOtp(isResend: true) : null,
      style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 0),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      child: Text(
        _secondsLeft > 0 ? 'Resend code' : 'Resend code ($remaining left)',
        style: TextStyle(
          color: _canResend ? accent : context.colors.textMuted,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.executiveTeal;
    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      body: Row(children: [
        Expanded(
          flex: 5,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF0A0F2C),
                  context.colors.primaryNavy,
                  AppTheme.executiveTeal
                ],
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgPicture.asset('Sri_Lanka_Customs_logo_tinted.svg',
                        width: 200,
                        height: 200,
                        theme: SvgTheme(currentColor: accent))
                    .animate()
                    .scale(duration: 700.ms, curve: Curves.easeOutBack)
                    .fadeIn(),
                const Gap(36),
                Text('Sri Lanka Customs',
                    style: TextStyle(
                        color: accent,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2)),
                const Text('SR Management System',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Color(0xFFB0BEC5), fontSize: 16, height: 1.2)),
                const Gap(28),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: accent.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(24),
                    color: accent.withOpacity(0.06),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.shield_moon_rounded, color: accent, size: 16),
                    const Gap(8),
                    Text('Executive • Create Account',
                        style: TextStyle(
                            color: accent,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 4,
          child: Center(
            child: SingleChildScrollView(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 460),
                padding: const EdgeInsets.all(48),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        IconButton(
                          icon: Icon(Icons.arrow_back_rounded,
                              color: context.colors.textSecondary),
                          onPressed: () => context.go('/executive/login'),
                        ),
                        const Gap(8),
                        Text('Executive Sign Up',
                            style: Theme.of(context).textTheme.headlineMedium),
                      ]),
                      const Gap(4),
                      Padding(
                        padding: const EdgeInsets.only(left: 48),
                        child: Text(
                            'Head-office account — one for DC and one for SDDC',
                            style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 14)),
                      ),
                      const Gap(8),
                      Padding(
                        padding: const EdgeInsets.only(left: 40),
                        child: Row(children: [
                          Text('Already have an account?',
                              style: TextStyle(
                                  color: context.colors.textMuted,
                                  fontSize: 13)),
                          TextButton(
                            onPressed: () => context.go('/executive/login'),
                            child: Text('Sign In',
                                style: TextStyle(
                                    color: accent,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                          ),
                        ]),
                      ),
                      const Gap(20),
                      if (_success != null) ...[
                        _banner(context, _success!, accent,
                            Icons.check_circle_outline),
                        const Gap(16),
                      ],
                      if (_error != null) ...[
                        _banner(context, _error!, context.colors.dangerRed,
                            Icons.error_outline),
                        const Gap(20),
                      ],
                      if (!_otpSent) ...[
                        StyledDropdownFormField<String>(
                          value: _position,
                          label: 'Position *',
                          helperText:
                              'One account per post (DG · ADG · DC)',
                          menuWidth: 364,
                          prefixIcon: Icon(Icons.badge_outlined,
                              color: context.colors.textMuted),
                          options: [
                            for (final e in kExecutivePositions.entries)
                              StyledDropdownOption(e.key, e.value),
                          ],
                          onChanged: (v) => setState(() => _position = v),
                          validator: (v) => v == null || v.isEmpty
                              ? 'Select a position'
                              : null,
                        ),
                        const Gap(14),
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Branch Email *',
                            helperText: 'OTP is sent here on every login',
                          ),
                          validator: (v) => v == null || v.isEmpty
                              ? 'Email required'
                              : !v.contains('@')
                                  ? 'Invalid email'
                                  : null,
                        ),
                        const Gap(14),
                        TextFormField(
                          controller: _passwordCtrl,
                          obscureText: _obscurePass,
                          decoration: InputDecoration(
                            labelText: 'Password *',
                            suffixIcon: IconButton(
                              icon: Icon(
                                  _obscurePass
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: context.colors.textMuted),
                              onPressed: () =>
                                  setState(() => _obscurePass = !_obscurePass),
                            ),
                          ),
                          validator: (v) => v == null || v.length < 8
                              ? 'Min 8 characters'
                              : null,
                        ),
                        const Gap(14),
                        TextFormField(
                          controller: _confirmCtrl,
                          obscureText: _obscureConfirm,
                          decoration: InputDecoration(
                            labelText: 'Confirm Password *',
                            suffixIcon: IconButton(
                              icon: Icon(
                                  _obscureConfirm
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: context.colors.textMuted),
                              onPressed: () => setState(
                                  () => _obscureConfirm = !_obscureConfirm),
                            ),
                          ),
                          validator: (v) => v != _passwordCtrl.text
                              ? 'Passwords do not match'
                              : null,
                        ),
                        const Gap(28),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: Colors.white),
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.mark_email_unread_rounded),
                            label: Text(_isLoading ? 'Sending...' : 'Send OTP',
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700)),
                            onPressed: _isLoading ? null : () => _sendOtp(),
                          ),
                        ),
                      ],
                      if (_otpSent) ...[
                        Row(children: [
                          Icon(Icons.mark_email_read_rounded,
                              color: accent, size: 22),
                          const Gap(10),
                          Expanded(
                            child: Text(
                              'Enter the 6-digit code sent to\n${_emailCtrl.text.trim()}',
                              style: TextStyle(
                                  color: context.colors.textSecondary,
                                  fontSize: 13),
                            ),
                          ),
                        ]),
                        const Gap(20),
                        TextFormField(
                          controller: _otpCtrl,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 22,
                              letterSpacing: 8,
                              fontWeight: FontWeight.w700),
                          decoration:
                              const InputDecoration(labelText: 'OTP Code *'),
                          onFieldSubmitted: (_) =>
                              _isLoading ? null : _verifyAndCreate(),
                        ),
                        const Gap(14),
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
                                    ? 'Code expires in $_countdownText'
                                    : 'Code expired',
                                style: TextStyle(
                                  color: _secondsLeft > 0
                                      ? context.colors.textSecondary
                                      : context.colors.dangerRed,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ]),
                            _buildResendControl(context, accent),
                          ],
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _isLoading ? null : _editDetails,
                            icon: Icon(Icons.edit_outlined,
                                size: 15, color: context.colors.textMuted),
                            label: Text('Change details',
                                style: TextStyle(
                                    color: context.colors.textMuted,
                                    fontSize: 13)),
                          ),
                        ),
                        const Gap(10),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: Colors.white),
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.how_to_reg_rounded),
                            label: Text(
                                _isLoading
                                    ? 'Processing...'
                                    : 'Verify OTP & Create Account',
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700)),
                            onPressed: _isLoading ? null : _verifyAndCreate,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _banner(
      BuildContext context, String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const Gap(10),
        Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 13))),
      ]),
    );
  }
}
