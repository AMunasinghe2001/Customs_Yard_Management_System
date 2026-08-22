import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../core/yards.dart';
import '../../models/models.dart';
import '../../widgets/error_view.dart';
import '../../widgets/empty_table_state.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/package_details_dialog.dart';
import '../../widgets/disposal_profile_dialog.dart';
import '../../widgets/styled_form_dialog.dart';
import '../../widgets/styled_dropdown.dart';
import '../../widgets/tooltip_text.dart';

/// The quantity actually forfeited & sent for disposal for a valuation row.
/// Prefers the stored [entryQty]; otherwise derives it from the item's forfeit
/// warehouse entries ([FORFEIT]/[CONFISCATED]) — so a partial forfeit (e.g. 6
/// of 10) is valued on 6, not the full item quantity. Returns null if it can't
/// be determined (caller then falls back to the full quantity).
int? _forfeitedQtyFor(DisposalRequestItemModel it, PackageItem? pkgItem) {
  if (it.forfeited?.entryQty != null) return it.forfeited!.entryQty;
  final pkg = it.forfeited?.packageDetails;
  final targetId = pkgItem?.id ?? it.forfeited?.itemId;
  if (pkg == null || targetId == null) return null;
  final q = pkg.warehouseEntries.where((e) {
    if (!e.isReturned || e.packageItemId != targetId) return false;
    final n = (e.returnNotes ?? '').trim().toUpperCase();
    return n.startsWith('[FORFEIT') || n.startsWith('[CONFISCATED');
  }).fold<int>(0, (s, e) => s + e.itemCount);
  return q > 0 ? q : null;
}

/// Valuation Directorate (DC / SDDC) portal. Standalone scaffold (not AppShell).
/// Lists every yard's disposal requests that are still awaiting valuation; the
/// directorate sets a cost per package item and forwards the request to the
/// Central Disposal Directorate.
class ValuationDashboardScreen extends ConsumerStatefulWidget {
  const ValuationDashboardScreen({super.key});

  @override
  ConsumerState<ValuationDashboardScreen> createState() =>
      _ValuationDashboardScreenState();
}

