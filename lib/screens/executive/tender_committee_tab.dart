import '../../widgets/page_title.dart';
import '../../widgets/sealed_valuation.dart';
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

/// True when the signed-in Top Management Directorate officer is the ADG — the post that
/// submits a committee's valuation as the tender's final price.
/// See [executivePostIs] for how the post is resolved.
bool _isAdg(ProfileModel? p) => executivePostIs(p, 'ADG');

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
          style:
              TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

/// Valuation cell: unit valuation × qty (matches the Central Disposal tables).
class _CommitteeValuationCell extends StatelessWidget {
  final ForfeitedPackageModel f;
  final int? qty;

  /// True while the package's newest tender round has not yet run. The
  /// valuation is the reserve price for that round, so it stays sealed here
  /// too — the committee is appointed while the package can still be
  /// re-tendered. See [valuationSealed].
  final bool sealedUntilSale;
  const _CommitteeValuationCell(
      {required this.f, this.qty, this.sealedUntilSale = false});
  @override
  Widget build(BuildContext context) {
    if (sealedUntilSale) return const SealedValuation(compact: true);
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
final _committeeYardProvider =
    StateProvider<String?>((ref) => null); // null=all

/// Top Management Directorate tab: packages still unsold after the Valuation Tender plus all
/// three bid-driven rounds (Tender 1-3), i.e. ≥4 attempts. The DG and the ADG
/// both appoint committees (usually five officers); the ADG then submits the
/// committee's valuation as the tender's final price. The DC observes only.
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
    // Both the DG and the ADG appoint committees; the DC only observes.
    final canAppoint = !isExecutiveViewOnly(ref.watch(currentProfileProvider));
    final storageRate = ref.watch(storageRateProvider).valueOrNull ??
        const <DateTime, double>{};

    return Padding(
      // ⚠️ 16, not 24. These pages are TABLES, and vertical chrome is rows
      // the officer cannot see. Central Disposal tightened to this for the
      // same reason; matching it also keeps the two portals looking alike.
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            PageTitle('Tender Committees', Icons.groups_rounded, accent: accent),
            const Gap(10),
            Expanded(
              child: Text(
                  canAppoint
                      ? 'Packages still unsold after Tender 3 — appoint a committee'
                      : 'Packages still unsold after Tender 3 — view only',
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
                // A package STAYS on this tab for the whole committee stage —
                // appointment, the committee's valuation, AND after the ADG
                // has submitted it. Dropping it at submission hid the finished
                // work: the row vanished from here while Central Disposal
                // still showed the package, so the two tables disagreed about
                // how many committee cases there were.
                //
                // It leaves on its own once the committee-priced tender has
                // been held and failed — the package is then exhausted and
                // moves to the DG's Unsold Goods tab.
                var rows = list.toList();
                if (yardFilter != null) {
                  rows = rows
                      .where((info) => matchesYardFilter(yardFilter,
                          info.forfeited.yard, info.forfeited.srNumber))
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
                          message: 'No packages unsold after Tender 3 yet'),
                      headingRowColor:
                          WidgetStateProperty.all(context.colors.surfaceDark),
                      columns: const [
                        DataColumn2(
                            label: Text('SR Number'), size: ColumnSize.M),
                        DataColumn2(label: Text('Case No'), size: ColumnSize.S),
                        DataColumn2(
                            label: Text('Goods Name'), size: ColumnSize.M),
                        DataColumn2(
                            label: Center(child: Text('Source')),
                            size: ColumnSize.S),
                        DataColumn2(
                            label: Text('Qty'),
                            size: ColumnSize.S,
                            fixedWidth: 56),
                        DataColumn2(
                            label: Text('Location'), size: ColumnSize.M),
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
                            fixedWidth: 186),
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
                                  color: accent, fontWeight: FontWeight.w600))),
                          DataCell(TooltipText(pkg?.caseNumber ?? '—',
                              overflow: TextOverflow.ellipsis)),
                          DataCell(TooltipText(_cItemName(f),
                              overflow: TextOverflow.ellipsis)),
                          DataCell(Center(
                              child: _CommitteeSourceChip(source: f.source))),
                          DataCell(TooltipText('${qty ?? '—'}')),
                          DataCell(TooltipText(
                              _committeeLocation(pkg, f.itemId),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: context.colors.textSecondary,
                                  fontSize: 12))),
                          DataCell(_CommitteeValuationCell(
                              f: f,
                              qty: qty,
                              sealedUntilSale:
                                  info.latestSale?.saleEnded == false)),
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
                            child: Builder(builder: (context) {
                              // Appointed committees are view-only — the record
                              // of who valued the goods must not change — and
                              // the DG never gets the Appoint form at all.
                              // Colour follows the ACTION, not the count, so
                              // every View button looks the same.
                              final appointing = canAppoint && count == 0;
                              // Width only — the button keeps its natural
                              // height, so the row does not look squashed.
                              return SizedBox(
                                width: 116,
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                      backgroundColor: appointing
                                          ? accent
                                          : context.colors.successGreen,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10),
                                      // Keeps the button inside the 48px data
                                      // row; without it the row overflows.
                                      visualDensity: VisualDensity.compact),
                                  icon: Icon(
                                      appointing
                                          ? Icons.group_add_rounded
                                          : Icons.visibility_rounded,
                                      size: 15),
                                  label: Text(
                                      count > 0
                                          ? 'View ($count)'
                                          : (appointing ? 'Appoint' : 'View'),
                                      style: const TextStyle(fontSize: 12)),
                                  onPressed: () => showDialog(
                                    context: context,
                                    builder: (_) => _CommitteeDialog(
                                        info: info, existing: committee),
                                  ),
                                ),
                              );
                            }),
                          )),
                          // Two-step: the appointed COMMITTEE records its
                          // valuation, then the ADG submits it as the tender's
                          // final valuation. Nothing until a committee exists.
                          DataCell(Center(
                            child: _CommitteeRoundValueCell(
                                info: info, qty: qty, committee: committee),
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
                                          valuationSealedUntilSale:
                                              info.latestSale?.saleEnded ==
                                                  false,
                                          valuationUnitCost: f.valuationCost,
                                          valuationTotalCost: f.valuationCost !=
                                                  null
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
///
/// [value] / the string [onChanged] reports is a [YardFilterOption.value]:
/// apply it with [matchesYardFilter], not a bare `==` on `yard` — see
/// [YardAllFilter] in disposal_shared.dart for the same contract.
class _CommitteeYardFilter extends ConsumerWidget {
  final String? value; // null = all
  final ValueChanged<String?> onChanged;
  const _CommitteeYardFilter({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(yardFilterOptionsProvider).valueOrNull ??
        [for (final y in kYards) YardFilterOption(value: y.code, label: y.name, filterYard: y.code)];
    final accent = AppTheme.executiveTeal;
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: w));
    return SizedBox(
      width: 220,
      child: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
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
          prefixIcon: Icon(Icons.warehouse_rounded, color: accent, size: 20),
          options: [
            const StyledDropdownOption('_all', 'All Yards'),
            for (final o in options) StyledDropdownOption(o.value, o.label),
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
  /// A committee is normally five officers, but the ADG may appoint fewer or
  /// more, so the rows are add/remove-able rather than a fixed five.
  static const _defaultCount = 5;
  static const _minCount = 1;
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
    // Blank rows are simply IGNORED, not an error: the form opens with five
    // rows because five is the norm, but a committee may be any size, so
    // leaving the spare rows empty is the normal way to appoint fewer.
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
    // …but at least one named officer is required.
    if (members.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Enter at least one committee member.'),
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
      showErrorSnack(context, e);
    }
  }

  /// The dialog is a read-only roster when EITHER:
  ///   * the members are already appointed — the record of who valued the
  ///     goods must not change afterwards; or
  ///   * the signed-in officer only observes (the DC). The DG and the ADG can
  ///     both appoint.
  bool get _readOnly {
    if (widget.existing?.members.isNotEmpty ?? false) return true;
    return isExecutiveViewOnly(ref.read(currentProfileProvider));
  }

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
          // A committee is normally 5 officers, but the ADG may appoint fewer
          // or more — up to 10.
          Row(children: [
            TextButton.icon(
              onPressed: (_saving || _count >= _maxCount) ? null : _addMember,
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
            minLines: 2,
            maxLines: 4,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(color: context.colors.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Note (optional)',
              alignLabelWithHint: true,
              hintText: 'Why these officers were appointed…',
              hintStyle:
                  TextStyle(color: context.colors.textMuted, fontSize: 12),
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
        title: members.isEmpty
            ? 'No Committee Yet · ${_cItemName(widget.info.forfeited)}'
            : 'Appointed Committee (${members.length}) · '
                '${_cItemName(widget.info.forfeited)}',
        icon: Icons.badge_rounded,
        children: [
          // A non-ADG officer (i.e. the DG) opening a package with no
          // committee: explain rather than showing an empty panel.
          if (members.isEmpty)
            Row(children: [
              Icon(Icons.info_outline_rounded,
                  size: 18, color: context.colors.textMuted),
              const Gap(10),
              Expanded(
                child: Text(
                    'No committee has been appointed for this package yet. '
                    'The DG or the ADG names the committee members.',
                    style: TextStyle(
                        color: context.colors.textMuted, fontSize: 13)),
              ),
            ]),
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
      if (m.salaryNo?.trim().isNotEmpty == true)
        'Salary No: ${m.salaryNo!.trim()}',
    ].join('  ·  ');
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: accent.withOpacity(0.12), shape: BoxShape.circle),
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

/// A pill for the Committee Value column's waiting states. Reads as a real
/// status like the chips beside it, instead of the faint italic caption these
/// states used to be.
Widget _waitingChip(
    BuildContext context, String label, IconData icon, Color colour) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: colour.withOpacity(0.12),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: colour.withOpacity(0.45)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: colour),
      const Gap(5),
      Flexible(
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: colour, fontSize: 11, fontWeight: FontWeight.w700)),
      ),
    ]),
  );
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

    // 1 ── Nobody appointed yet, so there is nothing to value.
    if (c == null || c.members.isEmpty) {
      return _waitingChip(context, 'Appoint first', Icons.group_add_rounded,
          context.colors.textSecondary);
    }

    final fmt = NumberFormat('#,##0');
    final effQty = (qty != null && qty! > 0) ? qty! : 1;
    final profile = ref.watch(currentProfileProvider);
    final isAdg = _isAdg(profile);

    // 2 ── Committee appointed but has not priced the goods yet.
    if (c.committeeValue == null) {
      // Only the ADG enters the committee's figure; the DG sees the state.
      if (!isAdg) {
        return _waitingChip(context, 'Awaiting ADG entry',
            Icons.hourglass_bottom_rounded, context.colors.warningAmber);
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
          builder: (_) =>
              _CommitteeValuationDialog(info: info, qty: effQty, committee: c),
        ),
      );
    }

    // 3 ── Valued. Show the figure, plus what still has to happen.
    final submitted = c.submittedValue != null;
    final shown = c.submittedValue ?? c.committeeValue!;
    final colour = submitted ? context.colors.successGreen : accent;

    // The whole cell is one tappable card, so the tap target is obvious rather
    // than being bare text that happens to respond to a click.
    final tappable = isAdg;
    // TWO compact lines so the row keeps its default height: the amount with
    // a leading status icon, and the unit rate + status beneath. Three stacked
    // lines overflowed the row by 16px, and raising dataRowHeight made the
    // whole table look bloated.
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colour.withOpacity(tappable ? 0.10 : 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colour.withOpacity(tappable ? 0.45 : 0.25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
                submitted
                    ? Icons.verified_rounded
                    : (isAdg
                        ? Icons.arrow_circle_right_rounded
                        : Icons.hourglass_bottom_rounded),
                size: 12,
                color: colour),
            const Gap(4),
            Flexible(
              child: Text('LKR ${fmt.format(shown * effQty)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: colour,
                      fontWeight: FontWeight.w800,
                      fontSize: 12)),
            ),
          ]),
          Text(
              submitted
                  ? 'Final'
                  : (isAdg ? 'Submit as Final' : 'Awaiting ADG'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: colour, fontSize: 9.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );

    if (!tappable) return card;

    return Tooltip(
      message: submitted
          ? 'Revise the final valuation'
          : 'Submit this as the tender’s final valuation',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => showDialog(
            context: context,
            builder: (_) => _CommitteeValuationDialog(
                info: info, qty: effQty, committee: c),
          ),
          child: card,
        ),
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
            // The committee's figure prices the round the package is about to
            // be re-tendered in — not the one just held. Writing it to a
            // finished round overwrote that round's own reserve AND left no
            // "next round is priced" signal, so the package sat on "Committee
            // valued" forever and dropped out of the Committees table.
            tenderSaleId: round.saleEnded ? null : round.id,
            value: cost,
            note: _noteCtrl.text,
            yard: widget.info.forfeited.yard,
          );
      ref.invalidate(tenderCommitteesProvider);
      ref.invalidate(tenderRevaluationsProvider(widget.info.forfeited.id));
      // Submitting makes the package re-tenderable, which these two decide.
      ref.invalidate(reTenderEligibleProvider);
      ref.invalidate(valuedCurrentRoundProvider);
      if (!mounted) return;
      Navigator.pop(context);
      _ok('Submitted as the final valuation: Rs. ${_money.format(cost)}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _err('Failed to submit: $e');
    }
  }

  void _ok(String m) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: context.colors.successGreen));
  void _err(String m) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: context.colors.dangerRed));

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.executiveTeal;
    final f = widget.info.forfeited;
    final c = widget.committee;
    final profile = ref.watch(currentProfileProvider);
    final isAdg = _isAdg(profile);
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
                    // the ADG appoints the members but the COMMITTEE prices
                    // the goods.
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
              // Grows 2-4 lines as you type, wraps instead of truncating, and
              // carries the same enabled/focused borders as every other field
              // (a single-line box with only `border:` set looked broken and
              // hid the end of the note).
              TextField(
                controller: _noteCtrl,
                enabled: isAdg,
                style:
                    TextStyle(color: context.colors.textPrimary, fontSize: 13),
                minLines: 2,
                maxLines: 4,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Committee note (optional)',
                  alignLabelWithHint: true,
                  hintText: 'Why the committee set this value…',
                  hintStyle:
                      TextStyle(color: context.colors.textMuted, fontSize: 12),
                  filled: true,
                  fillColor: context.colors.cardDark,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          BorderSide(color: context.colors.borderColor)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          BorderSide(color: context.colors.borderColor)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: accent, width: 1.4)),
                  disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                          color: context.colors.borderColor.withOpacity(0.5))),
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
        // Step 2 — the ADG records the figure the committee decided.
        // Labels are kept short: three long buttons overflowed the dialog.
        if (isAdg && !c.isSubmitted)
          OutlinedButton(
            onPressed: _saving ? null : _saveCommitteeValue,
            style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                visualDensity: VisualDensity.compact,
                side: BorderSide(color: accent.withOpacity(0.6))),
            child: Text(c.committeeValue == null ? 'Save Value' : 'Update'),
          ),
        // Step 3 — ADG only.
        if (isAdg) ...[
          const Gap(8),
          FilledButton(
            onPressed: (_saving || _typed == null) ? null : _submitAsFinal,
            style: FilledButton.styleFrom(
                backgroundColor: accent, visualDensity: VisualDensity.compact),
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(c.isSubmitted ? 'Re-submit' : 'Submit as Final'),
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
