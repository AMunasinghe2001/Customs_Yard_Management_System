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
import '../../widgets/table_pager.dart';
import '../../widgets/year_filter.dart';
import '../../widgets/date_range_picker_dialog.dart' as custom;
import '../../widgets/package_details_dialog.dart';
import '../executive/unsold_shared.dart';

/// The yard's own packages that could not be sold by any means.
///
/// READ-ONLY: the Top Management Directorate decides the final outcome; this page tells the
/// yard what was decided so they can act on goods still sitting in their
/// warehouses.
///
/// One widget serves SIX pages. With [proposalFilter] null it lists every
/// unsold package (the Unsold Goods page); set to an outcome code it lists
/// only the goods decided that way — Government Use, Remand, Convert and
/// "Removed from the Premises" each get their own page that way, without
/// duplicating the header, filters, table and pager five times over.
///
/// Laid out to match the Sold Packages page exactly — same header, same search
/// + Date Range + Year + status chips card, same table shell and pager.
class UnsoldPackagesScreen extends ConsumerStatefulWidget {
  /// The route this page is mounted at, so the sidebar highlights correctly.
  final String route;

  /// Page title and the line under it.
  final String title;
  final String subtitle;

  /// The word beside the count in the header ("3 Unsold").
  final String countLabel;

  /// One of [kUnsoldProposals], or null to list every unsold package.
  ///
  /// When set, the status chips are hidden: every row already carries the same
  /// outcome, so filtering by "decided" would be meaningless.
  final String? proposalFilter;

  const UnsoldPackagesScreen({
    super.key,
    this.route = '/unsold-packages',
    this.title = 'Unsold Goods',
    this.subtitle = 'Goods that could not be sold by any means',
    this.countLabel = 'Unsold',
    this.proposalFilter,
  });

  @override
  ConsumerState<UnsoldPackagesScreen> createState() =>
      _UnsoldPackagesScreenState();
}

class _UnsoldPackagesScreenState extends ConsumerState<UnsoldPackagesScreen> {
  static const int _pageSize = 20;

  final _searchCtrl = TextEditingController();
  String _search = '';
  DateTimeRange? _dateRange;
  String? _yearFilter;