class _ValuationDashboardScreenState
    extends ConsumerState<ValuationDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gold = context.colors.primaryGold;
    final profile = ref.watch(currentProfileProvider);
    final requests = ref.watch(valuationRequestsProvider);

    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top bar ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [gold.withOpacity(0.08), context.colors.cardDark],
              ),
              border:
                  Border(bottom: BorderSide(color: context.colors.borderColor)),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: gold.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: gold.withOpacity(0.3)),
                ),
                // Flat gold tint (colorFilter, not currentColor) so at this tiny
                // 30px size the inner ship/plane detail doesn't render as an ugly
                // navy blob — the fine detail isn't legible here anyway.
                child: SvgPicture.asset('Sri_Lanka_Customs_logo_tinted.svg',
                    width: 30,
                    height: 30,
                    colorFilter: ColorFilter.mode(gold, BlendMode.srcIn)),
              ),
              const Gap(14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Valuation Directorate',
                      style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                  Text(
                      'Value disposal requests across all yards · before Central Disposal',
                      style: TextStyle(
                          color: context.colors.textMuted, fontSize: 12)),
                ],
              ),
              const Spacer(),
              if (profile != null)
                Tooltip(
                  message: 'View profile',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => DisposalProfileDialog(accent: gold),
                    ),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: gold.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: gold.withOpacity(0.35)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.verified_user_rounded, color: gold, size: 16),
                        const Gap(8),
                        Text(profile.fullName,
                            style: TextStyle(
                                color: gold,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        if (profile.isPasswordExpiringSoon ||
                            profile.isPasswordExpired) ...[
                          const Gap(8),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: profile.isPasswordExpired
                                  ? context.colors.dangerRed
                                  : context.colors.warningAmber,
                            ),
                          ),
                        ],
                        const Gap(4),
                        Icon(Icons.chevron_right_rounded,
                            color: gold.withOpacity(0.7), size: 16),
                      ]),
                    ),
                  ),
                ),
              const Gap(8),
              IconButton(
                tooltip: 'Toggle theme',
                icon: Icon(
                    ref.watch(themeModeProvider) == ThemeMode.dark
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                    color: context.colors.textPrimary),
                onPressed: () {
                  final isDark = ref.read(themeModeProvider) == ThemeMode.dark;
                  ref.read(themeModeProvider.notifier).state =
                      isDark ? ThemeMode.light : ThemeMode.dark;
                },
              ),
              const Gap(4),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.colors.dangerRed,
                  side: BorderSide(
                      color: context.colors.dangerRed.withOpacity(0.5)),
                ),
                icon: const Icon(Icons.logout_rounded, size: 16),
                label: const Text('Sign Out'),
                onPressed: () async {
                  await ref.read(authServiceProvider).signOut();
                  ref.read(currentProfileProvider.notifier).state = null;
                  if (context.mounted) context.go('/');
                },
              ),
            ]),
          ).animate().fadeIn(duration: 350.ms).slideY(begin: -0.15),

          // ── Tab bar ──────────────────────────────────────────
          Container(
            color: context.colors.cardDark,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
            child: Container(
              decoration: BoxDecoration(
                color: context.colors.surfaceDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.colors.borderColor),
              ),
              child: TabBar(
                controller: _tabController,
                splashFactory: NoSplash.splashFactory,
                overlayColor: WidgetStateProperty.all(Colors.transparent),
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorPadding: const EdgeInsets.all(4),
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: gold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: gold.withOpacity(0.5)),
                ),
                labelColor: gold,
                unselectedLabelColor: context.colors.textMuted,
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                tabs: const [
                  Tab(
                    height: 44,
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.calculate_rounded, size: 18),
                          Gap(8),
                          Text('Pending Valuation'),
                        ]),
                  ),
                  Tab(
                    height: 44,
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.sell_rounded, size: 18),
                          Gap(8),
                          Text('Unsold Tenders · Bids'),
                        ]),
                  ),
                ],
              ),
            ),
          ),

          // ── Tab views ────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: existing pending-valuation list.
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text('Pending Valuation',
                            style: TextStyle(
                                color: context.colors.textPrimary,
                                fontSize: 22,
                                fontWeight: FontWeight.w700)),
                        const Gap(12),
                        requests.maybeWhen(
                          data: (list) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: gold.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: gold.withOpacity(0.3)),
                            ),
                            child: Text('${list.length} request(s)',
                                style: TextStyle(
                                    color: gold,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12)),
                          ),
                          orElse: () => const SizedBox(),
                        ),
                      ]).animate().fadeIn(duration: 300.ms),
                      const Gap(16),
                      Expanded(
                        child: requests.when(
                          skipLoadingOnReload: true,
                          loading: () => Center(
                              child: CircularProgressIndicator(color: gold)),
                          error: (e, _) => ErrorView(
                              error: e,
                              onRetry: () =>
                                  ref.refresh(valuationRequestsProvider)),
                          data: (list) {
                            if (list.isEmpty) {
                              return SizedBox(
                                width: double.infinity,
                                child: EmptyStateCard(
                                    icon: Icons.calculate_outlined,
                                    message: 'Nothing awaiting valuation',
                                    subtitle:
                                        'Monitoring all ${kYards.length} yards — new disposal requests will appear here for costing.'),
                              );
                            }
                            return ListView.separated(
                              itemCount: list.length,
                              separatorBuilder: (_, __) => const Gap(16),
                              itemBuilder: (context, i) =>
                                  _ValuationRequestCard(request: list[i]),
                            )
                                .animate()
                                .fadeIn(duration: 350.ms)
                                .slideY(begin: 0.05);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                // Tab 2: unsold tenders — view bids + set re-valuation.
                const _UnsoldTendersValTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ValuationRequestCard extends ConsumerWidget {
  final DisposalRequestModel request;
  const _ValuationRequestCard({required this.request});

  String _itemName(DisposalRequestItemModel it) {
    final items = it.forfeited?.packageDetails?.items ?? const [];
    if (items.isEmpty) return 'Multiple/Unspecified';
    final itemId = it.forfeited?.itemId;
    if (itemId != null) {
      final match = items.where((i) => i.id == itemId).firstOrNull;
      if (match != null) return match.itemName;
    }
    if (items.length == 1) return items.first.itemName;
    return '${items.first.itemName} +${items.length - 1}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gold = context.colors.primaryGold;
    final storageRate = ref.watch(storageRateProvider).valueOrNull ??
        {DateTime(2020, 1, 1): 50.0};
    final items = request.items;
    // Items handled by a per-item (itemId-specific) request row — keyed by
    // "<packageId>:<itemId>". When the same item also appears inside a
    // package-level (itemId==null) row, the package-level row must NOT expand
    // that item again, or its full registered qty (e.g. 200) duplicates the
    // partial-qty per-item rows (e.g. 3+2+5+2) the yard actually requested.
    final perItemKeys = <String>{};
    for (final it in items) {
      final iid = it.forfeited?.itemId;
      final pid = it.forfeited?.packageId;
      if (iid != null && pid != null) perItemKeys.add('$pid:$iid');
    }
    // Expand package-level FP rows (itemId==null, multiple pkg items) so each
    // item appears as its own table row — same as the Set Valuation form.
    final expandedRows = <({DisposalRequestItemModel it, PackageItem? pkgItem})>[];
    for (final it in items) {
      final fpItems = it.forfeited?.packageDetails?.items ?? const [];
      final pid = it.forfeited?.packageId;
      if (it.forfeited?.itemId == null && fpItems.length > 1) {
        for (final pkgItem in fpItems) {
          // Skip items already covered by a dedicated per-item request row —
          // those carry the correct partial quantity; the package-level row
          // would otherwise re-add them at the full registered quantity.
          if (pid != null && perItemKeys.contains('$pid:${pkgItem.id}')) {
            continue;
          }
          expandedRows.add((it: it, pkgItem: pkgItem));
        }
      } else {
        expandedRows.add((it: it, pkgItem: null));
      }
    }
    final valuedCount =
        items.where((i) => i.valuationCost != null).length;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: gold.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: gold.withOpacity(0.35)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.warehouse_rounded, size: 16, color: gold),
                  const Gap(8),
                  Text(yardName(request.yard),
                      style: TextStyle(
                          color: gold,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                ]),
              ),
              const Gap(14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.calendar_today_rounded,
                          size: 12, color: context.colors.textMuted),
                      const Gap(4),
                      Text(
                          DateFormat('yyyy-MM-dd').format(request.requestDate),
                          style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      if (request.createdByName != null) ...[
                        const Gap(12),
                        Icon(Icons.person_rounded,
                            size: 12, color: context.colors.textMuted),
                        const Gap(4),
                        Text(request.createdByName!,
                            style: TextStyle(
                                color: context.colors.textMuted, fontSize: 12)),
                      ],
                    ]),
                    const Gap(2),
                    Text(
                        '$valuedCount of ${expandedRows.length} item(s) valued',
                        style: TextStyle(
                            color: context.colors.textMuted, fontSize: 11)),
                  ],
                ),
              ),
              // Forward every item at once (all must be valued first).
              _ForwardAllButton(request: request, expandedCount: expandedRows.length),
            ]),
          ),
          Divider(height: 1, color: context.colors.borderColor),
          // Items table
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              height: (expandedRows.length * 48.0 + 52).clamp(100, 320),
              decoration: BoxDecoration(
                border: Border.all(color: context.colors.borderColor),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: DataTable2(
                  columnSpacing: 12,
                  horizontalMargin: 14,
                  fixedTopRows: 1,
                  empty: const EmptyTableState(
                      message: 'No packages in this request'),
                  columns: const [
                    DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
                    DataColumn2(label: Text('Goods Name'), size: ColumnSize.M),
                    DataColumn2(label: Text('Consignee'), size: ColumnSize.M),
                    DataColumn2(
                        label: Text('HS Code'),
                        size: ColumnSize.S,
                        fixedWidth: 110),
                    DataColumn2(
                        label: Text('Qty'),
                        size: ColumnSize.S,
                        fixedWidth: 64,
                        numeric: true),
                    DataColumn2(
                        label: Center(child: Text('Value')),
                        size: ColumnSize.S,
                        fixedWidth: 130),
                    DataColumn2(
                        label: Center(child: Text('Disposition')),
                        size: ColumnSize.S,
                        fixedWidth: 130),
                    DataColumn2(
                        label: Text('Valuation'),
                        size: ColumnSize.S,
                        fixedWidth: 150),
                    DataColumn2(
                        label: Center(child: Text('Action')),
                        size: ColumnSize.S,
                        fixedWidth: 96),
                    DataColumn2(
                        label: Center(child: Text('Details')),
                        size: ColumnSize.S,
                        fixedWidth: 70),
                  ],
                  rows: expandedRows.map((row) {
                    final it = row.it;
                    final pkgItem = row.pkgItem;
                    final f = it.forfeited;
                    final displayName = pkgItem?.itemName ?? _itemName(it);
                    final displayHs = pkgItem?.hsCode ?? it.hsCodeLabel;
                    // Value only the quantity actually forfeited & sent for
                    // disposal (e.g. 6 of 10) — not the full item qty.
                    final forfeitQty = _forfeitedQtyFor(it, pkgItem);
                    final displayQty = forfeitQty ??
                        (pkgItem != null ? pkgItem.quantity : it.totalQuantity);
                    // Carton packaging only makes sense for the whole item, not
                    // a partial-forfeit quantity.
                    final showPackaging =
                        forfeitQty == null && pkgItem?.packagingLabel != null;
                    final highlightId = pkgItem?.id ?? f?.itemId ??
                        (f?.packageDetails?.items.isNotEmpty == true
                            ? f!.packageDetails!.items.first.id
                            : null);
                    return DataRow(cells: [
                      DataCell(TooltipText(f?.srNumber ?? '—',
                          style: TextStyle(
                              color: context.colors.accentLightBlue,
                              fontWeight: FontWeight.w600))),
                      DataCell(TooltipText(displayName,
                          overflow: TextOverflow.ellipsis)),
                      DataCell(TooltipText(f?.consigneeName ?? '—',
                          overflow: TextOverflow.ellipsis)),
                      DataCell(TooltipText(displayHs ?? '—',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 12))),
                      DataCell(TooltipText(
                          showPackaging
                              ? '$displayQty (in ${pkgItem!.packagingLabel})'
                              : '$displayQty',
                          style: TextStyle(
                              color: context.colors.textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 12))),
                      DataCell(Center(child: Builder(builder: (_) {
                        // SR-form declared value (unit value × qty) — reference
                        // figure, distinct from the valuation cost set below.
                        final srUnit = pkgItem?.unitValue ?? 0;
                        final srTotal = srUnit * displayQty;
                        return Text(
                            'LKR ${NumberFormat('#,##0').format(srTotal)}',
                            style: TextStyle(
                                color: context.colors.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 12));
                      }))),
                      DataCell(_DispoChip(disposition: it.disposition)),
                      DataCell(it.valuationCost != null
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                    'LKR ${NumberFormat('#,##0').format((it.unitCost ?? 0) * displayQty)}',
                                    style: TextStyle(
                                        color: gold,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12)),
                                Text(
                                    '@ ${NumberFormat('#,##0').format(it.unitCost)} × $displayQty',
                                    style: TextStyle(
                                        color: context.colors.textMuted,
                                        fontSize: 10)),
                              ],
                            )
                          : Text('Not set',
                              style: TextStyle(
                                  color: context.colors.textMuted,
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic))),
                      DataCell(Center(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: gold,
                            side: BorderSide(color: gold.withOpacity(0.5)),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 10),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) => _ItemValuationDialog(
                              item: it,
                              pkgItem: pkgItem,
                              qty: displayQty,
                              itemName: displayName,
                            ),
                          ),
                          child: Text(
                              it.valuationCost == null ? 'Value' : 'Edit',
                              style: const TextStyle(fontSize: 12)),
                        ),
                      )),
                      DataCell(Center(
                        child: IconButton(
                          icon: Icon(Icons.info_outline_rounded,
                              color: context.colors.accentLightBlue, size: 18),
                          onPressed: f?.packageDetails == null
                              ? null
                              : () => showDialog(
                                    context: context,
                                    builder: (_) => PackageDetailsDialog(
                                      package: f!.packageDetails!,
                                      storageRate: storageRate,
                                      headerAccentColor: context.colors.primaryGold,
                                      useLegacySummary: true,
                                      highlightItemId: highlightId,
                                      yardLabel: yardName(
                                          f.yard ?? request.yard),
                                      valuationUnitCost: it.unitCost,
                                      valuationTotalCost: it.totalCost,
                                      valuationQty: displayQty,
                                    ),
                                  ),
                        ),
                      )),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Header button that forwards EVERY (valued) item of a request at once.
