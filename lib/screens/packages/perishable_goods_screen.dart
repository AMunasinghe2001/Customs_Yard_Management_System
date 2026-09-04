import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../core/post_status_activities.dart';
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
import '../../widgets/styled_dropdown.dart';
import '../../widgets/date_range_picker_dialog.dart' as custom;
import '../forfeited_packages/disposal_request_dialog.dart';
import '../executive/unsold_shared.dart';
import '../../widgets/destruction_status_pill.dart';
import '../disposal/disposal_shared.dart';

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
  // ⚠️ An item the DG has ruled on STAYS on this page. It has been sent, so
  // `sentKeys` holds it -- but dropping it would mean the yard and Central
  // Disposal never see the decision at all: the goods would simply vanish
  // from the only page that lists them. The row stays, carrying its outcome.
  //
  // ⚠️ NOT awaited. Awaiting it would make the whole list wait on the
  // outcomes query, so a slow or unavailable one leaves the page empty rather
  // than merely un-annotated -- and the goods matter more than the label.
  final decided =
      ref.watch(unsoldProposalsByItemProvider).valueOrNull ?? const {};

  final rows = <PerishableRow>[];
  for (final p in packages) {
    for (final i in p.items) {
      if (i.nature != kNaturePerishable) continue;
      // Once sent it belongs to the disposal request, not here -- unless a
      // final outcome has come back for it.
      if (sentKeys.contains('${p.id}:${i.id}') && !decided.containsKey(i.id)) {
        continue;
      }
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

class _PerishableGoodsScreenState extends ConsumerState<PerishableGoodsScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  String? _yearFilter;

  /// ⚠️ The same two filters the yard's Other Goods page offers, because this
  /// is the same kind of page: a yard officer looking through goods it holds.
  /// It had only a search box and a year, so narrowing to "what came in last
  /// week" or "what is marked for immediate disposal" — the two questions the
  /// other held-goods pages answer — could not be asked here at all.
  DateTimeRange? _dateRange;
  String _activity = 'all';

  /// Central Disposal only: which yard's goods to show. Null = every yard.
  String? _yardFilter;
  int _page = 0;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// The search box, built once and placed differently by each portal.
  ///
  /// ⚠️ On the YARD it has no border and no fill of its own — the gold card
  /// around it is the border, and drawing a second gold box inside a gold box
  /// is what made this search bar look nothing like the one on Forfeited or
  /// Other. On Central Disposal there is no card, so it keeps its own outline
  /// like every search box in that portal.
  Widget _searchBox(BuildContext context) => SizedBox(
        height: 44,
        child: TextField(
          controller: _searchCtrl,
          style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search SR #, consignee or item...',
            hintStyle:
                TextStyle(color: context.colors.textSecondary, fontSize: 13),
            prefixIcon: Icon(Icons.search_rounded,
                size: 20,
                color: widget.readOnly
                    ? context.colors.primaryGold
                    : context.colors.textMuted),
            suffixIcon: _search.isEmpty
                ? null
                : IconButton(
                    splashRadius: 16,
                    icon: Icon(Icons.close_rounded,
                        size: 16, color: context.colors.textMuted),
                    onPressed: () => setState(() {
                      _searchCtrl.clear();
                      _search = '';
                      _page = 0;
                    }),
                  ),
            filled: widget.readOnly,
            fillColor: context.colors.primaryGold.withOpacity(0.06),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: widget.readOnly
                ? _searchBorder(context)
                : InputBorder.none,
            enabledBorder: widget.readOnly
                ? _searchBorder(context)
                : InputBorder.none,
            focusedBorder: widget.readOnly
                ? _searchBorder(context, focused: true)
                : InputBorder.none,
          ),
          onChanged: (v) => setState(() {
            _search = v;
            _page = 0;
          }),
        ),
      );

  List<PerishableRow> _filter(List<PerishableRow> rows) {
    return rows.where((r) {
      if (!srYearMatches(r.package.srNumber, _yearFilter)) return false;
      if (_dateRange != null) {
        // Falls back to createdAt, as daysWaiting does: entryDate is
        // nullable and a row without one must not vanish from a date filter
        // that its neighbours answer.
        final d = r.package.entryDate ?? r.package.createdAt;
        // Whole days at both ends: a range picked as 1st-3rd must include
        // everything filed ON the 3rd, not stop at its first second.
        final from = DateTime(_dateRange!.start.year, _dateRange!.start.month,
            _dateRange!.start.day);
        final to = DateTime(_dateRange!.end.year, _dateRange!.end.month,
            _dateRange!.end.day, 23, 59, 59);
        if (d.isBefore(from) || d.isAfter(to)) return false;
      }
      if (_activity != 'all' &&
          (r.item.reasons ?? '') != _activity) {
        return false;
      }
      // Matched on the SR number's own yard segment, like every other
      // cross-yard page -- the package's `yard` column can be the filing
      // directorate rather than the yard holding the goods.
      // The SR number carries the yard, which is what the table itself shows.
      if (!matchesYardFilter(_yardFilter, yardOfSrNumber(r.package.srNumber),
          r.package.srNumber)) {
        return false;
      }
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
    // The DG's rulings, keyed by item. Both portals read the same map, so the
    // yard and Central Disposal cannot describe one outcome differently.
    final outcomes = ref.watch(unsoldProposalsByItemProvider).valueOrNull ??
        const <String, UnsoldProposalModel>{};
    final storageRate = ref.watch(storageRateProvider).valueOrNull ??
        {DateTime(2020, 1, 1): 50.0};

    final body = Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      body: Padding(
        // ⚠️ 24 in Central Disposal, 28 on the yard. Every tab in that
        // portal pads at 24, so 28 sat this page's title and its table
        // lower than the tab you switched from.
        padding: EdgeInsets.all(widget.readOnly ? 24 : 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ⚠️ Central Disposal's copy is built as ITS pages are built,
            // not as a yard page with a yard picker bolted on.
            //
            // Every cross-yard tab there -- Sold Goods, Unsold Tenders,
            // Committees -- is: a plain 22pt title, then the search box and
            // the yard picker on that SAME line, then a StatChip on its own
            // line under it. This page instead used DisposalPageHeader (a
            // title with a SUBTITLE and a big trailing count box) and put its
            // controls on a third row, so beside its neighbours it read as a
            // different product: taller, with the count in the wrong place
            // and in a different shape.
            if (widget.readOnly) ...[
              Row(children: [
                Text('Perishable Goods',
                    style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                SizedBox(width: 280, child: _searchBox(context)),
                const Gap(12),
                // ⚠️ No year filter here. Not one cross-yard tab in this
                // portal carries one -- they narrow by yard and by search --
                // and it was the extra control that made this header a
                // different shape from the tab beside it. The yard's own copy
                // keeps it, where the held-goods pages all have one.
                // This page watches EVERY yard here, so without it an officer
                // cannot narrow to the one they are dealing with.
                YardAllFilter(
                  value: _yardFilter,
                  onChanged: (v) => setState(() {
                    _yardFilter = v;
                    _page = 0;
                  }),
                ),
              ]).animate().fadeIn(duration: 300.ms),
              const Gap(14),
              async.maybeWhen(
                data: (rows) => Padding(
                  // The chip carries the gap under it, as it does on Unsold
                  // Tenders -- a Gap() as well would double it.
                  padding: const EdgeInsets.only(bottom: 14),
                  child: StatChip(
                    label: 'Awaiting disposal',
                    // Counts the rows the TABLE shows, so the number and the
                    // list can never disagree.
                    value: '${_filter(rows).length}',
                    color: context.colors.dangerRed,
                  ),
                ).animate().fadeIn(duration: 300.ms),
                orElse: () => const SizedBox.shrink(),
              ),
            ] else
              DisposalPageHeader(
                title: 'Perishable Goods',
                subtitle: 'Goods that spoil — no warehouse, no appeal window. '
                    'Send them for disposal without waiting.',
                trailing: [
                  async.maybeWhen(
                    data: (rows) => _CountChip(count: _filter(rows).length),
                    orElse: () => const SizedBox(),
                  ),
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
            if (!widget.readOnly) const Gap(20),
            // ⚠️ Boxed, like Forfeited and Other beside it. Every held-goods
            // page on the yard puts its search box and its filters INSIDE one
            // gold-bordered card, so the controls read as one panel and the
            // table below it starts at a clear edge. This page left them bare
            // on the page, which is why it looked like a different screen
            // however closely the individual controls matched.
            if (!widget.readOnly)
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
              _searchBox(context),
              const Gap(8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDialog<dynamic>(
                        context: context,
                        builder: (context) => custom.DateRangePickerDialog(
                            initialRange: _dateRange),
                      );
                      if (picked is DateTimeRange) {
                        setState(() {
                          _dateRange = picked;
                          _page = 0;
                        });
                      } else if (picked == false) {
                        setState(() {
                          _dateRange = null;
                          _page = 0;
                        });
                      }
                    },
                    icon: Icon(Icons.date_range_rounded,
                        size: 16,
                        color: _dateRange != null
                            ? context.colors.primaryGold
                            : context.colors.textSecondary),
                    label: Text(
                      _dateRange != null
                          ? '${DateFormat('MMM d').format(_dateRange!.start)} - '
                              '${DateFormat('MMM d').format(_dateRange!.end)}'
                          : 'Date Range',
                      style: TextStyle(
                          color: _dateRange != null
                              ? context.colors.primaryGold
                              : context.colors.textSecondary,
                          fontSize: 12,
                          fontWeight: _dateRange != null
                              ? FontWeight.bold
                              : FontWeight.normal),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: _dateRange != null
                              ? context.colors.primaryGold
                              : context.colors.borderColor),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  if (_dateRange != null)
                    IconButton(
                      icon: Icon(Icons.clear_rounded,
                          size: 16, color: context.colors.dangerRed),
                      onPressed: () => setState(() {
                        _dateRange = null;
                        _page = 0;
                      }),
                      tooltip: 'Clear Date Filter',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  const SizedBox(width: 8),
                  StyledDropdownButton<String>(
                    value: _activity == 'all' ? null : _activity,
                    allLabel: 'Post Status Activity',
                    icon: Icons.label_outline_rounded,
                    menuWidth: 320,
                    // ⚠️ EVERY activity, unfiltered. A perishable is
                    // registered under whatever activity the officer chose,
                    // and the list is not narrowed for this page -- see the
                    // SR form, which offers them all here for the same
                    // reason.
                    options: kAllPostStatusActivities
                        .map((a) => StyledDropdownOption(a, a))
                        .toList(),
                    onChanged: (v) => setState(() {
                      _activity = v ?? 'all';
                      _page = 0;
                    }),
                  ),
                  const SizedBox(width: 8),
                  YearFilterButton(
                    value: _yearFilter,
                    years: srYears(
                        async.valueOrNull?.map((r) => r.package.srNumber) ??
                            const <String>[]),
                    onChanged: (v) => setState(() {
                      _yearFilter = v;
                      _page = 0;
                    }),
                  ),
                ],
              ),
                  ],
                ),
              )
                  .animate()
                  .slideY(begin: 0.1, duration: 400.ms, delay: 200.ms)
                  .fadeIn(),
            if (!widget.readOnly) const Gap(16),
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
                            border:
                                Border.all(color: context.colors.borderColor),
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
                                //
                                // The DG's ruling, once there is one. Both the
                                // yard and Central Disposal read the SAME chip
                                // the Top Management portal shows, so the three
                                // cannot describe one outcome differently.
                                const DataColumn2(
                                    label: Center(child: Text('Final Outcome')),
                                    size: ColumnSize.S,
                                    // The shared constant, so this column and
                                    // the Destroyed/Delivered ones stay in
                                    // step when the pill width changes.
                                    fixedWidth: kDestructionStatusColumnWidth),
                                const DataColumn2(
                                    label: Center(child: Text('Details')),
                                    size: ColumnSize.S,
                                    fixedWidth: 60),
                              ],
                              rows: pageRows
                                  .map((r) => DataRow(cells: [
                                        DataCell(TooltipText(r.package.srNumber,
                                            style: TextStyle(
                                                color: context
                                                    .colors.accentLightBlue,
                                                fontWeight: FontWeight.w600))),
                                        DataCell(TooltipText(r.item.itemName,
                                            overflow: TextOverflow.ellipsis)),
                                        DataCell(
                                            TooltipText('${r.item.quantity}')),
                                        DataCell(TooltipText(
                                            r.package.consigneeName,
                                            overflow: TextOverflow.ellipsis)),
                                        DataCell(TooltipText(
                                            DateFormat('yyyy-MM-dd').format(
                                                r.package.entryDate ??
                                                    r.package.createdAt))),
                                        if (widget.readOnly)
                                          DataCell(TooltipText(
                                              yardName(yardOfSrNumber(
                                                  r.package.srNumber)),
                                              overflow: TextOverflow.ellipsis)),
                                        DataCell(Center(
                                            child: UnsoldOutcomeChip(
                                                proposal:
                                                    outcomes[r.item.id]))),
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
                                                // ⚠️ Central Disposal tints
                                                // every one of its dialogs
                                                // with the portal's green.
                                                // This page passed none, so
                                                // it fell back to the default
                                                // indigo and was the only
                                                // popup in that portal
                                                // wearing another colour.
                                                headerAccentColor:
                                                    widget.readOnly
                                                        ? context.colors
                                                            .successGreen
                                                        : null,
                                                yardLabel: widget.readOnly
                                                    ? yardName(yardOfSrNumber(
                                                        r.package.srNumber))
                                                    : null,
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

/// The search field's border, matching `DisposalSearch` on every other
/// Central Disposal tab (14px radius, gold at 0.4, 1.5px when focused).
OutlineInputBorder _searchBorder(BuildContext context,
        {bool focused = false}) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: focused
            ? context.colors.primaryGold
            : context.colors.primaryGold.withOpacity(0.4),
        width: focused ? 1.5 : 1,
      ),
    );

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
