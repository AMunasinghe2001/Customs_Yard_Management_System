import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:gap/gap.dart';
import '../core/theme.dart';
import 'password_strength_field.dart';
import 'dialog_close_button.dart';
import '../core/providers.dart';
import '../core/db_client.dart';
import '../models/models.dart';
import '../services/services.dart';
import 'error_view.dart';
import '../core/security_policy.dart';

/// Profile view + edit dialog for an institutional directorate account
/// (Central Disposal DC/SDDC, Appeal AD/ADD). Opened from the account chip in
/// the dashboard top bar. Lets the holder update their mobile number, profile
/// photo and branch email, and change their password. The full name / role are
/// institutional and read-only here. Pass [accent] to match the directorate's
/// colour (defaults to the disposal green).
class DisposalProfileDialog extends ConsumerStatefulWidget {
  final Color? accent;

  /// The ICT console's flatter shape: a plain header with a rule under it, a
  /// 12px radius, and the account's name on one line.
  ///
  /// ⚠️ Opt-in, and it must stay so — every other portal opens this dialog and
  /// only ICT was redesigned. The same flag, for the same reason, as
  /// [StyledFormDialog.erp]: a gradient header reads as a moment, and an
  /// admin console's dialogs are opened many times a day to do routine work.
  final bool erp;

  const DisposalProfileDialog({super.key, this.accent, this.erp = false});

  @override
  ConsumerState<DisposalProfileDialog> createState() =>
      _DisposalProfileDialogState();
}

