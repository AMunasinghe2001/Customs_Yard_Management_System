import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/secure_credentials.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import '../../core/theme.dart';
import '../../core/supabase_client.dart';
import '../../core/providers.dart';
import '../../core/dev_config.dart';
import '../../models/models.dart';
import '../../widgets/brand_panel.dart';
import '../../widgets/auth_back_button.dart';
import '../../core/security_policy.dart';

/// Two-step login for the ICT Directorate: password first, then an email
/// OTP that must be verified on EVERY sign-in (identical flow to the appeal/
/// disposal login).
class IctLoginScreen extends ConsumerStatefulWidget {
  const IctLoginScreen({super.key});
  @override
  ConsumerState<IctLoginScreen> createState() => _IctLoginScreenState();
}

class _IctLoginScreenState extends ConsumerState<IctLoginScreen> {
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

  // Password-expiry gate (mirrors the appeal login).
  ProfileModel? _pendingProfile;
  bool _passwordStage = false;
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  bool _obscureNew = true, _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final creds = await SecureCredentialStore.load('ict_saved');
    setState(() {
      _idCtrl.text = creds['email'] as String? ?? '';
      _passwordCtrl.text = creds['password'] as String? ?? '';
      _rememberMe = creds['remember_me'] as bool? ?? false;
    });
  }

  Future<void> _saveCredentials() async {
    await SecureCredentialStore.save(
      'ict_saved',
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
    if (raw.contains('email_not_confirmed')) {
      return 'Email not confirmed. Please check your inbox and confirm your email address first.';
    }
    if (raw.contains('Invalid login credentials') ||
        raw.contains('invalid_credentials')) {
      return 'Incorrect username/email or password. Please try again.';
    }
    if (raw.contains('too many requests') ||
        raw.contains('over_email_send_rate_limit')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (raw.contains('profile_not_found')) {
      // The auth user exists but has no profiles row — the sign-up got half
      // way. Almost always a database that has not run the ICT migration.
      return 'This account has no profile record, so it cannot sign in. '
          'It was created before the ICT migration was applied — ask ICT to '
          'run supabase/migrations, then register again.';
    }
    // The code is CONSUMED the moment it verifies, so a second tap of
    // "Verify & Sign In" finds nothing left. Without this the user saw the
    // generic "Sign in failed", which told them to retry something that can
    // never succeed and hid the real reason the FIRST attempt was rejected.
    // Raised by startOtpLogin BEFORE any code is sent, so the user is
    // told on the first screen rather than after spending a code.
    if (raw.contains('wrong_portal')) {
      return 'This account is not an ICT Directorate account. Use the correct portal.';
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
    if (raw.contains('account_expired')) {
      return 'Your account has expired (accounts auto-deactivate 8 months after creation). Please contact an administrator.';
    }
    if (low.contains('otp_expired') || low.contains('expired')) {
      return 'The verification code has expired. Please request a new one.';
    }
    if (low.contains('otp_invalid') || low.contains('invalid')) {
      return 'Incorrect verification code. Please check your email and try again.';
    }
    final cleaned = raw
        .replaceAll('Exception: ', '')
        .replaceAll('AuthApiException(', '')
        .trim();
    return 'Sign in failed: $cleaned';
  }

  Future<void> _finishLogin(ProfileModel profile) async {
    ref.read(currentProfileProvider.notifier).state = profile;
    await _saveCredentials();
    if (mounted) context.go('/ict');
  }

  Future<void> _submitLogin({bool isResend = false}) async {
    if (!isResend && !_formKey.currentState!.validate()) return;
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
      if (kDevSkipOtp) {
        final profile = await ref
            .read(authServiceProvider)
            .signInWithIdentifier(_idCtrl.text.trim(), _passwordCtrl.text);
        if (profile == null) {
          setState(() => _error = 'Invalid credentials.');
          return;
        }
        if (!profile.isIct) {
          await supabase.auth.signOut();
          setState(() => _error =
              'This account is not an ICT Directorate account. Use the correct portal.');
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
              requireRole: 'ict');

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
      final profile = await ref.read(authServiceProvider).finishOtpLogin(
          _resolvedEmail, _otpCtrl.text.trim(), _passwordCtrl.text);
      if (profile == null) {
        setState(() => _error = 'Verification failed. Please try again.');
        return;
      }
      if (!profile.isIct) {
        await supabase.auth.signOut();
        setState(() => _error =
            'This account is not an ICT Directorate account. Use the correct portal.');
        return;
      }
      await _finishLogin(profile);
    } catch (e) {
      setState(() => _error = _friendlyError(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitPasswordChange() async {
    final newPass = _newPassCtrl.text;
    final confirm = _confirmPassCtrl.text;
    // The database enforces this too (password_policy_violation); checking
    // here just tells the user before a round trip.
    final policyError = PasswordPolicy.violation(newPass);
    if (policyError != null) {
      setState(() => _error = policyError);
      return;
    }
    if (newPass != confirm) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).changePassword(newPass);
      if (_pendingProfile != null) {
        await _finishLogin(_pendingProfile!);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = _friendlyError(e.toString());
      });
    }
  }

  void _backToPassword() {
    _countdownTimer?.cancel();
    _lockTimer?.cancel();
    setState(() {
      _otpStage = false;
      _passwordStage = false;
      _otpCtrl.clear();
      _newPassCtrl.clear();
      _confirmPassCtrl.clear();
      _error = null;
      _success = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.ictCyan;
    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      body: Stack(children: [
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
        Row(children: [
          // Left - Dark ICT Branding (navy → cyan)
          Expanded(
            flex: 5,
            child: BrandPanel(
              accent: accent,
              deepColor: const Color(0xFF050411),
              badgeLabel: 'ICT Directorate Portal',
              badgeIcon: Icons.terminal_rounded,
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
                            Text(
                              _passwordStage
                                  ? 'Change Password'
                                  : (_otpStage
                                      ? 'Verify OTP'
                                      : 'ICT Directorate Sign In'),
                              style: Theme.of(context).textTheme.headlineMedium,
                            ).animate().fadeIn(duration: 400.ms),
                            const Gap(8),
                            Text(
                                    _passwordStage
                                        ? 'Change your password to continue'
                                        : (_otpStage
                                            ? 'Enter verification code sent to your email'
                                            : 'Restricted to ICT Officers only'),
                                    style: TextStyle(
                                        color: context.colors.textSecondary,
                                        fontSize: 14))
                                .animate()
                                .fadeIn(delay: 100.ms),
                            const Gap(40),
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
                            if (_success != null) ...[
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: context.colors.successGreen
                                      .withOpacity(0.1),
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
                              const Gap(20),
                            ],

                            // ── Step 1: Username + Password ─────────────────────────
                            if (!_otpStage && !_passwordStage) ...[
                              TextFormField(
                                controller: _idCtrl,
                                // Enter submits, so the form can be completed from the
                                // keyboard without reaching for the mouse.
                                onFieldSubmitted: (_) =>
                                    _isLoading ? null : _submitLogin(),
                                decoration: InputDecoration(
                                  labelText: 'Username or Email',
                                  prefixIcon: Icon(Icons.person_outline,
                                      color: context.colors.textMuted),
                                ),
                                keyboardType: TextInputType.text,
                                validator: (v) => v == null || v.isEmpty
                                    ? 'Username or email required'
                                    : null,
                              )
                                  .animate()
                                  .slideX(
                                      begin: 0.1,
                                      duration: 400.ms,
                                      delay: 200.ms)
                                  .fadeIn(),
                              const Gap(16),
                              TextFormField(
                                controller: _passwordCtrl,
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
                                obscureText: _obscurePassword,
                                validator: (v) => v == null || v.isEmpty
                                    ? 'Password required'
                                    : null,
                                onFieldSubmitted: (_) => _submitLogin(),
                              )
                                  .animate()
                                  .slideX(
                                      begin: 0.1,
                                      duration: 400.ms,
                                      delay: 300.ms)
                                  .fadeIn(),
                              const Gap(12),
                              Row(children: [
                                SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: Checkbox(
                                    value: _rememberMe,
                                    activeColor: accent,
                                    onChanged: (v) => setState(
                                        () => _rememberMe = v ?? false),
                                  ),
                                ),
                                const Gap(8),
                                Text('Remember me',
                                    style: TextStyle(
                                        color: context.colors.textSecondary,
                                        fontSize: 13)),
                              ]).animate().fadeIn(delay: 350.ms),
                              const Gap(24),
                              SizedBox(
                                      height: 54,
                                      child: ElevatedButton(
                                        onPressed: _isLoading
                                            ? null
                                            : () => _submitLogin(),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: accent,
                                          foregroundColor: Colors.white,
                                        ),
                                        child: _isLoading
                                            ? const SizedBox(
                                                width: 22,
                                                height: 22,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white))
                                            : const Text('Sign In',
                                                style: TextStyle(fontSize: 16)),
                                      ))
                                  .animate()
                                  .slideY(
                                      begin: 0.3,
                                      duration: 400.ms,
                                      delay: 400.ms)
                                  .fadeIn(),
                              const Gap(24),
                              Divider(
                                  color: context.colors.borderColor
                                      .withOpacity(0.5)),
                              const Gap(16),
                              Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text("Don't have an ICT account?",
                                        style: TextStyle(
                                            color: context.colors.textMuted,
                                            fontSize: 13)),
                                    TextButton(
                                      onPressed: () =>
                                          context.go('/ict/signup'),
                                      child: Text('Create Account',
                                          style: TextStyle(
                                              color: accent,
                                              fontWeight: FontWeight.w600)),
                                    ),
                                  ]).animate().fadeIn(delay: 600.ms),
                            ],

                            // ── Step 2: OTP Verification ────────────────────────────
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
                                decoration: const InputDecoration(
                                    labelText: 'OTP Code *'),
                                onFieldSubmitted: (_) =>
                                    _isLoading ? null : _verify(),
                              )
                                  .animate()
                                  .slideX(
                                      begin: 0.1,
                                      duration: 400.ms,
                                      delay: 200.ms)
                                  .fadeIn(),
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
                                  TextButton(
                                    onPressed: _canResend
                                        ? () => _submitLogin(isResend: true)
                                        : null,
                                    child: Text(
                                      _resendLocked
                                          ? 'Resend locked'
                                          // Its OWN progress text, so a resend in
                                          // flight shows HERE, not on the Verify
                                          // button, which is not doing the work.
                                          : (_isResending
                                              ? 'Sending...'
                                              : (_secondsLeft > 0
                                                  ? 'Resend code'
                                                  : 'Resend code (${_maxResends - _resendCount} left)')),
                                      style: TextStyle(
                                        color: _canResend
                                            ? accent
                                            : context.colors.textMuted,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed:
                                      _isLoading ? null : _backToPassword,
                                  icon: Icon(Icons.edit_outlined,
                                      size: 15,
                                      color: context.colors.textMuted),
                                  label: Text('Back to login',
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
                                        // A RESEND must not make this read "Verifying..." --
                                        // nothing is being verified. Still disabled while one is
                                        // in flight, so the code cannot be checked mid-resend.
                                        icon: _isLoading && !_isResending
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white))
                                            : const Icon(
                                                Icons.how_to_reg_rounded),
                                        label: Text(
                                            _isLoading && !_isResending
                                                ? 'Verifying...'
                                                : 'Verify OTP & Sign In',
                                            style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700)),
                                        onPressed: (_isLoading || _isResending)
                                            ? null
                                            : _verify,
                                      ))
                                  .animate()
                                  .slideY(
                                      begin: 0.3,
                                      duration: 400.ms,
                                      delay: 300.ms)
                                  .fadeIn(),
                            ],

                            // ── Step 3: Password Change (if expired) ────────────────
                            if (_passwordStage) ...[
                              TextFormField(
                                controller: _newPassCtrl,
                                // Enter submits, so the form can be completed from the
                                // keyboard without reaching for the mouse.
                                onFieldSubmitted: (_) =>
                                    _isLoading ? null : _submitPasswordChange(),
                                obscureText: _obscureNew,
                                decoration: InputDecoration(
                                  labelText: 'New Password (min 8 chars)',
                                  prefixIcon: Icon(Icons.lock_reset_rounded,
                                      color: context.colors.textMuted),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                        _obscureNew
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                        color: context.colors.textMuted),
                                    onPressed: () => setState(
                                        () => _obscureNew = !_obscureNew),
                                  ),
                                ),
                              )
                                  .animate()
                                  .slideX(
                                      begin: 0.1,
                                      duration: 400.ms,
                                      delay: 200.ms)
                                  .fadeIn(),
                              const Gap(16),
                              TextFormField(
                                controller: _confirmPassCtrl,
                                // Enter submits, so the form can be completed from the
                                // keyboard without reaching for the mouse.
                                onFieldSubmitted: (_) =>
                                    _isLoading ? null : _submitPasswordChange(),
                                obscureText: _obscureConfirm,
                                decoration: InputDecoration(
                                  labelText: 'Confirm New Password',
                                  prefixIcon: Icon(Icons.lock_clock_outlined,
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
                              )
                                  .animate()
                                  .slideX(
                                      begin: 0.1,
                                      duration: 400.ms,
                                      delay: 300.ms)
                                  .fadeIn(),
                              const Gap(24),
                              SizedBox(
                                      height: 54,
                                      child: ElevatedButton(
                                        onPressed: _isLoading
                                            ? null
                                            : _submitPasswordChange,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: accent,
                                          foregroundColor: Colors.white,
                                        ),
                                        child: _isLoading
                                            ? const SizedBox(
                                                width: 22,
                                                height: 22,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white))
                                            : const Text('Update Password',
                                                style: TextStyle(fontSize: 16)),
                                      ))
                                  .animate()
                                  .slideY(
                                      begin: 0.3,
                                      duration: 400.ms,
                                      delay: 400.ms)
                                  .fadeIn(),
                            ],
                          ],
                        )),
                  ),
                ),
              )),
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
        const AuthBackButton(tooltip: 'Back to portals'),
      ]),
    );
  }
}
