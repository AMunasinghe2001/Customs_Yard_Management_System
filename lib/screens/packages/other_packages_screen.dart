import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/providers.dart';
import '../../core/post_status_activities.dart';
import '../../models/models.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/error_view.dart';
import '../../widgets/empty_table_state.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/package_details_dialog.dart';
import '../../widgets/appeal_state_chip.dart';
import '../../widgets/styled_dropdown.dart';
import '../../widgets/year_filter.dart';
import '../../widgets/table_pager.dart';
import '../forfeited_packages/disposal_request_dialog.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../widgets/disposal_page_header.dart';
import '../../widgets/tooltip_text.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/date_filter_button.dart';

final otherPackageSearchProvider = StateProvider<String>((ref) => '');
final otherPackageDateRangeProvider =
    StateProvider<DateTimeRange?>((ref) => null);

/// Post Status Activity filter — 'all', or one of [kDisposalActivities].
final otherPackageActivityProvider = StateProvider<String>((ref) => 'all');

/// Genuine system statuses (set by the SR form dropdown or by later disposition
/// actions). An item whose status is NONE of these — and isn't empty — is a
/// legacy free-text "Other" disposition. Current registrations use the explicit
/// "Other: <text>" marker instead (see [_statusIsOther]). Kept in sync with
/// ForfeitedPackageService._knownStatuses.
const Set<String> _knownStatuses = {
  'detain',
  'detained',
  'held',
  'forfeit',
  'forfiet',
  'forfeited',
  'confiscated',
  'abandoned',
  'released',
  'returned',
  'cleared',
  're-export',
  're-exported',
  'reexport',
  'destroy',
  'destroyed',
  'sold',
  'sale',
  'inspecting',
  'pending',
  '',
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
// ⚠️ `_statusIsOther` moved into the view: the explicit 'Other' / 'Other: …'
// marker always qualifies, and a LEGACY free-text status only while the item
// is actually held in a warehouse — so a typo in the status field cannot
// masquerade as an Other package.

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
// ⚠️ `_isFinalOtherEntry` moved into the view as the OTHER (3) source. Those
// rows carry `completed`, because a [FINAL:OTHER] outcome is a finished
// record shown read-only — the one exception to "nothing finalised may be
// listed as actionable".

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
  final m =
      RegExp(r'^\[OTHER:\s*([^\]]*)\]', caseSensitive: false).firstMatch(notes);
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

  /// ⚠️ New: this page had no pager at all. Reset on every filter change, or
  /// a narrowed result strands the reader on a page that no longer exists.
  int _page = 0;

  /// Submits a single-package disposal request (Sale / Destruction) for an
  /// "Other" package — used by the details popup's Sale/Destroy buttons.
  /// createDisposalRequest creates the synthetic source='other' forfeited_packages
  /// row automatically.
  Future<void> _requestSingleDisposal(PackageModel pkg, String disposition,
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
        showErrorSnack(context, e);
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

  /// Whether these goods can be sent for disposal yet.
  ///
  // ⚠️ `_isRowActionable` moved into `getHeldGoodsCounts`, which applies the
  // rule once for the header: a HOLD always blocks, an Appeal Directorate
  // decision releases early, and otherwise the 30-day window decides.
  //
  // It used to be computed from data already on screen so the Send Disposal
  // Request button lit up as soon as the table did. That reasoning no longer
  // holds now the table is ONE PAGE: counting the visible rows would report
  // twenty, whatever the yard is holding.

  /// The view's rows, as this page's widgets already expect them.
  ///
  /// ⚠️ Replaces `_buildRows`. All three sources live in the view now, and the
  /// row key says which one a row came from:
  ///   OE: an [OTHER] disposition EVENT (repeatable per item)
  ///   OS: a form-level "Other" status with no event of its own
  ///   OF: the COMPLETED [FINAL:OTHER] outcome — read-only, like Released and
  ///       Sold on their own pages, which is what `completed` carries
  List<_OtherRow> _rowsFrom(HeldGoodsPage result) {
    final out = <_OtherRow>[];
    for (final k in result.keys) {
      final pkg = result.packages[k.packageId];
      if (pkg == null) continue;
      final item = pkg.items.where((i) => i.id == k.itemId).firstOrNull;
      if (item == null) continue;

      final itemEntries =
          pkg.warehouseEntries.where((e) => e.packageItemId == item.id).toList();
      final isEvent = k.rowKey.startsWith('OE:');
      final isFinal = k.rowKey.startsWith('OF:');
      final entry = (isEvent || isFinal)
          ? itemEntries
              .where((e) => k.rowKey.endsWith(e.id))
              .firstOrNull
          : (itemEntries.isNotEmpty ? itemEntries.first : null);

      out.add(_OtherRow(
        package: pkg,
        item: item,
        entry: entry,
        qty: entry?.itemCount ?? item.quantity,
        date: (isEvent || isFinal)
            ? (entry?.returnedAt ?? entry?.admittedAt)
            : entry?.admittedAt,
        // The most descriptive label available for each kind of row.
        disposition: isFinal
            ? _finalOtherLabel(entry!)
            : (isEvent ? _otherEntryLabel(entry!) : _otherLabel(item.status)),
        reason: entry?.holdReason ??
            (item.reasons?.isNotEmpty == true ? item.reasons! : '—'),
        officer: (isEvent || isFinal)
            ? (entry?.returnedByName ?? entry?.returnedByBadge ?? '—')
            : (entry?.admittedByName ?? '—'),
        completed: isFinal,
      ));
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    // ⚠️ SYNCHRONOUS, not in a post-frame callback.
    //
    // The search box is an Autocomplete, which builds its own controller. The
    // fieldViewBuilder copies _tableSearchCtrl into it, but a post-frame
    // callback runs AFTER that first build and calls no setState -- so leaving
    // the page and coming back left the table filtered by the remembered query
    // while the box showed nothing. The filter was on and invisible.
    //
    // Assigning here means the first build already has the text.
    _tableSearchCtrl.text = ref.read(otherPackageSearchProvider);
  }

  @override
  void dispose() {
    _tableSearchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ This page had NO pager: it fetched every package in the yard and
    // handed the whole list to DataTable2. All THREE row sources now live in
    // the `held_goods_rows` view (postgres/25, kind OTHER) -- the [OTHER]
    // disposition event, the form-level status, and the completed
    // [FINAL:OTHER] outcome, which is the one read-only kind.
    final query = HeldGoodsQuery(
      kind: 'OTHER',
      page: _page,
      search: ref.watch(otherPackageSearchProvider),
      dateStart: ref.watch(otherPackageDateRangeProvider)?.start,
      dateEnd: ref.watch(otherPackageDateRangeProvider)?.end,
      year: _yearFilter,
      activity: ref.watch(otherPackageActivityProvider),
    );
    final packages = ref.watch(heldGoodsPageProvider(query));
    final storageRateHistory = ref.watch(storageRateProvider).valueOrNull ??
        {DateTime(2020, 1, 1): 50.0};
    // Appeal rulings, keyed by item id. A decision releases the goods early;
    // a hold keeps them frozen past the deadline.
    final appealOutcomes =
        ref.watch(allItemAppealOutcomesProvider).valueOrNull ??
            const <String, ItemAppealOutcome>{};
    final dateRange = ref.watch(otherPackageDateRangeProvider);
    final activity = ref.watch(otherPackageActivityProvider);
    // ⚠️ Items already sent to Central Disposal are excluded by the QUERY
    // now (`sent = false` on the view), not by a set held here.

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
              Consumer(
                builder: (context, ref, child) {
                  // ⚠️ Counted in SQL, by their own query. Derived from one
                  // page they would contradict the header they sit in;
                  // derived from the whole list they would undo the paging.
                  final counts =
                      ref.watch(heldGoodsCountsProvider('OTHER')).valueOrNull ??
                          (total: 0, inAppeal: 0, actionable: 0);
                  final total = counts.total;
                  final actionable = counts.actionable;
                  return DisposalPageHeader(
                    title: 'Other Goods',
                    subtitle: 'Manage packages with an "Other" status — '
                        'release, re-export or send for disposal',
                    trailing: [
                      _OtherStatChip(
                          label: 'Total',
                          value: '$total',
                          color: context.colors.accentLightBlue),
                      _OtherStatChip(
                          label: 'In Appeal',
                          value:
                              '${total - actionable < 0 ? 0 : total - actionable}',
                          color: context.colors.warningAmber),
                      _OtherStatChip(
                          label: 'Actionable',
                          value: '$actionable',
                          color: context.colors.successGreen),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.local_shipping_rounded, size: 16),
                        label: const Text('Send Disposal Request'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: actionable > 0
                              ? context.colors.primaryGold
                              : context.colors.textMuted.withOpacity(0.2),
                          foregroundColor: actionable > 0
                              ? Colors.white
                              : context.colors.textMuted,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          elevation: actionable > 0 ? 2 : 0,
                        ),
                        onPressed: actionable > 0
                            ? () => showAppDialog(
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
                      ),
                    ],
                  );
                },
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
                        DateFilterButton(
                          dateRange: dateRange,
                          year: _yearFilter,
                          years: srYears(ref
                                  .watch(heldGoodsYearsProvider('OTHER'))
                                  .valueOrNull ??
                              const <String>[]),
                          onChanged: (range, year) {
                            ref
                                .read(otherPackageDateRangeProvider.notifier)
                                .state = range;
                            setState(() {
                              _yearFilter = year;
                              _page = 0;
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        
                        StyledDropdownButton<String>(
                          value: activity == 'all' ? null : activity,
                          allLabel: 'Post Status Activity',
                          icon: Icons.label_outline_rounded,
                          menuWidth: 320,
                          // "Other" goods carry a DISPOSAL activity, like
                          // Forfeit and Abandoned do.
                          options: kDisposalActivities
                              .map((a) => StyledDropdownOption(a, a))
                              .toList(),
                          onChanged: (v) => ref
                              .read(otherPackageActivityProvider.notifier)
                              .state = v ?? 'all',
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
                      onRetry: () =>
                          ref.refresh(heldGoodsPageProvider(query))),
                  data: (result) {
                    // Filtered, sorted and paged by the database.
                    final rows = _rowsFrom(result);
                    final maxPage = result.total == 0
                        ? 0
                        : (result.total - 1) ~/ kDispositionPageSize;
                    if (_page > maxPage) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _page = maxPage);
                      });
                    }

                    return Column(children: [
                      Expanded(
                        child: Container(
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
                                label: Text('Goods Name'), size: ColumnSize.M),
                            DataColumn2(
                                label: Text('HS Code'),
                                size: ColumnSize.S,
                                fixedWidth: 110),
                            DataColumn2(
                                label: Text('Qty'),
                                size: ColumnSize.S,
                                fixedWidth: 70),
                            DataColumn2(
                                label: Center(child: Text('Disposition')),
                                size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Date'), size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Consignee'), size: ColumnSize.M),
                            DataColumn2(
                                label: Center(child: Text('Appeal')),
                                size: ColumnSize.S,
                                fixedWidth: 130),
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
                                    // A [FINAL:OTHER] row is a COMPLETED
                                    // record — the outcome has already been
                                    // carried out, so there is nothing left to
                                    // appeal and no action to enable. Saying
                                    // "Enabled" there invited a click that
                                    // could do nothing.
                                    DataCell(Center(
                                        child: row.completed
                                            ? _CompletedChip(
                                                label: row.disposition)
                                            : AppealStateChip(
                                                entryDate:
                                                    row.package.entryDate ??
                                                        row.package.createdAt,
                                                outcome: appealOutcomes[
                                                    row.item.id]))),
                                    DataCell(Center(
                                        child: IconButton(
                                      icon: Icon(Icons.info_outline_rounded,
                                          color: context.colors.accentLightBlue,
                                          size: 18),
                                      onPressed: () {
                                        showAppDialog(
                                          context: context,
                                          builder: (_) => PackageDetailsDialog(
                                            package: row.package,
                                            storageRate: storageRateHistory,
                                            highlightEntry: row.entry,
                                            highlightItemId: row.item.id,
                                            useLegacySummary: true,
                                            // When the Appeal Directorate has
                                            // ruled, banner the ruling and
                                            // enable ONLY that action — the
                                            // yard carries out what was
                                            // decided, it does not choose
                                            // afresh.
                                            appealDecisionLabel:
                                                appealOutcomes[row.item.id]
                                                    ?.label,
                                            appealDecisionCode: (appealOutcomes[
                                                            row.item.id]
                                                        ?.isDecided ??
                                                    false)
                                                ? appealOutcomes[row.item.id]!
                                                    .decision
                                                : null,
                                            // Completed [FINAL:OTHER] outcomes
                                            // are read-only (no actions).
                                            forceFinalDisposition:
                                                !row.completed,
                                            allowFinalDisposition:
                                                !row.completed,
                                            onSaleOrDestroyRequest:
                                                row.completed
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
                            .slideY(
                                begin: 0.1, duration: 400.ms, delay: 300.ms)
                            .fadeIn(),
                      ),
                      TablePager(
                        // The database's count for this filter.
                        total: result.total,
                        page: _page.clamp(0, maxPage),
                        pageSize: kDispositionPageSize,
                        onPageChanged: (p) => setState(() => _page = p),
                      ),
                    ]);
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

/// A finished "Other" outcome. Read-only: the disposition was already
/// recorded, so no further action is offered on this row.
class _CompletedChip extends StatelessWidget {
  final String label;
  const _CompletedChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final colour = context.colors.textMuted;
    return Tooltip(
      message: 'Completed · $label',
      waitDuration: const Duration(milliseconds: 300),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: colour.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colour.withOpacity(0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.task_alt_rounded, size: 13, color: colour),
          const Gap(5),
          Flexible(
            child: Text('Completed',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: colour, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ]),
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
