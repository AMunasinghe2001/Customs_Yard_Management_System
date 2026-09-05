import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/error_view.dart';
import '../../widgets/empty_table_state.dart';
import '../../widgets/package_details_dialog.dart';
import '../../widgets/table_pager.dart';
import '../../widgets/tooltip_text.dart';
import '../../widgets/date_range_picker_dialog.dart' as custom;
import '../../widgets/year_filter.dart';

final oldEntrySearchProvider = StateProvider<String>((ref) => '');

/// Old Entries — packages registered under "Old Entry" mode, i.e. migrated from
/// a previous/legacy register. Shows the old SR number next to the new one.
/// The goods still flow through the normal package process; this page is just a
/// dedicated view of the migrated entries.
class OldEntriesScreen extends ConsumerStatefulWidget {
  const OldEntriesScreen({super.key});

  @override
  ConsumerState<OldEntriesScreen> createState() => _OldEntriesScreenState();
}

class _OldEntriesScreenState extends ConsumerState<OldEntriesScreen> {
  final _searchCtrl = TextEditingController();
  DateTimeRange? _dateRange;
  String? _yearFilter;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchCtrl.text = ref.read(oldEntrySearchProvider);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ⚠️ `_extractYears` moved into `getOldEntryYears`. It scanned FOUR places
  // a year can appear -- the old SR number, the new one, the entry date and
  // the CusDec date -- because a legacy entry filed under one numbering and
  // re-registered under another has to be findable by either year. That rule
  // is unchanged; it just runs over the whole table now instead of over
  // whatever twenty rows happen to be on screen.

