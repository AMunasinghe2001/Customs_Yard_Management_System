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
import '../../widgets/year_filter.dart';
import '../../widgets/table_pager.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../services/services.dart';
import '../../widgets/styled_form_dialog.dart';
import '../../widgets/tooltip_text.dart';
import '../../widgets/destruction_status_pill.dart';
import '../../widgets/handover_cell.dart';
import '../../widgets/handover_form_dialog.dart';
import '../executive/unsold_shared.dart';

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
  String? _yearFilter;
  int _page = 0;
  // Delivery sub-filter (Sold / Destroyed / Re-exported pages): null = all,
  // true = delivered, false = pending.
  bool? _deliveryFilter;

  // ⚠️ Released joins the delivery pages. A release is RULED and the
  // goods are COLLECTED later; the page showed only the first, so all 33
  // rows looked finished while the yard could still be storing them.
  bool get _hasDelivery =>
      widget.finalTag == 'SOLD' ||
      widget.finalTag == 'DESTROYED' ||
      widget.finalTag == 'RE-EXPORTED' ||
      widget.finalTag == 'RELEASED';

  /// Everything this page is asking the database for.
  ///
  /// ⚠️ Every filter is in here, so every filter is applied in SQL. The page
  /// used to fetch every package in the yard and narrow it in Dart; now a
  /// filter change is a new query key and the database does the narrowing.
  DispositionQuery get _query => DispositionQuery(
        finalTag: widget.finalTag,
        page: _page,
        search: _search,
        dateStart: _dateRange?.start,
        dateEnd: _dateRange?.end,
        year: _yearFilter,
        delivered: _hasDelivery ? _deliveryFilter : null,
      );

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ⚠️ The tag sets, the status sets, the note parsing and the row building
  // all moved to the `disposition_rows` VIEW (postgres/18, and 20 for the
  // delivery column). They are not gone — they are in SQL, verbatim, because
  // paging in SQL needs the rows to exist in SQL.
  //
  // That includes 'FINAL:DESTROY' with no ED: the PENDING tag
  // disposeWarehouseItem writes, since it upper-cases the action name and the
  // action is "Destroy". Without it a package marked for destruction reaches
  // no page at all and can never be confirmed. The view keeps it, and
  // disposition_paging_test.dart holds it there.

  /// The view's rows, as the widgets on this page already expect them.
  ///
  /// ⚠️ This REPLACES the two builders that used to live here — one walking
  /// every package's warehouse entries and items, the other merging in Top
  /// Management's re-export rulings, both then sorted and sliced in Dart. All
  /// three of those jobs (which rows, in what order, which page) now happen in
  /// SQL; this only rehydrates the twenty rows that came back.
  ///
  /// A package can be missing from [DispositionPageWithPackages.packages] only
  /// if it was deleted between the two queries, so such a row is skipped
  /// rather than rendered half-built.
  List<_CategoryRow> _rowsFrom(DispositionPageWithPackages result) {
    final out = <_CategoryRow>[];
    for (final r in result.rows) {
      final pkg = result.packages[r.packageId];
      if (pkg == null) continue;
      // The entry and the item, when this row came from one of them. Both are
      // already loaded on the package.
      final entry = r.entryId == null
          ? null
          : pkg.warehouseEntries.where((e) => e.id == r.entryId).firstOrNull;
      final item = r.itemId == null
          ? null
          : pkg.items.where((i) => i.id == r.itemId).firstOrNull;
      out.add(_CategoryRow(
        package: pkg,
        entry: entry,
        item: item,
        itemName: r.itemName,
        note: r.note ?? '',
        officer: r.officer ?? '—',
        // ⚠️ Only a Top Management row carries these, and the popup keys its
        // whole Tender History off them — see _CategoryRow.proposal.
        proposal: r.isTopManagement ? _proposalFor(r) : null,
        forfeited: r.isTopManagement ? _forfeitedFor(r) : null,
        fromTopManagement: r.isTopManagement,
        delivered: r.delivered,
        deliveredAt: r.deliveredAt,
      ));
    }
    return out;
  }

  /// The DG's decision behind a Top Management row.
  ///
  /// Read from the map every portal shares, so the note and date shown here
  /// are the same ones the Unsold page shows.
  UnsoldProposalModel? _proposalFor(DispositionRow r) {
    final byItem =
        ref.watch(unsoldProposalsByItemProvider).valueOrNull ?? const {};
    return r.itemId == null ? null : byItem[r.itemId!];
  }

  /// The forfeited row behind a Top Management decision, for the popup's
  /// Tender History.
  ForfeitedPackageModel? _forfeitedFor(DispositionRow r) {
    if (r.itemId == null) return null;
    return ref
        .watch(forfeitedByItemProvider(r.packageId))
        .valueOrNull?[r.itemId!];
  }

  /// A compact pill for the Delivered / Pending / All delivery sub-filter,
  /// styled like the date/year filter chips beside it.
  Widget _deliveryFilterChip(String label, bool? value, IconData icon) {
    final selected = _deliveryFilter == value;
    final color = context.colors.primaryGold;
    return OutlinedButton.icon(
      onPressed: () => setState(() {
        _deliveryFilter = value;
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
        side: BorderSide(
            color: selected ? color : context.colors.borderColor),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ ONE page of rows, already filtered and sorted by the database — not
    // every package in the yard. The delivery maps that used to be fetched
    // here went with it: the view answers that per SALE now, which the
    // package-keyed maps could not do.
    final page = ref.watch(dispositionPageWithPackagesProvider(_query));
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
                    // The count the DATABASE reports for this filter, not the
                    // length of a list held in memory.
                    page.when(
                      data: (p) => Text('${p.total} ${widget.countLabel}',
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
                          // ⚠️ From its own query, not from the loaded rows —
                          // the page holds twenty of them, which would offer
                          // only the years visible right now.
                          years: srYears(ref
                                  .watch(dispositionYearSourceProvider(
                                      widget.finalTag))
                                  .valueOrNull ??
                              const <String>[]),
                          onChanged: (v) => setState(() {
                            _yearFilter = v;
                            _page = 0;
                          }),
                        ),
                        // Delivery filter — Sold / Destroyed pages only.
                        if (_hasDelivery) ...[
                          _deliveryFilterChip('All', null, Icons.all_inbox_rounded),
                          _deliveryFilterChip(
                              widget.finalTag == 'DESTROYED'
                                  ? 'Destroyed'
                                  : 'Delivered',
                              true,
                              Icons.check_circle_rounded),
                          _deliveryFilterChip(
                              'Pending', false, Icons.schedule_rounded),
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
                child: page.when(
                  loading: () => Center(
                      child: CircularProgressIndicator(
                          color: context.colors.primaryGold)),
                  error: (e, _) => ErrorView(
                      error: e,
                      onRetry: () => ref.refresh(
                          dispositionPageWithPackagesProvider(_query))),
                  data: (result) {
                    // The rows for THIS page, in the order the database sorted
                    // them. No filtering left to do here — it all happened in
                    // SQL, which is what makes the page cost the page rather
                    // than the table.
                    final pageRows = _rowsFrom(result);
                    final maxPage = result.total == 0
                        ? 0
                        : (result.total - 1) ~/ kDispositionPageSize;
                    if (_page > maxPage) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _page = maxPage);
                      });
                    }

                    // ⚠️ ONE spend query for the whole page. The Destruction
                    // Expenses cells below read this scope rather than each
                    // fetching the yard ledger — see DestructionExpenseCell.
                    return DestructionExpenseScope(
                      srKey: DestructionExpenseScope.keyFor(
                          pageRows.map((r) => r.package.srNumber)),
                      child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                          empty: EmptyTableState(
                              message:
                                  'No ${widget.countLabel.toLowerCase()} packages found'),
                          isVerticalScrollBarVisible: true,
                          isHorizontalScrollBarVisible: false,
                          columns: [
                            const DataColumn2(
                                label: Text('SR Number'), size: ColumnSize.M),
                            const DataColumn2(
                                label: Text('Goods Name'), size: ColumnSize.M),
                            if (widget.finalTag != 'DESTROYED')
                              const DataColumn2(
                                  label: Text('HS Code'),
                                  size: ColumnSize.S,
                                  fixedWidth: 110),
                            const DataColumn2(
                                label: Text('Qty'),
                                size: ColumnSize.S,
                                fixedWidth: 70),
                            const DataColumn2(
                                label: Text('Date'), size: ColumnSize.M),
                            // ⚠️ No Officer column on RE-EXPORTED. It reads
                            // `returnedByName ?? returnedByBadge ?? '—'`, and
                            // a re-export sets neither — the act is recorded
                            // against the package, not against a person — so
                            // every row printed a dash. A column of dashes is
                            // not data waiting to arrive; it is a question
                            // this page has no answer to.
                            if (widget.finalTag != 'SOLD' &&
                                widget.finalTag != 'DESTROYED' &&
                                widget.finalTag != 'RE-EXPORTED')
                              const DataColumn2(
                                  label: Text('Officer'), size: ColumnSize.M),
                            // ⚠️ WHO sent them back. The two routes are not
                            // the same event and an officer reading this page
                            // needs to tell them apart: the yard's own Final
                            // Disposition, or Top Management ruling on goods
                            // that failed every tender.
                            if (widget.finalTag == 'RE-EXPORTED')
                              const DataColumn2(
                                  label: Text('Decided By'),
                                  size: ColumnSize.S,
                                  fixedWidth: 170),
                            // Destroyed rows carry no receipt and no useful
                            // note -- the column only ever printed the DSR
                            // number already shown elsewhere, so it is dropped
                            // there to match Central Disposal's own table.
                            if (widget.finalTag != 'DESTROYED')
                              DataColumn2(
                                  label: Text(widget.finalTag == 'SOLD'
                                      ? 'Receipt No'
                                      : 'Notes'),
                                  size: ColumnSize.M),
                            if (widget.finalTag == 'SOLD')
                              const DataColumn2(
                                  label: Text('Valuation'), size: ColumnSize.M),
                            if (widget.finalTag == 'SOLD')
                              DataColumn2(
                                  label: Text('Sold Price'),
                                  size: ColumnSize.M),
                            if (widget.finalTag == 'SOLD' ||
                                widget.finalTag == 'RE-EXPORTED' ||
                                widget.finalTag == 'RELEASED')
                              // Same width as the Destroyed Goods status
                              // column: both hold the same fixed-size pill, so
                              // a narrower box here would clip it.
                              const DataColumn2(
                                  label: Center(child: Text('Delivery')),
                                  fixedWidth: kDestructionStatusColumnWidth),
                            // What the destruction actually cost -- the same
                            // SR-level figure Central Disposal's own Destroyed
                            // Goods table shows, so the yard can see the spend
                            // without opening the popup.
                            if (widget.finalTag == 'DESTROYED')
                              const DataColumn2(
                                  label: Text('Destruction Expenses'),
                                  size: ColumnSize.M),
                            if (widget.finalTag == 'DESTROYED')
                              const DataColumn2(
                                  label: Center(child: Text('Status')),
                                  fixedWidth: kDestructionStatusColumnWidth),
                            const DataColumn2(
                                label: Center(child: Text('Details')),
                                size: ColumnSize.S,
                                fixedWidth: 55),
                          ],
                          rows: pageRows
                              .map((row) => DataRow(cells: [
                                    DataCell(TooltipText(row.package.srNumber,
                                        style: TextStyle(
                                            color: context
                                                .colors.accentLightBlue,
                                            fontWeight: FontWeight.w600))),
                                    DataCell(TooltipText(row.itemName,
                                        overflow: TextOverflow.ellipsis)),
                                    if (widget.finalTag != 'DESTROYED')
                                      DataCell(TooltipText((() {
                                        final itemId =
                                            row.entry?.packageItemId ??
                                                row.item?.id;
                                        final hs = row.package.items
                                            .where((i) => i.id == itemId)
                                            .firstOrNull
                                            ?.hsCode;
                                        return (hs != null && hs.isNotEmpty)
                                            ? hs
                                            : '—';
                                      })(),
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12))),
                                    DataCell(TooltipText(
                                        '${row.entry?.itemCount ?? row.item?.quantity ?? 0}')),
                                    DataCell(TooltipText(row.entry?.returnedAt != null
                                        ? DateFormat('yyyy-MM-dd')
                                            .format(row.entry!.returnedAt!)
                                        : '—')),
                                    if (widget.finalTag != 'SOLD' &&
                                        widget.finalTag != 'DESTROYED' &&
                                        widget.finalTag != 'RE-EXPORTED')
                                      DataCell(TooltipText(row.officer,
                                          overflow: TextOverflow.ellipsis)),
                                    if (widget.finalTag == 'RE-EXPORTED')
                                      DataCell(_OriginPill(
                                          fromTopManagement:
                                              row.fromTopManagement)),
                                    if (widget.finalTag != 'DESTROYED')
                                      DataCell(TooltipText(
                                          (() {
                                            if (widget.finalTag == 'SOLD') {
                                              return _parseSaleReceipt(
                                                      row.entry?.returnNotes) ??
                                                  '—';
                                            }
                                            return row.note.isEmpty
                                                ? '—'
                                                : row.note;
                                          })(),
                                          overflow: TextOverflow.ellipsis)),
                                    if (widget.finalTag == 'SOLD')
                                      DataCell(_SaleValuationCell(
                                        package: row.package,
                                        packageItemId: row.entry?.packageItemId,
                                        receipt: _parseSaleReceipt(
                                            row.entry?.returnNotes),
                                        qty: row.entry?.itemCount ??
                                            row.item?.quantity,
                                      )),
                                    if (widget.finalTag == 'SOLD')
                                      DataCell(_SaleFinancialsCell(
                                        package: row.package,
                                        packageItemId: row.entry?.packageItemId,
                                        receipt: _parseSaleReceipt(
                                            row.entry?.returnNotes),
                                      )),
                                    if (widget.finalTag == 'SOLD')
                                      DataCell(Center(child: _DeliveryStatusCell(
                                        package: row.package,
                                        packageItemId: row.entry?.packageItemId,
                                        receipt: _parseSaleReceipt(
                                            row.entry?.returnNotes),
                                      ))),
                                    if (widget.finalTag == 'RE-EXPORTED')
                                      DataCell(Center(
                                        child: row.fromTopManagement
                                            ? UnsoldDeliveryCell(
                                                proposal: row.proposal)
                                            // ⚠️ A yard-decided re-export used
                                            // to render a CONSTANT pill --
                                            // `delivered: true`, `onMark:
                                            // null` -- so all 17 read
                                            // Delivered from the moment the
                                            // disposition was recorded and
                                            // no officer could say
                                            // otherwise. Ruling a re-export
                                            // and the goods actually leaving
                                            // are two events; this cell is
                                            // the second one.
                                            : HandoverCell(
                                                entry: row.entry,
                                                delivered: row.delivered,
                                                kind: HandoverEntryKind
                                                    .reexport,
                                                package: row.package,
                                                rates: storageRateHistory),
                                      )),
                                    if (widget.finalTag == 'RELEASED')
                                      DataCell(Center(
                                        child: HandoverCell(
                                          entry: row.entry,
                                          delivered: row.delivered,
                                          kind: HandoverEntryKind.released,
                                        ),
                                      )),
                                    if (widget.finalTag == 'DESTROYED')
                                      DataCell(DestructionExpenseCell(
                                          srNumber: row.package.srNumber)),
                                    if (widget.finalTag == 'DESTROYED')
                                      DataCell(Center(
                                        child: DestructionStatusPill(
                                          destroyed: row.isDestroyed,
                                          onMark: row.isDestroyed
                                              ? null
                                              : () => _confirmMarkDestroyed(
                                                  context, ref, row),
                                        ),
                                      )),
                                    DataCell(Center(
                                        child: IconButton(
                                      icon: Icon(Icons.info_outline_rounded,
                                          color:
                                              context.colors.accentLightBlue,
                                          size: 18),
                                      onPressed: () async {
                                        // The forfeited row behind this sale,
                                        // so the popup can show the same
                                        // per-round Tender History the Unsold
                                        // page shows. A sold package may have
                                        // been re-valued several times before
                                        // it sold, and that chain was
                                        // invisible here.
                                        // ⚠️ The SAME key the row's own cells
                                        // watch: package|item|receipt. This
                                        // read package|item, which is a
                                        // different provider instance that
                                        // nothing had ever watched — so it
                                        // was still AsyncLoading, asData was
                                        // null, and the whole Tender History
                                        // section silently disappeared from
                                        // the popup: every round, the
                                        // committee and all the bids with it.
                                        //
                                        // With the right key it is already
                                        // resolved, because the row painted
                                        // its Valuation cell from it.
                                        final saleItem = ref
                                            .read(saleItemForPackageItemProvider(
                                                '${row.package.id}|'
                                                '${row.entry?.packageItemId ?? row.item?.id ?? ''}|'
                                                '${_parseSaleReceipt(row.entry?.returnNotes) ?? ''}'))
                                            .asData
                                            ?.value;
                                        // ⚠️ READ on the tap, not watched
                                        // while the table builds.
                                        // `srFinancialsProvider` is
                                        // getAllPackages() across every yard
                                        // plus getTenderSales() (~216ms
                                        // measured), and watching it from
                                        // this cell made every page of the
                                        // table wait for it -- to fill one
                                        // field only the popup reads.
                                        // Awaiting it here also means the
                                        // costs are THERE when the popup
                                        // opens, rather than reading "not
                                        // available" until the ledger caught
                                        // up.
                                        SrFinancials? srFin;
                                        try {
                                          srFin = (await ref.read(
                                                  srFinancialsProvider.future))
                                              .where((f) =>
                                                  f.srNumber.trim() ==
                                                  row.package.srNumber.trim())
                                              .firstOrNull;
                                        } catch (_) {
                                          // The costs section degrades; the
                                          // rest of the popup does not need
                                          // this and should still open.
                                        }
                                        if (!context.mounted) return;
                                        showDialog(
                                          context: context,
                                          builder: (_) =>
                                              PackageDetailsDialog(
                                            package: row.package,
                                            storageRate: storageRateHistory,
                                            highlightEntry: row.entry,
                                            highlightItemId: row.entry?.packageItemId ?? row.item?.id,
                                            useLegacySummary: true,
                                            // ⚠️ A Top Management row already
                                            // HAS its forfeited row — it came
                                            // from the unsold list — so use
                                            // it directly. The sale-item
                                            // lookup only knows about goods
                                            // that went through a sale on
                                            // this page's own route, and
                                            // would return nothing here,
                                            // leaving a package with a full
                                            // tender history showing none.
                                            tenderHistoryFor: row.forfeited ??
                                                saleItem?.forfeited,
                                            // The SAME quantity the row's
                                            // Valuation cell uses. These rows
                                            // are built from warehouse
                                            // entries, where `item` is null —
                                            // so passing only item.quantity
                                            // sent null, and the history fell
                                            // back to a qty of 1 and printed
                                            // "@ 950 × 1" beside a table
                                            // reading "@ 665 × 150".
                                            valuationQty: row.entry?.itemCount ??
                                                row.item?.quantity,
                                            // Same figure the Central
                                            // Disposal Destroyed Goods popup
                                            // now carries -- without it the
                                            // yard's own popup showed "not
                                            // available" even once Central
                                            // Disposal had recorded the
                                            // destruction expenses.
                                            srFinancials: srFin,
                                            // ⚠️ RE-EXPORT and RELEASE only,
                                            // and only a row the YARD
                                            // recorded.
                                            //
                                            // Both are two events wearing
                                            // one date: the yard rules it,
                                            // and the goods leave later --
                                            // a ship sails, an owner
                                            // arrives. Only the ruling was
                                            // ever stored, so both pages
                                            // reported every row finished
                                            // on the day it was decided.
                                            //
                                            // Sold and Destroyed pass null:
                                            // they already state their
                                            // ending twice, in the tender
                                            // history's Final Outcome panel
                                            // and a Sold Price column, or a
                                            // Destruction Status &
                                            // Financials section. A Top
                                            // Management row does too --
                                            // its ruling, date, note and
                                            // hand-over are all in that
                                            // same panel.
                                            handover: row.fromTopManagement
                                                ? null
                                                : switch (widget.finalTag) {
                                                    'RE-EXPORTED' =>
                                                      HandoverOutcome(
                                                        kind: HandoverKind
                                                            .reexport,
                                                        note: row.note
                                                                .trim()
                                                                .isEmpty
                                                            ? null
                                                            : row.note.trim(),
                                                        decidedAt: row.entry
                                                            ?.returnedAt,
                                                        delivered:
                                                            row.delivered ??
                                                                false,
                                                        deliveredAt:
                                                            row.deliveredAt,
                                                      ),
                                                    'RELEASED' =>
                                                      HandoverOutcome(
                                                        kind: HandoverKind
                                                            .released,
                                                        // ⚠️ A release's
                                                        // note is the
                                                        // receipt line, and
                                                        // the popup already
                                                        // shows Receipt No
                                                        // and Receipt Date
                                                        // as their own
                                                        // fields. Repeating
                                                        // it here would say
                                                        // the same thing a
                                                        // third time.
                                                        decidedAt: row.entry
                                                            ?.returnedAt,
                                                        delivered:
                                                            row.delivered ??
                                                                false,
                                                        deliveredAt:
                                                            row.deliveredAt,
                                                      ),
                                                    _ => null,
                                                  },
                                          ),
                                        );
                                      },
                                    ))),
                                  ]))
                              .toList(),
                        ),
                      ),
                          ),
                        ),
                        TablePager(
                          // The DATABASE's count for this filter. A pager
                          // whose total is the length of the loaded list can
                          // only ever say "20 of 20".
                          total: result.total,
                          page: _page.clamp(0, maxPage),
                          pageSize: kDispositionPageSize,
                          onPageChanged: (p) => setState(() => _page = p),
                        ),
                      ],
                    )
                        .animate()
                        .slideY(begin: 0.1, duration: 400.ms, delay: 300.ms)
                        .fadeIn(),
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

