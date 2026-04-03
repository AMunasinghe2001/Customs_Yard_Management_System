import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
  TextEditingController? _nameCtrl;
  TextEditingController? _salaryCtrl;
  TextEditingController? _mobileCtrl;
  TextEditingController? _jobRoleCtrl;
  TextEditingController? _departmentCtrl;
  TextEditingController? _profileImageCtrl;
  bool _isLoading = false;

  void _ensureControllers() {
    if (_nameCtrl != null) return;
    final profile = ref.read(currentProfileProvider);
    _nameCtrl = TextEditingController(text: profile?.fullName ?? '');
    _salaryCtrl = TextEditingController(text: profile?.badgeNumber ?? '');
    _mobileCtrl = TextEditingController(text: profile?.mobileNumber ?? '');
    _jobRoleCtrl = TextEditingController(text: profile?.jobRole ?? '');
    _departmentCtrl = TextEditingController(text: profile?.department ?? '');
    _profileImageCtrl =
        TextEditingController(text: profile?.profileImageUrl ?? '');
  }

  @override
  void initState() {
    super.initState();
    _ensureControllers();
  }

  @override
  void dispose() {
    _nameCtrl?.dispose();
    _salaryCtrl?.dispose();
    _mobileCtrl?.dispose();
    _jobRoleCtrl?.dispose();
    _departmentCtrl?.dispose();
    _profileImageCtrl?.dispose();
    super.dispose();
  }

  Future<void> _saveProfile(BuildContext dialogContext) async {
    if (!_formKey.currentState!.validate()) return;

    final profile = ref.read(currentProfileProvider);
    if (profile == null) return;

    setState(() => _isLoading = true);

    try {
      await ref.read(adminServiceProvider).updateProfile(
            profile.id,
          fullName: _nameCtrl!.text.trim(),
          badgeNumber: _salaryCtrl!.text.trim(),
          mobileNumber:
            _mobileCtrl!.text.trim().isEmpty ? null : _mobileCtrl!.text.trim(),
          jobRole:
            _jobRoleCtrl!.text.trim().isEmpty ? null : _jobRoleCtrl!.text.trim(),
          department: _departmentCtrl!.text.trim().isEmpty
            ? null
            : _departmentCtrl!.text.trim(),
          profileImageUrl: _profileImageCtrl!.text.trim().isEmpty
            ? null
            : _profileImageCtrl!.text.trim(),
          );
      
      // Refresh current profile provider
      final updatedProfile = await ref.read(authServiceProvider).getCurrentProfile();
      if (updatedProfile != null) {
        ref.read(currentProfileProvider.notifier).state = updatedProfile;
      }

      if (mounted && Navigator.of(dialogContext).canPop()) {
        Navigator.of(dialogContext).pop();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Profile updated successfully'),
            backgroundColor: context.colors.successGreen));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to update profile: $e'),
            backgroundColor: context.colors.dangerRed));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return 'U';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  Future<String?> _pickProfileImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;
    return result.files.single.path;
  }

  void _openEditDialog(BuildContext context) {
    _ensureControllers();
    final profile = ref.read(currentProfileProvider);
    _nameCtrl!.text = profile?.fullName ?? '';
    _salaryCtrl!.text = profile?.badgeNumber ?? '';
    _mobileCtrl!.text = profile?.mobileNumber ?? '';
    _jobRoleCtrl!.text = profile?.jobRole ?? '';
    _departmentCtrl!.text = profile?.department ?? '';
    _profileImageCtrl!.text = profile?.profileImageUrl ?? '';

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          title: const Text('Edit Profile'),
          content: Container(
            width: 620,
            constraints: const BoxConstraints(minHeight: 520, maxHeight: 680),
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                      Center(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(60),
                          onTap: () async {
                            final picked = await _pickProfileImage();
                            if (picked != null) {
                              setDlgState(() => _profileImageCtrl!.text = picked);
                            }
                          },
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              Container(
                                height: 96,
                                width: 96,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: context.colors.primaryGold.withOpacity(0.15),
                                  border: Border.all(
                                      color: context.colors.primaryGold
                                          .withOpacity(0.4)),
                                ),
                                child: ClipOval(
                                  child: _profileImageCtrl!.text.isNotEmpty
                                      ? Image.file(
                                          File(_profileImageCtrl!.text),
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Icon(
                                              Icons.person_rounded,
                                              color: context.colors.primaryGold,
                                              size: 36),
                                        )
                                      : Icon(Icons.person_rounded,
                                          color: context.colors.primaryGold,
                                          size: 36),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: context.colors.primaryGold,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.camera_alt_rounded,
                                    size: 14, color: context.colors.primaryNavy),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_profileImageCtrl!.text.isNotEmpty) ...[
                        const Gap(8),
                        TextButton.icon(
                          onPressed: () => setDlgState(() => _profileImageCtrl!.text = ''),
                          icon: Icon(Icons.delete_outline_rounded, 
                            size: 16, color: context.colors.dangerRed),
                          label: Text('Remove Photo', 
                            style: TextStyle(color: context.colors.dangerRed, fontSize: 13)),
                        ),
                      ],
                      const Gap(16),
                      TextFormField(
                        controller: _nameCtrl!,
                        style: TextStyle(color: context.colors.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Full Name *',
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        ),
                        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const Gap(10),
                      TextFormField(
                        controller: _salaryCtrl!,
                        style: TextStyle(color: context.colors.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Salary Number',
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        ),
                      ),
                      const Gap(10),
                      TextFormField(
                        controller: _mobileCtrl!,
                        style: TextStyle(color: context.colors.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Mobile Number',
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        ),
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        validator: (v) {
                          if (v == null || v.isEmpty) return null;
                          if (v.length != 10) {
                            return 'Enter exactly 10 digits';
                          }
                          return null;
                        },
                      ),
                      const Gap(10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _jobRoleCtrl!,
                              style: TextStyle(color: context.colors.textPrimary),
                              decoration: const InputDecoration(
                                labelText: 'Job Role',
                                contentPadding:
                                    EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              ),
                            ),
                          ),
                          const Gap(10),
                          Expanded(
                            child: TextFormField(
                              controller: _departmentCtrl!,
                              style: TextStyle(color: context.colors.textPrimary),
                              decoration: const InputDecoration(
                                labelText: 'Department',
                                contentPadding:
                                    EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Gap(10),
                      TextFormField(
                        initialValue: supabase.auth.currentUser?.email ?? '',
                        readOnly: true,
                        style: TextStyle(color: context.colors.textMuted),
                        decoration: InputDecoration(
                          labelText: 'Email Address',
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          filled: true,
                          fillColor: context.colors.borderColor.withOpacity(0.3),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _isLoading ? null : () => _saveProfile(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.primaryGold,
                foregroundColor: context.colors.primaryNavy,
              ),
              child: _isLoading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.colors.primaryNavy))
                  : const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensureControllers();
    final profile = ref.watch(currentProfileProvider);
    final email = supabase.auth.currentUser?.email ?? '—';

    if (profile == null) {
      return AppShell(
        currentRoute: '/profile',
        child: Scaffold(
          backgroundColor: context.colors.scaffoldBg,
          body: Center(
            child: Text('Profile not available',
                style: TextStyle(color: context.colors.textMuted)),
          ),
        ),
      );
    }

    return AppShell(
      currentRoute: '/profile',
      child: Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Profile',
                          style: Theme.of(context).textTheme.headlineLarge),
                      Text('View your account information and preferences.',
                          style: TextStyle(color: context.colors.textSecondary)),
                    ],
                  ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.1),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.primaryGold,
                      foregroundColor: context.colors.primaryNavy,
                    ),
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Edit Profile',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    onPressed: () => _openEditDialog(context),
                  ).animate().fadeIn(duration: 400.ms).scale(),
                ],
              ),
              const Gap(24),
              _ProfileHeroCard(
                name: profile.fullName,
                role: profile.role,
                email: email,
                badge: profile.badgeNumber,
                mobile: profile.mobileNumber,
                jobRole: profile.jobRole,
                department: profile.department,
                profileImageUrl: profile.profileImageUrl,
                initials: _initials(profile.fullName),
              ).animate().fadeIn(duration: 400.ms, delay: 100.ms).slideY(begin: 0.1),
              const Gap(24),
              _ProfileDetailsCard(
                fullName: profile.fullName,
                badge: profile.badgeNumber,
                email: email,
                role: profile.role,
                isActive: profile.isActive,
                mobile: profile.mobileNumber,
                jobRole: profile.jobRole,
                department: profile.department,
              ).animate().fadeIn(duration: 400.ms, delay: 200.ms).slideY(begin: 0.1),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileHeroCard extends StatelessWidget {
  final String name;
  final String role;
  final String email;
  final String? badge;
  final String? mobile;
  final String? jobRole;
  final String? department;
  final String? profileImageUrl;
  final String initials;

  const _ProfileHeroCard({
    required this.name,
    required this.role,
    required this.email,
    required this.badge,
    required this.mobile,
    required this.jobRole,
    required this.department,
    required this.profileImageUrl,
    required this.initials,
  });

  @override
  Widget build(BuildContext context) {
    final meta = <String>[];
    if (jobRole != null && jobRole!.trim().isNotEmpty) meta.add(jobRole!);
    if (department != null && department!.trim().isNotEmpty) {
      meta.add(department!);
    }

    final hasImage = profileImageUrl != null && profileImageUrl!.isNotEmpty;
    final isRemote = hasImage && profileImageUrl!.startsWith('http');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.colors.borderColor),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            context.colors.customsBlueDark.withOpacity(0.24),
            context.colors.customsBlue.withOpacity(0.18),
            context.colors.primaryNavy.withOpacity(0.08),
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            height: 110,
            width: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.colors.primaryGold.withOpacity(0.2),
              border: Border.all(
                  color: context.colors.primaryGold.withOpacity(0.35),
                  width: 3),
            ),
            child: ClipOval(
              child: hasImage
                  ? (isRemote
                      ? Image.network(
                          profileImageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Center(
                            child: Text(initials,
                                style: TextStyle(
                                    color: context.colors.primaryGold,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 32)),
                          ),
                        )
                      : Image.file(
                          File(profileImageUrl!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Center(
                            child: Text(initials,
                                style: TextStyle(
                                    color: context.colors.primaryGold,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 32)),
                          ),
                        ))
                  : Center(
                      child: Text(initials,
                          style: TextStyle(
                              color: context.colors.primaryGold,
                              fontWeight: FontWeight.w800,
                              fontSize: 32)),
                    ),
            ),
          ),
          const Gap(24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w800)),
                const Gap(8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: context.colors.accentLightBlue.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: context.colors.accentLightBlue.withOpacity(0.4),
                    ),
                  ),
                  child: Text(role.toUpperCase(),
                      style: TextStyle(
                          color: context.colors.accentLightBlue,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileDetailsCard extends StatelessWidget {
  final String fullName;
  final String? badge;
  final String email;
  final String role;
  final bool isActive;
  final String? mobile;
  final String? jobRole;
  final String? department;

  const _ProfileDetailsCard({
    required this.fullName,
    required this.badge,
    required this.email,
    required this.role,
    required this.isActive,
    required this.mobile,
    required this.jobRole,
    required this.department,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor =
        isActive ? context.colors.successGreen : context.colors.dangerRed;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Profile Details',
              style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const Gap(20),
          _InfoRow(
              label: 'Full Name',
              value: fullName,
              icon: Icons.person_outline_rounded),
          _InfoRow(
              label: 'Salary Number',
              value: badge?.isNotEmpty == true ? badge! : '—',
              icon: Icons.badge_outlined),
          _InfoRow(
              label: 'Mobile Number',
              value: mobile?.isNotEmpty == true ? mobile! : '—',
              icon: Icons.phone_android_rounded),
          _InfoRow(
              label: 'Email Address',
              value: email,
              icon: Icons.email_outlined),
          _InfoRow(
              label: 'Role',
              value: role.toUpperCase(),
              icon: Icons.admin_panel_settings_outlined),
          _InfoRow(
              label: 'Job Role',
              value: jobRole?.isNotEmpty == true ? jobRole! : '—',
              icon: Icons.work_outline_rounded),
          _InfoRow(
              label: 'Department',
              value: department?.isNotEmpty == true ? department! : '—',
              icon: Icons.business_rounded),
          _InfoRow(
            label: 'Status',
            value: isActive ? 'ACTIVE' : 'INACTIVE',
            valueColor: statusColor,
            icon: Icons.verified_user_outlined,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final IconData? icon;

  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: context.colors.primaryGold, size: 20),
            const Gap(14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                const Gap(4),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: valueColor ?? context.colors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