  @override
  Widget build(BuildContext context) {
    // ⚠️ Every filter is in the key. "Has a legacy SR number" is not one of
    // them -- it is the list's DEFINITION, applied in the query itself.
    final query = OldEntryQuery(
      page: _page,
      search: ref.watch(oldEntrySearchProvider),
      dateStart: _dateRange?.start,
      dateEnd: _dateRange?.end,
      year: _yearFilter,
    );
    final packagesAsync = ref.watch(oldEntriesPageProvider(query));
    final storageRate = ref.watch(storageRateProvider).valueOrNull ??
        const <DateTime, double>{};
    // Read through the query above; the listener still resets the page so a
    // new search starts at the top rather than on page 4 of the old result.
    ref.listen(oldEntrySearchProvider, (_, __) => setState(() => _page = 0));

    return AppShell(
      currentRoute: '/old-entries',
      child: Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Old Entries',
                      style: Theme.of(context).textTheme.headlineLarge),
                  Text(
                    'Packages migrated from a previous register (old SR → new SR)',
                    style: TextStyle(color: context.colors.textSecondary),
                  ),
                ],
              ).animate().slideY(begin: 0.1, duration: 400.ms).fadeIn(),
              const Gap(20),

              // ── Search & Filter Bar ──────────────────────────────
              packagesAsync.maybeWhen(
                data: (result) {
                  // ⚠️ From its own query, over all four places a year can
                  // appear -- not from the twenty rows on screen, which would
                  // offer only the years currently visible.
                  final availableYears =
                      ref.watch(oldEntryYearsProvider).valueOrNull ??
                          const <String>[];

                  return Container(
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
                            hintText:
                                'Search by old SR, new SR, cusdec or consignee...',
                            prefixIcon: Icon(Icons.search_rounded,
                                color: context.colors.textMuted),
                            suffixIcon: _searchCtrl.text.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.clear_rounded,
                                        color: context.colors.textMuted),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      ref
                                          .read(oldEntrySearchProvider.notifier)
                                          .state = '';
                                    },
                                  )
                                : null,
                            isDense: true,
                          ),
                          onChanged: (v) => ref
                              .read(oldEntrySearchProvider.notifier)
                              .state = v,
                        ),
                        const Gap(10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await showDialog<DateTimeRange>(
                                  context: context,
                                  builder: (_) => custom.DateRangePickerDialog(
                                      initialRange: _dateRange),
                                );
                                if (picked != null) {
                                  setState(() {
                                    _dateRange = picked;
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
                                _dateRange == null
                                    ? 'Date Range'
                                    : '${DateFormat('yyyy-MM-dd').format(_dateRange!.start)} → ${DateFormat('yyyy-MM-dd').format(_dateRange!.end)}',
                                style: TextStyle(
                                    color: _dateRange != null
                                        ? context.colors.primaryGold
                                        : context.colors.textSecondary,
                                    fontWeight: _dateRange != null
                                        ? FontWeight.bold
                                        : FontWeight.normal),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                    color: _dateRange != null
                                        ? context.colors.primaryGold
                                        : context.colors.borderColor),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
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
                            const SizedBox(width: 4),
                            YearFilterButton(
                              value: _yearFilter,
                              years: availableYears,
                              onChanged: (v) => setState(() {
                                _yearFilter = v;
                                _page = 0;
                              }),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              )
                  .animate()
                  .slideY(begin: 0.1, duration: 400.ms, delay: 200.ms)
                  .fadeIn(),
              const Gap(16),

              // ── Table ───────────────────────────────────────────
              Expanded(
                child: packagesAsync.when(
                  loading: () => Center(
                      child: CircularProgressIndicator(
                          color: context.colors.primaryGold)),
                  error: (e, _) => ErrorView(
                      error: e,
                      onRetry: () =>
                          ref.refresh(oldEntriesPageProvider(query))),
                  data: (result) {
                    // Filtered, sorted and paged by the database — including
                    // the "has a legacy SR number" definition of this list.
                    final pageRows = result.rows;
                    final maxPage = result.total == 0
                        ? 0
                        : (result.total - 1) ~/ kDispositionPageSize;
                    if (_page > maxPage) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _page = maxPage);
                      });
                    }

                    return Column(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                                color: context.colors.cardDark,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: context.colors.borderColor)),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: DataTable2(
                                columnSpacing: 12,
                                horizontalMargin: 12,
                                fixedTopRows: 1,
                                empty: const EmptyTableState(
                                    message: 'No old entries yet'),
                                isVerticalScrollBarVisible: true,
                                columns: const [
                                  DataColumn2(
                                      label: Text('Old SR Number'),
                                      size: ColumnSize.M),
                                  DataColumn2(
                                      label: Text('New SR Number'),
                                      size: ColumnSize.M),
                                  DataColumn2(
                                      label: Text('Cusdec No'),
                                      size: ColumnSize.S,
                                      fixedWidth: 130),
                                  DataColumn2(
                                      label: Text('Cusdec Date'),
                                      size: ColumnSize.S,
                                      fixedWidth: 120),
                                  DataColumn2(
                                      label: Text('Entry Date'),
                                      size: ColumnSize.S,
                                      fixedWidth: 120),
                                  DataColumn2(
                                      label: Text('Consignee'),
                                      size: ColumnSize.M),
                                  DataColumn2(
                                      label: Center(child: Text('Details')),
                                      size: ColumnSize.S,
                                      fixedWidth: 60),
                                ],
                                rows: pageRows
                                    .map((p) => DataRow(cells: [
                                          DataCell(TooltipText(
                                              p.oldSrNumber ?? '—',
                                              style: TextStyle(
                                                  color: context
                                                      .colors.primaryGold,
                                                  fontWeight:
                                                      FontWeight.w600))),
                                          DataCell(TooltipText(p.srNumber,
                                              style: TextStyle(
                                                  color: context.colors
                                                      .accentLightBlue,
                                                  fontWeight:
                                                      FontWeight.w600))),
                                          DataCell(TooltipText(
                                              (p.cusdecNo == null ||
                                                      p.cusdecNo!.isEmpty)
                                                  ? '—'
                                                  : p.cusdecNo!,
                                              overflow:
                                                  TextOverflow.ellipsis)),
                                          DataCell(TooltipText(
                                              (p.cusdecDate == null ||
                                                      p.cusdecDate!.isEmpty)
                                                  ? '—'
                                                  : p.cusdecDate!)),
                                          DataCell(TooltipText(p.entryDate !=
                                                  null
                                              ? DateFormat('yyyy-MM-dd')
                                                  .format(p.entryDate!)
                                              : '—')),
                                          DataCell(TooltipText(
                                              p.consigneeName,
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
                                                package: p,
                                                storageRate: storageRate,
                                                useLegacySummary: true,
                                              ),
                                            ),
                                          ))),
                                        ]))
                                    .toList(),
                              ),
                            ),
                          ),
                        ),
                        TablePager(
                          // The database's count for this filter.
                          total: result.total,
                          page: _page.clamp(0, maxPage),
                          pageSize: kDispositionPageSize,
                          onPageChanged: (p) => setState(() => _page = p),
                        ),
                      ],
                    )
                        // ⚠️ The table has to arrive like every other page's.
                        // The header and the filter bar above it were already
                        // animated and this was not, so the two slid in and
                        // the rows simply appeared underneath them — which
                        // read as the table snapping into place.
                        //
                        // Same 400ms slide and the same 300ms delay the other
                        // tables use, so it lands just after the filter bar
                        // rather than racing it.
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