class _ForwardAllButton extends ConsumerStatefulWidget {
  final DisposalRequestModel request;
  final int expandedCount;
  const _ForwardAllButton(
      {required this.request, required this.expandedCount});
  @override
  ConsumerState<_ForwardAllButton> createState() => _ForwardAllButtonState();
}

class _ForwardAllButtonState extends ConsumerState<_ForwardAllButton> {
  bool _busy = false;

  Future<void> _forwardAll() async {
    final allValued =
        widget.request.items.every((i) => i.valuationCost != null);
    if (!allValued) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Every item must have a cost before forwarding.'),
          backgroundColor: context.colors.dangerRed));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(valuationServiceProvider)
          .forwardAllValuationItems(widget.request.id);
      ref.read(disposalRequestsRefreshProvider.notifier).trigger();
      ref.invalidate(valuationRequestsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('All items forwarded to Central Disposal.'),
            backgroundColor: context.colors.successGreen));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: context.colors.dangerRed));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final gold = context.colors.primaryGold;
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: gold,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      icon: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.send_rounded, size: 18),
      label: const Text('Forward All'),
      onPressed: _busy ? null : _forwardAll,
    );
  }
}

/// Per-item valuation popup: set/edit this item's cost, then Save or
/// Save & Forward (forwards just this item to Central Disposal).
class _ItemValuationDialog extends ConsumerStatefulWidget {
  final DisposalRequestItemModel item;
  final PackageItem? pkgItem;
  final int qty;
  final String itemName;
  const _ItemValuationDialog({
    required this.item,
    required this.pkgItem,
    required this.qty,
    required this.itemName,
  });
  @override
  ConsumerState<_ItemValuationDialog> createState() =>
      _ItemValuationDialogState();
}

class _ItemValuationDialogState extends ConsumerState<_ItemValuationDialog> {
  late final TextEditingController _costCtrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _costCtrl = TextEditingController(
        text: widget.item.valuationCost != null
            ? widget.item.valuationCost!.toStringAsFixed(0)
            : '');
    _costCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _costCtrl.dispose();
    super.dispose();
  }

  double? get _cost {
    final v = double.tryParse(_costCtrl.text.trim());
    return (v != null && v > 0) ? v : null;
  }

  Future<void> _save({required bool forward}) async {
    final cost = _cost;
    if (cost == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Enter a valid cost.'),
          backgroundColor: context.colors.dangerRed));
      return;
    }
    setState(() => _busy = true);
    try {
      final svc = ref.read(valuationServiceProvider);
      await svc.setValuationItemCost(widget.item.id, cost);
      if (forward) await svc.forwardValuationItem(widget.item.id);
      ref.read(disposalRequestsRefreshProvider.notifier).trigger();
      ref.invalidate(valuationRequestsProvider);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(forward
              ? 'Item valued & forwarded to Central Disposal.'
              : 'Valuation saved.'),
          backgroundColor: context.colors.successGreen));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: context.colors.dangerRed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final gold = context.colors.primaryGold;
    final srUnit = widget.pkgItem?.unitValue ?? 0;
    final srTotal = srUnit * widget.qty;
    return StyledFormDialog(
      label: 'Set Valuation',
      title: widget.item.forfeited?.srNumber ?? widget.itemName,
      icon: Icons.calculate_rounded,
      headerAccentColor: gold,
      width: 460,
      child: StyledFormSection(
        title: 'Valuation',
        icon: Icons.price_change_rounded,
        children: [
          Text(widget.itemName,
              style: TextStyle(
                  color: context.colors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14)),
          const Gap(6),
          Row(children: [
            Icon(Icons.inventory_2_rounded,
                size: 13, color: context.colors.textMuted),
            const Gap(4),
            Text('Qty ${widget.qty}',
                style: TextStyle(
                    color: context.colors.textMuted, fontSize: 12)),
            const Gap(12),
            Icon(Icons.sell_rounded,
                size: 13, color: context.colors.textMuted),
            const Gap(4),
            Text('SR value LKR ${NumberFormat('#,##0').format(srTotal)}',
                style: TextStyle(
                    color: context.colors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12)),
            if (widget.item.forwarded) ...[
              const Gap(12),
              Icon(Icons.check_circle_rounded,
                  size: 13, color: context.colors.successGreen),
              const Gap(4),
              Text('Forwarded',
                  style: TextStyle(
                      color: context.colors.successGreen,
                      fontWeight: FontWeight.w700,
                      fontSize: 12)),
            ],
          ]),
          const Gap(14),
          // Full-width cost field; the live total sits on its own line below so
          // a large total never squeezes / overflows the input.
          TextField(
            controller: _costCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Cost / item (LKR)',
              isDense: true,
              prefixText: 'LKR ',
            ),
          ),
          const Gap(8),
          Align(
            alignment: Alignment.centerRight,
            child: _LiveTotal(qty: widget.qty, controller: _costCtrl),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(
          onPressed: _busy ? null : () => _save(forward: false),
          child: const Text('Save'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: gold),
          onPressed: _busy ? null : () => _save(forward: true),
          icon: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send_rounded, size: 16),
          label: const Text('Save & Forward'),
        ),
      ],
    );
  }
}


