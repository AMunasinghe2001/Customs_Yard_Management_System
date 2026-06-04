import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/providers.dart';
import '../../models/models.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/error_view.dart';
import '../../widgets/empty_table_state.dart';
import '../../widgets/package_details_dialog.dart';
import '../../widgets/date_range_picker_dialog.dart' as custom;
import 'package:data_table_2/data_table_2.dart';

/// Generic screen for a final-disposition category (Sold / Destroyed /
/// Re-exported / Other). Reads warehouse entries tagged "[FINAL:<TAG>]".
class DispositionCategoryScreen extends ConsumerStatefulWidget {
  final String route;
  final String title;
  final String subtitle;
  final String countLabel;
  final String finalTag; // e.g. SOLD, DESTROYED, RE-EXPORTED, OTHER

  const DispositionCategoryScreen({
    super.key,
    required this.route,
    required this.title,
    required this.subtitle,
    required this.countLabel,
    required this.finalTag,
  });

  @override
  ConsumerState<DispositionCategoryScreen> createState() =>
      _DispositionCategoryScreenState();
}

class _DispositionCategoryScreenState
    extends ConsumerState<DispositionCategoryScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  DateTimeRange? _dateRange;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matchesTag(WarehouseEntryModel e) {
    final notes = (e.returnNotes ?? '').trim().toUpperCase();
    return notes.startsWith('[FINAL:${widget.finalTag}');
  }

  String _extractNote(String? returnNotes) {
    if (returnNotes == null) return '';
    final idx = returnNotes.indexOf('—');
    if (idx == -1) return '';
    return returnNotes.substring(idx + 1).trim();
  }

  List<_CategoryRow> _buildRows(List<PackageModel> packages) {
    final rows = <_CategoryRow>[];
    for (final package in packages) {
      for (final entry in package.warehouseEntries) {
        if (!_matchesTag(entry)) continue;
        final item = package.items
            .where((i) => i.id == entry.packageItemId)
            .firstOrNull;
        rows.add(_CategoryRow(
          package: package,
          entry: entry,
          itemName: item?.itemName ??
              (package.items.isNotEmpty
                  ? package.items.first.itemName
                  : '—'),
          note: _extractNote(entry.returnNotes),
          officer: entry.returnedByName ?? entry.returnedByBadge ?? '—',
        ));
      }
    }
    rows.sort((a, b) {
      final aDate = a.entry.returnedAt ?? a.entry.admittedAt;
      final bDate = b.entry.returnedAt ?? b.entry.admittedAt;
      return bDate.compareTo(aDate);
    });
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final packages = ref.watch(livePackagesProvider);
    final storageRateHistory = ref.watch(storageRateProvider).valueOrNull ??
        {DateTime(2020, 1, 1): 50.0};

    return AppShell(
      currentRoute: widget.route,
      child: Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
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
                            style: TextStyle(
                                color: context.colors.textSecondary)),
                      ],
                    ),
                    packages.when(
                      data: (list) {
                        final count = _buildRows(list).length;
                        return Text('$count ${widget.countLabel}',
                            style: TextStyle(
                                color: context.colors.textMuted,
                                fontSize: 13,
                                fontWeight: FontWeight.bold));
                      },
                      loading: () => const SizedBox(),
                      error: (_, __) => const SizedBox(),
                    ),
                  ],
                ),
              ).animate().fadeIn(),
              const Gap(20),

              // Search + date range
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
                        suffixIcon: _search.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear_rounded,
                                    color: context.colors.textMuted),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _search = '');
                                },
                              )
                            : null,
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _search = v),
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
                              setState(() => _dateRange = picked);
                            } else if (picked == false) {
                              setState(() => _dateRange = null);
                            }
                          },
                          icon: Icon(Icons.date_range_rounded,
                              size: 16,
                              color: _dateRange != null
                                  ? context.colors.primaryGold
                                  : context.colors.textSecondary),
                          label: Text(
                            _dateRange != null
                                ? '${DateFormat('MMM d').format(_dateRange!.start)} - ${DateFormat('MMM d').format(_dateRange!.end)}'
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
                            onPressed: () =>
                                setState(() => _dateRange = null),
                            tooltip: 'Clear Date Filter',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
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
                child: packages.when(
                  loading: () => Center(
                      child: CircularProgressIndicator(
                          color: context.colors.primaryGold)),
                  error: (e, _) => ErrorView(
                      error: e,
                      onRetry: () => ref.refresh(livePackagesProvider)),
                  data: (list) {
                    final rows = _buildRows(list).where((row) {
                      if (_search.isNotEmpty) {
                        final s = _search.toLowerCase();
                        if (!row.package.srNumber.toLowerCase().contains(s) &&
                            !row.package.consigneeName
                                .toLowerCase()
                                .contains(s) &&
                            !row.itemName.toLowerCase().contains(s)) {
                          return false;
                        }
                      }
                      if (_dateRange != null) {
                        final date =
                            row.entry.returnedAt ?? row.entry.admittedAt;
                        final startOfDay = DateTime(_dateRange!.start.year,
                            _dateRange!.start.month, _dateRange!.start.day);
                        final endOfDay = DateTime(
                            _dateRange!.end.year,
                            _dateRange!.end.month,
                            _dateRange!.end.day,
                            23,
                            59,
                            59);
                        if (date.isBefore(startOfDay) ||
                            date.isAfter(endOfDay)) return false;
                      }
                      return true;
                    }).toList();

                    return Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                          color: context.colors.cardDark,
                          borderRadius: BorderRadius.circular(14),
                          border:
                              Border.all(color: context.colors.borderColor)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: DataTable2(
                          columnSpacing: 12,
                          horizontalMargin: 12,
                          fixedTopRows: 1,
                          empty: EmptyTableState(
                              message:
                                  'No ${widget.countLabel.toLowerCase()} packages found'),
                          isVerticalScrollBarVisible: true,
                          isHorizontalScrollBarVisible: false,
                          columns: const [
                            DataColumn2(
                                label: Text('SR Number'), size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Item Name'), size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Qty'),
                                size: ColumnSize.S,
                                fixedWidth: 70),
                            DataColumn2(
                                label: Text('Date'), size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Officer'), size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Notes'), size: ColumnSize.M),
                            DataColumn2(
                                label: Center(child: Text('Details')),
                                size: ColumnSize.S,
                                fixedWidth: 55),
                          ],
                          rows: rows
                              .map((row) => DataRow(cells: [
                                    DataCell(Text(row.package.srNumber,
                                        style: TextStyle(
                                            color: context
                                                .colors.accentLightBlue,
                                            fontWeight: FontWeight.w600))),
                                    DataCell(Text(row.itemName,
                                        overflow: TextOverflow.ellipsis)),
                                    DataCell(
                                        Text('${row.entry.itemCount}')),
                                    DataCell(Text(row.entry.returnedAt != null
                                        ? DateFormat('yyyy-MM-dd')
                                            .format(row.entry.returnedAt!)
                                        : '—')),
                                    DataCell(Text(row.officer,
                                        overflow: TextOverflow.ellipsis)),
                                    DataCell(Text(
                                        row.note.isEmpty ? '—' : row.note,
                                        overflow: TextOverflow.ellipsis)),
                                    DataCell(Center(
                                        child: IconButton(
                                      icon: Icon(Icons.info_outline_rounded,
                                          color:
                                              context.colors.accentLightBlue,
                                          size: 18),
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (_) =>
                                              PackageDetailsDialog(
                                            package: row.package,
                                            storageRate: storageRateHistory,
                                            highlightEntry: row.entry,
                                            useLegacySummary: true,
                                          ),
                                        );
                                      },
                                    ))),
                                  ]))
                              .toList(),
                        ),
                      ),
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

class _CategoryRow {
  final PackageModel package;
  final WarehouseEntryModel entry;
  final String itemName;
  final String note;
  final String officer;

  const _CategoryRow({
    required this.package,
    required this.entry,
    required this.itemName,
    required this.note,
    required this.officer,
  });
}
