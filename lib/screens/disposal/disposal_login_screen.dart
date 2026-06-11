import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import '../../core/theme.dart';
import '../../core/supabase_client.dart';
import '../../core/providers.dart';
import '../../services/services.dart';

/// Two-step login for the Disposal Directorate: password first, then an email
/// OTP that must be verified on EVERY sign-in.
class DisposalLoginScreen extends ConsumerStatefulWidget {
  const DisposalLoginScreen({super.key});
  @override
  ConsumerState<DisposalLoginScreen> createState() =>
      _DisposalLoginScreenState();
}

class _DisposalLoginScreenState extends ConsumerState<DisposalLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _idCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
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

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _idCtrl.text = prefs.getString('disposal_saved_id') ?? '';
      _passwordCtrl.text = prefs.getString('disposal_saved_password') ?? '';
      _rememberMe = prefs.getBool('disposal_remember_me') ?? false;
    });
  }

  Future<void> _saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString('disposal_saved_id', _idCtrl.text.trim());
      await prefs.setString('disposal_saved_password', _passwordCtrl.text);
      await prefs.setBool('disposal_remember_me', true);
    } else {
      await prefs.remove('disposal_saved_id');
      await prefs.remove('disposal_saved_password');
      await prefs.setBool('disposal_remember_me', false);
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _lockTimer?.cancel();
    _idCtrl.dispose();
    _passwordCtrl.dispose();
    _otpCtrl.dispose();
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

  // Phase 1: verify password, send OTP.
  Future<void> _continue({bool isResend = false}) async {
    if (isResend) {
      if (_resendLocked || !_canResend) return;
    } else {
      if (!_formKey.currentState!.validate()) return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
      _success = null;
    });
    try {
      final email = await ref
          .read(authServiceProvider)
          .startOtpLogin(_idCtrl.text.trim(), _passwordCtrl.text);
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Phase 2: verify the OTP and sign in.
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
          .finishOtpLogin(_resolvedEmail, _otpCtrl.text.trim());
      if (profile == null) {
        setState(() => _error = 'Verification failed. Please try again.');
        return;
      }
      if (!profile.isDisposal) {
        await supabase.auth.signOut();
        setState(() => _error =
            'This account is not a Disposal Directorate account. Use the correct portal.');
        return;
      }
      await _saveCredentials();
      ref.read(currentProfileProvider.notifier).state = profile;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ Logged in as ${profile.fullName}'),
          backgroundColor: context.colors.successGreen,
        ));
        context.go('/disposal');
      }
    } catch (e) {
      setState(() => _error = _friendlyError(e.toString()));
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
    if (raw.contains('account_expired')) {
      return 'Your account has expired. Please contact an administrator.';
    }
    if (raw.contains('account_deactivated')) {
      return 'Your account has been deactivated. Please contact an administrator.';
    }
    return 'Sign in failed. Please try again.';
  }

  Widget _buildResendControl(BuildContext context, Color green) {
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
      child: Text(
        _secondsLeft > 0 ? 'Resend code' : 'Resend code ($remaining left)',
        style: TextStyle(
          color: _canResend ? green : context.colors.textMuted,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final green = context.colors.successGreen;
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
                    const Color(0xFF051A0F),
                    context.colors.primaryNavy,
                    context.colors.customsBlueDark
                  ],
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SvgPicture.asset('Sri_Lanka_Customs_logo_tinted.svg',
                          width: 200,
                          height: 200,
                          theme: SvgTheme(currentColor: green))
                      .animate()
                      .scale(duration: 700.ms, curve: Curves.easeOutBack)
                      .fadeIn(),
                  const Gap(36),
                  Text('Sri Lanka Customs',
                      style: TextStyle(
                          color: green,
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
                      border: Border.all(color: green.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(24),
                      color: green.withOpacity(0.06),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.gavel_rounded, color: green, size: 16),
                      const Gap(8),
                      Text('Central Disposal Directorate',
                          style: TextStyle(
                              color: green,
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
                          Text('Disposal Sign In',
                              style:
                                  Theme.of(context).textTheme.headlineMedium),
                        ]),
                        const Gap(8),
                        Padding(
                          padding: const EdgeInsets.only(left: 48),
                          child: Text(
                              _otpStage
                                  ? 'Two-step verification'
                                  : 'Central Disposal Directorate access',
                              style: TextStyle(
                                  color: context.colors.textSecondary,
                                  fontSize: 14)),
                        ),
                        const Gap(36),
                        if (_success != null && _otpStage) ...[
                          _banner(context, _success!, green,
                              Icons.check_circle_outline),
                          const Gap(16),
                        ],
                        if (_error != null) ...[
                          _banner(context, _error!, context.colors.dangerRed,
                              Icons.error_outline),
                          const Gap(16),
                        ],
                        if (!_otpStage) ...[
                          TextFormField(
                            controller: _idCtrl,
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
                                activeColor: green,
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
                                  backgroundColor: green,
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
                                      context.go('/disposal/signup'),
                                  child: Text('Create Account',
                                      style: TextStyle(
                                          color: green,
                                          fontWeight: FontWeight.w600)),
                                ),
                              ]),
                        ],
                        if (_otpStage) ...[
                          Row(children: [
                            Icon(Icons.mark_email_read_rounded,
                                color: green, size: 22),
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
                              _buildResendControl(context, green),
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
                                  backgroundColor: green,
                                  foregroundColor: Colors.white),
                              icon: _isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.login_rounded),
                              label: Text(
                                  _isLoading
                                      ? 'Verifying...'
                                      : 'Verify & Sign In',
                                  style: const TextStyle(fontSize: 16)),
                              onPressed: _isLoading ? null : _verify,
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
}
