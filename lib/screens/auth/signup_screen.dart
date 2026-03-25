import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import '../../core/theme.dart';
import '../../services/services.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});
  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameCtrl = TextEditingController();
  final _badgeCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String _role = 'officer';
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _fullNameCtrl.dispose(); _badgeCtrl.dispose();
    _emailCtrl.dispose(); _passwordCtrl.dispose(); _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _error = null; _success = null; });
    try {
      await ref.read(adminServiceProvider).createOfficer(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        fullName: _fullNameCtrl.text.trim(),
        badgeNumber: _badgeCtrl.text.trim(),
        role: _role,
      );
      setState(() {
        _success = 'Account created successfully for ${_fullNameCtrl.text.trim()}!';
        _formKey.currentState?.reset();
        _fullNameCtrl.clear(); _badgeCtrl.clear();
        _emailCtrl.clear(); _passwordCtrl.clear(); _confirmCtrl.clear();
      });
    } catch (e) {
      setState(() => _error = 'Error: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      body: Row(
        children: [
          // Left branding panel
          Expanded(
            flex: 5,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.primaryNavy, AppTheme.customsBlue, AppTheme.customsBlueLight],
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 140, height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.1),
                      border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: SvgPicture.asset(
                        'Sri_Lanka_Customs_logo.svg',
                        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                      ),
                    ),
                  ).animate().scale(duration: 600.ms).fadeIn(),
                  const Gap(32),
                  const Text(
                    'Sri Lanka Customs',
                    style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 1),
                  ).animate().slideY(begin: 0.5, duration: 500.ms).fadeIn(),
                  const Gap(8),
                  const Text(
                    'Inventory Management System - Grey Line 1',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFFB0BEC5), fontSize: 15, height: 1.2),
                  ).animate().slideY(begin: 0.5, duration: 500.ms, delay: 100.ms).fadeIn(),
                  const Gap(24),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('Admin • Create New Account',
                        style: TextStyle(color: Color(0xFFB0BEC5), fontSize: 13)),
                  ).animate().fadeIn(delay: 300.ms),
                ],
              ),
            ),
          ),

          // Right panel - signup form
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
                            icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textSecondary),
                            onPressed: () => context.go('/'),
                          ),
                          const Gap(8),
                          Text('Create Account', style: Theme.of(context).textTheme.headlineMedium),
                        ]).animate().fadeIn(duration: 400.ms),
                        const Gap(6),
                        const Padding(
                          padding: EdgeInsets.only(left: 48),
                          child: Text('Register a new officer or admin account',
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                        ).animate().fadeIn(delay: 100.ms),
                        const Gap(32),

                        if (_success != null) ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppTheme.successGreen.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.successGreen.withOpacity(0.4)),
                            ),
                            child: Row(children: [
                              const Icon(Icons.check_circle_outline, color: AppTheme.successGreen, size: 18),
                              const Gap(10),
                              Expanded(child: Text(_success!, style: const TextStyle(color: AppTheme.successGreen, fontSize: 13))),
                            ]),
                          ),
                          const Gap(20),
                        ],

                        if (_error != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.dangerRed.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.dangerRed.withOpacity(0.4)),
                            ),
                            child: Row(children: [
                              const Icon(Icons.error_outline, color: AppTheme.dangerRed, size: 18),
                              const Gap(10),
                              Expanded(child: Text(_error!, style: const TextStyle(color: AppTheme.dangerRed, fontSize: 13))),
                            ]),
                          ),
                          const Gap(20),
                        ],

                        Row(children: [
                          Expanded(child: TextFormField(
                            controller: _fullNameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Full Name *',
                              prefixIcon: Icon(Icons.person_outline, color: AppTheme.textMuted),
                            ),
                            validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                          )),
                          const Gap(12),
                          Expanded(child: TextFormField(
                            controller: _badgeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Badge Number',
                              prefixIcon: Icon(Icons.badge_outlined, color: AppTheme.textMuted),
                            ),
                          )),
                        ]).animate().slideX(begin: 0.1, duration: 400.ms, delay: 200.ms).fadeIn(),
                        const Gap(16),

                        TextFormField(
                          controller: _emailCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Email *',
                            prefixIcon: Icon(Icons.email_outlined, color: AppTheme.textMuted),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) => v == null || v.isEmpty ? 'Email required'
                              : !v.contains('@') ? 'Invalid email' : null,
                        ).animate().slideX(begin: 0.1, duration: 400.ms, delay: 250.ms).fadeIn(),
                        const Gap(16),

                        DropdownButtonFormField<String>(
                          value: _role,
                          decoration: const InputDecoration(
                            labelText: 'Role *',
                            prefixIcon: Icon(Icons.admin_panel_settings_outlined, color: AppTheme.textMuted),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'officer', child: Text('Officer')),
                            DropdownMenuItem(value: 'admin', child: Text('Admin')),
                          ],
                          onChanged: (v) => setState(() => _role = v!),
                        ).animate().slideX(begin: 0.1, duration: 400.ms, delay: 300.ms).fadeIn(),
                        const Gap(16),

                        TextFormField(
                          controller: _passwordCtrl,
                          decoration: InputDecoration(
                            labelText: 'Password *',
                            prefixIcon: const Icon(Icons.lock_outline, color: AppTheme.textMuted),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility, color: AppTheme.textMuted),
                              onPressed: () => setState(() => _obscurePass = !_obscurePass),
                            ),
                          ),
                          obscureText: _obscurePass,
                          validator: (v) => v == null || v.length < 8 ? 'Min 8 characters' : null,
                        ).animate().slideX(begin: 0.1, duration: 400.ms, delay: 350.ms).fadeIn(),
                        const Gap(16),

                        TextFormField(
                          controller: _confirmCtrl,
                          decoration: InputDecoration(
                            labelText: 'Confirm Password *',
                            prefixIcon: const Icon(Icons.lock_outline, color: AppTheme.textMuted),
                            suffixIcon: IconButton(
                              icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility, color: AppTheme.textMuted),
                              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                            ),
                          ),
                          obscureText: _obscureConfirm,
                          validator: (v) => v != _passwordCtrl.text ? 'Passwords do not match' : null,
                        ).animate().slideX(begin: 0.1, duration: 400.ms, delay: 400.ms).fadeIn(),
                        const Gap(32),

                        SizedBox(
                          height: 52,
                          child: ElevatedButton.icon(
                            icon: _isLoading
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryNavy))
                                : const Icon(Icons.person_add_rounded),
                            label: Text(_isLoading ? 'Creating Account...' : 'Create Account'),
                            onPressed: _isLoading ? null : _signUp,
                          ),
                        ).animate().slideY(begin: 0.3, duration: 400.ms, delay: 450.ms).fadeIn(),
                        const Gap(16),
                        Center(
                          child: TextButton(
                            onPressed: () => context.go('/'),
                            child: const Text('← Back to Sign In'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
