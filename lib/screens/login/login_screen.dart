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

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _emailCtrl.text = prefs.getString('saved_email') ?? '';
      _passwordCtrl.text = prefs.getString('saved_password') ?? '';
      _rememberMe = prefs.getBool('remember_me') ?? false;
    });
  }

  Future<void> _saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString('saved_email', _emailCtrl.text.trim());
      await prefs.setString('saved_password', _passwordCtrl.text);
      await prefs.setBool('remember_me', true);
    } else {
      await prefs.remove('saved_email');
      await prefs.remove('saved_password');
      await prefs.setBool('remember_me', false);
    }
  }

  @override
  void dispose() { _emailCtrl.dispose(); _passwordCtrl.dispose(); super.dispose(); }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    ref.read(loginLoadingProvider.notifier).state = true;
    ref.read(loginErrorProvider.notifier).state = null;
    try {
      final profile = await ref.read(authServiceProvider).signIn(
        _emailCtrl.text.trim(), _passwordCtrl.text,
      );
      if (profile == null) { ref.read(loginErrorProvider.notifier).state = 'Login failed. Check credentials.'; return; }
      if (!profile.isActive) {
        await supabase.auth.signOut();
        ref.read(loginErrorProvider.notifier).state = 'Account is disabled. Contact admin.'; return;
      }
      if (profile.isAdmin) {
        await supabase.auth.signOut();
        ref.read(loginErrorProvider.notifier).state = 'Admin accounts must use the Admin Sign In.'; return;
      }
      await _saveCredentials();
      ref.read(currentProfileProvider.notifier).state = profile;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Logged in successfully as ${profile.fullName}'),
            backgroundColor: context.colors.successGreen,
          ),
        );
        context.go('/dashboard');
      }
    } catch (e) {
      ref.read(loginErrorProvider.notifier).state = _friendlyError(e.toString());
    } finally { ref.read(loginLoadingProvider.notifier).state = false; }
  }

  Future<void> _signInWithGoogle() async {
    ref.read(loginLoadingProvider.notifier).state = true;
    ref.read(loginErrorProvider.notifier).state = null;
    try {
      final profile = await ref.read(authServiceProvider).signInWithGoogle();
      if (profile == null) return;
      if (profile.isAdmin) {
        await supabase.auth.signOut();
        ref.read(loginErrorProvider.notifier).state = 'Admin accounts must use the Admin Sign In.'; return;
      }
      ref.read(currentProfileProvider.notifier).state = profile;
      if (mounted) context.go('/dashboard');
    } catch (e) {
      ref.read(loginErrorProvider.notifier).state = _friendlyError(e.toString());
    } finally { ref.read(loginLoadingProvider.notifier).state = false; }
  }

  String _friendlyError(String raw) {
    if (raw.contains('email_not_confirmed')) {
      return 'Email not confirmed. Please check your inbox and confirm your email address first.';
    }
    if (raw.contains('Invalid login credentials') || raw.contains('invalid_credentials')) {
      return 'Incorrect email or password. Please try again.';
    }
    if (raw.contains('too many requests') || raw.contains('over_email_send_rate_limit')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (raw.contains('account_deactivated')) {
      return 'Your account has been deactivated. Please contact an administrator.';
    }
    return 'Sign in failed. Please check your credentials.';
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(loginLoadingProvider);
    final error = ref.watch(loginErrorProvider);

    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      body: Stack(children: [
        Row(children: [
        // Left – branding
        Expanded(flex: 5, child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [context.colors.primaryNavy, context.colors.customsBlue, context.colors.customsBlueLight],
            ),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            SvgPicture.asset('Sri_Lanka_Customs_logo.svg', width: 200, height: 200,
              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
            ),
            const Gap(36),
            const Text('Sri Lanka Customs',
              style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            const Gap(8),
            const Text('Inventory Management System\nGrey Line 1',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFB0BEC5), fontSize: 16, height: 1.2)),
            const Gap(28),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: context.colors.accentLightBlue.withOpacity(0.4)),
                borderRadius: BorderRadius.circular(24),
                color: context.colors.accentLightBlue.withOpacity(0.08),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.person_outline_rounded, color: context.colors.accentLightBlue, size: 16),
                const Gap(8),
                Text('Officer Portal',
                    style: TextStyle(color: context.colors.accentLightBlue, fontSize: 14, fontWeight: FontWeight.w600)),
              ]),
            ),
          ]),
        )),
        // Right – login form
        Expanded(flex: 4, child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460),
            padding: const EdgeInsets.all(52),
            child: Form(key: _formKey, child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: context.colors.textSecondary),
                    onPressed: () => context.go('/'),
                  ),
                  const Gap(8),
                  Text('Officer Sign In', style: Theme.of(context).textTheme.headlineMedium),
                ]).animate().fadeIn(duration: 400.ms),
                const Gap(8),
                Padding(
                  padding: const EdgeInsets.only(left: 48),
                  child: Text('Enter your credentials to access the system',
                      style: TextStyle(color: context.colors.textSecondary, fontSize: 14)),
                ).animate().fadeIn(delay: 100.ms),
                const Gap(40),
                if (error != null) ...[
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
                      Expanded(child: Text(error, style: TextStyle(color: context.colors.dangerRed, fontSize: 13))),
                    ]),
                  ),
                  const Gap(20),
                ],
                TextFormField(
                  controller: _emailCtrl,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined, color: context.colors.textMuted),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => v == null || v.isEmpty ? 'Email required' : null,
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
                      activeColor: context.colors.accentLightBlue,
                      onChanged: (v) => setState(() => _rememberMe = v ?? false),
                    ),
                  ),
                  const Gap(8),
                  Text('Remember me', style: TextStyle(color: context.colors.textSecondary, fontSize: 13)),
                ]).animate().fadeIn(delay: 350.ms),
                const Gap(24),
                SizedBox(height: 54, child: ElevatedButton(
                  onPressed: isLoading ? null : _signIn,
                  child: isLoading
                      ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.primaryNavy))
                      : const Text('Sign In', style: TextStyle(fontSize: 16)),
                )).animate().slideY(begin: 0.3, duration: 400.ms, delay: 400.ms).fadeIn(),
                const Gap(24),
                Row(children: [
                  Expanded(child: Divider(color: context.colors.borderColor.withOpacity(0.5))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('OR', style: TextStyle(color: context.colors.textMuted, fontSize: 12)),
                  ),
                  Expanded(child: Divider(color: context.colors.borderColor.withOpacity(0.5))),
                ]).animate().fadeIn(delay: 450.ms),
                const Gap(24),
                SizedBox(height: 54, child: OutlinedButton.icon(
                  onPressed: isLoading ? null : _signInWithGoogle,
                  icon: SvgPicture.asset('google_logo.svg', width: 20),
                  label: const Text('Sign in with Google', style: TextStyle(fontSize: 16)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: context.colors.borderColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                )).animate().slideY(begin: 0.3, duration: 400.ms, delay: 500.ms).fadeIn(),
                const Gap(24),
                Divider(color: context.colors.borderColor.withOpacity(0.5)),
                const Gap(16),
                Center(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text("Don't have an account?", style: TextStyle(color: context.colors.textMuted, fontSize: 13)),
                  TextButton(
                    onPressed: () => context.go('/signup'),
                    child: Text('Create Account',
                        style: TextStyle(color: context.colors.accentLightBlue, fontWeight: FontWeight.w600)),
                  ),
                ])).animate().fadeIn(delay: 600.ms),
              ],
            )),
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