/// The live "× qty = total" line under a cost field in the Set Valuation
/// dialog. The dialog rebuilds on every keystroke, so reading the controller
/// here is enough to keep it current.
class _LiveTotal extends StatelessWidget {
  final int qty;
  final TextEditingController controller;
  const _LiveTotal({required this.qty, required this.controller});

  @override
  Widget build(BuildContext context) {
    final unit = double.tryParse(controller.text.trim());
    if (unit == null || unit < 0) {
      return Text('× $qty',
          style: TextStyle(color: context.colors.textMuted, fontSize: 11));
    }
    final total = unit * qty;
    return Text(
        '× $qty = LKR ${NumberFormat('#,##0').format(total)}',
        softWrap: true,
        textAlign: TextAlign.right,
        style: TextStyle(
            color: context.colors.primaryGold,
            fontWeight: FontWeight.w700,
            fontSize: 11));
  }
}

class _DispoChip extends StatelessWidget {
  final String disposition;
  const _DispoChip({required this.disposition});
  @override
  Widget build(BuildContext context) {
    final isSale = disposition == 'sale';
    final color =
        isSale ? context.colors.successGreen : context.colors.dangerRed;
    final icon = isSale ? Icons.sell_rounded : Icons.delete_forever_rounded;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const Gap(5),
        Text(dispositionLabel(disposition),
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

// ── Unsold Tenders (Valuation view: bids + re-valuation) ─────────────────────
final _valUnsoldSearchProvider = StateProvider<String>((ref) => '');
final _valUnsoldYardProvider = StateProvider<String?>((ref) => null); // null=all

/// Which rows the Unsold Tenders table shows:
///   null  = all
///   false = still PENDING this round's valuation (the work queue)
///   true  = already VALUED and sent on to Central Disposal
final _valUnsoldStatusProvider = StateProvider<bool?>((ref) => null);

/// Search field styled exactly like the Central Disposal Unsold page.
class _ValSearchField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _ValSearchField({required this.value, required this.onChanged});
  @override
  State<_ValSearchField> createState() => _ValSearchFieldState();
}

class _ValSearchFieldState extends State<_ValSearchField> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gold = context.colors.primaryGold;
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: w));
    return SizedBox(
      width: 300,
      child: TextField(
        controller: _c,
        style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600),
        onChanged: (v) {
          widget.onChanged(v);
          setState(() {});
        },
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search SR / item / consignee…',
          hintStyle:
              TextStyle(color: context.colors.textSecondary, fontSize: 13),
          prefixIcon: Icon(Icons.search_rounded, size: 20, color: gold),
          suffixIcon: _c.text.isEmpty
              ? null
              : IconButton(
                  splashRadius: 16,
                  icon: Icon(Icons.close_rounded,
                      size: 16, color: context.colors.textMuted),
                  onPressed: () {
                    _c.clear();
                    widget.onChanged('');
                    setState(() {});
                  },
                ),
          filled: true,
          fillColor: gold.withOpacity(0.06),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: border(gold.withOpacity(0.4)),
          enabledBorder: border(gold.withOpacity(0.4)),
          focusedBorder: border(gold, 1.5),
        ),
      ),
    );
  }
}

/// Yard dropdown with an "All Yards" option — same styled menu as Central
/// Disposal's Unsold page (StyledDropdownFormField).
class _ValYardFilter extends StatelessWidget {
  final String? value; // null = all
  final ValueChanged<String?> onChanged;
  const _ValYardFilter({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final gold = context.colors.primaryGold;
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: w));
    return SizedBox(
      width: 220,
      child: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme:
              Theme.of(context).inputDecorationTheme.copyWith(
                    filled: true,
                    fillColor: gold.withOpacity(0.06),
                    border: border(gold.withOpacity(0.4)),
                    enabledBorder: border(gold.withOpacity(0.4)),
                    focusedBorder: border(gold, 1.5),
                  ),
        ),
        child: StyledDropdownFormField<String>(
          value: value ?? '_all',
          label: 'Yard',
          helperText: null,
          isDense: true,
          menuWidth: 220,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          prefixIcon:
              Icon(Icons.warehouse_rounded, color: gold, size: 20),
          options: [
            const StyledDropdownOption('_all', 'All Yards'),
            for (final y in kYards) StyledDropdownOption(y.code, y.name),
          ],
          onChanged: (v) => onChanged((v == null || v == '_all') ? null : v),
        ),
      ),
    );
  }
}

String _valItemName(ForfeitedPackageModel f) {
  if (f.itemName != null) return f.itemName!;
  final items = f.packageDetails?.items ?? const [];
  if (items.isEmpty) return 'Multiple/Unspecified';
  // Forfeiture is recorded PER ITEM, so a multi-item package produces one row
  // per item. Resolve THIS row's own item from item_id — falling straight
  // through to items.first labelled every row of the package with the first
  // item's name (e.g. three "Wash Basins +2" rows).
  if (f.itemId != null) {
    final match = items.where((i) => i.id == f.itemId).firstOrNull;
    if (match != null) return match.itemName;
  }
  if (items.length == 1) return items.first.itemName;
  return '${items.first.itemName} +${items.length - 1}';
}

