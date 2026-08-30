import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../core/theme.dart';
import '../../core/supabase_client.dart';
import '../../core/providers.dart';
import '../../core/yards.dart';
import '../../models/models.dart';
import '../../services/services.dart';
import '../../widgets/styled_form_dialog.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/empty_state_card.dart';

/// ICT Directorate Portal: Central user provisioning and management for
/// DC / SDDC (Yard Admins) and Yard Officers across all customs yards.
class IctDashboardScreen extends ConsumerStatefulWidget {
  const IctDashboardScreen({super.key});

  @override
  ConsumerState<IctDashboardScreen> createState() => _IctDashboardScreenState();
}

class _IctDashboardScreenState extends ConsumerState<IctDashboardScreen> {
  final _searchCtrl = TextEditingController();
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
    String selectedYard = kDefaultYardCode;
    bool otpSent = false;
    bool dialogLoading = false;
    String? dialogInfo;
    String? dialogError;

    showDialog(
      context: context,
      barrierDismissible: false,
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
                    yard: selectedYard,
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
                    yard: selectedYard,
                  );

              if (ctx.mounted) Navigator.pop(ctx);
              _loadData();

              final emailed = res['emailed'] == true;
              final roleLabel =
                  selectedRole == 'admin' ? 'DC / SDDC (Admin)' : 'Yard Officer';
              final yardLabel = yardByCode(selectedYard).name;

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
                      child: DropdownButtonFormField<String>(
                        value: selectedRole,
                        decoration: const InputDecoration(
                          labelText: 'Account Role *',
                          prefixIcon: Icon(Icons.shield_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'officer',
                            child: Text('Yard Officer'),
                          ),
                          DropdownMenuItem(
                            value: 'admin',
                            child: Text('DC / SDDC (Yard Admin)'),
                          ),
                        ],
                        onChanged: otpSent
                            ? null
                            : (v) => setDialogState(
                                () => selectedRole = v ?? 'officer'),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: selectedYard,
                        decoration: const InputDecoration(
                          labelText: 'Assigned Yard *',
                          prefixIcon: Icon(Icons.warehouse_outlined),
                        ),
                        items: kYards
                            .map((y) => DropdownMenuItem(
                                  value: y.code,
                                  child: Text(y.name,
                                      overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: otpSent
                            ? null
                            : (v) => setDialogState(
                                () => selectedYard = v ?? kDefaultYardCode),
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
    String selectedYard = staff.yard ?? kDefaultYardCode;
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
                    yard: selectedYard,
                    role: selectedRole,
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
                  child: DropdownButtonFormField<String>(
                    value: selectedYard,
                    decoration: const InputDecoration(labelText: 'Yard'),
                    items: kYards
                        .map((y) => DropdownMenuItem(
                              value: y.code,
                              child: Text(y.name,
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) => setDialogState(
                        () => selectedYard = v ?? kDefaultYardCode),
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
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [accent.withOpacity(0.09), context.colors.cardDark],
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
                child: Icon(Icons.terminal_rounded, color: accent, size: 24),
              ),
              const Gap(14),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('ICT Directorate',
                      style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3)),
                  const Gap(8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: accent.withOpacity(0.4)),
                    ),
                    child: Text('User Management & Provisioning',
                        style: TextStyle(
                            color: accent,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700)),
                  ),
                ]),
                const Gap(2),
                Text(
                  'Sri Lanka Customs · Information & Communication Technology Division',
                  style:
                      TextStyle(color: context.colors.textMuted, fontSize: 11.5),
                ),
              ]),
              const Spacer(),

              // User Info Badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: context.colors.cardDark,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: context.colors.borderColor),
                ),
                child: Row(children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: accent.withOpacity(0.2),
                    child: Text(
                      (profile?.fullName.isNotEmpty == true)
                          ? profile!.fullName[0].toUpperCase()
                          : 'I',
                      style: TextStyle(
                          color: accent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Gap(8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(profile?.fullName ?? 'ICT Officer',
                          style: TextStyle(
                              color: context.colors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                      Text('ICT Directorate',
                          style: TextStyle(
                              color: context.colors.textMuted, fontSize: 10)),
                    ],
                  ),
                ]),
              ),
              const Gap(12),

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

              // Sign Out
              IconButton(
                icon: Icon(Icons.logout_rounded,
                    color: context.colors.dangerRed, size: 20),
                tooltip: 'Sign Out',
                onPressed: () async {
                  await supabase.auth.signOut();
                  ref.read(currentProfileProvider.notifier).state = null;
                  if (context.mounted) context.go('/');
                },
              ),
            ]),
          ),

          // ── Body Content ────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
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
                          decoration: InputDecoration(
                            hintText:
                                'Search by Name, Salary No, Email, Username...',
                            prefixIcon: const Icon(Icons.search_rounded, size: 20),
                            suffixIcon: _searchCtrl.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded, size: 18),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      _loadData();
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: context.colors.scaffoldBg,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                  color: context.colors.borderColor),
                            ),
                          ),
                        ),
                      ),
                      const Gap(14),

                      // Yard Filter
                      SizedBox(
                        width: 200,
                        child: DropdownButtonFormField<String>(
                          value: _selectedYard,
                          decoration: InputDecoration(
                            labelText: 'Yard Location',
                            prefixIcon: const Icon(Icons.warehouse_outlined, size: 18),
                            filled: true,
                            fillColor: context.colors.scaffoldBg,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          items: [
                            const DropdownMenuItem(
                                value: 'all', child: Text('All Yards')),
                            ...kYards.map((y) => DropdownMenuItem(
                                  value: y.code,
                                  child: Text(y.name,
                                      overflow: TextOverflow.ellipsis),
                                )),
                          ],
                          onChanged: (v) {
                            setState(() => _selectedYard = v ?? 'all');
                            _loadData();
                          },
                        ),
                      ),
                      const Gap(14),

                      // Role Filter
                      SizedBox(
                        width: 190,
                        child: DropdownButtonFormField<String>(
                          value: _selectedRole,
                          decoration: InputDecoration(
                            labelText: 'Role Filter',
                            prefixIcon: const Icon(Icons.badge_outlined, size: 18),
                            filled: true,
                            fillColor: context.colors.scaffoldBg,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'all', child: Text('All Roles')),
                            DropdownMenuItem(
                                value: 'admin',
                                child: Text('DC / SDDC (Admin)')),
                            DropdownMenuItem(
                                value: 'officer', child: Text('Yard Officer')),
                          ],
                          onChanged: (v) {
                            setState(() => _selectedRole = v ?? 'all');
                            _loadData();
                          },
                        ),
                      ),
                      const Gap(14),

                      // Status Filter
                      SizedBox(
                        width: 150,
                        child: DropdownButtonFormField<String>(
                          value: _selectedStatus,
                          decoration: InputDecoration(
                            labelText: 'Status',
                            prefixIcon:
                                const Icon(Icons.filter_list_rounded, size: 18),
                            filled: true,
                            fillColor: context.colors.scaffoldBg,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'all', child: Text('All Status')),
                            DropdownMenuItem(
                                value: 'active', child: Text('Active')),
                            DropdownMenuItem(
                                value: 'inactive', child: Text('Inactive')),
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
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
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
                                columnSpacing: 16,
                                horizontalMargin: 20,
                                minWidth: 960,
                                headingRowHeight: 46,
                                dataRowHeight: 52,
                                headingTextStyle: TextStyle(
                                  color: context.colors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                ),
                                headingRowColor: MaterialStateProperty.all(
                                    accent.withOpacity(0.08)),
                                columns: const [
                                  DataColumn2(
                                      label: Text('OFFICER NAME'), size: ColumnSize.L),
                                  DataColumn2(
                                      label: Text('USERNAME / SALARY NO'),
                                      size: ColumnSize.M),
                                  DataColumn2(
                                      label: Text('ROLE'), size: ColumnSize.S),
                                  DataColumn2(
                                      label: Text('ASSIGNED YARD'),
                                      size: ColumnSize.M),
                                  DataColumn2(
                                      label: Text('CONTACT'),
                                      size: ColumnSize.M),
                                  DataColumn2(
                                      label: Text('STATUS'), size: ColumnSize.S),
                                  DataColumn2(
                                      label: Text('ACTIONS'),
                                      size: ColumnSize.S,
                                      numeric: true),
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
                                      // Status
                                      DataCell(
                                        StatusChip(
                                          status: staff.isActive
                                              ? 'Active'
                                              : 'Inactive',
                                        ),
                                      ),
                                      // Actions
                                      DataCell(
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            // Edit Button
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.edit_outlined,
                                                  size: 18),
                                              color: context.colors.textSecondary,
                                              tooltip: 'Edit Details',
                                              onPressed: () =>
                                                  _showEditStaffDialog(staff),
                                            ),
                                            // Toggle Status
                                            IconButton(
                                              icon: Icon(
                                                staff.isActive
                                                    ? Icons.block_rounded
                                                    : Icons.check_circle_outline_rounded,
                                                size: 18,
                                                color: staff.isActive
                                                    ? context.colors.dangerRed
                                                    : context.colors.successGreen,
                                              ),
                                              tooltip: staff.isActive
                                                  ? 'Deactivate Account'
                                                  : 'Activate Account',
                                              onPressed: () =>
                                                  _toggleStaffStatus(staff),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              )),
                  ),
                ],
              ),
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
