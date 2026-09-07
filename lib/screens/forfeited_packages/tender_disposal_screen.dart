import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/supabase_client.dart';
import '../../core/app_session.dart';
import '../../models/models.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/empty_table_state.dart';
import '../../widgets/error_view.dart';
import '../../widgets/date_range_picker_dialog.dart' as custom;
import '../../widgets/year_filter.dart';
import '../../widgets/table_pager.dart';
import '../disposal/disposal_dashboard_screen.dart';
import 'tender_placement_dialog.dart';
import '../../widgets/tooltip_text.dart';

// ── Local providers ────────────────────────────────────────────

final tenderSearchProvider = StateProvider<String>((ref) => '');

// For each forfeited_package_id, what disposal has been recorded?
// We fetch all tender_disposals grouped by forfeitedPackageId
final tenderDisposalsMapProvider = FutureProvider<Map<String, TenderDisposalModel>>((ref) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  final data = await supabase
      .from('tender_disposals')
      .select('*, profiles(full_name)')
      .order('disposed_at', ascending: false);
  final map = <String, TenderDisposalModel>{};
  for (final row in data) {
    final model = TenderDisposalModel.fromJson(row as Map<String, dynamic>);
    // Keep the latest disposal per forfeited_package_id
    map.putIfAbsent(model.forfeitedPackageId, () => model);
  }
  return map;
});

// Full forfeited package detail lookup by id
final forfeitedPackageByIdProvider =
    FutureProvider.family<ForfeitedPackageModel?, String>((ref, id) async {
  ref.watch(forfeitedPackagesChangeTriggerProvider);
  final data = await supabase
      .from('forfeited_packages')
      .select('*, packages(*)')
      .eq('id', id)
      .maybeSingle();
  if (data == null) return null;
  return ForfeitedPackageModel.fromJson(data as Map<String, dynamic>);
});

// ⚠️ `allForfeitedMapProvider` lived here and nothing watched it.
//
// Its comment said the tender table used it "so tendered packages still
// resolve to a real SR number / consignee / item list" — the paged query
// fetches each sale's items with their forfeited rows, so the table resolves
// them itself. Left in place it was a fetch of EVERY forfeited package with
// every package item, kept alive by the file rather than by any reader.

// ── Screen ─────────────────────────────────────────────────────

class TenderDisposalScreen extends ConsumerStatefulWidget {
  const TenderDisposalScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<TenderDisposalScreen> createState() =>
      _TenderDisposalScreenState();
}

