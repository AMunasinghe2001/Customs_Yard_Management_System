import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../core/yards.dart';
import '../../models/models.dart';
import '../../widgets/error_view.dart';
import '../../widgets/empty_table_state.dart';
import '../../widgets/styled_form_dialog.dart';
import '../../widgets/styled_dropdown.dart';
import '../../widgets/tooltip_text.dart';
import '../../widgets/package_details_dialog.dart';
import 'package:intl/intl.dart';

String _cItemName(ForfeitedPackageModel f) {
  if (f.itemName != null) return f.itemName!;
  final items = f.packageDetails?.items ?? const [];
  if (items.isEmpty) return 'Multiple/Unspecified';
  if (items.length == 1) return items.first.itemName;
  return '${items.first.itemName} +${items.length - 1}';
}

/// Warehouse · zone the item currently sits in (latest entry).
String _committeeLocation(PackageModel? pkg, String? itemId) {
  if (pkg == null) return '—';
  var entries = itemId != null
      ? pkg.warehouseEntries.where((e) => e.packageItemId == itemId).toList()
      : <WarehouseEntryModel>[];
  if (entries.isEmpty) entries = [...pkg.warehouseEntries];
  if (entries.isEmpty) return '—';
  entries.sort((a, b) => b.admittedAt.compareTo(a.admittedAt));
  final w = entries.first;
  return (w.zone != null && w.zone!.isNotEmpty)
      ? '${w.warehouseName} · ${w.zone}'
      : w.warehouseName;
}

