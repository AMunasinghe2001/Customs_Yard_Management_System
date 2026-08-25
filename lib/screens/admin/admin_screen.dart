import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase_client.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../core/yards.dart';
import '../../services/services.dart';
import '../../models/models.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/error_view.dart';
import '../../widgets/styled_dropdown.dart';
import '../../widgets/styled_form_dialog.dart';
import '../../widgets/table_pager.dart';
import '../../widgets/empty_table_state.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../widgets/tooltip_text.dart';

class AdminScreen extends ConsumerWidget {
  final int initialIndex;
  const AdminScreen({super.key, this.initialIndex = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppShell(
      currentRoute: '/admin/panel',
      child: DefaultTabController(
        length: 5,
        initialIndex: initialIndex,
        child: Scaffold(
          backgroundColor: context.colors.scaffoldBg,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Admin Panel',
                            style: Theme.of(context).textTheme.headlineLarge),
                        Text('Manage officers and system configuration',
                            style:
                                TextStyle(color: context.colors.textSecondary)),
                      ],
                    ).animate().fadeIn(),
                    const Gap(20),
                    Container(
                      height: 56,
                      decoration: BoxDecoration(
                        color: context.colors.surfaceDark,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: context.colors.borderColor),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: TabBar(
                          indicatorSize: TabBarIndicatorSize.tab,
                          indicatorPadding: const EdgeInsets.all(2),
                          indicator: BoxDecoration(
                            color: context.colors.primaryGold.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: context.colors.primaryGold
                                    .withOpacity(0.5)),
                          ),
                          splashBorderRadius: BorderRadius.circular(12),
                          overlayColor:
                              WidgetStateProperty.resolveWith<Color?>((states) {
                            if (states.contains(WidgetState.hovered))
                              return Colors.grey.withOpacity(0.1);
                            if (states.contains(WidgetState.focused))
                              return Colors.grey.withOpacity(0.1);
                            return Colors.transparent;
                          }),
                          splashFactory: NoSplash.splashFactory,
                          labelColor: context.colors.primaryGold,
                          unselectedLabelColor: context.colors.textMuted,
                          dividerColor: Colors.transparent,
                          tabs: const [
                            Tab(
                                icon: Icon(Icons.people_rounded, size: 20),
                                text: 'Officers'),
                            Tab(
                                icon: Icon(Icons.warehouse_rounded, size: 20),
                                text: 'Warehouses'),
                            Tab(
                                icon: Icon(Icons.category_rounded, size: 20),
                                text: 'Items'),
                            Tab(
                                icon: Icon(Icons.payments_rounded, size: 20),
                                text: 'Storage Charges'),
                            Tab(
                                icon: Icon(Icons.history_toggle_off_rounded,
                                    size: 20),
                                text: 'Logs'),
                          ],
                        ),
                      ),
                    )
                        .animate()
                        .slideY(begin: 0.1, duration: 400.ms, delay: 100.ms)
                        .fadeIn(),
                  ],
                ),
              ),
              const Gap(4),
              const Expanded(
                  child: TabBarView(children: [
                _OfficersTab(),
                _WarehousesTab(),
                _CategoriesTab(),
                _StorageChargesTab(),
                _LogsTab()
              ])),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Officers Tab ───────────────────────────────────────────────

class _OfficersTab extends ConsumerStatefulWidget {
  const _OfficersTab();
  @override
  ConsumerState<_OfficersTab> createState() => _OfficersTabState();
}

class _OfficersTabState extends ConsumerState<_OfficersTab> {
  int _page = 0;
  // null = All, true = Active, false = Inactive/Expired
  bool? _statusFilter;

