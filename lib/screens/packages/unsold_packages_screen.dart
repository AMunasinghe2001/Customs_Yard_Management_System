import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../models/models.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/error_view.dart';
import '../../widgets/empty_table_state.dart';
import '../../widgets/tooltip_text.dart';
import '../../widgets/package_details_dialog.dart';

String _itemName(ForfeitedPackageModel f) {
  if (f.itemName != null) return f.itemName!;
  final items = f.packageDetails?.items ?? const [];
  if (items.isEmpty) return 'Multiple/Unspecified';
  // Forfeiture is per item, so resolve THIS row's own item.
  if (f.itemId != null) {
    final m = items.where((i) => i.id == f.itemId).firstOrNull;
    if (m != null) return m.itemName;
  }
  if (items.length == 1) return items.first.itemName;
  return '${items.first.itemName} +${items.length - 1}';
}

int _qtyOf(ForfeitedPackageModel f) {
  if (f.entryQty != null) return f.entryQty!;
  if (f.itemId != null) {
    final it =
        f.packageDetails?.items.where((i) => i.id == f.itemId).firstOrNull;
    if (it != null) return it.quantity;
  }
  return f.packageDetails?.items.fold<int>(0, (s, i) => s + i.quantity) ?? 1;
}

String _location(PackageModel? pkg, String? itemId) {
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

final _searchProvider = StateProvider<String>((ref) => '');
/// null = all · false = awaiting the High Panel · true = decided
final _decidedProvider = StateProvider<bool?>((ref) => null);

({IconData icon, Color colour}) _style(BuildContext context, String p) {
  switch (p) {
    case 'destroy':
      return (
        icon: Icons.delete_forever_rounded,
        colour: context.colors.dangerRed
      );
    case 'remand':
      return (
        icon: Icons.reply_all_rounded,
        colour: context.colors.accentLightBlue
      );
    case 'government_use':
      return (
        icon: Icons.account_balance_rounded,
        colour: context.colors.successGreen
      );
    case 'auction':
      return (icon: Icons.gavel_rounded, colour: context.colors.warningAmber);
    default:
      return (
        icon: Icons.help_outline_rounded,
        colour: context.colors.textMuted
      );
  }
}

/// The yard's view of its own packages that could not be sold by any means.
///
/// READ-ONLY: the High Panel decides the final outcome (destroy / remand /
/// government use / auction); this page tells the yard what was decided so
/// they can act on the goods sitting in their warehouses.
class UnsoldPackagesScreen extends ConsumerWidget {
  const UnsoldPackagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gold = context.colors.primaryGold;
    final async = ref.watch(exhaustedUnsoldProvider);
    final proposals =
        ref.watch(unsoldProposalsProvider).valueOrNull ?? const {};
    final q = ref.watch(_searchProvider).trim().toLowerCase();
    final decidedFilter = ref.watch(_decidedProvider);
    final storageRate = ref.watch(storageRateProvider).valueOrNull ??
        const <DateTime, double>{};
    // RLS already scopes reads to the officer's own yard, but the shared
    // provider is cross-yard, so filter explicitly too.
    final myYard = ref.watch(currentProfileProvider)?.yard;

    return AppShell(
      currentRoute: '/unsold-packages',
      child: Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Unsold Packages',
                        style: Theme.of(context).textTheme.headlineLarge),
                    Text(
                        'Could not be sold by any means — awaiting or carrying '
                        'the High Panel’s final outcome',
                        style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 13)),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  width: 320,
                  child: TextField(
                    onChanged: (v) =>
                        ref.read(_searchProvider.notifier).state = v,
                    style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search SR / item / consignee…',
                      prefixIcon:
                          Icon(Icons.search_rounded, size: 20, color: gold),
                      filled: true,
                      fillColor: gold.withOpacity(0.06),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              BorderSide(color: gold.withOpacity(0.4))),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              BorderSide(color: gold.withOpacity(0.4))),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: gold, width: 1.5)),
                    ),
                  ),
                ),
              ]).animate().fadeIn(duration: 300.ms),
              const Gap(14),
              Row(children: [
                _chip(context,
                    label: 'All',
                    selected: decidedFilter == null,
                    onTap: () =>
                        ref.read(_decidedProvider.notifier).state = null),
                const Gap(8),
                _chip(context,
                    label: 'Awaiting decision',
                    icon: Icons.hourglass_bottom_rounded,
                    colour: context.colors.warningAmber,
                    selected: decidedFilter == false,
                    onTap: () =>
                        ref.read(_decidedProvider.notifier).state = false),
                const Gap(8),
                _chip(context,
                    label: 'Decided',
                    icon: Icons.check_circle_rounded,
                    colour: context.colors.successGreen,
                    selected: decidedFilter == true,
                    onTap: () =>
                        ref.read(_decidedProvider.notifier).state = true),
              ]),
              const Gap(16),
              Expanded(
                child: async.when(
                  skipLoadingOnReload: true,
                  loading: () =>
                      Center(child: CircularProgressIndicator(color: gold)),
                  error: (e, _) => ErrorView(
                      error: e,
                      onRetry: () => ref.refresh(exhaustedUnsoldProvider)),
                  data: (list) {
                    var rows = myYard == null
                        ? list
                        : list
                            .where((i) => i.forfeited.yard == myYard)
                            .toList();
                    if (q.isNotEmpty) {
                      rows = rows.where((i) {
                        final f = i.forfeited;
                        return f.srNumber.toLowerCase().contains(q) ||
                            f.consigneeName.toLowerCase().contains(q) ||
                            _itemName(f).toLowerCase().contains(q);
                      }).toList();
                    }
                    if (decidedFilter != null) {
                      rows = rows
                          .where((i) =>
                              proposals.containsKey(i.forfeited.id) ==
                              decidedFilter)
                          .toList();
                    }
                    return Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: context.colors.cardDark,
                        borderRadius: BorderRadius.circular(14),
                        border:
                            Border.all(color: context.colors.borderColor),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: DataTable2(
                          columnSpacing: 12,
                          horizontalMargin: 16,
                          fixedTopRows: 1,
                          minWidth: 980,
                          empty: const EmptyTableState(
                              message: 'No unsold packages in this yard'),
                          headingRowColor: WidgetStateProperty.all(
                              context.colors.surfaceDark),
                          columns: const [
                            DataColumn2(
                                label: Text('SR Number'), size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Item'), size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Consignee'), size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Qty'),
                                size: ColumnSize.S,
                                fixedWidth: 60),
                            DataColumn2(
                                label: Text('Location'), size: ColumnSize.M),
                            DataColumn2(
                                label: Center(child: Text('Tenders')),
                                size: ColumnSize.S,
                                fixedWidth: 80),
                            DataColumn2(
                                label: Center(child: Text('Final Outcome')),
                                size: ColumnSize.M,
                                fixedWidth: 200),
                            DataColumn2(
                                label: Center(child: Text('Details')),
                                size: ColumnSize.S,
                                fixedWidth: 70),
                          ],
                          rows: rows.map((info) {
                            final f = info.forfeited;
                            final pkg = f.packageDetails;
                            return DataRow(cells: [
                              DataCell(TooltipText(f.srNumber,
                                  style: TextStyle(
                                      color: gold,
                                      fontWeight: FontWeight.w600))),
                              DataCell(TooltipText(_itemName(f),
                                  overflow: TextOverflow.ellipsis)),
                              DataCell(TooltipText(f.consigneeName,
                                  overflow: TextOverflow.ellipsis)),
                              DataCell(TooltipText('${_qtyOf(f)}')),
                              DataCell(TooltipText(
                                  _location(pkg, f.itemId),
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: context.colors.textSecondary,
                                      fontSize: 12))),
                              DataCell(Center(
                                child: Text('${info.tenderCount}×',
                                    style: TextStyle(
                                        color: context.colors.warningAmber,
                                        fontWeight: FontWeight.w800)),
                              )),
                              DataCell(Center(
                                child: _OutcomeChip(
                                    proposal: proposals[f.id]),
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
                                            builder: (_) =>
                                                PackageDetailsDialog(
                                              package: pkg,
                                              storageRate: storageRate,
                                              headerAccentColor: gold,
                                              useLegacySummary: true,
                                              highlightItemId: f.itemId,
                                            ),
                                          ),
                                ),
                              )),
                            ]);
                          }).toList(),
                        ),
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 350.ms)
                        .slideY(begin: 0.05);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
    Color? colour,
  }) {
    final c = colour ?? context.colors.primaryGold;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? c.withOpacity(0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color:
                    selected ? c.withOpacity(0.6) : context.colors.borderColor,
                width: selected ? 1.4 : 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 14, color: selected ? c : context.colors.textMuted),
              const Gap(6),
            ],
            Text(label,
                style: TextStyle(
                    color: selected ? c : context.colors.textSecondary,
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

/// The High Panel's decision, read-only.
class _OutcomeChip extends StatelessWidget {
  final UnsoldProposalModel? proposal;
  const _OutcomeChip({required this.proposal});

  @override
  Widget build(BuildContext context) {
    final p = proposal;
    if (p == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: context.colors.warningAmber.withOpacity(0.10),
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: context.colors.warningAmber.withOpacity(0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.hourglass_bottom_rounded,
              size: 13, color: context.colors.warningAmber),
          const Gap(5),
          Text('Awaiting High Panel',
              style: TextStyle(
                  color: context.colors.warningAmber,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ]),
      );
    }
    final st = _style(context, p.proposal);
    return Tooltip(
      message: p.note?.trim().isNotEmpty == true
          ? p.note!.trim()
          : 'Decided ${DateFormat('yyyy-MM-dd').format(p.decidedAt)}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: st.colour.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: st.colour.withOpacity(0.45)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(st.icon, size: 13, color: st.colour),
          const Gap(5),
          Flexible(
            child: Text(p.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: st.colour,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
    );
  }
}
