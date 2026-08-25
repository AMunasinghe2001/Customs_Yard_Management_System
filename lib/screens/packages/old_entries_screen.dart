import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../models/models.dart';
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

  List<String> _extractYears(List<PackageModel> packages) {
    final yearRegex = RegExp(r'\b(19\d\d|20\d\d)\b');
    final years = <String>{};
    for (final p in packages) {
      if (p.oldSrNumber != null) {
        for (final m in yearRegex.allMatches(p.oldSrNumber!)) {
          if (m.group(1) != null) years.add(m.group(1)!);
        }
      }
      for (final m in yearRegex.allMatches(p.srNumber)) {
        if (m.group(1) != null) years.add(m.group(1)!);
      }
      if (p.entryDate != null) {
        years.add(p.entryDate!.year.toString());
      }
      if (p.cusdecDate != null) {
        for (final m in yearRegex.allMatches(p.cusdecDate!)) {
          if (m.group(1) != null) years.add(m.group(1)!);
        }
      }
    }
    return years.toList()..sort((a, b) => b.compareTo(a));
  }

  @override
  Widget build(BuildContext context) {
    final packagesAsync = ref.watch(livePackagesProvider);
    final storageRate = ref.watch(storageRateProvider).valueOrNull ??
        const <DateTime, double>{};
    final search = ref.watch(oldEntrySearchProvider);
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
                data: (packages) {
                  final oldPackages = packages
                      .where((p) =>
                          p.oldSrNumber != null &&
                          p.oldSrNumber!.trim().isNotEmpty)
                      .toList();
                  final availableYears = _extractYears(oldPackages);

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
                      onRetry: () => ref.refresh(livePackagesProvider)),
                  data: (packages) {
                    // Only packages that carry a legacy SR number.
                    var rows = packages
                        .where((p) =>
                            p.oldSrNumber != null &&
                            p.oldSrNumber!.trim().isNotEmpty)
                        .toList();

                    // Apply Year filter
                    if (_yearFilter != null) {
                      final y = _yearFilter!;
                      rows = rows.where((p) {
                        final oldHas = (p.oldSrNumber ?? '').contains(y);
                        final newHas = p.srNumber.contains(y);
                        final entryHas = p.entryDate?.year.toString() == y;
                        final cusdecDateHas = (p.cusdecDate ?? '').contains(y);
                        return oldHas || newHas || entryHas || cusdecDateHas;
                      }).toList();
                    }

                    // Apply Date Range filter
                    if (_dateRange != null) {
                      final start = DateTime(_dateRange!.start.year,
                          _dateRange!.start.month, _dateRange!.start.day);
                      final end = DateTime(
                          _dateRange!.end.year,
                          _dateRange!.end.month,
                          _dateRange!.end.day,
                          23,
                          59,
                          59);
                      rows = rows.where((p) {
                        final date = p.entryDate ?? p.createdAt;
                        return (date.isAfter(start) ||
                                date.isAtSameMomentAs(start)) &&
                            (date.isBefore(end) || date.isAtSameMomentAs(end));
                      }).toList();
                    }

                    final q = search.trim().toLowerCase();
                    if (q.isNotEmpty) {
                      rows = rows
                          .where((p) =>
                              (p.oldSrNumber ?? '')
                                  .toLowerCase()
                                  .contains(q) ||
                              p.srNumber.toLowerCase().contains(q) ||
                              p.consigneeName.toLowerCase().contains(q) ||
                              (p.cusdecNo ?? '').toLowerCase().contains(q))
                          .toList();
                    }
                    rows.sort((a, b) => b.createdAt.compareTo(a.createdAt));

                    final pageRows = rows
                        .skip(_page * kClientPageSize)
                        .take(kClientPageSize)
                        .toList();

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
                          total: rows.length,
                          page: _page,
                          pageSize: kClientPageSize,
                          onPageChanged: (p) => setState(() => _page = p),
                        ),
                      ],
                    );
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
