import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../core/yards.dart';
import '../../core/directorates.dart';
import '../../models/models.dart';
import '../../widgets/styled_form_dialog.dart';
import '../../widgets/empty_table_state.dart';
import '../../widgets/account_cells.dart';
import '../../widgets/styled_dropdown.dart';
import 'ict_ui.dart';
import 'activity_logs_tab.dart';
import 'directorate_access_tab.dart';
import 'system_rates_tab.dart';
import 'yard_directorate_tab.dart';
import '../../widgets/error_view.dart';

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
  /// 0 = Staff Accounts, 1 = Yards & Directorates, 2 = Directorate Access,
  /// 3 = Rates & Taxes,
  /// 3 = Activity Logs.
  ///
  /// A TabController rather than a plain int so the pages can also be SWIPED,
  /// the way every other directorate's tabs work. The rail both drives it and
  /// follows it.
  ///
  /// ⚠️ NO listener on this. A TabController is an `Animation<double>`, so
  /// `addListener` fires on every ANIMATION TICK, not on index changes — and
  /// this one called `setState` on the whole screen. Changing tab rebuilt the
  /// entire console, metric tiles and staff table included, sixty times a
  /// second for the length of the transition. That was the rail's "lag": it
  /// was not animating slowly, it was waiting behind a full rebuild of the
  /// page each frame.
  ///
  /// Nothing needs it. The two things that follow the controller — the rail
  /// and the header's section name — each listen through their own
  /// AnimatedBuilder, so only those few widgets rebuild as it moves.
  late final TabController _tabs = TabController(
      length: 5,
      vsync: this,
      // Slightly quicker than Material's 300ms: the rail is right there, so
      // a console switches modules many times a minute and the transition
      // should be over before it is noticed as a wait.
      animationDuration: const Duration(milliseconds: 240));
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
      // Split "<yard>|<directorate>" from a multi-directorate yard's split
      // entry -- see the Yard Location filter above.
      String? yardArg;
      String? directorateArg;
      if (_selectedYard != 'all') {
        final bar = _selectedYard.indexOf('|');
        if (bar < 0) {
          yardArg = _selectedYard;
        } else {
          yardArg = _selectedYard.substring(0, bar);
          directorateArg = _selectedYard.substring(bar + 1);
        }
      }
      final list = await ref.read(ictServiceProvider).getAllYardStaff(
            yard: yardArg,
            directorate: directorateArg,
            // The query speaks in permission roles; _selectedRole holds a
            // POST. Send the role it carries, then narrow to the exact post
            // below -- DC and SDDC both come back as 'admin'.
            role: _selectedRole == 'all' ? null : kPostRoles[_selectedRole],
            query: _searchCtrl.text.trim(),
            activeOnly: _selectedStatus == 'active'
                ? true
                : (_selectedStatus == 'inactive' ? false : null),
          );
      setState(() {
        // DC and SDDC both come back as 'admin', so the exact post is settled
        // here. An account provisioned before ICT recorded a post has none:
        // fall back to what its role implies, so it is not filtered away.
        _staffList = _selectedRole == 'all'
            ? list
            : list.where((p) {
                final post = p.jobRole?.trim();
                if (post != null && kPostTitles.containsKey(post)) {
                  return post == _selectedRole;
                }
                return kPostRoles[_selectedRole] == p.role;
              }).toList();
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

    // The POST held, a key of kPostTitles. The permission role is derived
    // from it (kPostRoles): DC and SDDC are different posts that share the
    // 'admin' role, so the role alone cannot record which one this is.
    String selectedPost = 'officer';
    // Both start unset: the yard list depends on the directorate, and a
    // pre-filled pair would quietly assign whichever yard happened to be first.
    String? selectedDirectorate;
    String? selectedYard;
    bool otpSent = false;
    bool dialogLoading = false;
    String? dialogInfo;
    String? dialogError;

    showIctDialog(
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
                    role: kPostRoles[selectedPost] ?? 'officer',
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
                    role: kPostRoles[selectedPost] ?? 'officer',
                    jobRole: selectedPost,
                    yard: selectedYard!,
                    directorate: selectedDirectorate,
                  );

              if (ctx.mounted) Navigator.pop(ctx);
              _loadData();

              final emailed = res['emailed'] == true;
              final roleLabel = kPostTitles[selectedPost] ?? 'Officer';
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
            erp: true,
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
                erp: true,
                accentColor: AppTheme.ictCyan,
                title: 'Role & Yard Assignment',
                icon: Icons.admin_panel_settings_outlined,
                children: [
                  Row(children: [
                    Expanded(
                      child: _IctDialogDropdown(
                        label: 'Post *',
                        icon: Icons.shield_outlined,
                        accent: AppTheme.ictCyan,
                        value: selectedPost,
                        options: [
                          for (final e in kPostTitles.entries)
                            StyledDropdownOption(e.key, e.value),
                        ],
                        onChanged: otpSent
                            ? null
                            : (v) => setDialogState(
                                () => selectedPost = v ?? 'officer'),
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
                erp: true,
                accentColor: AppTheme.ictCyan,
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
                erp: true,
                accentColor: AppTheme.ictCyan,
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
    showIctDialog(
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
    // The POST held. An account provisioned before ICT recorded one falls
    // back to whatever its permission role implies.
    String selectedPost = staff.jobRole?.trim().isNotEmpty == true &&
            kPostTitles.containsKey(staff.jobRole!.trim())
        ? staff.jobRole!.trim()
        : (staff.isAdmin ? 'dc' : 'officer');
    String? selectedDirectorate = staff.directorate;
    String? selectedYard = staff.yard;
    bool loading = false;
    String? error;

    showIctDialog(
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
                    role: kPostRoles[selectedPost] ?? 'officer',
                    jobRole: selectedPost,
                    directorate: selectedDirectorate,
                    oldYard: staff.yard,
                    oldPost: staff.jobRole,
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
            erp: true,
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
                  // The same styled dropdown the Add form uses -- this was a
                  // bare DropdownButtonFormField, so the two forms that edit
                  // the same field looked nothing alike.
                  child: _IctDialogDropdown(
                    label: 'Post *',
                    icon: Icons.shield_outlined,
                    accent: AppTheme.ictCyan,
                    value: selectedPost,
                    options: [
                      for (final e in kPostTitles.entries)
                        StyledDropdownOption(e.key, e.value),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => selectedPost = v ?? 'officer'),
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
                erp: true,
                accentColor: AppTheme.ictCyan,
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
      await ref.read(ictServiceProvider).toggleUserStatus(
            staff.id,
            newStatus,
            staffName: staff.fullName,
          );
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
        showErrorSnack(context, e);
      }
    }
  }

  void _showStaffHistory(ProfileModel staff) {
    final accent = AppTheme.ictCyan;
    final yardObj = yardByCode(staff.yard);

    showIctDialog(
      context: context,
      builder: (ctx) {
        return StyledFormDialog(
          label: 'OFFICER HISTORY',
          title: '${staff.fullName} - Activity & Transfers',
          headerAccentColor: accent,
          erp: true,
          icon: Icons.history_rounded,
          width: 580,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Current details overview banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.colors.surfaceDark.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.colors.borderColor),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: accent.withOpacity(0.15),
                      child: Text(
                        staff.fullName.isNotEmpty ? staff.fullName[0].toUpperCase() : '?',
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  staff.fullName,
                                  style: TextStyle(
                                    color: context.colors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              IctStatusPill(
                                label: staff.postShortTitle,
                                color: staff.isAdmin ? context.colors.primaryGold : accent,
                                dot: false,
                                width: 70,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 12,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'Salary/Badge: ${staff.badgeNumber ?? '—'}',
                                style: TextStyle(
                                  color: context.colors.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.location_on_outlined, size: 13, color: context.colors.textMuted),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Current Yard: ${yardObj.name}',
                                    style: TextStyle(
                                      color: context.colors.textSecondary,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IctStatusPill(
                      label: staff.isActive ? 'ACTIVE' : 'INACTIVE',
                      color: staff.isActive ? context.colors.successGreen : context.colors.textMuted,
                      dot: true,
                    ),
                  ],
                ),
              ),
              const Gap(16),
              Row(
                children: [
                  Icon(Icons.timeline_rounded, size: 16, color: accent),
                  const SizedBox(width: 6),
                  Text(
                    'Yard Transfers & Status History',
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const Gap(10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 340),
                child: FutureBuilder<List<AuditLogModel>>(
                  future: ref.read(ictServiceProvider).getStaffHistory(
                    staff.id,
                    username: staff.username,
                    fullName: staff.fullName,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: CircularProgressIndicator(color: accent, strokeWidth: 2),
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Failed to load history: ${snapshot.error}',
                            style: TextStyle(color: context.colors.dangerRed, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }
                    final logs = snapshot.data ?? [];
                    if (logs.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(32),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: context.colors.cardDark.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: context.colors.borderColor),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.history_toggle_off_rounded, size: 36, color: context.colors.textMuted),
                            const SizedBox(height: 8),
                            Text(
                              'No transfer or status change history recorded yet.',
                              style: TextStyle(color: context.colors.textMuted, fontSize: 12.5),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: logs.length,
                      separatorBuilder: (_, __) => const Gap(8),
                      itemBuilder: (context, index) {
                        final log = logs[index];
                        final actionLower = log.action.toLowerCase();

                        IconData itemIcon = Icons.history_rounded;
                        Color itemColor = accent;
                        if (actionLower.contains('transfer')) {
                          itemIcon = Icons.swap_horiz_rounded;
                          itemColor = accent;
                        } else if (actionLower.contains('post') || actionLower.contains('role')) {
                          itemIcon = Icons.badge_outlined;
                          itemColor = accent;
                        } else if (actionLower.contains('activated')) {
                          itemIcon = Icons.check_circle_outline_rounded;
                          itemColor = context.colors.successGreen;
                        } else if (actionLower.contains('deactivated')) {
                          itemIcon = Icons.block_rounded;
                          itemColor = context.colors.dangerRed;
                        } else if (actionLower.contains('created') || log.entityType == 'auth') {
                          itemIcon = Icons.person_add_outlined;
                          itemColor = context.colors.primaryGold;
                        }

                        final formattedDate = DateFormat('yyyy-MM-dd • hh:mm a').format(log.createdAt);

                        // Extract clean details without database trigger artifacts
                        String? cleanDetail;
                        if (log.details != null) {
                          final d = log.details!;
                          final parts = <String>[];
                          if (d['old_yard'] != null && d['new_yard'] != null) {
                            parts.add('Yard: ${d['old_yard']} ➔ ${d['new_yard']}');
                          }
                          if (d['old_post'] != null && d['new_post'] != null) {
                            parts.add('Post: ${d['old_post']} ➔ ${d['new_post']}');
                          }
                          if (parts.isNotEmpty) {
                            cleanDetail = parts.join('  •  ');
                          }
                        }

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: context.colors.cardDark,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: context.colors.borderColor),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                margin: const EdgeInsets.only(top: 2),
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: itemColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(itemIcon, size: 16, color: itemColor),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            log.action,
                                            style: TextStyle(
                                              color: context.colors.textPrimary,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          formattedDate,
                                          style: TextStyle(
                                            color: context.colors.textMuted,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (cleanDetail != null) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        cleanDetail,
                                        style: TextStyle(
                                          color: accent,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                    if (log.userFullName != null && log.userFullName!.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'By: ${log.userFullName}',
                                        style: TextStyle(
                                          color: context.colors.textMuted,
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
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
      // ⚠️ Not the plain scaffold colour. Against a white page the console's
      // white cards had only their hairline borders to lift them off it, and
      // the whole portal read as one flat sheet -- which is what "too white"
      // was. A trace of the portal's own colour in the ground gives every
      // card an edge without putting any colour on the card itself.
      backgroundColor: Color.alphaBlend(
          accent.withOpacity(0.035), context.colors.scaffoldBg),
      // ⚠️ ICT alone is laid out as an ERP console: a permanent left rail and
      // the work to its right. The other portals are single-purpose -- an
      // officer opens one to do one job -- so a top tab strip suits them. ICT
      // is an ADMIN console: four unrelated areas (accounts, the org chart,
      // credentials, the audit trail) that a system admin moves between all
      // day, and a rail keeps all four in view and named at once.
      //
      // The tab CONTROLLER is unchanged, so swiping still works and the four
      // tab bodies are untouched -- only the chrome around them moved.
      body: IctAccent(
        color: accent,
        child: Row(children: [
        _IctSideRail(controller: _tabs, accent: accent),
        Expanded(
          child: Column(
        children: [
          // ── Top Header ──────────────────────────────────────────
          Container(
            // ⚠️ Flat, not the accent gradient the other directorate headers
            // wear. Those headers ARE the page's identity — one screen, one
            // wash. A console header sits above four different modules and is
            // read many times a day, so it stays neutral and lets the module
            // below it carry the colour.
            // ⚠️ kIctTopBarHeight, the same height the rail's brand block is
            // pinned to. They are two widgets either side of the rail's
            // border, so nothing makes them agree on their own — and when
            // they disagreed their two bottom rules sat a few pixels apart,
            // which reads as a notch in the corner where the two meet.
            height: kIctTopBarHeight,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
            decoration: BoxDecoration(
              color: context.colors.cardDark,
              border:
                  Border(bottom: BorderSide(color: context.colors.borderColor)),
            ),
            child: Row(children: [
              // ⚠️ No emblem or portal name here -- the rail carries both, and
              // repeating them wastes the width the header needs for the page
              // title and its actions. An ERP console names the SECTION you
              // are in at the top; the product is named once, on the rail.
              AnimatedBuilder(
                animation: _tabs.animation ?? _tabs,
                builder: (context, _) {
                  final item = _IctSideRail.itemAt(_tabs.index);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // A breadcrumb, not a second copy of the section name:
                      // it says where in the console you are, which is the one
                      // thing the rail cannot show once it scrolls out of the
                      // corner of the eye.
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('Administration',
                            style: TextStyle(
                                color: context.colors.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                        Icon(Icons.chevron_right_rounded,
                            size: 14, color: context.colors.textMuted),
                        Text(item.label,
                            style: TextStyle(
                                color: accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ]),
                      const Gap(3),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(item.icon, color: accent, size: 19),
                        const Gap(9),
                        Text(item.label,
                            style: TextStyle(
                                color: context.colors.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w800)),
                      ]),
                    ],
                  );
                },
              ),
              const Spacer(),

              // ⚠️ The three header controls are one aligned group at one
              // height. They were a rounded-999 pill, a bare IconButton and a
              // themed OutlinedButton — three shapes and three heights, and
              // the tallest of them set how deep the header had to be.
              //
              // Tapping the profile opens the SHARED DisposalProfileDialog:
              // ICT's badge used to be dead, so its officers had no way to
              // reach their own profile or change their password.
              if (profile != null)
                Tooltip(
                  message: 'View profile',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(kIctControlRadius),
                      // ⚠️ A dialog again, not a page.
                      //
                      // The page version broke the console: the rail stayed
                      // visible and clickable but its taps only moved a tab
                      // controller nothing was showing any more, so choosing
                      // another module did nothing and the one back button
                      // was the only way out. A dialog cannot get into that
                      // state -- it owns the screen until it is dismissed,
                      // and dismissing it puts you back where you were.
                      onTap: () => showIctProfileDialog(context, accent),
                      child: Container(
                        height: 40,
                        // ⚠️ Capped, and padded. The account name is a job
                        // title — "ICT Directorate (Chief ICT Officer /
                        // System Admin)" — so at its natural width it filled
                        // the header and sat hard against its own border with
                        // no room on either side. It now ellipsises inside a
                        // box with real padding.
                        constraints: const BoxConstraints(maxWidth: 340),
                        padding: const EdgeInsets.fromLTRB(7, 0, 12, 0),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.08),
                          borderRadius:
                              BorderRadius.circular(kIctControlRadius),
                          border:
                              Border.all(color: accent.withOpacity(0.3)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          CircleAvatar(
                            radius: 13,
                            backgroundColor: accent.withOpacity(0.2),
                            child: Text(
                              profile.fullName.isNotEmpty
                                  ? profile.fullName[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                  color: accent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800),
                            ),
                          ),
                          const Gap(10),
                          Flexible(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(profile.fullName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: context.colors.textPrimary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5)),
                                const Gap(1),
                                Text('System Administrator',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: context.colors.textMuted,
                                        fontSize: 10)),
                              ],
                            ),
                          ),
                          // Amber/red dot while the password is inside its
                          // expiry window — the same quiet nudge the others
                          // show.
                          if (profile.isPasswordExpiringSoon ||
                              profile.isPasswordExpired) ...[
                            const Gap(9),
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
                          Icon(Icons.expand_more_rounded,
                              color: accent.withOpacity(0.8), size: 17),
                        ]),
                      ),
                    ),
                  ),
                ),
              const Gap(8),

              // Theme toggle — a bordered square, so it reads as a control
              // rather than as an icon someone left in the header.
              Tooltip(
                message: 'Toggle theme',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(kIctControlRadius),
                    onTap: () {
                      final isDark =
                          ref.read(themeModeProvider) == ThemeMode.dark;
                      ref.read(themeModeProvider.notifier).state =
                          isDark ? ThemeMode.light : ThemeMode.dark;
                    },
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: context.colors.surfaceDark,
                        borderRadius:
                            BorderRadius.circular(kIctControlRadius),
                        border:
                            Border.all(color: context.colors.borderColor),
                      ),
                      child: Icon(
                        ref.watch(themeModeProvider) == ThemeMode.dark
                            ? Icons.light_mode_rounded
                            : Icons.dark_mode_rounded,
                        color: context.colors.textSecondary,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
              const Gap(8),

              // Sign Out — still the labelled button every other directorate
              // shows, and it still goes through AuthService: ICT once called
              // supabase.auth.signOut() directly and skipped the sign-out
              // bookkeeping (audit log, presence) the others do.
              SizedBox(
                height: 38,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.colors.dangerRed,
                    side: BorderSide(
                        color: context.colors.dangerRed.withOpacity(0.45)),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(kIctControlRadius)),
                  ),
                  icon: const Icon(Icons.logout_rounded, size: 16),
                  label: const Text('Sign Out',
                      style: TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700)),
                  onPressed: () async {
                    await ref.read(authServiceProvider).signOut();
                    ref.read(currentProfileProvider.notifier).state = null;
                    if (context.mounted) context.go('/');
                  },
                ),
              ),
            ]),
          ),

          // ── Body Content ────────────────────────────────────────
          // TabBarView so the two pages can be dragged between, not only
          // tapped. The strip above stays in sync through the controller.
          Expanded(
            child: TabBarView(
              controller: _tabs,
              // ⚠️ Not draggable. On a trackpad a two-finger sideways flick
              // slid the console between modules -- so an officer scrolling a
              // wide table found half of Directorate Access beside half of
              // Yards, with no idea what they had done. A console is navigated
              // from its rail; the pages are not a carousel.
              //
              // The rail's animateTo still runs the slide, so choosing a
              // module is animated -- it is only the DRAG that is gone.
              physics: const NeverScrollableScrollPhysics(),
              // ⚠️ Each module is wrapped by _IctModule, so choosing one from
              // the rail brings the page in rather than snapping it into
              // place. TabBarView's own slide moves both pages together,
              // which on a full-width console reads as the whole window
              // lurching sideways; the arriving page lifting and fading in on
              // its own is what makes it read as a page LOADING.
              children: [
                // 24, matching the Yards & Directorates tab and every other
                // directorate page.
                _IctModule(
                  index: 0,
                  controller: _tabs,
                  child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ⚠️ The same staged entrance Activity Logs plays: the
                  // measures, then the filters, then the rows. Two modules of
                  // one console must not arrive differently — a page that
                  // simply appears, next to one that unfolds, reads as the
                  // one that failed.
                  //
                  // On the SUBTREES rather than on the module, because the
                  // stagger is the point: one fade over the whole page would
                  // put the toolbar and the table on the same beat.
                  // _IctModule still carries the module itself in.
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
                  ]).animate().fadeIn(duration: 300.ms),
                  const Gap(28),

                  // ── Toolbar ───────────────────────────────────
                  // One strip: what you are looking for, how it is narrowed,
                  // and the one thing this screen exists to do. Every control
                  // in it is kIctControlHeight tall.
                  IctToolbar(children: [
                    Expanded(
                      flex: 3,
                      child: IctSearchField(
                        controller: _searchCtrl,
                        accent: accent,
                        hintText: 'Search name, salary no, email or username',
                        onChanged: (_) => _loadData(),
                        onClear: () {
                          _searchCtrl.clear();
                          _loadData();
                        },
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: IctSelect(
                        label: 'Yard',
                        icon: Icons.warehouse_rounded,
                        accent: accent,
                        value: _selectedYard,
                        // Value is a YardFilterOption.value: a bare yard code,
                        // or "<yard>|<directorate>" for one entry of a
                        // multi-directorate yard (e.g. "NNR|CED", shown as
                        // "CED/NNR") -- see _loadData for how it is split.
                        options: [
                          const StyledDropdownOption('all', 'All Yards'),
                          for (final o in ref
                                  .watch(yardFilterOptionsProvider)
                                  .valueOrNull ??
                              [
                                for (final y in kYards)
                                  YardFilterOption(
                                      value: y.code,
                                      label: y.name,
                                      filterYard: y.code)
                              ])
                            StyledDropdownOption(o.value, o.label),
                        ],
                        onChanged: (v) {
                          setState(() => _selectedYard = v ?? 'all');
                          _loadData();
                        },
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: IctSelect(
                        label: 'Role',
                        icon: Icons.badge_rounded,
                        accent: accent,
                        value: _selectedRole,
                        // Posts, not permission roles: DC and SDDC share the
                        // 'admin' role, so filtering by role alone could never
                        // tell them apart and the two had to be one entry.
                        options: [
                          const StyledDropdownOption('all', 'All Roles'),
                          for (final e in kPostTitles.entries)
                            StyledDropdownOption(e.key, e.value),
                        ],
                        onChanged: (v) {
                          setState(() => _selectedRole = v ?? 'all');
                          _loadData();
                        },
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: IctSelect(
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
                    IctPrimaryButton(
                      label: 'Add Officer / DC',
                      icon: Icons.person_add_alt_1_rounded,
                      accent: accent,
                      onPressed: _showAddStaffDialog,
                    ),
                  ]).animate().fadeIn(duration: 300.ms, delay: 120.ms),
                  const Gap(20),

                  // ── Staff table ─────────────────────────
                  // The card names the table and counts it; the heading row
                  // below is only a quiet rule over the columns.
                  IctSectionCard(
                    icon: Icons.groups_2_rounded,
                    title: 'Staff Register',
                    subtitle:
                        'Accounts ICT has provisioned for the yards.',
                    badge: _isLoading
                        ? null
                        : '${_staffList.length} '
                            '${_staffList.length == 1 ? 'account' : 'accounts'}',
                    height: 540,
                    child: _isLoading
                        ? Center(child: CircularProgressIndicator(color: accent))
                        : _error != null
                            // ⚠️ Was captured and never shown: a failed load
                            // fell through to the empty state, so a database
                            // that was down read as "no accounts exist".
                            ? ErrorView(error: _error!, onRetry: _loadData)
                                // ⚠️ The empty state goes in DataTable2's own
                            // `empty` slot, not in place of the table. Swapped
                            // for the table it left the card with no column
                            // headings, so an officer who filtered everything
                            // away lost the very controls that would tell them
                            // what they had filtered ON.
                            : IctTableTheme(
                                child: DataTable2(
                                empty: const EmptyTableState(
                                  icon: Icons.people_outline_rounded,
                                  message: 'No staff accounts found',
                                  subtitle:
                                      'No DC/SDDC or officers match these filters.',
                                ),
                                // ⚠️ No headingTextStyle or headingRowColor
                                // here: IctTableTheme sets both, and a value
                                // passed at the call site would win over it.
                                columnSpacing: 12,
                                horizontalMargin: 16,
                                fixedTopRows: 1,
                                minWidth: 960,
                                headingRowHeight: kIctHeadingHeight,
                                dataRowHeight: kIctRowHeight,
                                columns: [
                                  ictCol('Officer Name', size: ColumnSize.L),
                                  ictCol('Username / Salary No',
                                      size: ColumnSize.M),
                                  ictCol('Role',
                                      size: ColumnSize.S, fixedWidth: 100),
                                  ictCol('Assigned Yard', size: ColumnSize.M),
                                  ictCol('Contact', size: ColumnSize.M),
                                  ictCol('Status',
                                      size: ColumnSize.S,
                                      fixedWidth: kIctPillWidth + 24),
                                  // NOT numeric: that right-aligns the HEADER,
                                  // leaving the word far from the buttons under
                                  // it. The cell aligns its own contents.
                                  ictCol('Actions',
                                      size: ColumnSize.S, fixedWidth: 140),
                                ],
                                rows: _staffList.asMap().entries.map((entry) {
                                  final i = entry.key;
                                  final staff = entry.value;
                                  final yardObj = yardByCode(staff.yard);
                                  final postColor = staff.isAdmin
                                      ? context.colors.primaryGold
                                      : const Color(0xFF5E35B1);
                                  final status =
                                      accountStatusOf(context, staff);
                                  return DataRow2(
                                    color: ictRowColor(context, i),
                                    cells: [
                                      // Name
                                      DataCell(
                                        Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 13,
                                              backgroundColor:
                                                  postColor.withOpacity(0.18),
                                              child: Text(
                                                staff.fullName.isNotEmpty
                                                    ? staff.fullName[0]
                                                        .toUpperCase()
                                                    : '?',
                                                style: TextStyle(
                                                  color: postColor,
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
                                                  color: context
                                                      .colors.textPrimary,
                                                  fontWeight: FontWeight.w700,
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
                                      // Role — the POST held.
                                      DataCell(IctStatusPill(
                                        label: staff.postShortTitle,
                                        color: postColor,
                                        dot: false,
                                        width: 74,
                                      )),
                                      // Assigned Yard
                                      DataCell(
                                        Text(
                                          yardObj.name,
                                          style: TextStyle(
                                            color: context.colors.textPrimary,
                                            fontSize: 12.5,
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
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ),
                                      // Status
                                      DataCell(IctStatusPill(
                                        label: status.label,
                                        color: status.color,
                                        tooltip: status.tooltip,
                                      )),
                                      // Actions — Edit, Toggle Status, History
                                      DataCell(Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          RowActionButtons(
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
                                          ),
                                          const SizedBox(width: 6),
                                          Tooltip(
                                            message: 'View History',
                                            child: Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                onTap: () => _showStaffHistory(staff),
                                                borderRadius: BorderRadius.circular(6),
                                                child: Container(
                                                  padding: const EdgeInsets.all(6),
                                                  decoration: BoxDecoration(
                                                    color: accent.withOpacity(0.1),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(
                                                        color: accent.withOpacity(0.25),
                                                        width: 0.8),
                                                  ),
                                                  child: Icon(Icons.history_rounded,
                                                      size: 15, color: accent),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      )),
                                    ],
                                  );
                                }).toList(),
                              )),
                  ).animate().slideY(begin: 0.05, duration: 400.ms).fadeIn(),
                ],
              ),
            ),
                ),
                _IctModule(
                    index: 1,
                    controller: _tabs,
                    child: YardDirectorateTab(accent: accent)),
                // Reissues a directorate account's sign-in details. Yard
                // staff are absent: they reset their own from the login page.
                _IctModule(
                    index: 2,
                    controller: _tabs,
                    child: DirectorateAccessTab(accent: accent)),
                // The national rates. It scrolls its own body, like the two
                // above it.
                _IctModule(
                    index: 3,
                    controller: _tabs,
                    child: SystemRatesTab(accent: accent)),
                // Every action across every office. The tab scrolls its own
                // table, so unlike the others it is not wrapped in a
                // SingleChildScrollView.
                _IctModule(
                    index: 4,
                    controller: _tabs,
                    child: ActivityLogsTab(accent: accent)),
              ],
            ),
          ),
        ],
          ),
        ),
      ]),
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
    // ⚠️ The tile itself lives in ict_ui.dart so the console has ONE metric
    // tile. This method stays only because four call sites read better with
    // named arguments than with a constructor repeated four times.
    return IctMetricCard(
      label: title,
      value: value,
      caption: subtitle,
      icon: icon,
      color: color,
    );
  }
}

// ── Dialog field helpers ────────────────────────────────────────────────────
//  The Add-Staff and Edit-Staff dialogs ask the same two questions, so the
//  fields live here rather than being written twice. They are plain
//  `DropdownButtonFormField`s to match the other controls in those dialogs —
//  the login/sign-up screens use the styled variant via DirectorateYardPicker.

/// Picks the head-office directorate an account belongs to.
/// Brings a module in when the rail selects it.
///
/// ⚠️ Driven by the controller's ANIMATION, not by a one-shot animation
/// started in initState: a module is built once and then shown and hidden
/// many times, so a play-on-build animation would run only the first time
/// anyone opened it. Reading the controller means every arrival animates,
/// including the way back to a module already visited.
class _IctModule extends StatelessWidget {
  const _IctModule({
    required this.index,
    required this.controller,
    required this.child,
  });

  final int index;
  final TabController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final animation = controller.animation;
    if (animation == null) return child;
    return AnimatedBuilder(
      animation: animation,
      // ⚠️ `child` is passed through, so the module's subtree is NOT rebuilt
      // on each frame -- only the opacity and offset around it are. Rebuilding
      // a page with a data table sixty times a second is what made the rail
      // feel slow in the first place.
      child: child,
      builder: (context, built) {
        // 1 when this module is centred, 0 once it is a full page away.
        final t = (1 - (animation.value - index).abs()).clamp(0.0, 1.0);
        // ⚠️ easeOutCubic and a 5% lift, matching the .slideY(begin: 0.05)
        // every table card in the console plays when its data arrives. The
        // rail used to move a page in with a flat 12px nudge, so choosing a
        // module and turning a page — two ways of asking for new rows —
        // arrived differently, and only one of them looked deliberate.
        final eased = Curves.easeOutCubic.transform(t);
        return Opacity(
          opacity: eased,
          child: FractionalTranslation(
            translation: Offset(0, (1 - eased) * 0.05),
            child: built,
          ),
        );
      },
    );
  }
}

/// One entry on the ICT console's left rail.
class _IctRailItem {
  final String label;
  final String hint;
  final IconData icon;
  const _IctRailItem(this.label, this.hint, this.icon);
}

/// The ICT console's permanent left rail.
///
/// ⚠️ Driven by the SAME [TabController] the body uses, not by its own index.
/// A rail holding a copy of the selection would fall out of step the moment
/// someone swiped the body -- the rail would still point at the old page. It
/// listens to the controller and repaints, so the two can never disagree.
class _IctSideRail extends StatefulWidget {
  final TabController controller;
  final Color accent;
  const _IctSideRail({required this.controller, required this.accent});

  /// The entry at [index], for the header that names the current section.
  static _IctRailItem itemAt(int index) =>
      _items[index.clamp(0, _items.length - 1)];

  static const _items = [
    _IctRailItem('Staff Accounts', 'Officers & DC / SDDC',
        Icons.groups_2_rounded),
    _IctRailItem('Yards & Directorates', 'Offices and their yards',
        Icons.account_tree_rounded),
    _IctRailItem('Directorate Access', 'Reissue sign-in details',
        Icons.vpn_key_rounded),
    // ⚠️ The storage rate and the sale taxes, which used to live in the
    // two portals they billed -- the yard's Admin Panel and Central
    // Disposal's Taxes tab. Neither is a yard or a directorate decision:
    // they are statutory figures that must be the same everywhere, and a
    // rate one office can change under another's feet is not a rate.
    _IctRailItem('Rates & Taxes', 'Storage rate and sale levies',
        Icons.payments_rounded),
    _IctRailItem('Activity Logs', 'Every action, every office',
        Icons.history_rounded),
  ];

  @override
  State<_IctSideRail> createState() => _IctSideRailState();
}

class _IctSideRailState extends State<_IctSideRail> {
  /// ⚠️ ONE hovered index for the WHOLE rail, instead of a bool inside each
  /// row.
  ///
  /// With a bool per row, two rows could light at once — and did. The rail
  /// rebuilds as the tab controller animates, and a MouseRegion that is
  /// rebuilt while the pointer is already inside it never receives the exit
  /// event that would have cleared the row the pointer left behind. So a
  /// quick pass down the rail left a trail of stuck highlights. A single
  /// index cannot represent two rows, so the bug is gone by construction
  /// rather than by trying to catch every missed exit.
  int? _hovered;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final controller = widget.controller;
    return Container(
      width: 258,
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        border:
            Border(right: BorderSide(color: context.colors.borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Brand ──────────────────────────────────────────────────────
          // ⚠️ OUTSIDE the AnimatedBuilder. It used to be inside, so every
          // frame of a tab change re-rasterised the SVG emblem -- sixty times
          // a second, for a picture that never changes. That was the lag: the
          // rail was not animating slowly, it was re-drawing the logo.
          Container(
            // ⚠️ Same height AND same construction as the header on the other
            // side of the rail's border: a box of kIctTopBarHeight that draws
            // its own bottom rule INSIDE that height.
            //
            // It was a SizedBox followed by a Divider, which puts the rule in
            // the pixel AFTER the box while the header's border sits in the
            // last pixel OF it. Equal heights, rules one pixel apart — which
            // is exactly the step you can see where the two meet.
            height: kIctTopBarHeight,
            decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: context.colors.borderColor)),
            ),
            child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accent.withOpacity(0.3)),
                ),
                child: SvgPicture.asset('Sri_Lanka_Customs_logo_tinted.svg',
                    width: 24,
                    height: 24,
                    colorFilter: ColorFilter.mode(accent, BlendMode.srcIn)),
              ),
              const Gap(11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('SL Customs',
                        style: TextStyle(
                            color: context.colors.textPrimary,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800)),
                    Text('ICT Console',
                        style: TextStyle(
                            color: accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ]),
            ),
          ),
          const Gap(12),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
            child: Text('ADMINISTRATION',
                style: TextStyle(
                    color: context.colors.textMuted,
                    fontSize: 9.5,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800)),
          ),

          // ── The four modules ───────────────────────────────────────────
          // Only THIS follows the controller, and only the four cheap rows
          // are rebuilt as it moves. The whole group is one MouseRegion as
          // well: leaving the rail sideways -- out to the page, or off the
          // window -- is the one exit no individual row is guaranteed to see.
          MouseRegion(
            onExit: (_) => setState(() => _hovered = null),
            child: AnimatedBuilder(
              animation: controller.animation ?? controller,
              builder: (context, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _IctSideRail._items.length; i++)
                    _IctRailTile(
                      item: _IctSideRail._items[i],
                      accent: accent,
                      selected: controller.index == i,
                      hovered: _hovered == i,
                      onHover: (on) => setState(() => _hovered = on ? i : null),
                      onTap: () => controller.animateTo(i),
                    ),
                ],
              ),
            ),
          ),
          const Spacer(),
          Divider(height: 1, color: context.colors.borderColor),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
            child: Row(children: [
              Icon(Icons.shield_moon_rounded,
                  size: 14, color: context.colors.textMuted),
              const Gap(8),
              Expanded(
                child: Text('System Administration',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: context.colors.textMuted, fontSize: 11)),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

/// One rail row: the active bar, the icon, the label, and the line of hint
/// text under it.
///
/// ⚠️ Stateless, and it animates NOTHING. Its highlight is told to it by
/// [_IctSideRailState], which holds the one hovered index for the rail — see
/// the note there for why the state cannot live in the row. The
/// AnimatedContainers it used to have ran two implicit animations per row on
/// every rebuild, which on a rail that rebuilds with the tab animation meant
/// eight animations chasing a change that had already happened.
class _IctRailTile extends StatelessWidget {
  final _IctRailItem item;
  final Color accent;
  final bool selected;
  final bool hovered;
  final ValueChanged<bool> onHover;
  final VoidCallback onTap;
  const _IctRailTile({
    required this.item,
    required this.accent,
    required this.selected,
    required this.hovered,
    required this.onHover,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // ⚠️ Hover is deliberately WEAKER than selected, not a different colour of
    // the same strength. Pointing at one row while another was open read as
    // two open rows: both had a filled box, and the fill is what the eye takes
    // for "this is the page you are on". Hover now says only "the pointer is
    // here" — a faint grey wash and brighter text, no accent anywhere, and no
    // bar. The accent fill and the edge bar belong to the open page alone.
    final Color fill;
    if (selected) {
      fill = accent.withOpacity(0.13);
    } else if (hovered) {
      // ⚠️ A tint of the ACCENT, not surfaceDark. surfaceDark is the light
      // theme's near-white, so on this rail the hover state read as a white
      // gap punched in the panel rather than as a row lighting up. A faint
      // wash of the portal's own colour is unmistakably a highlight, and at
      // this strength still clearly below the open page's 0.13.
      fill = accent.withOpacity(0.06);
    } else {
      fill = Colors.transparent;
    }
    final tint = selected
        ? accent
        : (hovered ? context.colors.textPrimary : context.colors.textSecondary);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => onHover(true),
        onExit: (_) => onHover(false),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(kIctControlRadius),
          child: InkWell(
            borderRadius: BorderRadius.circular(kIctControlRadius),
            onTap: onTap,
            // ⚠️ The InkWell's own hover overlay is off. It is a faint wash
            // that barely registers on a rail this dark, and it fades on its
            // own schedule — so on a fast pass it stayed lit under the painted
            // highlight and gave the second stuck row its colour.
            hoverColor: Colors.transparent,
            splashColor: accent.withOpacity(0.12),
            child: Container(
              padding: const EdgeInsets.fromLTRB(0, 9, 12, 9),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(kIctControlRadius),
              ),
              child: Row(children: [
                // The active bar — an ERP rail marks the open module on the
                // rail's own edge, so the eye finds it without reading.
                Container(
                  width: 3,
                  height: 26,
                  margin: const EdgeInsets.only(right: 11),
                  decoration: BoxDecoration(
                    color: selected ? accent : Colors.transparent,
                    borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(3)),
                  ),
                ),
                Icon(item.icon, size: 18, color: tint),
                const Gap(11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(item.label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: tint,
                              fontSize: 12.5,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w600)),
                      const Gap(1),
                      Text(item.hint,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: context.colors.textMuted, fontSize: 10)),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

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
        accentColor: accent,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        prefixIcon: Icon(icon, color: accent, size: 20),
        options: options,
        onChanged: onChanged ?? (_) {},
      ),
    );
  }
}
