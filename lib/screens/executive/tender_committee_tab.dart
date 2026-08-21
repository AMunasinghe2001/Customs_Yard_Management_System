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
  // Forfeiture is recorded PER ITEM, so a multi-item package produces one row
  // per item. Resolve THIS row's own item from item_id — falling straight
  // through to items.first labelled every row of the package with the first
  // item's name (e.g. three "Wash Basins +2" rows).
  if (f.itemId != null) {
    final match = items.where((i) => i.id == f.itemId).firstOrNull;
    if (match != null) return match.itemName;
  }
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

/// High Panel tab: packages still unsold after the Valuation Tender plus all
/// three bid-driven rounds (Tender 1-3), i.e. ≥4 attempts. The DG appoints a
/// committee for each (usually five officers); the ADG then submits that
/// committee's valuation as the tender's final price.
class TenderCommitteeTab extends ConsumerWidget {
  const TenderCommitteeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = AppTheme.executiveTeal;
    final async = ref.watch(committeeEligibleProvider);
    final committees =
        // valueOrNull keeps the last map while re-fetching; asData?.value goes
        // null mid-reload and every row would briefly lose its committee.
        ref.watch(tenderCommitteesProvider).valueOrNull ?? const {};
    final q = ref.watch(_committeeSearchProvider).trim().toLowerCase();
    final yardFilter = ref.watch(_committeeYardProvider);
    final storageRate = ref.watch(storageRateProvider).valueOrNull ??
        const <DateTime, double>{};

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
                  'Packages still unsold after Tender 3 — appoint a committee',
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
                // A package STAYS on this tab after the committee is appointed:
                // the committee still has to record its valuation and the ADG
                // still has to submit it as the tender's final valuation. It
                // only leaves once the ADG has submitted.
                var rows = list.where((info) {
                  final c = committees[info.forfeited.id];
                  return c == null || !c.isSubmitted;
                }).toList();
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
                              'No packages unsold after Tender 3 yet'),
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
                            label: Center(child: Text('Committee Value')),
                            size: ColumnSize.S,
                            fixedWidth: 172),
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
                                      ? Icons.visibility_rounded
                                      : Icons.group_add_rounded,
                                  size: 15),
                              // Appointed committees are view-only — the record
                              // of who valued the goods must not change.
                              label: Text(
                                  count > 0
                                      ? 'View ($count)'
                                      : 'Appoint',
                                  style: const TextStyle(fontSize: 12)),
                              onPressed: () => showDialog(
                                context: context,
                                builder: (_) => _CommitteeDialog(
                                    info: info, existing: committee),
                              ),
                            ),
                          )),
                          // Two-step: the appointed COMMITTEE records its
                          // valuation, then the ADG submits it as the tender's
                          // final valuation. Nothing until a committee exists.
                          DataCell(Center(
                            child: _CommitteeRoundValueCell(
                                info: info,
                                qty: qty,
                                committee: committee),
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

/// Appoint a committee for a package (name + designation + salary no. each).
/// Usually five officers; 2-10 allowed. Read-only once appointed.
class _CommitteeDialog extends ConsumerStatefulWidget {
  final ReTenderSaleInfo info;
  final TenderCommitteeModel? existing;
  const _CommitteeDialog({required this.info, this.existing});
  @override
  ConsumerState<_CommitteeDialog> createState() => _CommitteeDialogState();
}

class _CommitteeDialogState extends ConsumerState<_CommitteeDialog> {
  /// A committee is normally five officers, but the DG may appoint fewer or
  /// more, so the rows are add/remove-able rather than a fixed five.
  static const _defaultCount = 5;
  static const _minCount = 2;
  static const _maxCount = 10;

  final List<TextEditingController> _names = [];
  final List<TextEditingController> _desigs = [];
  final List<TextEditingController> _salaries = [];
  final _noteCtrl = TextEditingController();
  bool _saving = false;

  int get _count => _names.length;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing?.members ?? const <CommitteeMember>[];
    final rows = existing.isNotEmpty ? existing.length : _defaultCount;
    for (var i = 0; i < rows; i++) {
      _names.add(TextEditingController(
          text: i < existing.length ? existing[i].name : ''));
      _desigs.add(TextEditingController(
          text: i < existing.length ? (existing[i].designation ?? '') : ''));
      _salaries.add(TextEditingController(
          text: i < existing.length ? (existing[i].salaryNo ?? '') : ''));
    }
    _noteCtrl.text = widget.existing?.note ?? '';
  }

  void _addMember() {
    if (_count >= _maxCount) return;
    setState(() {
      _names.add(TextEditingController());
      _desigs.add(TextEditingController());
      _salaries.add(TextEditingController());
    });
  }

  void _removeMember(int i) {
    if (_count <= _minCount) return;
    setState(() {
      _names.removeAt(i).dispose();
      _desigs.removeAt(i).dispose();
      _salaries.removeAt(i).dispose();
    });
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
    // Every row that exists must be named — remove a row instead of blanking it.
    final missing = <int>[];
    for (var i = 0; i < _count; i++) {
      if (_names[i].text.trim().isEmpty) missing.add(i + 1);
    }
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Enter a name for member ${missing.join(', ')}, or remove the row.'),
          backgroundColor: context.colors.dangerRed));
      return;
    }
    final members = <CommitteeMember>[];
    for (var i = 0; i < _count; i++) {
      final d = _desigs[i].text.trim();
      final s = _salaries[i].text.trim();
      members.add(CommitteeMember(
          name: _names[i].text.trim(),
          designation: d.isEmpty ? null : d,
          salaryNo: s.isEmpty ? null : s));
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

  /// Once the DG has appointed the members the committee is fixed — the record
  /// of who valued the goods must not change afterwards, so the dialog becomes
  /// a read-only roster.
  bool get _readOnly => (widget.existing?.members.isNotEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.executiveTeal;
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c, width: w));

    if (_readOnly) return _rosterView(accent);

    return StyledFormDialog(
      label: 'Tender Committee',
      title: widget.info.forfeited.srNumber,
      headerAccentColor: accent,
      icon: Icons.groups_rounded,
      width: 520,
      child: StyledFormSection(
        gap: 0,
        title:
            '$_count-Member Committee · ${_cItemName(widget.info.forfeited)}',
        icon: Icons.badge_rounded,
        children: [
          for (var i = 0; i < _count; i++) ...[
            if (i > 0) ...[
              const Gap(6),
              Divider(height: 1, color: context.colors.borderColor),
              const Gap(6),
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
              // Remove this member (kept above the minimum).
              if (_count > _minCount) ...[
                const Gap(4),
                IconButton(
                  tooltip: 'Remove member ${i + 1}',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.remove_circle_outline_rounded,
                      size: 18, color: context.colors.dangerRed),
                  onPressed: _saving ? null : () => _removeMember(i),
                ),
              ],
            ]),
            const Gap(6),
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
          const Gap(6),
          // A committee is normally 5 officers, but the DG may appoint fewer
          // or more — up to 10.
          Row(children: [
            TextButton.icon(
              onPressed:
                  (_saving || _count >= _maxCount) ? null : _addMember,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 17),
              style: TextButton.styleFrom(foregroundColor: accent),
              label: const Text('Add member',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const Spacer(),
            Text('$_count of $_maxCount',
                style:
                    TextStyle(color: context.colors.textMuted, fontSize: 11)),
          ]),
          const Gap(8),
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

  /// Read-only roster shown once the committee is appointed.
  Widget _rosterView(Color accent) {
    final members = widget.existing?.members ?? const <CommitteeMember>[];
    return StyledFormDialog(
      label: 'Tender Committee',
      title: widget.info.forfeited.srNumber,
      headerAccentColor: accent,
      icon: Icons.groups_rounded,
      width: 520,
      child: StyledFormSection(
        title: 'Appointed Committee (${members.length}) · '
            '${_cItemName(widget.info.forfeited)}',
        icon: Icons.badge_rounded,
        children: [
          for (var i = 0; i < members.length; i++) ...[
            if (i > 0) const Gap(6),
            _memberTile(i + 1, members[i], accent),
          ],
          if (widget.existing?.note?.trim().isNotEmpty == true) ...[
            const Gap(14),
            Text(widget.existing!.note!.trim(),
                style: TextStyle(
                    color: context.colors.textMuted,
                    fontSize: 12,
                    fontStyle: FontStyle.italic)),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close')),
      ],
    );
  }
}

/// One appointed member, shown at a comfortable reading size.
Widget _memberTile(int no, CommitteeMember m, Color accent) {
  return Builder(builder: (context) {
    final sub = [
      if (m.designation?.trim().isNotEmpty == true) m.designation!.trim(),
      if (m.salaryNo?.trim().isNotEmpty == true) 'Salary No: ${m.salaryNo!.trim()}',
    ].join('  ·  ');
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration:
            BoxDecoration(color: accent.withOpacity(0.12), shape: BoxShape.circle),
        child: Text('$no',
            style: TextStyle(
                color: accent, fontSize: 13, fontWeight: FontWeight.w800)),
      ),
      const Gap(12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(m.name,
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            if (sub.isNotEmpty) ...[
              const Gap(2),
              Text(sub,
                  style: TextStyle(
                      color: context.colors.textSecondary, fontSize: 12.5)),
            ],
          ],
        ),
      ),
    ]);
  });
}

