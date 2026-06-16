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
import '../../widgets/status_chip.dart';
import '../../widgets/package_details_dialog.dart';
import '../../widgets/date_range_picker_dialog.dart' as custom;
import '../../widgets/year_filter.dart';
import '../forfeited_packages/disposal_request_dialog.dart';
import 'package:data_table_2/data_table_2.dart';

final otherPackageSearchProvider = StateProvider<String>((ref) => '');
final otherPackageDateRangeProvider =
    StateProvider<DateTimeRange?>((ref) => null);

/// Genuine system statuses (set by the SR form dropdown or by later disposition
/// actions). An item whose status is NONE of these — and isn't empty — is a
/// legacy free-text "Other" disposition. Current registrations use the explicit
/// "Other: <text>" marker instead (see [_statusIsOther]). Kept in sync with
/// ForfeitedPackageService._knownStatuses.
const Set<String> _knownStatuses = {
  'detain', 'detained', 'held',
  'forfeit', 'forfiet', 'forfeited', 'confiscated',
  'abandoned',
  'released', 'returned', 'cleared',
  're-export', 're-exported', 'reexport',
  'destroy', 'destroyed',
  'sold', 'sale',
  'inspecting', 'pending', '',
};

/// True if a status string is the explicit "Other" marker the SR form now
/// writes ("Other" or "Other: <text>").
bool _isOtherMarker(String? s) {
  final v = (s ?? '').trim().toLowerCase();
  return v == 'other' || v.startsWith('other:');
}

/// True if a status is a legacy free-text "Other" disposition — non-empty and
/// not one of the known system statuses (so it must be a custom label typed in
/// the SR form's "Other Status" field before the marker scheme existed).
bool _isLegacyOtherStatus(String? s) {
  final v = (s ?? '').trim().toLowerCase();
  if (v.isEmpty) return false;
  return !_knownStatuses.contains(v);
}

/// True if an item's status is an "Other" disposition. Recognises the explicit
/// "Other"/"Other: <text>" marker (current) and, for backward compatibility,
/// legacy free-text statuses.
bool _statusIsOther(String? s) =>
    _isOtherMarker(s) || _isLegacyOtherStatus(s);

/// The custom disposition label for an "Other" item — strips the "Other:"
/// marker prefix when present, otherwise returns the raw status (legacy) or
/// 'Other'.
String _otherLabel(String? s) {
  final raw = (s ?? '').trim();
  if (raw.toLowerCase().startsWith('other:')) {
    final t = raw.substring(6).trim();
    return t.isEmpty ? 'Other' : t;
  }
  if (raw.isEmpty || raw.toLowerCase() == 'other') return 'Other';
  return raw;
}

/// True if the item has moved on to a final disposition
/// (Released/Sold/Destroyed/Re-exported/Other) — it should no longer appear in
/// the Other table.
bool _itemHasFinalDisposition(PackageModel p, String itemId) {
  return p.warehouseEntries.any((e) =>
      e.packageItemId == itemId &&
      (e.returnNotes ?? '').trim().toUpperCase().startsWith('[FINAL:'));
}

/// True if a package has any "Other" item that should be managed here: the
/// explicit "Other" marker always qualifies; a legacy free-text status only
/// qualifies when the item is actually held in a warehouse (so a stray
/// non-warehoused status can't masquerade as an Other package). Finalised items
/// are excluded.
bool _itemIsManageableOther(PackageModel p, PackageItem item) {
  if (_itemHasFinalDisposition(p, item.id)) return false;
  if (_isOtherMarker(item.status)) return true;
  if (_isLegacyOtherStatus(item.status)) {
    return p.warehouseEntries
        .any((e) => e.packageItemId == item.id && !e.isReturned);
  }
  return false;
}

bool _packageHasOther(PackageModel p) =>
    p.items.any((item) => _itemIsManageableOther(p, item));

