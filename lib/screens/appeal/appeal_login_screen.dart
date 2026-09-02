import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/secure_credentials.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import '../../core/theme.dart';
import '../../core/supabase_client.dart';
import '../../core/providers.dart';
import '../../core/dev_config.dart';
import '../../models/models.dart';
import '../../services/services.dart';

/// Two-step login for the Appeal Directorate: password first, then an email OTP
/// that must be verified on EVERY sign-in (identical flow to the disposal login).
class AppealLoginScreen extends ConsumerStatefulWidget {
  const AppealLoginScreen({super.key});
  @override
  ConsumerState<AppealLoginScreen> createState() => _AppealLoginScreenState();
}

class _AppealLoginScreenState extends ConsumerState<AppealLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _idCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  /// Resending is its OWN action. It used to share `_isLoading`, so
  /// tapping "Resend code" put the Verify button into "Verifying..."
  /// while nothing was being verified.
  bool _isResending = false;
  bool _rememberMe = false;
  bool _otpStage = false;
  String _resolvedEmail = '';
  String? _error, _success;

  static const int _otpWindowSeconds = 120;
  static const int _maxResends = 2;
  Timer? _countdownTimer;
  Timer? _lockTimer;
  int _secondsLeft = 0;
  int _resendCount = 0;
  DateTime? _resendLockUntil;

  // Password-expiry gate (mirrors the disposal login).
  ProfileModel? _pendingProfile;
  bool _passwordStage = false;
  bool _passwordExpired = false;
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  bool _obscureNew = true, _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final creds = await SecureCredentialStore.load('appeal_saved');
    setState(() {
      _idCtrl.text = creds['email'] as String? ?? '';
      _passwordCtrl.text = creds['password'] as String? ?? '';
      _rememberMe = creds['remember_me'] as bool? ?? false;
    });
  }

  Future<void> _saveCredentials() async {
    await SecureCredentialStore.save(
      'appeal_saved',
      emailOrId: _idCtrl.text.trim(),
      password: _passwordCtrl.text,
      rememberMe: _rememberMe,
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _lockTimer?.cancel();
    _idCtrl.dispose();
    _passwordCtrl.dispose();
    _otpCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  bool get _resendLocked =>
      _resendLockUntil != null && DateTime.now().isBefore(_resendLockUntil!);
  bool get _canResend =>
      _otpStage &&
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

  Future<void> _continue({bool isResend = false}) async {
    if (isResend) {
      if (_resendLocked || !_canResend) return;
    } else {
      if (!_formKey.currentState!.validate()) return;
    }
    setState(() {
      if (isResend) {
        _isResending = true;
      } else {
        _isLoading = true;
      }
      _error = null;
      _success = null;
    });
    try {
      // DEV/TESTING: skip the emailed OTP — verify password and sign in.
      if (kDevSkipOtp && !isResend) {
        final profile = await ref
            .read(authServiceProvider)
            .passwordOnlyLogin(_idCtrl.text.trim(), _passwordCtrl.text);
        if (profile == null) {
          setState(() => _error = 'Verification failed. Please try again.');
          return;
        }
        if (!profile.isAppeal) {
          await supabase.auth.signOut();
          setState(() => _error =
              'This account is not an Appeal Directorate account. Use the correct portal.');
          return;
        }
        if (profile.isPasswordExpired || profile.isPasswordExpiringSoon) {
          _countdownTimer?.cancel();
          setState(() {
            _pendingProfile = profile;
            _passwordExpired = profile.isPasswordExpired;
            _passwordStage = true;
            _otpStage = false;
            _success = null;
            _error = null;
          });
          return;
        }
        await _finishLogin(profile);
        return;
      }
      final email = await ref
          .read(authServiceProvider)
          .startOtpLogin(_idCtrl.text.trim(), _passwordCtrl.text,
              // Reject a wrong-portal account HERE, before a code
              // is sent, instead of after it has been spent.
              requireRole: 'appeal');
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
        _resolvedEmail = email;
        _otpStage = true;
        _success = 'A verification code was sent to your email.';
      });
      _startCountdown();
    } catch (e) {
      setState(() => _error = _friendlyError(e.toString()));
    } finally {
      // BOTH flags: a resend sets _isResending, and leaving it true left
      // the Verify button stuck on "Verifying..." beside a "Code
      // expired" notice, with no verification actually running.
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isResending = false;
        });
      }
    }
  }

  Future<void> _verify() async {
    if (_otpCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please enter the OTP code.');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final profile = await ref
          .read(authServiceProvider)
          .finishOtpLogin(_resolvedEmail, _otpCtrl.text.trim(),
              _passwordCtrl.text);
      if (profile == null) {
        setState(() => _error = 'Verification failed. Please try again.');
        return;
      }
      if (!profile.isAppeal) {
        await supabase.auth.signOut();
        setState(() => _error =
            'This account is not an Appeal Directorate account. Use the correct portal.');
        return;
      }
      if (profile.isPasswordExpired || profile.isPasswordExpiringSoon) {
        _countdownTimer?.cancel();
        setState(() {
          _pendingProfile = profile;
          _passwordExpired = profile.isPasswordExpired;
          _passwordStage = true;
          _otpStage = false;
          _success = null;
          _error = null;
        });
        return;
      }
      await _finishLogin(profile);
    } catch (e) {
      setState(() => _error = _friendlyError(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _finishLogin(ProfileModel profile) async {
    await _saveCredentials();
    ref.read(currentProfileProvider.notifier).state = profile;
    if (mounted) {
      context.showSuccess('Logged in as ${profile.fullName}');
      context.go('/appeal');
    }
  }

  Future<void> _submitNewPassword() async {
    final newPass = _newPassCtrl.text;
    if (newPass.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (newPass != _confirmPassCtrl.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).changePassword(newPass);
      final refreshed = await ref.read(authServiceProvider).getCurrentProfile();
      final profile = refreshed ?? _pendingProfile!;
      _passwordCtrl.text = newPass;
      await _finishLogin(profile);
    } catch (e) {
      setState(() => _error = _friendlyError(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _skipPasswordChange() async {
    final profile = _pendingProfile;
    if (profile == null) return;
    setState(() => _isLoading = true);
    try {
      await _finishLogin(profile);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _backToCredentials() {
    _countdownTimer?.cancel();
    setState(() {
      _otpStage = false;
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
      return 'Too many email requests. Please wait a few minutes before trying again.';
    }
    if (raw.contains('Invalid login credentials') ||
        raw.contains('invalid_credentials')) {
      return 'Incorrect username/email or password. Please try again.';
    }
    if (low.contains('expired')) {
      return 'This code has expired. Tap "Resend code" for a new one, then enter it within 2 minutes.';
    }
    if (raw.contains('otp_failed') ||
        low.contains('invalid_otp') ||
        low.contains('token')) {
      return 'Invalid or expired code. Use the code from the latest email, or tap "Resend code".';
    }
    // The code is CONSUMED the moment it verifies, so a second tap of
    // "Verify & Sign In" finds nothing left. Without this the user saw the
    // generic "Sign in failed", which told them to retry something that can
    // never succeed and hid the real reason the FIRST attempt was rejected.
    // Raised by startOtpLogin BEFORE any code is sent, so the user is
    // told on the first screen rather than after spending a code.
    if (raw.contains('wrong_portal')) {
      return 'This account is not an Appeal Directorate account. Use the correct portal.';
    }
    if (low.contains('no verification code')) {
      return 'That code has already been used. Tap "Resend code" for a new one.';
    }
    if (low.contains('too many attempts')) {
      return 'Too many incorrect attempts. Tap "Resend code" for a new one.';
    }
    if (raw.contains('account_deactivated')) {
      return 'Your account has been deactivated. Please contact an administrator.';
    }
    return 'Sign in failed. Please try again.';
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
      onPressed: _canResend ? () => _continue(isResend: true) : null,
      style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 0),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      // Its OWN progress text, so a resend in flight is visible HERE rather
      // than on the Verify button, which is not doing the work.
      child: Text(
        _isResending
            ? 'Sending...'
            : (_secondsLeft > 0
                ? 'Resend code'
                : 'Resend code ($remaining left)'),
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
    final accent = AppTheme.appealPurple;
    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      body: Stack(children: [
        Row(children: [
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
                    AppTheme.appealPurple
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: accent.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(24),
                      color: accent.withOpacity(0.06),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.balance_rounded, color: accent, size: 16),
                      const Gap(8),
                      Text('Appeal Directorate',
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
                  padding: const EdgeInsets.all(52),
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
                            onPressed: () => context.go('/'),
                          ),
                          const Gap(8),
                          Text('Appeal Sign In',
                              style:
                                  Theme.of(context).textTheme.headlineMedium),
                        ]).animate().fadeIn(duration: 400.ms),
                        const Gap(8),
                        Padding(
                          padding: const EdgeInsets.only(left: 48),
                          child: Text(
                              _passwordStage
                                  ? (_passwordExpired
                                      ? 'Your password has expired'
                                      : 'Update your password')
                                  : _otpStage
                                      ? 'Two-step verification'
                                      : 'Appeal Directorate access',
                              style: TextStyle(
                                  color: context.colors.textSecondary,
                                  fontSize: 14)),
                        ).animate().fadeIn(delay: 100.ms),
                        const Gap(36),
                        if (_success != null && _otpStage) ...[
                          // Green, not the portal accent: this is a
                          // confirmation that the code went out, and it has to
                          // read as one on every portal alike.
                          _banner(context, _success!,
                              context.colors.successGreen,
                              Icons.check_circle_outline),
                          const Gap(16),
                        ],
                        if (_error != null) ...[
                          _banner(context, _error!, context.colors.dangerRed,
                              Icons.error_outline),
                          const Gap(16),
                        ],
                        if (!_otpStage && !_passwordStage) ...[
                          TextFormField(
                            controller: _idCtrl,
                            // Enter submits, so the form can be completed from the
                            // keyboard without reaching for the mouse.
                            onFieldSubmitted: (_) => _isLoading ? null : _continue(),
                            decoration: InputDecoration(
                              labelText: 'Username or Email',
                              prefixIcon: Icon(Icons.person_outline,
                                  color: context.colors.textMuted),
                            ),
                            validator: (v) => v == null || v.isEmpty
                                ? 'Username or email required'
                                : null,
                          ),
                          const Gap(16),
                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: Icon(Icons.lock_outline,
                                  color: context.colors.textMuted),
                              suffixIcon: IconButton(
                                icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: context.colors.textMuted),
                                onPressed: () => setState(() =>
                                    _obscurePassword = !_obscurePassword),
                              ),
                            ),
                            validator: (v) => v == null || v.isEmpty
                                ? 'Password required'
                                : null,
                            onFieldSubmitted: (_) => _continue(),
                          ),
                          const Gap(12),
                          Row(children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: _rememberMe,
                                activeColor: accent,
                                onChanged: (v) =>
                                    setState(() => _rememberMe = v ?? false),
                              ),
                            ),
                            const Gap(8),
                            Text('Remember me',
                                style: TextStyle(
                                    color: context.colors.textSecondary,
                                    fontSize: 13)),
                          ]),
                          const Gap(24),
                          SizedBox(
                            height: 54,
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
                                  : const Icon(Icons.arrow_forward_rounded),
                              label: Text(
                                  _isLoading ? 'Please wait...' : 'Continue',
                                  style: const TextStyle(fontSize: 16)),
                              onPressed: _isLoading ? null : () => _continue(),
                            ),
                          ),
                          const Gap(20),
                          Divider(
                              color:
                                  context.colors.borderColor.withOpacity(0.5)),
                          Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text("Don't have an account?",
                                    style: TextStyle(
                                        color: context.colors.textMuted,
                                        fontSize: 13)),
                                TextButton(
                                  onPressed: () =>
                                      context.go('/appeal/signup'),
                                  child: Text('Create Account',
                                      style: TextStyle(
                                          color: accent,
                                          fontWeight: FontWeight.w600)),
                                ),
                              ]),
                        ],
                        if (_otpStage) ...[
                          Row(children: [
                            Icon(Icons.mark_email_read_rounded,
                                color: accent, size: 22),
                            const Gap(10),
                            Expanded(
                              child: Text(
                                'Enter the 6-digit code sent to\n$_resolvedEmail',
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
                                _isLoading ? null : _verify(),
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
                              onPressed: _isLoading ? null : _backToCredentials,
                              icon: Icon(Icons.arrow_back_rounded,
                                  size: 15, color: context.colors.textMuted),
                              label: Text('Back',
                                  style: TextStyle(
                                      color: context.colors.textMuted,
                                      fontSize: 13)),
                            ),
                          ),
                          const Gap(10),
                          SizedBox(
                            height: 54,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: accent,
                                  foregroundColor: Colors.white),
                              // A RESEND must not make this read
                              // "Verifying..." -- nothing is being verified.
                              // It is still disabled while one is in flight,
                              // so the code cannot be checked mid-resend.
                              icon: _isLoading && !_isResending
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.login_rounded),
                              label: Text(
                                  _isLoading && !_isResending
                                      ? 'Verifying...'
                                      : 'Verify & Sign In',
                                  style: const TextStyle(fontSize: 16)),
                              onPressed:
                                  (_isLoading || _isResending) ? null : _verify,
                            ),
                          ),
                        ],
                        if (_passwordStage)
                          ..._buildPasswordStage(context, accent),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]),
        Positioned(
          top: 24,
          right: 24,
          child: IconButton(
            icon: Icon(
                ref.watch(themeModeProvider) == ThemeMode.dark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
                color: context.colors.textPrimary),
            onPressed: () {
              final isDark = ref.read(themeModeProvider) == ThemeMode.dark;
              ref.read(themeModeProvider.notifier).state =
                  isDark ? ThemeMode.light : ThemeMode.dark;
            },
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
        color: color.withOpacity(0.1),
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

  List<Widget> _buildPasswordStage(BuildContext context, Color accent) {
    final profile = _pendingProfile;
    final daysLeft = profile?.daysUntilPasswordExpiry ?? 0;
    final amber = context.colors.warningAmber;
    final red = context.colors.dangerRed;
    final accentColor = _passwordExpired ? red : amber;

    return [
      _banner(
        context,
        _passwordExpired
            ? 'Your password has passed its 90-day limit. Set a new password to continue.'
            : 'Your password expires in $daysLeft day${daysLeft == 1 ? '' : 's'}. '
                'Set a new one now, or skip and change it later.',
        accentColor,
        _passwordExpired
            ? Icons.lock_clock_rounded
            : Icons.warning_amber_rounded,
      ),
      const Gap(20),
      TextFormField(
        controller: _newPassCtrl,
        // Enter submits, so the form can be completed from the
        // keyboard without reaching for the mouse.
        onFieldSubmitted: (_) => _isLoading ? null : _submitNewPassword(),
        obscureText: _obscureNew,
        decoration: InputDecoration(
          labelText: 'New Password',
          helperText: 'Minimum 8 characters',
          prefixIcon: Icon(Icons.lock_outline, color: context.colors.textMuted),
          suffixIcon: IconButton(
            icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility,
                color: context.colors.textMuted),
            onPressed: () => setState(() => _obscureNew = !_obscureNew),
          ),
        ),
      ),
      const Gap(16),
      TextFormField(
        controller: _confirmPassCtrl,
        obscureText: _obscureConfirm,
        decoration: InputDecoration(
          labelText: 'Confirm New Password',
          prefixIcon: Icon(Icons.lock_outline, color: context.colors.textMuted),
          suffixIcon: IconButton(
            icon: Icon(
                _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                color: context.colors.textMuted),
            onPressed: () =>
                setState(() => _obscureConfirm = !_obscureConfirm),
          ),
        ),
        onFieldSubmitted: (_) => _isLoading ? null : _submitNewPassword(),
      ),
      const Gap(24),
      SizedBox(
        height: 54,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
              backgroundColor: accent, foregroundColor: Colors.white),
          icon: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_circle_rounded),
          label: Text(_isLoading ? 'Updating...' : 'Update Password & Sign In',
              style: const TextStyle(fontSize: 16)),
          onPressed: _isLoading ? null : _submitNewPassword,
        ),
      ),
      if (!_passwordExpired) ...[
        const Gap(10),
        Center(
          child: TextButton(
            onPressed: _isLoading ? null : _skipPasswordChange,
            child: Text('Skip for now',
                style: TextStyle(
                    color: context.colors.textMuted,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    ];
  }
}
