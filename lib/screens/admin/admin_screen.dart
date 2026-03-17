import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../services/services.dart';
import '../../models/models.dart';
import '../../widgets/app_shell.dart';
import 'package:data_table_2/data_table_2.dart';

class AdminScreen extends ConsumerWidget {
  final int initialIndex;
  const AdminScreen({super.key, this.initialIndex = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppShell(
      currentRoute: '/admin/panel',
      child: DefaultTabController(
        length: 3,
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
                        Text('Admin Panel', style: Theme.of(context).textTheme.headlineLarge),
                        Text('Manage officers, customs rules and system configuration',
                            style: TextStyle(color: context.colors.textSecondary)),
                      ],
                    ).animate().fadeIn(),
                    const Gap(20),
                    Container(
                      decoration: BoxDecoration(color: context.colors.cardDark, borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: context.colors.borderColor)),
                      child: TabBar(
                        labelColor: context.colors.primaryGold,
                        unselectedLabelColor: context.colors.textMuted,
                        indicatorColor: context.colors.primaryGold,
                        tabs: const [
                          Tab(icon: Icon(Icons.people_rounded), text: 'Officers'),
                          Tab(icon: Icon(Icons.gavel_rounded), text: 'Customs Rules'),
                          Tab(icon: Icon(Icons.history_toggle_off_rounded), text: 'Activity Logs'),
                        ],
                        dividerColor: Colors.transparent,
                      ),
                    ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 100.ms).fadeIn(),
                  ],
                ),
              ),
              const Gap(4),
              const Expanded(child: TabBarView(children: [_OfficersTab(), _RulesTab(), _LogsTab()])),
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
          Text('Officers & Admins', style: TextStyle(color: context.colors.textPrimary, fontSize: 24, fontWeight: FontWeight.w700)),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colors.primaryGold,
              foregroundColor: context.colors.primaryNavy,
            ),
            icon: const Icon(Icons.person_add_rounded, size: 18),
            label: const Text('Add Officer', style: TextStyle(fontWeight: FontWeight.w600)),
            onPressed: () => _showAddDialog(context, ref),
          ),
        ]),
        const Gap(16),
        Expanded(
          child: profiles.when(
            loading: () => Center(child: CircularProgressIndicator(color: context.colors.primaryGold)),
            error: (e, _) => Center(child: Text('Error: $e', style: TextStyle(color: context.colors.dangerRed))),
            data: (list) => Container(
              width: double.infinity,
              decoration: BoxDecoration(color: context.colors.cardDark, borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.colors.borderColor)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: DataTable2(
                  horizontalMargin: 24,
                  columnSpacing: 20,
                  fixedTopRows: 1,
                  isHorizontalScrollBarVisible: false,
                  dataRowColor: WidgetStateProperty.all(Colors.transparent),
                  headingRowColor: WidgetStateProperty.all(context.colors.surfaceDark),
                  columns: [
                    DataColumn2(label: Text('Name', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.w700, fontSize: 13)), size: ColumnSize.L),
                    DataColumn2(label: Text('Salary No', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.w700, fontSize: 13)), size: ColumnSize.M),
                    DataColumn2(label: Text('Role', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.w700, fontSize: 13)), size: ColumnSize.S, fixedWidth: 100),
                    DataColumn2(label: Text('Active', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.w700, fontSize: 13)), size: ColumnSize.S, fixedWidth: 100),
                    DataColumn2(label: Text('Actions', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.w700, fontSize: 13)), size: ColumnSize.S, fixedWidth: 80),
                  ],
                  rows: list.map((p) => DataRow(cells: [
                    DataCell(Text(p.fullName, style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13))),
                    DataCell(Text(p.badgeNumber ?? '—', style: TextStyle(color: context.colors.textMuted, fontSize: 13))),
                    DataCell(_RoleChip(role: p.role)),
                    DataCell(
                      _StatusToggle(
                        isActive: p.isActive,
                        onChanged: (v) async {
                          final currentProfile = ref.read(currentProfileProvider);
                          if (v == false && currentProfile?.id == p.id) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('You cannot deactivate your own account!'), 
                                backgroundColor: Colors.orange, duration: Duration(seconds: 2)));
                            }
                            return;
                          }
                          await ref.read(adminServiceProvider).toggleUserStatus(p.id, v);
                          ref.invalidate(allProfilesProvider);
                        },
                        label: p.fullName,
                      )
                    ),
                    DataCell(IconButton(
                      icon: Icon(Icons.edit_outlined, color: context.colors.accentLightBlue, size: 18),
                      onPressed: () => _showEditDialog(context, ref, p),
                    )),
                  ])).toList(),
                ),
              ),
            ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 200.ms).fadeIn(),
          ),
        ),
      ]),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    final emailC = TextEditingController(), passC = TextEditingController();
    final nameC = TextEditingController(), badgeC = TextEditingController();
    String role = 'officer'; bool loading = false;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Add New Officer'),
        content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Full Name *')),
          const Gap(12),
          TextField(controller: badgeC, decoration: const InputDecoration(labelText: 'Salary Number')),
          const Gap(12),
          TextField(controller: emailC, decoration: const InputDecoration(labelText: 'Email *'), keyboardType: TextInputType.emailAddress),
          const Gap(12),
          TextField(controller: passC, decoration: const InputDecoration(labelText: 'Password *'), obscureText: true),
          const Gap(12),
          DropdownButtonFormField<String>(value: role,
            decoration: const InputDecoration(labelText: 'Role'),
            items: const [DropdownMenuItem(value: 'officer', child: Text('Officer')), DropdownMenuItem(value: 'admin', child: Text('Admin'))],
            onChanged: (v) => setState(() => role = v!),
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: loading ? null : () async {
              final email = emailC.text.trim();
              if (email.isEmpty || !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid email address'), backgroundColor: Colors.red));
                return;
              }
              setState(() => loading = true);
              try {
                await ref.read(adminServiceProvider).createOfficer(
                  email: email, password: passC.text,
                  fullName: nameC.text.trim(), badgeNumber: badgeC.text.trim(), role: role);
                ref.invalidate(allProfilesProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                final msg = _translateAuthError(e);
                if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(msg), backgroundColor: context.colors.dangerRed, duration: const Duration(seconds: 8)));
              } finally { setState(() => loading = false); }
            },
            child: loading
                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.primaryNavy))
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
    showDialog(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('Edit: ${p.fullName}'),
        content: SizedBox(width: 360, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Full Name')),
          const Gap(12),
          TextField(controller: badgeC, decoration: const InputDecoration(labelText: 'Salary Number')),
          const Gap(12),
          DropdownButtonFormField<String>(value: role,
            decoration: const InputDecoration(labelText: 'Role'),
            items: const [DropdownMenuItem(value: 'officer', child: Text('Officer')), DropdownMenuItem(value: 'admin', child: Text('Admin'))],
            onChanged: (v) => setState(() => role = v!),
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () async {
            await ref.read(adminServiceProvider).updateProfile(p.id, fullName: nameC.text.trim(), badgeNumber: badgeC.text.trim(), role: role);
            ref.invalidate(allProfilesProvider);
            if (ctx.mounted) Navigator.pop(ctx);
          }, child: const Text('Save')),
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
        color: isAdmin ? context.colors.primaryGold.withOpacity(0.15) : context.colors.accentBlue.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isAdmin ? context.colors.primaryGold.withOpacity(0.4) : context.colors.accentBlue.withOpacity(0.4)),
      ),
      child: Text(role.toUpperCase(), style: TextStyle(
          color: isAdmin ? context.colors.primaryGold : context.colors.accentLightBlue, fontSize: 11, fontWeight: FontWeight.w700)),
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
          Text('Customs Rules', style: TextStyle(color: context.colors.textPrimary, fontSize: 24, fontWeight: FontWeight.w700)),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colors.primaryGold,
              foregroundColor: context.colors.primaryNavy,
            ),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Rule', style: TextStyle(fontWeight: FontWeight.w600)),
            onPressed: () => _showAddRuleDialog(context, ref),
          ),
        ]),
        const Gap(16),
        Expanded(
          child: rules.when(
            loading: () => Center(child: CircularProgressIndicator(color: context.colors.primaryGold)),
            error: (e, _) => Center(child: Text('Error: $e', style: TextStyle(color: context.colors.dangerRed))),
            data: (list) => Container(
              width: double.infinity,
              decoration: BoxDecoration(color: context.colors.cardDark, borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.colors.borderColor)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: DataTable2(
                  horizontalMargin: 24,
                  columnSpacing: 20,
                  fixedTopRows: 1,
                  isHorizontalScrollBarVisible: false,
                  dataRowColor: WidgetStateProperty.all(Colors.transparent),
                  headingRowColor: WidgetStateProperty.all(context.colors.surfaceDark),
                  columns: [
                    DataColumn2(label: Text('Rule Name', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.w700, fontSize: 13)), size: ColumnSize.L),
                    DataColumn2(label: Text('Type', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.w700, fontSize: 13)), size: ColumnSize.S, fixedWidth: 120),
                    DataColumn2(label: Text('Threshold', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.w700, fontSize: 13)), size: ColumnSize.S, fixedWidth: 100),
                    DataColumn2(label: Text('Description', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.w700, fontSize: 13)), size: ColumnSize.L),
                    DataColumn2(label: Text('Active', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.w700, fontSize: 13)), size: ColumnSize.S, fixedWidth: 100),
                    DataColumn2(label: Text('Del', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.w700, fontSize: 13)), size: ColumnSize.S, fixedWidth: 80),
                  ],
                  rows: list.map((r) => DataRow(cells: [
                    DataCell(Text(r.ruleName, style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13))),
                    DataCell(_RuleTypeChip(type: r.ruleType)),
                    DataCell(Text(r.thresholdValue?.toString() ?? r.stringValue ?? '—',
                        style: TextStyle(color: context.colors.accentLightBlue, fontSize: 13))),
                    DataCell(Text(r.description ?? '—', overflow: TextOverflow.ellipsis, maxLines: 1,
                        style: TextStyle(color: context.colors.textMuted, fontSize: 12))),
                    DataCell(
                      _StatusToggle(
                        isActive: r.isActive,
                        onChanged: (v) async {
                          await ref.read(customsRulesServiceProvider).toggleRule(r.id, v);
                          ref.invalidate(allRulesProvider);
                        },
                        label: 'Rule "${r.ruleName}"',
                      )
                    ),
                    DataCell(IconButton(
                      icon: Icon(Icons.delete_outline_rounded, color: context.colors.dangerRed, size: 18),
                      onPressed: () async {
                        final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
                          title: const Text('Delete Rule'),
                          content: Text('Delete "${r.ruleName}"?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: context.colors.dangerRed, foregroundColor: Colors.white),
                                onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                          ],
                        ));
                        if (ok == true) { await ref.read(customsRulesServiceProvider).deleteRule(r.id); ref.invalidate(allRulesProvider); }
                      },
                    )),
                  ])).toList(),
                ),
              ),
            ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 200.ms).fadeIn(),
          ),
        ),
      ]),
    );
  }

  void _showAddRuleDialog(BuildContext context, WidgetRef ref) {
    final nameC = TextEditingController(), descC = TextEditingController();
    final thresholdC = TextEditingController(), stringC = TextEditingController();
    String type = 'max_value';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Add Customs Rule'),
        content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Rule Name *')),
          const Gap(12),
          DropdownButtonFormField<String>(value: type,
            decoration: const InputDecoration(labelText: 'Type'),
            items: const [
              DropdownMenuItem(value: 'max_value', child: Text('Max Declared Value')),
              DropdownMenuItem(value: 'max_weight', child: Text('Max Weight')),
              DropdownMenuItem(value: 'max_items', child: Text('Max Item Count')),
              DropdownMenuItem(value: 'prohibited_category', child: Text('Prohibited Category')),
            ],
            onChanged: (v) => setState(() => type = v!),
          ),
          const Gap(12),
          type == 'prohibited_category'
              ? TextField(controller: stringC, decoration: const InputDecoration(labelText: 'Category Keyword', hintText: 'e.g. firearms'))
              : TextField(controller: thresholdC, decoration: const InputDecoration(labelText: 'Threshold Value'), keyboardType: TextInputType.number),
          const Gap(12),
          TextField(controller: descC, decoration: const InputDecoration(labelText: 'Description'), maxLines: 2),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () async {
            await ref.read(customsRulesServiceProvider).createRule(CustomsRule(
              id: '', ruleName: nameC.text.trim(), ruleType: type,
              thresholdValue: type != 'prohibited_category' ? double.tryParse(thresholdC.text) : null,
              stringValue: type == 'prohibited_category' ? stringC.text.trim() : null,
              isActive: true, description: descC.text.trim(),
            ));
            ref.invalidate(allRulesProvider);
            if (ctx.mounted) Navigator.pop(ctx);
          }, child: const Text('Add Rule')),
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
    Color color; String label;
    switch (type) {
      case 'max_value': color = context.colors.warningAmber; label = 'MAX VALUE'; break;
      case 'max_weight': color = context.colors.accentLightBlue; label = 'MAX WEIGHT'; break;
      case 'max_items': color = context.colors.primaryGold; label = 'MAX ITEMS'; break;
      case 'prohibited_category': color = context.colors.dangerRed; label = 'PROHIBITED'; break;
      default: color = context.colors.textMuted; label = 'CUSTOM';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(5),
          border: Border.all(color: color.withOpacity(0.35))),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