class _DisposalProfileDialogState extends ConsumerState<DisposalProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _mobileCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _imageCtrl;
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  bool _editing = false;
  bool _isLoading = false;
  bool _obscureNew = true, _obscureConfirm = true;
  String _originalEmail = '';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(currentProfileProvider);
    _originalEmail = supabase.auth.currentUser?.email ?? '';
    _usernameCtrl = TextEditingController(text: profile?.username ?? '');
    _mobileCtrl = TextEditingController(text: profile?.mobileNumber ?? '');
    _emailCtrl = TextEditingController(text: _originalEmail);
    _imageCtrl = TextEditingController(text: profile?.profileImageUrl ?? '');
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _mobileCtrl.dispose();
    _emailCtrl.dispose();
    _imageCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return 'DC';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  String _friendlyProfileError(Object e) {
    final raw = e.toString().trim();
    final low = raw.toLowerCase();

    // Password reuse / current password
    if (low.contains('current password')) {
      return 'New password cannot be your current password. Please choose a different password.';
    }
    if (low.contains('used this password before') ||
        low.contains('password_history')) {
      return 'You have used this password recently. Please choose a password you have not used before.';
    }

    // Password policy rules
    if (low.contains('at least 12') ||
        low.contains('min length') ||
        low.contains('too short')) {
      return 'Password must be at least 12 characters.';
    }
    if (low.contains('at most 24') ||
        low.contains('max length') ||
        low.contains('too long')) {
      return 'Password must be at most 24 characters.';
    }
    if (low.contains('uppercase')) {
      return 'Password must contain an uppercase letter (A-Z).';
    }
    if (low.contains('lowercase')) {
      return 'Password must contain a lowercase letter (a-z).';
    }
    if (low.contains('number') || low.contains('digit')) {
      return 'Password must contain a number (0-9).';
    }
    if (low.contains('special character') || low.contains('symbol')) {
      return 'Password must contain a special character (@ # % ! & ...).';
    }
    if (low.contains('common') || low.contains('commonly used')) {
      return 'Password contains a commonly used word. Please choose a stronger password.';
    }
    if (low.contains('passwords do not match')) {
      return 'Passwords do not match.';
    }

    // Username taken / unique constraint
    if (low.contains('duplicate') ||
        low.contains('23505') ||
        low.contains('profiles_username_lower_idx') ||
        (low.contains('username') &&
            (low.contains('unique') ||
                low.contains('already exists') ||
                low.contains('taken')))) {
      return 'That username is already taken. Please choose another.';
    }

    // Email errors
    if (low.contains('email') &&
        (low.contains('duplicate') ||
            low.contains('user_already_exists') ||
            low.contains('23505') ||
            low.contains('already in use'))) {
      return 'This email address is already in use by another account.';
    }

    // Permission / Session errors
    if (low.contains('42501') ||
        low.contains('permission denied') ||
        low.contains('only change your own password')) {
      return 'You may only update your own account.';
    }

    // Network / server
    if (low.contains('socketexception') ||
        low.contains('connection refused') ||
        low.contains('network')) {
      return 'Network problem — could not reach the server. Check your connection and try again.';
    }

    // Clean raw message
    var cleaned = raw;
    for (final prefix in [
      'Exception: ',
      'PgQueryException: ',
      'PostgreSQLException: ',
      'AuthApiException: ',
      'AuthException: ',
      'AuthException(null): ',
      'AuthException(invalid_credentials): ',
    ]) {
      if (cleaned.startsWith(prefix)) {
        cleaned = cleaned.substring(prefix.length);
      }
    }
    cleaned = cleaned.replaceFirst(RegExp(r'^Severity\.\w+\s*'), '').trim();
    if (cleaned.startsWith('22023:')) {
      cleaned = cleaned.substring(6).trim();
    }
    return cleaned.isNotEmpty
        ? cleaned
        : 'Failed to update profile. Please check the details and try again.';
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.image, allowMultiple: false);
    if (result != null && result.files.single.path != null) {
      setState(() => _imageCtrl.text = result.files.single.path!);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final profile = ref.read(currentProfileProvider);
    if (profile == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await ref.read(adminServiceProvider).updateProfile(
            profile.id,
            username: _usernameCtrl.text.trim().isEmpty
                ? null
                : _usernameCtrl.text.trim(),
            mobileNumber: _mobileCtrl.text.trim().isEmpty
                ? null
                : _mobileCtrl.text.trim(),
            profileImageUrl:
                _imageCtrl.text.trim().isEmpty ? null : _imageCtrl.text.trim(),
          );

      final newEmail = _emailCtrl.text.trim();
      final emailChanged =
          newEmail.isNotEmpty && newEmail != _originalEmail;
      if (emailChanged) {
        await ref.read(authServiceProvider).changeEmail(newEmail);
      }

      final newPass = _newPassCtrl.text;
      if (newPass.isNotEmpty) {
        await ref.read(authServiceProvider).changePassword(newPass);
      }

      final updated = await ref.read(authServiceProvider).getCurrentProfile();
      if (updated != null) {
        ref.read(currentProfileProvider.notifier).state = updated;
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: widget.accent ?? context.colors.successGreen,
          content: Text(emailChanged
              ? 'Profile updated. Check your new email to confirm the address.'
              : 'Profile updated successfully.'),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = _friendlyProfileError(e);
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final green = widget.accent ?? context.colors.successGreen;
    final profile = ref.watch(currentProfileProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final body = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Green gradient header (matches the dashboard top bar) ──
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: widget.erp ? 18 : 24,
                  vertical: widget.erp ? 14 : 20),
              decoration: widget.erp
                  ? BoxDecoration(
                      color: context.colors.cardDark,
                      border: Border(
                          bottom:
                              BorderSide(color: context.colors.borderColor)),
                    )
                  : BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          green.withOpacity(0.85),
                          green.withOpacity(0.55)
                        ],
                      ),
                    ),
              child: Row(children: [
                // ⚠️ Smaller on the flat header. Without a gradient behind it
                // the photo is the only block of colour up there, and at 64 it
                // took the header over. The big one is the PICKER's, where
                // changing the photo is the point.
                _avatar(profile, widget.erp ? 44 : 64),
                const Gap(16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile?.fullName ?? 'Profile',
                          // ⚠️ One line. A directorate account's name is a job
                          // title — "ICT Directorate (Chief ICT Officer /
                          // System Admin)" — so at 19px it wrapped to two and
                          // pushed the close button onto its own row.
                          maxLines: widget.erp ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: widget.erp
                                  ? context.colors.textPrimary
                                  : Colors.white,
                              fontSize: widget.erp ? 15 : 19,
                              fontWeight: FontWeight.bold)),
                      const Gap(2),
                      Text((profile?.jobRole ?? profile?.role ?? '').toUpperCase(),
                          style: TextStyle(
                              color: widget.erp
                                  ? green
                                  : Colors.white.withOpacity(0.85),
                              fontSize: widget.erp ? 10 : 11,
                              letterSpacing: 1.0,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                // ICT's flat dialog keeps the plain shape; every directorate's
                // gradient header needs the disc to be seen at all.
                DialogCloseButton(prominent: !widget.erp),
              ]),
            ),
            // ── Body ──
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(widget.erp ? 18 : 24),
                child: Form(
                  key: _formKey,
                  child: _editing
                      ? _buildEditForm(context, profile)
                      : _buildView(context, profile),
                ),
              ),
            ),
            // ── Footer ──
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: widget.erp ? 18 : 24,
                  vertical: widget.erp ? 12 : 16),
              decoration: BoxDecoration(
                color: widget.erp
                    ? context.colors.surfaceDark
                    : (isDark ? Colors.black26 : Colors.grey.shade100),
                border:
                    Border(top: BorderSide(color: context.colors.borderColor)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: _editing
                    ? [
                        TextButton(
                          onPressed: _isLoading
                              ? null
                              : () => setState(() {
                                    _editing = false;
                                    _errorMessage = null;
                                  }),
                          child: const Text('Cancel'),
                        ),
                        const Gap(12),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 14)),
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.save_rounded, size: 18),
                          label: const Text('Save Changes',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          onPressed: _isLoading ? null : _save,
                        ),
                      ]
                    : [
                        OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                        const Gap(12),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 14)),
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          label: const Text('Edit Profile',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          onPressed: () => setState(() {
                            _editing = true;
                            _errorMessage = null;
                          }),
                        ),
                      ],
              ),
            ),
          ],
        );

    return Dialog(
      backgroundColor:
          isDark ? context.colors.cardDark : context.colors.scaffoldBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(widget.erp ? 12 : 24),
        side: widget.erp
            ? BorderSide(color: context.colors.borderColor)
            : BorderSide.none,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          // Narrower: this dialog is four read-only rows and a form, and a
          // 520px column of labelled fields is wider than any of them needs.
          maxWidth: widget.erp ? 440 : 520,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: body,
      ),
    );
  }

  // ── Read-only view ──────────────────────────────────────────────────────
  Widget _buildView(BuildContext context, ProfileModel? profile) {
    final daysLeft = profile?.daysUntilPasswordExpiry ?? 0;
    final expiringSoon = profile?.isPasswordExpiringSoon ?? false;
    final expired = profile?.isPasswordExpired ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The USERNAME, not the full name: it is what this account signs in
        // with, so it is the thing the officer needs to be able to read back.
        // "Role" is gone -- the portal the dialog opens from already says
        // which directorate this is, so the row only ever repeated it.
        _infoRow(context, Icons.alternate_email_rounded, 'Username',
            profile?.username?.isNotEmpty == true ? profile!.username! : '—'),
        _infoRow(context, Icons.email_outlined, 'Branch Email', _originalEmail),
        _infoRow(context, Icons.phone_android_rounded, 'Mobile Number',
            profile?.mobileNumber?.isNotEmpty == true
                ? profile!.mobileNumber!
                : '—'),
        _infoRow(
          context,
          expired
              ? Icons.lock_clock_rounded
              : Icons.password_rounded,
          'Password',
          expired
              ? 'Expired — change required'
              : expiringSoon
                  ? 'Expires in $daysLeft day${daysLeft == 1 ? '' : 's'}'
                  : 'Valid · expires in $daysLeft days',
          valueColor: expired
              ? context.colors.dangerRed
              : expiringSoon
                  ? context.colors.warningAmber
                  : null,
        ),
      ],
    );
  }

  // ── Edit form ───────────────────────────────────────────────────────────
  Widget _buildEditForm(BuildContext context, ProfileModel? profile) {
    final green = widget.accent ?? context.colors.successGreen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: context.colors.dangerRed.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: context.colors.dangerRed.withOpacity(0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline_rounded,
                    color: context.colors.dangerRed, size: 20),
                const Gap(10),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: context.colors.dangerRed,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Gap(14),
        ],
        // Avatar picker
        Center(
          child: InkWell(
            borderRadius: BorderRadius.circular(60),
            onTap: _pickImage,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                _avatarFromPath(_imageCtrl.text, profile, 112),
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration:
                      BoxDecoration(color: green, shape: BoxShape.circle),
                  child: const Icon(Icons.camera_alt_rounded,
                      size: 16, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
        if (_imageCtrl.text.isNotEmpty) ...[
          const Gap(6),
          Center(
            child: TextButton.icon(
              onPressed: () => setState(() => _imageCtrl.text = ''),
              icon: Icon(Icons.delete_outline_rounded,
                  size: 16, color: context.colors.dangerRed),
              label: Text('Remove Photo',
                  style:
                      TextStyle(color: context.colors.dangerRed, fontSize: 13)),
            ),
          ),
        ],
        const Gap(16),
        TextFormField(
          controller: _usernameCtrl,
          decoration: InputDecoration(
            labelText: 'Username',
            helperText: 'Used to sign in (email also works)',
            prefixIcon: Icon(Icons.alternate_email_rounded,
                color: context.colors.textMuted),
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
        const Gap(16),
        TextFormField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: 'Branch Email',
            helperText:
                'Changing this emails a confirmation link to the new address',
            prefixIcon:
                Icon(Icons.email_outlined, color: context.colors.textMuted),
          ),
          validator: (v) {
            final t = v?.trim() ?? '';
            if (t.isEmpty) return 'Email required';
            if (!t.contains('@')) return 'Invalid email';
            return null;
          },
        ),
        const Gap(14),
        TextFormField(
          controller: _mobileCtrl,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          decoration: InputDecoration(
            labelText: 'Mobile Number',
            prefixIcon: Icon(Icons.phone_android_rounded,
                color: context.colors.textMuted),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return null;
            if (v.length != 10) return 'Enter exactly 10 digits';
            return null;
          },
        ),
        const Gap(16),
        const Divider(height: 28),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Change Password',
              style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ),
        const Gap(2),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Leave blank to keep your current password',
              style:
                  TextStyle(color: context.colors.textMuted, fontSize: 11)),
        ),
        const Gap(12),
        // ⚠️ ALWAYS in the tree, shown or not — the slot stays and only its
        // CONTENTS change. A bare `if` here added two children above the
        // field on the first keystroke, the field lost focus, and typing
        // stopped until the officer clicked back into the box. A fixed slot
        // also stops the layout jumping under the cursor.
        //
        // Hidden until typing starts because the change is optional here
        // (blank keeps the current password), and unmet rules on an
        // untouched form read as an error blocking an unrelated edit.
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _newPassCtrl.text.isEmpty
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: PasswordRequirements(password: _newPassCtrl.text),
                ),
        ),
        TextFormField(
          controller: _newPassCtrl,
          obscureText: _obscureNew,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'New Password',
            prefixIcon:
                Icon(Icons.lock_outline, color: context.colors.textMuted),
            suffixIcon: IconButton(
              icon: Icon(
                  _obscureNew ? Icons.visibility_off : Icons.visibility,
                  color: context.colors.textMuted),
              onPressed: () => setState(() => _obscureNew = !_obscureNew),
            ),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return null;
            // Blank means "leave the password alone"; a typed one must pass.
                          return PasswordPolicy.violation(v);
            return null;
          },
        ),
        PasswordStrengthBar(password: _newPassCtrl.text),
        const Gap(12),
        TextFormField(
          controller: _confirmPassCtrl,
          obscureText: _obscureConfirm,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Confirm New Password',
            prefixIcon:
                Icon(Icons.lock_outline, color: context.colors.textMuted),
            suffixIcon: IconButton(
              icon: Icon(
                  _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                  color: context.colors.textMuted),
              onPressed: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
          validator: (v) {
            if (_newPassCtrl.text.isEmpty) return null;
            if (v != _newPassCtrl.text) return 'Passwords do not match';
            return null;
          },
        ),
        // Same reasoning: a fixed slot. PasswordMatchBar already shows
        // nothing for an empty confirm box.
        PasswordMatchBar(
            password: _newPassCtrl.text, confirm: _confirmPassCtrl.text),
      ],
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────
  Widget _avatar(ProfileModel? profile, double size) =>
      _avatarFromPath(profile?.profileImageUrl ?? '', profile, size);

  Widget _avatarFromPath(String path, ProfileModel? profile, double size) {
    final green = widget.accent ?? context.colors.successGreen;
    final initials = _initials(profile?.fullName);
    Widget fallback = Center(
      child: Text(initials,
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: size / 3)),
    );
    Widget content = fallback;
    if (path.isNotEmpty) {
      content = path.startsWith('http')
          ? Image.network(path,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback)
          : Image.file(File(path),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback);
    }
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.25),
        border: Border.all(color: green.withOpacity(0.4), width: 2),
      ),
      child: ClipOval(child: content),
    );
  }

  Widget _infoRow(BuildContext context, IconData icon, String label,
      String value,
      {Color? valueColor}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.colors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Row(children: [
        Icon(icon, color: widget.accent ?? context.colors.successGreen, size: 20),
        const Gap(14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              const Gap(3),
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
      ]),
    );
  }
}