/// Small forfeit/source chip (Forfeit / Confiscated / …).
class _CommitteeSourceChip extends StatelessWidget {
  final String source;
  const _CommitteeSourceChip({required this.source});
  @override
  Widget build(BuildContext context) {
    final label = source.isEmpty
        ? 'Forfeit'
        : '${source[0].toUpperCase()}${source.substring(1)}';
    final c = AppTheme.appealPurple;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withOpacity(0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              color: c, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

/// Valuation cell: unit valuation × qty (matches the Central Disposal tables).
class _CommitteeValuationCell extends StatelessWidget {
  final ForfeitedPackageModel f;
  final int? qty;
  const _CommitteeValuationCell({required this.f, this.qty});
  @override
  Widget build(BuildContext context) {
    final unit = f.valuationCost;
    if (unit == null) {
      return Text('—', style: TextStyle(color: context.colors.textMuted));
    }
    final effQty = (qty != null && qty! > 0) ? qty! : 1;
    final fmt = NumberFormat('#,##0');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('LKR ${fmt.format(unit * effQty)}',
            style: TextStyle(
                color: context.colors.primaryGold,
                fontWeight: FontWeight.w700,
                fontSize: 12)),
        Text('@ ${fmt.format(unit)} × $effQty',
            style: TextStyle(color: context.colors.textMuted, fontSize: 10)),
      ],
    );
  }
}

final _committeeSearchProvider = StateProvider<String>((ref) => '');
final _committeeYardProvider = StateProvider<String?>((ref) => null); // null=all

/// DG Office tab: tender packages that have gone unsold >3 times (≥4 attempts).
/// The DG appoints a 5-member committee for each.
class TenderCommitteeTab extends ConsumerWidget {
  const TenderCommitteeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = AppTheme.executiveTeal;
    final async = ref.watch(committeeEligibleProvider);
    final committees =
        ref.watch(tenderCommitteesProvider).asData?.value ?? const {};
ල්

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Tender Committees',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const Gap(10),
            Expanded(
              child: Text(
                  'Packages unsold more than 3 times — appoint a 5-member committee',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(color: context.colors.textMuted, fontSize: 13)),
            ),
            const Gap(12),
            SizedBox(
              width: 300,
              child: TextField(
                onChanged: (v) =>
                    ref.read(_committeeSearchProvider.notifier).state = v,
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search SR / item / consignee…',
                  prefixIcon:
                      Icon(Icons.search_rounded, size: 20, color: accent),
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
            ),
            const Gap(12),
            _CommitteeYardFilter(
              value: yardFilter,
              onChanged: (v) =>
                  ref.read(_committeeYardProvider.notifier).state = v,
            ),
          ]).animate().fadeIn(duration: 300.ms),
          const Gap(16),
          Expanded(
            child: async.when(
              skipLoadingOnReload: true,
              loading: () =>
                  Center(child: CircularProgressIndicator(color: accent)),
              error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.refresh(committeeEligibleProvider)),
              data: (list) {
                var rows = list;
                if (yardFilter != null) {
                  rows = rows
                      .where((info) => info.forfeited.yard == yardFilter)
                      .toList();
                }
                if (q.isNotEmpty) {
                  rows = rows.where((info) {
                    final f = info.forfeited;
                    return f.srNumber.toLowerCase().contains(q) ||
                        f.consigneeName.toLowerCase().contains(q) ||
                        _cItemName(f).toLowerCase().contains(q);
                  }).toList();
                }
                return Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: context.colors.cardDark,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.colors.borderColor),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: DataTable2(
                      columnSpacing: 12,
                      horizontalMargin: 16,
                      fixedTopRows: 1,
                      minWidth: 1080,
                      empty: const EmptyTableState(
                          message:
                              'No packages unsold more than 3 times yet'),
                      headingRowColor:
                          WidgetStateProperty.all(context.colors.surfaceDark),
                      columns: const [
                        DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
                        DataColumn2(label: Text('Case No'), size: ColumnSize.S),
                        DataColumn2(label: Text('Item'), size: ColumnSize.M),
                        DataColumn2(
                            label: Center(child: Text('Source')),
                            size: ColumnSize.S),
                        DataColumn2(
                            label: Text('Qty'),
                            size: ColumnSize.S,
                            fixedWidth: 56),
                        DataColumn2(label: Text('Location'), size: ColumnSize.M),
                        DataColumn2(
                            label: Text('Valuation'),
                            size: ColumnSize.S,
                            fixedWidth: 112),
                        DataColumn2(
                            label: Center(child: Text('Times')),
                            size: ColumnSize.S,
                            fixedWidth: 70),
                        DataColumn2(
                            label: Center(child: Text('Committee')),
                            size: ColumnSize.S,
                            fixedWidth: 175),
                        DataColumn2(
                            label: Center(child: Text('Details')),
                            size: ColumnSize.S,
                            fixedWidth: 64),
                      ],
                      rows: rows.map((info) {
                        final f = info.forfeited;
                        final pkg = f.packageDetails;
                        final item = f.itemId != null
                            ? pkg?.items
                                .where((i) => i.id == f.itemId)
                                .firstOrNull
                            : null;
                        final qty = f.entryQty ?? item?.quantity;
                        final committee = committees[f.id];
                        final count = committee?.members.length ?? 0;
                        return DataRow(cells: [
                          DataCell(TooltipText(f.srNumber,
                              style: TextStyle(
                                  color: accent,
                                  fontWeight: FontWeight.w600))),
                          DataCell(TooltipText(pkg?.caseNumber ?? '—',
                              overflow: TextOverflow.ellipsis)),
                          DataCell(TooltipText(_cItemName(f),
                              overflow: TextOverflow.ellipsis)),
                          DataCell(Center(child: _CommitteeSourceChip(source: f.source))),
                          DataCell(TooltipText('${qty ?? '—'}')),
                          DataCell(TooltipText(_committeeLocation(pkg, f.itemId),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: context.colors.textSecondary,
                                  fontSize: 12))),
                          DataCell(_CommitteeValuationCell(f: f, qty: qty)),
                          DataCell(Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: context.colors.warningAmber
                                    .withOpacity(0.14),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: context.colors.warningAmber
                                        .withOpacity(0.4)),
                              ),
                              child: Text('${info.tenderCount}×',
                                  style: TextStyle(
                                      color: context.colors.warningAmber,
                                      fontWeight: FontWeight.w800)),
                            ),
                          )),
                          DataCell(Center(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                  backgroundColor: count > 0
                                      ? context.colors.successGreen
                                      : accent,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10),
                                  visualDensity: VisualDensity.compact),
                              icon: Icon(
                                  count > 0
                                      ? Icons.groups_rounded
                                      : Icons.group_add_rounded,
                                  size: 15),
                              label: Text(
                                  count > 0
                                      ? 'Committee ($count)'
                                      : 'Appoint',
                                  style: const TextStyle(fontSize: 12)),
                              onPressed: () => showDialog(
                                context: context,
                                builder: (_) => _CommitteeDialog(
                                    info: info, existing: committee),
                              ),
                            ),
                          )),
                          DataCell(Center(
                            child: IconButton(
                              icon: Icon(Icons.info_outline_rounded,
                                  color: context.colors.accentLightBlue,
                                  size: 18),
                              onPressed: pkg == null
                                  ? null
                                  : () => showDialog(
                                        context: context,
                                        builder: (_) => PackageDetailsDialog(
                                          package: pkg,
                                          storageRate: storageRate,
                                          headerAccentColor: accent,
                                          useLegacySummary: true,
                                          highlightItemId: f.itemId,
                                          yardLabel: yardName(f.yard),
                                          valuationUnitCost: f.valuationCost,
                                          valuationTotalCost:
                                              f.valuationCost != null
                                                  ? f.valuationCost! * (qty ?? 1)
                                                  : null,
                                          valuationQty: qty,
                                        ),
                                      ),
                            ),
                          )),
                        ]);
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Yard dropdown with "All Yards" — teal-accented styled menu (executive).
class _CommitteeYardFilter extends StatelessWidget {
  final String? value; // null = all
  final ValueChanged<String?> onChanged;
  const _CommitteeYardFilter({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.executiveTeal;
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: w));
    return SizedBox(
      width: 220,
      child: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme:
              Theme.of(context).inputDecorationTheme.copyWith(
                    filled: true,
                    fillColor: accent.withOpacity(0.06),
                    border: border(accent.withOpacity(0.4)),
                    enabledBorder: border(accent.withOpacity(0.4)),
                    focusedBorder: border(accent, 1.5),
                  ),
        ),
        child: StyledDropdownFormField<String>(
          value: value ?? '_all',
          label: 'Yard',
          helperText: null,
          isDense: true,
          menuWidth: 220,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          prefixIcon:
              Icon(Icons.warehouse_rounded, color: accent, size: 20),
          options: [
            const StyledDropdownOption('_all', 'All Yards'),
            for (final y in kYards) StyledDropdownOption(y.code, y.name),
          ],
          onChanged: (v) => onChanged((v == null || v == '_all') ? null : v),
        ),
      ),
    );
  }
}