  @override
  Widget build(BuildContext context) {
    // Admins manage only their own yard's staff. [myYardProfilesProvider]
    // filters to the current admin's yard and drops the head-office Appeal /
    // Disposal directorate accounts.
    final profiles = ref.watch(myYardProfilesProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Officers & Admins',
              style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700)),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colors.primaryGold,
              foregroundColor: context.colors.primaryNavy,
            ),
            icon: const Icon(Icons.person_add_rounded, size: 18),
            label: const Text('Add Officer',
                style: TextStyle(fontWeight: FontWeight.w600)),
            onPressed: () => _showCreateOfficerDialog(context, ref),
          ),
        ]),
        const Gap(12),
        // ── Status filter chips ──────────────────────────────────
        Row(children: [
          _statusChip('All', null),
          const Gap(8),
          _statusChip('Active', true),
          const Gap(8),
          _statusChip('Inactive', false),
        ]),
        const Gap(12),
        Expanded(
          child: profiles.when(
            // Keep the table visible while the realtime/heartbeat refresh
            // re-fetches in the background (prevents the periodic flicker).
            skipLoadingOnReload: true,
            loading: () => Center(
                child: CircularProgressIndicator(
                    color: context.colors.primaryGold)),
            error: (e, _) => ErrorView(
                error: e, onRetry: () => ref.refresh(myYardProfilesProvider)),
            data: (list) {
              // Apply status filter (copy so the sort below doesn't mutate the
              // provider's cached list).
              final filtered = [
                ...(_statusFilter == null
                    ? list
                    : list.where((p) {
                        final isActive = p.isActive && !p.isExpired;
                        return _statusFilter! ? isActive : !isActive;
                      }))
              ];
              // Fewest days-until-disable first (most urgent on top); accounts
              // that never auto-expire (directorate) sink to the bottom.
              filtered.sort((a, b) {
                final da = a.daysUntilExpiry;
                final db = b.daysUntilExpiry;
                if (da == null && db == null) return 0;
                if (da == null) return 1;
                if (db == null) return -1;
                return da.compareTo(db);
              });
              final pageItems = pageSlice(filtered, _page, kClientPageSize);
              return Column(children: [
                Expanded(
                    child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                      color: context.colors.cardDark,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: context.colors.borderColor)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: DataTable2(
                      horizontalMargin: 24,
                      columnSpacing: 20,
                      fixedTopRows: 1,
                      empty: const EmptyTableState(
                          icon: Icons.people_outline_rounded,
                          message: 'No officers yet',
                          subtitle: 'Add an officer to your yard from here.'),
                      isHorizontalScrollBarVisible: false,
                      dataRowColor: WidgetStateProperty.all(Colors.transparent),
                      headingRowColor:
                          WidgetStateProperty.all(context.colors.surfaceDark),
                      columns: [
                        DataColumn2(
                            label: Text('Name',
                                style: TextStyle(
                                    color: context.colors.primaryGold,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                            size: ColumnSize.L),
                        DataColumn2(
                            label: Text('Salary No',
                                style: TextStyle(
                                    color: context.colors.primaryGold,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                            size: ColumnSize.M),
                        DataColumn2(
                            label: Text('Role',
                                style: TextStyle(
                                    color: context.colors.primaryGold,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                            size: ColumnSize.S,
                            fixedWidth: 100),
                        DataColumn2(
                            label: Text('Disables In',
                                style: TextStyle(
                                    color: context.colors.primaryGold,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                            size: ColumnSize.S,
                            fixedWidth: 120),
                        DataColumn2(
                            label: Text('Status',
                                style: TextStyle(
                                    color: context.colors.primaryGold,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                            size: ColumnSize.S,
                            fixedWidth: 130),
                      ],
                      rows: pageItems
                          .map((p) => DataRow(cells: [
                                DataCell(TooltipText(p.fullName,
                                    style: TextStyle(
                                        color: context.colors.textPrimary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13))),
                                DataCell(TooltipText(p.badgeNumber ?? '—',
                                    style: TextStyle(
                                        color: context.colors.textMuted,
                                        fontSize: 13))),
                                DataCell(_RoleChip(role: p.role)),
                                DataCell(_ExpiresInCell(profile: p)),
                                DataCell(_AccountStatusChip(profile: p)),
                              ]))
                          .toList(),
                    ),
                  ),
                )
                        .animate()
                        .slideY(begin: 0.1, duration: 400.ms, delay: 200.ms)
                        .fadeIn()),
                TablePager(
                  total: filtered.length,
                  page: _page,
                  pageSize: kClientPageSize,
                  onPageChanged: (p) => setState(() => _page = p),
                ),
              ]);
            },
          ),
        ),
      ]),
    );
  }

  Widget _statusChip(String label, bool? value) {
    final selected = _statusFilter == value;
    Color color;
    if (value == true) {
      color = context.colors.successGreen;
    } else if (value == false) {
      color = context.colors.dangerRed;
    } else {
      color = context.colors.primaryGold;
    }
    return GestureDetector(
      onTap: () => setState(() {
        _statusFilter = value;
        _page = 0;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : context.colors.borderColor,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? color : context.colors.textSecondary,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
      ),
    );
  }

  // ── Create Officer (OTP → auto username/password emailed) ──────────────
  void _showCreateOfficerDialog(BuildContext context, WidgetRef ref) {
    final firstC = TextEditingController();
    final lastC = TextEditingController();
    final salaryC = TextEditingController();
    final emailC = TextEditingController();
    final mobileC = TextEditingController();
    final otpC = TextEditingController();
    bool otpSent = false;
    bool loading = false;
    String? error;
    String? info;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          Future<void> sendOtp() async {
            final email = emailC.text.trim();
            final first = firstC.text.trim();
            final last = lastC.text.trim();
            if (first.isEmpty || last.isEmpty) {
              setState(() => error = 'First and last name are required.');
              return;
            }
            if (email.isEmpty ||
                !RegExp(r'^[\w.\-]+@([\w\-]+\.)+[\w\-]{2,}$').hasMatch(email)) {
              setState(() => error = 'Please enter a valid email address.');
              return;
            }
            setState(() {
              loading = true;
              error = null;
              info = null;
            });
            try {
              await ref.read(adminServiceProvider).requestOfficerOtp(
                    email: email,
                    fullName: '$first $last',
                    mobileNumber: mobileC.text.trim(),
                    badgeNumber: salaryC.text.trim(),
                  );
              setState(() {
                otpSent = true;
                info =
                    'OTP sent to $email. Enter the code the officer received to finish.';
              });
            } catch (e) {
              setState(
                  () => error = e.toString().replaceAll('Exception: ', ''));
            } finally {
              setState(() => loading = false);
            }
          }

          Future<void> verifyCreate() async {
            if (otpC.text.trim().isEmpty) {
              setState(() => error = 'Enter the OTP code.');
              return;
            }
            setState(() {
              loading = true;
              error = null;
            });
            try {
              final res =
                  await ref.read(adminServiceProvider).verifyAndCreateOfficer(
                        email: emailC.text.trim(),
                        otp: otpC.text.trim(),
                        fullName: '${firstC.text.trim()} ${lastC.text.trim()}',
                        mobileNumber: mobileC.text.trim(),
                        badgeNumber: salaryC.text.trim(),
                      );
              ref.invalidate(allProfilesProvider);
              if (ctx.mounted) Navigator.pop(ctx);
              final emailed = res['emailed'] == true;
              if (emailed) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                        '✅ Officer created — username & password emailed to ${emailC.text.trim()}'),
                    backgroundColor: context.colors.successGreen,
                    duration: const Duration(seconds: 6),
                  ));
                }
              } else {
                // Email delivery failed — show credentials so the admin can
                // hand them over manually.
                if (context.mounted) {
                  _showOfficerCredentialsFallback(
                    context,
                    res['username']?.toString() ?? '—',
                    res['password']?.toString() ?? '—',
                  );
                }
              }
            } catch (e) {
              setState(
                  () => error = e.toString().replaceAll('Exception: ', ''));
            } finally {
              setState(() => loading = false);
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
                      child: Text(text,
                          style: TextStyle(color: color, fontSize: 13))),
                ]),
              );

          return StyledFormDialog(
            label: 'Create Officer',
            title: 'New Officer Account',
            icon: Icons.person_add_rounded,
            width: 480,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (info != null)
                banner(info!, context.colors.successGreen,
                    Icons.check_circle_outline),
              if (error != null)
                banner(error!, context.colors.dangerRed, Icons.error_outline),
              StyledFormSection(
                title: 'Officer Details',
                icon: Icons.badge_outlined,
                children: [
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: firstC,
                            enabled: !otpSent,
                            decoration: const InputDecoration(
                                labelText: 'First Name *'))),
                    const Gap(12),
                    Expanded(
                        child: TextField(
                            controller: lastC,
                            enabled: !otpSent,
                            decoration: const InputDecoration(
                                labelText: 'Last Name *'))),
                  ]),
                  TextField(
                      controller: salaryC,
                      enabled: !otpSent,
                      decoration:
                          const InputDecoration(labelText: 'Salary Number')),
                  TextField(
                      controller: emailC,
                      enabled: !otpSent,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email *')),
                  TextField(
                      controller: mobileC,
                      enabled: !otpSent,
                      keyboardType: TextInputType.phone,
                      decoration:
                          const InputDecoration(labelText: 'Mobile Number')),
                  if (otpSent)
                    TextField(
                        controller: otpC,
                        keyboardType: TextInputType.number,
                        autofocus: true,
                        decoration: const InputDecoration(
                            labelText: 'OTP Code *',
                            helperText:
                                'A username & password will be emailed on success')),
                ],
              ),
            ]),
            actions: [
              if (otpSent && !loading)
                TextButton(
                    onPressed: () => setState(() {
                          otpSent = false;
                          otpC.clear();
                          info = null;
                          error = null;
                        }),
                    child: const Text('Back')),
              TextButton(
                  onPressed: loading ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              StyledDialogPrimaryButton(
                labelText: otpSent ? 'Verify & Create' : 'Send OTP',
                icon: otpSent ? Icons.how_to_reg_rounded : Icons.send_rounded,
                loading: loading,
                onPressed: otpSent ? verifyCreate : sendOtp,
              ),
            ],
          );
        },
      ),
    );
  }

  void _showOfficerCredentialsFallback(
      BuildContext context, String username, String password) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Account created (email failed)'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'The account was created but the credentials email could not be sent. Please give these to the officer:'),
          const Gap(16),
          SelectableText('Username: $username',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          SelectableText('Password: $password',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
        actions: [
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    final emailC = TextEditingController(), passC = TextEditingController();
    final nameC = TextEditingController(), badgeC = TextEditingController();
    String role = 'officer';
    String selectedYard = kDefaultYardCode;
    bool loading = false;
    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
              builder: (ctx, setState) => AlertDialog(
                title: const Text('Add New Officer'),
                content: SizedBox(
                    width: 400,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: nameC,
                          decoration:
                              const InputDecoration(labelText: 'Full Name *')),
                      const Gap(12),
                      TextField(
                          controller: badgeC,
                          decoration: const InputDecoration(
                              labelText: 'Salary Number')),
                      const Gap(12),
                      TextField(
                          controller: emailC,
                          decoration:
                              const InputDecoration(labelText: 'Email *'),
                          keyboardType: TextInputType.emailAddress),
                      const Gap(12),
                      TextField(
                          controller: passC,
                          decoration:
                              const InputDecoration(labelText: 'Password *'),
                          obscureText: true),
                      const Gap(12),
                      DropdownButtonFormField<String>(
                        value: role,
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: const [
                          DropdownMenuItem(
                              value: 'officer', child: Text('Officer')),
                          DropdownMenuItem(value: 'admin', child: Text('Admin'))
                        ],
                        onChanged: (v) => setState(() => role = v!),
                      ),
                      const Gap(12),
                      StyledDropdownFormField<String>(
                        value: selectedYard,
                        label: 'Yard *',
                        helperText: null,
                        menuWidth: 340,
                        options: [
                          for (final y in kYards)
                            StyledDropdownOption(y.code, y.name),
                        ],
                        onChanged: (v) => setState(
                            () => selectedYard = v ?? kDefaultYardCode),
                      ),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                  ElevatedButton(
                    onPressed: loading
                        ? null
                        : () async {
                            final email = emailC.text.trim();
                            if (email.isEmpty ||
                                !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                                    .hasMatch(email)) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Please enter a valid email address'),
                                      backgroundColor: Colors.red));
                              return;
                            }
                            setState(() => loading = true);
                            try {
                              await ref
                                  .read(adminServiceProvider)
                                  .createOfficer(
                                      email: email,
                                      password: passC.text,
                                      fullName: nameC.text.trim(),
                                      badgeNumber: badgeC.text.trim(),
                                      role: role,
                                      yard: selectedYard);
                              ref.invalidate(allProfilesProvider);
                              if (ctx.mounted) Navigator.pop(ctx);
                            } catch (e) {
                              final msg = _translateAuthError(e);
                              if (ctx.mounted)
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(msg),
                                        backgroundColor:
                                            context.colors.dangerRed,
                                        duration: const Duration(seconds: 8)));
                            } finally {
                              setState(() => loading = false);
                            }
                          },
                    child: loading
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.colors.primaryNavy))
                        : const Text('Create'),
                  ),
                ],
              ),
            ));
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, ProfileModel p) {
    final nameC = TextEditingController(text: p.fullName);
    final badgeC = TextEditingController(text: p.badgeNumber);
    String role = p.role;
    String selectedYard = yardByCode(p.yard).code;
    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
              builder: (ctx, setState) => AlertDialog(
                title: Text('Edit: ${p.fullName}'),
                content: SizedBox(
                    width: 360,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: nameC,
                          decoration:
                              const InputDecoration(labelText: 'Full Name')),
                      const Gap(12),
                      TextField(
                          controller: badgeC,
                          decoration: const InputDecoration(
                              labelText: 'Salary Number')),
                      const Gap(12),
                      DropdownButtonFormField<String>(
                        value: role,
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: const [
                          DropdownMenuItem(
                              value: 'officer', child: Text('Officer')),
                          DropdownMenuItem(value: 'admin', child: Text('Admin'))
                        ],
                        onChanged: (v) => setState(() => role = v!),
                      ),
                      const Gap(12),
                      StyledDropdownFormField<String>(
                        value: selectedYard,
                        label: 'Yard',
                        helperText: null,
                        menuWidth: 320,
                        options: [
                          for (final y in kYards)
                            StyledDropdownOption(y.code, y.name),
                        ],
                        onChanged: (v) => setState(
                            () => selectedYard = v ?? kDefaultYardCode),
                      ),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                  ElevatedButton(
                      onPressed: () async {
                        await ref.read(adminServiceProvider).updateProfile(p.id,
                            fullName: nameC.text.trim(),
                            badgeNumber: badgeC.text.trim(),
                            role: role,
                            yard: selectedYard);
                        ref.invalidate(allProfilesProvider);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: const Text('Save')),
                ],
              ),
            ));
  }
}