/// The committee valuation cell — a TWO-STEP flow, shown as three states:
///
///   1. no committee yet          → "Appoint first" (nothing to value)
///   2. committee appointed       → [Committee Value] button; the COMMITTEE
///                                  records the price it decided on inspection
///   3. committee has valued      → the amount + a [Submit as Final] action
///                                  for the ADG only; once submitted it shows
///                                  the figure with a "Final" badge
///
/// Submitting writes the normal `tender_revaluations` row for the current
/// round, so the price reaches the tender through the same path a Valuation
/// Directorate re-valuation uses — the valuation chain and every report pick
/// it up with no extra wiring.
class _CommitteeRoundValueCell extends ConsumerWidget {
  final ReTenderSaleInfo info;
  final int? qty;
  final TenderCommitteeModel? committee;
  const _CommitteeRoundValueCell({
    required this.info,
    required this.qty,
    required this.committee,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = AppTheme.executiveTeal;
    final c = committee;

    // 1 ── The DG has not appointed anyone yet, so there is nothing to value.
    if (c == null || c.members.isEmpty) {
      return Text('Appoint first',
          style: TextStyle(
              color: context.colors.textMuted,
              fontSize: 11,
              fontStyle: FontStyle.italic));
    }

    final fmt = NumberFormat('#,##0');
    final effQty = (qty != null && qty! > 0) ? qty! : 1;
    final profile = ref.watch(currentProfileProvider);
    final isAdg = (profile?.jobRole ?? '').toUpperCase() == 'ADG';

    // 2 ── Committee appointed but has not priced the goods yet.
    if (c.committeeValue == null) {
      // Only the ADG enters the committee's figure; the DG sees the state.
      if (!isAdg) {
        return Text('Awaiting ADG entry',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: context.colors.textMuted,
                fontSize: 11,
                fontStyle: FontStyle.italic));
      }
      return FilledButton.icon(
        style: FilledButton.styleFrom(
            backgroundColor: accent,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            visualDensity: VisualDensity.compact),
        icon: const Icon(Icons.price_change_rounded, size: 15),
        label: const Text('Enter Value', style: TextStyle(fontSize: 12)),
        onPressed: () => showDialog(
          context: context,
          builder: (_) => _CommitteeValuationDialog(
              info: info, qty: effQty, committee: c),
        ),
      );
    }

    // 3 ── Valued. Show the figure, plus what still has to happen.
    final submitted = c.submittedValue != null;
    final shown = c.submittedValue ?? c.committeeValue!;
    final colour = submitted ? context.colors.successGreen : accent;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      // Only the ADG can act here: re-open to submit, or to revise.
      onTap: isAdg
          ? () => showDialog(
                context: context,
                builder: (_) => _CommitteeValuationDialog(
                    info: info, qty: effQty, committee: c),
              )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('LKR ${fmt.format(shown * effQty)}',
              style: TextStyle(
                  color: colour, fontWeight: FontWeight.w800, fontSize: 12)),
          Text('@ ${fmt.format(shown)} × $effQty',
              style: TextStyle(color: context.colors.textMuted, fontSize: 10)),
          const Gap(2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: colour.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colour.withOpacity(0.4)),
            ),
            child: Text(
                submitted
                    ? 'Final'
                    : (isAdg ? 'Submit as Final' : 'Awaiting ADG'),
                style: TextStyle(
                    color: colour, fontSize: 9, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Records the committee's valuation, and — for the ADG — submits it as the
/// tender's final valuation.
class _CommitteeValuationDialog extends ConsumerStatefulWidget {
  final ReTenderSaleInfo info;
  final int qty;
  final TenderCommitteeModel committee;
  const _CommitteeValuationDialog({
    required this.info,
    required this.qty,
    required this.committee,
  });
  @override
  ConsumerState<_CommitteeValuationDialog> createState() =>
      _CommitteeValuationDialogState();
}

class _CommitteeValuationDialogState
    extends ConsumerState<_CommitteeValuationDialog> {
  final _costCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _saving = false;

  static final _money = NumberFormat('#,##0.##');

  @override
  void initState() {
    super.initState();
    final v = widget.committee.committeeValue;
    if (v != null) {
      _costCtrl.text =
          v == v.roundToDouble() ? v.toInt().toString() : v.toString();
      _noteCtrl.text = widget.committee.committeeNote ?? '';
    }
    _costCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _costCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  double? get _typed {
    final v = double.tryParse(_costCtrl.text.trim());
    return (v != null && v > 0) ? v : null;
  }

  /// Step 2 — the committee records its own figure.
  Future<void> _saveCommitteeValue() async {
    final cost = _typed;
    if (cost == null) {
      _err('Enter a valid valuation amount');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(disposalServiceProvider).saveCommitteeValuation(
            widget.info.forfeited.id,
            cost,
            note: _noteCtrl.text,
          );
      ref.invalidate(tenderCommitteesProvider);
      if (!mounted) return;
      Navigator.pop(context);
      _ok('Committee valuation recorded: Rs. ${_money.format(cost)}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _err('Failed to save: $e');
    }
  }

  /// Step 3 — the ADG submits it as the tender's final valuation.
  Future<void> _submitAsFinal() async {
    final cost = _typed;
    if (cost == null) {
      _err('Enter a valid valuation amount');
      return;
    }
    final round = widget.info.latestSale;
    if (round == null) {
      _err('This package has no tender round to price');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(disposalServiceProvider).submitCommitteeValuation(
            forfeitedPackageId: widget.info.forfeited.id,
            tenderSaleId: round.id,
            value: cost,
            note: _noteCtrl.text,
            yard: widget.info.forfeited.yard,
          );
      ref.invalidate(tenderCommitteesProvider);
      ref.invalidate(tenderRevaluationsProvider(widget.info.forfeited.id));
      if (!mounted) return;
      Navigator.pop(context);
      _ok('Submitted as the final valuation: Rs. ${_money.format(cost)}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _err('Failed to submit: $e');
    }
  }

  void _ok(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m), backgroundColor: context.colors.successGreen));
  void _err(String m) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: context.colors.dangerRed));

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.executiveTeal;
    final f = widget.info.forfeited;
    final c = widget.committee;
    final profile = ref.watch(currentProfileProvider);
    final isAdg = (profile?.jobRole ?? '').toUpperCase() == 'ADG';
    final typed = _typed ?? 0;

    return StyledFormDialog(
      label: 'Committee Valuation',
      title: f.srNumber,
      headerAccentColor: accent,
      icon: Icons.groups_rounded,
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Who is on the committee — the people whose figure this is.
          StyledFormSection(
            title: 'Appointed Committee (${c.members.length})',
            icon: Icons.groups_rounded,
            children: [
              // Name on its own line at a readable size, details beneath it —
              // these are the officers accountable for the figure below.
              for (var i = 0; i < c.members.length; i++) ...[
                if (i > 0) const Gap(6),
                _memberTile(i + 1, c.members[i], accent),
              ],
            ],
          ),
          const Gap(10),
          StyledFormSection(
            title: 'Committee Valuation',
            icon: Icons.price_change_rounded,
            children: [
              Text(
                  'The committee inspects the goods and decides this value. '
                  'The ADG then submits it as the final valuation for the '
                  'next tender.',
                  style:
                      TextStyle(color: context.colors.textMuted, fontSize: 11)),
              const Gap(10),
              // Item + qty on one line, and the cost field beside the running
              // total — the old layout gave each of these its own full-width
              // row, which left most of the dialog empty.
              Row(children: [
                Expanded(
                  child: Text(_cItemName(f),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: context.colors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ),
                const Gap(8),
                Icon(Icons.inventory_2_rounded,
                    size: 12, color: context.colors.textMuted),
                const Gap(4),
                Text('Qty ${widget.qty}',
                    style: TextStyle(
                        color: context.colors.textMuted, fontSize: 11)),
              ]),
              const Gap(8),
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _costCtrl,
                    // The ADG enters the committee's figure and submits it;
                    // the DG appoints the members but does not price the goods.
                    enabled: isAdg,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Cost / item (LKR)',
                      isDense: true,
                      prefixText: 'LKR ',
                    ),
                  ),
                ),
                const Gap(12),
                Expanded(
                  flex: 2,
                  child: Text(
                      typed > 0
                          ? 'LKR ${_money.format(typed * widget.qty)}'
                          : '× ${widget.qty}',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: typed > 0
                              ? context.colors.successGreen
                              : context.colors.textMuted,
                          fontWeight: typed > 0 ? FontWeight.w800 : null,
                          fontSize: 13)),
                ),
              ]),
              const Gap(10),
              TextField(
                controller: _noteCtrl,
                enabled: isAdg,
                style: TextStyle(color: context.colors.textPrimary),
                maxLines: 1,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Committee note (optional)',
                  filled: true,
                  fillColor: context.colors.cardDark,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          BorderSide(color: context.colors.borderColor)),
                ),
              ),
              if (c.isAwaitingAdgSubmission && !isAdg) ...[
                const Gap(10),
                _statusNote(
                    context,
                    Icons.hourglass_bottom_rounded,
                    context.colors.warningAmber,
                    'Valued by the committee. Awaiting the ADG to submit it as '
                    'the final valuation.'),
              ],
              if (c.isSubmitted) ...[
                const Gap(10),
                _statusNote(
                    context,
                    Icons.check_circle_rounded,
                    context.colors.successGreen,
                    'Submitted as the final valuation for the next tender.'),
              ],
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        // Step 2 — record/revise the committee's own figure.
        // Step 2 — the ADG enters the figure the committee decided.
        if (isAdg && !c.isSubmitted)
          OutlinedButton(
            onPressed: _saving ? null : _saveCommitteeValue,
            style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent.withOpacity(0.6))),
            child: Text(c.committeeValue == null
                ? 'Save Committee Value'
                : 'Update Value'),
          ),
        // Step 3 — ADG only.
        if (isAdg) ...[
          const Gap(8),
          FilledButton(
            onPressed: (_saving || _typed == null) ? null : _submitAsFinal,
            style: FilledButton.styleFrom(backgroundColor: accent),
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(c.isSubmitted ? 'Re-submit as Final' : 'Submit as Final'),
          ),
        ],
      ],
    );
  }
}

/// Small coloured status strip used inside the committee valuation dialog.
Widget _statusNote(
    BuildContext context, IconData icon, Color colour, String text) {
  return Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: colour.withOpacity(0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: colour.withOpacity(0.35)),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 14, color: colour),
      const Gap(8),
      Expanded(
        child: Text(text,
            style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 11,
                height: 1.35)),
      ),
    ]),
  );
}