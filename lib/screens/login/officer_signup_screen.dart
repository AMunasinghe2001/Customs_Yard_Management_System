import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import '../../core/theme.dart';
import '../../services/services.dart';
import '../../core/providers.dart';

class OfficerSignupScreen extends ConsumerStatefulWidget {
  const OfficerSignupScreen({super.key});
  @override
  ConsumerState<OfficerSignupScreen> createState() => _OfficerSignupScreenState();
}

class _OfficerSignupScreenState extends ConsumerState<OfficerSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _salaryCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscurePass = true, _obscureConfirm = true;
  bool _isLoading = false;
  String? _error, _success;

  @override
  void dispose() {
    _firstNameCtrl.dispose(); _lastNameCtrl.dispose(); _salaryCtrl.dispose();
    _emailCtrl.dispose(); _passwordCtrl.dispose(); _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _error = null; _success = null; });
    try {
      final fullName = '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}';
      await ref.read(adminServiceProvider).createOfficer(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        fullName: fullName,
        badgeNumber: _salaryCtrl.text.trim(),
        role: 'officer',
      );
      setState(() {
        _success = 'Account created successfully! Redirecting to Sign In...';
        _formKey.currentState?.reset();
        _firstNameCtrl.clear(); _lastNameCtrl.clear(); _salaryCtrl.clear();
        _emailCtrl.clear(); _passwordCtrl.clear(); _confirmCtrl.clear();
      });
      // Auto-navigate to login after 2 seconds
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) context.go('/login');
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('email_not_confirmed')) {
        setState(() => _success = 'Account created! Please confirm your email before signing in.');
        await Future.delayed(const Duration(seconds: 3));
        if (mounted) context.go('/login');
      } else {
        setState(() => _error = _friendlyError(msg));
      }
    } finally { setState(() => _isLoading = false); }
  }

  String _friendlyError(String raw) {
    if (raw.contains('already_registered') || raw.contains('User already registered') || raw.contains('already been registered')) {
      return 'This email is already registered. Please sign in instead.';
    }
    if (raw.contains('email_not_confirmed')) {
      return 'Email not confirmed. Please check your inbox.';
    }
    if (raw.contains('too many requests') || raw.contains('over_email_send_rate_limit')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    return raw.replaceAll('Exception: ', '').replaceAll('AuthApiException(', '').replaceAll(')', '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      body: Row(children: [
        // Left branding
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
            ).animate().scale(duration: 700.ms, curve: Curves.easeOutBack).fadeIn(),
            const Gap(36),
            const Text('Sri Lanka Customs',
              style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            const Gap(8),
            const Text('Yard Management System',
              style: TextStyle(color: Color(0xFFB0BEC5), fontSize: 17)),
            const Gap(28),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: context.colors.accentLightBlue.withOpacity(0.4)),
                borderRadius: BorderRadius.circular(24),
                color: context.colors.accentLightBlue.withOpacity(0.08),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.person_add_rounded, color: context.colors.accentLightBlue, size: 16),
                const Gap(8),
                Text('Officer • Create Account',
                    style: TextStyle(color: context.colors.accentLightBlue, fontSize: 14, fontWeight: FontWeight.w600)),
              ]),
            ),
          ]),
        )),

        // Right form
        Expanded(flex: 4, child: Center(child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            padding: const EdgeInsets.all(48),
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
                  Text('Officer Sign Up', style: Theme.of(context).textTheme.headlineMedium),
                ]).animate().fadeIn(duration: 400.ms),
                const Gap(4),
                Padding(
                  padding: const EdgeInsets.only(left: 48),
                  child: Text('Create your officer account',
                      style: TextStyle(color: context.colors.textSecondary, fontSize: 14)),
                ).animate().fadeIn(delay: 100.ms),
                const Gap(8),
                // "Already have account" link
                Padding(
                  padding: const EdgeInsets.only(left: 40),
                  child: Row(children: [
                    Text('Already have an account?', style: TextStyle(color: context.colors.textMuted, fontSize: 13)),
                    TextButton(
                      onPressed: () => context.go('/login'),
                      child: Text('Sign In',
                          style: TextStyle(color: context.colors.accentLightBlue, fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ]),
                ).animate().fadeIn(delay: 150.ms),
                const Gap(20),

                if (_success != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.colors.successGreen.withOpacity(0.12), borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: context.colors.successGreen.withOpacity(0.4)),
                    ),
                    child: Row(children: [
                      Icon(Icons.check_circle_outline, color: context.colors.successGreen, size: 18),
                      const Gap(10),
                      Expanded(child: Text(_success!, style: TextStyle(color: context.colors.successGreen, fontSize: 13))),
                    ]),
                  ),
                  const Gap(16),
                ],
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.colors.dangerRed.withOpacity(0.1), borderRadius: BorderRadius.circular(10),
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

                // First & Last Name
                Row(children: [
                  Expanded(child: TextFormField(
                    controller: _firstNameCtrl,
                    decoration: InputDecoration(
                      labelText: 'First Name *',
                      prefixIcon: Icon(Icons.person_outline, color: context.colors.textMuted),
                    ),
                    validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                  )),
                  const Gap(12),
                  Expanded(child: TextFormField(
                    controller: _lastNameCtrl,
                    decoration: const InputDecoration(labelText: 'Last Name *'),
                    validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                  )),
                ]).animate().slideX(begin: 0.1, duration: 400.ms, delay: 200.ms).fadeIn(),
                const Gap(14),

                // Salary Number (full width, below names)
                TextFormField(
                  controller: _salaryCtrl,
                  decoration: InputDecoration(
                    labelText: 'Salary Number',
                    prefixIcon: Icon(Icons.badge_outlined, color: context.colors.textMuted),
                  ),
                ).animate().slideX(begin: 0.1, duration: 400.ms, delay: 240.ms).fadeIn(),
                const Gap(14),

                TextFormField(
                  controller: _emailCtrl,
                  decoration: InputDecoration(
                    labelText: 'Email *',
                    prefixIcon: Icon(Icons.email_outlined, color: context.colors.textMuted),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => v == null || v.isEmpty ? 'Email required' : !v.contains('@') ? 'Invalid email' : null,
                ).animate().slideX(begin: 0.1, duration: 400.ms, delay: 280.ms).fadeIn(),
                const Gap(14),

                TextFormField(
                  controller: _passwordCtrl,
                  decoration: InputDecoration(
                    labelText: 'Password *',
                    prefixIcon: Icon(Icons.lock_outline, color: context.colors.textMuted),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility, color: context.colors.textMuted),
                      onPressed: () => setState(() => _obscurePass = !_obscurePass),
                    ),
                  ),
                  obscureText: _obscurePass,
                  validator: (v) => v == null || v.length < 8 ? 'Min 8 characters' : null,
                ).animate().slideX(begin: 0.1, duration: 400.ms, delay: 320.ms).fadeIn(),
                const Gap(14),

                TextFormField(
                  controller: _confirmCtrl,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password *',
                    prefixIcon: Icon(Icons.lock_outline, color: context.colors.textMuted),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility, color: context.colors.textMuted),
                      onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  obscureText: _obscureConfirm,
                  validator: (v) => v != _passwordCtrl.text ? 'Passwords do not match' : null,
                ).animate().slideX(begin: 0.1, duration: 400.ms, delay: 360.ms).fadeIn(),
                const Gap(28),

                SizedBox(height: 52, child: ElevatedButton.icon(
                  icon: _isLoading
                      ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.primaryNavy))
                      : const Icon(Icons.how_to_reg_rounded),
                  label: Text(_isLoading ? 'Creating...' : 'Create Officer Account',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  onPressed: _isLoading ? null : _register,
                )).animate().slideY(begin: 0.3, duration: 400.ms, delay: 400.ms).fadeIn(),
              ],
            )),
          ),
        ))),
      ]),
    );
  }
}
