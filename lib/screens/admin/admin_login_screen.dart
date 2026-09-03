import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/secure_credentials.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import '../../core/theme.dart';
import '../../widgets/forgot_password_panel.dart';
import '../../core/supabase_client.dart';
import '../../core/providers.dart';
import '../../services/services.dart';

class AdminLoginScreen extends ConsumerStatefulWidget {
  const AdminLoginScreen({super.key});
  @override
  ConsumerState<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends ConsumerState<AdminLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _error;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final creds = await SecureCredentialStore.load('admin_saved');
    setState(() {
      _emailCtrl.text = creds['email'] as String? ?? '';
      _passwordCtrl.text = creds['password'] as String? ?? '';
      _rememberMe = creds['remember_me'] as bool? ?? false;
    });
  }

  Future<void> _saveCredentials() async {
    await SecureCredentialStore.save(
      'admin_saved',
      emailOrId: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
      rememberMe: _rememberMe,
    );
  }

  @override
  void dispose() { _emailCtrl.dispose(); _passwordCtrl.dispose(); super.dispose(); }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _error = null; });
    try {
      final profile = await ref.read(authServiceProvider).signInWithIdentifier(
        _emailCtrl.text.trim(), _passwordCtrl.text,
      );
      if (profile == null) { setState(() => _error = 'Login failed. Check credentials.'); return; }
      if (!profile.isAdmin) {
        await supabase.auth.signOut();
        setState(() => _error = 'This account is not an Admin. Use the Officer login instead.');
        return;
      }
      if (!profile.isActive) {
        await supabase.auth.signOut();
        setState(() => _error = 'Account is disabled. Contact super admin.'); return;
      }
      await _saveCredentials();
      ref.read(currentProfileProvider.notifier).state = profile;
      if (mounted) {
        context.showSuccess('Logged in successfully as ${profile.fullName}');
        context.go('/admin');
      }
    } catch (e) {
      setState(() => _error = _friendlyError(e.toString()));
    } finally { setState(() => _isLoading = false); }
  }

  Future<void> _signInWithGoogle() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final profile = await ref.read(authServiceProvider).signInWithGoogle();
      if (profile == null) return;
      if (!profile.isAdmin) {
        await supabase.auth.signOut();
        setState(() => _error = 'This account is not an Admin. Use the Officer login instead.');
        return;
      }
      ref.read(currentProfileProvider.notifier).state = profile;
      if (mounted) context.go('/admin');
    } catch (e) {
      setState(() => _error = _friendlyError(e.toString()));
    } finally { setState(() => _isLoading = false); }
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
      return 'Network problem — couldn\'t reach the server. Check your internet connection (Wi-Fi/firewall) and try again.';
    }
    if (raw.contains('email_not_confirmed')) {
      return 'Email not confirmed. Please check your inbox and confirm your email address first.';
    }
    if (raw.contains('Invalid login credentials') || raw.contains('invalid_credentials')) {
      return 'Incorrect username/email or password. Please try again.';
    }
    if (raw.contains('too many requests') || raw.contains('over_email_send_rate_limit')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (raw.contains('account_deactivated')) {
      return 'Your account has been deactivated. Please contact another administrator.';
    }
    if (raw.contains('account_expired')) {
      return 'Your account has expired (accounts auto-deactivate 8 months after creation). Please contact another administrator.';
    }
    // Surface the underlying error instead of a vague catch-all, so DB/RLS or
    // configuration problems are visible rather than looking like a bad password.
    final cleaned = raw
        .replaceAll('Exception: ', '')
        .replaceAll('AuthApiException(', '')
        .trim();
    return 'Sign in failed: $cleaned';
  }

  /// Whether the right-hand panel is showing the reset flow instead of the
  /// sign-in form.
  ///
  /// ⚠️ Not a dialog. Resetting a password is the same act as signing in --
  /// the officer is getting into their account -- so it happens in the same
  /// panel, as the next page of one flow.
  bool _resetting = false;

  /// Shows the reset flow, pre-filled with whatever was already typed.
  void _openForgotPassword() => setState(() => _resetting = true);

  /// Back from the reset flow. On success the officer is left on the sign-in
  /// form with a note to sign in again -- which is exactly where they need
  /// to be.
  void _closeForgotPassword(bool changed) {
    if (!mounted) return;
    setState(() => _resetting = false);
    if (changed) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text(
            'Password changed. Sign in with your new password.'),
        backgroundColor: context.colors.successGreen,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      body: Stack(children: [
      Positioned(top: 24, right: 24,
        child: IconButton(
          icon: Icon(ref.watch(themeModeProvider) == ThemeMode.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, 
              color: context.colors.textPrimary),
          onPressed: () {
            final isDark = ref.read(themeModeProvider) == ThemeMode.dark;
            ref.read(themeModeProvider.notifier).state = isDark ? ThemeMode.light : ThemeMode.dark;
          },
        ),
      ),
        Row(children: [
        // Left - Dark Admin Branding (navy)
        Expanded(flex: 5, child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [const Color(0xFF050411), context.colors.primaryNavy, context.colors.primaryGold],
            ),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              // Logo - big, no circle, tinted gold for admin
              SvgPicture.asset(
                'Sri_Lanka_Customs_logo_tinted.svg',
                width: 200,
                height: 200,
                theme: const SvgTheme(currentColor: Color(0xFFD4A017)),
              ),
            const Gap(36),
            Text('Sri Lanka Customs',
              style: TextStyle(color: context.colors.primaryGold, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 1.2),
            ).animate().slideY(begin: 0.5, duration: 500.ms).fadeIn(),
            const Text('SR Management System',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFB0BEC5), fontSize: 16, height: 1.2),
            ).animate().slideY(begin: 0.5, duration: 500.ms, delay: 100.ms).fadeIn(),
            const Gap(28),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: context.colors.primaryGold.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(24),
                color: context.colors.primaryGold.withOpacity(0.06),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.admin_panel_settings_rounded, color: context.colors.primaryGold, size: 16),
                const Gap(8),
                Text('DC / SDDC Portal',
                    style: TextStyle(color: context.colors.primaryGold, fontSize: 14, fontWeight: FontWeight.w600)),
              ]),
            ).animate().fadeIn(delay: 300.ms),
          ]),
        )),
        // Right - Admin Login form
        Expanded(flex: 4, child: Center(
          child: SingleChildScrollView(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 460),
              padding: const EdgeInsets.all(52),
              child: _resetting
                  ? ForgotPasswordPanel(
                      accent: context.colors.primaryGold,
                      initialIdentifier: _emailCtrl.text.trim(),
                      onClose: _closeForgotPassword,
                    )
                  : Form(key: _formKey, child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_rounded, color: context.colors.textSecondary),
                      // Back to the Yard Access page (Officer / DC-SDDC tiles).
                      onPressed: () => context.go('/yard-access'),
                    ),
                    const Gap(8),
                    Text('DC / SDDC Sign In', style: Theme.of(context).textTheme.headlineMedium),
                  ]).animate().fadeIn(duration: 400.ms),
                  const Gap(8),
                  Padding(
                    padding: const EdgeInsets.only(left: 48),
                    child: Text('Restricted to DC / SDDC officers only',
                        style: TextStyle(color: context.colors.textSecondary, fontSize: 14)),
                  ).animate().fadeIn(delay: 100.ms),
                  const Gap(40),
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: context.colors.dangerRed.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: context.colors.dangerRed.withOpacity(0.4)),
                      ),
                      child: Row(children: [
                        Icon(Icons.error_outline, color: context.colors.dangerRed, size: 18),
                        const Gap(10),
                        Expanded(child: Text(_error!, style: TextStyle(color: context.colors.dangerRed, fontSize: 13))),
                      ]),
                    ),
                    const Gap(20),
                  ],
                  TextFormField(
                    controller: _emailCtrl,
                    // Enter submits, so the form can be completed from the
                    // keyboard without reaching for the mouse.
                    onFieldSubmitted: (_) => _isLoading ? null : _signIn(),
                    decoration: InputDecoration(
                      labelText: 'Username or Email',
                      prefixIcon: Icon(Icons.person_outline, color: context.colors.textMuted),
                    ),
                    keyboardType: TextInputType.text,
                    validator: (v) => v == null || v.isEmpty ? 'Username or email required' : null,
                  ).animate().slideX(begin: 0.1, duration: 400.ms, delay: 200.ms).fadeIn(),
                  const Gap(16),
                  TextFormField(
                    controller: _passwordCtrl,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline, color: context.colors.textMuted),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: context.colors.textMuted),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    obscureText: _obscurePassword,
                    validator: (v) => v == null || v.isEmpty ? 'Password required' : null,
                    onFieldSubmitted: (_) => _signIn(),
                  ).animate().slideX(begin: 0.1, duration: 400.ms, delay: 300.ms).fadeIn(),
                  const Gap(12),
                  Row(children: [
                    SizedBox(
                      width: 24, height: 24,
                      child: Checkbox(
                        value: _rememberMe,
                        activeColor: context.colors.primaryGold,
                        onChanged: (v) => setState(() => _rememberMe = v ?? false),
                      ),
                    ),
                    const Gap(8),
                    Text('Remember me', style: TextStyle(color: context.colors.textSecondary, fontSize: 13)),
                    const Spacer(),
                    // Beside Remember-me: both are things an officer
                    // reaches for at a sign-in that will not go through.
                    TextButton(
                      onPressed: _openForgotPassword,
                      style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      child: Text('Forgot password?',
                          style: TextStyle(
                              color: context.colors.primaryGold,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ),
                  ]).animate().fadeIn(delay: 350.ms),
                  const Gap(24),
                  SizedBox(height: 54, child: ElevatedButton(
                    onPressed: _isLoading ? null : _signIn,
                    child: _isLoading
                        ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.primaryNavy))
                        : const Text('Sign In', style: TextStyle(fontSize: 16)),
                  )).animate().slideY(begin: 0.3, duration: 400.ms, delay: 400.ms).fadeIn(),
                  const Gap(24),
                  Divider(color: context.colors.borderColor.withOpacity(0.5)),
                  const Gap(16),
                  Center(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.info_outline_rounded, size: 15, color: context.colors.textMuted),
                    const Gap(6),
                    Flexible(
                      child: Text('DC / SDDC accounts are provisioned by the ICT Directorate.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.colors.textMuted, fontSize: 13)),
                    ),
                  ])).animate().fadeIn(delay: 500.ms),
                ],
              )),
            ),
          ),
        )),
      ]),
      Positioned(top: 24, right: 24,
        child: IconButton(
          icon: Icon(ref.watch(themeModeProvider) == ThemeMode.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, 
              color: context.colors.textPrimary),
          onPressed: () {
            final isDark = ref.read(themeModeProvider) == ThemeMode.dark;
            ref.read(themeModeProvider.notifier).state = isDark ? ThemeMode.light : ThemeMode.dark;
          },
        ),
      ),
    ]),
    );
  }
}