/// Which route sent these goods back.
///
/// ⚠️ Two very different events end on this page, and only the label tells
/// them apart: the yard's own Final Disposition, taken before the goods ever
/// went to tender; or Top Management ruling "Re-export" after every tender
/// round failed. The second carries a whole tender history behind it and the
/// first carries none, so an officer reading a row needs to know which they
/// are looking at before they open it.
class _OriginPill extends StatelessWidget {
  const _OriginPill({required this.fromTopManagement});
  final bool fromTopManagement;

  @override
  Widget build(BuildContext context) {
    final tint = fromTopManagement
        ? context.colors.primaryGold
        : context.colors.accentLightBlue;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: tint.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: tint.withOpacity(0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
              fromTopManagement
                  ? Icons.account_balance_rounded
                  : Icons.warehouse_rounded,
              size: 13,
              color: tint),
          const Gap(6),
          Text(fromTopManagement ? 'Top Management' : 'Yard',
              style: TextStyle(
                  color: tint, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

class _CategoryRow {
  final PackageModel package;
  final WarehouseEntryModel? entry;
  final String itemName;
  final String note;
  final String officer;
  // For status-only rows (no warehouse entry): the package item itself.
  final PackageItem? item;

  /// ⚠️ Set only when the row arrived by the TOP MANAGEMENT route.
  ///
  /// Goods reach Re-exported two ways, and they are not the same event:
  ///
  ///   * The yard's Final Disposition sends them straight back — the goods
  ///     were never going to be sold, so there is no tender behind them.
  ///   * A package that went to tender, failed every round, and was then
  ///     ruled "Re-export" by the DG. That one HAS a tender history, a
  ///     valuation and a decision date, and none of it was visible because
  ///     the page only ever looked at warehouse entries and item statuses.
  ///
  /// A DG decision on `re_export` had nowhere to land at all: the outcome is
  /// offered in the decision dialog, but no page listed it, so those goods
  /// would simply have disappeared.
  final UnsoldProposalModel? proposal;

  /// The forfeited row behind a Top Management decision, for the popup's
  /// Tender History.
  final ForfeitedPackageModel? forfeited;

  /// Which route recorded this, straight from the view.
  ///
  /// ⚠️ NOT derived from [proposal] being non-null. The proposal is fetched by
  /// a second provider that may still be loading, and a row that briefly
  /// reported itself as a yard row would flip its Decided By pill under the
  /// reader's eyes. The view answered this question when it built the row.
  final bool fromTopManagement;

  /// The delivery answer straight from `disposition_rows`.
  ///
  /// ⚠️ Read from the VIEW, not derived here. The view knows which of the
  /// four delivery sources applies to this row -- a sale's is_delivered, a
  /// destruction's, a proposal's, or a re-export entry's -- and a second
  /// answer computed in Dart would be a second story to keep in step.
  final bool? delivered;

  /// The day it was handed over, when one was recorded.
  final DateTime? deliveredAt;

  const _CategoryRow({
    required this.package,
    this.entry,
    required this.itemName,
    required this.note,
    required this.officer,
    this.item,
    this.proposal,
    this.forfeited,
    this.fromTopManagement = false,
    this.delivered,
    this.deliveredAt,
  });

  bool get isDestroyed {
    final notes = (entry?.returnNotes ?? '').trim().toUpperCase();
    if (notes.startsWith('[FINAL:DESTROYED]') || notes.startsWith('[DESTROYED]')) return true;
    if (item?.status?.toLowerCase() == 'destroyed') return true;
    return false;
  }
}

// Read-only delivery STATUS chip (the action button is in the details dialog,
// enabled for yards). Uses per-item provider so each row shows its own status.
/// Delivery status for a SOLD item, and the action that changes it.
///
/// Confirming delivery is the yard's ONE routine action on a sold row, and it
/// was buried in the details popup: open the row, scroll, press, watch the
/// popup close. It belongs in the table, next to the status it changes.
///
/// ⚠️ There is no revert. Once delivered the chip is a plain label again --
/// goods that have left with their buyer cannot un-leave.
class _DeliveryStatusCell extends ConsumerStatefulWidget {
  final PackageModel package;
  final String? packageItemId;

  /// Pins the exact TSI row when an item was sold across several partial sales.
  final String? receipt;
  const _DeliveryStatusCell(
      {required this.package, this.packageItemId, this.receipt});

  @override
  ConsumerState<_DeliveryStatusCell> createState() =>
      _DeliveryStatusCellState();
}

class _DeliveryStatusCellState extends ConsumerState<_DeliveryStatusCell> {
  bool _saving = false;

  /// What the goods have cost in storage, on the entry this row is about.
  ///
  /// ⚠️ The SR's ENTRY DATE to the sale, the same rule every other
  /// hand-over uses -- so the three forms cannot quote three figures for
  /// the same goods.
  double _storageCharge() {
    final entry = widget.package.warehouseEntries
        .where((e) => e.packageItemId == widget.packageItemId)
        .firstOrNull;
    if (entry == null) return 0;
    final rates = ref.read(storageRateProvider).valueOrNull;
    if (rates == null) return 0;
    return handoverCharge(entry, widget.package, rates);
  }

  String get _key =>
      '${widget.package.id}|${widget.packageItemId ?? ''}|${widget.receipt ?? ''}';

  Future<void> _markDelivered(TenderSaleItemModel item) async {
    // ⚠️ The same form the release and re-export hand-overs use. The
    // buyer pays the storage before the goods go: this cell used to set a
    // flag and let them walk out with goods the yard had been keeping for
    // years, the charge collected on no receipt.
    final result = await showHandoverForm(
      context,
      title: 'Release Sold Goods to Buyer',
      actionLabel: 'Confirm Delivered',
      icon: Icons.sell_rounded,
      srNumber: widget.package.srNumber,
      itemName: widget.package.items
              .where((i) => i.id == widget.packageItemId)
              .firstOrNull
              ?.itemName ??
          '—',
      quantity: widget.package.warehouseEntries
              .where((e) => e.packageItemId == widget.packageItemId)
              .firstOrNull
              ?.itemCount ??
          0,
      charge: _storageCharge(),
      chargeCaption: 'Storage from the SR entry date to the sale',
    );
    if (result == null) return;

    setState(() => _saving = true);
    try {
      await ref.read(disposalServiceProvider).toggleDeliveryStatus(
            item.id,
            true,
            receiptNo: result.receiptNo,
            charge: result.charge,
            handedAt: result.handedOverAt,
          );
      // ⚠️ Invalidate the SHARED providers, not just this cell's. Central
      // Disposal's Sold table reads the same tender_sale_items row through
      // them, so refreshing only here would leave the two portals disagreeing
      // about whether the goods had been handed over.
      ref.invalidate(saleItemForPackageItemProvider(_key));
      ref.invalidate(saleItemForPackageProvider(widget.package.id));
      ref.read(tenderSaleItemsRefreshProvider.notifier).trigger();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Marked as Delivered'),
          backgroundColor: context.colors.successGreen,
        ));
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, e, action: 'Confirming delivery');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(saleItemForPackageItemProvider(_key));
    // Only a yard confirms delivery; Central Disposal watches.
    final profile = ref.watch(currentProfileProvider);
    final canEdit = profile != null && !profile.isDisposal;

    return async.when(
      loading: () => const SizedBox(
          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => const Text('—'),
      data: (item) {
        if (item == null) return const Text('—');
        // The SAME pill the Destroyed Goods column uses -- one fixed box for
        // all three states, so neither column jumps as a row changes state and
        // the two tables line up beside each other.
        return Tooltip(
          message: item.isDelivered
              ? 'The buyer has taken the goods'
              : (canEdit
                  ? 'Confirm the buyer has taken the goods'
                  : 'Awaiting the yard to confirm hand-over'),
          child: DeliveryStatusPill(
            delivered: item.isDelivered,
            busy: _saving,
            onMark: canEdit ? () => _markDelivered(item) : null,
          ),
        );
      },
    );
  }
}

class _SaleValuationCell extends ConsumerWidget {
  final PackageModel package;
  final String? packageItemId;
  /// Pins the exact TSI row when an item was sold across several partial sales
  /// (same package_item_id, distinct qty/valuation per sale).
  final String? receipt;
  /// The quantity shown in the table's Qty column — the valuation must multiply
  /// by exactly this so "@ unit × qty" stays consistent with what the row shows.
  final int? qty;
  const _SaleValuationCell(
      {required this.package, this.packageItemId, this.receipt, this.qty});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = '${package.id}|${packageItemId ?? ''}|${receipt ?? ''}';
    final async = ref.watch(saleItemForPackageItemProvider(key));
    return async.when(
      loading: () => const SizedBox(
          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => Text('—', style: TextStyle(color: context.colors.textMuted)),
      data: (item) {
        final fp = item?.forfeited;
        if (fp == null) {
          return Text('—', style: TextStyle(color: context.colors.textMuted));
        }
        // Prefer the LATEST tender re-valuation, exactly as Central Disposal
        // does. Without this the yard showed the ORIGINAL valuation for a
        // package that had since been re-valued, so the two screens disagreed
        // about the same goods.
        final revals =
            ref.watch(tenderRevaluationsProvider(fp.id)).asData?.value ??
                const <String, TenderRevaluationModel>{};
        // Warm the rest of the details popup's Tender History while the table
        // is on screen. This cell already resolves the forfeited package for
        // every visible row, so the two remaining reads cost nothing here and
        // the section is ready the moment the popup opens instead of fetching
        // on click. (Central Disposal never needed this — its Tender Sales tab
        // had already cached the data.)
        ref.watch(tenderRoundsForPackageProvider(fp.id));
        ref.watch(tenderBidsProvider(fp.id));
        TenderRevaluationModel? latest;
        for (final r in revals.values) {
          if (latest == null || r.createdAt.isAfter(latest.createdAt)) {
            latest = r;
          }
        }
        final isRevalued = latest != null;
        final unitCost = latest?.valuationCost ?? fp.valuationCost;
        if (unitCost == null) {
          return Text('—', style: TextStyle(color: context.colors.textMuted));
        }
        final int effQty;
        if (qty != null && qty! > 0) {
          effQty = qty!;
        } else if (fp.entryQty != null) {
          effQty = fp.entryQty!;
        } else if (fp.itemId != null) {
          effQty = fp.packageDetails?.items
                  .where((i) => i.id == fp.itemId)
                  .firstOrNull
                  ?.quantity ??
              1;
        } else {
          effQty = fp.packageDetails?.items
                  .fold<int>(0, (s, i) => s + i.quantity) ??
              1;
        }
        final total = unitCost * effQty;
        final fmt = NumberFormat('#,##0');
        // Blue + a price-change icon when the figure is a re-valuation, the
        // same signal Central Disposal uses.
        final priceColor = isRevalued
            ? context.colors.accentLightBlue
            : context.colors.primaryGold;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ⚠️ The amount must be allowed to SHRINK. With
            // MainAxisSize.min and an unconstrained Text, a large re-valued
            // figure ("Rs 22,768,380" plus the icon) is wider than the column
            // and Flutter paints its overflow stripes straight down the table
            // -- the vertical red bar seen on Sold Goods. Flexible + ellipsis
            // lets the number give way instead.
            Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text('Rs ${fmt.format(total)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: priceColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 12)),
              ),
              if (isRevalued) ...[
                const SizedBox(width: 4),
                Icon(Icons.price_change_rounded,
                    size: 11, color: context.colors.accentLightBlue),
              ],
            ]),
            Text(
                '@ ${fmt.format(unitCost)} × $effQty'
                '${isRevalued ? ' · re-valued' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontSize: 10, color: context.colors.textMuted)),
          ],
        );
      },
    );
  }
}

