import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../services/services.dart';
import '../../models/models.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/error_view.dart';
import 'package:data_table_2/data_table_2.dart';

class AdminScreen extends ConsumerWidget {
  final int initialIndex;
  const AdminScreen({super.key, this.initialIndex = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppShell(
      currentRoute: '/admin/panel',
      child: DefaultTabController(
        length: 6,
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
                        Text(
                            'Manage officers, customs rules and system configuration',
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
                                icon: Icon(Icons.gavel_rounded, size: 20),
                                text: 'Rules'),
                            Tab(
                                icon: Icon(Icons.category_rounded, size: 20),
                                text: 'Items'),
                            Tab(
                                icon: Icon(Icons.payments_rounded, size: 20),
                                text: 'Storage Charges'),
                            Tab(
                                icon: Icon(Icons.list_alt_rounded, size: 20),
                                text: 'Hold Reasons'),
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
                _RulesTab(),
                _CategoriesTab(),
                _StorageChargesTab(),
                _HoldReasonsTab(),
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

class _OfficersTab extends ConsumerWidget {
  const _OfficersTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(allProfilesProvider);
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
            onPressed: () => _showAddDialog(context, ref),
          ),
        ]),
        const Gap(16),
        Expanded(
          child: profiles.when(
            loading: () => Center(
                child: CircularProgressIndicator(
                    color: context.colors.primaryGold)),
            error: (e, _) => ErrorView(
                error: e, onRetry: () => ref.refresh(allProfilesProvider)),
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
                        label: Text('Active',
                            style: TextStyle(
                                color: context.colors.primaryGold,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        size: ColumnSize.S,
                        fixedWidth: 100),
                    DataColumn2(
                        label: Text('Actions',
                            style: TextStyle(
                                color: context.colors.primaryGold,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        size: ColumnSize.S,
                        fixedWidth: 80),
                  ],
                  rows: list
                      .map((p) => DataRow(cells: [
                            DataCell(Text(p.fullName,
                                style: TextStyle(
                                    color: context.colors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13))),
                            DataCell(Text(p.badgeNumber ?? '—',
                                style: TextStyle(
                                    color: context.colors.textMuted,
                                    fontSize: 13))),
                            DataCell(_RoleChip(role: p.role)),
                            DataCell(_StatusToggle(
                              isActive: p.isActive,
                              onChanged: (v) async {
                                final currentProfile =
                                    ref.read(currentProfileProvider);
                                if (v == false && currentProfile?.id == p.id) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                'You cannot deactivate your own account!'),
                                            backgroundColor: Colors.orange,
                                            duration: Duration(seconds: 2)));
                                  }
                                  return;
                                }
                                await ref
                                    .read(adminServiceProvider)
                                    .toggleUserStatus(p.id, v);
                                ref.invalidate(allProfilesProvider);
                              },
                              label: p.fullName,
                            )),
                            DataCell(IconButton(
                              icon: Icon(Icons.edit_outlined,
                                  color: context.colors.accentLightBlue,
                                  size: 18),
                              onPressed: () => _showEditDialog(context, ref, p),
                            )),
                          ]))
                      .toList(),
                ),
              ),
            )
                .animate()
                .slideY(begin: 0.1, duration: 400.ms, delay: 200.ms)
                .fadeIn(),
          ),
        ),
      ]),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    final emailC = TextEditingController(), passC = TextEditingController();
    final nameC = TextEditingController(), badgeC = TextEditingController();
    String role = 'officer';
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
                                      role: role);
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
                            role: role);
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

// ── Rules Tab ─────────────────────────────────────────────────