/// Cross-yard unsold tender packages, so the Valuation Directorate can review
/// the recorded bids and set a fresh re-valuation for the current tender round.
class _UnsoldTendersValTab extends ConsumerWidget {
  const _UnsoldTendersValTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gold = context.colors.primaryGold;
    final async = ref.watch(unsoldTenderSalesProvider);
    final q = ref.watch(_valUnsoldSearchProvider).toLowerCase();
    final yardFilter = ref.watch(_valUnsoldYardProvider);
    final statusFilter = ref.watch(_valUnsoldStatusProvider);
    final valued =
        ref.watch(valuedCurrentRoundProvider).valueOrNull ?? const <String>{};
    final storageRate = ref.watch(storageRateProvider).valueOrNull ??
        {DateTime(2020, 1, 1): 50.0};
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Unsold Tenders',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const Gap(10),
            Text('Review bids · set a new valuation for re-tender',
                style: TextStyle(
                    color: context.colors.textMuted, fontSize: 13)),
            const Spacer(),
            // Search — same style as the Central Disposal Unsold page.
            _ValSearchField(
              value: q,
              onChanged: (v) =>
                  ref.read(_valUnsoldSearchProvider.notifier).state = v,
            ),
            const Gap(12),
            // Yard filter — same styled dropdown as Central Disposal.
            _ValYardFilter(
              value: yardFilter,
              onChanged: (v) =>
                  ref.read(_valUnsoldYardProvider.notifier).state = v,
            ),
          ]).animate().fadeIn(duration: 300.ms),
          const Gap(12),
          // Pending vs Valued — lets the officer see just their work queue,
          // or just what has already gone to Central Disposal.
          Row(children: [
            _ValStatusFilter(
              value: statusFilter,
              onChanged: (v) =>
                  ref.read(_valUnsoldStatusProvider.notifier).state = v,
            ),
            const Spacer(),
            // How much work is actually waiting on this directorate.
            Builder(builder: (context) {
              // Same exclusion as the table: High Panel packages are not this
              // directorate's work, so they must not inflate the count.
              final all = (async.valueOrNull ?? const <ReTenderSaleInfo>[])
                  .where((i) => i.tenderCount <= kMaxBidTenderRounds)
                  .toList();
              final pending = all
                  .where((i) => !valued.contains(i.forfeited.id))
                  .length;
              if (all.isEmpty) return const SizedBox.shrink();
              return Text(
                  '$pending of ${all.length} awaiting valuation',
                  style: TextStyle(
                      color: context.colors.textMuted, fontSize: 12));
            }),
          ]),
          const Gap(14),
          Expanded(
            child: async.when(
              skipLoadingOnReload: true,
              loading: () => Center(child: CircularProgressIndicator(color: gold)),
              error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.refresh(unsoldTenderSalesProvider)),
              data: (list) {
                // Packages past Tender 3 belong to the High Panel: a committee
                // prices them and the ADG submits it, so the Valuation
                // Directorate has no work left on them. Drop them entirely
                // rather than showing rows this officer cannot act on.
                var rows = list
                    .where((info) => info.tenderCount <= kMaxBidTenderRounds)
                    .toList();
                if (yardFilter != null) {
                  rows = rows
                      .where((info) => info.forfeited.yard == yardFilter)
                      .toList();
                }
                if (q.isNotEmpty) {
                  rows = rows.where((info) {
                    final f = info.forfeited;
                    return f.srNumber.toLowerCase().contains(q) ||
                        f.consigneeName.toLowerCase().contains(q) ||
                        _valItemName(f).toLowerCase().contains(q);
                  }).toList();
                }
                // Pending vs Valued for THIS round.
                if (statusFilter != null) {
                  rows = rows
                      .where((info) =>
                          valued.contains(info.forfeited.id) == statusFilter)
                      .toList();
                }
                return Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: context.colors.cardDark,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.colors.borderColor),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: DataTable2(
                      columnSpacing: 12,
                      horizontalMargin: 16,
                      fixedTopRows: 1,
                      minWidth: 1070,
                      showCheckboxColumn: false,
                      empty: const EmptyTableState(
                          message: 'No unsold tender packages'),
                      headingRowColor:
                          WidgetStateProperty.all(context.colors.surfaceDark),
                      columns: const [
                        DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
                        DataColumn2(label: Text('Goods Name'), size: ColumnSize.M),
                        DataColumn2(
                            label: Text('Consignee'), size: ColumnSize.M),
                        DataColumn2(
                            label: Text('Yard'),
                            size: ColumnSize.S,
                            fixedWidth: 110),
                        DataColumn2(
                            label: Center(child: Text('Times')),
                            size: ColumnSize.S,
                            fixedWidth: 70),
                        DataColumn2(
                            label: Center(child: Text('Bids')),
                            size: ColumnSize.S,
                            fixedWidth: 70),
                        DataColumn2(
                            label: Center(child: Text('Re-valuation')),
                            size: ColumnSize.S,
                            fixedWidth: 150),
                        DataColumn2(
                            label: Center(child: Text('Details')),
                            size: ColumnSize.S,
                            fixedWidth: 70),
                      ],
                      rows: rows.map((info) {
                        final f = info.forfeited;
                        return DataRow(
                          cells: [
                            DataCell(TooltipText(f.srNumber,
                                style: TextStyle(
                                    color: gold,
                                    fontWeight: FontWeight.w600))),
                            DataCell(TooltipText(_valItemName(f),
                                overflow: TextOverflow.ellipsis)),
                            DataCell(TooltipText(f.consigneeName,
                                overflow: TextOverflow.ellipsis)),
                            DataCell(TooltipText(yardName(f.yard),
                                overflow: TextOverflow.ellipsis)),
                            DataCell(Center(
                                child: _ValAttemptsBadge(info: info))),
                            DataCell(Center(
                                child: _ValBidCountChip(fpId: f.id))),
                            DataCell(Center(
                              child: _ValRevalCell(
                                  info: info,
                                  valued: valued.contains(f.id)),
                            )),
                            DataCell(Center(
                              child: IconButton(
                                icon: Icon(Icons.info_outline_rounded,
                                    color: context.colors.accentLightBlue,
                                    size: 18),
                                onPressed: f.packageDetails == null
                                    ? null
                                    : () => showDialog(
                                          context: context,
                                          builder: (_) => PackageDetailsDialog(
                                            package: f.packageDetails!,
                                            storageRate: storageRate,
                                            headerAccentColor:
                                                context.colors.primaryGold,
                                            useLegacySummary: true,
                                            highlightItemId: f.itemId,
                                            yardLabel: yardName(f.yard),
                                            valuationUnitCost: f.valuationCost,
                                            valuationTotalCost:
                                                f.valuationCost != null
                                                    ? f.valuationCost! *
                                                        (f.entryQty ?? 1)
                                                    : null,
                                          ),
                                        ),
                              ),
                            )),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Small chip showing the total recorded bid count for a package.
class _ValBidCountChip extends ConsumerWidget {
  final String fpId;
  const _ValBidCountChip({required this.fpId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gold = context.colors.primaryGold;
    // valueOrNull, NOT asData?.value: while the provider re-fetches, asData is
    // null and the count collapses to 0 before snapping back — which is what
    // made the table look like it was constantly refreshing. valueOrNull keeps
    // the previous value during a reload.
    final count = ref
            .watch(tenderBidsProvider(fpId))
            .valueOrNull
            ?.values
            .fold<int>(0, (s, l) => s + l.length) ??
        0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: gold.withOpacity(count > 0 ? 0.14 : 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$count',
          style: TextStyle(
              color: count > 0 ? gold : context.colors.textMuted,
              fontWeight: FontWeight.w800)),
    );
  }
}

/// Combined popup: shows the bids per tender round (read-only) and lets the
/// Valuation Directorate set a NEW valuation for the CURRENT round.
class _ValBidsAndRevalDialog extends ConsumerStatefulWidget {
  final ReTenderSaleInfo info;
  const _ValBidsAndRevalDialog({required this.info});

  @override
  ConsumerState<_ValBidsAndRevalDialog> createState() =>
      _ValBidsAndRevalDialogState();
}

class _ValBidsAndRevalDialogState
    extends ConsumerState<_ValBidsAndRevalDialog> {
  final _costCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  Map<String, List<double>> _bids = const {};
  Map<String, TenderRevaluationModel> _revals = const {};
  bool _loading = true;
  bool _saving = false;

  static final _money = NumberFormat('#,##0.##', 'en_US');

  List<TenderSaleModel> get _rounds =>
      [...widget.info.sales]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  TenderSaleModel get _current => _rounds.last;

  // The forfeited package's item + the forfeited quantity being valued.
  PackageItem? get _pkgItem {
    final f = widget.info.forfeited;
    final items = f.packageDetails?.items ?? const [];
    if (f.itemId != null) {
      return items.where((i) => i.id == f.itemId).firstOrNull;
    }
    return items.length == 1 ? items.first : null;
  }

  // Quantity valued — MUST match the Unsold table's Valuation cell
  // (_ValuationCell effQty): entryQty, else the matched item's qty, else the
  // sum of all item quantities. (No forfeit-entry derivation here, so the
  // popup's "× qty" agrees with the table.)
  int get _qty {
    final f = widget.info.forfeited;
    if (f.entryQty != null) return f.entryQty!;
    if (f.itemId != null) {
      final it = f.packageDetails?.items
          .where((i) => i.id == f.itemId)
          .firstOrNull;
      if (it != null) return it.quantity;
    }
    return f.packageDetails?.items.fold<int>(0, (s, i) => s + i.quantity) ?? 1;
  }

  @override
  void initState() {
    super.initState();
    // Rebuild on each keystroke so the live "× qty = total" updates.
    _costCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
  }

  Future<void> _load() async {
    final svc = ref.read(disposalServiceProvider);
    final fpId = widget.info.forfeited.id;
    try {
      final results = await Future.wait([
        svc.getTenderBidsByRound(fpId),
        svc.getTenderRevaluationsByRound(fpId),
      ]);
      _bids = results[0] as Map<String, List<double>>;
      _revals = results[1] as Map<String, TenderRevaluationModel>;
    } catch (_) {}
    final existing = _revals[_current.id];
    if (existing != null) {
      _costCtrl.text = existing.valuationCost == existing.valuationCost.roundToDouble()
          ? existing.valuationCost.toInt().toString()
          : existing.valuationCost.toString();
      _noteCtrl.text = existing.note ?? '';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _costCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  // NumberFormat, not toString(): a raw double prints its binary artefacts
  // (e.g. 222272.63999999998 for 222272.64).
  String _fmt(double b) => b == b.roundToDouble()
      ? NumberFormat('#,##0').format(b)
      : NumberFormat('#,##0.00').format(b);

  String _roundLabel(TenderSaleModel s, int attempt) {
    final parts = <String>[tenderRoundLabel(attempt)];
    if (s.saleNumber != null && s.saleNumber!.isNotEmpty) parts.add(s.saleNumber!);
    if (s.saleDate != null) {
      parts.add(DateFormat('yyyy-MM-dd').format(s.saleDate!));
    }
    return parts.join(' · ');
  }

  Future<void> _save() async {
    final cost = double.tryParse(_costCtrl.text.trim());
    if (cost == null || cost <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Enter a valid valuation amount'),
          backgroundColor: context.colors.dangerRed));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(disposalServiceProvider).saveTenderRevaluation(
            widget.info.forfeited.id,
            _current.id,
            cost,
            note: _noteCtrl.text,
            yard: widget.info.forfeited.yard,
          );
      ref.invalidate(tenderRevaluationsProvider(widget.info.forfeited.id));
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Re-valuation saved: Rs. ${_money.format(cost)}'),
          backgroundColor: context.colors.successGreen));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: context.colors.dangerRed));
    }
  }

  // The recorded bids for a round: "Bids" heading + amount chips.
  Widget _roundBidsList(String roundId) {
    final amounts = [...(_bids[roundId] ?? const <double>[])]
      ..sort((a, b) => b.compareTo(a));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.sell_rounded, size: 15, color: context.colors.primaryGold),
          const Gap(8),
          Text('Bids',
              style: TextStyle(
                  color: context.colors.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
        ]),
        const Gap(8),
        if (amounts.isEmpty)
          Text('No bids recorded',
              style: TextStyle(color: context.colors.textMuted, fontSize: 12))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (int i = 0; i < amounts.length; i++)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: context.colors.cardDark,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: i == 0
                            ? context.colors.successGreen.withOpacity(0.5)
                            : context.colors.borderColor),
                  ),
                  child: Text('Rs. ${_fmt(amounts[i])}',
                      style: TextStyle(
                          color: context.colors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ),
            ],
          ),
      ],
    );
  }

  // Editable "Set / update valuation" input for the current round — cost per
  // item × forfeited qty (like Pending Valuation) + an optional note.
  Widget _newValuationEditor(Color gold) {
    // "Set" once a value exists (either already saved for the next tender, or
    // typed now); otherwise a Pending status prompts the officer to enter it.
    final saved = _revals[_current.id] != null;
    final typed = (double.tryParse(_costCtrl.text.trim()) ?? 0) > 0;
    final isSet = saved || typed;
    final amber = context.colors.warningAmber;
    final green = context.colors.successGreen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.edit_rounded, size: 15, color: gold),
          const Gap(8),
          Text('Set valuation',
              style: TextStyle(
                  color: context.colors.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (isSet ? green : amber).withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: (isSet ? green : amber).withOpacity(0.4)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                  isSet
                      ? Icons.check_circle_rounded
                      : Icons.hourglass_bottom_rounded,
                  size: 13,
                  color: isSet ? green : amber),
              const Gap(5),
              Text(isSet ? 'Valuation set' : 'Pending',
                  style: TextStyle(
                      color: isSet ? green : amber,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
        const Gap(4),
        Text(
            'Decide this round’s value (${tenderRoundLabel(_rounds.length)}) from the bids above. '
            'Central Disposal can re-tender the package once it is set.',
            style: TextStyle(color: context.colors.textMuted, fontSize: 11)),
        const Gap(10),
        Row(children: [
          Expanded(
            child: Text(_valItemName(widget.info.forfeited),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ),
          const Gap(8),
          Icon(Icons.inventory_2_rounded,
              size: 12, color: context.colors.textMuted),
          const Gap(4),
          Text('Qty $_qty',
              style:
                  TextStyle(color: context.colors.textMuted, fontSize: 11)),
        ]),
        const Gap(10),
        // Full-width cost field; live total on its own line below so a large
        // total never squeezes / overflows the input.
        TextField(
          controller: _costCtrl,
          // Locked once saved: the valuation is a decision already issued to
          // Central Disposal, so it is not silently editable afterwards.
          enabled: !saved,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Cost / item (LKR)',
            isDense: true,
            prefixText: 'LKR ',
          ),
        ),
        const Gap(8),
        Align(
          alignment: Alignment.centerRight,
          child: _LiveTotal(qty: _qty, controller: _costCtrl),
        ),
        const Gap(12),
        TextField(
          controller: _noteCtrl,
          enabled: !saved,
          style: TextStyle(color: context.colors.textPrimary),
          maxLines: 2,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Note (optional)',
            filled: true,
            fillColor: context.colors.cardDark,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: context.colors.borderColor)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: context.colors.borderColor)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: gold, width: 1.4)),
          ),
        ),
      ],
    );
  }

  // Valuation block for a round: the Valuation Tender (attempt 1) falls back to
  // the original Pending Valuation price; later re-tenders show the Valuation
  // Directorate's bid-driven re-valuation, or amber while it is still pending.
  Widget _roundValuation(String roundId, int attempt) {
    final reval = _revals[roundId];
    final unit = reval?.valuationCost ??
        (attempt == 1 ? widget.info.forfeited.valuationCost : null);
    final isReval = reval != null;

    Widget heading(String? tag) => Row(children: [
          Icon(Icons.price_change_rounded,
              size: 15, color: context.colors.primaryGold),
          const Gap(8),
          Text('Valuation',
              style: TextStyle(
                  color: context.colors.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
          if (tag != null) ...[
            const Gap(8),
            Text(tag,
                style: TextStyle(
                    color: context.colors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
        ]);

    if (unit == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading(null),
          const Gap(8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: context.colors.warningAmber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: context.colors.warningAmber.withOpacity(0.4)),
            ),
            child: Text('Awaiting new valuation',
                style: TextStyle(
                    color: context.colors.warningAmber,
                    fontWeight: FontWeight.w700,
                    fontSize: 12)),
          ),
        ],
      );
    }
    final blue = context.colors.accentLightBlue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading(isReval ? 'Re-valued' : null),
        const Gap(8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: blue.withOpacity(0.4)),
          ),
          child: RichText(
            text: TextSpan(children: [
              TextSpan(
                  text: 'LKR ${_money.format(unit * _qty)}',
                  style: TextStyle(
                      color: blue, fontWeight: FontWeight.w800, fontSize: 13)),
              TextSpan(
                  text: '  (@ ${_money.format(unit)} × $_qty)',
                  style: TextStyle(
                      color: context.colors.textMuted, fontSize: 11)),
            ]),
          ),
        ),
        if (reval?.note != null && reval!.note!.isNotEmpty) ...[
          const Gap(6),
          Text(reval.note!,
              style: TextStyle(color: context.colors.textMuted, fontSize: 12)),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final gold = context.colors.primaryGold;
    final rounds = _rounds;
    return StyledFormDialog(
      label: 'Bids & Re-valuation',
      title: widget.info.forfeited.srNumber,
      headerAccentColor: gold,
      icon: Icons.price_change_rounded,
      width: 500,
      child: _loading
          ? Padding(
              padding: const EdgeInsets.all(28),
              child: Center(child: CircularProgressIndicator(color: gold)))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Past tender rounds — READ-ONLY: each round's valuation + bids.
                for (int r = 0; r < rounds.length; r++) ...[
                  if (r > 0) const Gap(10),
                  StyledFormSection(
                    gap: 0,
                    title: _roundLabel(rounds[r], r + 1),
                    icon: Icons.gavel_rounded,
                    children: [
                      _roundValuation(rounds[r].id, r + 1),
                      const Gap(10),
                      _roundBidsList(rounds[r].id),
                    ],
                  ),
                ],
                const Gap(10),
                // After the Valuation Tender plus Tender 1-3 have all gone
                // unsold, the Valuation Directorate is done: the next price is
                // set by a High Panel tender committee, not here.
                if (_handedToHighPanel)
                  StyledFormSection(
                    gap: 0,
                    title: 'Referred to the High Panel',
                    icon: Icons.groups_rounded,
                    children: [_handoverNotice()],
                  )
                else
                  // The valuation for the NEXT (re-)tender — decided from the
                  // bids above. Editable; shows Pending until entered.
                  StyledFormSection(
                    gap: 0,
                    // This prices the CURRENT round — the one whose bids are
                    // listed above. Labelling it "Next Tender N+1" made the
                    // same round read as "Tender 2" here and "Tender 1" on
                    // Central Disposal.
                    title:
                        '${tenderRoundLabel(rounds.length)} · New Valuation',
                    icon: Icons.price_change_rounded,
                    children: [_newValuationEditor(gold)],
                  ),
              ],
            ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text(
                (_handedToHighPanel || _alreadyValued) ? 'Close' : 'Cancel')),
        // Hidden once this round already carries a valuation — the figure has
        // gone to Central Disposal and must not be quietly changed.
        if (!_handedToHighPanel && !_alreadyValued)
          FilledButton(
            onPressed: (_loading || _saving) ? null : _save,
            style: FilledButton.styleFrom(backgroundColor: gold),
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Save Valuation'),
          ),
      ],
    );
  }

  /// True once the package has exhausted the Valuation Tender + Tender 1-3.
  /// From that point a High Panel committee decides the price.
  ///
  /// The Unsold table now filters these packages out entirely, so this is a
  /// safety net for a package that crosses the threshold while the dialog is
  /// already open.
  bool get _handedToHighPanel => _rounds.length > kMaxBidTenderRounds;

  /// True once this round's valuation has been issued.
  bool get _alreadyValued => _revals[_current.id] != null;

  /// Read-only explanation shown in place of the editor after Tender 3.
  Widget _handoverNotice() {
    final blue = context.colors.accentLightBlue;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: blue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: blue.withOpacity(0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline_rounded, size: 16, color: blue),
        const Gap(10),
        Expanded(
          child: Text(
            'This package went unsold through the Valuation Tender and '
            'Tender 1-3. A High Panel tender committee now inspects it and '
            'sets the committee valuation, which the ADG then submits as the '
            'final valuation for the next tender.',
            style: TextStyle(
                color: context.colors.textSecondary, fontSize: 12, height: 1.4),
          ),
        ),
      ]),
    );
  }
}