class _RoleChip extends StatelessWidget {
  final String role;
  const _RoleChip({required this.role});
  @override
  Widget build(BuildContext context) {
    final isAdmin = role == 'admin';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isAdmin
            ? context.colors.primaryGold.withOpacity(0.15)
            : context.colors.accentBlue.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: isAdmin
                ? context.colors.primaryGold.withOpacity(0.4)
                : context.colors.accentBlue.withOpacity(0.4)),
      ),
      child: Text(role.toUpperCase(),
          style: TextStyle(
              color: isAdmin
                  ? context.colors.primaryGold
                  : context.colors.accentLightBlue,
              fontSize: 11,
              fontWeight: FontWeight.w700)),
    );
  }
}

/// How long until the account auto-deactivates (its 8-month lifetime).
/// "Never" for directorate accounts, "Expired" once past, and a red countdown
/// in the last 2 weeks so admins can renew in time.
class _ExpiresInCell extends StatelessWidget {
  final ProfileModel profile;
  const _ExpiresInCell({required this.profile});

  @override
  Widget build(BuildContext context) {
    final days = profile.daysUntilExpiry;
    if (days == null) {
      return Text('Never',
          style: TextStyle(color: context.colors.textMuted, fontSize: 12));
    }
    if (days < 0) {
      return Text('Expired',
          style: TextStyle(
              color: context.colors.dangerRed,
              fontWeight: FontWeight.w700,
              fontSize: 12));
    }
    final soon = days <= 14;
    final label = days == 0 ? 'Today' : '$days day${days == 1 ? '' : 's'}';
    return Text(label,
        style: TextStyle(
            color: soon ? context.colors.dangerRed : context.colors.textPrimary,
            fontWeight: soon ? FontWeight.w700 : FontWeight.w600,
            fontSize: 12));
  }
}