/// Admin-only management view for packages registered with an "Other" item
/// status. Mirrors the Abandoned page: there is NO appeal period and no Appeal
/// Directorate involvement. The admin can Release / Re-export / record a custom
/// "Other" outcome directly, or send the package to Central Disposal for Sale /
/// Destruction.
class OtherPackagesScreen extends ConsumerStatefulWidget {
  const OtherPackagesScreen({super.key});
  @override
  ConsumerState<OtherPackagesScreen> createState() =>
      _OtherPackagesScreenState();
}

class _OtherPackagesScreenState extends ConsumerState<OtherPackagesScreen> {
  final _tableSearchCtrl = TextEditingController();
  String? _yearFilter;

  /// Submits a single-package disposal request (Sale / Destruction) for an
  /// "Other" package — used by the details popup's Sale/Destroy buttons.
  /// createDisposalRequest creates the synthetic source='other' forfeited_packages
  /// row automatically.
  Future<void> _requestSingleDisposal(
      PackageModel pkg, String disposition) async {
    try {
      await ref.read(forfeitedPackageServiceProvider).createDisposalRequest(
            requestDate: DateTime.now(),
            dispositions: {pkg.id: disposition},
          );
      ref.read(disposalRequestsRefreshProvider.notifier).trigger();
      ref.invalidate(livePackagesProvider);
      ref.invalidate(requestableForfeitedPackagesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: context.colors.successGreen,
          content: Text(
              'Disposal request sent for ${pkg.srNumber} (${disposition == 'sale' ? 'Sale' : 'Destruction'}).'),
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

  /// One row per "Other"-status item still held in the warehouse.
  List<_OtherRow> _buildRows(List<PackageModel> packages) {
    final rows = <_OtherRow>[];
    for (final package in packages) {
      for (final item in package.items) {
        if (!_itemIsManageableOther(package, item)) continue;

        final itemEntries = package.warehouseEntries
            .where((e) => e.packageItemId == item.id)
            .toList();
        final ctx = itemEntries.isNotEmpty ? itemEntries.first : null;

        // The custom "Other Status" label is the most descriptive disposition.
        final disposition = _otherLabel(item.status);

        rows.add(_OtherRow(
          package: package,
          item: item,
          entry: ctx,
          qty: ctx?.itemCount ?? item.quantity,
          date: ctx?.admittedAt,
          disposition: disposition,
          reason: ctx?.holdReason ??
              (item.reasons?.isNotEmpty == true ? item.reasons! : '—'),
          officer: ctx?.admittedByName ?? '—',
        ));
      }
    }
    rows.sort((a, b) {
      final aDate = a.date ?? DateTime(2000);
      final bDate = b.date ?? DateTime(2000);
      return bDate.compareTo(aDate);
    });
    return rows;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tableSearchCtrl.text = ref.read(otherPackageSearchProvider);
    });
  }

  @override
  void dispose() {
    _tableSearchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final packages = ref.watch(livePackagesProvider);
    final storageRateHistory = ref.watch(storageRateProvider).valueOrNull ??
        {DateTime(2020, 1, 1): 50.0};
    final search = ref.watch(otherPackageSearchProvider);
    final dateRange = ref.watch(otherPackageDateRangeProvider);

    return AppShell(
      currentRoute: '/other-packages',
      child: Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──
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
                        Text('Other Packages',
                            style: Theme.of(context).textTheme.headlineLarge),
                        Text(
                          'Manage packages with an "Other" status — release, re-export or send for disposal',
                          style:
                              TextStyle(color: context.colors.textSecondary)),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Consumer(
                          builder: (context, ref, child) {
                            final pkgs = ref.watch(livePackagesProvider);
                            return pkgs.when(
                              data: (list) => _OtherStatChip(
                                  label: 'Other',
                                  value: '${_buildRows(list).length}',
                                  color: context.colors.accentLightBlue),
                              loading: () => const SizedBox(),
                              error: (_, __) => const SizedBox(),
                            );
                          },
                        ),
                        const Gap(8),
                        // Requestable = "Other" packages not yet sent in a
                        // disposal request (surfaced by the shared provider).
                        Consumer(
                          builder: (context, ref, child) {
                            final req =
                                ref.watch(requestableForfeitedPackagesProvider);
                            final n = req.maybeWhen(
                                data: (list) =>
                                    list.where((p) => p.isOtherSource).length,
                                orElse: () => 0);
                            return _OtherStatChip(
                                label: 'Requestable',
                                value: '$n',
                                color: context.colors.primaryGold);
                          },
                        ),
                        const Gap(16),
                        Consumer(
                          builder: (context, ref, child) {
                            final req =
                                ref.watch(requestableForfeitedPackagesProvider);
                            final n = req.maybeWhen(
                                data: (list) =>
                                    list.where((p) => p.isOtherSource).length,
                                orElse: () => 0);
                            return ElevatedButton.icon(
                              icon: const Icon(Icons.local_shipping_rounded,
                                  size: 16),
                              label: const Text('Send Disposal Request'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: n > 0
                                    ? context.colors.primaryGold
                                    : context.colors.textMuted
                                        .withOpacity(0.2),
                                foregroundColor: n > 0
                                    ? Colors.white
                                    : context.colors.textMuted,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                elevation: n > 0 ? 2 : 0,
                              ),
                              onPressed: n > 0
                                  ? () => showDialog(
                                        context: context,
                                        builder: (ctx) => DisposalRequestDialog(
                                          onSubmitted: () {
                                            ref.invalidate(
                                                requestableForfeitedPackagesProvider);
                                            ref.invalidate(livePackagesProvider);
                                          },
                                        ),
                                      )
                                  : null,
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ).animate().fadeIn(),
              const Gap(20),

              // ── TEMP DIAGNOSTIC (remove after debugging) ──
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.colors.warningAmber.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: context.colors.warningAmber.withOpacity(0.4)),
                ),
                child: ref.watch(requestableForfeitedPackagesProvider).when(
                      loading: () => const Text('DEBUG: loading requestable…'),
                      error: (e, _) => Text('DEBUG requestable ERROR: $e',
                          style: TextStyle(
                              fontSize: 11, color: context.colors.dangerRed)),
                      data: (req) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              'DEBUG — requestable=${req.length} '
                              '(abandoned=${req.where((p) => p.isAbandonedSource).length}, '
                              'other=${req.where((p) => p.isOtherSource).length}, '
                              'forfeit=${req.where((p) => p.source == 'forfeit').length})',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: context.colors.warningAmber)),
                          const Gap(4),
                          for (final p in req)
                            Text('  • ${p.srNumber} · source=${p.source}',
                                style: const TextStyle(
                                    fontSize: 11, fontFamily: 'monospace')),
                        ],
                      ),
                    ),
              ),

              // ── Search & filters ──
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
                    Row(children: [
                      Expanded(
                        child: Autocomplete<PackageModel>(
                          displayStringForOption: (p) => p.srNumber,
                          initialValue:
                              TextEditingValue(text: _tableSearchCtrl.text),
                          optionsBuilder: (textEditingValue) {
                            final query =
                                textEditingValue.text.trim().toLowerCase();
                            if (query.isEmpty) return const [];
                            final packages =
                                ref.read(livePackagesProvider).valueOrNull ??
                                    [];
                            return packages.where((p) =>
                                _packageHasOther(p) &&
                                (p.srNumber.toLowerCase().contains(query) ||
                                    p.consigneeName
                                        .toLowerCase()
                                        .contains(query)));
                          },
                          onSelected: (package) {
                            setState(() {
                              _tableSearchCtrl.text = package.srNumber;
                              ref
                                  .read(otherPackageSearchProvider.notifier)
                                  .state = package.srNumber;
                            });
                          },
                          optionsViewBuilder: (context, onSelected, options) {
                            return Align(
                              alignment: Alignment.topLeft,
                              child: Material(
                                color: Colors.transparent,
                                child: Container(
                                  width: 500,
                                  margin: const EdgeInsets.only(top: 8),
                                  decoration: BoxDecoration(
                                    color: context.colors.surfaceDark,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: context.colors.borderColor),
                                    boxShadow: [
                                      BoxShadow(
                                          color: Colors.black.withOpacity(0.15),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4))
                                    ],
                                  ),
                                  child: ListView.builder(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    shrinkWrap: true,
                                    itemCount: options.length,
                                    itemBuilder: (context, index) {
                                      final option = options.elementAt(index);
                                      return InkWell(
                                        onTap: () => onSelected(option),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 10),
                                          child: Row(
                                            children: [
                                              Text(option.srNumber,
                                                  style: TextStyle(
                                                      color: context.colors
                                                          .accentLightBlue,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                              const Gap(12),
                                              Expanded(
                                                  child: Text(
                                                      option.consigneeName,
                                                      style: TextStyle(
                                                          color: context.colors
                                                              .textSecondary,
                                                          fontSize: 13),
                                                      overflow: TextOverflow
                                                          .ellipsis)),
                                              StatusChip(status: option.status),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                          fieldViewBuilder: (context, controller, focusNode,
                              onFieldSubmitted) {
                            if (controller.text != _tableSearchCtrl.text &&
                                _tableSearchCtrl.text.isNotEmpty &&
                                controller.text.isEmpty) {
                              controller.text = _tableSearchCtrl.text;
                            }
                            return TextField(
                              controller: controller,
                              focusNode: focusNode,
                              style:
                                  TextStyle(color: context.colors.textPrimary),
                              decoration: InputDecoration(
                                hintText: 'Search SR #, consignee or item...',
                                prefixIcon: Icon(Icons.search_rounded,
                                    color: context.colors.textMuted),
                                suffixIcon: controller.text.isNotEmpty
                                    ? IconButton(
                                        icon: Icon(Icons.clear_rounded,
                                            color: context.colors.textMuted),
                                        onPressed: () {
                                          controller.clear();
                                          _tableSearchCtrl.clear();
                                          ref
                                              .read(otherPackageSearchProvider
                                                  .notifier)
                                              .state = '';
                                        },
                                      )
                                    : null,
                                isDense: true,
                              ),
                              onChanged: (v) {
                                _tableSearchCtrl.text = v;
                                ref
                                    .read(otherPackageSearchProvider.notifier)
                                    .state = v;
                              },
                            );
                          },
                        ),
                      ),
                    ]),
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
                                      initialRange: dateRange),
                            );
                            if (picked is DateTimeRange) {
                              ref
                                  .read(otherPackageDateRangeProvider.notifier)
                                  .state = picked;
                            } else if (picked == false) {
                              ref
                                  .read(otherPackageDateRangeProvider.notifier)
                                  .state = null;
                            }
                          },
                          icon: Icon(Icons.date_range_rounded,
                              size: 16,
                              color: dateRange != null
                                  ? context.colors.primaryGold
                                  : context.colors.textSecondary),
                          label: Text(
                            dateRange != null
                                ? '${DateFormat('MMM d').format(dateRange.start)} - ${DateFormat('MMM d').format(dateRange.end)}'
                                : 'Date Range',
                            style: TextStyle(
                                color: dateRange != null
                                    ? context.colors.primaryGold
                                    : context.colors.textSecondary,
                                fontSize: 12,
                                fontWeight: dateRange != null
                                    ? FontWeight.bold
                                    : FontWeight.normal),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: dateRange != null
                                    ? context.colors.primaryGold
                                    : context.colors.borderColor),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        if (dateRange != null)
                          IconButton(
                            icon: Icon(Icons.clear_rounded,
                                size: 16, color: context.colors.dangerRed),
                            onPressed: () => ref
                                .read(otherPackageDateRangeProvider.notifier)
                                .state = null,
                            tooltip: 'Clear Date Filter',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        const SizedBox(width: 8),
                        YearFilterButton(
                          value: _yearFilter,
                          years: srYears(_buildRows(packages.valueOrNull ??
                                  const <PackageModel>[])
                              .map((r) => r.package.srNumber)),
                          onChanged: (v) => setState(() => _yearFilter = v),
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
                      if (search.isNotEmpty) {
                        final s = search.toLowerCase();
                        final itemName = row.itemName.toLowerCase();
                        if (!row.package.srNumber.toLowerCase().contains(s) &&
                            !row.package.consigneeName
                                .toLowerCase()
                                .contains(s) &&
                            !itemName.contains(s)) {
                          return false;
                        }
                      }
                      if (dateRange != null && row.date != null) {
                        final date = row.date!;
                        final startOfDay = DateTime(dateRange.start.year,
                            dateRange.start.month, dateRange.start.day);
                        final endOfDay = DateTime(dateRange.end.year,
                            dateRange.end.month, dateRange.end.day, 23, 59, 59);
                        if (date.isBefore(startOfDay) || date.isAfter(endOfDay))
                          return false;
                      }
                      if (!srYearMatches(row.package.srNumber, _yearFilter))
                        return false;
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
                          empty: const EmptyTableState(
                              message: 'No "Other" packages found'),
                          isVerticalScrollBarVisible: true,
                          isHorizontalScrollBarVisible: false,
                          columns: const [
                            DataColumn2(
                                label: Text('SR Number'), size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Item Name'), size: ColumnSize.M),
                            DataColumn2(
                                label: Text('HS Code'),
                                size: ColumnSize.S,
                                fixedWidth: 110),
                            DataColumn2(
                                label: Text('Qty'),
                                size: ColumnSize.S,
                                fixedWidth: 70),
                            DataColumn2(
                                label: Text('Disposition'), size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Date'), size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Consignee'), size: ColumnSize.M),
                            DataColumn2(
                                label: Center(child: Text('Details')),
                                size: ColumnSize.S,
                                fixedWidth: 55),
                          ],
                          rows: rows
                              .map((row) => DataRow(cells: [
                                    DataCell(Text(row.package.srNumber,
                                        style: TextStyle(
                                            color:
                                                context.colors.accentLightBlue,
                                            fontWeight: FontWeight.w600))),
                                    DataCell(Text(row.itemName,
                                        overflow: TextOverflow.ellipsis)),
                                    DataCell(Text(
                                        (row.item.hsCode != null &&
                                                row.item.hsCode!.isNotEmpty)
                                            ? row.item.hsCode!
                                            : '—',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12))),
                                    DataCell(Center(child: Text('${row.qty}'))),
                                    DataCell(_OtherDispositionChip(
                                        label: row.disposition)),
                                    DataCell(Text(row.date != null
                                        ? DateFormat('yyyy-MM-dd')
                                            .format(row.date!)
                                        : '—')),
                                    DataCell(Text(
                                        row.package.consigneeName.isNotEmpty
                                            ? row.package.consigneeName
                                            : '—',
                                        overflow: TextOverflow.ellipsis)),
                                    DataCell(Center(
                                        child: IconButton(
                                      icon: Icon(Icons.info_outline_rounded,
                                          color: context.colors.accentLightBlue,
                                          size: 18),
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (_) => PackageDetailsDialog(
                                            package: row.package,
                                            storageRate: storageRateHistory,
                                            highlightEntry: row.entry,
                                            useLegacySummary: true,
                                            // "Other" goods have no appeal —
                                            // disposition allowed immediately.
                                            onSaleOrDestroyRequest:
                                                (disposition) =>
                                                    _requestSingleDisposal(
                                                        row.package,
                                                        disposition),
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

class _OtherStatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _OtherStatChip(
      {required this.label, required this.value, required this.color});
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
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  height: 1.1)),
          Text(label,
              style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

/// Shows the custom "Other" disposition label the officer typed on the form.
class _OtherDispositionChip extends StatelessWidget {
  final String label;
  const _OtherDispositionChip({required this.label});
  @override
  Widget build(BuildContext context) {
    final color = context.colors.warningAmber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _OtherRow {
  final PackageModel package;
  final PackageItem item;
  final WarehouseEntryModel? entry; // null only if no warehouse entry exists
  final int qty;
  final DateTime? date;
  final String disposition; // custom "Other Status" label, or 'Other'
  final String reason;
  final String officer;

  const _OtherRow({
    required this.package,
    required this.item,
    required this.entry,
    required this.qty,
    required this.date,
    required this.disposition,
    required this.reason,
    required this.officer,
  });

  String get itemName => item.itemName;
}
