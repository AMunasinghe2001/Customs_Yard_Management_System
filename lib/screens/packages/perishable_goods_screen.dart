import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/yards.dart';
import '../../models/models.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/disposal_page_header.dart';
import '../../widgets/empty_table_state.dart';
import '../../widgets/error_view.dart';
import '../../widgets/package_details_dialog.dart';
import '../../widgets/table_pager.dart';
import '../../widgets/tooltip_text.dart';
import '../../widgets/year_filter.dart';
import '../forfeited_packages/disposal_request_dialog.dart';

/// One perishable item, with the package it belongs to.
class PerishableRow {
  final PackageModel package;
  final PackageItem item;
  const PerishableRow({required this.package, required this.item});

  /// Perishables are sent as soon as they are registered, so what matters is
  /// how long this one has been waiting.
  int get daysWaiting =>
      DateTime.now().difference(package.entryDate ?? package.createdAt).inDays;
}

/// Every perishable item still awaiting disposal, newest first.
///
/// Perishable goods never reach a warehouse and never sit out the appeal
/// window, so they cannot be found on any of the disposition pages — this is
/// the only place they appear before they are sent.
final perishableRowsProvider = FutureProvider<List<PerishableRow>>((ref) async {
  final packages = await ref.watch(livePackagesProvider.future);
  final sentKeys = await ref.watch(sentPerishableKeysProvider.future);

  final rows = <PerishableRow>[];
  for (final p in packages) {
    for (final i in p.items) {
      if (i.nature != kNaturePerishable) continue;
      // Once sent it belongs to the disposal request, not here.
      if (sentKeys.contains('${p.id}:${i.id}')) continue;
      rows.add(PerishableRow(package: p, item: i));
    }
  }
  rows.sort((a, b) => (b.package.entryDate ?? b.package.createdAt)
      .compareTo(a.package.entryDate ?? a.package.createdAt));
  return rows;
});

/// "pkgId:itemId" for every perishable item already in a disposal request.
final sentPerishableKeysProvider = FutureProvider<Set<String>>((ref) async {
  ref.watch(disposalRequestsChangeTriggerProvider);
  ref.watch(disposalRequestsRefreshProvider);
  ref.watch(packagesChangeTriggerProvider);
  final data = await supabase
      .from('disposal_request_items')
      .select('forfeited_packages!inner(package_id, item_id, source)')
      .eq('forfeited_packages.source', 'perishable');
  return {
    for (final row in (data as List))
      () {
        final e = (row as Map<String, dynamic>)['forfeited_packages']
            as Map<String, dynamic>;
        return '${e['package_id']}:${e['item_id']}';
      }(),
  };
});

/// The yard's Perishable Goods page.
///
/// Read-only on the Central Disposal side ([readOnly]), which watches what each
/// yard is holding but does not send the request itself.
class PerishableGoodsScreen extends ConsumerStatefulWidget {
  /// Central Disposal's copy: no Send Disposal Request, and no app shell.
  final bool readOnly;
  const PerishableGoodsScreen({super.key, this.readOnly = false});

  @override
  ConsumerState<PerishableGoodsScreen> createState() =>
      _PerishableGoodsScreenState();
}