/// Read-only account status. Admins can no longer toggle this manually; an
/// account is ACTIVE until 8 months after its creation date, then EXPIRED.
class _AccountStatusChip extends StatelessWidget {
  final ProfileModel profile;
  const _AccountStatusChip({required this.profile});

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color color;
    if (!profile.isActive) {
      label = 'INACTIVE';
      color = context.colors.dangerRed;
    } else if (profile.isExpired) {
      label = 'EXPIRED';
      color = context.colors.dangerRed;
    } else {
      label = 'ACTIVE';
      color = context.colors.successGreen;
    }
    final expiresStr = DateFormat('dd MMM yyyy').format(profile.expiresAt);
    return Tooltip(
      message: profile.isExpired
          ? 'Auto-deactivated on $expiresStr (8 months after creation)'
          : 'Auto-deactivates on $expiresStr (8 months after creation)',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

// ── Warehouses Tab ──────────────────────────────────────────────

class _WarehousesTab extends ConsumerWidget {
  const _WarehousesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warehouses = ref.watch(warehousesProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Warehouses',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.primaryGold,
                  foregroundColor: context.colors.primaryNavy,
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text(
                  'Add Warehouse',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                onPressed: () => _showAddWarehouseDialog(context, ref),
              ),
            ],
          ),
          const Gap(16),
          Expanded(
            child: warehouses.when(
              loading: () => Center(
                child: CircularProgressIndicator(
                  color: context.colors.primaryGold,
                ),
              ),
              error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.refresh(warehousesProvider),
              ),
              data: (list) => Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: context.colors.cardDark,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.colors.borderColor),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: DataTable2(
                    horizontalMargin: 24,
                    columnSpacing: 20,
                    fixedTopRows: 1,
                    empty: const EmptyTableState(
                        icon: Icons.warehouse_outlined,
                        message: 'No warehouses yet',
                        subtitle: 'Add a warehouse to admit packages into.'),
                    isHorizontalScrollBarVisible: false,
                    dataRowColor: WidgetStateProperty.all(Colors.transparent),
                    headingRowColor:
                        WidgetStateProperty.all(context.colors.surfaceDark),
                    columns: [
                      DataColumn2(
                        label: Text(
                          'Name',
                          style: TextStyle(
                            color: context.colors.primaryGold,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        size: ColumnSize.L,
                      ),
                      DataColumn2(
                        label: Text(
                          'Code',
                          style: TextStyle(
                            color: context.colors.primaryGold,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        size: ColumnSize.M,
                      ),
                      DataColumn2(
                        label: Text(
                          'Location',
                          style: TextStyle(
                            color: context.colors.primaryGold,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        size: ColumnSize.L,
                      ),
                      DataColumn2(
                        label: Text(
                          'Capacity',
                          style: TextStyle(
                            color: context.colors.primaryGold,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        size: ColumnSize.S,
                        fixedWidth: 80,
                      ),
                      DataColumn2(
                        label: Text(
                          'Actions',
                          style: TextStyle(
                            color: context.colors.primaryGold,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        size: ColumnSize.S,
                        fixedWidth: 160,
                      ),
                    ],
                    // Each warehouse, then one row per ZONE beneath it —
                    // capacity is set zone by zone, so the layout follows.
                    // The warehouse name repeats on the zone rows (greyed) so
                    // a zone is never orphaned from what it belongs to.
                    rows: _warehouseRowsWithZones(
                      context,
                      ref,
                      list,
                      (w) => DataRow(
                        cells: [
                          DataCell(
                            TooltipText(
                              w.name,
                              style: TextStyle(
                                color: context.colors.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          DataCell(
                            TooltipText(
                              w.code,
                              style: TextStyle(
                                color: context.colors.textMuted,
                                fontFamily: 'monospace',
                                fontSize: 13,
                              ),
                            ),
                          ),
                          DataCell(
                            TooltipText(
                              (w.description?.trim().isNotEmpty ?? false)
                                  ? w.description!.trim()
                                  : (w.location ?? '—'),
                              style: TextStyle(
                                color: context.colors.textMuted,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          // Capacity is the SUM of this warehouse's zones —
                          // space is managed zone by zone, so the warehouse
                          // figure is derived, never entered.
                          DataCell(Consumer(
                            builder: (context, ref, _) {
                              final zones = ref
                                      .watch(warehouseZonesProvider)
                                      .valueOrNull ??
                                  const <WarehouseZoneModel>[];
                              final mine = zones
                                  .where((z) => z.warehouseId == w.id)
                                  .toList();
                              final total =
                                  mine.fold<int>(0, (a, z) => a + z.capacity);
                              return TooltipText(
                                mine.isEmpty
                                    ? 'No zones'
                                    : '$total  (${mine.length} zone'
                                        '${mine.length == 1 ? '' : 's'})',
                                style: TextStyle(
                                  color: mine.isEmpty
                                      ? context.colors.dangerRed
                                      : context.colors.textMuted,
                                  fontSize: 13,
                                ),
                              );
                            },
                          )),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    Icons.grid_view_rounded,
                                    size: 16,
                                    color: context.colors.primaryGold,
                                  ),
                                  onPressed: () =>
                                      _showZonesDialog(context, ref, w),
                                  tooltip: 'Zones & capacity',
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.edit_rounded,
                                    size: 16,
                                    color: context.colors.accentLightBlue,
                                  ),
                                  onPressed: () => _showEditWarehouseDialog(
                                    context,
                                    ref,
                                    w,
                                  ),
                                  tooltip: 'Edit',
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.delete_rounded,
                                    size: 16,
                                    color: context.colors.dangerRed,
                                  ),
                                  onPressed: () => _showDeleteConfirmation(
                                    context,
                                    ref,
                                    w,
                                  ),
                                  tooltip: 'Delete',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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

  void _showAddWarehouseDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => const _AddWarehouseDialog(),
    );
  }

  /// The warehouse rows, each followed by one row per ZONE.
  ///
  /// Capacity is set zone by zone, so the table shows that structure directly
  /// rather than hiding it behind a dialog. A zone row repeats its warehouse's
  /// name in grey, so it is never orphaned from what it belongs to.
  List<DataRow> _warehouseRowsWithZones(
    BuildContext context,
    WidgetRef ref,
    List<WarehouseModel> warehouses,
    DataRow Function(WarehouseModel) buildWarehouseRow,
  ) {
    final zones = ref.watch(warehouseZonesProvider).valueOrNull ??
        const <WarehouseZoneModel>[];
    final occupancy = ref.watch(zoneOccupancyProvider).valueOrNull ??
        const <String, ZoneOccupancy>{};

    final rows = <DataRow>[];
    for (final w in warehouses) {
      rows.add(buildWarehouseRow(w));

      final mine = zones.where((z) => z.warehouseId == w.id).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      if (mine.isEmpty) {
        rows.add(DataRow(cells: [
          DataCell(Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Text('No zones — add one to set capacity',
                style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: context.colors.dangerRed)),
          )),
          const DataCell(SizedBox()),
          const DataCell(SizedBox()),
          const DataCell(SizedBox()),
          DataCell(Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.add_rounded, size: 14),
              label: const Text('Add Zone', style: TextStyle(fontSize: 12)),
              onPressed: () => _showZonesDialog(context, ref, w),
            ),
          )),
        ]));
        continue;
      }

      for (final z in mine) {
        final occ = occupancy[z.id];
        final used = occ?.used ?? 0;
        final free = occ?.free ?? z.capacity;
        rows.add(DataRow(cells: [
          // Warehouse name repeated, greyed — the zone's parent.
          DataCell(Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Row(children: [
              Icon(Icons.subdirectory_arrow_right_rounded,
                  size: 14, color: context.colors.textMuted),
              const Gap(6),
              Flexible(
                child: TooltipText('${w.name}  \u00b7  Zone ${z.name}',
                    style: TextStyle(
                        fontSize: 12.5, color: context.colors.textSecondary)),
              ),
            ]),
          )),
          // Code column — the zone's own, read like the warehouse's.
          DataCell(TooltipText(
              (z.code?.trim().isNotEmpty ?? false) ? z.code!.trim() : '—',
              style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: context.colors.textMuted))),
          DataCell(TooltipText(
              z.description?.trim().isNotEmpty == true
                  ? z.description!.trim()
                  : '$used in use',
              style: TextStyle(fontSize: 12, color: context.colors.textMuted))),
          DataCell(TooltipText(
              free == 0
                  ? '${z.capacity}  (FULL)'
                  : '${z.capacity}  ($free free)',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: free == 0
                      ? context.colors.dangerRed
                      : context.colors.successGreen))),
          DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              icon: Icon(Icons.edit_rounded,
                  size: 15, color: context.colors.accentLightBlue),
              tooltip: 'Edit zone',
              onPressed: () => _showZonesDialog(context, ref, w),
            ),
          ])),
        ]));
      }
    }
    return rows;
  }

  /// Manage the zones of one warehouse — this is where capacity is set.
  void _showZonesDialog(
      BuildContext context, WidgetRef ref, WarehouseModel warehouse) {
    showDialog(
      context: context,
      builder: (_) => _WarehouseZonesDialog(warehouse: warehouse),
    );
  }

  void _showEditWarehouseDialog(
    BuildContext context,
    WidgetRef ref,
    WarehouseModel warehouse,
  ) {
    final nameC = TextEditingController(text: warehouse.name);
    final codeC = TextEditingController(text: warehouse.code);
    final descC = TextEditingController(text: warehouse.description ?? '');
    final locC = TextEditingController(text: warehouse.location ?? '');
    final capC = TextEditingController(text: warehouse.capacity.toString());
    bool loading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => StyledFormDialog(
          label: 'Warehouse',
          title: 'Edit Warehouse',
          icon: Icons.warehouse_rounded,
          width: 460,
          child: StyledFormSection(
            title: warehouse.name,
            icon: Icons.warehouse_outlined,
            children: [
              TextField(
                controller: nameC,
                decoration: const InputDecoration(labelText: 'Warehouse Name'),
              ),
              TextField(
                controller: codeC,
                decoration: const InputDecoration(labelText: 'Code'),
              ),
              TextField(
                controller: descC,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 3,
                minLines: 2,
                keyboardType: TextInputType.multiline,
              ),
              TextField(
                controller: locC,
                decoration: const InputDecoration(labelText: 'Location'),
              ),
              TextField(
                controller: capC,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Capacity (items)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            StyledDialogPrimaryButton(
              labelText: 'Save',
              icon: Icons.save_rounded,
              loading: loading,
              onPressed: loading
                  ? null
                  : () async {
                      setState(() => loading = true);
                      try {
                        await ref
                            .read(warehouseServiceProvider)
                            .updateWarehouse(
                              id: warehouse.id,
                              name:
                                  nameC.text.isEmpty ? null : nameC.text.trim(),
                              code: codeC.text.isEmpty
                                  ? null
                                  : codeC.text.trim().toUpperCase(),
                              description:
                                  descC.text.isEmpty ? null : descC.text.trim(),
                              location:
                                  locC.text.isEmpty ? null : locC.text.trim(),
                              capacity: int.tryParse(capC.text),
                            );
                        ref.refresh(warehousesProvider);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Warehouse updated successfully'),
                              backgroundColor: Colors.green,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: ${e.toString()}'),
                              backgroundColor: Colors.red,
                              duration: const Duration(seconds: 4),
                            ),
                          );
                        }
                      } finally {
                        setState(() => loading = false);
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(
    BuildContext context,
    WidgetRef ref,
    WarehouseModel warehouse,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Warehouse?'),
        content: Text(
          'Are you sure you want to delete "${warehouse.name}"? This action cannot be undone. The warehouse must have no active entries.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () async {
              try {
                await ref.read(warehouseServiceProvider).deleteWarehouse(
                      warehouse.id,
                    );
                ref.refresh(warehousesProvider);
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Warehouse deleted successfully'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: ${e.toString()}'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 4),
                    ),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ── Categories Tab ──────────────────────────────────────────────

class _CategoriesTab extends ConsumerStatefulWidget {
  const _CategoriesTab();
  @override
  ConsumerState<_CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends ConsumerState<_CategoriesTab> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(packageCategoriesProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Item Categories',
              style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700)),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colors.primaryGold,
              foregroundColor: context.colors.primaryNavy,
            ),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Category',
                style: TextStyle(fontWeight: FontWeight.w600)),
            onPressed: () => _showAddCategoryDialog(context, ref),
          ),
        ]),
        const Gap(16),
        Expanded(
          child: categories.when(
            loading: () => Center(
                child: CircularProgressIndicator(
                    color: context.colors.primaryGold)),
            error: (e, _) => Center(
                child: Text('Error: $e',
                    style: TextStyle(color: context.colors.dangerRed))),
            data: (list) {
              final pageItems = pageSlice(list, _page, kClientPageSize);
              return Column(children: [
                Expanded(
                    child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                      color: context.colors.cardDark,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: context.colors.borderColor)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: DataTable2(
                      horizontalMargin: 24,
                      columnSpacing: 20,
                      fixedTopRows: 1,
                      empty: const EmptyTableState(
                          icon: Icons.category_outlined,
                          message: 'No item categories yet',
                          subtitle:
                              'Add a category to route items to a warehouse zone.'),
                      isHorizontalScrollBarVisible: false,
                      dataRowColor: WidgetStateProperty.all(Colors.transparent),
                      headingRowColor:
                          WidgetStateProperty.all(context.colors.surfaceDark),
                      columns: [
                        DataColumn2(
                            label: Text('Category Name',
                                style: TextStyle(
                                    color: context.colors.primaryGold,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                            size: ColumnSize.L),
                        DataColumn2(
                            label: Text('Warehouse',
                                style: TextStyle(
                                    color: context.colors.primaryGold,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                            size: ColumnSize.L),
                        DataColumn2(
                            label: Text('Zone',
                                style: TextStyle(
                                    color: context.colors.primaryGold,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                            size: ColumnSize.S,
                            fixedWidth: 100),
                        DataColumn2(
                            label: Text('Description',
                                style: TextStyle(
                                    color: context.colors.primaryGold,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                            size: ColumnSize.L),
                        DataColumn2(
                            label: Text('Actions',
                                style: TextStyle(
                                    color: context.colors.primaryGold,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                            size: ColumnSize.S,
                            fixedWidth: 120),
                      ],
                      rows: pageItems
                          .map((c) => DataRow(cells: [
                                DataCell(TooltipText(c.name,
                                    style: TextStyle(
                                        color: context.colors.textPrimary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13))),
                                DataCell(TooltipText(
                                    c.targetWarehouseName ?? '—',
                                    style: TextStyle(
                                        color: context.colors.textMuted,
                                        fontSize: 12))),
                                // Flags a zone the warehouse no longer has, so
                                // a category pointing nowhere is visible.
                                DataCell(Builder(builder: (_) {
                                  final zn = c.targetZone?.trim();
                                  if (zn == null || zn.isEmpty) {
                                    return TooltipText('—',
                                        style: TextStyle(
                                            color: context.colors.textMuted,
                                            fontSize: 12));
                                  }
                                  final zone = (ref
                                              .watch(warehouseZonesProvider)
                                              .valueOrNull ??
                                          const <WarehouseZoneModel>[])
                                      .where((z) =>
                                          z.warehouseId ==
                                              c.targetWarehouseId &&
                                          z.name.trim() == zn)
                                      .firstOrNull;
                                  return TooltipText(
                                      zone == null
                                          ? '$zn (not defined)'
                                          : '$zn  ·  ${zone.capacity} cap',
                                      style: TextStyle(
                                          color: zone == null
                                              ? context.colors.dangerRed
                                              : context.colors.textMuted,
                                          fontSize: 12));
                                })),
                                DataCell(TooltipText(c.description ?? '—',
                                    style: TextStyle(
                                        color: context.colors.textMuted,
                                        fontSize: 12))),
                                DataCell(Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.edit_rounded,
                                          color: context.colors.primaryGold,
                                          size: 22),
                                      padding: const EdgeInsets.all(4),
                                      constraints: const BoxConstraints(),
                                      onPressed: () => _showEditCategoryDialog(
                                          context, ref, c),
                                    ),
                                    const Gap(16),
                                    IconButton(
                                      icon: Icon(Icons.delete_outline_rounded,
                                          color: context.colors.dangerRed,
                                          size: 22),
                                      padding: const EdgeInsets.all(4),
                                      constraints: const BoxConstraints(),
                                      onPressed: () async {
                                        final ok = await showDialog<bool>(
                                            context: context,
                                            builder: (_) => AlertDialog(
                                                  title: const Text(
                                                      'Delete Category'),
                                                  content: Text(
                                                      'Delete "${c.name}"?'),
                                                  actions: [
                                                    TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                                context, false),
                                                        child: const Text(
                                                            'Cancel')),
                                                    ElevatedButton(
                                                        style: ElevatedButton.styleFrom(
                                                            backgroundColor:
                                                                context.colors
                                                                    .dangerRed,
                                                            foregroundColor:
                                                                Colors.white),
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                                context, true),
                                                        child: const Text(
                                                            'Delete')),
                                                  ],
                                                ));
                                        if (ok == true) {
                                          await ref
                                              .read(
                                                  packageCategoryServiceProvider)
                                              .deleteCategory(c.id);
                                          ref.invalidate(
                                              packageCategoriesProvider);
                                        }
                                      },
                                    ),
                                  ],
                                )),
                              ]))
                          .toList(),
                    ),
                  ),
                )
                        .animate()
                        .slideY(begin: 0.1, duration: 400.ms, delay: 200.ms)
                        .fadeIn()),
                TablePager(
                  total: list.length,
                  page: _page,
                  pageSize: kClientPageSize,
                  onPageChanged: (p) => setState(() => _page = p),
                ),
              ]);
            },
          ),
        ),
      ]),
    );
  }

  void _showAddCategoryDialog(BuildContext context, WidgetRef ref) {
    final nameC = TextEditingController(), descC = TextEditingController();
    String? selectedWarehouseId;
    String? selectedZone;

    showDialog(
        context: context,
        // Consumer so the dialog rebuilds when warehousesProvider resolves —
        // capturing the parent tab's `ref` here would freeze it on whatever
        // state the provider had when the dialog opened (often loading).
        builder: (ctx) => Consumer(builder: (ctx, ref, _) {
              return StatefulBuilder(builder: (ctx, setState) {
                final warehouses = ref.watch(warehousesProvider);
                return StyledFormDialog(
                  label: 'Item Category',
                  title: 'Add Package Category',
                  icon: Icons.category_rounded,
                  width: 560,
                  child: StyledFormSection(
                    title: 'Category Details',
                    icon: Icons.label_outline_rounded,
                    gap: 16,
                    children: [
                      TextField(
                          controller: nameC,
                          decoration: const InputDecoration(
                              labelText: 'Category Name *')),
                      TextField(
                          controller: descC,
                          decoration:
                              const InputDecoration(labelText: 'Description'),
                          maxLines: 3),
                      warehouses.when(
                        data: (list) => StyledDropdownFormField<String?>(
                          value: selectedWarehouseId,
                          label: 'Target Warehouse (Auto-assign)',
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 18),
                          options: [
                            const StyledDropdownOption<String?>(
                                null, 'None: Do not auto-assign'),
                            ...list.map((w) =>
                                StyledDropdownOption<String?>(w.id, w.name)),
                          ],
                          onChanged: (v) => setState(() {
                            selectedWarehouseId = v;
                            if (v == null) selectedZone = null;
                          }),
                        ),
                        loading: () => const CircularProgressIndicator(),
                        error: (e, _) => Text('Error: $e'),
                      ),
                      if (selectedWarehouseId != null)
                        Builder(builder: (_) {
                          // The REAL zones of the chosen warehouse, from
                          // `warehouse_zones` — not a fixed 1..10 list, so a
                          // warehouse can have as many as it actually has.
                          final zones = (ref
                                      .watch(warehouseZonesProvider)
                                      .valueOrNull ??
                                  const <WarehouseZoneModel>[])
                              .where(
                                  (z) => z.warehouseId == selectedWarehouseId)
                              .toList()
                            ..sort((a, b) => a.name.compareTo(b.name));

                          // Zones already assigned to another category in THIS
                          // warehouse — shown but disabled so they can't be picked.
                          final occupied = (ref
                                      .watch(packageCategoriesProvider)
                                      .value ??
                                  const [])
                              .where((c) =>
                                  c.targetWarehouseId == selectedWarehouseId &&
                                  c.targetZone != null)
                              .map((c) => c.targetZone!.trim())
                              .toSet();

                          return StyledDropdownFormField<String?>(
                            value: selectedZone,
                            label: zones.isEmpty
                                ? 'Target Zone (none defined)'
                                : 'Target Zone',
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 18),
                            options: [
                              const StyledDropdownOption<String?>(null, 'None'),
                              ...zones.map((z) => StyledDropdownOption<String?>(
                                  z.name,
                                  occupied.contains(z.name)
                                      ? '${z.name} (in use)'
                                      : '${z.name}  \u00b7  ${z.capacity} cap',
                                  enabled: !occupied.contains(z.name))),
                            ],
                            onChanged: (v) => setState(() => selectedZone = v),
                          );
                        }),
                    ],
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel',
                            style: TextStyle(fontSize: 16))),
                    StyledDialogPrimaryButton(
                        labelText: 'Add Category',
                        icon: Icons.add_rounded,
                        onPressed: () async {
                          if (nameC.text.isEmpty) return;

                          final existingCategories =
                              ref.read(packageCategoriesProvider).value ?? [];
                          if (selectedWarehouseId != null &&
                              selectedZone != null) {
                            final isOccupied = existingCategories.any((c) =>
                                c.targetWarehouseId == selectedWarehouseId &&
                                c.targetZone == selectedZone);
                            if (isOccupied) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'This Zone in the selected Warehouse is already assigned to another Category.'),
                                    backgroundColor: Colors.red),
                              );
                              return;
                            }
                          }

                          await ref
                              .read(packageCategoryServiceProvider)
                              .createCategory(
                                nameC.text.trim(),
                                description: descC.text.trim(),
                                targetWarehouseId: selectedWarehouseId,
                                targetZone: selectedZone,
                              );
                          ref.invalidate(packageCategoriesProvider);
                          if (ctx.mounted) Navigator.pop(ctx);
                        }),
                  ],
                );
              });
            }));
  }

  void _showEditCategoryDialog(
      BuildContext context, WidgetRef ref, PackageCategory category) {
    final nameC = TextEditingController(text: category.name);
    final descC = TextEditingController(text: category.description);
    String? selectedWarehouseId = category.targetWarehouseId;
    // Zones are stored by NAME now. Legacy rows were saved as "Zone 3" while
    // the zone itself is named "3", so strip that prefix if it is there.
    String? selectedZone = category.targetZone?.trim();

    showDialog(
        context: context,
        // Consumer so the dialog rebuilds when warehousesProvider resolves —
        // capturing the parent tab's `ref` here would freeze it on whatever
        // state the provider had when the dialog opened (often loading).
        builder: (ctx) => Consumer(builder: (ctx, ref, _) {
              return StatefulBuilder(builder: (ctx, setState) {
                final warehouses = ref.watch(warehousesProvider);
                return StyledFormDialog(
                  label: 'Item Category',
                  title: 'Edit Package Category',
                  icon: Icons.category_rounded,
                  width: 560,
                  child: StyledFormSection(
                    title: category.name,
                    icon: Icons.label_outline_rounded,
                    gap: 16,
                    children: [
                      TextField(
                          controller: nameC,
                          decoration: const InputDecoration(
                              labelText: 'Category Name *')),
                      TextField(
                          controller: descC,
                          decoration:
                              const InputDecoration(labelText: 'Description'),
                          maxLines: 3),
                      warehouses.when(
                        data: (list) => StyledDropdownFormField<String?>(
                          value: list.any((w) => w.id == selectedWarehouseId)
                              ? selectedWarehouseId
                              : null,
                          label: 'Target Warehouse (Auto-assign)',
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 18),
                          options: [
                            const StyledDropdownOption<String?>(
                                null, 'None: Do not auto-assign'),
                            ...list.map((w) =>
                                StyledDropdownOption<String?>(w.id, w.name)),
                          ],
                          onChanged: (v) => setState(() {
                            selectedWarehouseId = v;
                            if (v == null) selectedZone = null;
                          }),
                        ),
                        loading: () => const CircularProgressIndicator(),
                        error: (e, _) => Text('Error: $e'),
                      ),
                      if (selectedWarehouseId != null)
                        Builder(builder: (_) {
                          // The REAL zones of the chosen warehouse.
                          final zones = (ref
                                      .watch(warehouseZonesProvider)
                                      .valueOrNull ??
                                  const <WarehouseZoneModel>[])
                              .where(
                                  (z) => z.warehouseId == selectedWarehouseId)
                              .toList()
                            ..sort((a, b) => a.name.compareTo(b.name));
                          final names = zones.map((z) => z.name).toSet();

                          // Zones taken by OTHER categories in this warehouse
                          // (exclude this category itself) — shown but disabled.
                          final occupied = (ref
                                      .watch(packageCategoriesProvider)
                                      .value ??
                                  const [])
                              .where((c) =>
                                  c.id != category.id &&
                                  c.targetWarehouseId == selectedWarehouseId &&
                                  c.targetZone != null)
                              .map((c) => c.targetZone!.trim())
                              .toSet();

                          return StyledDropdownFormField<String?>(
                            // A zone the warehouse no longer has cannot stay
                            // selected, or the dropdown would hold a value its
                            // menu cannot offer.
                            value: names.contains(selectedZone)
                                ? selectedZone
                                : null,
                            label: zones.isEmpty
                                ? 'Target Zone (none defined)'
                                : 'Target Zone',
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 18),
                            options: [
                              const StyledDropdownOption<String?>(null, 'None'),
                              ...zones.map((z) => StyledDropdownOption<String?>(
                                  z.name,
                                  occupied.contains(z.name)
                                      ? '${z.name} (in use)'
                                      : '${z.name}  ·  ${z.capacity} cap',
                                  enabled: !occupied.contains(z.name))),
                            ],
                            onChanged: (v) => setState(() => selectedZone = v),
                          );
                        }),
                    ],
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel',
                            style: TextStyle(fontSize: 16))),
                    StyledDialogPrimaryButton(
                        labelText: 'Save Changes',
                        icon: Icons.save_rounded,
                        onPressed: () async {
                          if (nameC.text.isEmpty) return;

                          final existingCategories =
                              ref.read(packageCategoriesProvider).value ?? [];
                          if (selectedWarehouseId != null &&
                              selectedZone != null) {
                            final isOccupied = existingCategories.any((c) =>
                                c.id != category.id &&
                                c.targetWarehouseId == selectedWarehouseId &&
                                c.targetZone == selectedZone);

                            if (isOccupied) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'This Zone in the selected Warehouse is already assigned to another Category.'),
                                    backgroundColor: Colors.red),
                              );
                              return;
                            }
                          }

                          await ref
                              .read(packageCategoryServiceProvider)
                              .updateCategory(
                                category.id,
                                nameC.text.trim(),
                                description: descC.text.trim(),
                                targetWarehouseId: selectedWarehouseId,
                                targetZone: selectedWarehouseId == null ||
                                        selectedZone == null
                                    ? null
                                    : selectedZone,
                              );
                          ref.invalidate(packageCategoriesProvider);
                          if (ctx.mounted) Navigator.pop(ctx);
                        }),
                  ],
                );
              });
            }));
  }
}