class _RulesTab extends ConsumerWidget {
  const _RulesTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(allRulesProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Customs Rules',
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
            label: const Text('Add Rule',
                style: TextStyle(fontWeight: FontWeight.w600)),
            onPressed: () => _showAddRuleDialog(context, ref),
          ),
        ]),
        const Gap(16),
        Expanded(
          child: rules.when(
            loading: () => Center(
                child: CircularProgressIndicator(
                    color: context.colors.primaryGold)),
            error: (e, _) => ErrorView(
                error: e, onRetry: () => ref.refresh(allRulesProvider)),
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
                  isHorizontalScrollBarVisible: false,
                  dataRowColor: WidgetStateProperty.all(Colors.transparent),
                  headingRowColor:
                      WidgetStateProperty.all(context.colors.surfaceDark),
                  columns: [
                    DataColumn2(
                        label: Text('Rule Name',
                            style: TextStyle(
                                color: context.colors.primaryGold,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        size: ColumnSize.L),
                    DataColumn2(
                        label: Text('Type',
                            style: TextStyle(
                                color: context.colors.primaryGold,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        size: ColumnSize.S,
                        fixedWidth: 120),
                    DataColumn2(
                        label: Text('Threshold',
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
                        label: Text('Active',
                            style: TextStyle(
                                color: context.colors.primaryGold,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        size: ColumnSize.S,
                        fixedWidth: 100),
                    DataColumn2(
                        label: Text('Del',
                            style: TextStyle(
                                color: context.colors.primaryGold,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        size: ColumnSize.S,
                        fixedWidth: 80),
                  ],
                  rows: list
                      .map((r) => DataRow(cells: [
                            DataCell(Text(r.ruleName,
                                style: TextStyle(
                                    color: context.colors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13))),
                            DataCell(_RuleTypeChip(type: r.ruleType)),
                            DataCell(Text(
                                r.thresholdValue?.toString() ??
                                    r.stringValue ??
                                    '—',
                                style: TextStyle(
                                    color: context.colors.accentLightBlue,
                                    fontSize: 13))),
                            DataCell(Text(r.description ?? '—',
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: TextStyle(
                                    color: context.colors.textMuted,
                                    fontSize: 12))),
                            DataCell(_StatusToggle(
                              isActive: r.isActive,
                              onChanged: (v) async {
                                await ref
                                    .read(customsRulesServiceProvider)
                                    .toggleRule(r.id, v);
                                ref.invalidate(allRulesProvider);
                              },
                              label: 'Rule "${r.ruleName}"',
                            )),
                            DataCell(IconButton(
                              icon: Icon(Icons.delete_outline_rounded,
                                  color: context.colors.dangerRed, size: 18),
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                          title: const Text('Delete Rule'),
                                          content:
                                              Text('Delete "${r.ruleName}"?'),
                                          actions: [
                                            TextButton(
                                                onPressed: () => Navigator.pop(
                                                    context, false),
                                                child: const Text('Cancel')),
                                            ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                    backgroundColor: context
                                                        .colors.dangerRed,
                                                    foregroundColor:
                                                        Colors.white),
                                                onPressed: () => Navigator.pop(
                                                    context, true),
                                                child: const Text('Delete')),
                                          ],
                                        ));
                                if (ok == true) {
                                  await ref
                                      .read(customsRulesServiceProvider)
                                      .deleteRule(r.id);
                                  ref.invalidate(allRulesProvider);
                                }
                              },
                            )),
                          ]))
                      .toList(),
                ),
              ),
            )
                .animate()
                .slideY(begin: 0.1, duration: 400.ms, delay: 200.ms)
                .fadeIn(),
          ),
        ),
      ]),
    );
  }

  void _showAddRuleDialog(BuildContext context, WidgetRef ref) {
    final nameC = TextEditingController(), descC = TextEditingController();
    final thresholdC = TextEditingController(),
        stringC = TextEditingController();
    String type = 'max_value';
    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
              builder: (ctx, setState) => AlertDialog(
                title: const Text('Add Customs Rule'),
                content: SizedBox(
                    width: 420,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: nameC,
                          decoration:
                              const InputDecoration(labelText: 'Rule Name *')),
                      const Gap(12),
                      DropdownButtonFormField<String>(
                        value: type,
                        decoration: const InputDecoration(labelText: 'Type'),
                        items: const [
                          DropdownMenuItem(
                              value: 'max_value',
                              child: Text('Max Declared Value')),
                          DropdownMenuItem(
                              value: 'max_weight', child: Text('Max Weight')),
                          DropdownMenuItem(
                              value: 'max_items',
                              child: Text('Max Item Count')),
                          DropdownMenuItem(
                              value: 'prohibited_category',
                              child: Text('Prohibited Category')),
                        ],
                        onChanged: (v) => setState(() => type = v!),
                      ),
                      const Gap(12),
                      type == 'prohibited_category'
                          ? TextField(
                              controller: stringC,
                              decoration: const InputDecoration(
                                  labelText: 'Category Keyword',
                                  hintText: 'e.g. firearms'))
                          : TextField(
                              controller: thresholdC,
                              decoration: const InputDecoration(
                                  labelText: 'Threshold Value'),
                              keyboardType: TextInputType.number),
                      const Gap(12),
                      TextField(
                          controller: descC,
                          decoration:
                              const InputDecoration(labelText: 'Description'),
                          maxLines: 2),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                  ElevatedButton(
                      onPressed: () async {
                        await ref
                            .read(customsRulesServiceProvider)
                            .createRule(CustomsRule(
                              id: '',
                              ruleName: nameC.text.trim(),
                              ruleType: type,
                              thresholdValue: type != 'prohibited_category'
                                  ? double.tryParse(thresholdC.text)
                                  : null,
                              stringValue: type == 'prohibited_category'
                                  ? stringC.text.trim()
                                  : null,
                              isActive: true,
                              description: descC.text.trim(),
                            ));
                        ref.invalidate(allRulesProvider);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: const Text('Add Rule')),
                ],
              ),
            ));
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

