import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import '../../core/theme.dart';
import '../../widgets/password_strength_field.dart';
import '../../core/providers.dart';
import '../../core/db_client.dart';
import '../../core/directorates.dart';
import '../../models/models.dart';
import '../../widgets/styled_form_dialog.dart';
import '../../core/yards.dart';
import '../../core/app_session.dart';
import '../../services/services.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/status_chip.dart';
import '../../core/security_policy.dart';
import '../../widgets/app_dialog.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  TextEditingController? _nameCtrl;
  TextEditingController? _usernameCtrl;
  TextEditingController? _salaryCtrl;
  TextEditingController? _mobileCtrl;
  TextEditingController? _jobRoleCtrl;
  TextEditingController? _profileImageCtrl;
  TextEditingController? _newPasswordCtrl;
  TextEditingController? _confirmPasswordCtrl;
  String _selectedYard = kDefaultYardCode;
  bool _isLoading = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  void _ensureControllers() {
    if (_nameCtrl != null) return;
    final profile = ref.read(currentProfileProvider);
    _nameCtrl = TextEditingController(text: profile?.fullName ?? '');
    _usernameCtrl = TextEditingController(text: profile?.username ?? '');
    _salaryCtrl = TextEditingController(text: profile?.badgeNumber ?? '');
    _mobileCtrl = TextEditingController(text: profile?.mobileNumber ?? '');
    _jobRoleCtrl = TextEditingController(text: profile?.jobRole ?? '');
    _selectedYard = yardByCode(profile?.yard).code;
    _profileImageCtrl =
        TextEditingController(text: profile?.profileImageUrl ?? '');
    _newPasswordCtrl = TextEditingController();
    _confirmPasswordCtrl = TextEditingController();
  }

  @override
  void initState() {
    super.initState();
    _ensureControllers();
  }

  @override
  void dispose() {
    _nameCtrl?.dispose();
    _usernameCtrl?.dispose();
    _salaryCtrl?.dispose();
    _mobileCtrl?.dispose();
    _jobRoleCtrl?.dispose();
    _profileImageCtrl?.dispose();
    _newPasswordCtrl?.dispose();
    _confirmPasswordCtrl?.dispose();
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
          username: _usernameCtrl!.text.trim(),
          badgeNumber: _salaryCtrl!.text.trim(),
          mobileNumber:
            _mobileCtrl!.text.trim().isEmpty ? null : _mobileCtrl!.text.trim(),
          // jobRole and yard are deliberately NOT sent: ICT owns them, the
          // fields are read-only above, and updateProfile skips a null.
          profileImageUrl: _profileImageCtrl!.text.trim().isEmpty
            ? null
            : _profileImageCtrl!.text.trim(),
          );

      // Optional password change
      final newPass = _newPasswordCtrl!.text;
      if (newPass.isNotEmpty) {
        await ref.read(authServiceProvider).changePassword(newPass);
        _newPasswordCtrl!.clear();
        _confirmPasswordCtrl!.clear();
      }

      // Refresh current profile provider
      final updatedProfile = await ref.read(authServiceProvider).getCurrentProfile();
      if (updatedProfile != null) {
        ref.read(currentProfileProvider.notifier).state = updatedProfile;
        // Keep the session's active yard in sync so new records are tagged correctly.
        AppSession.setYard(updatedProfile.yard);
        AppSession.setDirectorate(updatedProfile.directorate);
        // The realtime filter keys off the yard that just changed, so it has
        // to be re-derived here too — otherwise the listener keeps filtering
        // for the OLD yard and the user stops seeing their own new one update.
        AppSession.applyYardFilterToRealtime(updatedProfile.role);
      }

      if (mounted && Navigator.of(dialogContext).canPop()) {
        Navigator.of(dialogContext).pop();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(newPass.isNotEmpty
                ? 'Profile and password updated successfully'
                : 'Profile updated successfully'),
            backgroundColor: context.colors.successGreen));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_friendlyProfileError(e)),
            backgroundColor: context.colors.dangerRed));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyProfileError(Object e) {
    final raw = e.toString().toLowerCase();
    if (raw.contains('duplicate') ||
        raw.contains('23505') ||
        raw.contains('profiles_username_lower_idx') ||
        raw.contains('unique')) {
      return 'That username is already taken. Please choose another.';
    }
    return 'Failed to update profile: $e';
  }

  String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return 'U';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  /// The largest profile photo accepted. The image is stored and shipped with
  /// the profile, so an unbounded pick means an unbounded row.
  static const int _maxProfileImageBytes = 2 * 1024 * 1024; // 2 MB

  /// The image formats accepted. Narrow on purpose: FileType.image lets the
  /// picker offer anything the platform calls an image -- including SVG, which
  /// is a document that can carry script, and formats nothing here can decode.
  /// These three are what the app actually renders.
  static const List<String> _allowedImageExtensions = ['jpg', 'jpeg', 'png'];

  Future<String?> _pickProfileImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedImageExtensions,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final path = result.files.single.path;
    if (path == null) return null;

    // Re-checked here, not just handed to the picker: a picker filter is a
    // convenience the platform may not honour, and a path can arrive by other
    // routes. The extension is what decides.
    final ext = path.split('.').last.toLowerCase();
    if (!_allowedImageExtensions.contains(ext)) {
      if (mounted) {
        context.showError('Only JPG and PNG images are accepted.');
      }
      return null;
    }

    // Checked off the file itself rather than the picker's reported size:
    // that is what actually gets read and stored.
    final length = await File(path).length();
    if (length > _maxProfileImageBytes) {
      if (mounted) {
        final mb = (length / (1024 * 1024)).toStringAsFixed(1);
        context.showError(
            'That photo is ${mb}MB. Please choose one under 2MB.');
      }
      return null;
    }
    return path;
  }

  void _openEditDialog(BuildContext context) {
    _ensureControllers();
    final profile = ref.read(currentProfileProvider);
    _nameCtrl!.text = profile?.fullName ?? '';
    _usernameCtrl!.text = profile?.username ?? '';
    _salaryCtrl!.text = profile?.badgeNumber ?? '';
    _mobileCtrl!.text = profile?.mobileNumber ?? '';
    _jobRoleCtrl!.text = profile?.jobRole ?? '';
    _selectedYard = yardByCode(profile?.yard).code;
    _profileImageCtrl!.text = profile?.profileImageUrl ?? '';
    _newPasswordCtrl!.clear();
    _confirmPasswordCtrl!.clear();
    _obscureNew = true;
    _obscureConfirm = true;

    showAppDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => StyledFormDialog(
          label: 'MY ACCOUNT',
          title: 'Edit Profile',
          icon: Icons.manage_accounts_rounded,
          width: 620,
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
                      StyledFormSection(
                        title: 'Your Details',
                        icon: Icons.person_outline_rounded,
                        children: [
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
                        controller: _usernameCtrl!,
                        style: TextStyle(color: context.colors.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          helperText: 'Used to sign in (email also works)',
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        ),
                        validator: (v) {
                          final t = v?.trim() ?? '';
                          if (t.isEmpty) return null; // optional
                          if (t.length < 3) return 'Min 3 characters';
                          if (t.contains('@')) return 'Username cannot contain @';
                          if (t.contains(' ')) return 'No spaces allowed';
                          return null;
                        },
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
                      // Job Role and Yard are set by ICT when the account is
                      // provisioned -- an officer cannot reassign their own
                      // posting, so they are shown for context, greyed, and
                      // never sent on save.
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _jobRoleCtrl!,
                              readOnly: true,
                              enabled: false,
                              style:
                                  TextStyle(color: context.colors.textPrimary),
                              decoration: const InputDecoration(
                                labelText: 'Job Role',
                                helperText: 'Set by ICT',
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 14),
                              ),
                            ),
                          ),
                          const Gap(10),
                          Expanded(
                            child: TextFormField(
                              initialValue: yardName(_selectedYard),
                              readOnly: true,
                              enabled: false,
                              style:
                                  TextStyle(color: context.colors.textPrimary),
                              decoration: const InputDecoration(
                                labelText: 'Yard',
                                helperText: 'Set by ICT',
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                        ],
                      ),
                      const Gap(14),
                      StyledFormSection(
                        title: 'Change Password',
                        icon: Icons.lock_outline_rounded,
                        children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                            'Leave blank to keep your current password',
                            style: TextStyle(
                                color: context.colors.textMuted, fontSize: 11)),
                      ),
                      const Gap(10),
                      // ⚠️ ALWAYS in the tree, shown or not — the slot
                      // stays and only its CONTENTS change.
                      //
                      // This was a bare `if`, which added two children above
                      // the field on the first keystroke. The field then lost
                      // focus and the officer had to click back into the box
                      // for every following character.
                      //
                      // A fixed slot also keeps the layout from jumping under
                      // the cursor as the checklist appears, which is worth
                      // having on its own.
                      //
                      // Hidden until typing starts because the change is
                      // OPTIONAL here (blank keeps the current password), and
                      // a checklist of unmet rules on an untouched form reads
                      // as an error blocking an unrelated edit.
                      AnimatedSize(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        alignment: Alignment.topCenter,
                        child: _newPasswordCtrl!.text.isEmpty
                            ? const SizedBox(width: double.infinity)
                            : Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: PasswordRequirements(
                                    password: _newPasswordCtrl!.text),
                              ),
                      ),
                      TextFormField(
                        controller: _newPasswordCtrl!,
                        obscureText: _obscureNew,
                        onChanged: (_) => setDlgState(() {}),
                        style: TextStyle(color: context.colors.textPrimary),
                        decoration: InputDecoration(
                          labelText: 'New Password',
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          suffixIcon: IconButton(
                            icon: Icon(
                                _obscureNew
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: context.colors.textMuted),
                            onPressed: () =>
                                setDlgState(() => _obscureNew = !_obscureNew),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return null; // optional
                          // Blank means "leave the password alone"; a typed one must pass.
                          return PasswordPolicy.violation(v);
                          return null;
                        },
                      ),
                      PasswordStrengthBar(password: _newPasswordCtrl!.text),
                      const Gap(10),
                      TextFormField(
                        controller: _confirmPasswordCtrl!,
                        obscureText: _obscureConfirm,
                        onChanged: (_) => setDlgState(() {}),
                        style: TextStyle(color: context.colors.textPrimary),
                        decoration: InputDecoration(
                          labelText: 'Confirm New Password',
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          suffixIcon: IconButton(
                            icon: Icon(
                                _obscureConfirm
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: context.colors.textMuted),
                            onPressed: () => setDlgState(
                                () => _obscureConfirm = !_obscureConfirm),
                          ),
                        ),
                        validator: (v) {
                          if (_newPasswordCtrl!.text.isEmpty) return null;
                          if (v != _newPasswordCtrl!.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                      ),
                      // Same reasoning: a fixed slot, so the fields below
                      // never shift index. PasswordMatchBar already shows
                      // nothing for an empty confirm box.
                      PasswordMatchBar(
                          password: _newPasswordCtrl!.text,
                          confirm: _confirmPasswordCtrl!.text),
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
                  ],
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
                role: profile.postTitle,
                email: email,
                badge: profile.badgeNumber,
                mobile: profile.mobileNumber,
                jobRole: profile.jobRole,
                yard: _yardWithDirectorate(profile),
                profileImageUrl: profile.profileImageUrl,
                initials: _initials(profile.fullName),
              ).animate().fadeIn(duration: 400.ms, delay: 100.ms).slideY(begin: 0.1),
              const Gap(24),
              _ProfileDetailsCard(
                fullName: profile.fullName,
                username: profile.username,
                badge: profile.badgeNumber,
                email: email,
                isActive: profile.isActive,
                mobile: profile.mobileNumber,
                jobRole: profile.jobRole,
                yard: _yardWithDirectorate(profile),
                daysUntilExpiry: profile.daysUntilExpiry,
              ).animate().fadeIn(duration: 400.ms, delay: 200.ms).slideY(begin: 0.1),
            ],
          ),
        ),
      ),
    );
  }
}