/// How many times this package has been tendered, as a tappable badge that
/// opens the round history — the same affordance Central Disposal's Unsold
/// table uses, instead of a bare "4×".
class _ValAttemptsBadge extends StatelessWidget {
  final ReTenderSaleInfo info;
  const _ValAttemptsBadge({required this.info});

  @override
  Widget build(BuildContext context) {
    final amber = context.colors.warningAmber;
    return Tooltip(
      message: 'View tender history',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => showDialog(
            context: context,
            builder: (_) => _ValTenderHistoryDialog(info: info),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: amber.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: amber.withOpacity(0.4)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('${info.tenderCount}×',
                  style:
                      TextStyle(color: amber, fontWeight: FontWeight.w800)),
              const Gap(5),
              Icon(Icons.history_rounded, size: 14, color: amber),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Every tender round this package has been through, newest first.
class _ValTenderHistoryDialog extends StatelessWidget {
  final ReTenderSaleInfo info;
  const _ValTenderHistoryDialog({required this.info});

  @override
  Widget build(BuildContext context) {
    final gold = context.colors.primaryGold;
    // Oldest first so the round numbers read Valuation Tender, Tender 1, 2, 3.
    final sales = [...info.sales]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return StyledFormDialog(
      label: 'Tender History',
      title: info.forfeited.srNumber,
      headerAccentColor: gold,
      icon: Icons.history_rounded,
      width: 520,
      child: StyledFormSection(
        title: 'Tendered ${info.tenderCount} time(s)',
        icon: Icons.gavel_rounded,
        children: [
          for (int i = 0; i < sales.length; i++) ...[
            if (i > 0) const Gap(8),
            _roundCard(context, sales[i], i + 1, i == sales.length - 1),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close')),
      ],
    );
  }

  Widget _roundCard(
      BuildContext context, TenderSaleModel t, int attempt, bool isLatest) {
    final gold = context.colors.primaryGold;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isLatest ? gold.withOpacity(0.5) : context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.gavel_rounded, size: 15, color: gold),
            const Gap(8),
            Expanded(
              child: Text(tenderRoundLabel(attempt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: context.colors.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 14)),
            ),
            if (isLatest)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: gold.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: gold.withOpacity(0.4)),
                ),
                child: Text('Current',
                    style: TextStyle(
                        color: gold,
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
              ),
          ]),
          const Gap(8),
          _kv(context, 'Sale Number', t.saleNumber ?? '—'),
          _kv(
              context,
              'Sale Date',
              t.saleDate != null
                  ? DateFormat('yyyy-MM-dd').format(t.saleDate!)
                  : '—'),
          _kv(context, 'Sale Start Time', t.saleTime ?? '—'),
          if (t.createdByName?.trim().isNotEmpty == true)
            _kv(context, 'Created By', t.createdByName!.trim()),
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 118,
          child: Text(k,
              style:
                  TextStyle(color: context.colors.textMuted, fontSize: 12)),
        ),
        Expanded(
          child: Text(v,
              style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

/// All / Pending / Valued segmented filter for the Unsold Tenders table.
///
/// "Pending" is this directorate's actual work queue — rounds whose valuation
/// has not been set yet. "Valued" is what has already gone to Central Disposal.
class _ValStatusFilter extends StatelessWidget {
  final bool? value;
  final ValueChanged<bool?> onChanged;
  const _ValStatusFilter({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _chip(context, label: 'All', selected: value == null, onTap: () => onChanged(null)),
      const Gap(8),
      _chip(context,
          label: 'Pending',
          icon: Icons.hourglass_bottom_rounded,
          colour: context.colors.warningAmber,
          selected: value == false,
          onTap: () => onChanged(false)),
      const Gap(8),
      _chip(context,
          label: 'Valued',
          icon: Icons.check_circle_rounded,
          colour: context.colors.successGreen,
          selected: value == true,
          onTap: () => onChanged(true)),
    ]);
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
    Color? colour,
  }) {
    final c = colour ?? context.colors.primaryGold;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? c.withOpacity(0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: selected ? c.withOpacity(0.6) : context.colors.borderColor,
                width: selected ? 1.4 : 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 14,
                  color: selected ? c : context.colors.textMuted),
              const Gap(6),
            ],
            Text(label,
                style: TextStyle(
                    color: selected ? c : context.colors.textSecondary,
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

/// The Re-valuation cell — must make PENDING and VALUED tellable apart at a
/// glance, which a uniform gold "Value" button on every row could not do.
///
///   pending -> amber outlined "Set Value" button
///   valued  -> green card showing the amount that was set (still tappable,
///              so the round's bids and figure can be reviewed)
class _ValRevalCell extends ConsumerWidget {
  final ReTenderSaleInfo info;
  final bool valued;
  const _ValRevalCell({required this.info, required this.valued});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final amber = context.colors.warningAmber;
    final green = context.colors.successGreen;

    void open() => showDialog(
          context: context,
          builder: (_) => _ValBidsAndRevalDialog(info: info),
        );

    if (!valued) {
      return FilledButton.icon(
        style: FilledButton.styleFrom(
            backgroundColor: amber,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            visualDensity: VisualDensity.compact),
        icon: const Icon(Icons.price_change_rounded, size: 15),
        label: const Text('Set Value', style: TextStyle(fontSize: 12)),
        onPressed: open,
      );
    }

    // Valued — show WHAT was set, not just that it was.
    final current = info.latestSale?.id;
    final revals =
        ref.watch(tenderRevaluationsProvider(info.forfeited.id)).valueOrNull ??
            const <String, TenderRevaluationModel>{};
    final unit = current != null ? revals[current]?.valuationCost : null;
    final qty = _valQtyOf(info.forfeited);
    final fmt = NumberFormat('#,##0');

    return Tooltip(
      message: 'View bids & the valuation set for this round',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: open,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: green.withOpacity(0.10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: green.withOpacity(0.45)),
            ),
            // ONE line, so the row keeps its default height. A stacked
            // label + amount forced the whole table taller, which looked
            // worse than the extra line was worth.
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_circle_rounded, size: 13, color: green),
              const Gap(5),
              Flexible(
                child: Text(
                    unit != null ? 'LKR ${fmt.format(unit * qty)}' : 'Valued',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: green,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Quantity a valuation is multiplied by — the forfeited entry qty, else the
/// matched item's qty, else the sum of the package's items.
int _valQtyOf(ForfeitedPackageModel f) {
  if (f.entryQty != null) return f.entryQty!;
  if (f.itemId != null) {
    final it =
        f.packageDetails?.items.where((i) => i.id == f.itemId).firstOrNull;
    if (it != null) return it.quantity;
  }
  return f.packageDetails?.items.fold<int>(0, (s, i) => s + i.quantity) ?? 1;
}
