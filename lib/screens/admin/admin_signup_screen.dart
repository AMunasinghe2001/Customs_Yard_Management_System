import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import '../../core/theme.dart';
import '../../widgets/password_strength_field.dart';
import '../../widgets/brand_panel.dart';
import '../../widgets/directorate_yard_picker.dart';
import '../../services/services.dart';
import '../../services/otp_service.dart';
import '../../core/providers.dart';
import '../../widgets/styled_dropdown.dart';
import '../../widgets/auth_back_button.dart';
import '../../core/security_policy.dart';
import '../../widgets/portal_field_theme.dart';

class AdminSignupScreen extends ConsumerStatefulWidget {
  const AdminSignupScreen({super.key});
  @override
  ConsumerState<AdminSignupScreen> createState() => _AdminSignupScreenState();
}

class _AdminSignupScreenState extends ConsumerState<AdminSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _salaryCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  String? _selectedDirectorate;
  String? _selectedYard;
  bool _obscurePass = true, _obscureConfirm = true;
  bool _isLoading = false;
  bool _otpSent = false;
  String? _error, _success;

  // ── OTP timer / resend throttling ──────────────────────────────
  static int get _otpWindowSeconds => GmailOtpService.codeLifetime.inSeconds;
  static const int _maxResends = 2; // resend allowed twice
  Timer? _countdownTimer;
  Timer? _lockTimer;
  int _secondsLeft = 0;
  int _resendCount = 0;
  DateTime? _resendLockUntil; // after 2 resends → locked for 2 hours

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _lockTimer?.cancel();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _salaryCtrl.dispose();
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

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
    } else if (!_canResend) {
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
      _success = null;
    });
    try {
      final fullName =
          '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}';
      await ref.read(adminServiceProvider).requestSignupOtp(
            email: _emailCtrl.text.trim(),
            fullName: fullName,
            badgeNumber: _salaryCtrl.text.trim(),
            username: _usernameCtrl.text.trim().isEmpty
                ? null
                : _usernameCtrl.text.trim(),
            role: 'admin',
            yard: _selectedYard,
            directorate: _selectedDirectorate,
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
    final cleanOtp = _otpCtrl.text.replaceAll(RegExp(r'\s+'), '');
    if (cleanOtp.isEmpty) {
      setState(() => _error = 'Please enter the OTP code.');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
      _success = null;
    });
    try {
      final fullName =
          '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}';
      await ref.read(adminServiceProvider).verifySignupOtp(
            email: _emailCtrl.text.trim(),
            otp: cleanOtp,
            password: _passwordCtrl.text,
            fullName: fullName,
            badgeNumber: _salaryCtrl.text.trim(),
            username: _usernameCtrl.text.trim().isEmpty
                ? null
                : _usernameCtrl.text.trim(),
            role: 'admin',
            yard: _selectedYard,
            directorate: _selectedDirectorate,
          );
      _countdownTimer?.cancel();
      _lockTimer?.cancel();
      setState(() {
        _success = 'Account verified! Redirecting to Sign In...';
      });
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) context.go('/admin/login');
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
    if (low.contains('rate limit') ||
        low.contains('429') ||
        low.contains('over_email_send_rate_limit')) {
      return 'Too many email requests. Please wait a few minutes before sending the OTP again.';
    }
    if (low.contains('same_password') ||
        low.contains('different from the old')) {
      return 'This account already exists with this password. Try signing in instead.';
    }
    if (raw.contains('already_registered') ||
        raw.contains('User already registered') ||
        raw.contains('already been registered')) {
      return 'This email is already registered. Please sign in instead.';
    }
    if (raw.toLowerCase().contains('expired')) {
      return 'This code has expired. Tap "Resend code" to get a new one, then enter it within 2 minutes.';
    }
    if (raw.contains('invalid_otp') ||
        raw.contains('otp') ||
        raw.contains('token')) {
      return 'Invalid or expired code. Use the code from the latest email, or tap "Resend code".';
    }
    if (raw.contains('Invalid login credentials') ||
        raw.contains('invalid_credentials')) {
      return 'Invalid email or password. Please try again.';
    }
    if (raw.contains('too many requests') ||
        raw.contains('over_email_send_rate_limit')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    return raw
        .replaceAll('Exception: ', '')
        .replaceAll('AuthApiException(', '')
        .replaceAll(')', '');
  }

  Widget _buildResendControl(BuildContext context) {
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
          color: _canResend
              ? context.colors.primaryGold
              : context.colors.textMuted,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      body: Stack(children: [
        Row(children: [
          // Left branding - dark admin theme with gold logo
          Expanded(
            flex: 5,
            child: BrandPanel(
              accent: context.colors.primaryGold,
              badgeLabel: 'SDDC / DDC • Create Account',
              badgeIcon: Icons.person_add_rounded,
            ),
          ),
          Expanded(
              flex: 4,
              child: PortalFieldTheme(
                accent: context.colors.primaryGold,
                child: Center(
                    child: SingleChildScrollView(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 480),
                    padding: const EdgeInsets.all(48),
                    child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('SDDC / DDC Sign Up',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium)
                                .animate()
                                .fadeIn(duration: 400.ms),
                            const Gap(4),
                            Text('Create a SDDC / DDC account',
                                    style: TextStyle(
                                        color: context.colors.textSecondary,
                                        fontSize: 14))
                                .animate()
                                .fadeIn(delay: 100.ms),
                            const Gap(8),
                            // "Already have account" link
                            Padding(
                              padding: const EdgeInsets.only(left: 40),
                              child: Row(children: [
                                Text('Already have an account?',
                                    style: TextStyle(
                                        color: context.colors.textMuted,
                                        fontSize: 13)),
                                TextButton(
                                  onPressed: () => context.go('/admin/login'),
                                  child: Text('Sign In',
                                      style: TextStyle(
                                          color: context.colors.primaryGold,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13)),
                                ),
                              ]),
                            ).animate().fadeIn(delay: 150.ms),
                            const Gap(20),

                            if (_success != null) ...[
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: context.colors.successGreen
                                      .withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: context.colors.successGreen
                                          .withOpacity(0.4)),
                                ),
                                child: Row(children: [
                                  Icon(Icons.check_circle_outline,
                                      color: context.colors.successGreen,
                                      size: 18),
                                  const Gap(10),
                                  Expanded(
                                      child: Text(_success!,
                                          style: TextStyle(
                                              color:
                                                  context.colors.successGreen,
                                              fontSize: 13))),
                                ]),
                              ),
                              const Gap(16),
                            ],
                            if (_error != null) ...[
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color:
                                      context.colors.dangerRed.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: context.colors.dangerRed
                                          .withOpacity(0.4)),
                                ),
                                child: Row(children: [
                                  Icon(Icons.error_outline,
                                      color: context.colors.dangerRed,
                                      size: 18),
                                  const Gap(10),
                                  Expanded(
                                      child: Text(_error!,
                                          style: TextStyle(
                                              color: context.colors.dangerRed,
                                              fontSize: 13))),
                                ]),
                              ),
                              const Gap(20),
                            ],

                            if (!_otpSent) ...[
                              // First & Last Name
                              Row(children: [
                                Expanded(
                                    child: TextFormField(
                                  controller: _firstNameCtrl,
                                  // Enter submits, so the form can be completed from the
                                  // keyboard without reaching for the mouse.
                                  onFieldSubmitted: (_) =>
                                      _isLoading ? null : _sendOtp(),
                                  decoration: InputDecoration(
                                    labelText: 'First Name *',
                                    prefixIcon: Icon(Icons.person_outline,
                                        color: context.colors.textMuted),
                                  ),
                                  validator: (v) => v == null || v.isEmpty
                                      ? 'Required'
                                      : null,
                                )),
                                const Gap(12),
                                Expanded(
                                    child: TextFormField(
                                  controller: _lastNameCtrl,
                                  // Enter submits, so the form can be completed from the
                                  // keyboard without reaching for the mouse.
                                  onFieldSubmitted: (_) =>
                                      _isLoading ? null : _sendOtp(),
                                  decoration: const InputDecoration(
                                      labelText: 'Last Name *'),
                                  validator: (v) => v == null || v.isEmpty
                                      ? 'Required'
                                      : null,
                                )),
                              ])
                                  .animate()
                                  .slideX(
                                      begin: 0.1,
                                      duration: 400.ms,
                                      delay: 200.ms)
                                  .fadeIn(),
                              const Gap(14),

                              // Salary Number (full width, below names)
                              TextFormField(
                                controller: _salaryCtrl,
                                // Enter submits, so the form can be completed from the
                                // keyboard without reaching for the mouse.
                                onFieldSubmitted: (_) =>
                                    _isLoading ? null : _sendOtp(),
                                decoration: InputDecoration(
                                  labelText: 'Salary Number',
                                  prefixIcon: Icon(Icons.badge_outlined,
                                      color: context.colors.textMuted),
                                ),
                              )
                                  .animate()
                                  .slideX(
                                      begin: 0.1,
                                      duration: 400.ms,
                                      delay: 240.ms)
                                  .fadeIn(),
                              const Gap(14),

                              // Username — admin's login handle (can also log in with email)
                              TextFormField(
                                controller: _usernameCtrl,
                                // Enter submits, so the form can be completed from the
                                // keyboard without reaching for the mouse.
                                onFieldSubmitted: (_) =>
                                    _isLoading ? null : _sendOtp(),
                                decoration: InputDecoration(
                                  labelText: 'Username *',
                                  helperText:
                                      'Used to sign in (email also works)',
                                  prefixIcon: Icon(
                                      Icons.alternate_email_rounded,
                                      color: context.colors.textMuted),
                                ),
                                validator: (v) {
                                  final t = v?.trim() ?? '';
                                  if (t.isEmpty) return 'Username required';
                                  if (t.length < 3) return 'Min 3 characters';
                                  if (t.contains('@'))
                                    return 'Username cannot contain @';
                                  if (t.contains(' '))
                                    return 'No spaces allowed';
                                  return null;
                                },
                              )
                                  .animate()
                                  .slideX(
                                      begin: 0.1,
                                      duration: 400.ms,
                                      delay: 250.ms)
                                  .fadeIn(),
                              const Gap(14),

                              // Which directorate, then which of ITS yards. The pair decides
                              // this account's SR-number prefix for good, so it is asked at
                              // registration rather than inferred later.
                              DirectorateYardPicker(
                                directorate: _selectedDirectorate,
                                yard: _selectedYard,
                                onDirectorateChanged: (v) => setState(() {
                                  _selectedDirectorate = v;
                                  _selectedYard = null;
                                }),
                                onYardChanged: (v) =>
                                    setState(() => _selectedYard = v),
                              )
                                  .animate()
                                  .slideX(
                                      begin: 0.1,
                                      duration: 400.ms,
                                      delay: 260.ms)
                                  .fadeIn(),
                              const Gap(14),

                              TextFormField(
                                controller: _emailCtrl,
                                // Enter submits, so the form can be completed from the
                                // keyboard without reaching for the mouse.
                                onFieldSubmitted: (_) =>
                                    _isLoading ? null : _sendOtp(),
                                decoration: InputDecoration(
                                  labelText: 'Email *',
                                  prefixIcon: Icon(Icons.email_outlined,
                                      color: context.colors.textMuted),
                                ),
                                keyboardType: TextInputType.emailAddress,
                                validator: (v) => v == null || v.isEmpty
                                    ? 'Email required'
                                    : !v.contains('@')
                                        ? 'Invalid email'
                                        : null,
                              )
                                  .animate()
                                  .slideX(
                                      begin: 0.1,
                                      duration: 400.ms,
                                      delay: 280.ms)
                                  .fadeIn(),
                              const Gap(14),

                              PasswordRequirements(
                                  password: _passwordCtrl.text),
                              const Gap(10),
                              TextFormField(
                                controller: _passwordCtrl,
                                onChanged: (_) => setState(() {}),
                                // Enter submits, so the form can be completed from the
                                // keyboard without reaching for the mouse.
                                onFieldSubmitted: (_) =>
                                    _isLoading ? null : _sendOtp(),
                                decoration: InputDecoration(
                                  labelText: 'Password *',
                                  prefixIcon: Icon(Icons.lock_outline,
                                      color: context.colors.textMuted),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                        _obscurePass
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                        color: context.colors.textMuted),
                                    onPressed: () => setState(
                                        () => _obscurePass = !_obscurePass),
                                  ),
                                ),
                                obscureText: _obscurePass,
                                validator: PasswordPolicy.validate,
                              )
                                  .animate()
                                  .slideX(
                                      begin: 0.1,
                                      duration: 400.ms,
                                      delay: 320.ms)
                                  .fadeIn(),
                              PasswordStrengthBar(password: _passwordCtrl.text),
                              const Gap(14),

                              TextFormField(
                                controller: _confirmCtrl,
                                onChanged: (_) => setState(() {}),
                                // Enter submits, so the form can be completed from the
                                // keyboard without reaching for the mouse.
                                onFieldSubmitted: (_) =>
                                    _isLoading ? null : _sendOtp(),
                                decoration: InputDecoration(
                                  labelText: 'Confirm Password *',
                                  prefixIcon: Icon(Icons.lock_outline,
                                      color: context.colors.textMuted),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                        _obscureConfirm
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                        color: context.colors.textMuted),
                                    onPressed: () => setState(() =>
                                        _obscureConfirm = !_obscureConfirm),
                                  ),
                                ),
                                obscureText: _obscureConfirm,
                                validator: (v) => v != _passwordCtrl.text
                                    ? 'Passwords do not match'
                                    : null,
                              )
                                  .animate()
                                  .slideX(
                                      begin: 0.1,
                                      duration: 400.ms,
                                      delay: 360.ms)
                                  .fadeIn(),
                              PasswordMatchBar(
                                  password: _passwordCtrl.text,
                                  confirm: _confirmCtrl.text),
                              const Gap(28),

                              SizedBox(
                                      height: 52,
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              context.colors.primaryGold,
                                          foregroundColor:
                                              context.colors.primaryNavy,
                                        ),
                                        icon: _isLoading
                                            ? SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: context.colors
                                                            .primaryNavy))
                                            : const Icon(Icons
                                                .mark_email_unread_rounded),
                                        label: Text(
                                            _isLoading
                                                ? 'Sending...'
                                                : 'Send OTP',
                                            style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700)),
                                        onPressed: _isLoading
                                            ? null
                                            : () => _sendOtp(),
                                      ))
                                  .animate()
                                  .slideY(
                                      begin: 0.3,
                                      duration: 400.ms,
                                      delay: 400.ms)
                                  .fadeIn(),
                            ],

                            // ── OTP verification step (shown on its own) ──────────
                            if (_otpSent) ...[
                              Row(children: [
                                Icon(Icons.mark_email_read_rounded,
                                    color: context.colors.primaryGold,
                                    size: 22),
                                const Gap(10),
                                Expanded(
                                  child: Text(
                                    'Enter the 6-digit code sent to\n${_emailCtrl.text.trim()}',
                                    style: TextStyle(
                                        color: context.colors.textSecondary,
                                        fontSize: 13),
                                  ),
                                ),
                              ]).animate().fadeIn(duration: 300.ms),
                              const Gap(20),
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
                                    fontSize: 22,
                                    letterSpacing: 8,
                                    fontWeight: FontWeight.w700),
                                decoration: InputDecoration(
                                  labelText: 'OTP Code *',
                                  prefixIcon: Icon(Icons.verified_user_rounded,
                                      color: context.colors.textMuted),
                                ),
                                onFieldSubmitted: (_) =>
                                    _isLoading ? null : _verifyAndCreate(),
                              ),
                              const Gap(14),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
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
                                  _buildResendControl(context),
                                ],
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: _isLoading ? null : _editDetails,
                                  icon: Icon(Icons.edit_outlined,
                                      size: 15,
                                      color: context.colors.textMuted),
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
                                          backgroundColor:
                                              context.colors.primaryGold,
                                          foregroundColor:
                                              context.colors.primaryNavy,
                                        ),
                                        icon: _isLoading
                                            ? SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: context.colors
                                                            .primaryNavy))
                                            : const Icon(
                                                Icons.how_to_reg_rounded),
                                        label: Text(
                                            _isLoading
                                                ? 'Processing...'
                                                : 'Verify OTP & Create Account',
                                            style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700)),
                                        onPressed: _isLoading
                                            ? null
                                            : _verifyAndCreate,
                                      ))
                                  .animate()
                                  .slideY(
                                      begin: 0.3,
                                      duration: 400.ms,
                                      delay: 200.ms)
                                  .fadeIn(),
                            ],
                          ],
                        )),
                  ),
                )),
              )),
        ]),
        // No onPressed: the arrow returns to whatever page the officer
        // came from, falling back to the sign-in only when there is no
        // history to pop.
        const AuthBackButton(
          tooltip: 'Back to sign in',
          fallbackRoute: '/admin/login',
        ),
      ]),
    );
  }
}
