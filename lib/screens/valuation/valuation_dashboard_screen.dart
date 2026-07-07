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

/// Valuation Directorate (DC / SDDC) portal. Standalone scaffold (not AppShell).
/// Lists every yard's disposal requests that are still awaiting valuation; the
/// directorate sets a cost per package item and forwards the request to the
/// Central Disposal Directorate.
class ValuationDashboardScreen extends ConsumerWidget {
  const ValuationDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

          // ── Body ─────────────────────────────────────────────
          Expanded(
            child: Padding(
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
                      loading: () =>
                          Center(child: CircularProgressIndicator(color: gold)),
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
                        ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.05);
                      },
                    ),
                  ),
                ],
              ),
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
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: gold,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                icon: const Icon(Icons.calculate_rounded, size: 18),
                label: const Text('Set Valuation'),
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => _SetValuationDialog(request: request),
                ),
              ),
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
                    DataColumn2(label: Text('Item'), size: ColumnSize.M),
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
                        label: Text('Disposition'),
                        size: ColumnSize.S,
                        fixedWidth: 130),
                    DataColumn2(
                        label: Text('Valuation'),
                        size: ColumnSize.S,
                        fixedWidth: 150),
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
                    final displayQty = pkgItem != null
                        ? pkgItem.quantity
                        : it.totalQuantity;
                    final highlightId = pkgItem?.id ?? f?.itemId ??
                        (f?.packageDetails?.items.isNotEmpty == true
                            ? f!.packageDetails!.items.first.id
                            : null);
                    return DataRow(cells: [
                      DataCell(Text(f?.srNumber ?? '—',
                          style: TextStyle(
                              color: context.colors.accentLightBlue,
                              fontWeight: FontWeight.w600))),
                      DataCell(Text(displayName,
                          overflow: TextOverflow.ellipsis)),
                      DataCell(Text(f?.consigneeName ?? '—',
                          overflow: TextOverflow.ellipsis)),
                      DataCell(Text(displayHs ?? '—',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 12))),
                      DataCell(Text('$displayQty',
                          style: TextStyle(
                              color: context.colors.textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 12))),
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

/// Dialog with one cost field per package item. "Save Draft" stores the costs
/// without forwarding; "Forward to Central Disposal" requires every item to
/// have a cost, then releases the request.
class _SetValuationDialog extends ConsumerStatefulWidget {
  final DisposalRequestModel request;
  const _SetValuationDialog({required this.request});

  @override
  ConsumerState<_SetValuationDialog> createState() =>
      _SetValuationDialogState();
}

class _SetValuationDialogState extends ConsumerState<_SetValuationDialog> {
  late final Map<String, TextEditingController> _ctrls;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Build one controller per *display row* (composite key = itemId_pkgItemId)
    // so that expanded per-item rows from the same FP row each have an
    // independent text field rather than sharing one controller. Uses the same
    // _expandRows() so skipped (duplicate) per-item rows get no orphan field.
    _ctrls = {};
    for (final row in _expandRows()) {
      final key = _ctrlKey(row.it, row.pkgItem);
      _ctrls[key] = TextEditingController(
          text: row.it.valuationCost != null
              ? row.it.valuationCost!.toStringAsFixed(0)
              : '');
    }
    // Rebuild on every keystroke so each item's live total (cost × qty)
    // updates as the directorate types.
    for (final c in _ctrls.values) {
      c.addListener(_onCostChanged);
    }
  }

  void _onCostChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.removeListener(_onCostChanged);
      c.dispose();
    }
    super.dispose();
  }

  String _itemName(DisposalRequestItemModel it) {
    final items = it.forfeited?.packageDetails?.items ?? const [];
    if (items.isEmpty) return it.forfeited?.srNumber ?? 'Item';
    final itemId = it.forfeited?.itemId;
    if (itemId != null) {
      final match = items.where((i) => i.id == itemId).firstOrNull;
      if (match != null) return match.itemName;
    }
    if (items.length == 1) return items.first.itemName;
    return '${items.first.itemName} +${items.length - 1}';
  }

  /// Composite controller key for a display row.
  String _ctrlKey(DisposalRequestItemModel it, PackageItem? pkgItem) =>
      pkgItem != null ? '${it.id}_${pkgItem.id}' : it.id;

  /// Collect costs keyed by disposal_request_items.id.
  /// For expanded rows (multiple pkgItems from same it.id), each pkgItem has
  /// its own controller; we map them back to it.id by taking the value from
  /// whichever controller was filled (last non-empty wins — for now they're
  /// independent fields but the backend stores one cost per DR item row).
  Map<String, double> _collectCosts() {
    final out = <String, double>{};
    final expandedRows = _expandRows();
    for (final row in expandedRows) {
      final key = _ctrlKey(row.it, row.pkgItem);
      final v = double.tryParse(_ctrls[key]?.text.trim() ?? '');
      if (v != null && v >= 0) out[row.it.id] = v;
    }
    return out;
  }

  Future<void> _submit({required bool forward}) async {
    final costs = _collectCosts();
    if (forward && costs.length != widget.request.items.length) {
      setState(() => _error =
          'Enter a cost for every item before forwarding to Central Disposal.');
      return;
    }

    if (costs.isEmpty) {
      setState(() => _error = 'Enter at least one cost.');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await ref.read(valuationServiceProvider).setValuationCosts(
            widget.request.id,
            costs,
            forward: forward,
          );
      ref.read(disposalRequestsRefreshProvider.notifier).trigger();
      ref.invalidate(valuationRequestsProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: context.colors.successGreen,
          content: Text(forward
              ? 'Request forwarded to the Central Disposal Directorate.'
              : 'Valuation saved.'),
        ));
      }
    } catch (e) {
      final msg = e.toString().contains('valuation_incomplete')
          ? 'Every item must have a cost before forwarding.'
          : 'Error: $e';
      setState(() => _error = msg);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Expand package-level FP rows (itemId==null, multiple items) into per-item
  // display rows. Each sub-row shares the same disposal_request_items.id (and
  // thus the same cost field) since the directorate sets one unit price for the
  // item type; the total = unitCost × that item's qty.
  List<({DisposalRequestItemModel it, PackageItem? pkgItem})> _expandRows() {
    final out = <({DisposalRequestItemModel it, PackageItem? pkgItem})>[];
    // Items already covered by a dedicated per-item request row (correct
    // partial qty) — keyed "<packageId>:<itemId>". A package-level row must not
    // re-expand these at the full registered qty (mirrors the table builder).
    final perItemKeys = <String>{};
    for (final it in widget.request.items) {
      final iid = it.forfeited?.itemId;
      final pid = it.forfeited?.packageId;
      if (iid != null && pid != null) perItemKeys.add('$pid:$iid');
    }
    for (final it in widget.request.items) {
      final fpItems = it.forfeited?.packageDetails?.items ?? const [];
      final pid = it.forfeited?.packageId;
      if (it.forfeited?.itemId == null && fpItems.length > 1) {
        for (final pkgItem in fpItems) {
          if (pid != null && perItemKeys.contains('$pid:${pkgItem.id}')) {
            continue;
          }
          out.add((it: it, pkgItem: pkgItem));
        }
      } else {
        out.add((it: it, pkgItem: null));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final gold = context.colors.primaryGold;
    final expandedRows = _expandRows();
    return StyledFormDialog(
      label: 'SET VALUATION',
      title: '${yardName(widget.request.yard)} · ${expandedRows.length} item(s)',
      icon: Icons.calculate_rounded,
      headerAccentColor: gold,
      // Match the Central Disposal / Appeal package-detail popups (width 900) so
      // the Set Valuation dialog has the same large, full-style presentation.
      width: 900,
      actions: [
        Expanded(
          child: Text(
              'Forwarding requires a cost for every item.',
              style: TextStyle(
                  color: context.colors.textMuted, fontSize: 11)),
        ),
        TextButton(
          onPressed: _isLoading ? null : () => _submit(forward: false),
          child: const Text('Save Draft'),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
              backgroundColor: gold, foregroundColor: Colors.white),
          icon: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send_rounded, size: 16),
          label: const Text('Forward to Central Disposal'),
          onPressed: _isLoading ? null : () => _submit(forward: true),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.colors.dangerRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: context.colors.dangerRed.withOpacity(0.4)),
              ),
              child: Row(children: [
                Icon(Icons.error_outline,
                    color: context.colors.dangerRed, size: 18),
                const Gap(10),
                Expanded(
                    child: Text(_error!,
                        style: TextStyle(
                            color: context.colors.dangerRed,
                            fontSize: 13))),
              ]),
            ),
            const Gap(16),
          ],
          for (final row in expandedRows) ...[
            Builder(builder: (context) {
              final it = row.it;
              final pkgItem = row.pkgItem;
              final displayName = pkgItem?.itemName ?? _itemName(it);
              final displayHs = pkgItem?.hsCode ?? it.hsCodeLabel;
              final displayQty = pkgItem != null
                  ? pkgItem.quantity
                  : it.totalQuantity;
              return Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(it.forfeited?.srNumber ?? '—',
                          style: TextStyle(
                              color: context.colors.accentLightBlue,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                      Text(displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 12)),
                      const Gap(4),
                      Row(children: [
                        Icon(Icons.tag_rounded,
                            size: 12, color: context.colors.textMuted),
                        const Gap(4),
                        Text('HS ${displayHs ?? '—'}',
                            style: TextStyle(
                                color: context.colors.textMuted,
                                fontSize: 11)),
                        const Gap(10),
                        Icon(Icons.inventory_2_rounded,
                            size: 12, color: context.colors.textMuted),
                        const Gap(4),
                        Text('Qty $displayQty',
                            style: TextStyle(
                                color: context.colors.textMuted,
                                fontSize: 11)),
                      ]),
                    ],
                  ),
                ),
                const Gap(8),
                _DispoChip(disposition: it.disposition),
                const Gap(12),
                SizedBox(
                  width: 150,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      TextField(
                        controller: _ctrls[_ctrlKey(it, pkgItem)],
                        keyboardType:
                            const TextInputType.numberWithOptions(
                                decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Cost / item (LKR)',
                          isDense: true,
                          prefixText: 'LKR ',
                        ),
                      ),
                      const Gap(6),
                      _LiveTotal(
                          qty: displayQty,
                          controller: _ctrls[_ctrlKey(it, pkgItem)]!),
                    ],
                  ),
                ),
              ]);
            }),
            const Divider(height: 24),
          ],
        ],
      ),
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
