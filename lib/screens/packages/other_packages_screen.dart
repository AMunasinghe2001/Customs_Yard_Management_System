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
import '../../widgets/tooltip_text.dart';

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

/// True if a warehouse entry is an "Other" disposition event — a custom
/// disposition recorded from the warehouse Actions dialog. A PARTIAL "Other"
/// disposition tags the entry "[OTHER: <text>]" but leaves item.status
/// unchanged (e.g. 'detain'), so these events must be surfaced here directly.
/// Final-disposition entries ("[FINAL:OTHER]") are NOT included — those belong
/// to the finished-category views.
bool _isOtherEntry(WarehouseEntryModel e) {
  if (!e.isReturned) return false;
  final notes = (e.returnNotes ?? '').trim().toUpperCase();
  return notes.startsWith('[OTHER:') ||
      notes.startsWith('[OTHER]') ||
      notes.startsWith('[OTHER ');
}

/// True if a warehouse entry is a FINAL "Other" disposition ("[FINAL:OTHER]"),
/// i.e. the terminal custom outcome recorded from the Final Disposition dialog.
/// These are completed records (read-only) shown in this page's list.
bool _isFinalOtherEntry(WarehouseEntryModel e) {
  if (!e.isReturned) return false;
  final notes = (e.returnNotes ?? '').trim().toUpperCase();
  return notes.startsWith('[FINAL:OTHER]');
}

/// The custom outcome label from a "[FINAL:OTHER] — <text>" entry (the text
/// after the marker, falls back to 'Other').
String _finalOtherLabel(WarehouseEntryModel e) {
  final notes = (e.returnNotes ?? '').trim();
  final m = RegExp(r'^\[FINAL:OTHER\]\s*—\s*(.+)$', caseSensitive: false)
      .firstMatch(notes);
  if (m != null) {
    final t = m.group(1)!.trim();
    if (t.isNotEmpty) return t;
  }
  return 'Other';
}

/// The custom label from an "[OTHER: <text>] — notes" disposition entry — the
/// text inside the brackets after the "OTHER:" marker (falls back to 'Other').
String _otherEntryLabel(WarehouseEntryModel e) {
  final notes = (e.returnNotes ?? '').trim();
  final m = RegExp(r'^\[OTHER:\s*([^\]]*)\]', caseSensitive: false)
      .firstMatch(notes);
  if (m != null) {
    final t = m.group(1)!.trim();
    if (t.isNotEmpty) return t;
  }
  return 'Other';
}

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

