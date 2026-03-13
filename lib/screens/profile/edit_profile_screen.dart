import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../core/supabase_client.dart';
import '../../services/services.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/status_chip.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _salaryCtrl;
  bool _isLoading = false;
  String? _success;
  String? _error;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(currentProfileProvider);
    _nameCtrl = TextEditingController(text: profile?.fullName ?? '');
    _salaryCtrl = TextEditingController(text: profile?.badgeNumber ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _salaryCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final profile = ref.read(currentProfileProvider);
    if (profile == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _success = null;
    });

    try {
      await ref.read(adminServiceProvider).updateProfile(
            profile.id,
            fullName: _nameCtrl.text.trim(),
            badgeNumber: _salaryCtrl.text.trim(),
          );
      
      // Refresh current profile provider
      final updatedProfile = await ref.read(authServiceProvider).getCurrentProfile();
      if (updatedProfile != null) {
        ref.read(currentProfileProvider.notifier).state = updatedProfile;
      }

      setState(() {
        _success = 'Profile updated successfully!';
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to update profile: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider);

    return AppShell(
      currentRoute: '/profile',
      child: Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: Center(
          child: SingleChildScrollView(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 550),
              padding: const EdgeInsets.all(48),
              decoration: BoxDecoration(
                color: context.colors.cardDark,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.colors.borderColor),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 24, offset: const Offset(0, 8))
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: context.colors.primaryGold.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.person_rounded, color: context.colors.primaryGold, size: 32),
                        ),
                        const Gap(20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Edit Profile', style: TextStyle(color: context.colors.textPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
                              const Gap(4),
                              Text('Update your personal details and app preferences.',
                                  style: TextStyle(color: context.colors.textSecondary, fontSize: 14)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Gap(36),

                    if (_success != null) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: context.colors.successGreen.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: context.colors.successGreen.withOpacity(0.4)),
                        ),
                        child: Row(children: [
                          Icon(Icons.check_circle_rounded, color: context.colors.successGreen, size: 20),
                          const Gap(12),
                          Expanded(child: Text(_success!, style: TextStyle(color: context.colors.successGreen, fontSize: 14, fontWeight: FontWeight.w500))),
                        ]),
                      ),
                      const Gap(28),
                    ],

                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: context.colors.dangerRed.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: context.colors.dangerRed.withOpacity(0.4)),
                        ),
                        child: Row(children: [
                          Icon(Icons.error_outline_rounded, color: context.colors.dangerRed, size: 20),
                          const Gap(12),
                          Expanded(child: Text(_error!, style: TextStyle(color: context.colors.dangerRed, fontSize: 14, fontWeight: FontWeight.w500))),
                        ]),
                      ),
                      const Gap(28),
                    ],

                    TextFormField(
                      controller: _nameCtrl,
                      style: TextStyle(color: context.colors.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Full Name *',
                        prefixIcon: Icon(Icons.person_outline_rounded, color: context.colors.textMuted),
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                    ),
                    const Gap(20),

                    TextFormField(
                      controller: _salaryCtrl,
                      style: TextStyle(color: context.colors.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Salary Number',
                        prefixIcon: Icon(Icons.badge_outlined, color: context.colors.textMuted),
                      ),
                    ),
                    const Gap(20),

                    // Make email read-only for now, as updating it requires Supabase email confirmation flows
                    TextFormField(
                      initialValue: supabase.auth.currentUser?.email ?? '',
                      readOnly: true,
                      style: TextStyle(color: context.colors.textMuted),
                      decoration: InputDecoration(
                        labelText: 'Email Address',
                        prefixIcon: Icon(Icons.email_outlined, color: context.colors.textMuted),
                        enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.transparent)),
                        focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.transparent)),
                        filled: true,
                        fillColor: context.colors.borderColor.withOpacity(0.3),
                      ),
                    ),
                    const Gap(12),
                    Text('Email cannot be changed from the profile directly.',
                        style: TextStyle(color: context.colors.textSecondary, fontSize: 13)),
                        
                    const Gap(36),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.colors.primaryGold,
                          foregroundColor: context.colors.primaryNavy,
                        ),
                        onPressed: _isLoading ? null : _saveProfile,
                        child: _isLoading
                            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.primaryNavy))
                            : const Text('Save Changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