class _RuleTypeChip extends StatelessWidget {
  final String type;
  const _RuleTypeChip({required this.type});
  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (type) {
      case 'max_value':
        color = context.colors.warningAmber;
        label = 'MAX VALUE';
        break;
      case 'max_weight':
        color = context.colors.accentLightBlue;
        label = 'MAX WEIGHT';
        break;
      case 'max_items':
        color = context.colors.primaryGold;
        label = 'MAX ITEMS';
        break;
      case 'prohibited_category':
        color = context.colors.dangerRed;
        label = 'PROHIBITED';
        break;
      default:
        color = context.colors.textMuted;
        label = 'CUSTOM';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: color.withOpacity(0.35))),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

String _translateAuthError(Object e) {
  final raw = e.toString().toLowerCase();

  if (raw.contains('rate_limit') ||
      raw.contains('rate limit') ||
      raw.contains('429')) {
    return 'Supabase Email Limit Reached! 🛑\n\nTo fix this:\n1. Open Supabase Dashboard\n2. Go to Authentication > Providers > Email\n3. Turn OFF "Confirm email"\n4. Save and try again.';
  }
  if (raw.contains('already registered') ||
      raw.contains('user_already_exists')) {
    return 'This email is already registered. Try a different email.';
  }
  return 'Error: $e';
}