// ── Categories Tab ──────────────────────────────────────────────

class _CategoriesTab extends ConsumerWidget {
  const _CategoriesTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                        label: Text('Description',
                            style: TextStyle(
                                color: context.colors.primaryGold,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        size: ColumnSize.L),
                    DataColumn2(
                        label: Text('Warehouse/Zone',
                            style: TextStyle(
                                color: context.colors.primaryGold,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        size: ColumnSize.L),
                    DataColumn2(
                        label: Text('Created At',
                            style: TextStyle(
                                color: context.colors.primaryGold,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        size: ColumnSize.M,
                        fixedWidth: 150),
                    DataColumn2(
                        label: Text('Actions',
                            style: TextStyle(
                                color: context.colors.primaryGold,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        size: ColumnSize.S,
                        fixedWidth: 120),
                  ],
                  rows: list
                      .map((c) => DataRow(cells: [
                            DataCell(Text(c.name,
                                style: TextStyle(
                                    color: context.colors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13))),
                            DataCell(Text(c.description ?? '—',
                                style: TextStyle(
                                    color: context.colors.textMuted,
                                    fontSize: 12))),
                            DataCell(Text(
                                '${c.targetWarehouseName ?? '—'} ${c.targetZone != null ? '(Zone: ${c.targetZone})' : ''}',
                                style: TextStyle(
                                    color: context.colors.textMuted,
                                    fontSize: 12))),
                            DataCell(Text(
                                DateFormat('dd/MM/yy HH:mm')
                                    .format(c.createdAt),
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
                                  onPressed: () =>
                                      _showEditCategoryDialog(context, ref, c),
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
                                              title:
                                                  const Text('Delete Category'),
                                              content:
                                                  Text('Delete "${c.name}"?'),
                                              actions: [
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            context, false),
                                                    child:
                                                        const Text('Cancel')),
                                                ElevatedButton(
                                                    style: ElevatedButton
                                                        .styleFrom(
                                                            backgroundColor:
                                                                context.colors
                                                                    .dangerRed,
                                                            foregroundColor:
                                                                Colors.white),
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            context, true),
                                                    child:
                                                        const Text('Delete')),
                                              ],
                                            ));
                                    if (ok == true) {
                                      await ref
                                          .read(packageCategoryServiceProvider)
                                          .deleteCategory(c.id);
                                      ref.invalidate(packageCategoriesProvider);
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
                .fadeIn(),
          ),
        ),
      ]),
    );
  }

  void _showAddCategoryDialog(BuildContext context, WidgetRef ref) {
    final nameC = TextEditingController(), descC = TextEditingController();
    String? selectedWarehouseId;
    String? selectedZone;
    final List<String> availableZones =
        List.generate(10, (index) => '${index + 1}');

    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
              final warehouses = ref.watch(warehousesProvider);
              return AlertDialog(
                title: const Text('Add Package Category'),
                content: SizedBox(
                  width: 600,
                  child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: nameC,
                          decoration: const InputDecoration(
                              labelText: 'Category Name *')),
                      const Gap(16),
                      TextField(
                          controller: descC,
                          decoration:
                              const InputDecoration(labelText: 'Description'),
                          maxLines: 3),
                      const Gap(16),
                      warehouses.when(
                        data: (list) => DropdownButtonFormField<String>(
                          value: selectedWarehouseId,
                          decoration: const InputDecoration(
                              labelText: 'Target Warehouse (Auto-assign)',
                              isDense: true),
                          items: [
                            const DropdownMenuItem(
                                value: null,
                                child: Text('None: Do not auto-assign')),
                            ...list.map((w) => DropdownMenuItem(
                                value: w.id, child: Text(w.name)))
                          ],
                          onChanged: (v) => setState(() {
                            selectedWarehouseId = v;
                            if (v == null) selectedZone = null;
                          }),
                        ),
                        loading: () => const CircularProgressIndicator(),
                        error: (e, _) => Text('Error: $e'),
                      ),
                      const Gap(16),
                      if (selectedWarehouseId != null)
                        DropdownButtonFormField<String>(
                          value: selectedZone,
                          decoration: const InputDecoration(
                              labelText: 'Target Zone', isDense: true),
                          items: [
                            const DropdownMenuItem(
                                value: null, child: Text('None')),
                            ...availableZones.map((z) => DropdownMenuItem(
                                value: z, child: Text('Zone $z')))
                          ],
                          onChanged: (v) => setState(() => selectedZone = v),
                        ),
                    ]),
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child:
                          const Text('Cancel', style: TextStyle(fontSize: 16))),
                  ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
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
                      },
                      child: const Text('Add Category',
                          style: TextStyle(fontSize: 16))),
                ],
              );
            }));
  }

  void _showEditCategoryDialog(
      BuildContext context, WidgetRef ref, PackageCategory category) {
    final nameC = TextEditingController(text: category.name);
    final descC = TextEditingController(text: category.description);
    String? selectedWarehouseId = category.targetWarehouseId;
    String? selectedZone = category.targetZone?.replaceAll('Zone ', '');
    final List<String> availableZones =
        List.generate(10, (index) => '${index + 1}');

    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
              final warehouses = ref.watch(warehousesProvider);
              return AlertDialog(
                title: const Text('Edit Package Category'),
                content: SizedBox(
                  width: 600,
                  child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: nameC,
                          decoration: const InputDecoration(
                              labelText: 'Category Name *')),
                      const Gap(16),
                      TextField(
                          controller: descC,
                          decoration:
                              const InputDecoration(labelText: 'Description'),
                          maxLines: 3),
                      const Gap(16),
                      warehouses.when(
                        data: (list) => DropdownButtonFormField<String>(
                          value: list.any((w) => w.id == selectedWarehouseId)
                              ? selectedWarehouseId
                              : null,
                          decoration: const InputDecoration(
                              labelText: 'Target Warehouse (Auto-assign)',
                              isDense: true),
                          items: [
                            const DropdownMenuItem(
                                value: null,
                                child: Text('None: Do not auto-assign')),
                            ...list.map((w) => DropdownMenuItem(
                                value: w.id, child: Text(w.name)))
                          ],
                          onChanged: (v) => setState(() {
                            selectedWarehouseId = v;
                            if (v == null) selectedZone = null;
                          }),
                        ),
                        loading: () => const CircularProgressIndicator(),
                        error: (e, _) => Text('Error: $e'),
                      ),
                      const Gap(16),
                      if (selectedWarehouseId != null)
                        DropdownButtonFormField<String>(
                          value: availableZones.contains(selectedZone)
                              ? selectedZone
                              : null,
                          decoration: const InputDecoration(
                              labelText: 'Target Zone', isDense: true),
                          items: [
                            const DropdownMenuItem(
                                value: null, child: Text('None')),
                            ...availableZones.map((z) => DropdownMenuItem(
                                value: z, child: Text('Zone $z')))
                          ],
                          onChanged: (v) => setState(() => selectedZone = v),
                        ),
                    ]),
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child:
                          const Text('Cancel', style: TextStyle(fontSize: 16))),
                  ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
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
                      },
                      child: const Text('Save Changes',
                          style: TextStyle(fontSize: 16))),
                ],
              );
            }));
  }
}