Future<void> _confirmMarkDestroyed(
    BuildContext context, WidgetRef ref, _CategoryRow row) async {
  final itemId = row.entry?.packageItemId ?? row.item?.id;
  if (itemId == null) return;
  final qty = row.entry?.itemCount ?? row.item?.quantity ?? 1;
  DateTime pickedDate = DateTime.now();
  final notesCtrl = TextEditingController();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlgState) => StyledFormDialog(
        label: 'DESTROY GOODS',
        title: 'Mark as Destroyed',
        icon: Icons.local_fire_department_rounded,
        headerAccentColor: ctx.colors.dangerRed,
        width: 480,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: ctx.colors.dangerRed,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.check_rounded, size: 16),
            label: const Text('Confirm Destruction'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            StyledFormSection(
              title: 'Package Information',
              icon: Icons.inventory_2_rounded,
              children: [
                _DialogDetailRow(
                    label: 'SR Number', value: row.package.srNumber),
                _DialogDetailRow(label: 'Goods Name', value: row.itemName),
                _DialogDetailRow(label: 'Quantity', value: '$qty'),
              ],
            ),
            const Gap(14),
            StyledFormSection(
              title: 'Destruction Details',
              icon: Icons.edit_calendar_rounded,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.calendar_today_rounded,
                      color: ctx.colors.primaryGold, size: 20),
                  title: const Text('Destruction Date',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle:
                      Text(DateFormat('yyyy-MM-dd').format(pickedDate)),
                  trailing: OutlinedButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: pickedDate,
                        firstDate: DateTime(2020),
                        // ⚠️ TODAY, not a year out. This records when goods
                        // WERE destroyed — an act that has already happened —
                        // so a future date is not a date the officer might
                        // mean, it is one they cannot mean. The picker used to
                        // offer 365 days ahead and accept any of them.
                        lastDate: DateTime.now(),
                      );
                      if (d != null) {
                        setDlgState(() => pickedDate = d);
                      }
                    },
                    child: const Text('Change'),
                  ),
                ),
                const Gap(8),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notes / Remarks (Optional)',
                    hintText:
                        'Enter destruction certificate # or remarks...',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  if (confirmed == true) {
    try {
      await WarehouseService().recordFinalDisposition(
        packageItemId: itemId,
        dispositionType: 'DESTROYED',
        qty: qty,
        dispositionDate: pickedDate,
        notes: notesCtrl.text.trim().isNotEmpty ? notesCtrl.text.trim() : null,
      );
      ref.invalidate(livePackagesProvider);
      ref.invalidate(disposalDestroyedPackagesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${row.itemName} marked as Destroyed.'),
            backgroundColor: context.colors.successGreen,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        showErrorSnack(context, e);
      }
    }
  }
}