class _PerishableGoodsScreenState
    extends ConsumerState<PerishableGoodsScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  String? _yearFilter;
  int _page = 0;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<PerishableRow> _filter(List<PerishableRow> rows) {
    return rows.where((r) {
      if (!srYearMatches(r.package.srNumber, _yearFilter)) return false;
      if (_search.isEmpty) return true;
      final q = _search.toLowerCase();
      return r.package.srNumber.toLowerCase().contains(q) ||
          r.package.consigneeName.toLowerCase().contains(q) ||
          r.item.itemName.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(perishableRowsProvider);
    final storageRate = ref.watch(storageRateProvider).valueOrNull ??
        {DateTime(2020, 1, 1): 50.0};

    final body = Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DisposalPageHeader(
              title: 'Perishable Goods',
              subtitle: widget.readOnly
                  ? 'Goods that spoil — held at the yard, awaiting a disposal '
                      'request'
                  : 'Goods that spoil — no warehouse, no appeal window. Send '
                      'them for disposal without waiting.',
              trailing: [
                async.maybeWhen(
                  data: (rows) => _CountChip(count: _filter(rows).length),
                  orElse: () => const SizedBox(),
                ),
                if (!widget.readOnly)
                  async.maybeWhen(
                    data: (rows) => ElevatedButton.icon(
                      icon: const Icon(Icons.local_shipping_rounded, size: 16),
                      label: const Text('Send Disposal Request'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: rows.isNotEmpty
                            ? context.colors.primaryGold
                            : context.colors.textMuted.withOpacity(0.2),
                        foregroundColor: rows.isNotEmpty
                            ? Colors.white
                            : context.colors.textMuted,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        elevation: rows.isNotEmpty ? 2 : 0,
                      ),
                      // The same dialog every other page sends through, so a
                      // perishable request is an ordinary request from here on.
                      onPressed: rows.isEmpty
                          ? null
                          : () => showDialog(
                                context: context,
                                builder: (_) => DisposalRequestDialog(
                                  onSubmitted: () {
                                    ref.invalidate(livePackagesProvider);
                                    ref.invalidate(sentPerishableKeysProvider);
                                    ref.invalidate(
                                        requestableForfeitedPackagesProvider);
                                  },
                                ),
                              ),
                    ),
                    orElse: () => const SizedBox(),
                  ),
              ],
            ).animate().fadeIn(),
            const Gap(20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.colors.cardDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: context.colors.primaryGold.withOpacity(0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _searchCtrl,
                    style: TextStyle(color: context.colors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search SR #, consignee or item...',
                      prefixIcon: Icon(Icons.search_rounded,
                          color: context.colors.textMuted),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() {
                      _search = v;
                      _page = 0;
                    }),
                  ),
                  const Gap(8),
                  YearFilterButton(
                    value: _yearFilter,
                    years: srYears(async.valueOrNull
                            ?.map((r) => r.package.srNumber) ??
                        const <String>[]),
                    onChanged: (v) => setState(() {
                      _yearFilter = v;
                      _page = 0;
                    }),
                  ),
                ],
              ),
            ).animate().slideY(begin: 0.1, duration: 400.ms).fadeIn(),
            const Gap(16),
            Expanded(
              child: async.when(
                loading: () => Center(
                    child: CircularProgressIndicator(
                        color: context.colors.primaryGold)),
                error: (e, _) => ErrorView(
                    error: e,
                    onRetry: () => ref.refresh(perishableRowsProvider)),
                data: (all) {
                  final rows = _filter(all);
                  final maxPage =
                      rows.isEmpty ? 0 : (rows.length - 1) ~/ kClientPageSize;
                  final page = _page.clamp(0, maxPage);
                  final pageRows = pageSlice(rows, page);

                  return Column(
                    children: [
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: context.colors.cardDark,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: context.colors.borderColor),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: DataTable2(
                              columnSpacing: 12,
                              horizontalMargin: 16,
                              fixedTopRows: 1,
                              isHorizontalScrollBarVisible: false,
                              empty: const EmptyTableState(
                                icon: Icons.eco_rounded,
                                message: 'No perishable goods',
                                subtitle:
                                    'Goods registered as perishable appear '
                                    'here until they are sent for disposal.',
                              ),
                              columns: [
                                const DataColumn2(
                                    label: Text('SR Number'),
                                    size: ColumnSize.M),
                                const DataColumn2(
                                    label: Text('Goods Name'),
                                    size: ColumnSize.M),
                                const DataColumn2(
                                    label: Text('Qty'),
                                    size: ColumnSize.S,
                                    fixedWidth: 70),
                                const DataColumn2(
                                    label: Text('Consignee'),
                                    size: ColumnSize.M),
                                const DataColumn2(
                                    label: Text('Entry Date'),
                                    size: ColumnSize.S,
                                    fixedWidth: 120),
                                if (widget.readOnly)
                                  const DataColumn2(
                                      label: Text('Yard'),
                                      size: ColumnSize.S,
                                      fixedWidth: 130),
                                // ⚠️ No "Waiting" column. A countdown here read
                                // as an appeal window running down -- and a
                                // perishable has NO appeal window; that is the
                                // whole point of the nature. Nothing is being
                                // waited out, so nothing should be counted.
                                const DataColumn2(
                                    label: Center(child: Text('Details')),
                                    size: ColumnSize.S,
                                    fixedWidth: 60),
                              ],
                              rows: pageRows
                                  .map((r) => DataRow(cells: [
                                        DataCell(TooltipText(
                                            r.package.srNumber,
                                            style: TextStyle(
                                                color: context
                                                    .colors.accentLightBlue,
                                                fontWeight:
                                                    FontWeight.w600))),
                                        DataCell(TooltipText(r.item.itemName,
                                            overflow: TextOverflow.ellipsis)),
                                        DataCell(
                                            TooltipText('${r.item.quantity}')),
                                        DataCell(TooltipText(
                                            r.package.consigneeName,
                                            overflow: TextOverflow.ellipsis)),
                                        DataCell(TooltipText(DateFormat(
                                                'yyyy-MM-dd')
                                            .format(r.package.entryDate ??
                                                r.package.createdAt))),
                                        if (widget.readOnly)
                                          DataCell(TooltipText(
                                              yardName(yardOfSrNumber(
                                                  r.package.srNumber)),
                                              overflow:
                                                  TextOverflow.ellipsis)),
                                        DataCell(Center(
                                          child: IconButton(
                                            icon: Icon(
                                                Icons.info_outline_rounded,
                                                color: context
                                                    .colors.accentLightBlue,
                                                size: 18),
                                            onPressed: () => showDialog(
                                              context: context,
                                              builder: (_) =>
                                                  PackageDetailsDialog(
                                                package: r.package,
                                                storageRate: storageRate,
                                                highlightItemId: r.item.id,
                                                useLegacySummary: true,
                                              ),
                                            ),
                                          ),
                                        )),
                                      ]))
                                  .toList(),
                            ),
                          ),
                        ),
                      ),
                      TablePager(
                        total: rows.length,
                        page: page,
                        onPageChanged: (p) => setState(() => _page = p),
                      ),
                    ],
                  )
                      .animate()
                      .slideY(begin: 0.1, duration: 400.ms, delay: 200.ms)
                      .fadeIn();
                },
              ),
            ),
          ],
        ),
      ),
    );

    // Central Disposal renders this inside its own tab bar, which already has
    // a shell of its own.
    return widget.readOnly
        ? body
        : AppShell(currentRoute: '/perishable-goods', child: body);
  }
}

class _CountChip extends StatelessWidget {
  final int count;
  const _CountChip({required this.count});

  @override
  Widget build(BuildContext context) {
    final color = context.colors.dangerRed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('$count',
            style: TextStyle(
                color: color, fontSize: 20, fontWeight: FontWeight.bold)),
        Text('Awaiting disposal',
            style:
                TextStyle(color: context.colors.textSecondary, fontSize: 12)),
      ]),
    );
  }
}

/// How long this item has been waiting. Perishables spoil, so the number
/// matters more here than on any other page — it reddens as it grows.