/// The yard as it is actually referred to: with the directorate it sits under.
///
/// A yard alone is ambiguous — NNR is both CED and PSD, and the directorate is
/// what puts the prefix on every SR number the officer registers. "Grey Line 1"
/// on its own left that unsaid.
String _yardWithDirectorate(ProfileModel profile) {
  final yard = yardName(profile.yard);
  final dir = profile.directorate;
  if (dir == null || dir.trim().isEmpty) return yard;
  final prefix = directorateSrPrefix(dir);
  return prefix.isEmpty ? yard : '$prefix / $yard';
}

class _ProfileHeroCard extends StatelessWidget {
  final String name;
  final String role;
  final String email;
  final String? badge;
  final String? mobile;
  final String? jobRole;
  final String? yard;
  final String? profileImageUrl;
  final String initials;

  const _ProfileHeroCard({
    required this.name,
    required this.role,
    required this.email,
    required this.badge,
    required this.mobile,
    required this.jobRole,
    required this.yard,
    required this.profileImageUrl,
    required this.initials,
  });

  @override
  Widget build(BuildContext context) {
    final meta = <String>[];
    if (jobRole != null && jobRole!.trim().isNotEmpty) meta.add(jobRole!);
    if (yard != null && yard!.trim().isNotEmpty) {
      meta.add(yard!);
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
                  // The officer's POST, not the raw permission role: there
                  // are no "admins" in this service, and "ADMIN" told the
                  // officer nothing about the job they actually hold.
                  child: Text(role,
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

/// The profile's details, grouped and laid out as a responsive grid.
///
/// This was one column of full-width rows: nine identical bars stacked down
/// the page, every field given the same weight whether it was the officer's
/// name or a yard code, and a lot of empty space to the right of each. Now the
/// fields sit in titled groups -- who the account is, how to reach them, where
/// they are posted -- two to a row on a wide window and one on a narrow one.
class _ProfileDetailsCard extends StatelessWidget {
  final String fullName;
  final String? username;
  final String? badge;
  final String email;
  final bool isActive;
  final String? mobile;
  final String? jobRole;
  final String? yard;

  /// Whole days until the account auto-deactivates, or null for an
  /// institutional directorate account that never expires.
  final int? daysUntilExpiry;

  const _ProfileDetailsCard({
    required this.fullName,
    this.username,
    required this.badge,
    required this.email,
    required this.isActive,
    required this.mobile,
    required this.jobRole,
    required this.yard,
    required this.daysUntilExpiry,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor =
        isActive ? context.colors.successGreen : context.colors.dangerRed;

    // The expiry countdown ICT's staff table shows, brought to the officer's
    // own profile so they can see their account lapsing before it does.
    final (String expiryValue, Color? expiryColor) = switch (daysUntilExpiry) {
      null => ('Never expires', context.colors.textSecondary),
      final d when d < 0 => ('Expired', context.colors.dangerRed),
      final d when d <= 30 => ('$d days', context.colors.warningAmber),
      final d => ('$d days', context.colors.textPrimary),
    };

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
          _Group(
            title: 'Identity',
            icon: Icons.person_outline_rounded,
            fields: [
              _Field('Full Name', fullName, Icons.badge_outlined),
              _Field('Username', username, Icons.alternate_email_rounded),
              _Field('Salary Number', badge, Icons.pin_outlined),
            ],
          ),
          const Gap(22),
          _Group(
            title: 'Contact',
            icon: Icons.contact_mail_outlined,
            fields: [
              _Field('Email Address', email, Icons.email_outlined),
              _Field('Mobile Number', mobile, Icons.phone_android_rounded),
            ],
          ),
          const Gap(22),
          _Group(
            title: 'Posting',
            icon: Icons.work_outline_rounded,
            // Set by ICT when the account is provisioned, so they are shown
            // here but not editable. "Role" is deliberately absent: it named
            // the same thing as Job Role in coarser words.
            subtitle: 'Assigned by ICT',
            fields: [
              _Field('Job Role', jobRole, Icons.work_outline_rounded),
              _Field('Yard', yard, Icons.warehouse_rounded),
            ],
          ),
          const Gap(22),
          _Group(
            title: 'Account',
            icon: Icons.verified_user_outlined,
            fields: [
              _Field(
                'Status',
                isActive ? 'ACTIVE' : 'INACTIVE',
                Icons.verified_user_outlined,
                color: statusColor,
              ),
              _Field(
                'Disables In',
                expiryValue,
                Icons.schedule_rounded,
                color: expiryColor,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One field's label, value and icon. A null or blank [value] renders as a dash.
class _Field {
  final String label;
  final String? value;
  final IconData icon;
  final Color? color;
  const _Field(this.label, this.value, this.icon, {this.color});
}

/// A titled group of fields, two to a row when there is room for two.
class _Group extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? subtitle;
  final List<_Field> fields;

  const _Group({
    required this.title,
    required this.icon,
    required this.fields,
    this.subtitle,
  });

  /// Below this a row of two would squeeze both values to nothing, so the
  /// fields go one per row instead.
  static const double _twoColumnMinWidth = 620;
  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: context.colors.primaryGold),
            const Gap(8),
            Text(title.toUpperCase(),
                style: TextStyle(
                    color: context.colors.primaryGold,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1)),
            const Gap(10),
            // A hairline carrying the eye across to the group's note, so the
            // groups read as bands rather than as more stacked boxes.
            Expanded(
              child: Container(
                  height: 1, color: context.colors.borderColor),
            ),
            if (subtitle != null) ...[
              const Gap(10),
              Text(subtitle!,
                  style: TextStyle(
                      color: context.colors.textMuted,
                      fontSize: 10.5,
                      fontStyle: FontStyle.italic)),
            ],
          ],
        ),
        const Gap(12),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoUp = constraints.maxWidth >= _twoColumnMinWidth;
            final cellWidth = twoUp
                ? (constraints.maxWidth - _gap) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: _gap,
              runSpacing: _gap,
              children: [
                for (final f in fields)
                  SizedBox(
                    width: cellWidth,
                    child: _InfoRow(
                      label: f.label,
                      value: f.value?.trim().isNotEmpty == true
                          ? f.value!
                          : '—',
                      valueColor: f.color,
                      icon: f.icon,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
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