// ── Logs Tab ──────────────────────────────────────────────────

class _LogsTab extends ConsumerWidget {
  const _LogsTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  isHorizontalScrollBarVisible: false, // No horizontal scroll
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
                  rows: list.map((l) {
                    final timeStr =
                        '${l.createdAt.hour}:${l.createdAt.minute.toString().padLeft(2, '0')} ${l.createdAt.day}/${l.createdAt.month}';
                    return DataRow(cells: [
                      DataCell(Text(timeStr,
                          style: TextStyle(
                              color: context.colors.textMuted, fontSize: 13))),
                      DataCell(Text(l.userFullName ?? 'Unknown',
                          style: TextStyle(
                              color: context.colors.textPrimary,
                              fontWeight: FontWeight.w600))),
                      DataCell(Text(l.action,
                          style: TextStyle(
                              color: context.colors.accentLightBlue))),
                      DataCell(Text(l.entityType.toUpperCase(),
                          style: TextStyle(
                              color: context.colors.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700))),
                      DataCell(Text(l.details?.toString() ?? '—',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: TextStyle(
                              color: context.colors.textMuted, fontSize: 12))),
                    ]);
                  }).toList(),
                ),
              ),
            )
                .animate()
                .slideY(begin: 0.1, duration: 400.ms, delay: 200.ms)
                .fadeIn(),
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rate = ref.read(storageRateProvider).valueOrNull ?? 0;
      _chargeCtrl.text = rate.toString();
    });
  }

  @override
  void dispose() {
    _chargeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final rate = double.tryParse(_chargeCtrl.text) ?? 0;
    setState(() => _loading = true);
    try {
      await ref.read(customsRulesServiceProvider).updateStorageRate(rate);
      ref.invalidate(storageRateProvider);
      ref.invalidate(storageRateHistoryProvider);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Settings updated successfully'),
            backgroundColor: context.colors.successGreen));
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
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left side - Form
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Storage Rates & Charges',
                    style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w700)),
                const Gap(24),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                      color: context.colors.cardDark,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: context.colors.borderColor)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.warehouse_rounded,
                              color: context.colors.primaryGold, size: 20),
                          const Gap(10),
                          Text('Warehouse Storage Charges',
                              style: TextStyle(
                                  color: context.colors.primaryGold,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16)),
                        ]),
                        const Gap(12),
                        Text(
                            'Set the daily storage fee per package. This rate is used to calculate the total cost for held items (excluding confiscated goods).',
                            style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 13)),
                        const Gap(24),
                        TextField(
                          controller: _chargeCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: TextStyle(color: context.colors.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Daily Charge Rate (LKR)',
                            prefixText: 'LKR ',
                            helperText: 'e.g. 150.00',
                            filled: true,
                            fillColor:
                                context.colors.surfaceDark.withOpacity(0.5),
                          ),
                        ),
                        const Gap(32),
                        ElevatedButton(
                          onPressed: _loading ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.colors.primaryGold,
                            foregroundColor: context.colors.primaryNavy,
                            minimumSize: const Size(double.infinity, 54),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.black))
                              : const Text('Save Settings',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15)),
                        ),
                      ]),
                ),
              ],
            ),
          ),
          const Gap(40),
          // Right side - History
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Charge Rate History',
                    style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                const Gap(16),
                Expanded(
                  child: ref.watch(storageRateHistoryProvider).when(
                        loading: () => Center(
                            child: CircularProgressIndicator(
                                color: context.colors.primaryGold)),
                        error: (e, _) => ErrorView(
                            error: e,
                            onRetry: () =>
                                ref.refresh(storageRateHistoryProvider)),
                        data: (history) => history.isEmpty
                            ? Center(
                                child: Text('No charge history found',
                                    style: TextStyle(
                                        color: context.colors.textMuted)))
                            : Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                    color: context.colors.cardDark,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                        color: context.colors.borderColor)),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: DataTable2(
                                    headingRowColor: WidgetStateProperty.all(
                                        context.colors.surfaceDark),
                                    columns: [
                                      DataColumn2(
                                          label: Text('Date & Time',
                                              style: TextStyle(
                                                  color: context
                                                      .colors.primaryGold,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13)),
                                          size: ColumnSize.M),
                                      DataColumn2(
                                          label: Text('Officer/Admin',
                                              style: TextStyle(
                                                  color: context
                                                      .colors.primaryGold,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13)),
                                          size: ColumnSize.L),
                                      DataColumn2(
                                          label: Text('Action / Value Change',
                                              style: TextStyle(
                                                  color: context
                                                      .colors.primaryGold,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13)),
                                          size: ColumnSize.L),
                                    ],
                                    rows: history
                                        .map((h) => DataRow(cells: [
                                              DataCell(Text(
                                                  DateFormat(
                                                          'dd MMM yyyy, HH:mm')
                                                      .format(h.createdAt),
                                                  style: TextStyle(
                                                      color: context
                                                          .colors.textMuted,
                                                      fontSize: 13))),
                                              DataCell(Text(
                                                  h.userFullName ?? 'System',
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600))),
                                              DataCell(Text(h.action,
                                                  style: TextStyle(
                                                      color: context
                                                          .colors.primaryGold,
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
          ),
        ],
      ),
    );
  }
}