class _StatusToggle extends StatefulWidget {
  final bool isActive;
  final Future<void> Function(bool) onChanged;
  final String label;

  const _StatusToggle(
      {required this.isActive, required this.onChanged, required this.label});

  @override
  State<_StatusToggle> createState() => _StatusToggleState();
}

class _StatusToggleState extends State<_StatusToggle> {
  bool _loading = false;
  late bool _currentValue;

  DateTime? _lastChangeTime;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.isActive;
  }

  @override
  void didUpdateWidget(_StatusToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If we are currently loading, or if we just successfully changed the value
    // within the last 1.5 seconds, ignore updates from the parent.
    // This prevents the "snap back" to old data while the provider is re-fetching.
    if (_loading) return;
    if (_lastChangeTime != null &&
        DateTime.now().difference(_lastChangeTime!) <
            const Duration(milliseconds: 1500)) {
      return;
    }

    if (widget.isActive != _currentValue) {
      setState(() => _currentValue = widget.isActive);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Switch(
      value: _currentValue,
      activeColor: context.colors.successGreen,
      activeTrackColor: context.colors.successGreen.withOpacity(0.4),
      inactiveThumbColor: Colors.white,
      inactiveTrackColor: Colors.grey.withOpacity(0.3),
      onChanged: (v) async {
        if (_loading) return;
        setState(() {
          _loading = true;
          _currentValue = v;
        });
        print('DEBUG: _StatusToggle triggered for ${widget.label} to $v');
        try {
          await widget.onChanged(v);
          _lastChangeTime = DateTime.now(); // Mark successful change
        } catch (e) {
          if (mounted) {
            setState(() => _currentValue = !v);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Failed: $e'),
                backgroundColor: context.colors.dangerRed));
          }
        } finally {
          if (mounted) setState(() => _loading = false);
        }
      },
    );
  }
}

// ── Logs Tab ──────────────────────────────────────────────────

