import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import '../../core/theme.dart';
import '../../services/services.dart';
import '../../models/models.dart';
import '../../widgets/app_shell.dart';

final allProfilesProvider = FutureProvider<List<ProfileModel>>((ref) async {
  return ref.read(adminServiceProvider).getAllProfiles();
});
final allRulesProvider = FutureProvider<List<CustomsRule>>((ref) async {
  return ref.read(customsRulesServiceProvider).getAllRules();
});

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppShell(
      currentRoute: '/admin/panel',
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: AppTheme.scaffoldBg,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Admin Panel', style: Theme.of(context).textTheme.headlineLarge),
                  const Text('Manage officers, customs rules and system configuration',
                      style: TextStyle(color: AppTheme.textSecondary)),
                  const Gap(20),
                  Container(
                    decoration: BoxDecoration(color: AppTheme.cardDark, borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.borderColor)),
                    child: const TabBar(
                      tabs: [
                        Tab(icon: Icon(Icons.people_rounded), text: 'Officers'),
                        Tab(icon: Icon(Icons.gavel_rounded), text: 'Customs Rules'),
                      ],
                      dividerColor: Colors.transparent,
                    ),
                  ),
                ]),
              ),
              const Gap(4),
              const Expanded(child: TabBarView(children: [_OfficersTab(), _RulesTab()])),
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
          Text('Officers & Admins', style: Theme.of(context).textTheme.titleLarge),
          ElevatedButton.icon(
            icon: const Icon(Icons.person_add_rounded, size: 18),
            label: const Text('Add Officer'),
            onPressed: () => _showAddDialog(context, ref),
          ),
        ]),
        const Gap(16),
        Expanded(
          child: profiles.when(
            loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primaryGold)),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (list) => Container(
              decoration: BoxDecoration(color: AppTheme.cardDark, borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.borderColor)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SingleChildScrollView(
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Name')),
                      DataColumn(label: Text('Salary No')),
                      DataColumn(label: Text('Role')),
                      DataColumn(label: Text('Active')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: list.map((p) => DataRow(cells: [
                      DataCell(Text(p.fullName, style: const TextStyle(fontWeight: FontWeight.w600))),
                      DataCell(Text(p.badgeNumber ?? '—', style: const TextStyle(color: AppTheme.textMuted))),
                      DataCell(_RoleChip(role: p.role)),
                      DataCell(Switch(value: p.isActive, activeColor: AppTheme.successGreen,
                          onChanged: (v) async {
                            await ref.read(adminServiceProvider).toggleUserStatus(p.id, v);
                            ref.invalidate(allProfilesProvider);
                          })),
                      DataCell(IconButton(
                        icon: const Icon(Icons.edit_outlined, color: AppTheme.accentLightBlue, size: 18),
                        onPressed: () => _showEditDialog(context, ref, p),
                      )),
                    ])).toList(),
                  ),
                ),
              ),
            ),
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
              setState(() => loading = true);
              try {
                await ref.read(adminServiceProvider).createOfficer(
                  email: emailC.text.trim(), password: passC.text,
                  fullName: nameC.text.trim(), badgeNumber: badgeC.text.trim(), role: role);
                ref.invalidate(allProfilesProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.dangerRed));
              } finally { setState(() => loading = false); }
            },
            child: loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryNavy))
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
        color: isAdmin ? AppTheme.primaryGold.withOpacity(0.15) : AppTheme.accentBlue.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isAdmin ? AppTheme.primaryGold.withOpacity(0.4) : AppTheme.accentBlue.withOpacity(0.4)),
      ),
      child: Text(role.toUpperCase(), style: TextStyle(
          color: isAdmin ? AppTheme.primaryGold : AppTheme.accentLightBlue, fontSize: 11, fontWeight: FontWeight.w700)),
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
          Text('Customs Rules', style: Theme.of(context).textTheme.titleLarge),
          ElevatedButton.icon(
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Rule'),
            onPressed: () => _showAddRuleDialog(context, ref),
          ),
        ]),
        const Gap(16),
        Expanded(
          child: rules.when(
            loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primaryGold)),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (list) => Container(
              decoration: BoxDecoration(color: AppTheme.cardDark, borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.borderColor)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SingleChildScrollView(
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Rule Name')),
                      DataColumn(label: Text('Type')),
                      DataColumn(label: Text('Threshold')),
                      DataColumn(label: Text('Description')),
                      DataColumn(label: Text('Active')),
                      DataColumn(label: Text('Del')),
                    ],
                    rows: list.map((r) => DataRow(cells: [
                      DataCell(Text(r.ruleName, style: const TextStyle(fontWeight: FontWeight.w600))),
                      DataCell(_RuleTypeChip(type: r.ruleType)),
                      DataCell(Text(r.thresholdValue?.toString() ?? r.stringValue ?? '—',
                          style: const TextStyle(color: AppTheme.accentLightBlue))),
                      DataCell(SizedBox(width: 180, child: Text(r.description ?? '—',
                          overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)))),
                      DataCell(Switch(value: r.isActive, activeColor: AppTheme.successGreen,
                          onChanged: (v) async {
                            await ref.read(customsRulesServiceProvider).toggleRule(r.id, v);
                            ref.invalidate(allRulesProvider);
                          })),
                      DataCell(IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.dangerRed, size: 18),
                        onPressed: () async {
                          final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
                            title: const Text('Delete Rule'),
                            content: Text('Delete "${r.ruleName}"?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                              ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRed, foregroundColor: Colors.white),
                                  onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                            ],
                          ));
                          if (ok == true) { await ref.read(customsRulesServiceProvider).deleteRule(r.id); ref.invalidate(allRulesProvider); }
                        },
                      )),
                    ])).toList(),
                  ),
                ),
              ),
            ),
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
      case 'max_value': color = AppTheme.warningAmber; label = 'MAX VALUE'; break;
      case 'max_weight': color = AppTheme.accentLightBlue; label = 'MAX WEIGHT'; break;
      case 'max_items': color = AppTheme.primaryGold; label = 'MAX ITEMS'; break;
      case 'prohibited_category': color = AppTheme.dangerRed; label = 'PROHIBITED'; break;
      default: color = AppTheme.textMuted; label = 'CUSTOM';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(5),
          border: Border.all(color: color.withOpacity(0.35))),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}