// ── Hold Reasons Tab ──────────────────────────────────────────

class _HoldReasonsTab extends ConsumerWidget {
  const _HoldReasonsTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reasons = ref.watch(holdReasonsProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Hold Reasons',
              style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700)),
          const Spacer(),
          ElevatedButton.icon(
              onPressed: () => _showAddReasonDialog(context, ref),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Reason')),
        ]),
        const Gap(16),
        Expanded(
          child: reasons.when(
            loading: () => Center(
                child: CircularProgressIndicator(
                    color: context.colors.primaryGold)),
            error: (e, _) => Center(
                child: Text('Error: $e',
                    style: TextStyle(color: context.colors.dangerRed))),
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
                  headingRowColor:
                      WidgetStateProperty.all(context.colors.surfaceDark),
                  columns: [
                    DataColumn2(
                        label: Text('Reason Text',
                            style: TextStyle(
                                color: context.colors.primaryGold,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        size: ColumnSize.M),
                    DataColumn2(
                        label: Text('Description',
                            style: TextStyle(
                                color: context.colors.primaryGold,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        size: ColumnSize.L),
                    DataColumn2(
                        label: Text('Active',
                            style: TextStyle(
                                color: context.colors.primaryGold,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        size: ColumnSize.S,
                        fixedWidth: 100),
                    DataColumn2(
                        label: Text('Actions',
                            style: TextStyle(
                                color: context.colors.primaryGold,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        size: ColumnSize.S,
                        fixedWidth: 100),
                  ],
                  rows: list
                      .map((r) => DataRow(cells: [
                            DataCell(Text(r.reasonText,
                                style: TextStyle(
                                    color: context.colors.textPrimary,
                                    fontWeight: FontWeight.w500))),
                            DataCell(Text(r.description ?? '—',
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: TextStyle(
                                    color: context.colors.textMuted,
                                    fontSize: 12))),
                            DataCell(_StatusToggle(
                              isActive: r.isActive,
                              onChanged: (v) async {
                                await ref
                                    .read(holdReasonServiceProvider)
                                    .toggleReasonActive(r.id, v);
                                ref.invalidate(holdReasonsProvider);
                              },
                              label: 'Reason "${r.reasonText}"',
                            )),
                            DataCell(Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.edit_rounded,
                                      color: context.colors.primaryGold,
                                      size: 18),
                                  onPressed: () =>
                                      _showEditReasonDialog(context, ref, r),
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete_outline_rounded,
                                      color: context.colors.dangerRed,
                                      size: 18),
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                              title:
                                                  const Text('Delete Reason?'),
                                              content: Text(
                                                  'Delete "${r.reasonText}"?'),
                                              actions: [
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            context, false),
                                                    child:
                                                        const Text('Cancel')),
                                                ElevatedButton(
                                                    style: ElevatedButton
                                                        .styleFrom(
                                                            backgroundColor:
                                                                context.colors
                                                                    .dangerRed,
                                                            foregroundColor:
                                                                Colors.white),
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            context, true),
                                                    child:
                                                        const Text('Delete')),
                                              ],
                                            ));
                                    if (ok == true) {
                                      await ref
                                          .read(holdReasonServiceProvider)
                                          .deleteReason(r.id);
                                      ref.invalidate(holdReasonsProvider);
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
                .fadeIn(),
          ),
        ),
      ]),
    );
  }

  void _showAddReasonDialog(BuildContext context, WidgetRef ref) {
    final nameC = TextEditingController();
    final descC = TextEditingController();
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Add Hold Reason'),
              content: SizedBox(
                  width: 420,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        controller: nameC,
                        decoration:
                            const InputDecoration(labelText: 'Reason Text *')),
                    const Gap(12),
                    TextField(
                        controller: descC,
                        decoration:
                            const InputDecoration(labelText: 'Description'),
                        maxLines: 2),
                  ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel')),
                ElevatedButton(
                    onPressed: () async {
                      if (nameC.text.trim().isEmpty) return;
                      await ref.read(holdReasonServiceProvider).addReason(
                          nameC.text.trim(),
                          descC.text.trim().isEmpty ? null : descC.text.trim());
                      ref.invalidate(holdReasonsProvider);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Add Reason')),
              ],
            ));
  }

  void _showEditReasonDialog(
      BuildContext context, WidgetRef ref, HoldReasonModel reason) {
    final nameC = TextEditingController(text: reason.reasonText);
    final descC = TextEditingController(text: reason.description);
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Edit Hold Reason'),
              content: SizedBox(
                  width: 420,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        controller: nameC,
                        decoration:
                            const InputDecoration(labelText: 'Reason Text *')),
                    const Gap(12),
                    TextField(
                        controller: descC,
                        decoration:
                            const InputDecoration(labelText: 'Description'),
                        maxLines: 2),
                  ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel')),
                ElevatedButton(
                    onPressed: () async {
                      if (nameC.text.trim().isEmpty) return;
                      await ref.read(holdReasonServiceProvider).updateReason(
                          reason.id,
                          nameC.text.trim(),
                          descC.text.trim().isEmpty ? null : descC.text.trim());
                      ref.invalidate(holdReasonsProvider);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Save Changes')),
              ],
            ));
  }
}