class _LogsTab extends ConsumerStatefulWidget {
  const _LogsTab();
  @override
  ConsumerState<_LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends ConsumerState<_LogsTab> {
  int _page = 0;

  String _formatEntity(String entityType) {
    if (entityType.isEmpty) return '—';
    return entityType
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty
            ? w
            : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }

  String _formatAction(AuditLogModel log) {
    if (log.entityType == 'storage_rate' &&
        log.action == 'Updated storage rate') {
      return 'Storage rate updated';
    }
    return log.action;
  }

  String _formatDetails(AuditLogModel log) {
    final details = log.details;
    if (details == null || details.isEmpty) return '—';

    if (log.entityType == 'storage_rate') {
      final oldRate = details['old_rate'] as num?;
      final newRate = details['new_rate'] as num?;
      if (oldRate != null || newRate != null) {
        final oldText =
            oldRate != null ? NumberFormat('#,##0.00').format(oldRate) : '—';
        final newText =
            newRate != null ? NumberFormat('#,##0.00').format(newRate) : '—';
        return 'LKR $oldText -> LKR $newText';
      }
    }

    final pairs = details.entries.map((e) => '${e.key}: ${e.value}').toList();
    return pairs.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(allLogsProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Activity Logs',
            style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w700)),
        const Gap(16),
        Expanded(
          child: logs.when(
            loading: () => Center(
                child: CircularProgressIndicator(
                    color: context.colors.primaryGold)),
            error: (e, _) => Center(
                child: Text('Error: $e',
                    style: TextStyle(color: context.colors.dangerRed))),
            data: (list) {
              final pageItems = pageSlice(list, _page, kClientPageSize);
              return Column(children: [
                Expanded(
                    child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                      color: context.colors.cardDark,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: context.colors.borderColor)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: DataTable2(
                      horizontalMargin: 24,
                      columnSpacing: 20,
                      fixedTopRows: 1,
                      empty: const EmptyTableState(
                          icon: Icons.request_quote_outlined,
                          message: 'No storage rates yet',
                          subtitle:
                              'Add a storage rate to charge warehouse holds.'),
                      isHorizontalScrollBarVisible: false,
                      dataRowColor: WidgetStateProperty.all(Colors.transparent),
                      headingRowColor:
                          WidgetStateProperty.all(context.colors.surfaceDark),
                      columns: [
                        DataColumn2(
                            label: Text('Time',
                                style: TextStyle(
                                    color: context.colors.primaryGold,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                            size: ColumnSize.S,
                            fixedWidth: 140),
                        DataColumn2(
                            label: Text('User',
                                style: TextStyle(
                                    color: context.colors.primaryGold,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                            size: ColumnSize.M),
                        DataColumn2(
                            label: Text('Action',
                                style: TextStyle(
                                    color: context.colors.primaryGold,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                            size: ColumnSize.L),
                        DataColumn2(
                            label: Text('Entity',
                                style: TextStyle(
                                    color: context.colors.primaryGold,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                            size: ColumnSize.S,
                            fixedWidth: 100),
                        DataColumn2(
                            label: Text('Details',
                                style: TextStyle(
                                    color: context.colors.primaryGold,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                            size: ColumnSize.L),
                      ],
                      rows: pageItems.map((l) {
                        final timeStr = DateFormat('dd MMM yyyy, HH:mm')
                            .format(l.createdAt);
                        return DataRow(cells: [
                          DataCell(TooltipText(timeStr,
                              style: TextStyle(
                                  color: context.colors.textMuted,
                                  fontSize: 13))),
                          DataCell(TooltipText(l.userFullName ?? 'Unknown',
                              style: TextStyle(
                                  color: context.colors.textPrimary,
                                  fontWeight: FontWeight.w600))),
                          DataCell(TooltipText(_formatAction(l),
                              style: TextStyle(
                                  color: context.colors.accentLightBlue))),
                          DataCell(TooltipText(_formatEntity(l.entityType),
                              style: TextStyle(
                                  color: context.colors.textMuted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700))),
                          DataCell(TooltipText(_formatDetails(l),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: TextStyle(
                                  color: context.colors.textMuted,
                                  fontSize: 12))),
                        ]);
                      }).toList(),
                    ),
                  ),
                )
                        .animate()
                        .slideY(begin: 0.1, duration: 400.ms, delay: 200.ms)
                        .fadeIn()),
                TablePager(
                  total: list.length,
                  page: _page,
                  pageSize: kClientPageSize,
                  onPageChanged: (p) => setState(() => _page = p),
                ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

// ── Storage Charges Tab ───────────────────────────────────────

class _StorageChargesTab extends ConsumerStatefulWidget {
  const _StorageChargesTab();
  @override
  ConsumerState<_StorageChargesTab> createState() => _StorageChargesTabState();
}

class _StorageChargesTabState extends ConsumerState<_StorageChargesTab> {
  final _chargeCtrl = TextEditingController();
  bool _loading = false;

  double? _latestRate(Map<DateTime, double>? rates) {
    if (rates == null || rates.isEmpty) return null;
    final latestEntry = rates.entries.reduce(
      (a, b) => a.key.isAfter(b.key) ? a : b,
    );
    return latestEntry.value;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rates = ref.read(storageRateProvider).valueOrNull;
      final rate = _latestRate(rates);
      _chargeCtrl.text = rate?.toStringAsFixed(2) ?? '';
    });
  }

  @override
  void dispose() {
    _chargeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_chargeCtrl.text.isEmpty) return;
    final rate = double.tryParse(_chargeCtrl.text) ?? 0;
    setState(() => _loading = true);
    try {
      final previousRate = _latestRate(
        ref.read(storageRateProvider).valueOrNull,
      );
      final insertRes = await supabase
          .from('storage_rates')
          .insert({
            'rate': rate,
            'effective_from': DateTime.now().toIso8601String(),
          })
          .select('id')
          .single();

      final user = supabase.auth.currentUser;
      if (user != null) {
        await AuditLogService().recordLog(
          userId: user.id,
          action: 'Updated storage rate',
          entityType: 'storage_rate',
          entityId: insertRes['id'].toString(),
          details: {
            'old_rate': previousRate,
            'new_rate': rate,
          },
        );
      }

      ref.invalidate(storageRateProvider);
      ref.invalidate(storageRateHistoryProvider);
      ref.invalidate(allLogsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Storage rate updated successfully'),
            backgroundColor: context.colors.successGreen));
        Navigator.pop(context);
        _chargeCtrl.clear();
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'),
            backgroundColor: context.colors.dangerRed));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(storageRateHistoryProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Storage Rates & Charges',
                  style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w700)),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.primaryGold,
                  foregroundColor: context.colors.primaryNavy,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Change Charges',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                onPressed: () => _showUpdateDialog(context),
              ),
            ],
          ),
          const Gap(16),
          Expanded(
            child: history.when(
              loading: () => Center(
                  child: CircularProgressIndicator(
                      color: context.colors.primaryGold)),
              error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.refresh(storageRateHistoryProvider)),
              data: (list) => Container(
                width: double.infinity,
                decoration: BoxDecoration(
                    color: context.colors.cardDark,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.colors.borderColor)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: DataTable2(
                    horizontalMargin: 24,
                    columnSpacing: 20,
                    fixedTopRows: 1,
                    empty: const EmptyTableState(
                        icon: Icons.history_rounded,
                        message: 'No activity yet',
                        subtitle: 'System actions will be logged here.'),
                    isHorizontalScrollBarVisible: false,
                    dataRowColor: WidgetStateProperty.all(Colors.transparent),
                    headingRowColor:
                        WidgetStateProperty.all(context.colors.surfaceDark),
                    columns: [
                      DataColumn2(
                          label: Text('Date & Time',
                              style: TextStyle(
                                  color: context.colors.primaryGold,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13)),
                          size: ColumnSize.M),
                      DataColumn2(
                          label: Text('Officer/Admin',
                              style: TextStyle(
                                  color: context.colors.primaryGold,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13)),
                          size: ColumnSize.L),
                      DataColumn2(
                          label: Text('Action / Value Change',
                              style: TextStyle(
                                  color: context.colors.primaryGold,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13)),
                          size: ColumnSize.L),
                    ],
                    rows: list
                        .map((h) => DataRow(cells: [
                              DataCell(TooltipText(
                                  DateFormat('dd MMM yyyy, HH:mm')
                                      .format(h.createdAt),
                                  style: TextStyle(
                                      color: context.colors.textMuted,
                                      fontSize: 13))),
                              DataCell(TooltipText(
                                  h.userId == 'system'
                                      ? 'System'
                                      : (h.userFullName ?? 'Admin'),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600))),
                              DataCell(TooltipText(
                                  h.action == 'RATE_UPDATE'
                                      ? 'Rate Set: LKR ${NumberFormat('#,##0.00').format(h.details?['rate'] ?? 0)}'
                                      : h.action,
                                  style: TextStyle(
                                      color: context.colors.primaryGold,
                                      fontSize: 13))),
                            ]))
                        .toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showUpdateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => StyledFormDialog(
          label: 'Storage Rate',
          title: 'Update Storage Charges',
          icon: Icons.payments_rounded,
          width: 440,
          child: StyledFormSection(
            title: 'Daily Charge',
            icon: Icons.attach_money_rounded,
            children: [
              Text(
                'Set the daily storage fee per package. This rate is used to calculate the total cost for held items.',
                style: TextStyle(
                    color: context.colors.textSecondary, fontSize: 13),
              ),
              TextField(
                controller: _chargeCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                style: TextStyle(color: context.colors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Daily Charge Rate (LKR)',
                  prefixText: 'LKR ',
                  helperText: 'e.g. 150.00',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            StyledDialogPrimaryButton(
              labelText: 'Update Rate',
              icon: Icons.save_rounded,
              loading: _loading,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

/// Zones of one warehouse, each with its own capacity.
///
/// Capacity lives here rather than on the warehouse: space is organised zone
/// by zone, and the warehouse's figure is simply their sum. Setting it in one
/// place means the two can never disagree.
class _WarehouseZonesDialog extends ConsumerStatefulWidget {
  final WarehouseModel warehouse;
  const _WarehouseZonesDialog({required this.warehouse});

  @override
  ConsumerState<_WarehouseZonesDialog> createState() =>
      _WarehouseZonesDialogState();
}

class _WarehouseZonesDialogState extends ConsumerState<_WarehouseZonesDialog> {
  bool _busy = false;

  Future<void> _save(WarehouseZoneModel zone) async {
    setState(() => _busy = true);
    try {
      await ref.read(warehouseServiceProvider).saveWarehouseZone(zone);
      ref.read(warehouseRefreshTriggerProvider.notifier).trigger();
      ref.invalidate(warehouseZonesProvider);
      ref.invalidate(zoneOccupancyProvider);
      ref.invalidate(yardWarehouseCapacityProvider);
    } catch (e) {
      if (mounted) context.showError('Could not save the zone: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(WarehouseZoneModel zone) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('Delete zone ${zone.name}?'),
            content: const Text(
                'Goods already recorded in this zone stay where they are, but '
                'the zone stops counting towards capacity.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text('Delete',
                    style: TextStyle(color: context.colors.dangerRed)),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;

    setState(() => _busy = true);
    try {
      await ref.read(warehouseServiceProvider).deleteWarehouseZone(zone.id);
      ref.read(warehouseRefreshTriggerProvider.notifier).trigger();
      ref.invalidate(warehouseZonesProvider);
      ref.invalidate(zoneOccupancyProvider);
      ref.invalidate(yardWarehouseCapacityProvider);
    } catch (e) {
      if (mounted) context.showError('Could not delete the zone: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit({WarehouseZoneModel? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final codeCtrl = TextEditingController(text: existing?.code ?? '');
    final capCtrl =
        TextEditingController(text: (existing?.capacity ?? 500).toString());
    final descCtrl = TextEditingController(text: existing?.description ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(existing == null ? 'Add zone' : 'Edit zone'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Zone name *', hintText: 'A, B, Cold Room…'),
            ),
            const Gap(12),
            TextField(
              controller: codeCtrl,
              decoration: InputDecoration(
                  labelText: 'Zone Code',
                  hintText:
                      '${widget.warehouse.code}-${nameCtrl.text.trim().toUpperCase()}'),
            ),
            const Gap(12),
            TextField(
              controller: capCtrl,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Capacity (items) *'),
            ),
            const Gap(12),
            TextField(
              controller: descCtrl,
              decoration:
                  const InputDecoration(labelText: 'Description (optional)'),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty) return;
              if ((int.tryParse(capCtrl.text.trim()) ?? -1) < 0) return;
              Navigator.pop(c, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved != true) return;
    await _save(WarehouseZoneModel(
      id: existing?.id ?? '',
      warehouseId: widget.warehouse.id,
      name: nameCtrl.text.trim(),
      // Falls back to "<warehouse code>-<zone name>" so codes stay consistent
      // without the operator having to type them.
      code: codeCtrl.text.trim().isEmpty
          ? '${widget.warehouse.code}-'
              '${nameCtrl.text.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase()}'
          : codeCtrl.text.trim().toUpperCase(),
      description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
      capacity: int.tryParse(capCtrl.text.trim()) ?? 500,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final zones = (ref.watch(warehouseZonesProvider).valueOrNull ??
            const <WarehouseZoneModel>[])
        .where((z) => z.warehouseId == widget.warehouse.id)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final occupancy = ref.watch(zoneOccupancyProvider).valueOrNull ??
        const <String, ZoneOccupancy>{};
    final total = zones.fold<int>(0, (a, z) => a + z.capacity);

    return StyledFormDialog(
      label: 'ZONES & CAPACITY',
      title: widget.warehouse.name,
      icon: Icons.grid_view_rounded,
      width: 620,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        const Gap(8),
        ElevatedButton.icon(
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add Zone'),
          onPressed: _busy ? null : () => _edit(),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.colors.primaryGold.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: context.colors.primaryGold.withOpacity(0.3)),
            ),
            child: Row(children: [
              Icon(Icons.info_outline_rounded,
                  size: 16, color: context.colors.primaryGold),
              const Gap(10),
              Expanded(
                child: Text(
                    "This warehouse's capacity is the SUM of its zones: "
                    '$total item${total == 1 ? '' : 's'} across '
                    '${zones.length} zone${zones.length == 1 ? '' : 's'}.',
                    style: TextStyle(
                        fontSize: 12, color: context.colors.textSecondary)),
              ),
            ]),
          ),
          const Gap(14),
          if (zones.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                    'No zones yet — add one so goods can be admitted here.',
                    style: TextStyle(
                        color: context.colors.textMuted, fontSize: 13)),
              ),
            )
          else
            ...zones.map((z) {
              final occ = occupancy[z.id];
              final used = occ?.used ?? 0;
              final free = occ?.free ?? z.capacity;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: context.colors.surfaceDark,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.colors.borderColor),
                ),
                child: Row(children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Zone ${z.name}',
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w700)),
                        if (z.description?.trim().isNotEmpty ?? false)
                          Text(z.description!.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: context.colors.textMuted)),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('$used / ${z.capacity}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 12.5,
                            color: context.colors.textSecondary)),
                  ),
                  const Gap(12),
                  SizedBox(
                    width: 84,
                    child: Text(free == 0 ? 'FULL' : '$free free',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: free == 0
                                ? context.colors.dangerRed
                                : context.colors.successGreen)),
                  ),
                  const Gap(4),
                  IconButton(
                    icon: Icon(Icons.edit_rounded,
                        size: 16, color: context.colors.accentLightBlue),
                    tooltip: 'Edit',
                    onPressed: _busy ? null : () => _edit(existing: z),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_rounded,
                        size: 16, color: context.colors.dangerRed),
                    tooltip: 'Delete',
                    onPressed: _busy ? null : () => _delete(z),
                  ),
                ]),
              );
            }),
        ],
      ),
    );
  }
}

/// Create a warehouse together with its ZONES.
///
/// Capacity belongs to the zones, so a warehouse cannot be created without at
/// least one — otherwise it would exist with nowhere to put anything. The
/// warehouse's own capacity is the SUM of what is entered here.
class _AddWarehouseDialog extends ConsumerStatefulWidget {
  const _AddWarehouseDialog();

  @override
  ConsumerState<_AddWarehouseDialog> createState() =>
      _AddWarehouseDialogState();
}

/// One zone row being filled in on the form.
class _ZoneDraft {
  final TextEditingController name;
  final TextEditingController code;
  final TextEditingController capacity;

  _ZoneDraft({String name = '', String code = '', String capacity = '500'})
      : name = TextEditingController(text: name),
        code = TextEditingController(text: code),
        capacity = TextEditingController(text: capacity);

  void dispose() {
    name.dispose();
    code.dispose();
    capacity.dispose();
  }
}

class _AddWarehouseDialogState extends ConsumerState<_AddWarehouseDialog> {
  final _nameC = TextEditingController();
  final _codeC = TextEditingController();
  final _descC = TextEditingController();
  final _locC = TextEditingController();

  // Starts with one zone: a warehouse with none could hold nothing.
  final _zones = <_ZoneDraft>[_ZoneDraft(name: 'A')];
  bool _loading = false;

  @override
  void dispose() {
    _nameC.dispose();
    _codeC.dispose();
    _descC.dispose();
    _locC.dispose();
    for (final z in _zones) {
      z.dispose();
    }
    super.dispose();
  }

  int get _totalCapacity => _zones.fold<int>(
      0, (a, z) => a + (int.tryParse(z.capacity.text.trim()) ?? 0));

  /// Suggests "<warehouse code>-<zone name>" so the codes read consistently
  /// without the operator having to type them.
  String _suggestedZoneCode(_ZoneDraft z) {
    final wh = _codeC.text.trim().toUpperCase();
    final zn = z.name.text.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (wh.isEmpty || zn.isEmpty) return '';
    return '$wh-$zn';
  }

  Future<void> _create() async {
    final name = _nameC.text.trim();
    final code = _codeC.text.trim().toUpperCase();
    if (name.isEmpty || code.isEmpty) {
      context.showError('Name and Code are required');
      return;
    }
    final named = _zones.where((z) => z.name.text.trim().isNotEmpty).toList();
    if (named.isEmpty) {
      context.showError('Add at least one zone — capacity lives on the zones');
      return;
    }

    setState(() => _loading = true);
    try {
      final svc = ref.read(warehouseServiceProvider);
      final created = await svc.addWarehouse(
        name: name,
        code: code,
        description: _descC.text.trim().isEmpty ? null : _descC.text.trim(),
        location: _locC.text.trim().isEmpty ? null : _locC.text.trim(),
        // Kept in step with the zones so anything still reading the legacy
        // column sees the same number.
        capacity: _totalCapacity,
      );

      for (final z in named) {
        await svc.saveWarehouseZone(WarehouseZoneModel(
          id: '',
          warehouseId: created.id,
          name: z.name.text.trim(),
          code: z.code.text.trim().isEmpty
              ? _suggestedZoneCode(z)
              : z.code.text.trim().toUpperCase(),
          capacity: int.tryParse(z.capacity.text.trim()) ?? 500,
        ));
      }

      ref.read(warehouseRefreshTriggerProvider.notifier).trigger();
      ref.invalidate(warehousesProvider);
      ref.invalidate(warehouseZonesProvider);
      ref.invalidate(zoneOccupancyProvider);
      ref.invalidate(yardWarehouseCapacityProvider);

      if (!mounted) return;
      Navigator.pop(context);
      context.showSuccess('Warehouse "$name" added with '
          '${named.length} zone${named.length == 1 ? '' : 's'}');
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        context.showError('Error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StyledFormDialog(
      label: 'WAREHOUSE',
      title: 'Add New Warehouse',
      icon: Icons.warehouse_rounded,
      width: 620,
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        StyledDialogPrimaryButton(
          labelText: 'Create',
          icon: Icons.add_rounded,
          loading: _loading,
          onPressed: _loading ? null : _create,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          StyledFormSection(
            title: 'Warehouse Details',
            icon: Icons.warehouse_outlined,
            children: [
              TextField(
                controller: _nameC,
                decoration:
                    const InputDecoration(labelText: 'Warehouse Name *'),
              ),
              TextField(
                controller: _codeC,
                onChanged: (_) => setState(() {}), // refresh code suggestions
                decoration:
                    const InputDecoration(labelText: 'Code (e.g., W01) *'),
              ),
              TextField(
                controller: _descC,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 2,
                minLines: 1,
              ),
              TextField(
                controller: _locC,
                decoration: const InputDecoration(labelText: 'Location'),
              ),
            ],
          ),
          const Gap(14),
          StyledFormSection(
            title: 'Zones',
            icon: Icons.grid_view_rounded,
            children: [
              Text(
                  "Capacity is set per zone — the warehouse's capacity is "
                  'their total.',
                  style:
                      TextStyle(fontSize: 12, color: context.colors.textMuted)),
              const Gap(10),
              for (var i = 0; i < _zones.length; i++) ...[
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _zones[i].name,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                          labelText: 'Zone Name *', isDense: true),
                    ),
                  ),
                  const Gap(8),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _zones[i].code,
                      decoration: InputDecoration(
                          labelText: 'Zone Code',
                          isDense: true,
                          hintText: _suggestedZoneCode(_zones[i])),
                    ),
                  ),
                  const Gap(8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _zones[i].capacity,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                          labelText: 'Capacity *', isDense: true),
                    ),
                  ),
                  // The last remaining zone cannot be removed.
                  IconButton(
                    icon: Icon(Icons.close_rounded,
                        size: 18,
                        color: _zones.length == 1
                            ? context.colors.textMuted
                            : context.colors.dangerRed),
                    tooltip: 'Remove zone',
                    onPressed: _zones.length == 1
                        ? null
                        : () => setState(() {
                              // Dispose the controllers of the row we drop,
                              // not of whatever ends up at that index after.
                              _zones.removeAt(i).dispose();
                            }),
                  ),
                ]),
                const Gap(8),
              ],
              Row(children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add Zone'),
                  onPressed: () => setState(() => _zones.add(_ZoneDraft())),
                ),
                const Spacer(),
                Text('Total capacity: $_totalCapacity',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: context.colors.primaryGold)),
              ]),
            ],
          ),
        ],
      ),
    );
  }
}
