import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:gap/gap.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/empty_table_state.dart';
import '../../widgets/error_view.dart';
import '../../widgets/date_range_picker_dialog.dart' as custom;
import '../../widgets/year_filter.dart';
import '../../widgets/package_details_dialog.dart';
import 'disposal_request_dialog.dart';

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold, height: 1.1)),
          Text(label, style: TextStyle(color: context.colors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

class ForfeitedPackagesScreen extends ConsumerStatefulWidget {
  const ForfeitedPackagesScreen({super.key});

  @override
  ConsumerState<ForfeitedPackagesScreen> createState() => _ForfeitedPackagesScreenState();
}

/// One forfeiture line — a single item (or disposition event) within a
/// forfeited package. The same SR can yield several rows.
class _ForfeitRow {
  final ForfeitedPackageModel forfeited;
  final String itemName;
  final String? hsCode;
  final int qty;
  final DateTime forfeitedDate;
  final String officer;
  // The specific item + its forfeit warehouse entry this row represents, so
  // the details dialog can highlight exactly this item (like the Abandoned page).
  final PackageItem? item;
  final WarehouseEntryModel? entry;

  const _ForfeitRow({
    required this.forfeited,
    required this.itemName,
    this.hsCode,
    required this.qty,
    required this.forfeitedDate,
    required this.officer,
    this.item,
    this.entry,
  });
}

class _ForfeitedPackagesScreenState extends ConsumerState<ForfeitedPackagesScreen> {
  String _searchQuery = '';
  DateTimeRange? _dateRange;
  String? _yearFilter;

  /// Submits a single-package disposal request (Sale / Destruction) to the
  /// Central Disposal Directorate — used by the details popup's Final
  /// Disposition Sale/Destroy buttons. The package then leaves the Forfeited
  /// list (it is now "requested") and surfaces in the directorate's queue.
  Future<void> _requestSingleDisposal(
      ForfeitedPackageModel fp, String disposition) async {
    try {
      await ref.read(forfeitedPackageServiceProvider).createDisposalRequest(
            requestDate: DateTime.now(),
            dispositions: {fp.id: disposition},
          );
      ref.read(disposalRequestsRefreshProvider.notifier).trigger();
      ref.invalidate(forfeitedPackagesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: context.colors.successGreen,
          content: Text(
              'Disposal request sent for ${fp.srNumber} (${disposition == 'sale' ? 'Sale' : 'Destruction'}).'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: context.colors.dangerRed,
          content: Text('Error: $e'),
        ));
      }
    }
  }

  bool _isForfeitStatus(String? status) {
    if (status == null) return false;
    final normalized = status.trim().toLowerCase();
    return normalized == 'forfiet' || normalized == 'forfeit' || normalized == 'forfeited';
  }

  /// A warehouse entry tagged as a FORFEIT disposition event in returnNotes.
  bool _isForfeitEntry(WarehouseEntryModel e) {
    if (!e.isReturned) return false;
    final notes = (e.returnNotes ?? '').trim().toUpperCase();
    return notes.startsWith('[FORFEIT') || notes.startsWith('[CONFISCATED');
  }

  /// True if the item has moved on to a final disposition — it should no
  /// longer appear in the Forfeit table.
  bool _itemHasFinalDisposition(PackageModel p, String itemId) {
    return p.warehouseEntries.any((e) =>
        e.packageItemId == itemId &&
        (e.returnNotes ?? '').trim().toUpperCase().startsWith('[FINAL:'));
  }

  /// Builds one row per forfeited item / per forfeit disposition event.
  /// A single SR can appear on multiple lines.
  List<_ForfeitRow> _buildForfeitRows(List<ForfeitedPackageModel> packages) {
    final rows = <_ForfeitRow>[];
    for (final fp in packages) {
      final pkg = fp.packageDetails;
      final items = pkg?.items ?? [];
      bool addedAny = false;
      // True once at least one item has been resolved to a final disposition
      // (sold / destroyed / re-exported / …). Such a package has left the
      // forfeit lifecycle, so we must NOT fall back to a summary row for it.
      bool anyItemFinalized = false;

      for (final item in items) {
        // Skip items that have moved to a final disposition.
        if (pkg != null && _itemHasFinalDisposition(pkg, item.id)) {
          anyItemFinalized = true;
          continue;
        }

        final itemEntries = pkg!.warehouseEntries
            .where((e) => e.packageItemId == item.id)
            .toList();

        // 1. Forfeit disposition events (detain → forfeit, partial/full)
        final forfeitEntries = itemEntries.where(_isForfeitEntry).toList();
        for (final entry in forfeitEntries) {
          rows.add(_ForfeitRow(
            forfeited: fp,
            itemName: item.itemName,
            hsCode: item.hsCode,
            qty: entry.itemCount,
            forfeitedDate: entry.returnedAt ?? fp.forfeitedAt,
            officer: entry.returnedByName ?? entry.returnedByBadge ?? '—',
            item: item,
            entry: entry,
          ));
          addedAny = true;
        }

        // 2. Form-level forfeit (item.status forfeit) with no disposition event
        if (_isForfeitStatus(item.status) && forfeitEntries.isEmpty) {
          rows.add(_ForfeitRow(
            forfeited: fp,
            itemName: item.itemName,
            hsCode: item.hsCode,
            qty: item.quantity,
            forfeitedDate: fp.forfeitedAt,
            officer: '—',
            item: item,
            // No forfeit disposition event — fall back to any warehouse entry
            // for this item so the dialog can still show its details.
            entry: itemEntries.firstOrNull,
          ));
          addedAny = true;
        }
      }

      // The Appeal Directorate decided this package should be Sold / Destroyed
      // but the yard admin hasn't sent the disposal request yet — it is still
      // pending an admin action. Keep it on the table (even if some items carry
      // an unrelated [FINAL:…] tag) so the admin can see and act on it.
      final pendingAppealAction = fp.appealRequestDisposition != null;

      // 3. Legacy / no item detail — show a single summary row. Skipped when an
      //    item has already been finalized (sold / destroyed / …) AND there's no
      //    pending appeal action: such a package now lives on its outcome page,
      //    not the Forfeited list.
      if (!addedAny && (!anyItemFinalized || pendingAppealAction)) {
        rows.add(_ForfeitRow(
          forfeited: fp,
          itemName: items.isNotEmpty ? items.first.itemName : 'Multiple/Unspecified',
          hsCode: items.isNotEmpty ? items.first.hsCode : null,
          item: items.isNotEmpty ? items.first : null,
          entry: pkg?.warehouseEntries.firstOrNull,
          qty: items.fold<int>(0, (s, i) => s + i.quantity),
          forfeitedDate: fp.forfeitedAt,
          officer: '—',
        ));
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final forfeitedAsync = ref.watch(forfeitedPackagesProvider);
    final storageRate = ref.watch(storageRateProvider).valueOrNull ??
        {DateTime(2020, 1, 1): 50.0};

    return AppShell(
      currentRoute: '/forfeited-packages',
      child: Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────
              forfeitedAsync.when(
                data: (packages) {
                  // Count the SAME rows the table renders (one per forfeited
                  // item / disposition event) so the header stats always match
                  // the list below — not the raw package count, which includes
                  // packages that produce no forfeit rows (e.g. fully sold).
                  final headerRows = _buildForfeitRows(packages);
                  final totalCount = headerRows.length;
                  final appealingCount = headerRows
                      .where((r) => !r.forfeited.isAppealExpired)
                      .length;
                  final expiredCount = headerRows
                      .where((r) => r.forfeited.isAppealExpired)
                      .length;
                  // The Send-Disposal button enables once ANY package is
                  // actionable: window passed OR an appeal decision is in.
                  final actionableCount = headerRows
                      .where((r) => r.forfeited.isActionable)
                      .length;

                  return SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      runSpacing: 16,
                      children: [
                            Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Forfeited Packages', style: Theme.of(context).textTheme.headlineLarge),
                            const Gap(4),
                            Text(
                              'Manage forfeited packages and their 30-day appeal periods',
                              style: TextStyle(color: context.colors.textSecondary, fontSize: 14),
                            ),
                          ],
                        ).animate().slideY(begin: 0.1, duration: 400.ms).fadeIn(),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _StatChip(label: 'Total', value: totalCount.toString(), color: context.colors.accentLightBlue).animate().slideY(begin: 0.1, duration: 400.ms, delay: 100.ms).fadeIn(),
                            const Gap(8),
                            _StatChip(label: 'In Appeal', value: appealingCount.toString(), color: context.colors.successGreen).animate().slideY(begin: 0.1, duration: 400.ms, delay: 200.ms).fadeIn(),
                            const Gap(8),
                            _StatChip(label: 'Expired', value: expiredCount.toString(), color: context.colors.dangerRed).animate().slideY(begin: 0.1, duration: 400.ms, delay: 300.ms).fadeIn(),
                            const Gap(16),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.local_shipping_rounded, size: 16),
                              label: const Text('Send Disposal Request'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: actionableCount > 0 ? context.colors.primaryGold : context.colors.textMuted.withOpacity(0.2),
                                foregroundColor: actionableCount > 0 ? Colors.white : context.colors.textMuted,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                elevation: actionableCount > 0 ? 2 : 0,
                              ),
                              onPressed: actionableCount > 0
                                  ? () => showDialog(
                                        context: context,
                                        builder: (ctx) => DisposalRequestDialog(
                                          onSubmitted: () => ref.invalidate(forfeitedPackagesProvider),
                                        ),
                                      )
                                  : null,
                            ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 400.ms).fadeIn(),
                          ],
                        ),
                      ],
                    ),
                  );
                },
                loading: () => const SizedBox(),
                error: (_, __) => const SizedBox(),
              ),
              const Gap(24),

              // ── Search Bar ──────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.colors.cardDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.colors.primaryGold.withOpacity(0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      style: TextStyle(color: context.colors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search by SR Number or Consignee...',
                        prefixIcon: Icon(Icons.search_rounded, color: context.colors.textMuted),
                        isDense: true,
                        border: InputBorder.none,
                      ),
                      onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
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
                              builder: (context) => custom.DateRangePickerDialog(
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
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        if (_dateRange != null)
                          IconButton(
                            icon: Icon(Icons.clear_rounded,
                                size: 16, color: context.colors.dangerRed),
                            onPressed: () => setState(() => _dateRange = null),
                            tooltip: 'Clear Date Filter',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        const SizedBox(width: 8),
                        YearFilterButton(
                          value: _yearFilter,
                          years: srYears((forfeitedAsync.valueOrNull ??
                                  const <ForfeitedPackageModel>[])
                              .map((p) => p.srNumber)),
                          onChanged: (v) => setState(() => _yearFilter = v),
                        ),
                      ],
                    ),
                  ],
                ),
              ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 200.ms).fadeIn(),

              const Gap(16),

              // ── Data Table ──────────────────────────────────────
              Expanded(
                child: forfeitedAsync.when(
                  loading: () => Center(child: CircularProgressIndicator(color: context.colors.primaryGold)),
                  error: (error, stackTrace) => ErrorView(
                    error: error.toString(),
                    onRetry: () => ref.refresh(forfeitedPackagesProvider),
                  ),
                  data: (packages) {
                    final filtered = packages.where((pkg) {
                      final srMatch = pkg.srNumber.toLowerCase().contains(_searchQuery);
                      final consigneeMatch = pkg.consigneeName.toLowerCase().contains(_searchQuery);
                      if (!srMatch && !consigneeMatch) return false;
                      if (_dateRange != null) {
                        final date = pkg.forfeitedAt;
                        final startOfDay = DateTime(_dateRange!.start.year,
                            _dateRange!.start.month, _dateRange!.start.day);
                        final endOfDay = DateTime(_dateRange!.end.year,
                            _dateRange!.end.month, _dateRange!.end.day,
                            23, 59, 59);
                        if (date.isBefore(startOfDay) || date.isAfter(endOfDay)) {
                          return false;
                        }
                      }
                      if (!srYearMatches(pkg.srNumber, _yearFilter)) return false;
                      return true;
                    }).toList();

                    final rows = _buildForfeitRows(filtered);

                    if (rows.isEmpty) {
                      return const EmptyTableState(
                              icon: Icons.gavel_outlined,
                              message: 'No forfeited packages found',
                              subtitle:
                                  'Try adjusting the search or date filters.')
                          .animate()
                          .fadeIn();
                    }

                    return Container(
                      decoration: BoxDecoration(
                        color: context.colors.cardDark,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: context.colors.borderColor),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: DataTable2(
                          columnSpacing: 10,
                          horizontalMargin: 16,
                          fixedTopRows: 1,
                          columns: const [
                            DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
                            DataColumn2(label: Text('Item Name'), size: ColumnSize.L),
                            DataColumn2(label: Text('HS Code'), size: ColumnSize.S, fixedWidth: 110),
                            DataColumn2(label: Text('Qty'), size: ColumnSize.S, fixedWidth: 70),
                            DataColumn2(label: Text('Consignee'), size: ColumnSize.M),
                            DataColumn2(label: Text('Forfeited Date'), size: ColumnSize.M),
                            DataColumn2(label: Text('Appeal Deadline'), size: ColumnSize.M),
                            DataColumn2(label: Text('Days Remaining'), size: ColumnSize.S),
                            DataColumn2(label: Center(child: Text('Status')), size: ColumnSize.S),
                            DataColumn2(label: Center(child: Text('Details')), size: ColumnSize.S, fixedWidth: 70),
                          ],
                          rows: rows.map((row) {
                            final pkg = row.forfeited;
                            final isExpired = pkg.isAppealExpired;

                            return DataRow(
                              color: WidgetStateProperty.resolveWith<Color?>((states) {
                                if (isExpired) return context.colors.dangerRed.withOpacity(0.04);
                                return null;
                              }),
                              cells: [
                                DataCell(Text(pkg.srNumber, style: TextStyle(color: context.colors.accentLightBlue, fontWeight: FontWeight.bold))),
                                DataCell(Text(row.itemName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500))),
                                DataCell(Text(
                                    (row.hsCode != null && row.hsCode!.isNotEmpty)
                                        ? row.hsCode!
                                        : '—',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12))),
                                DataCell(Text('${row.qty}')),
                                DataCell(Text(pkg.consigneeName, overflow: TextOverflow.ellipsis)),
                                DataCell(Text(DateFormat('yyyy-MM-dd').format(row.forfeitedDate))),
                                DataCell(Text(
                                  DateFormat('yyyy-MM-dd').format(pkg.appealDeadline),
                                  style: TextStyle(
                                    color: isExpired ? context.colors.dangerRed : context.colors.textPrimary,
                                    fontWeight: isExpired ? FontWeight.bold : FontWeight.normal
                                  ),
                                )),
                                DataCell(Text(
                                  isExpired ? ' overdue' : '',
                                  style: TextStyle(
                                    color: isExpired ? context.colors.dangerRed : context.colors.successGreen,
                                    fontWeight: FontWeight.bold
                                  ),
                                )),
                                DataCell(Center(
                                  child: pkg.appealHold
                                      // Appeal Directorate has placed a hold —
                                      // this package must NOT be sold/destroyed.
                                      ? Tooltip(
                                          message: pkg.appealHoldNote?.isNotEmpty ==
                                                  true
                                              ? pkg.appealHoldNote!
                                              : 'Appeal received — do not sell or destroy',
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: context.colors.warningAmber
                                                  .withOpacity(0.15),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                  color: context
                                                      .colors.warningAmber
                                                      .withOpacity(0.5)),
                                            ),
                                            child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.gavel_rounded,
                                                      size: 12,
                                                      color: context
                                                          .colors.warningAmber),
                                                  const Gap(4),
                                                  Flexible(
                                                    child: Text('APPEAL HOLD',
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                            fontSize: 10.5,
                                                            color: context.colors
                                                                .warningAmber,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w800)),
                                                  ),
                                                ]),
                                          ),
                                        )
                                      : pkg.hasAppealDecision
                                          // Appeal processed — directorate told
                                          // the yard what to do with this package.
                                          ? Tooltip(
                                              message:
                                                  'Appeal decision: ${pkg.appealDecisionLabel}',
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: context
                                                      .colors.accentLightBlue
                                                      .withOpacity(0.12),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  border: Border.all(
                                                      color: context.colors
                                                          .accentLightBlue
                                                          .withOpacity(0.4)),
                                                ),
                                                child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.gavel_rounded,
                                                          size: 12,
                                                          color: context.colors
                                                              .accentLightBlue),
                                                      const Gap(4),
                                                      Flexible(
                                                        child: Text(
                                                            '→ ${pkg.appealDecisionLabel}',
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: TextStyle(
                                                                fontSize: 10.5,
                                                                color: context
                                                                    .colors
                                                                    .accentLightBlue,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800)),
                                                      ),
                                                    ]),
                                              ),
                                            )
                                          : Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: isExpired ? context.colors.dangerRed.withOpacity(0.1) : context.colors.successGreen.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: isExpired ? context.colors.dangerRed.withOpacity(0.3) : context.colors.successGreen.withOpacity(0.3)),
                                          ),
                                          child: Text(
                                            isExpired ? 'Appeal Expired' : 'Appealing',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isExpired ? context.colors.dangerRed : context.colors.successGreen,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                )),
                                DataCell(Center(
                                  child: IconButton(
                                    icon: Icon(Icons.info_outline_rounded,
                                        color: context.colors.accentLightBlue,
                                        size: 18),
                                    tooltip: 'View details',
                                    onPressed: pkg.packageDetails == null
                                        ? null
                                        : () => showDialog(
                                              context: context,
                                              builder: (_) =>
                                                  PackageDetailsDialog(
                                                package: pkg.packageDetails!,
                                                storageRate: storageRate,
                                                highlightEntry: row.entry,
                                                useLegacySummary: true,
                                                appealDecisionLabel:
                                                    pkg.hasAppealDecision
                                                        ? pkg.appealDecisionLabel
                                                        : null,
                                                // Final disposition once the
                                                // window has passed OR an appeal
                                                // decision has been received.
                                                allowFinalDisposition:
                                                    pkg.isActionable,
                                                // Sale / Destroy → disposal
                                                // request to Central Disposal.
                                                onSaleOrDestroyRequest:
                                                    (disposition) =>
                                                        _requestSingleDisposal(
                                                            pkg, disposition),
                                              ),
                                            ),
                                  ),
                                )),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 100.ms).fadeIn();
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