class _TenderDisposalScreenState
    extends ConsumerState<TenderDisposalScreen> {
  final _searchCtrl = TextEditingController();
  DateTimeRange? _dateRange;
  String? _yearFilter;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchCtrl.text = ref.read(tenderSearchProvider);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(tenderSearchProvider);
    final myYard = AppSession.currentYard;

    // ⚠️ One page from SQL. This screen used to watch `tenderSalesProvider` —
    // the heaviest query in the app, every sale in the country with its
    // items, forfeited rows, packages, package items and warehouse entries —
    // then filter it by yard, search, date range and year here and page the
    // result with `pageSlice`. Client-side paging still loads everything; it
    // only renders less.
    final query = TenderSaleQuery(
      page: _page,
      search: search.trim().isEmpty ? null : search.trim(),
      // The yard is the FILTER, not an afterthought: this page is "sales that
      // include packages from this yard", and the view matches on the yards a
      // sale's ITEMS carry rather than the sale's own column.
      yardFilter: myYard,
      dateStart: _dateRange?.start,
      dateEnd: _dateRange?.end,
      year: _yearFilter,
    );
    final salesAsync = ref.watch(tenderSalesPageProvider(query));
    // ⚠️ Over ALL sales, not this page. Derived from twenty rows a sale would
    // be called new simply because its predecessor sat on the page before.
    final retenderIds =
        ref.watch(retenderSaleIdsProvider).valueOrNull ?? const <String>{};

    return AppShell(
      currentRoute: '/tender-disposals',
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
                  Text('Tender Sale',
                      style: Theme.of(context).textTheme.headlineLarge),
                  Text(
                    'Tender sales that include packages from this yard',
                    style: TextStyle(color: context.colors.textSecondary),
                  ),
                ],
              ).animate().slideY(begin: 0.1, duration: 400.ms).fadeIn(),
              const Gap(20),

              // ── Search Bar ──────────────────────────────────────
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
                        hintText: 'Search by sale number or SR number...',
                        prefixIcon: Icon(Icons.search_rounded,
                            color: context.colors.textMuted),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear_rounded,
                                    color: context.colors.textMuted),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  ref
                                      .read(tenderSearchProvider.notifier)
                                      .state = '';
                                },
                              )
                            : null,
                        isDense: true,
                      ),
                      onChanged: (v) {
                        ref.read(tenderSearchProvider.notifier).state = v;
                        setState(() => _page = 0);
                      },
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
                              setState(() { _dateRange = picked; _page = 0; });
                            } else if (picked == false) {
                              setState(() { _dateRange = null; _page = 0; });
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
                            onPressed: () => setState(() { _dateRange = null; _page = 0; }),
                            tooltip: 'Clear Date Filter',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        const SizedBox(width: 8),
                        YearFilterButton(
                          value: _yearFilter,
                          // ⚠️ From ALL sales, not the page. Built from twenty
                          // rows the dropdown would offer only the years on
                          // screen, and a year that is not listed reads as
                          // records that no longer exist.
                          years: ref
                                  .watch(tenderSaleYearsProvider)
                                  .valueOrNull ??
                              const <String>[],
                          onChanged: (v) => setState(() { _yearFilter = v; _page = 0; }),
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

              // ── Tender Sales list (view-only, this yard's packages) ──────
              Expanded(
                child: salesAsync.when(
                  loading: () => Center(
                      child: CircularProgressIndicator(
                          color: context.colors.primaryGold)),
                  error: (e, _) => ErrorView(
                      error: e,
                      onRetry: () =>
                          ref.refresh(tenderSalesPageProvider(query))),
                  data: (data) {
                    // ⚠️ Nothing is filtered here any more. The yard, the
                    // search, the date range and the year are all in the SQL
                    // above — filtering a page would narrow the twenty rows on
                    // screen while the pager went on counting the sales it had
                    // just removed.
                    final visible = data.rows;

                    if (visible.isEmpty) {
                      return Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: context.colors.cardDark,
                          borderRadius: BorderRadius.circular(14),
                          border:
                              Border.all(color: context.colors.borderColor),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.storefront_rounded,
                                color: context.colors.textMuted, size: 48),
                            const Gap(12),
                            Text('No tender sales for this yard yet',
                                style: TextStyle(
                                    color: context.colors.textSecondary,
                                    fontSize: 16)),
                            const Gap(6),
                            Text(
                                'Sales are created centrally by the Disposal Directorate',
                                style: TextStyle(
                                    color: context.colors.textMuted,
                                    fontSize: 13)),
                          ],
                        ),
                      );
                    }

                    return Column(
                      children: [
                        Expanded(
                          child: ListView.separated(
                            itemCount: visible.length,
                            separatorBuilder: (_, __) => const Gap(16),
                            itemBuilder: (context, i) => TenderSaleCard(
                                sale: visible[i],
                                readOnly: true,
                                isRetender:
                                    retenderIds.contains(visible[i].id)),
                          )
                              .animate()
                              .slideY(
                                  begin: 0.1,
                                  duration: 400.ms,
                                  delay: 300.ms)
                              .fadeIn(),
                        ),
                        // ⚠️ Against the SERVER's count: `visible.length` is
                        // the page size now and would pin the pager to page 1.
                        TablePager(
                          total: data.total,
                          page: _page,
                          pageSize: kDispositionPageSize,
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

// ── Tender Card ─────────────────────────────────────────────────

class TenderCard extends ConsumerWidget {
  final TenderModel tender;
  final Map<String, TenderDisposalModel> disposalsMap;
  final Map<String, ForfeitedPackageModel> forfeitedMap;

  const TenderCard({
    required this.tender,
    required this.disposalsMap,
    required this.forfeitedMap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disposedCount = tender.forfeitedPackageIds
        .where((id) => disposalsMap.containsKey(id))
        .length;
    final total = tender.forfeitedPackageIds.length;
    final isComplete = disposedCount == total;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.cardDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isComplete
                ? context.colors.successGreen.withOpacity(0.4)
                : context.colors.borderColor,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Tender Header ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.colors.primaryGold.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.gavel_rounded,
                        color: context.colors.primaryGold, size: 22),
                  ),
                  const Gap(14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tender.tenderNumber,
                          style: TextStyle(
                            color: context.colors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        Row(
                          children: [
                            Icon(Icons.calendar_today_rounded,
                                size: 12,
                                color: context.colors.textMuted),
                            const Gap(4),
                            Text(
                              DateFormat('yyyy-MM-dd')
                                  .format(tender.tenderDate),
                              style: TextStyle(
                                  color: context.colors.textMuted,
                                  fontSize: 12),
                            ),
                            if (tender.createdByName != null) ...[
                              const Gap(12),
                              Icon(Icons.person_rounded,
                                  size: 12,
                                  color: context.colors.textMuted),
                              const Gap(4),
                              Text(
                                tender.createdByName!,
                                style: TextStyle(
                                    color: context.colors.textMuted,
                                    fontSize: 12),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Progress / Completion Badge
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isComplete
                              ? context.colors.successGreen.withOpacity(0.15)
                              : context.colors.warningAmber.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isComplete
                                ? context.colors.successGreen.withOpacity(0.4)
                                : context.colors.warningAmber.withOpacity(0.4),
                          ),
                        ),
                        child: Text(
                          isComplete
                              ? 'Completed'
                              : '$disposedCount / $total disposed',
                          style: TextStyle(
                            color: isComplete
                                ? context.colors.successGreen
                                : context.colors.warningAmber,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Divider(height: 1, color: context.colors.borderColor),

            // ── Packages Table ────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(12),
              child: _TenderPackagesTable(
                tender: tender,
                disposalsMap: disposalsMap,
                forfeitedMap: forfeitedMap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Packages Table inside a Tender Card ─────────────────────────

class _TenderPackagesTable extends ConsumerWidget {
  final TenderModel tender;
  final Map<String, TenderDisposalModel> disposalsMap;
  final Map<String, ForfeitedPackageModel> forfeitedMap;

  const _TenderPackagesTable({
    required this.tender,
    required this.disposalsMap,
    required this.forfeitedMap,
  });

  /// True if an item's status is a forfeit variant.
  bool _isForfeitItem(String? s) {
    final v = (s ?? '').trim().toLowerCase();
    return v == 'forfeit' || v == 'forfeited' || v == 'forfiet' || v == 'confiscated';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Break each tendered package into per-item rows so the same SR can be
    // shown once per forfeited item (matching the Abandoned / Forfeit tables).
    final rows = <_PackageRow>[];
    for (final pkgId in tender.forfeitedPackageIds) {
      final forfeited = forfeitedMap[pkgId];
      final disposal = disposalsMap[pkgId];
      final items = forfeited?.packageDetails?.items ?? [];
      final forfeitItems =
          items.where((i) => _isForfeitItem(i.status)).toList();
      final shown = forfeitItems.isNotEmpty
          ? forfeitItems
          : (items.isNotEmpty ? items : <PackageItem>[]);

      if (shown.isEmpty) {
        rows.add(_PackageRow(
          forfeitedPackageId: pkgId,
          forfeited: forfeited,
          disposal: disposal,
          item: null,
        ));
      } else {
        for (final item in shown) {
          rows.add(_PackageRow(
            forfeitedPackageId: pkgId,
            forfeited: forfeited,
            disposal: disposal,
            item: item,
          ));
        }
      }
    }

    return Container(
      height: (rows.length * 52.0 + 56).clamp(100, 340),
      decoration: BoxDecoration(
        border: Border.all(color: context.colors.borderColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: DataTable2(
          columnSpacing: 10,
          horizontalMargin: 12,
          fixedTopRows: 1,
          isVerticalScrollBarVisible: true,
          empty: const EmptyTableState(message: 'No packages in this tender'),
          columns: const [
            DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
            DataColumn2(label: Text('Goods Name'), size: ColumnSize.M),
            DataColumn2(label: Text('Consignee'), size: ColumnSize.M),
            DataColumn2(label: Text('Disposal Type'), size: ColumnSize.M),
            DataColumn2(label: Text('Receipt / Details'), size: ColumnSize.M),
            DataColumn2(label: Text('Disposed By'), size: ColumnSize.M),
            DataColumn2(
              label: Center(child: Text('Action')),
              size: ColumnSize.S,
              fixedWidth: 90,
            ),
          ],
          rows: rows.map((row) => DataRow2(
            cells: [
              DataCell(TooltipText(
                row.forfeited?.srNumber ?? row.forfeitedPackageId.substring(0, 8),
                style: TextStyle(
                  color: context.colors.accentLightBlue,
                  fontWeight: FontWeight.w600,
                ),
              )),
              DataCell(TooltipText(
                row.item?.itemName ?? 'Multiple/Unspecified',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500),
              )),
              DataCell(TooltipText(
                row.forfeited?.consigneeName ?? '—',
                overflow: TextOverflow.ellipsis,
              )),
              DataCell(row.disposal != null
                  ? _DisposalTypeBadge(type: row.disposal!.disposalType)
                  : Text('—',
                      style:
                          TextStyle(color: context.colors.textMuted))),
              DataCell(TooltipText(
                _receiptOrDetails(row.disposal),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: context.colors.textSecondary, fontSize: 13),
              )),
              DataCell(TooltipText(
                row.disposal?.disposedByName ?? '—',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: context.colors.textMuted, fontSize: 13),
              )),
              DataCell(Center(
                child: IconButton(
                  icon: Icon(
                    row.disposal != null
                        ? Icons.visibility_rounded
                        : Icons.assignment_ind_rounded,
                    color: row.disposal != null
                        ? context.colors.successGreen
                        : context.colors.primaryGold,
                    size: 20,
                  ),
                  tooltip: row.disposal != null
                      ? 'View Disposal'
                      : 'Record Disposal',
                  onPressed: () => _showDisposalDialog(
                      context, ref, row),
                ),
              )),
            ],
          )).toList(),
        ),
      ),
    );
  }

  String _receiptOrDetails(TenderDisposalModel? disposal) {
    if (disposal == null) return '—';
    if (disposal.receiptNumber != null && disposal.receiptNumber!.isNotEmpty) {
      return 'Receipt: ${disposal.receiptNumber}';
    }
    if (disposal.otherDetails != null && disposal.otherDetails!.isNotEmpty) {
      return disposal.otherDetails!;
    }
    return '—';
  }

  void _showDisposalDialog(
      BuildContext context, WidgetRef ref, _PackageRow row) {
    showDialog(
      context: context,
      builder: (_) => DisposalDialog(
        forfeitedPackageId: row.forfeitedPackageId,
        forfeited: row.forfeited,
        existingDisposal: row.disposal,
        tenderId: tender.id,
      ),
    );
  }
}

class _PackageRow {
  final String forfeitedPackageId;
  final ForfeitedPackageModel? forfeited;
  final TenderDisposalModel? disposal;
  final PackageItem? item; // null = package-level summary row

  _PackageRow({
    required this.forfeitedPackageId,
    this.forfeited,
    this.disposal,
    this.item,
  });
}

// ── Disposal Type Badge ──────────────────────────────────────────

class _DisposalTypeBadge extends StatelessWidget {
  final String type;
  const _DisposalTypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (type) {
      'sold' => ('Sold', context.colors.successGreen),
      're_export' => ('Re-export', context.colors.accentLightBlue),
      'release' => ('Released', context.colors.heldOrange),
      'govt_use' => ('Govt. Use', context.colors.primaryGold),
      'destroy' => ('Destroy', context.colors.dangerRed),
      'other' => ('Other', context.colors.textSecondary),
      _ => (type, context.colors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 11)),
    );
  }
}

// ── Disposal Dialog ─────────────────────────────────────────────

class DisposalDialog extends ConsumerStatefulWidget {
  final String forfeitedPackageId;
  final ForfeitedPackageModel? forfeited;
  final TenderDisposalModel? existingDisposal;
  final String tenderId;

  const DisposalDialog({
    Key? key,
    required this.forfeitedPackageId,
    this.forfeited,
    this.existingDisposal,
    required this.tenderId,
  }) : super(key: key);

  @override
  ConsumerState<DisposalDialog> createState() => _DisposalDialogState();
}

class _DisposalDialogState extends ConsumerState<DisposalDialog> {
  String? _selectedDisposalType;
  late TextEditingController _receiptNumberController;
  late TextEditingController _otherDetailsController;
  bool _isLoading = false;

  final List<(String, String, IconData, String)> _disposalTypes = const [
    ('sold', 'Sold', Icons.sell_rounded, 'Goods sold / disposed by sale.'),
    ('re_export', 'Re-export', Icons.flight_takeoff_rounded,
        'Goods sent back to country of origin.'),
    ('release', 'Release', Icons.lock_open_rounded,
        'Goods released back to the owner / consignee.'),
    ('govt_use', 'Government Use', Icons.account_balance_rounded,
        'Goods transferred for government use.'),
    ('destroy', 'Destroy', Icons.delete_forever_rounded,
        'Goods destroyed.'),
    ('other', 'Other', Icons.more_horiz_rounded,
        'Custom disposal outcome.'),
  ];

  // Outcomes a yard admin may NOT record here — they are handled centrally by
  // the Central Disposal Directorate (Sold via Tender Sale; Destroy / Govt Use
  // via the directorate). Shown disabled so the reason is visible.
  static const Set<String> _restrictedTypes = {'sold', 'govt_use', 'destroy'};

  @override
  void initState() {
    super.initState();
    _receiptNumberController = TextEditingController(
        text: widget.existingDisposal?.receiptNumber ?? '');
    _otherDetailsController = TextEditingController(
        text: widget.existingDisposal?.otherDetails ?? '');
    _selectedDisposalType = widget.existingDisposal?.disposalType;
  }

  @override
  void dispose() {
    _receiptNumberController.dispose();
    _otherDetailsController.dispose();
    super.dispose();
  }

  bool get _isViewOnly => widget.existingDisposal != null;

  Future<void> _handleSave() async {
    if (_selectedDisposalType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a disposal type')),
      );
      return;
    }
    final isDisposalUser =
        ref.read(currentProfileProvider)?.isDisposal ?? false;
    if (!isDisposalUser && _restrictedTypes.contains(_selectedDisposalType)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Sold, Destroy and Government Use are handled by the Central Disposal Directorate.')),
      );
      return;
    }
    if (_selectedDisposalType == 'sold' &&
        _receiptNumberController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Receipt number is required for sold items')),
      );
      return;
    }
    if (_selectedDisposalType == 'other' &&
        _otherDetailsController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide details for Other')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(tendersServiceProvider).recordDisposal(
            tenderPackageId: widget.tenderId,
            forfeitedPackageId: widget.forfeitedPackageId,
            disposalType: _selectedDisposalType!,
            receiptNumber: _selectedDisposalType == 'sold'
                ? _receiptNumberController.text.trim()
                : null,
            otherDetails: _selectedDisposalType == 'other'
                ? _otherDetailsController.text.trim()
                : null,
          );

      ref.invalidate(tendersProvider);
      ref.invalidate(tenderDisposalsMapProvider);
      ref.invalidate(forfeitedPackagesProvider);

      if (mounted) {
        context.showSuccess('Disposal recorded successfully');
        Navigator.pop(context);
      }
    } catch (e) {
      showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final forfeited = widget.forfeited;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // The Central Disposal Directorate may record any outcome; yard admins are
    // restricted (Sold / Destroy / Govt Use are centralised).
    final isDisposalUser =
        ref.watch(currentProfileProvider)?.isDisposal ?? false;

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 400),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
        );
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 580,
          constraints: const BoxConstraints(maxHeight: 700),
          decoration: BoxDecoration(
            color: context.colors.scaffoldBg,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 40,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Dialog Header ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [context.colors.surfaceDark, context.colors.cardDark]
                        : [context.colors.customsBlue, context.colors.customsBlueDark],
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.gavel_rounded, color: context.colors.primaryGold, size: 24),
                    ).animate().slideY(begin: 0.1, duration: 400.ms).fadeIn(),
                    const Gap(16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isViewOnly ? 'DISPOSAL DETAILS' : 'RECORD DISPOSAL',
                            style: TextStyle(
                              color: context.colors.primaryGold,
                              fontSize: 11,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w800,
                            ),
                          ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 100.ms).fadeIn(),
                          if (forfeited != null)
                            Text(
                              forfeited.srNumber,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 150.ms).fadeIn(),
                        ],
                      ),
                    ),
                    const Gap(12),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.7)),
                      splashRadius: 24,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // ── Dialog Body ──
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Package Details (read-only) ──
                      if (forfeited != null) ...[
                        _SectionLabel(
                          icon: Icons.inventory_2_rounded,
                          label: 'Package Information',
                          color: context.colors.accentLightBlue,
                        ),
                        const Gap(16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: context.colors.textPrimary.withOpacity(0.02),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: context.colors.borderColor.withOpacity(0.5)),
                          ),
                          child: _InfoGrid(forfeited: forfeited),
                        ).animate().fadeIn(delay: 100.ms),
                        const Gap(24),
                      ],

                      // ── Disposal Type ──
                      _SectionLabel(
                        icon: Icons.assignment_ind_rounded,
                        label: 'Disposal Method',
                        color: context.colors.primaryGold,
                      ).animate().fadeIn(delay: 200.ms),
                      const Gap(16),
                      if (_isViewOnly)
                        _DisposalTypeBadge(
                            type: widget.existingDisposal!.disposalType)
                      else
                        Column(
                          // Central Disposal records only Sold here (a tender is
                          // a sale); yard admins keep Re-export / Release / Other.
                          children: (isDisposalUser
                                  ? _disposalTypes
                                      .where((e) => e.$1 == 'sold')
                                      .toList()
                                  : _disposalTypes)
                              .map((entry) {
                            final (value, label, icon, description) = entry;
                            final restricted = !isDisposalUser &&
                                _restrictedTypes.contains(value);
                            final isSelected =
                                !restricted && _selectedDisposalType == value;
                            final color = _disposalTypeColor(context, value);
                            return Opacity(
                              opacity: restricted ? 0.5 : 1,
                              child: Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: isSelected
                                        ? color.withOpacity(0.6)
                                        : color.withOpacity(0.2),
                                    width: isSelected ? 1.5 : 1,
                                  ),
                                ),
                                color: isSelected
                                    ? color.withOpacity(0.1)
                                    : color.withOpacity(0.04),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: restricted
                                      ? null
                                      : () => setState(
                                          () => _selectedDisposalType = value),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                    child: Row(children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: color.withOpacity(0.12),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child:
                                            Icon(icon, color: color, size: 20),
                                      ),
                                      const Gap(14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(label,
                                                style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 14,
                                                    color: color)),
                                            const Gap(2),
                                            Text(
                                                restricted
                                                    ? 'Handled by the Central Disposal Directorate'
                                                    : description,
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    fontStyle: restricted
                                                        ? FontStyle.italic
                                                        : FontStyle.normal,
                                                    color: context
                                                        .colors.textMuted)),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        restricted
                                            ? Icons.lock_outline_rounded
                                            : (isSelected
                                                ? Icons.check_circle_rounded
                                                : Icons.chevron_right_rounded),
                                        color: restricted
                                            ? context.colors.textMuted
                                            : (isSelected
                                                ? color
                                                : color.withOpacity(0.6)),
                                        size: 20,
                                      ),
                                    ]),
                                  ),
                                ),
                              ),
                            ).animate().fadeIn(delay: 250.ms).slideY(begin: 0.05);
                          }).toList(),
                        ),

                      // ── Sold → Receipt Number ──
                      if (_selectedDisposalType == 'sold' ||
                          (_isViewOnly &&
                              widget.existingDisposal?.disposalType == 'sold')) ...[
                        const Gap(20),
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                          decoration: BoxDecoration(
                            color: context.colors.textPrimary.withOpacity(0.02),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: context.colors.borderColor.withOpacity(0.5)),
                          ),
                          child: TextField(
                            controller: _receiptNumberController,
                            readOnly: _isViewOnly,
                            style:
                                TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.bold),
                            decoration: InputDecoration(
                              labelText: 'Receipt Number *',
                              labelStyle: TextStyle(color: context.colors.textMuted, fontSize: 13),
                              border: InputBorder.none,
                              prefixIcon: Icon(Icons.receipt_rounded,
                                  color: context.colors.textMuted, size: 20),
                            ),
                          ),
                        ).animate().fadeIn(delay: 300.ms),
                      ],

                      // ── Other → Details ──
                      if (_selectedDisposalType == 'other' ||
                          (_isViewOnly &&
                              widget.existingDisposal?.disposalType == 'other')) ...[
                        const Gap(20),
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                          decoration: BoxDecoration(
                            color: context.colors.textPrimary.withOpacity(0.02),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: context.colors.borderColor.withOpacity(0.5)),
                          ),
                          child: TextField(
                            controller: _otherDetailsController,
                            readOnly: _isViewOnly,
                            maxLines: 3,
                            style:
                                TextStyle(color: context.colors.textPrimary),
                            decoration: InputDecoration(
                              labelText: 'Details *',
                              labelStyle: TextStyle(color: context.colors.textMuted, fontSize: 13),
                              border: InputBorder.none,
                              alignLabelWithHint: true,
                              prefixIcon: Padding(
                                padding: const EdgeInsets.only(bottom: 42),
                                child: Icon(Icons.notes_rounded,
                                    color: context.colors.textMuted, size: 20),
                              ),
                            ),
                          ),
                        ).animate().fadeIn(delay: 300.ms),
                      ],

                      // ── View Only — disposed info ──
                      if (_isViewOnly &&
                          widget.existingDisposal != null) ...[
                        const Gap(24),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: context.colors.successGreen.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: context.colors.successGreen
                                    .withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_rounded,
                                  color: context.colors.successGreen),
                              const Gap(12),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      const TextSpan(text: 'Disposed on '),
                                      TextSpan(
                                          text: DateFormat('yyyy-MM-dd')
                                              .format(widget.existingDisposal!
                                                  .disposedAt),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                      const TextSpan(text: ' by '),
                                      TextSpan(
                                          text: widget.existingDisposal!
                                              .disposedByName,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  style: TextStyle(
                                      color: context.colors.textPrimary,
                                      fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ).animate().fadeIn(delay: 300.ms),
                      ],
                    ],
                  ),
                ),
              ),

              // ── Dialog Footer ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: context.colors.surfaceDark,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                  border: Border(top: BorderSide(color: context.colors.borderColor)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!_isViewOnly)
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          foregroundColor: context.colors.textSecondary,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        ),
                        child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    if (_isViewOnly)
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Close'),
                      )
                    else ...[
                      const Gap(12),
                      ElevatedButton.icon(
                        icon: _isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save_rounded, size: 18),
                        label: const Text('Save Disposal', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.colors.primaryGold,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _isLoading || _selectedDisposalType == null
                            ? null
                            : _handleSave,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _disposalTypeColor(BuildContext context, String type) {
    return switch (type) {
      'sold' => context.colors.successGreen,
      're_export' => context.colors.accentLightBlue,
      'release' => context.colors.heldOrange,
      'govt_use' => context.colors.primaryGold,
      'destroy' => context.colors.dangerRed,
      _ => context.colors.textSecondary,
    };
  }
}

// ── Info Grid (read-only package details) ───────────────────────

class _InfoGrid extends StatelessWidget {
  final ForfeitedPackageModel forfeited;
  const _InfoGrid({required this.forfeited});

  @override
  Widget build(BuildContext context) {
    final pkg = forfeited.packageDetails;
    final fields = <(String, String, IconData)>[
      ('SR Number', forfeited.srNumber, Icons.numbers_rounded),
      ('Consignee', forfeited.consigneeName, Icons.person_rounded),
      ('Forfeited Date',
          DateFormat('yyyy-MM-dd').format(forfeited.forfeitedAt), Icons.calendar_today_rounded),
      ('Appeal Deadline',
          DateFormat('yyyy-MM-dd').format(forfeited.appealDeadline), Icons.event_busy_rounded),
      ('Reason', forfeited.reason, Icons.gavel_rounded),
      if (pkg != null) ...[
        ('Weight', '${pkg.weightKg} kg', Icons.scale_rounded),
        ('Declared Value', 'LKR ${NumberFormat('#,##0').format(pkg.declaredValue)}', Icons.monetization_on_rounded),
        if (pkg.cusdecNo != null) ('CUSDEC No.', pkg.cusdecNo!, Icons.receipt_long_rounded),
        if (pkg.originCountry.isNotEmpty) ('Origin', pkg.originCountry, Icons.flight_takeoff_rounded),
        if (pkg.consigneeNic != null && pkg.consigneeNic!.isNotEmpty)
          ('NIC', pkg.consigneeNic!, Icons.badge_rounded),
      ],
    ];

    Widget buildCell((String, String, IconData) f) {
      final (label, value, icon) = f;
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.textPrimary.withOpacity(0.02),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.borderColor.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.colors.primaryGold.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 16, color: context.colors.primaryGold),
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: context.colors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5)),
                  const Gap(2),
                  Text(value,
                      style: TextStyle(
                          color: context.colors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Build rows of 2 columns each
    final rows = <Widget>[];
    for (int i = 0; i < fields.length; i += 2) {
      final left = fields[i];
      final right = i + 1 < fields.length ? fields[i + 1] : null;
      rows.add(
        Row(
          children: [
            Expanded(child: buildCell(left)),
            if (right != null) ...[
              const Gap(12),
              Expanded(child: buildCell(right)),
            ] else
              const Expanded(child: SizedBox()),
          ],
        ),
      );
      if (i + 2 < fields.length) rows.add(const Gap(12));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

// ── Section Label ────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _SectionLabel(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const Gap(8),
        Text(label,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 0.3)),
      ],
    );
  }
}