  /// null = all · false = awaiting the Top Management Directorate · true = decided
  bool? _decidedFilter;
  int _page = 0;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Status chip, styled exactly like the Sold page's delivery filter.
  Widget _statusChip(String label, bool? value, IconData icon) {
    final selected = _decidedFilter == value;
    final color = context.colors.primaryGold;
    return OutlinedButton.icon(
      onPressed: () => setState(() {
        _decidedFilter = value;
        _page = 0;
      }),
      icon: Icon(icon,
          size: 16, color: selected ? color : context.colors.textSecondary),
      label: Text(label,
          style: TextStyle(
              color: selected ? color : context.colors.textSecondary,
              fontSize: 12,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: selected ? color : context.colors.borderColor),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  /// The rows for this yard, before search/date/year/status filtering.
  List<ReTenderSaleInfo> _yardRows(List<ReTenderSaleInfo> all, String? myYard) {
    // RLS already scopes reads, but the shared provider is cross-yard.
    if (myYard == null) return all;
    return all.where((i) => i.forfeited.yard == myYard).toList();
  }

  /// This yard's rows, narrowed to the outcome this page is for.
  ///
  /// The header count and the table must agree, so both go through here — an
  /// outcome page that counted every unsold package would contradict its own
  /// list.
  List<ReTenderSaleInfo> _visibleRows(List<ReTenderSaleInfo> all,
      String? myYard, Map<String, UnsoldProposalModel> proposals) {
    final mine = _yardRows(all, myYard);
    final want = widget.proposalFilter;
    if (want == null) return mine;
    return mine
        .where((i) => proposals[i.forfeited.id]?.proposal == want)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final gold = context.colors.primaryGold;
    final async = ref.watch(exhaustedUnsoldProvider);
    final proposals =
        ref.watch(unsoldProposalsProvider).valueOrNull ?? const {};
    final storageRate = ref.watch(storageRateProvider).valueOrNull ??
        {DateTime(2020, 1, 1): 50.0};
    final myYard = ref.watch(currentProfileProvider)?.yard;

    return AppShell(
      currentRoute: widget.route,
      child: Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 16,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title,
                            style: Theme.of(context).textTheme.headlineLarge),
                        Text(widget.subtitle,
                            style:
                                TextStyle(color: context.colors.textSecondary)),
                      ],
                    ),
                    async.when(
                      data: (list) => Text(
                          '${_visibleRows(list, myYard, proposals).length} '
                          '${widget.countLabel}',
                          style: TextStyle(
                              color: context.colors.textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.bold)),
                      loading: () => const SizedBox(),
                      error: (_, __) => const SizedBox(),
                    ),
                  ],
                ),
              ).animate().fadeIn(),
              const Gap(20),

              // ── Search + filters ────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.colors.cardDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: gold.withOpacity(0.5)),
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
                        suffixIcon: _search.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear_rounded,
                                    color: context.colors.textMuted),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() {
                                    _search = '';
                                    _page = 0;
                                  });
                                },
                              )
                            : null,
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() {
                        _search = v;
                        _page = 0;
                      }),
                    ),
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
                              builder: (context) =>
                                  custom.DateRangePickerDialog(
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
                                  ? gold
                                  : context.colors.textSecondary),
                          label: Text(
                            _dateRange != null
                                ? '${DateFormat('MMM d').format(_dateRange!.start)} - ${DateFormat('MMM d').format(_dateRange!.end)}'
                                : 'Date Range',
                            style: TextStyle(
                                color: _dateRange != null
                                    ? gold
                                    : context.colors.textSecondary,
                                fontSize: 12,
                                fontWeight: _dateRange != null
                                    ? FontWeight.bold
                                    : FontWeight.normal),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: _dateRange != null
                                    ? gold
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
                        YearFilterButton(
                          value: _yearFilter,
                          years: srYears(async.valueOrNull == null
                              ? const <String>[]
                              : _yardRows(async.valueOrNull!, myYard)
                                  .map((r) => r.forfeited.srNumber)),
                          onChanged: (v) => setState(() {
                            _yearFilter = v;
                            _page = 0;
                          }),
                        ),
                        // Hidden on an outcome page: every row there is
                        // already decided the same way, so filtering by
                        // decided/awaiting would offer nothing.
                        if (widget.proposalFilter == null) ...[
                          _statusChip('All', null, Icons.all_inbox_rounded),
                          _statusChip('Awaiting decision', false,
                              Icons.schedule_rounded),
                          _statusChip(
                              'Decided', true, Icons.check_circle_rounded),
                        ],
                      ],
                    ),
                  ],
                ),
              )
                  .animate()
                  .slideY(begin: 0.1, duration: 400.ms, delay: 200.ms)
                  .fadeIn(),

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
                    // Same narrowing the header count uses, so the two can
                    // never disagree.
                    final rows =
                        _visibleRows(list, myYard, proposals).where((info) {
                      final f = info.forfeited;
                      if (_search.isNotEmpty) {
                        final s = _search.toLowerCase();
                        if (!f.srNumber.toLowerCase().contains(s) &&
                            !f.consigneeName.toLowerCase().contains(s) &&
                            !unsoldItemName(f).toLowerCase().contains(s)) {
                          return false;
                        }
                      }
                      if (_dateRange != null) {
                        final d = f.forfeitedAt;
                        final start = DateTime(_dateRange!.start.year,
                            _dateRange!.start.month, _dateRange!.start.day);
                        final end = DateTime(
                            _dateRange!.end.year,
                            _dateRange!.end.month,
                            _dateRange!.end.day,
                            23,
                            59,
                            59);
                        if (d.isBefore(start) || d.isAfter(end)) return false;
                      }
                      if (_yearFilter != null &&
                          !f.srNumber.endsWith('/$_yearFilter')) {
                        return false;
                      }
                      if (_decidedFilter != null &&
                          proposals.containsKey(f.id) != _decidedFilter) {
                        return false;
                      }
                      return true;
                    }).toList();

                    final maxPage =
                        rows.isEmpty ? 0 : (rows.length - 1) ~/ _pageSize;
                    final page = _page.clamp(0, maxPage);
                    final pageRows =
                        rows.skip(page * _pageSize).take(_pageSize);

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
                                // Wider than the viewport on purpose: the
                                // table scrolls sideways so no column is
                                // squeezed out.
                                minWidth: kUnsoldTableMinWidth,
                                empty: const EmptyTableState(
                                    message: 'No unsold packages in this yard'),
                                headingRowColor: WidgetStateProperty.all(
                                    context.colors.surfaceDark),
                                // An outcome page already filters to one
                                // outcome, so a Final Outcome column would
                                // repeat the page title on every row; it shows
                                // the decision DATE instead.
                                columns: widget.proposalFilter == null
                                    ? kUnsoldColumns
                                    : kUnsoldDecidedColumns,
                                rows: pageRows.map((info) {
                                  final f = info.forfeited;
                                  final pkg = f.packageDetails;
                                  final qty = unsoldQty(f);
                                  return DataRow(
                                    cells: unsoldCells(
                                      context,
                                      info: info,
                                      srColor: gold,
                                      // Plain text on the yard table — the
                                      // green highlight is for the portals
                                      // that act on the money.
                                      valuationColor:
                                          context.colors.textPrimary,
                                      // READ-ONLY: the DG decides, the yard
                                      // acts on what was decided.
                                      outcome: widget.proposalFilter == null
                                          ? Center(
                                              child: UnsoldOutcomeChip(
                                                  proposal: proposals[f.id]),
                                            )
                                          : unsoldDecidedOnCell(
                                              context, proposals[f.id]),
                                      onDetails: pkg == null
                                          ? null
                                          : () => showDialog(
                                                context: context,
                                                builder: (_) =>
                                                    PackageDetailsDialog(
                                                  package: pkg,
                                                  storageRate: storageRate,
                                                  // No headerAccentColor: the
                                                  // yard's other pages (Sold,
                                                  // Abandoned, ...) use the
                                                  // default blue header, and
                                                  // this popup must match.
                                                  useLegacySummary: true,
                                                  highlightItemId: f.itemId,
                                                  valuationUnitCost:
                                                      f.valuationCost,
                                                  valuationTotalCost:
                                                      f.valuationCost != null
                                                          ? f.valuationCost! *
                                                              qty
                                                          : null,
                                                  valuationQty: qty,
                                                  tenderHistoryFor: f,
                                                ),
                                              ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                        TablePager(
                          total: rows.length,
                          page: page,
                          pageSize: _pageSize,
                          onPageChanged: (p) => setState(() => _page = p),
                        ),
                      ],
                    )
                        .animate()
                        .slideY(begin: 0.1, duration: 400.ms, delay: 300.ms)
                        .fadeIn();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