String _translateAuthError(Object e) {
  final raw = e.toString().toLowerCase();
  
  if (raw.contains('rate_limit') || raw.contains('rate limit') || raw.contains('429')) {
    return 'Supabase Email Limit Reached! 🛑\n\nTo fix this:\n1. Open Supabase Dashboard\n2. Go to Authentication > Providers > Email\n3. Turn OFF "Confirm email"\n4. Save and try again.';
  }
  if (raw.contains('already registered') || raw.contains('user_already_exists')) {
    return 'This email is already registered. Try a different email.';
  }
  return 'Error: $e';
}

class _StatusToggle extends StatefulWidget {
  final bool isActive;
  final Future<void> Function(bool) onChanged;
  final String label;

  const _StatusToggle({required this.isActive, required this.onChanged, required this.label});

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
        DateTime.now().difference(_lastChangeTime!) < const Duration(milliseconds: 1500)) {
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed: $e'), backgroundColor: context.colors.dangerRed));
          }
        } finally {
          if (mounted) setState(() => _loading = false);
        }
      },
    );
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
        Text('Activity Logs', style: TextStyle(color: context.colors.textPrimary, fontSize: 24, fontWeight: FontWeight.w700)),
        const Gap(16),
        Expanded(
          child: logs.when(
            loading: () => Center(child: CircularProgressIndicator(color: context.colors.primaryGold)),
            error: (e, _) => Center(child: Text('Error: $e', style: TextStyle(color: context.colors.dangerRed))),
            data: (list) => Container(
              width: double.infinity,
              decoration: BoxDecoration(color: context.colors.cardDark, borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.colors.borderColor)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: DataTable2(
                  horizontalMargin: 24,
                  columnSpacing: 20,
                  fixedTopRows: 1,
                  isHorizontalScrollBarVisible: false, // No horizontal scroll
                  dataRowColor: WidgetStateProperty.all(Colors.transparent),
                  headingRowColor: WidgetStateProperty.all(context.colors.surfaceDark),
                  columns: [
                    DataColumn2(label: Text('Time', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.w700, fontSize: 13)), size: ColumnSize.S, fixedWidth: 140),
                    DataColumn2(label: Text('User', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.w700, fontSize: 13)), size: ColumnSize.M),
                    DataColumn2(label: Text('Action', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.w700, fontSize: 13)), size: ColumnSize.L),
                    DataColumn2(label: Text('Entity', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.w700, fontSize: 13)), size: ColumnSize.S, fixedWidth: 100),
                    DataColumn2(label: Text('Details', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.w700, fontSize: 13)), size: ColumnSize.L),
                  ],
                  rows: list.map((l) {
                    final timeStr = '${l.createdAt.hour}:${l.createdAt.minute.toString().padLeft(2, '0')} ${l.createdAt.day}/${l.createdAt.month}';
                    return DataRow(cells: [
                      DataCell(Text(timeStr, style: TextStyle(color: context.colors.textMuted, fontSize: 13))),
                      DataCell(Text(l.userFullName ?? 'Unknown', style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600))),
                      DataCell(Text(l.action, style: TextStyle(color: context.colors.accentLightBlue))),
                      DataCell(Text(l.entityType.toUpperCase(), style: TextStyle(color: context.colors.textMuted, fontSize: 11, fontWeight: FontWeight.w700))),
                      DataCell(Text(l.details?.toString() ?? '—', overflow: TextOverflow.ellipsis, maxLines: 1, 
                          style: TextStyle(color: context.colors.textMuted, fontSize: 12))),
                    ]);
                  }).toList(),
                ),
              ),
            ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 200.ms).fadeIn(),
          ),
        ),
      ]),
    );
  }
}
