import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../core/yards.dart';
import '../../core/directorates.dart';
import '../../models/models.dart';
import '../../widgets/styled_form_dialog.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/account_cells.dart';
import '../../widgets/styled_dropdown.dart';
import '../../widgets/disposal_profile_dialog.dart';
import 'yard_directorate_tab.dart';

/// ICT Directorate Portal: Central user provisioning and management for
/// DC / SDDC (Yard Admins) and Yard Officers across all customs yards.
class IctDashboardScreen extends ConsumerStatefulWidget {
  const IctDashboardScreen({super.key});

  @override
  ConsumerState<IctDashboardScreen> createState() => _IctDashboardScreenState();
}

class _IctDashboardScreenState extends ConsumerState<IctDashboardScreen>
    with SingleTickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  /// 0 = Staff Accounts, 1 = Yards & Directorates.
  ///
  /// A TabController rather than a plain int so the pages can also be SWIPED,
  /// the way every other directorate's tabs work. The custom tab strip below
  /// both drives it and follows it.
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(() {
      if (mounted) setState(() {});
    });
  String _selectedYard = 'all';
  String _selectedRole = 'all';
  String _selectedStatus = 'all'; // 'all', 'active', 'inactive'

  List<ProfileModel> _staffList = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final list = await ref.read(ictServiceProvider).getAllYardStaff(
            yard: _selectedYard == 'all' ? null : _selectedYard,
            role: _selectedRole == 'all' ? null : _selectedRole,
            query: _searchCtrl.text.trim(),
            activeOnly: _selectedStatus == 'active'
                ? true
                : (_selectedStatus == 'inactive' ? false : null),
          );
      setState(() {
        _staffList = list;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  void _showAddStaffDialog() {
    final firstC = TextEditingController();
    final lastC = TextEditingController();
    final salaryC = TextEditingController();
    final emailC = TextEditingController();
    final mobileC = TextEditingController();
    final otpC = TextEditingController();

    String selectedRole = 'officer'; // 'admin' or 'officer'
    // Both start unset: the yard list depends on the directorate, and a
    // pre-filled pair would quietly assign whichever yard happened to be first.
    String? selectedDirectorate;
    String? selectedYard;
    bool otpSent = false;
    bool dialogLoading = false;
    String? dialogInfo;
    String? dialogError;

    showDialog(
      context: context,
      // Closes on an outside click, like every other portal's forms. It was
      // `false`, so an ICT officer who opened this by mistake had to hunt for
      // the Cancel button.
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> sendOtp() async {
            final first = firstC.text.trim();
            final last = lastC.text.trim();
            final email = emailC.text.trim();

            if (first.isEmpty || last.isEmpty || email.isEmpty) {
              setDialogState(
                  () => dialogError = 'First Name, Last Name and Email are required.');
              return;
            }
            if (!email.contains('@') || !email.contains('.')) {
              setDialogState(() => dialogError = 'Enter a valid email address.');
              return;
            }
            if (selectedDirectorate == null || selectedYard == null) {
              setDialogState(() => dialogError =
                  'Choose the directorate and the yard this account belongs to.');
              return;
            }

            setDialogState(() {
              dialogLoading = true;
              dialogError = null;
              dialogInfo = null;
            });

            try {
              await ref.read(ictServiceProvider).requestUserOtp(
                    email: email,
                    fullName: '$first $last',
                    mobileNumber: mobileC.text.trim(),
                    badgeNumber: salaryC.text.trim(),
                    role: selectedRole,
                    yard: selectedYard!,
                  );
              setDialogState(() {
                otpSent = true;
                dialogInfo =
                    'Verification OTP sent to $email. Enter the code to create the account.';
              });
            } catch (e) {
              setDialogState(
                  () => dialogError = e.toString().replaceAll('Exception: ', ''));
            } finally {
              setDialogState(() => dialogLoading = false);
            }
          }

          Future<void> verifyAndCreate() async {
            final otp = otpC.text.trim();
            if (otp.isEmpty) {
              setDialogState(() => dialogError = 'Please enter the OTP code.');
              return;
            }

            setDialogState(() {
              dialogLoading = true;
              dialogError = null;
            });

            try {
              final res = await ref.read(ictServiceProvider).verifyAndCreateUser(
                    email: emailC.text.trim(),
                    otp: otp,
                    fullName: '${firstC.text.trim()} ${lastC.text.trim()}',
                    mobileNumber: mobileC.text.trim(),
                    badgeNumber: salaryC.text.trim(),
                    role: selectedRole,
                    yard: selectedYard!,
                    directorate: selectedDirectorate,
                  );

              if (ctx.mounted) Navigator.pop(ctx);
              _loadData();

              final emailed = res['emailed'] == true;
              final roleLabel =
                  selectedRole == 'admin' ? 'DC / SDDC (Admin)' : 'Yard Officer';
              final yardLabel = yardByCode(selectedYard).name;
              final dirLabel = directorateName(selectedDirectorate);

              if (emailed) {
                if (mounted) {
                  _showSuccessCredentialsDialog(
                    context,
                    fullName: '${firstC.text.trim()} ${lastC.text.trim()}',
                    email: emailC.text.trim(),
                    username: res['username']?.toString() ?? '',
                    password: res['password']?.toString() ?? '',
                    role: roleLabel,
                    yard: yardLabel,
                    directorate: dirLabel,
                    emailed: true,
                  );
                }
              } else {
                if (mounted) {
                  _showSuccessCredentialsDialog(
                    context,
                    fullName: '${firstC.text.trim()} ${lastC.text.trim()}',
                    email: emailC.text.trim(),
                    username: res['username']?.toString() ?? '',
                    password: res['password']?.toString() ?? '',
                    role: roleLabel,
                    yard: yardLabel,
                    directorate: dirLabel,
                    emailed: false,
                  );
                }
              }
            } catch (e) {
              setDialogState(
                  () => dialogError = e.toString().replaceAll('Exception: ', ''));
            } finally {
              setDialogState(() => dialogLoading = false);
            }
          }

          Widget banner(String text, Color color, IconData icon) => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withOpacity(0.4)),
                ),
                child: Row(children: [
                  Icon(icon, color: color, size: 18),
                  const Gap(8),
                  Expanded(
                    child: Text(text, style: TextStyle(color: color, fontSize: 13)),
                  ),
                ]),
              );

          return StyledFormDialog(
            label: 'ICT Account Provisioning',
            title: 'Create Yard Staff Account',
            // Without this the header gradient falls back to gold — Central
            // Disposal's colour — on an ICT form.
            headerAccentColor: AppTheme.ictCyan,
            icon: Icons.person_add_alt_1_rounded,
            width: 520,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (dialogInfo != null)
                banner(dialogInfo!, context.colors.successGreen,
                    Icons.check_circle_outline_rounded),
              if (dialogError != null)
                banner(dialogError!, context.colors.dangerRed,
                    Icons.error_outline_rounded),

              StyledFormSection(
                title: 'Role & Yard Assignment',
                icon: Icons.admin_panel_settings_outlined,
                children: [
                  Row(children: [
                    Expanded(
                      child: _IctDialogDropdown(
                        label: 'Account Role *',
                        icon: Icons.shield_outlined,
                        accent: AppTheme.ictCyan,
                        value: selectedRole,
                        options: const [
                          StyledDropdownOption('officer', 'Yard Officer'),
                          StyledDropdownOption(
                              'admin', 'DC / SDDC (Yard Admin)'),
                        ],
                        onChanged: otpSent
                            ? null
                            : (v) => setDialogState(
                                () => selectedRole = v ?? 'officer'),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: _DirectorateField(
                        value: selectedDirectorate,
                        enabled: !otpSent,
                        onChanged: (v) => setDialogState(() {
                          selectedDirectorate = v;
                          // The yard list is about to change; a yard from the
                          // old directorate must not survive the switch.
                          selectedYard = null;
                        }),
                      ),
                    ),
                  ]),
                  const Gap(12),
                  Row(children: [
                    Expanded(
                      child: _YardField(
                        directorate: selectedDirectorate,
                        value: selectedYard,
                        enabled: !otpSent,
                        onChanged: (v) =>
                            setDialogState(() => selectedYard = v),
                      ),
                    ),
                  ]),
                ],
              ),
              const Gap(16),

              StyledFormSection(
                title: 'Personal & Contact Details',
                icon: Icons.badge_outlined,
                children: [
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: firstC,
                        enabled: !otpSent,
                        decoration:
                            const InputDecoration(labelText: 'First Name *'),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: TextField(
                        controller: lastC,
                        enabled: !otpSent,
                        decoration:
                            const InputDecoration(labelText: 'Last Name *'),
                      ),
                    ),
                  ]),
                  const Gap(12),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: salaryC,
                        enabled: !otpSent,
                        decoration: const InputDecoration(
                            labelText: 'Salary / Badge Number'),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: TextField(
                        controller: mobileC,
                        enabled: !otpSent,
                        keyboardType: TextInputType.phone,
                        decoration:
                            const InputDecoration(labelText: 'Mobile Number'),
                      ),
                    ),
                  ]),
                  const Gap(12),
                  TextField(
                    controller: emailC,
                    enabled: !otpSent,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Official Email *',
                      helperText:
                          'Credentials will be sent to this email upon verification',
                    ),
                  ),
                  if (otpSent) ...[
                    const Gap(12),
                    TextField(
                      controller: otpC,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Enter 6-digit OTP Code *',
                        prefixIcon: Icon(Icons.pin_rounded),
                        helperText:
                            'Check email for OTP. Enter code to complete creation.',
                      ),
                    ),
                  ],
                ],
              ),
            ]),
            actions: [
              if (otpSent && !dialogLoading)
                TextButton(
                  onPressed: () => setDialogState(() {
                    otpSent = false;
                    otpC.clear();
                    dialogInfo = null;
                    dialogError = null;
                  }),
                  child: const Text('Back'),
                ),
              TextButton(
                onPressed: dialogLoading ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              StyledDialogPrimaryButton(
                labelText: otpSent ? 'Verify & Create' : 'Send OTP',
                icon: otpSent ? Icons.how_to_reg_rounded : Icons.send_rounded,
                loading: dialogLoading,
                onPressed: otpSent ? verifyAndCreate : sendOtp,
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSuccessCredentialsDialog(
    BuildContext context, {
    required String fullName,
    required String email,
    required String username,
    required String password,
    required String role,
    required String yard,
    required String directorate,
    required bool emailed,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: context.colors.scaffoldBg,
        title: Row(
          children: [
            Icon(
              emailed ? Icons.check_circle_rounded : Icons.info_outline_rounded,
              color: emailed ? context.colors.successGreen : context.colors.warningAmber,
              size: 28,
            ),
            const Gap(10),
            Text(
              emailed ? 'Account Created & Emailed' : 'Account Created (Manual Handover)',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Container(
          width: 460,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.colors.cardDark,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.colors.borderColor),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                emailed
                    ? 'The account credentials have been successfully emailed to $email.'
                    : 'The account was created, but email delivery encountered an issue. Please securely provide these credentials to the officer:',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const Gap(16),
              const Divider(),
              const Gap(10),
              _credRow('Officer Name', fullName),
              _credRow('Assigned Role', role),
              _credRow('Directorate', directorate),
              _credRow('Assigned Yard', yard),
              _credRow('Email Address', email),
              const Gap(10),
              const Divider(),
              const Gap(10),
              _credRow('Username', username, isBold: true, isHighlight: true),
              _credRow('Temporary Password', password, isBold: true, isHighlight: true),
              const Gap(12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.ictCyan.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.ictCyan.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_outline_rounded,
                        color: AppTheme.ictCyan, size: 18),
                    const Gap(8),
                    Expanded(
                      child: Text(
                        'The officer can sign in at Yard Access with either username or email and can customize their password in their profile.',
                        style: TextStyle(
                            color: context.colors.textPrimary, fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.ictCyan,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _credRow(String label, String value,
      {bool isBold = false, bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: context.colors.textSecondary, fontSize: 13)),
          SelectableText(
            value,
            style: TextStyle(
              color: isHighlight
                  ? AppTheme.ictCyan
                  : context.colors.textPrimary,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  void _showEditStaffDialog(ProfileModel staff) {
    final nameC = TextEditingController(text: staff.fullName);
    final unameC = TextEditingController(text: staff.username ?? '');
    final salaryC = TextEditingController(text: staff.badgeNumber ?? '');
    final mobileC = TextEditingController(text: staff.mobileNumber ?? '');
    String selectedRole = staff.role;
    String? selectedDirectorate = staff.directorate;
    String? selectedYard = staff.yard;
    bool loading = false;
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> saveChanges() async {
            if (nameC.text.trim().isEmpty) {
              setDialogState(() => error = 'Full Name is required.');
              return;
            }
            setDialogState(() {
              loading = true;
              error = null;
            });
            try {
              await ref.read(ictServiceProvider).updateUserProfile(
                    staff.id,
                    fullName: nameC.text.trim(),
                    username: unameC.text.trim(),
                    badgeNumber: salaryC.text.trim(),
                    mobileNumber: mobileC.text.trim(),
                    yard: selectedYard ?? staff.yard ?? kDefaultYardCode,
                    role: selectedRole,
                    directorate: selectedDirectorate,
                  );
              if (ctx.mounted) Navigator.pop(ctx);
              _loadData();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: const Text('✅ Officer profile updated successfully'),
                  backgroundColor: context.colors.successGreen,
                ));
              }
            } catch (e) {
              setDialogState(
                  () => error = e.toString().replaceAll('Exception: ', ''));
            } finally {
              setDialogState(() => loading = false);
            }
          }

          return StyledFormDialog(
            label: 'Edit User',
            title: 'Edit Officer Details',
            headerAccentColor: AppTheme.ictCyan,
            icon: Icons.edit_note_rounded,
            width: 480,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (error != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.colors.dangerRed.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: context.colors.dangerRed.withOpacity(0.4)),
                  ),
                  child: Text(error!,
                      style: TextStyle(
                          color: context.colors.dangerRed, fontSize: 13)),
                ),
              TextField(
                controller: nameC,
                decoration: const InputDecoration(labelText: 'Full Name *'),
              ),
              const Gap(12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: unameC,
                    decoration: const InputDecoration(labelText: 'Username'),
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: TextField(
                    controller: salaryC,
                    decoration:
                        const InputDecoration(labelText: 'Salary / Badge No'),
                  ),
                ),
              ]),
              const Gap(12),
              TextField(
                controller: mobileC,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Mobile Number'),
              ),
              const Gap(12),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: selectedRole,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: const [
                      DropdownMenuItem(
                          value: 'officer', child: Text('Yard Officer')),
                      DropdownMenuItem(
                          value: 'admin', child: Text('DC / SDDC (Admin)')),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => selectedRole = v ?? 'officer'),
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: _DirectorateField(
                    value: selectedDirectorate,
                    onChanged: (v) => setDialogState(() {
                      selectedDirectorate = v;
                      selectedYard = null;
                    }),
                  ),
                ),
              ]),
              const Gap(12),
              Row(children: [
                Expanded(
                  child: _YardField(
                    directorate: selectedDirectorate,
                    value: selectedYard,
                    onChanged: (v) => setDialogState(() => selectedYard = v),
                  ),
                ),
              ]),
            ]),
            actions: [
              TextButton(
                onPressed: loading ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              StyledDialogPrimaryButton(
                labelText: 'Save Changes',
                icon: Icons.save_rounded,
                loading: loading,
                onPressed: saveChanges,
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _toggleStaffStatus(ProfileModel staff) async {
    final newStatus = !staff.isActive;
    try {
      await ref.read(ictServiceProvider).toggleUserStatus(staff.id, newStatus);
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(newStatus
              ? '✅ ${staff.fullName} activated'
              : '⚠️ ${staff.fullName} deactivated'),
          backgroundColor: newStatus
              ? context.colors.successGreen
              : context.colors.warningAmber,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: context.colors.dangerRed,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.ictCyan;
    final profile = ref.watch(currentProfileProvider);

    // Compute stats
    final totalAdmins = _staffList.where((s) => s.isAdmin).length;
    final totalOfficers = _staffList.where((s) => s.isOfficer).length;
    final totalActive = _staffList.where((s) => s.isActive).length;
    final yardsCovered =
        _staffList.map((s) => s.yard).where((y) => y != null).toSet().length;

    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      body: Column(
        children: [
          // ── Top Header ──────────────────────────────────────────
          Container(
            // Same padding and wash strength as the other directorate
            // headers (Central Disposal uses 24/16 and 0.08).
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [accent.withOpacity(0.08), context.colors.cardDark],
              ),
              border:
                  Border(bottom: BorderSide(color: context.colors.borderColor)),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withOpacity(0.3)),
                ),
                // The Customs emblem, matching Appeal / Valuation / Central
                // Disposal / Top Management. ICT used a terminal glyph, which
                // made it the one portal that did not look like the others.
                //
                // Flat tint (colorFilter, not currentColor) because at 30px the
                // emblem's inner ship/plane detail renders as a dark blob.
                child: SvgPicture.asset('Sri_Lanka_Customs_logo_tinted.svg',
                    width: 30,
                    height: 30,
                    colorFilter: ColorFilter.mode(accent, BlendMode.srcIn)),
              ),
              const Gap(14),
              // Title + one subtitle line, exactly like the other
              // directorates. The old version added a
              // "User Management & Provisioning" pill that none of them have,
              // and the extra Row is what pushed the filter bar wide enough to
              // overflow.
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('ICT Directorate',
                      style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                  Text(
                    'User provisioning · yards & directorates across all offices',
                    style: TextStyle(
                        color: context.colors.textMuted, fontSize: 12),
                  ),
                ],
              ),
              const Spacer(),

              // Profile pill — identical to the other directorates: tapping it
              // opens the SHARED DisposalProfileDialog. ICT's badge used to be
              // dead, so its officers had no way to reach their own profile or
              // change their password.
              if (profile != null)
                Tooltip(
                  message: 'View profile',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => DisposalProfileDialog(accent: accent),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: accent.withOpacity(0.35)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.verified_user_rounded,
                            color: accent, size: 16),
                        const Gap(8),
                        Text(profile.fullName,
                            style: TextStyle(
                                color: accent,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        // Amber/red dot while the password is inside its expiry
                        // window — the same quiet nudge the others show.
                        if (profile.isPasswordExpiringSoon ||
                            profile.isPasswordExpired) ...[
                          const Gap(8),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: profile.isPasswordExpired
                                  ? context.colors.dangerRed
                                  : context.colors.warningAmber,
                            ),
                          ),
                        ],
                        const Gap(4),
                        Icon(Icons.chevron_right_rounded,
                            color: accent.withOpacity(0.7), size: 16),
                      ]),
                    ),
                  ),
                ),
              const Gap(8),

              // Theme Toggle
              IconButton(
                icon: Icon(
                  ref.watch(themeModeProvider) == ThemeMode.dark
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded,
                  color: context.colors.textSecondary,
                  size: 20,
                ),
                tooltip: 'Toggle Theme',
                onPressed: () {
                  final isDark = ref.read(themeModeProvider) == ThemeMode.dark;
                  ref.read(themeModeProvider.notifier).state =
                      isDark ? ThemeMode.light : ThemeMode.dark;
                },
              ),
              const Gap(6),

              // Sign Out — the labelled OutlinedButton every other directorate
              // uses. ICT had a bare icon, and it called supabase.auth.signOut()
              // directly instead of AuthService, so it skipped the sign-out
              // bookkeeping (audit log, presence) the others do.
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.colors.dangerRed,
                  side: BorderSide(
                      color: context.colors.dangerRed.withOpacity(0.5)),
                ),
                icon: const Icon(Icons.logout_rounded, size: 16),
                label: const Text('Sign Out'),
                onPressed: () async {
                  await ref.read(authServiceProvider).signOut();
                  ref.read(currentProfileProvider.notifier).state = null;
                  if (context.mounted) context.go('/');
                },
              ),
            ]),
          ),

          // ── Tab bar ─────────────────────────────────────────────
          // A real TabBar, not a hand-rolled strip: its indicator is driven by
          // the controller's animation, so it SLIDES with a swipe. The custom
          // version repainted a plain Container and simply snapped.
          Container(
            color: context.colors.cardDark,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
            child: Container(
              decoration: BoxDecoration(
                color: context.colors.surfaceDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.colors.borderColor),
              ),
              child: TabBar(
                controller: _tabs,
                splashFactory: NoSplash.splashFactory,
                overlayColor: WidgetStateProperty.all(Colors.transparent),
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorPadding: const EdgeInsets.all(4),
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: accent.withOpacity(0.5)),
                ),
                labelColor: accent,
                unselectedLabelColor: context.colors.textMuted,
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                tabs: const [
                  Tab(
                      height: 44,
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.groups_rounded, size: 18),
                            Gap(8),
                            Text('Staff Accounts'),
                          ])),
                  Tab(
                      height: 44,
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.account_tree_rounded, size: 18),
                            Gap(8),
                            Text('Yards & Directorates'),
                          ])),
                ],
              ),
            ),
          ),

          // ── Body Content ────────────────────────────────────────
          // TabBarView so the two pages can be dragged between, not only
          // tapped. The strip above stays in sync through the controller.
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                // 24, matching the Yards & Directorates tab and every other
                // directorate page.
                SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // KPI Overview Cards
                  Row(children: [
                    Expanded(
                      child: _buildKpiCard(
                        title: 'DC / SDDC (Admins)',
                        value: '$totalAdmins',
                        subtitle: 'Yard Administrator Accounts',
                        icon: Icons.admin_panel_settings_rounded,
                        color: context.colors.primaryGold,
                      ),
                    ),
                    const Gap(16),
                    Expanded(
                      child: _buildKpiCard(
                        title: 'Yard Officers',
                        value: '$totalOfficers',
                        subtitle: 'Inspection & Yard Staff',
                        icon: Icons.badge_rounded,
                        color: const Color(0xFF5E35B1),
                      ),
                    ),
                    const Gap(16),
                    Expanded(
                      child: _buildKpiCard(
                        title: 'Active Accounts',
                        value: '$totalActive / ${_staffList.length}',
                        subtitle: 'Currently Active Staff',
                        icon: Icons.verified_user_rounded,
                        color: context.colors.successGreen,
                      ),
                    ),
                    const Gap(16),
                    Expanded(
                      child: _buildKpiCard(
                        title: 'Customs Yards Covered',
                        value: '$yardsCovered',
                        subtitle: 'Active Yard Locations',
                        icon: Icons.warehouse_rounded,
                        color: accent,
                      ),
                    ),
                  ]),
                  const Gap(28),

                  // Controls & Action Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.colors.cardDark,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: context.colors.borderColor),
                    ),
                    child: Row(children: [
                      // Search field
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (_) => _loadData(),
                          style: TextStyle(
                              color: context.colors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                          // Matches DisposalSearch: 14px radius, accent prefix
                          // icon, dense 13px text.
                          decoration: InputDecoration(
                            isDense: true,
                            hintText:
                                'Search by Name, Salary No, Email, Username…',
                            hintStyle: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 13),
                            prefixIcon: Icon(Icons.search_rounded,
                                size: 20, color: accent),
                            suffixIcon: _searchCtrl.text.isEmpty
                                ? null
                                : IconButton(
                                    splashRadius: 16,
                                    icon: Icon(Icons.close_rounded,
                                        size: 16,
                                        color: context.colors.textSecondary),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      _loadData();
                                    },
                                  ),
                            filled: true,
                            fillColor: context.colors.cardDark,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                  color: context.colors.borderColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                  color: context.colors.borderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: accent, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                      const Gap(14),

                      // Yard Filter
                      // Flexible, not a fixed width: three fixed dropdowns
                      // plus the search box and the Add button overflowed this
                      // row on a narrower window.
                      Flexible(
                        child: _IctFilter(
                          label: 'Yard Location',
                          icon: Icons.warehouse_rounded,
                          accent: accent,
                          value: _selectedYard,
                          options: [
                            const StyledDropdownOption('all', 'All Yards'),
                            for (final y in kYards)
                              StyledDropdownOption(y.code, y.name),
                          ],
                          onChanged: (v) {
                            setState(() => _selectedYard = v ?? 'all');
                            _loadData();
                          },
                        ),
                      ),
                      const Gap(14),

                      // Role Filter
                      Flexible(
                        child: _IctFilter(
                          label: 'Role Filter',
                          icon: Icons.badge_rounded,
                          accent: accent,
                          value: _selectedRole,
                          options: const [
                            StyledDropdownOption('all', 'All Roles'),
                            StyledDropdownOption('admin', 'DC / SDDC'),
                            StyledDropdownOption('officer', 'Officer'),
                          ],
                          onChanged: (v) {
                            setState(() => _selectedRole = v ?? 'all');
                            _loadData();
                          },
                        ),
                      ),
                      const Gap(14),

                      // Status Filter
                      Flexible(
                        child: _IctFilter(
                          label: 'Status',
                          icon: Icons.filter_alt_rounded,
                          accent: accent,
                          value: _selectedStatus,
                          options: const [
                            StyledDropdownOption('all', 'All Status'),
                            StyledDropdownOption('active', 'Active'),
                            StyledDropdownOption('inactive', 'Inactive'),
                          ],
                          onChanged: (v) {
                            setState(() => _selectedStatus = v ?? 'all');
                            _loadData();
                          },
                        ),
                      ),
                      const Spacer(),

                      // Primary Action: Add Officer
                      ElevatedButton.icon(
                        icon: const Icon(Icons.person_add_alt_1_rounded,
                            color: Colors.white, size: 18),
                        label: const Text('Add Officer / DC',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                        // Central Disposal's action buttons use the theme's
                        // own padding and radius; ICT's custom 20/16 + r10 made
                        // it noticeably chunkier than every other portal.
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _showAddStaffDialog,
                      ),
                    ]),
                  ),
                  const Gap(20),

                  // ── Data Table ──────────────────────────────────────────
                  Container(
                    height: 540,
                    decoration: BoxDecoration(
                      color: context.colors.cardDark,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: context.colors.borderColor),
                    ),
                    // ⚠️ ClipRRect, exactly as Central Disposal's _listCard does
                    // it. Without it the table's own background paints over
                    // the container's rounded corners and they read as square.
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: _isLoading
                        ? Center(
                            child: CircularProgressIndicator(color: accent))
                        : (_staffList.isEmpty
                            ? const Center(
                                child: EmptyStateCard(
                                  icon: Icons.people_outline_rounded,
                                  message: 'No Staff Accounts Found',
                                  subtitle:
                                      'No DC/SDDC or Officers matching the criteria.',
                                ),
                              )
                            : DataTable2(
                                // Same table shell as Central Disposal: 12/16
                                // spacing, a pinned heading row on the tinted
                                // surface colour.
                                columnSpacing: 12,
                                horizontalMargin: 16,
                                fixedTopRows: 1,
                                minWidth: 960,
                                headingRowHeight: 46,
                                dataRowHeight: 52,
                                headingTextStyle: TextStyle(
                                  color: context.colors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                ),
                                headingRowColor: WidgetStateProperty.all(
                                    context.colors.surfaceDark),
                                columns: const [
                                  DataColumn2(
                                      label: Text('Officer Name'), size: ColumnSize.L),
                                  DataColumn2(
                                      label: Text('Username / Salary No'),
                                      size: ColumnSize.M),
                                  DataColumn2(
                                      label: Text('Role'), size: ColumnSize.S),
                                  DataColumn2(
                                      label: Text('Assigned Yard'),
                                      size: ColumnSize.M),
                                  DataColumn2(
                                      label: Text('Contact'),
                                      size: ColumnSize.M),
                                  DataColumn2(
                                      label: Text('Disables In'),
                                      size: ColumnSize.S,
                                      fixedWidth: 110),
                                  DataColumn2(
                                      label: Text('Status'), size: ColumnSize.S),
                                  // NOT numeric: that right-aligns the HEADER,
                                  // leaving the word far from the buttons under
                                  // it. The cell aligns its own contents.
                                  DataColumn2(
                                      label: Text('Actions'),
                                      size: ColumnSize.S,
                                      fixedWidth: 110),
                                ],
                                rows: _staffList.map((staff) {
                                  final yardObj = yardByCode(staff.yard);
                                  return DataRow2(
                                    cells: [
                                      // Name
                                      DataCell(
                                        Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 14,
                                              backgroundColor: staff.isAdmin
                                                  ? context.colors.primaryGold
                                                      .withOpacity(0.18)
                                                  : const Color(0xFF5E35B1)
                                                      .withOpacity(0.18),
                                              child: Text(
                                                staff.fullName.isNotEmpty
                                                    ? staff.fullName[0]
                                                        .toUpperCase()
                                                    : '?',
                                                style: TextStyle(
                                                  color: staff.isAdmin
                                                      ? context.colors.primaryGold
                                                      : const Color(0xFF5E35B1),
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            const Gap(10),
                                            Expanded(
                                              child: Text(
                                                staff.fullName,
                                                style: TextStyle(
                                                  color: context.colors.textPrimary,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Username / Salary No
                                      DataCell(
                                        Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '@${staff.username ?? '—'}',
                                              style: TextStyle(
                                                color: accent,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12,
                                              ),
                                            ),
                                            Text(
                                              'Salary: ${staff.badgeNumber ?? '—'}',
                                              style: TextStyle(
                                                color: context.colors.textMuted,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Role
                                      DataCell(
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: staff.isAdmin
                                                ? context.colors.primaryGold
                                                    .withOpacity(0.15)
                                                : const Color(0xFF5E35B1)
                                                    .withOpacity(0.15),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            border: Border.all(
                                              color: staff.isAdmin
                                                  ? context.colors.primaryGold
                                                      .withOpacity(0.4)
                                                  : const Color(0xFF5E35B1)
                                                      .withOpacity(0.4),
                                            ),
                                          ),
                                          child: Text(
                                            staff.isAdmin ? 'DC / SDDC' : 'OFFICER',
                                            style: TextStyle(
                                              color: staff.isAdmin
                                                  ? context.colors.primaryGold
                                                  : const Color(0xFF5E35B1),
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Assigned Yard
                                      DataCell(
                                        Text(
                                          yardObj.name,
                                          style: TextStyle(
                                            color: context.colors.textPrimary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      // Contact (Mobile)
                                      DataCell(
                                        Text(
                                          staff.mobileNumber?.isNotEmpty == true
                                              ? staff.mobileNumber!
                                              : '—',
                                          style: TextStyle(
                                            color: context.colors.textSecondary,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      // Disables In — the 8-month auto-expiry
                                      // countdown the Admin Panel shows. ICT
                                      // provisions these accounts, so it needs
                                      // to see which are about to lapse.
                                      DataCell(ExpiresInCell(profile: staff)),
                                      // Status — the same green ACTIVE / red
                                      // EXPIRED chip as the Admin Panel, with
                                      // the auto-deactivation date in its
                                      // tooltip.
                                      DataCell(AccountStatusChip(profile: staff)),
                                      // Actions — the shared Edit/Delete pair.
                                      // "Delete" here deactivates rather than
                                      // removes: the account's id is stamped on
                                      // every package it ever registered.
                                      DataCell(RowActionButtons(
                                        accent: accent,
                                        onEdit: () =>
                                            _showEditStaffDialog(staff),
                                        onDelete: () =>
                                            _toggleStaffStatus(staff),
                                        editTooltip: 'Edit Details',
                                        deleteTooltip: staff.isActive
                                            ? 'Deactivate Account'
                                            : 'Activate Account',
                                        deleteIcon: staff.isActive
                                            ? Icons.block_rounded
                                            : Icons.check_circle_outline_rounded,
                                      )),
                                    ],
                                  );
                                }).toList(),
                              )),
                    ),
                  ),
                ],
              ),
            ),
                YardDirectorateTab(accent: accent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const Gap(16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: context.colors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const Gap(4),
              Text(value,
                  style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
              const Gap(2),
              Text(subtitle,
                  style: TextStyle(
                      color: context.colors.textSecondary, fontSize: 10.5),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ]),
    );
  }
}

// ── Dialog field helpers ────────────────────────────────────────────────────
//  The Add-Staff and Edit-Staff dialogs ask the same two questions, so the
//  fields live here rather than being written twice. They are plain
//  `DropdownButtonFormField`s to match the other controls in those dialogs —
//  the login/sign-up screens use the styled variant via DirectorateYardPicker.

/// Picks the head-office directorate an account belongs to.
class _DirectorateField extends ConsumerWidget {
  const _DirectorateField({
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(directoratesProvider);
    return async.when(
      loading: () => const _LoadingField(label: 'Directorate *'),
      error: (_, __) => const _LoadingField(label: 'Directorate (unavailable)'),
      data: (list) {
        final active = list.where((d) => d.isActive).toList();
        return _IctDialogDropdown(
          label: 'Directorate *',
          icon: Icons.account_balance_outlined,
          accent: AppTheme.ictCyan,
          // Guard against a value whose directorate was deactivated: an
          // unmatched value makes the dropdown throw rather than render.
          value: active.any((d) => d.code == value) ? value : null,
          options: [
            for (final d in active)
              StyledDropdownOption(d.code, '${d.srPrefix} — ${d.name}'),
          ],
          onChanged: enabled ? onChanged : null,
        );
      },
    );
  }
}

/// Picks a yard from those belonging to [directorate].
class _YardField extends ConsumerWidget {
  const _YardField({
    required this.directorate,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String? directorate;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(yardsForDirectorateProvider(directorate));
    return async.when(
      loading: () => const _LoadingField(label: 'Assigned Yard *'),
      error: (_, __) => const _LoadingField(label: 'Yard (unavailable)'),
      data: (list) {
        final active = list.where((y) => y.isActive).toList();
        final ready = directorate != null && directorate!.isNotEmpty;
        return _IctDialogDropdown(
          label: 'Assigned Yard *',
          icon: Icons.warehouse_outlined,
          accent: AppTheme.ictCyan,
          value: active.any((y) => y.code == value) ? value : null,
          // Explains an empty list instead of leaving a dead control.
          helperText: !ready
              ? 'Choose a directorate first'
              : active.isEmpty
                  ? 'No yards assigned to this directorate yet'
                  : null,
          options: [
            for (final y in active) StyledDropdownOption(y.code, y.name),
          ],
          onChanged: (enabled && ready) ? onChanged : null,
        );
      },
    );
  }
}

class _LoadingField extends StatelessWidget {
  const _LoadingField({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: const SizedBox(
        height: 20,
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
              width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
    );
  }
}


/// One filter dropdown, styled exactly like Central Disposal's `YardAllFilter`:
/// a [StyledDropdownFormField] (the paged popup) on a tinted fill with a
/// rounded 14px accent border.
///
/// ICT previously used bare `DropdownButtonFormField`s, which is the single
/// biggest reason its filter row looked like a different application.
class _IctFilter extends StatelessWidget {
  const _IctFilter({
    required this.label,
    required this.icon,
    required this.accent,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final String value;
  final List<StyledDropdownOption<String>> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
              filled: true,
              fillColor: accent.withOpacity(0.06),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: accent.withOpacity(0.4))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: accent.withOpacity(0.4))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: accent, width: 1.5)),
            ),
      ),
      child: StyledDropdownFormField<String>(
        value: value,
        label: label,
        helperText: null,
        isDense: true,
        menuWidth: 220,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        prefixIcon: Icon(icon, color: accent, size: 20),
        options: options,
        onChanged: onChanged,
      ),
    );
  }
}


/// A dropdown for the ICT dialogs, styled like every other form field in the
/// app: [StyledDropdownFormField]'s paged popup on a tinted accent fill.
///
/// The dialogs previously used bare `DropdownButtonFormField`s, which opened
/// the plain grey Material menu — the last place in ICT still doing that — and
/// the Account Role one had no `isExpanded`, so its longest item
/// ("DC / SDDC (Yard Admin)") overflowed the row by 49px.
class _IctDialogDropdown extends StatelessWidget {
  const _IctDialogDropdown({
    required this.label,
    required this.icon,
    required this.accent,
    required this.value,
    required this.options,
    required this.onChanged,
    this.helperText,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final String? value;
  final List<StyledDropdownOption<String>> options;
  final ValueChanged<String?>? onChanged;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    final disabled = onChanged == null;
    return Theme(
      data: Theme.of(context).copyWith(
        inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
              filled: true,
              fillColor: disabled
                  ? context.colors.surfaceDark
                  : accent.withOpacity(0.06),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: accent.withOpacity(0.4))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: accent.withOpacity(0.4))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: accent, width: 1.5)),
            ),
      ),
      child: StyledDropdownFormField<String>(
        value: value,
        label: label,
        helperText: helperText,
        isDense: true,
        menuWidth: 260,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        prefixIcon: Icon(icon, color: accent, size: 20),
        options: options,
        onChanged: onChanged ?? (_) {},
      ),
    );
  }
}