bool _packageHasOther(PackageModel p) {
  for (final item in p.items) {
    if (_itemIsManageableOther(p, item)) return true;
    // A partial "[OTHER]" disposition event also qualifies — its item.status
    // may still read 'detain' (partial dispositions don't change it).
    final entries = p.warehouseEntries.where((e) => e.packageItemId == item.id);
    if (entries.any(_isOtherEntry)) return true;
  }
  return false;
}

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
      PackageModel pkg, String disposition,
      {String? itemId, WarehouseEntryModel? entry}) async {
    try {
      // Include the entry id when this row is a partial "[OTHER]" disposition
      // event so createDisposalRequest stores entry.itemCount as entry_qty —
      // Valuation / Central Disposal then price the partial qty (e.g. 4) rather
      // than the full registered item quantity.
      final key = (itemId != null && entry != null)
          ? '${pkg.id}:$itemId:${entry.id}:other'
          : itemId != null
              ? '${pkg.id}:$itemId:other'
              : '${pkg.id}:other';
      await ref.read(forfeitedPackageServiceProvider).createDisposalRequest(
            requestDate: DateTime.now(),
            // item-level key: "pkgId:itemId:other" ensures each item gets its
            // own forfeited_packages row and is not blocked by sibling items.
            dispositions: {key: disposition},
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

  /// Builds rows for "Other" packages — broken down per package item.
  /// A single SR can appear on multiple lines: once per "Other"-status item
  /// (set on the SR form), and once per partial "[OTHER]" disposition event
  /// recorded from the warehouse Actions dialog (these don't change the item
  /// status, so they must be surfaced from the warehouse entries directly).
  /// [sentKeys] — "pkgId:itemId" keys for items already sent in a disposal
  /// request; those rows are hidden from the table.
  List<_OtherRow> _buildRows(List<PackageModel> packages,
      {Set<String> sentKeys = const {}}) {
    final rows = <_OtherRow>[];
    for (final package in packages) {
      for (final item in package.items) {
        // Skip items already sent in a disposal request.
        if (sentKeys.contains('${package.id}:${item.id}')) continue;

        final itemEntries = package.warehouseEntries
            .where((e) => e.packageItemId == item.id)
            .toList();

        // 1. Partial/full "[OTHER]" disposition events — each is its own row
        //    (repeatable per item). Skipped for finalised items.
        final otherEntries = _itemHasFinalDisposition(package, item.id)
            ? const <WarehouseEntryModel>[]
            : itemEntries.where(_isOtherEntry).toList();
        for (final entry in otherEntries) {
          rows.add(_OtherRow(
            package: package,
            item: item,
            entry: entry,
            qty: entry.itemCount,
            date: entry.returnedAt ?? entry.admittedAt,
            disposition: _otherEntryLabel(entry),
            reason: entry.holdReason,
            officer: entry.returnedByName ?? entry.returnedByBadge ?? '—',
          ));
        }

        // 2. Form-level "Other" status (item.status == 'Other: …') with no
        //    "[OTHER]" disposition event — use the held entry for context.
        if (_itemIsManageableOther(package, item) && otherEntries.isEmpty) {
          final ctx = itemEntries.isNotEmpty ? itemEntries.first : null;
          rows.add(_OtherRow(
            package: package,
            item: item,
            entry: ctx,
            qty: ctx?.itemCount ?? item.quantity,
            date: ctx?.admittedAt,
            // The custom "Other Status" label is the most descriptive label.
            disposition: _otherLabel(item.status),
            reason: ctx?.holdReason ??
                (item.reasons?.isNotEmpty == true ? item.reasons! : '—'),
            officer: ctx?.admittedByName ?? '—',
          ));
        }

        // 3. FINAL "Other" outcomes ([FINAL:OTHER]) — the terminal custom
        //    disposition recorded from the Final Disposition dialog. Shown as
        //    completed, read-only records (like Released/Sold on their pages).
        final finalOtherEntries =
            itemEntries.where(_isFinalOtherEntry).toList();
        for (final entry in finalOtherEntries) {
          rows.add(_OtherRow(
            package: package,
            item: item,
            entry: entry,
            qty: entry.itemCount,
            date: entry.returnedAt ?? entry.admittedAt,
            disposition: _finalOtherLabel(entry),
            reason: entry.holdReason ??
                (item.reasons?.isNotEmpty == true ? item.reasons! : '—'),
            officer: entry.returnedByName ?? entry.returnedByBadge ?? '—',
            completed: true,
          ));
        }
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
    final sentKeys =
        ref.watch(sentAbandonedOtherFpKeysProvider).valueOrNull ?? {};

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
                            final sk = ref
                                    .watch(sentAbandonedOtherFpKeysProvider)
                                    .valueOrNull ??
                                {};
                            return pkgs.when(
                              data: (list) => _OtherStatChip(
                                  label: 'Other',
                                  value:
                                      '${_buildRows(list, sentKeys: sk).length}',
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
                          years: srYears(_buildRows(
                                  packages.valueOrNull ?? const <PackageModel>[],
                                  sentKeys: sentKeys)
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
                    final rows =
                        _buildRows(list, sentKeys: sentKeys).where((row) {
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
                                label: Center(child: Text('Disposition')), size: ColumnSize.M),
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
                                    DataCell(TooltipText(row.package.srNumber,
                                        style: TextStyle(
                                            color:
                                                context.colors.accentLightBlue,
                                            fontWeight: FontWeight.w600))),
                                    DataCell(TooltipText(row.itemName,
                                        overflow: TextOverflow.ellipsis)),
                                    DataCell(TooltipText(
                                        (row.item.hsCode != null &&
                                                row.item.hsCode!.isNotEmpty)
                                            ? row.item.hsCode!
                                            : '—',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12))),
                                    DataCell(Center(child: Text('${row.qty}'))),
                                    DataCell(_OtherDispositionChip(
                                        label: row.disposition)),
                                    DataCell(TooltipText(row.date != null
                                        ? DateFormat('yyyy-MM-dd')
                                            .format(row.date!)
                                        : '—')),
                                    DataCell(TooltipText(
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
                                            highlightItemId: row.item.id,
                                            useLegacySummary: true,
                                            // Manageable "Other" goods have no
                                            // appeal — disposition allowed
                                            // immediately. Completed [FINAL:OTHER]
                                            // outcomes are read-only (no actions).
                                            forceFinalDisposition: !row.completed,
                                            allowFinalDisposition:
                                                !row.completed,
                                            onSaleOrDestroyRequest: row.completed
                                                ? null
                                                : (disposition) =>
                                                    _requestSingleDisposal(
                                                        row.package,
                                                        disposition,
                                                        itemId: row.item.id,
                                                        entry: row.entry),
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
  /// True for a FINAL "Other" outcome ([FINAL:OTHER]) — a completed record that
  /// is read-only (no further disposal actions).
  final bool completed;

  const _OtherRow({
    required this.package,
    required this.item,
    required this.entry,
    required this.qty,
    required this.date,
    required this.disposition,
    required this.reason,
    required this.officer,
    this.completed = false,
  });

  String get itemName => item.itemName;
}
