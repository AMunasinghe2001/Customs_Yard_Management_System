import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import '../../core/theme.dart';
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

  @override
  void dispose() { _emailCtrl.dispose(); _passwordCtrl.dispose(); super.dispose(); }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _error = null; });
    try {
      final profile = await ref.read(authServiceProvider).signIn(
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
      ref.read(currentProfileProvider.notifier).state = profile;
      if (mounted) context.go('/admin');
    } catch (e) {
      setState(() => _error = _friendlyError(e.toString()));
    } finally { setState(() => _isLoading = false); }
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
    return 'Sign in failed. Please check your credentials.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      body: Row(children: [
        // Left - Dark Admin Branding (navy)
        Expanded(flex: 5, child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [const Color(0xFF050411), context.colors.primaryNavy, context.colors.customsBlueDark],
            ),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            // Logo - big, no circle, tinted gold for admin
            SvgPicture.asset(
              'Sri_Lanka_Customs_logo.svg',
              width: 200, height: 200,
              colorFilter: ColorFilter.mode(context.colors.primaryGold, BlendMode.srcIn),
            ).animate().scale(duration: 700.ms, curve: Curves.easeOutBack).fadeIn(),
            const Gap(36),
            Text('Sri Lanka Customs',
              style: TextStyle(color: context.colors.primaryGold, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 1.2),
            ).animate().slideY(begin: 0.5, duration: 500.ms).fadeIn(),
            const Gap(8),
            const Text('Yard Management System',
              style: TextStyle(color: Color(0xFFB0BEC5), fontSize: 17),
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
                Text('Admin Portal',
                    style: TextStyle(color: context.colors.primaryGold, fontSize: 14, fontWeight: FontWeight.w600)),
              ]),
            ).animate().fadeIn(delay: 300.ms),
          ]),
        )),

        // Right - Admin Login form
        Expanded(flex: 4, child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460),
            padding: const EdgeInsets.all(52),
            child: Form(key: _formKey, child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.colors.primaryGold.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.admin_panel_settings_rounded, color: context.colors.primaryGold, size: 22),
                  ),
                  const Gap(14),
                  Text('Admin Sign In', style: Theme.of(context).textTheme.headlineMedium),
                ]).animate().fadeIn(duration: 400.ms),
                const Gap(8),
                Text('Restricted to administrators only',
                    style: TextStyle(color: context.colors.textSecondary, fontSize: 14))
                    .animate().fadeIn(delay: 100.ms),
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
                  decoration: InputDecoration(
                    labelText: 'Admin Email',
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
                const Gap(32),
                SizedBox(height: 54, child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.primaryGold,
                    foregroundColor: context.colors.primaryNavy,
                  ),
                  onPressed: _isLoading ? null : _signIn,
                  child: _isLoading
                      ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.primaryNavy))
                      : const Text('Sign In as Admin', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                )).animate().slideY(begin: 0.3, duration: 400.ms, delay: 400.ms).fadeIn(),
                const Gap(24),
                Divider(color: context.colors.borderColor.withOpacity(0.5)),
                const Gap(16),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  TextButton.icon(
                    icon: const Icon(Icons.arrow_back_rounded, size: 16),
                    label: const Text('Officer Login'),
                    onPressed: () => context.go('/'),
                    style: TextButton.styleFrom(foregroundColor: context.colors.textMuted),
                  ),
                  TextButton(
                    onPressed: () => context.go('/admin/signup'),
                    child: Text('Create Admin',
                        style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.w600)),
                  ),
                ]).animate().fadeIn(delay: 600.ms),
              ],
            )),
          ),
        )),
      ]),
    );
  }
}