// ── Unsold packages → re-tender view ────────────────────────────────
// Tendered-but-unsold packages (sale window passed). Shows how many times each
// was tendered, a Details button (full tender history), and a Re-tender action
// that opens the tender form sourcing only these packages.

class UnsoldReTenderDialog extends ConsumerWidget {
  const UnsoldReTenderDialog();

  String _itemName(ForfeitedPackageModel f) {
    final items = f.packageDetails?.items ?? const [];
    if (items.isEmpty) return 'Multiple/Unspecified';
    if (items.length == 1) return items.first.itemName;
    return '${items.first.itemName} +${items.length - 1}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reTenderablePackagesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 900,
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.86),
        decoration: BoxDecoration(
          color: context.colors.scaffoldBg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [context.colors.surfaceDark, context.colors.cardDark]
                    : [
                        context.colors.customsBlue,
                        context.colors.customsBlueDark
                      ],
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.replay_rounded,
                    color: context.colors.primaryGold, size: 22),
              ),
              const Gap(14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TENDER MANAGEMENT',
                        style: TextStyle(
                            color: context.colors.primaryGold,
                            fontSize: 11,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w800)),
                    const Text('Unsold Packages — Re-tender',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              async.maybeWhen(
                data: (list) => ElevatedButton.icon(
                  icon: const Icon(Icons.gavel_rounded, size: 16),
                  label: const Text('Re-tender'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.primaryGold,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: list.isEmpty
                      ? null
                      : () => showDialog(
                            context: context,
                            builder: (_) => TenderPlacementDialog(
                              ref: ref,
                              reTender: true,
                              onTenderCreated: () {
                                ref.invalidate(reTenderablePackagesProvider);
                                ref.invalidate(tendersProvider);
                              },
                            ),
                          ),
                ),
                orElse: () => const SizedBox(),
              ),
              const Gap(8),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close_rounded,
                    color: Colors.white.withOpacity(0.7)),
              ),
            ]),
          ),
          // Body
          Flexible(
            child: async.when(
              loading: () => Center(
                  child: CircularProgressIndicator(
                      color: context.colors.primaryGold)),
              error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.refresh(reTenderablePackagesProvider)),
              data: (list) {
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(40),
                    child: EmptyTableState(
                        message:
                            'No unsold packages — everything tendered is either sold or still in an active sale window'),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: DataTable2(
                    columnSpacing: 12,
                    horizontalMargin: 12,
                    fixedTopRows: 1,
                    minWidth: 760,
                    columns: const [
                      DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
                      DataColumn2(label: Text('Goods Name'), size: ColumnSize.L),
                      DataColumn2(label: Text('Consignee'), size: ColumnSize.M),
                      DataColumn2(
                          label: Center(child: Text('Times Tendered')),
                          size: ColumnSize.S,
                          fixedWidth: 130),
                      DataColumn2(
                          label: Center(child: Text('Tenders')),
                          size: ColumnSize.S,
                          fixedWidth: 90),
                    ],
                    rows: list.map((info) {
                      final f = info.forfeited;
                      return DataRow(cells: [
                        DataCell(TooltipText(f.srNumber,
                            style: TextStyle(
                                color: context.colors.accentLightBlue,
                                fontWeight: FontWeight.w600))),
                        DataCell(TooltipText(_itemName(f),
                            overflow: TextOverflow.ellipsis)),
                        DataCell(TooltipText(f.consigneeName,
                            overflow: TextOverflow.ellipsis)),
                        DataCell(Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color:
                                  context.colors.warningAmber.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: context.colors.warningAmber
                                      .withOpacity(0.4)),
                            ),
                            child: Text('${info.tenderCount}×',
                                style: TextStyle(
                                    color: context.colors.warningAmber,
                                    fontWeight: FontWeight.w800)),
                          ),
                        )),
                        DataCell(Center(
                          child: IconButton(
                            tooltip: 'Tender history',
                            icon: Icon(Icons.history_rounded,
                                color: context.colors.accentLightBlue,
                                size: 20),
                            onPressed: () => showDialog(
                              context: context,
                              builder: (_) => TenderHistoryDialog(info: info),
                            ),
                          ),
                        )),
                      ]);
                    }).toList(),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