class _DialogDetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DialogDetailRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(
                    color: context.colors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}


/// Parse the receipt number from a "[FINAL:SOLD] — Receipt: <no>" warehouse
/// note. Used to pin the exact TSI row for an item sold across several partial
/// tenders (same package_item_id, distinct prices/receipts).
String? _parseSaleReceipt(String? returnNotes) {
  if (returnNotes == null) return null;
  final m = RegExp(r'Receipt:\s*([^\|—]+)', caseSensitive: false)
      .firstMatch(returnNotes);
  return m?.group(1)?.trim();
}

/// Read-only sold price + tax total for a sold package. Uses per-item provider.
class _SaleFinancialsCell extends ConsumerWidget {
  final PackageModel package;
  final String? packageItemId;
  /// Receipt of THIS sale — pins the exact TSI row when an item was sold across
  /// several partial tenders (same package_item_id, distinct prices).
  final String? receipt;
  const _SaleFinancialsCell(
      {required this.package, this.packageItemId, this.receipt});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key =
        '${package.id}|${packageItemId ?? ''}|${receipt ?? ''}';
    final async = ref.watch(saleItemForPackageItemProvider(key));
    return async.when(
      loading: () => const SizedBox(
          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => const Text('—'),
      data: (item) {
        if (item == null) return const Text('—');
        double taxSum = 0;
        for (final t in item.appliedTaxes) {
          taxSum += parseDbNum(t['amount']) ?? 0;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Rs ${item.soldPrice.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Tax: Rs ${taxSum.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 11, color: context.colors.textMuted)),
          ],
        );
      },
    );
  }
}