/// Appoint / edit a 5-member committee for a package (name + designation each).
class _CommitteeDialog extends ConsumerStatefulWidget {
  final ReTenderSaleInfo info;
  final TenderCommitteeModel? existing;
  const _CommitteeDialog({required this.info, this.existing});
  @override
  ConsumerState<_CommitteeDialog> createState() => _CommitteeDialogState();
}

class _CommitteeDialogState extends ConsumerState<_CommitteeDialog> {
  static const _count = 5;
  late final List<TextEditingController> _names;
  late final List<TextEditingController> _desigs;
  late final List<TextEditingController> _salaries;
  final _noteCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing?.members ?? const <CommitteeMember>[];
    _names = List.generate(
        _count,
        (i) => TextEditingController(
            text: i < existing.length ? existing[i].name : ''));
    _desigs = List.generate(
        _count,
        (i) => TextEditingController(
            text: i < existing.length
                ? (existing[i].designation ?? '')
                : ''));
    _salaries = List.generate(
        _count,
        (i) => TextEditingController(
            text: i < existing.length ? (existing[i].salaryNo ?? '') : ''));
    _noteCtrl.text = widget.existing?.note ?? '';
  }

  @override
  void dispose() {
    for (final c in _names) {
      c.dispose();
    }
    for (final c in _desigs) {
      c.dispose();
    }
    for (final c in _salaries) {
      c.dispose();
    }
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final members = <CommitteeMember>[];
    for (var i = 0; i < _count; i++) {
      final name = _names[i].text.trim();
      if (name.isEmpty) continue;
      final d = _desigs[i].text.trim();
      final s = _salaries[i].text.trim();
      members.add(CommitteeMember(
          name: name,
          designation: d.isEmpty ? null : d,
          salaryNo: s.isEmpty ? null : s));
    }
    if (members.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Enter at least one member.'),
          backgroundColor: context.colors.dangerRed));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(disposalServiceProvider).saveTenderCommittee(
            widget.info.forfeited.id,
            members,
            note: _noteCtrl.text,
            yard: widget.info.forfeited.yard,
          );
      ref.invalidate(tenderCommitteesProvider);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Committee of ${members.length} appointed.'),
          backgroundColor: context.colors.successGreen));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: context.colors.dangerRed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.executiveTeal;
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c, width: w));
    return StyledFormDialog(
      label: 'Tender Committee',
      title: widget.info.forfeited.srNumber,
      headerAccentColor: accent,
      icon: Icons.groups_rounded,
      width: 520,
      child: StyledFormSection(
        gap: 0,
        title: '5-Member Committee · ${_cItemName(widget.info.forfeited)}',
        icon: Icons.badge_rounded,
        children: [
          for (var i = 0; i < _count; i++) ...[
            if (i > 0) ...[
              const Gap(10),
              Divider(height: 1, color: context.colors.borderColor),
              const Gap(10),
            ],
            // Row 1: number + name.
            Row(children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Text('${i + 1}',
                    style: TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
              const Gap(10),
              Expanded(
                child: TextField(
                  controller: _names[i],
                  style: TextStyle(color: context.colors.textPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Member ${i + 1} name',
                    filled: true,
                    fillColor: context.colors.cardDark,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    border: border(context.colors.borderColor),
                    enabledBorder: border(context.colors.borderColor),
                    focusedBorder: border(accent, 1.4),
                  ),
                ),
              ),
            ]),
            const Gap(8),
            // Row 2: designation + salary number (aligned under the name).
            Padding(
              padding: const EdgeInsets.only(left: 34),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _desigs[i],
                    style: TextStyle(color: context.colors.textPrimary),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'Designation',
                      filled: true,
                      fillColor: context.colors.cardDark,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      border: border(context.colors.borderColor),
                      enabledBorder: border(context.colors.borderColor),
                      focusedBorder: border(accent, 1.4),
                    ),
                  ),
                ),
                const Gap(8),
                Expanded(
                  child: TextField(
                    controller: _salaries[i],
                    style: TextStyle(color: context.colors.textPrimary),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'Salary No.',
                      filled: true,
                      fillColor: context.colors.cardDark,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      border: border(context.colors.borderColor),
                      enabledBorder: border(context.colors.borderColor),
                      focusedBorder: border(accent, 1.4),
                    ),
                  ),
                ),
              ]),
            ),
          ],
          const Gap(14),
          TextField(
            controller: _noteCtrl,
            maxLines: 2,
            style: TextStyle(color: context.colors.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Note (optional)',
              filled: true,
              fillColor: context.colors.cardDark,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: border(context.colors.borderColor),
              enabledBorder: border(context.colors.borderColor),
              focusedBorder: border(accent, 1.4),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: accent),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Save Committee'),
        ),
      ],
    );
  }
}