class TenderHistoryDialog extends StatelessWidget {
  final ReTenderInfo info;
  const TenderHistoryDialog({required this.info});

  @override
  Widget build(BuildContext context) {
    final tenders = info.tenders;
    return Dialog(
      backgroundColor: context.colors.scaffoldBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        width: 540,
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.history_rounded, color: context.colors.primaryGold),
              const Gap(10),
              Expanded(
                child: Text('Tender History — ${info.forfeited.srNumber}',
                    style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
              ),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded)),
            ]),
            const Gap(4),
            Text('Tendered ${info.tenderCount} time(s)',
                style: TextStyle(color: context.colors.textSecondary)),
            const Gap(12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: tenders.length,
                separatorBuilder: (_, __) => const Gap(10),
                itemBuilder: (context, i) {
                  final t = tenders[i];
                  final isLatest = i == 0;
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.colors.cardDark,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: isLatest
                              ? context.colors.primaryGold.withOpacity(0.5)
                              : context.colors.borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.gavel_rounded,
                              size: 16, color: context.colors.primaryGold),
                          const Gap(8),
                          Text(t.tenderNumber,
                              style: TextStyle(
                                  color: context.colors.textPrimary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15)),
                          if (isLatest) ...[
                            const Gap(8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: context.colors.primaryGold
                                    .withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('Latest',
                                  style: TextStyle(
                                      color: context.colors.primaryGold,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ]),
                        const Gap(8),
                        _kv(context, 'Tender Date',
                            DateFormat('yyyy-MM-dd').format(t.tenderDate)),
                        _kv(
                            context,
                            'Sale Date',
                            t.saleDate != null
                                ? DateFormat('yyyy-MM-dd').format(t.saleDate!)
                                : '—'),
                        _kv(context, 'Sale Start Time', t.saleTime ?? '—'),
                        if (t.createdByName != null)
                          _kv(context, 'Created By', t.createdByName!),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(
          width: 130,
          child: Text(k,
              style: TextStyle(
                  color: context.colors.textMuted, fontSize: 12)),
        ),
        Expanded(
          child: Text(v,
              style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}
