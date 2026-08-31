import 'sealed_valuation.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/material.dart'
    show
        Wrap,
        RoundedRectangleBorder,
        Colors,
        Icons,
        Theme,
        FontWeight,
        BorderRadius,
        Radius,
        BoxConstraints,
        BoxShadow,
        Offset,
        Border,
        BorderSide,
        IconButton,
        ElevatedButton,
        CircularProgressIndicator,
        ScaffoldMessenger,
        SnackBar,
        showDialog,
        BuildContext,
        Widget,
        Row,
        Column,
        Expanded,
        Icon,
        Text,
        Padding,
        EdgeInsets,
        Center,
        SingleChildScrollView,
        Form,
        GlobalKey,
        FormState,
        TextFormField,
        InputDecoration,
        OutlineInputBorder,
        DropdownButtonFormField,
        DropdownMenuItem,
        SizedBox,
        Brightness,
        Color,
        IconData,
        Dialog,
        Tween,
        TweenAnimationBuilder,
        AnimationController,
        Animation,
        CurvedAnimation,
        AnimatedBuilder,
        SingleTickerProviderStateMixin,
        Transform,
        Opacity,
        Curves,
        MainAxisSize,
        CrossAxisAlignment,
        BoxDecoration,
        StatelessWidget,
        LinearGradient,
        Flexible,
        Navigator,
        MainAxisAlignment,
        TextButton,
        BoxShape,
        FontStyle,
        TextStyle,
        Container,
        OutlinedButton,
        TextEditingController,
        MediaQuery,
        TextInputType,
        VoidCallback,
        Spacer,
        TextOverflow,
        StatefulWidget,
        StatefulBuilder,
        ConstrainedBox,
        State,
        InkWell,
        AlwaysStoppedAnimation,
        Positioned,
        SnackBarBehavior,
        Stack;
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../core/providers.dart';
import '../core/post_status_activities.dart';
import 'styled_dropdown.dart';
import 'one_tap_date_picker.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/services.dart';

/// The valuation row shown in the Sale / Destruction sections.
///
/// Shows the **LATEST** valuation: if the package was re-valued for a later
/// tender round that figure wins over the Valuation Directorate's first one,
/// and the row is marked "re-valued" — the same rule the Unsold tables use.
/// Formatted like those tables too: total first, then `@ unit x qty`.
class _ValuationDetailRow extends ConsumerWidget {
  final ForfeitedPackageModel fp;

  /// The quantity actually sold / destroyed, when the caller knows it.
  final int? soldQty;

  const _ValuationDetailRow({required this.fp, this.soldQty});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revals =
        ref.watch(tenderRevaluationsProvider(fp.id)).valueOrNull ?? const {};
    TenderRevaluationModel? latest;
    for (final r in revals.values) {
      if (latest == null || r.createdAt.isAfter(latest.createdAt)) latest = r;
    }
    final unit = latest?.valuationCost ?? fp.valuationCost;
    if (unit == null) return const SizedBox.shrink();

    final int qty;
    if (soldQty != null && soldQty! > 0) {
      qty = soldQty!;
    } else if (fp.entryQty != null) {
      qty = fp.entryQty!;
    } else if (fp.itemId != null) {
      qty = fp.packageDetails?.items
              .where((i) => i.id == fp.itemId)
              .firstOrNull
              ?.quantity ??
          1;
    } else {
      qty =
          fp.packageDetails?.items.fold<int>(0, (s, i) => s + i.quantity) ?? 1;
    }

    final money = NumberFormat('#,##0.##');
    final revalued = latest != null;
    return _DetailItem(
      icon: Icons.calculate_rounded,
      label: revalued ? 'Valuation (Rs) · re-valued' : 'Valuation (Rs)',
      value: '${money.format(unit * qty)}'
          '  (@ ${money.format(unit)} × $qty)',
      valueColor: revalued ? context.colors.accentLightBlue : null,
    );
  }
}

/// Per-round tender history for an unsold package: the valuation each round
/// was offered at, and the bids that came in against it.
///
/// Shown on the Unsold popup so the whole story is visible in one place —
/// the Valuation Tender, then Tender 1/2/3, then the committee-priced round,
/// each with its price and its bids. Rounds with neither a valuation nor a
/// bid are skipped, and the section hides itself entirely when there is
/// nothing to show.
class TenderHistorySection extends ConsumerWidget {
  final ForfeitedPackageModel forfeited;

  /// Quantity this row covers, so a per-item unit price can be totalled.
  final int? qty;

  const TenderHistorySection({super.key, required this.forfeited, this.qty});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revals =
        ref.watch(tenderRevaluationsProvider(forfeited.id)).valueOrNull ??
            const <String, TenderRevaluationModel>{};
    final bids = ref.watch(tenderBidsProvider(forfeited.id)).valueOrNull ??
        const <String, List<double>>{};
    // The committee round is priced by the ADG's submission. The seed also
    // records that as a tender_revaluations row, but a package valued through
    // the UI may not have one yet — so fall back to the committee itself,
    // otherwise the round would vanish from this list.
    final committeeAsync = ref.watch(tenderCommitteesProvider);
    final committee = committeeAsync.valueOrNull?[forfeited.id];
    // Members only exist once the DG/ADG appointed the committee. Held in a
    // local so every branch below reads the same list.
    final committeeMembers = committee?.members ?? const <CommitteeMember>[];
    final sales =
        ref.watch(tenderSalesProvider).valueOrNull ?? const <TenderSaleModel>[];

    // The rounds THIS package sat in, oldest first — that ordering is what
    // turns a sale id into "Valuation Tender" / "Tender 1" / ...
    final mine = sales
        .where((s) => s.items.any((i) => i.forfeitedPackageId == forfeited.id))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // Any round that has a valuation or bids but no matching sale row still
    // deserves a line, so collect those ids too.
    final ordered = <String>[for (final s in mine) s.id];
    for (final id in {...revals.keys, ...bids.keys}) {
      if (id.isNotEmpty && !ordered.contains(id)) ordered.add(id);
    }
    if (ordered.isEmpty) return const SizedBox.shrink();

    final effQty = (qty != null && qty! > 0)
        ? qty!
        : (forfeited.entryQty ??
            (forfeited.itemId != null
                ? (forfeited.packageDetails?.items
                        .where((i) => i.id == forfeited.itemId)
                        .firstOrNull
                        ?.quantity ??
                    1)
                : (forfeited.packageDetails?.items
                        .fold<int>(0, (a, i) => a + i.quantity) ??
                    1)));

    final money = NumberFormat('#,##0.##');
    final rows = <Widget>[];
    for (var i = 0; i < ordered.length; i++) {
      final id = ordered[i];
      final reval = revals[id];
      final roundBids = bids[id] ?? const <double>[];
      // Bids only exist to PRICE the next round, and the committee round is
      // the last one — its price comes from the committee, not from bidding,
      // so it shows its price and nothing about bids.
      //
      // Normally the round's POSITION says it: anything past Tender 3 is
      // committee-priced. But a package whose earlier rounds were never
      // recorded would shift that index, so the last round also counts as the
      // committee round once the ADG has submitted a committee price.
      final isLastRound = i == ordered.length - 1;
      final isCommitteeRound = (i + 1) > kMaxBidTenderRounds + 1 ||
          (isLastRound && committee?.submittedValue != null && i > 0);
      // Round 1 has no re-valuation of its own — it ran at the Valuation
      // Directorate's original figure. The committee round falls back to the
      // ADG's submitted value.
      final unit = reval?.valuationCost ??
          (i == 0
              ? forfeited.valuationCost
              : (isCommitteeRound ? committee?.submittedValue : null));
      // A committee round is ALWAYS worth showing: it is the last attempt, and
      // hiding it would end the history at Tender 3.
      if (unit == null && roundBids.isEmpty && !isCommitteeRound) continue;
      rows.add(_TenderRoundTile(
        label: tenderRoundLabel(i + 1),
        isCommitteeRound: isCommitteeRound,
        // Who set this price. Only the committee round names its officers.
        committeeMembers: isCommitteeRound ? committeeMembers : const [],
        // Separates "still loading" from "nobody was appointed", so the tile
        // can say which instead of silently listing none.
        committeeLoading: isCommitteeRound && committeeAsync.isLoading,
        priceLabel: unit == null
            ? null
            : 'LKR ${money.format(unit * effQty)}'
                '  (@ ${money.format(unit)} \u00d7 $effQty)',
        revalued: reval != null && !isCommitteeRound,
        bids: isCommitteeRound
            ? const []
            : [for (final b in roundBids) 'LKR ${money.format(b)}'],
      ));
    }
    if (rows.isEmpty) return const SizedBox.shrink();

    return _DetailSection(
      title: 'Tender History',
      icon: Icons.history_rounded,
      delay: 250,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }
}

/// One appointed committee officer, shown under the committee round.
class _CommitteeMemberChip extends StatelessWidget {
  final int no;
  final CommitteeMember member;

  const _CommitteeMemberChip({required this.no, required this.member});

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.accentLightBlue;
    final desig = member.designation?.trim() ?? '';
    final salary = member.salaryNo?.trim() ?? '';
    final sub = [
      if (desig.isNotEmpty) desig,
      if (salary.isNotEmpty) 'Salary No: $salary',
    ].join('  ·  ');

    return material.Tooltip(
      message: sub.isEmpty ? member.name : member.name + '\n' + sub,
      waitDuration: const Duration(milliseconds: 300),
      child: material.Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: accent.withOpacity(0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withOpacity(0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          material.Container(
            width: 17,
            height: 17,
            alignment: material.Alignment.center,
            decoration: BoxDecoration(
                color: accent.withOpacity(0.18), shape: BoxShape.circle),
            child: Text('$no',
                style: TextStyle(
                    color: accent, fontSize: 9.5, fontWeight: FontWeight.w800)),
          ),
          const Gap(6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(member.name,
                  style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700)),
              if (desig.isNotEmpty)
                Text(desig,
                    style: TextStyle(
                        color: context.colors.textMuted, fontSize: 10)),
            ],
          ),
        ]),
      ),
    );
  }
}

/// One round of [TenderHistorySection]: its price and the bids against it.
class _TenderRoundTile extends StatelessWidget {
  final String label;
  final String? priceLabel;
  final bool revalued;
  final List<String> bids;

  /// The committee-priced round. It takes no bids, so the bid line is replaced
  /// by a note saying where its price came from.
  final bool isCommitteeRound;

  /// The officers the ADG appointed to value these goods. Listed under the
  /// committee round so the price and the people who set it read together.
  final List<CommitteeMember> committeeMembers;

  /// The committee list has not arrived yet. Distinguishes it from a package
  /// no committee was ever appointed for.
  final bool committeeLoading;

  const _TenderRoundTile({
    required this.label,
    required this.priceLabel,
    required this.revalued,
    required this.bids,
    this.isCommitteeRound = false,
    this.committeeMembers = const [],
    this.committeeLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent =
        revalued ? context.colors.accentLightBlue : context.colors.primaryGold;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.colors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: accent.withOpacity(0.4)),
              ),
              child: Text(label,
                  style: TextStyle(
                      color: accent,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800)),
            ),
            if (revalued) ...[
              const Gap(8),
              Icon(Icons.price_change_rounded,
                  size: 14, color: context.colors.accentLightBlue),
              const Gap(4),
              Text('re-valued',
                  style: TextStyle(
                      color: context.colors.accentLightBlue,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ],
            const Spacer(),
            if (priceLabel != null)
              Flexible(
                child: Text(priceLabel!,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700)),
              ),
          ]),
          const Gap(8),
          if (isCommitteeRound) ...[
            Text(
                committeeLoading
                    ? 'Priced by the tender committee · loading members…'
                    : committeeMembers.isEmpty
                        ? 'Priced by the tender committee · no bidding'
                        : 'Priced by the tender committee '
                            '(${committeeMembers.length} '
                            '${committeeMembers.length == 1 ? 'member' : 'members'})'
                            ' · no bidding',
                style:
                    TextStyle(color: context.colors.textMuted, fontSize: 11.5)),
            if (committeeMembers.isNotEmpty) ...[
              const Gap(8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < committeeMembers.length; i++)
                    _CommitteeMemberChip(
                        no: i + 1, member: committeeMembers[i]),
                ],
              ),
            ],
          ] else if (bids.isEmpty)
            Text('No bids recorded',
                style:
                    TextStyle(color: context.colors.textMuted, fontSize: 11.5))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Text('Bids:',
                    style: TextStyle(
                        color: context.colors.textMuted, fontSize: 11.5)),
                for (final b in bids)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: context.colors.successGreen.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: context.colors.successGreen.withOpacity(0.35)),
                    ),
                    child: Text(b,
                        style: TextStyle(
                            color: context.colors.successGreen,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class PackageDetailsDialog extends ConsumerStatefulWidget {
  final PackageModel package;
  final Map<DateTime, double> storageRate;
  final WarehouseEntryModel? highlightEntry; // Added highlightEntry
  // Fallback item to highlight when there is no warehouse entry ([highlightEntry]
  // is null) — e.g. an abandoned/"Other" item registered on the SR form that was
  // never admitted to a warehouse. Ensures such items still get the item-detail
  // view and the Final Disposition footer button.
  final String? highlightItemId;
  final bool useLegacySummary;

  /// The forfeited row whose tender history (per-round valuation + bids)
  /// should be shown. Set by the Unsold pages; null hides the section.
  final ForfeitedPackageModel? tenderHistoryFor;
  final bool useWarehouseSummary;

  // Optional yard label (e.g. 'Grey Line 1') shown in the Warehouse Summary so
  // the cross-yard directorate views (Central Disposal / Valuation) can see
  // which yard holds the package. Null hides the row.
  final String? yardLabel;

  // Optional valuation cost set by the Valuation Directorate, shown in the Item
  // Details alongside the package's own declared value. [valuationUnitCost] is
  // per item; [valuationTotalCost] = unit × qty. Null hides the rows.
  final double? valuationUnitCost;
  final double? valuationTotalCost;
  final int? valuationQty;

  /// True while the goods are still in a tender/destruction sale that has not
  /// yet run. The valuation is the reserve price, so the whole Valuation
  /// section AND the per-round tender history are replaced by a "sealed"
  /// notice — see [valuationSealed].
  final bool valuationSealedUntilSale;

  // Optional generic footer action (e.g. the Appeal Directorate's "Hold Appeal"
  // / "Release"). When [footerActionLabel] is set, a button is shown in the
  // dialog footer — styled like the Final Disposition footer — that calls
  // [onFooterAction] (the dialog closes first).
  final String? footerActionLabel;
  final IconData? footerActionIcon;
  final Color? footerActionColor;
  final String? footerActionHint;
  final VoidCallback? onFooterAction;
  final Color? headerAccentColor;

  // Appeal Directorate decision banner. When [appealDecisionLabel] is set, a
  // prominent banner is shown at the top of the body telling the owning yard
  // what to do with the package (e.g. "Release to owner", "Destroy").
  final String? appealDecisionLabel;
  // The raw decision CODE ('RELEASE' | 'SALE' | 'DESTROY' | 'RE-EXPORT' |
  // 'OTHER'). When set, the Final Disposition dialog enables ONLY the matching
  // action — the yard must proceed exactly as the Appeal Directorate decided.
  final String? appealDecisionCode;

  // Final-disposition gating (Forfeited screen). The footer "Final Disposition"
  // button is shown ONLY when [allowFinalDisposition] is true — i.e. the appeal
  // window has passed. While an appeal is still open it is hidden entirely.
  final bool allowFinalDisposition;

  // Sale / Destroy are NOT offered in this dialog — `_isActionEnabled` always
  // disables them. Those two outcomes belong to the Central Disposal
  // Directorate and are started from the "Send Disposal Request" button on the
  // status page, so that one deliberate request covers every selected item.
  //
  // The hook is kept for callers that want to route a Sale / Destroy pick
  // somewhere of their own, but with the current gating it is never invoked.
  final void Function(String disposition)? onSaleOrDestroyRequest;

  // When true, the Final Disposition footer is shown unconditionally (skips the
  // [_hasFinalDisposition] heuristic). Callers that already guarantee the item
  // is actionable — e.g. the Abandoned / Other tables, which exclude finalised
  // items when building their rows — pass this so EVERY listed package gets the
  // button in its details popup.
  final bool forceFinalDisposition;

  // When true, the dialog is opened from the Sold Packages page, so the
  // Sale & Financial Information section is always shown. When false
  // (default), the section only shows if the highlighted entry is sold.
  final bool isSoldPage;

  // When true, show the admin-only "Update" (edit) footer even when this
  // isn't the warehouse-summary layout — e.g. opened from the Packages page.
  // The Update action itself remains admin-only regardless of this flag.
  final bool allowEdit;

  const PackageDetailsDialog({
    super.key,
    required this.package,
    required this.storageRate,
    this.highlightEntry, // Added highlightEntry
    this.highlightItemId,
    this.useLegacySummary = false,
    this.tenderHistoryFor,
    this.useWarehouseSummary = false,
    this.yardLabel,
    this.valuationUnitCost,
    this.valuationTotalCost,
    this.valuationQty,
    this.valuationSealedUntilSale = false,
    this.footerActionLabel,
    this.footerActionIcon,
    this.footerActionColor,
    this.footerActionHint,
    this.onFooterAction,
    this.headerAccentColor,
    this.appealDecisionLabel,
    this.appealDecisionCode,
    this.allowFinalDisposition = true,
    this.onSaleOrDestroyRequest,
    this.forceFinalDisposition = false,
    this.isSoldPage = false,
    this.allowEdit = false,
    this.srFinancials,
  });

  final SrFinancials? srFinancials;

  @override
  ConsumerState<PackageDetailsDialog> createState() =>
      _PackageDetailsDialogState();
}

class _PackageDetailsDialogState extends ConsumerState<PackageDetailsDialog>
    with SingleTickerProviderStateMixin {
  String? _creatorFallback;
  bool _isLoadingCreator = false;
  late final AnimationController _animCtrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _anim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack);
    _animCtrl.forward();
    if (widget.package.inspectedBy == null) {
      _lookupCreator();
    }
  }

  Future<void> _lookupCreator() async {
    setState(() => _isLoadingCreator = true);
    try {
      final creator =
          await AuditLogService().getPackageCreator(widget.package.id);
      if (mounted) setState(() => _creatorFallback = creator);
    } catch (_) {}
    if (mounted) setState(() => _isLoadingCreator = false);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<bool> _showReleaseConfirmation(
      BuildContext context, WarehouseEntryModel entry,
      {int? preselectedQty, List<int>? packageNumbers}) async {
    final notesCtrl = TextEditingController();
    final receiptCtrl = TextEditingController();
    final dateCtrl = TextEditingController(
        text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
    // Release date drives the warehouse-charge calculation (entry date → this
    // date). Defaults to today; editable (a back-date is allowed).
    DateTime releaseDate = DateTime.now();
    final releaseDateCtrl = TextEditingController(
        text: DateFormat('yyyy-MM-dd').format(releaseDate));

    // Find the specific item this entry refers to
    final specificItem = widget.package.items.firstWhere(
      (i) => i.id == entry.packageItemId,
      orElse: () => widget.package.items.first,
    );

    // Auto-repair display logic for old entries that saved 1 as itemCount
    int displayCount = entry.itemCount;
    if (displayCount == 1 && specificItem.quantity > 1 && !entry.isReturned) {
      final returnedSum = widget.package.warehouseEntries
          .where((e) => e.packageItemId == specificItem.id && e.isReturned)
          .fold(0, (sum, e) => sum + e.itemCount);
      displayCount = specificItem.quantity - returnedSum;
      if (displayCount < 1) displayCount = 1; // Fallback
    }

    final qtyCtrl = TextEditingController(
        text: (preselectedQty ?? displayCount).toString());
    final formKey = GlobalKey<FormState>();

    // Charge counts from the SR-form Entry Date (falling back to the warehouse
    // admit date if the package has none), NOT the warehouse admit timestamp —
    // that's what the officer sets on the SR form and expects to be billed from.
    final chargeStart = widget.package.entryDate ?? entry.admittedAt;

    double getCharge(int count) {
      // Temp entry with the release date as the exit date, so the charge covers
      // SR entry date → release date (inclusive) at the historical daily rates.
      final tempEntry = WarehouseEntryModel(
        id: entry.id,
        packageId: entry.packageId,
        packageItemId: entry.packageItemId,
        warehouseId: entry.warehouseId,
        warehouseName: entry.warehouseName,
        warehouseCode: entry.warehouseCode,
        holdReason: entry.holdReason,
        itemCount: count,
        admittedAt: chargeStart,
        dailyRate: entry.dailyRate,
        returnedAt: releaseDate,
      );
      return tempEntry
          .calculatePackageCharge([specificItem], widget.storageRate);
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => material.AlertDialog(
          title: const Text('Release Package Item'),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SR: ${widget.package.srNumber}',
                      style: const material.TextStyle(
                          fontWeight: FontWeight.bold)),
                  Text('Goods: ${specificItem.itemName}',
                      style: material.TextStyle(
                          color: context.colors.primaryGold)),
                  Text('Warehouse: ${entry.warehouseName}',
                      style: const material.TextStyle(fontSize: 12)),
                  const Gap(16),
                  material.Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceDark,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total in Warehouse:'),
                            Text('$displayCount',
                                style: const material.TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const Gap(12),
                        // Quantity is fixed to the packages selected in the
                        // previous step — read-only so it can't diverge.
                        TextFormField(
                          controller: qtyCtrl,
                          readOnly: true,
                          enabled: false,
                          decoration: const material.InputDecoration(
                            labelText: 'Quantity to Release',
                            isDense: true,
                          ),
                        ),
                        const Gap(12),
                        // Release date — drives the charge below.
                        TextFormField(
                          controller: releaseDateCtrl,
                          readOnly: true,
                          decoration: material.InputDecoration(
                            labelText: 'Release Date *',
                            isDense: true,
                            suffixIcon: Icon(Icons.calendar_month,
                                size: 18, color: context.colors.primaryGold),
                          ),
                          onTap: () async {
                            final picked = await showDialog<DateTime>(
                              context: ctx,
                              builder: (_) => OneTapDatePicker(
                                initialDate: releaseDate,
                                // Release can't be before the SR entry date.
                                firstDate: chargeStart,
                                lastDate: DateTime.now(),
                              ),
                            );
                            if (picked != null) {
                              setDialogState(() {
                                releaseDate = picked;
                                releaseDateCtrl.text =
                                    DateFormat('yyyy-MM-dd').format(picked);
                              });
                            }
                          },
                        ),
                        const Gap(8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Warehouse Charge:'),
                            Text(
                                'LKR ${NumberFormat('#,##0.00').format(getCharge(int.tryParse(qtyCtrl.text) ?? 0))}',
                                style: material.TextStyle(
                                    color: context.colors.primaryGold,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const Gap(4),
                        material.Builder(builder: (_) {
                          final startDay = DateTime(chargeStart.year,
                              chargeStart.month, chargeStart.day);
                          final endDay = DateTime(releaseDate.year,
                              releaseDate.month, releaseDate.day);
                          final days = endDay.difference(startDay).inDays + 1;
                          final beforeEntry = endDay.isBefore(startDay);
                          return material.Align(
                            alignment: material.Alignment.centerLeft,
                            child: Text(
                              beforeEntry
                                  ? 'Release date is before the entry date (${DateFormat('yyyy-MM-dd').format(chargeStart)}) — no charge.'
                                  : 'Entry ${DateFormat('yyyy-MM-dd').format(chargeStart)} → Release · $days day(s)',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: beforeEntry
                                      ? context.colors.dangerRed
                                      : context.colors.textMuted),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const Gap(16),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: receiptCtrl,
                          decoration: const material.InputDecoration(
                            labelText: 'Receipt No. *',
                            hintText: 'Enter receipt #',
                          ),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                                  ? 'Required'
                                  : null,
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: dateCtrl,
                          readOnly: true,
                          decoration: const material.InputDecoration(
                            labelText: 'Receipt Date *',
                            suffixIcon: Icon(Icons.calendar_today, size: 18),
                          ),
                          onTap: () async {
                            // Same custom picker as the SR form (consistent look).
                            final existing =
                                DateTime.tryParse(dateCtrl.text.trim());
                            final date = await showDialog<DateTime>(
                              context: context,
                              builder: (_) => OneTapDatePicker(
                                initialDate: existing ?? DateTime.now(),
                                lastDate: DateTime.now(),
                              ),
                            );
                            if (date != null) {
                              dateCtrl.text =
                                  DateFormat('yyyy-MM-dd').format(date);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const Gap(16),
                  material.TextField(
                    controller: notesCtrl,
                    maxLines: 3,
                    minLines: 2,
                    keyboardType: TextInputType.multiline,
                    decoration: const material.InputDecoration(
                      labelText: 'Release Notes (Optional)',
                      hintText: 'Enter any additional details',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            material.TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.successGreen,
                  foregroundColor: Colors.white),
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;

                final releaseQty = int.tryParse(qtyCtrl.text) ?? 0;
                if (releaseQty <= 0 || releaseQty > entry.itemCount) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                      content: Text('Invalid quantity to release'),
                      backgroundColor: Colors.red));
                  return;
                }

                try {
                  String finalNotes =
                      "Receipt No: ${receiptCtrl.text.trim()} | Date: ${dateCtrl.text}";
                  if (notesCtrl.text.trim().isNotEmpty) {
                    finalNotes += " | Notes: ${notesCtrl.text.trim()}";
                  }

                  await ref.read(warehouseServiceProvider).markAsReturned(
                        entry.id,
                        returnNotes: finalNotes,
                        returnQty: releaseQty,
                        packageNumbers: packageNumbers,
                        returnDate: releaseDate,
                      );
                  ref.read(packagesRefreshTriggerProvider.notifier).trigger();
                  ref.read(warehouseRefreshTriggerProvider.notifier).trigger();
                  ref.invalidate(
                      liveWarehouseEntriesProvider(entry.warehouseId));
                  ref.invalidate(livePackagesProvider);
                  ref.invalidate(allWarehouseEntriesProvider);
                  ref.invalidate(packageDataProvider(entry.packageId));
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: context.colors.dangerRed));
                  }
                }
              },
              child: const Text('Confirm Release'),
            ),
          ],
        ),
      ),
    );
    return result ?? false;
  }

  Future<bool> _showDispositionDialog(
      BuildContext context, WarehouseEntryModel entry, String dispositionType,
      {int? preselectedQty, List<int>? packageNumbers}) async {
    final notesCtrl = TextEditingController();
    // Every disposition captures the date the action took place — defaults to
    // today, back-dating allowed, future dates blocked. For Forfeit this date
    // also anchors the 30-day appeal deadline; for others it's the record date
    // (Re-export date, Abandon date, Destroy date, …).
    final isForfeit = _isForfeitStatusLocal(dispositionType);
    DateTime dispositionDate = DateTime.now();
    final dispositionDateCtrl = TextEditingController(
        text:
            '${dispositionDate.year}-${dispositionDate.month.toString().padLeft(2, '0')}-${dispositionDate.day.toString().padLeft(2, '0')}');
    // The date field's label follows the action, e.g. "Re-export Date".
    final dateLabel = isForfeit ? 'Forfeit Date' : '$dispositionType Date';

    final Map<String, _DispositionMeta> meta = {
      'Forfeit': _DispositionMeta(
        icon: Icons.gavel_rounded,
        color: const Color(0xFFE53935),
        label: 'Forfeit',
        description:
            'Package is forfeited to the state. No further charges apply.',
      ),
      'Abandoned': _DispositionMeta(
        icon: Icons.inbox_rounded,
        color: const Color(0xFF9E9E9E),
        label: 'Abandoned',
        description: 'Package is declared abandoned. No further charges apply.',
      ),
      'Re-export': _DispositionMeta(
        icon: Icons.flight_takeoff_rounded,
        color: const Color(0xFF00ACC1),
        label: 'Re-export',
        description: 'Package is sent back to the country of origin.',
      ),
      'Destroy': _DispositionMeta(
        icon: Icons.delete_forever_rounded,
        color: const Color(0xFFE64A19),
        label: 'Destroy',
        description: 'Package is destroyed. No further charges apply.',
      ),
    };
    final m = meta[dispositionType] ??
        _DispositionMeta(
          icon: Icons.help_outline_rounded,
          color: const Color(0xFF7E57C2),
          label: dispositionType,
          description: 'Custom disposition: $dispositionType',
        );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => material.AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(m.icon, color: m.color, size: 22),
          const Gap(10),
          Text('${m.label} Package Item'),
        ]),
        content: StatefulBuilder(
            builder: (ctx, setLocalState) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: m.color.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: m.color.withOpacity(0.3)),
                        ),
                        child: Text(m.description,
                            style: TextStyle(color: m.color, fontSize: 13)),
                      ),
                      // Forfeit date picker (Forfeit only). Defaults to today; a back-date is
                      // allowed. The 30-day appeal deadline is counted from this date.
                      // Date picker for EVERY disposition — defaults to today, future dates
                      // blocked (lastDate = now), same one-tap calendar as the SR form.
                      const Gap(16),
                      TextFormField(
                        controller: dispositionDateCtrl,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: dateLabel,
                          isDense: true,
                          suffixIcon:
                              Icon(Icons.calendar_month, color: m.color),
                        ),
                        onTap: () async {
                          final picked = await showDialog<DateTime>(
                            context: ctx,
                            builder: (_) => OneTapDatePicker(
                              initialDate: dispositionDate,
                              lastDate: DateTime.now(),
                            ),
                          );
                          if (picked != null) {
                            setLocalState(() {
                              dispositionDate = picked;
                              dispositionDateCtrl.text =
                                  '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                            });
                          }
                        },
                      ),
                      if (preselectedQty != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Container(
                            margin: const EdgeInsets.only(top: 12),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: m.color.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Packages selected:',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: m.color.withOpacity(0.7))),
                                Text('$preselectedQty',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: m.color)),
                              ],
                            ),
                          ),
                        ),
                      const Gap(16),
                      TextFormField(
                        controller: notesCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Notes / Remarks (optional)',
                          isDense: true,
                        ),
                        maxLines: 3,
                        minLines: 2,
                        keyboardType: TextInputType.multiline,
                      ),
                    ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton.icon(
            icon: Icon(m.icon, size: 16),
            label: Text('Confirm ${m.label}'),
            style: ElevatedButton.styleFrom(
              backgroundColor: m.color,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;

    await ref.read(warehouseServiceProvider).disposeWarehouseItem(
          entry.id,
          dispositionStatus: dispositionType,
          notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
          qty: preselectedQty,
          packageNumbers: packageNumbers,
          // Every disposition now carries its chosen date (stored as returned_at;
          // for Forfeit it also anchors the appeal deadline).
          forfeitDate: dispositionDate,
        );
    // Refresh so the (still open) actions dialog recomputes processed slots.
    ref.read(packagesRefreshTriggerProvider.notifier).trigger();
    ref.read(warehouseRefreshTriggerProvider.notifier).trigger();
    ref.invalidate(packageDataProvider(entry.packageId));
    ref.invalidate(liveWarehouseEntriesProvider(entry.warehouseId));
    ref.invalidate(livePackagesProvider);
    // When forfeited: refresh the Forfeited Packages page too so the new row appears.
    if (_isForfeitStatusLocal(dispositionType)) {
      ref.invalidate(forfeitedPackagesProvider);
      ref.invalidate(requestableForfeitedPackagesProvider);
    }
    return true;
  }

  void _showActionsDialog(
    BuildContext ctx,
    WarehouseEntryModel entry, {
    PackageItem? highlightedItem,
  }) {
    final specificItem = highlightedItem ??
        widget.package.items.firstWhere(
          (i) => i.id == entry.packageItemId,
          orElse: () => widget.package.items.first,
        );

    showDialog(
      context: ctx,
      builder: (dialogCtx) => _PackageActionsDialog(
        packageId: entry.packageId,
        itemId: specificItem.id,
        fallbackEntry: entry,
        entryDate: widget.package.entryDate ?? widget.package.createdAt,
        onRelease: (held, slots) async {
          return await _showReleaseConfirmation(ctx, held,
              preselectedQty: slots.length, packageNumbers: slots);
        },
        onDispose: (held, type, slots) async {
          return await _showDispositionDialog(ctx, held, type,
              preselectedQty: slots.length, packageNumbers: slots);
        },
        // On a successful action: instead of closing the details dialog (which
        // dumped the user back to the warehouse page, resetting it to the first
        // tab), re-open the SAME package's details with fresh data so the
        // action's result is reflected and the user stays in context.
        onCompleted: () => _reopenWithFreshData(ctx, entry),
      ),
    );
  }

  /// Refresh providers after an in-dialog action so the warehouse list
  /// (behind the dialog) stays in sync. The dialog itself stays open and alive —
  /// no pop/re-open so the entry animation does not replay.
  void _reopenWithFreshData(BuildContext ctx, WarehouseEntryModel oldEntry) {
    ref.read(packagesRefreshTriggerProvider.notifier).trigger();
    ref.read(warehouseRefreshTriggerProvider.notifier).trigger();
    ref.invalidate(packageDataProvider(oldEntry.packageId));
    ref.invalidate(liveWarehouseEntriesProvider(oldEntry.warehouseId));
    ref.invalidate(livePackagesProvider);
    ref.invalidate(allWarehouseEntriesProvider);
  }

  /// Opens the final-disposition picker for an abandoned/forfeit item.
  /// Release / Re-export / Other are admin-only (hidden for officers).
  void _showFinalDispositionDialog(
    BuildContext ctx, {
    required PackageItem item,
    required WarehouseEntryModel? entry,
    required bool isOfficer,
  }) {
    final qty = entry?.itemCount ?? item.effectiveQuantity;
    showDialog(
      context: ctx,
      builder: (dialogCtx) => _FinalDispositionDialog(
        item: item,
        qty: qty,
        isOfficer: isOfficer,
        // Restrict the enabled action to the Appeal Directorate's decision.
        decisionCode: widget.appealDecisionCode,
        // When a Sale/Destroy request handler is supplied (Forfeited screen),
        // those two route to the Central Disposal request flow instead of
        // writing a [FINAL:…] entry directly.
        onRequestDisposal: widget.onSaleOrDestroyRequest == null
            ? null
            : (String disposition) {
                Navigator.pop(dialogCtx); // close the picker
                Navigator.pop(ctx); // close the details dialog
                widget.onSaleOrDestroyRequest!(disposition);
              },
        onConfirm: (String type, String? notes, DateTime date) async {
          Navigator.pop(dialogCtx);

          // Capture everything that reads from a BuildContext BEFORE popping —
          // this State's own context is torn down with the dialog, so looking
          // any of it up afterwards would fail.
          final messenger = material.ScaffoldMessenger.maybeOf(ctx);
          final successColour = context.colors.successGreen;
          final failColour = context.colors.dangerRed;

          // Close the details dialog BEFORE the write, not after it.
          //
          // Popping last meant the popup stayed on screen through the round
          // trip AND the invalidations that follow it, so the goods had
          // already vanished from the table behind it while the dialog sat
          // there. The write does not need this dialog, and the page it
          // returns to refreshes itself.
          Navigator.pop(ctx);

          try {
            await ref.read(warehouseServiceProvider).recordFinalDisposition(
                  packageItemId: item.id,
                  dispositionType: type,
                  qty: qty,
                  notes: notes,
                  dispositionDate: date,
                );
            // Refresh every affected view so the item leaves the Forfeited /
            // Other-manageable list and appears on its outcome page — the item's
            // status just changed but no realtime fires on package_items alone.
            ref.read(packagesRefreshTriggerProvider.notifier).trigger();
            ref.invalidate(livePackagesProvider);
            ref.invalidate(packageDataProvider(widget.package.id));
            ref.invalidate(forfeitedPackagesProvider);
            ref.invalidate(requestableForfeitedPackagesProvider);
            ref.invalidate(allItemAppealOutcomesProvider);
            messenger?.showSnackBar(
              material.SnackBar(
                content: Text('Final disposition recorded: $type'),
                backgroundColor: successColour,
              ),
            );
          } catch (e) {
            messenger?.showSnackBar(
              material.SnackBar(
                content: Text('Failed: $e'),
                backgroundColor: failColour,
              ),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.package;
    String officerDisplay = 'Unknown Officer';
    String? salaryNumber;

    if (p.inspectedByName != null) {
      // Extract salary number if it's in the name format "(Salary No: XXXXX)"
      final match =
          RegExp(r'\(Salary No:\s*(\d+)\)').firstMatch(p.inspectedByName!);
      if (match != null) {
        salaryNumber = match.group(1);
      }
      // Clean up officer name - remove salary number if included
      officerDisplay =
          p.inspectedByName!.replaceAll(RegExp(r'\s*\(Salary No:.*?\)'), '');
    } else if (p.inspectedBy != null) {
      officerDisplay = 'ID: ${p.inspectedBy}';
    } else if (_isLoadingCreator) {
      officerDisplay = 'Loading...';
    } else if (_creatorFallback != null) {
      officerDisplay = _creatorFallback!;
    }

    // Use badge number if available, otherwise use extracted salary number
    final displayBadgeNumber =
        (p.inspectedByBadge != null && p.inspectedByBadge!.isNotEmpty)
            ? p.inspectedByBadge
            : salaryNumber;

    // Get current user's role to conditionally disable update button
    final currentProfile = ref.watch(currentProfileProvider);
    final isOfficer = currentProfile?.role == 'officer';
    // Editing a package is strictly admin-only.
    final canUpdatePackage = currentProfile?.isAdmin ?? false;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOld = p.oldSrNumber != null && p.oldSrNumber!.trim().isNotEmpty;

    // Resolve which package item this popup is about. [highlightItemId] is the
    // caller's explicit choice (e.g. the Abandoned/Other table row's own item)
    // and takes priority — it's authoritative even when a [highlightEntry] is
    // also supplied, because an entry may be package-level (packageItemId null)
    // or reference a sibling item, which would otherwise resolve to the WRONG
    // item via the orElse fallback and break the Final Disposition gating.
    final highlightedItem = (widget.highlightItemId != null &&
            p.items.any((i) => i.id == widget.highlightItemId))
        ? p.items.firstWhere((i) => i.id == widget.highlightItemId)
        : (widget.highlightEntry != null
            ? p.items.firstWhere(
                (i) => i.id == widget.highlightEntry!.packageItemId,
                orElse: () => p.items.first)
            : null);

    // Show ONLY the item this popup is about whenever it's known (via
    // highlightItemId OR a highlightEntry) — a decided/forfeited item may have
    // no warehouse entry, so relying on highlightEntry alone would fall back to
    // listing every sibling item. If no specific item is known, show all.
    final legacyItems = highlightedItem != null ? [highlightedItem] : p.items;
    final legacyEntries =
        (widget.useLegacySummary && widget.highlightEntry != null)
            ? [widget.highlightEntry!]
            // When an item is known (via entry OR highlightItemId), show only
            // that item's warehouse entries (the Central Disposal / Valuation
            // request popup goes through here). Package-level entries with no
            // packageItemId are kept too so legacy data still surfaces. If that
            // leaves nothing, fall back to all entries. Otherwise show all.
            : (highlightedItem != null)
                ? (() {
                    final matched = p.warehouseEntries
                        .where((e) =>
                            e.packageItemId == highlightedItem.id ||
                            e.packageItemId == null)
                        .toList();
                    return matched.isEmpty ? p.warehouseEntries : matched;
                  })()
                : p.warehouseEntries;

    int? displayQty;
    if (highlightedItem != null && widget.highlightEntry != null) {
      displayQty = widget.highlightEntry!.itemCount;
      if (displayQty == 1 &&
          highlightedItem.quantity > 1 &&
          !widget.highlightEntry!.isReturned) {
        final returnedSum = widget.package.warehouseEntries
            .where((e) => e.packageItemId == highlightedItem.id && e.isReturned)
            .fold(0, (sum, e) => sum + e.itemCount);
        displayQty = highlightedItem.quantity - returnedSum;
        if (displayQty! < 1) displayQty = 1;
      }
    }

    String? returnedReceiptNo;
    String? returnedReceiptDate;
    String? releaseNotesText;
    final returnNotes = widget.highlightEntry?.returnNotes;
    if (returnNotes != null && returnNotes.trim().isNotEmpty) {
      for (final part in returnNotes.split('|')) {
        final text = part.trim();
        if (text.toLowerCase().startsWith('receipt no:')) {
          final idx = text.indexOf(':');
          if (idx != -1) returnedReceiptNo = text.substring(idx + 1).trim();
        } else if (text.toLowerCase().startsWith('date:')) {
          final idx = text.indexOf(':');
          if (idx != -1) returnedReceiptDate = text.substring(idx + 1).trim();
        } else if (text.toLowerCase().startsWith('notes:')) {
          final idx = text.indexOf(':');
          if (idx != -1) releaseNotesText = text.substring(idx + 1).trim();
        }
      }
    }
    // The actual disposition date is stored on the entry as returnedAt.
    final String? releaseDateText = widget.highlightEntry?.returnedAt != null
        ? DateFormat('yyyy-MM-dd').format(widget.highlightEntry!.returnedAt!)
        : null;
    // Label that date by the disposition it records — the return_notes carry a
    // "[FINAL:RE-EXPORTED]" / "[FINAL:DESTROYED]" / "[RELEASED]" … tag, so the
    // popup reads "Re-export Date" / "Destroyed Date" instead of always
    // "Release Date".
    final String dispoDateLabel = (() {
      final n = widget.highlightEntry?.returnNotes?.toUpperCase() ?? '';
      if (n.contains('RE-EXPORT')) return 'Re-export Date';
      if (n.contains('DESTROY')) return 'Destroyed Date';
      if (n.contains('SOLD') || n.contains('SALE')) return 'Sold Date';
      if (n.contains('FORFEIT')) return 'Forfeit Date';
      if (n.contains('ABANDON')) return 'Abandoned Date';
      if (n.contains('OTHER')) return 'Disposition Date';
      return 'Release Date';
    })();
    // Warehouse charge counts from the SR-form Entry Date (not the warehouse
    // admit timestamp) → the release date, so the popup matches the release
    // dialog's figure. Falls back to admittedAt if the package has no entry date.
    double? releasedCharge;
    if (widget.highlightEntry != null && highlightedItem != null) {
      final e = widget.highlightEntry!;
      final chargeStart = p.entryDate ?? e.admittedAt;
      final tempEntry = WarehouseEntryModel(
        id: e.id,
        packageId: e.packageId,
        packageItemId: e.packageItemId,
        warehouseId: e.warehouseId,
        warehouseName: e.warehouseName,
        warehouseCode: e.warehouseCode,
        holdReason: e.holdReason,
        itemCount: e.itemCount,
        admittedAt: chargeStart,
        dailyRate: e.dailyRate,
        returnedAt: e.returnedAt,
      );
      releasedCharge = tempEntry
          .calculatePackageCharge([highlightedItem], widget.storageRate);
    }

    final highlightReturnedById = widget.highlightEntry?.returnedBy;
    final returnedOfficerDisplay = widget.highlightEntry?.returnedByName ??
        (highlightReturnedById != null &&
                highlightReturnedById == currentProfile?.id
            ? currentProfile?.fullName
            : null) ??
        'Unknown Officer';
    final returnedOfficerBadge = widget.highlightEntry?.returnedByBadge ??
        (highlightReturnedById != null &&
                highlightReturnedById == currentProfile?.id
            ? currentProfile?.badgeNumber
            : null);

    final _hs = highlightedItem?.status?.toLowerCase() ?? '';
    final isConfiscated = _hs == 'confiscated' ||
        _hs == 'forfeit' ||
        _hs == 'forfiet' ||
        _hs == 'abandoned' ||
        widget.highlightEntry?.isPackageConfiscated == true;

    // No-charge context: abandoned / forfeit / destroy. These items carry no
    // storage fee and no release receipt — so we show registration-form item
    // details instead of charge/receipt fields. A [FINAL:DESTROYED] disposition
    // entry is also no-charge even if the item status didn't update.
    final _entryNotesUpper =
        (widget.highlightEntry?.returnNotes ?? '').trim().toUpperCase();
    final isDestroyedEntry = _entryNotesUpper.startsWith('[FINAL:DESTROYED') ||
        _entryNotesUpper.startsWith('[DESTROY');
    final isReExportEntry = _entryNotesUpper.startsWith('[FINAL:RE-EXPORTED') ||
        _entryNotesUpper.startsWith('[RE-EXPORT');
    final isOtherEntry = _entryNotesUpper.startsWith('[FINAL:OTHER') ||
        _entryNotesUpper.startsWith('[OTHER');

    // No-charge context: abandoned / forfeit / destroy / re-export / other. These items carry no
    // storage fee and no release receipt — so we show registration-form item
    // details instead of charge/receipt fields.
    final isNoChargeContext = WarehouseEntryModel.isNoChargeStatus(_hs) ||
        _isAbandonOrForfeitEntry(widget.highlightEntry) ||
        isDestroyedEntry ||
        isReExportEntry ||
        isOtherEntry;

    // SOLD-via-tender context: declutter — no release receipt / warehouse
    // charges / packages-released fields (the Sale & Financial section covers it).
    final isSoldContext = _hs == 'sold' ||
        p.status?.toLowerCase() == 'sold' ||
        (widget.highlightEntry?.returnNotes?.toUpperCase().contains('SOLD') ??
            false);

    // ── "(This Action)" count label ──
    // For released items the second count reads "Released (This Receipt)".
    // For every other disposition (Forfeit / Abandoned / Re-export / Destroy /
    // Other-custom) we show the SAME pattern — Total Packages + the count of
    // packages handled by THIS specific action — using a label matching the
    // disposition type. The disposition key is read from the entry's returnNotes
    // tag (e.g. "[FORFEIT]"), falling back to the item status.
    String? _actionCountLabel;
    if (widget.highlightEntry != null && !isSoldContext) {
      final notes = (widget.highlightEntry!.returnNotes ?? '').trim();
      final m = RegExp(r'^\[([^\]]+)\](.*)').firstMatch(notes);
      if (m != null) {
        final raw = m.group(1)!.trim();
        final rawUpper = raw.toUpperCase();
        if (rawUpper.startsWith('OTHER:')) {
          // New "[OTHER: <text>]" tag — the custom text is inside the bracket.
          final customText = raw.substring(6).trim();
          _actionCountLabel =
              '${customText.isEmpty ? 'Other' : customText} (This Action)';
        } else if (raw == 'OTHER' || raw == 'FINAL:OTHER') {
          final dashIndex = notes.indexOf('—');
          if (dashIndex != -1) {
            final customText = notes.substring(dashIndex + 1).trim();
            _actionCountLabel = '$customText (This Action)';
          } else {
            _actionCountLabel = 'Other (This Action)';
          }
        } else {
          _actionCountLabel =
              '${_dispoLabel(raw.toUpperCase(), raw)} (This Action)';
        }
      } else if (isNoChargeContext) {
        // No disposition tag but a no-charge status (form-level forfeit/abandoned/
        // destroy) — label by the item status.
        String key = _hs.toUpperCase();
        if (key == 'FORFEIT' || key == 'FORFIET' || key == 'CONFISCATED') {
          key = 'FORFEIT';
        }
        _actionCountLabel = '${_dispoLabel(key, _hs)} (This Action)';
      }
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) {
          final v = _anim.value;
          return Transform.scale(
            scale: v,
            child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
          );
        },
        child: material.Container(
          width: 900,
          decoration: BoxDecoration(
            color: context.colors.scaffoldBg,
            borderRadius: BorderRadius.circular(24),
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              material.Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: BoxDecoration(
                  gradient: widget.headerAccentColor != null
                      ? LinearGradient(colors: [
                          widget.headerAccentColor!.withOpacity(0.15),
                          context.colors.cardDark,
                        ])
                      : LinearGradient(
                          colors: isDark
                              ? [
                                  context.colors.surfaceDark,
                                  context.colors.cardDark
                                ]
                              : [
                                  context.colors.customsBlue,
                                  context.colors.customsBlueDark
                                ],
                        ),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(23)),
                ),
                child: Row(
                  children: [
                    material.Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.inventory_2_rounded,
                          color: widget.headerAccentColor ??
                              context.colors.primaryGold,
                          size: 24),
                    )
                        .animate()
                        .scale(duration: 400.ms, curve: Curves.easeOutBack),
                    const Gap(16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                isOld
                                    ? 'OLD ENTRY (MIGRATED)'
                                    : 'SR REGISTER ENTRY',
                                style: material.TextStyle(
                                  color: widget.headerAccentColor ??
                                      (isOld
                                          ? context.colors.primaryGold
                                          : context.colors.primaryGold),
                                  fontSize: 11,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const Gap(8),
                              material.Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isOld
                                      ? context.colors.primaryGold
                                          .withOpacity(0.18)
                                      : context.colors.accentLightBlue
                                          .withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isOld
                                        ? context.colors.primaryGold
                                            .withOpacity(0.5)
                                        : context.colors.accentLightBlue
                                            .withOpacity(0.4),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  isOld
                                      ? 'Old SR: ${p.oldSrNumber}'
                                      : 'NEW ENTRY',
                                  style: material.TextStyle(
                                    color: isOld
                                        ? context.colors.primaryGold
                                        : context.colors.accentLightBlue,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                            ],
                          ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
                          const Gap(2),
                          Text(
                            p.srNumber,
                            style: const material.TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                              .animate()
                              .fadeIn(duration: 400.ms, delay: 150.ms)
                              .slideX(begin: -0.1),
                        ],
                      ),
                    ),
                    const Gap(12),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded,
                          color: Colors.white.withOpacity(0.7)),
                      splashRadius: 24,
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // ── Appeal decision banner ──
                      // Shown to the owning yard once the Appeal Directorate has
                      // released a hold with a decision.
                      if (widget.appealDecisionLabel != null &&
                          widget.appealDecisionLabel!.trim().isNotEmpty)
                        material.Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: context.colors.accentLightBlue
                                .withOpacity(0.10),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: context.colors.accentLightBlue
                                    .withOpacity(0.4)),
                          ),
                          child: Row(children: [
                            Icon(Icons.gavel_rounded,
                                color: context.colors.accentLightBlue,
                                size: 22),
                            const Gap(12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('APPEAL DIRECTORATE DECISION',
                                      style: material.TextStyle(
                                          color: context.colors.accentLightBlue,
                                          fontSize: 10,
                                          letterSpacing: 1.0,
                                          fontWeight: FontWeight.w800)),
                                  const Gap(2),
                                  Text(
                                    'Proceed with: ${widget.appealDecisionLabel}',
                                    style: material.TextStyle(
                                        color: context.colors.textPrimary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                          ]),
                        ),
                      // SR Register Information Section
                      _DetailSection(
                        title: 'SR Register Information',
                        icon: Icons.assignment_rounded,
                        delay: 100,
                        child: Column(
                          children: [
                              if (isOld) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: _DetailItem(
                                        icon: Icons.numbers_rounded,
                                        label: 'New SR Number',
                                        value: p.srNumber,
                                        valueColor:
                                            context.colors.accentLightBlue,
                                      ),
                                    ),
                                    const Gap(12),
                                    Expanded(
                                      child: _DetailItem(
                                        icon: Icons.history_edu_rounded,
                                        label: 'Old SR Number (Migrated)',
                                        value: p.oldSrNumber!,
                                        valueColor:
                                            context.colors.primaryGold,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _DetailItem(
                                        icon: Icons.history_rounded,
                                        label: 'Entry Type',
                                        value: 'Old Entry (Migrated)',
                                        valueColor:
                                            context.colors.primaryGold,
                                      ),
                                    ),
                                    const Gap(12),
                                    Expanded(
                                      child: _DetailItem(
                                        icon: Icons.calendar_today_rounded,
                                        label: 'Entry Date',
                                        value: p.entryDate != null
                                            ? DateFormat('yyyy-MM-dd')
                                                .format(p.entryDate!)
                                            : 'N/A',
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _DetailItem(
                                        icon: Icons.receipt_long_rounded,
                                        label: 'Cusdec No',
                                        value: p.cusdecNo ?? 'N/A',
                                      ),
                                    ),
                                    const Gap(12),
                                    Expanded(
                                      child: _DetailItem(
                                        icon: Icons.calendar_month_rounded,
                                        label: 'Cusdec Date',
                                        value: p.cusdecDate ?? 'N/A',
                                      ),
                                    ),
                                  ],
                                ),
                              ] else ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: _DetailItem(
                                        icon: Icons.numbers_rounded,
                                        label: 'SR Number',
                                        value: p.srNumber,
                                      ),
                                    ),
                                    const Gap(12),
                                    Expanded(
                                      child: _DetailItem(
                                        icon: Icons.fiber_new_rounded,
                                        label: 'Entry Type',
                                        value: 'New Entry (Standard)',
                                        valueColor:
                                            context.colors.accentLightBlue,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _DetailItem(
                                        icon: Icons.calendar_today_rounded,
                                        label: 'Entry Date',
                                        value: p.entryDate != null
                                            ? DateFormat('yyyy-MM-dd')
                                                .format(p.entryDate!)
                                            : 'N/A',
                                      ),
                                    ),
                                    const Gap(12),
                                    Expanded(
                                      child: _DetailItem(
                                        icon: Icons.receipt_long_rounded,
                                        label: 'Cusdec No',
                                        value: p.cusdecNo ?? 'N/A',
                                      ),
                                    ),
                                  ],
                                ),
                                _DetailItem(
                                  icon: Icons.calendar_month_rounded,
                                  label: 'Cusdec Date',
                                  value: p.cusdecDate ?? 'N/A',
                                ),
                              ],
                              _DetailItem(
                                icon: Icons.gavel_rounded,
                                label: 'Case Number',
                                value: p.caseNumber ?? 'N/A',
                              ),
                              _DetailItem(
                                icon: Icons.local_shipping_rounded,
                                label: 'Container Number',
                                value: p.containerNumber ?? 'N/A',
                              ),
                              // Package-level: one deposit per SR, taken at
                              // registration against the cost of destruction.
                              _DetailItem(
                                icon: Icons.savings_rounded,
                                label: 'Destroying Deposit',
                                value: p.destroyingDeposit == null
                                    ? 'N/A'
                                    : 'LKR ${NumberFormat('#,##0.##').format(p.destroyingDeposit)}',
                              ),
                              _DetailItem(
                                icon: Icons.description_rounded,
                                label: 'Package Description',
                                value:
                                    p.description ?? 'No description provided',
                              ),
                            ],
                          ),
                        ),

                      // Consignee Information Section
                      _DetailSection(
                        title: 'Consignee Information',
                        icon: Icons.person_pin_rounded,
                        delay: 200,
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _DetailItem(
                                    icon: Icons.person_rounded,
                                    label: 'Consignee Name',
                                    value: p.consigneeName,
                                  ),
                                ),
                                const Gap(12),
                                Expanded(
                                  child: _DetailItem(
                                    icon: Icons.badge_rounded,
                                    label: 'Declarant Name',
                                    value: p.declarantName ?? 'N/A',
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: _DetailItem(
                                    icon: Icons.home_rounded,
                                    label: 'Declarant Address',
                                    value: p.consigneeAddress ?? 'N/A',
                                  ),
                                ),
                                const Gap(12),
                                Expanded(
                                  child: _DetailItem(
                                    icon: Icons.phone_rounded,
                                    label: 'Declarant Phone Number',
                                    value: p.consigneePhone ?? 'N/A',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      if (widget.useLegacySummary ||
                          widget.useWarehouseSummary) ...[
                        _DetailSection(
                          title: 'Goods Details',
                          icon: Icons.shopping_bag_rounded,
                          delay: 300,
                          child: (widget.highlightEntry == null &&
                                  highlightedItem != null)
                              // No warehouse entry (form-level abandoned/"Other"
                              // item) — show a compact item card from the SR
                              // registration data.
                              ? _NoEntryItemCard(item: highlightedItem)
                              : (widget.highlightEntry == null ||
                                      highlightedItem == null)
                                  // No specific item/entry highlighted (e.g. the
                                  // Central Disposal request view) — fall back to
                                  // listing every package item so the popup still
                                  // shows full details, like the Forfeited screen.
                                  ? (legacyItems.isEmpty
                                      ? const _EmptyState(
                                          message: 'No released item details')
                                      : Column(
                                          children: [
                                            for (var i = 0;
                                                i < legacyItems.length;
                                                i++) ...[
                                              if (i > 0) const Gap(12),
                                              _NoEntryItemCard(
                                                  item: legacyItems[i]),
                                            ],
                                          ],
                                        ))
                                  : material.Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: context.colors.surfaceDark,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: context.colors.borderColor),
                                      ),
                                      child: isNoChargeContext
                                          ? Column(
                                              children: [
                                                _DetailItem(
                                                  icon: Icons
                                                      .label_important_rounded,
                                                  label: 'Goods Name',
                                                  value:
                                                      highlightedItem.itemName,
                                                ),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: _DetailItem(
                                                        icon: Icons
                                                            .view_in_ar_rounded,
                                                        label: 'Total Packages',
                                                        value:
                                                            '${highlightedItem.effectiveQuantity}',
                                                      ),
                                                    ),
                                                    const Gap(12),
                                                    Expanded(
                                                      child: _DetailItem(
                                                        icon: Icons
                                                            .inventory_2_rounded,
                                                        label:
                                                            _actionCountLabel ??
                                                                'Quantity',
                                                        value:
                                                            '${widget.highlightEntry!.itemCount}',
                                                        valueColor: context
                                                            .colors.primaryGold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: _DetailItem(
                                                        icon: Icons
                                                            .straighten_rounded,
                                                        label: 'Unit',
                                                        value: highlightedItem
                                                                    .unitOfMeasure ==
                                                                'Other'
                                                            ? (highlightedItem
                                                                    .unitOther ??
                                                                'Other')
                                                            : (highlightedItem
                                                                        .packagingLabel !=
                                                                    null
                                                                ? '${highlightedItem.effectiveQuantity} ${highlightedItem.effectiveUnit} (in ${highlightedItem.packagingLabel})'
                                                                : highlightedItem
                                                                    .effectiveUnit),
                                                      ),
                                                    ),
                                                    const Gap(12),
                                                    Expanded(
                                                      child: _DetailItem(
                                                        icon: Icons
                                                            .category_rounded,
                                                        label: 'Category',
                                                        value: (highlightedItem
                                                                    .category
                                                                    ?.isNotEmpty ==
                                                                true)
                                                            ? highlightedItem
                                                                .category!
                                                            : '—',
                                                      ),
                                                    ),
                                                    const Gap(12),
                                                    Expanded(
                                                      child: _DetailItem(
                                                        icon: Icons.tag_rounded,
                                                        label: 'HS Code',
                                                        value: (highlightedItem
                                                                    .hsCode
                                                                    ?.isNotEmpty ==
                                                                true)
                                                            ? highlightedItem
                                                                .hsCode!
                                                            : '—',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                _DetailItem(
                                                  icon: Icons.payments_rounded,
                                                  // The TOTAL, with the unit price beneath it — the same shape
                                                  // the Valuation column uses. This showed the bare unitValue
                                                  // under a label reading just "Value", while every table showed
                                                  // unitValue x quantity under that same word.
                                                  label: 'Value (total)',
                                                  value: 'LKR ${NumberFormat('#,##0.00').format(highlightedItem.unitValue * highlightedItem.quantity)}'
                                                      '  ·  @ ${NumberFormat('#,##0.00').format(highlightedItem.unitValue)} × ${highlightedItem.quantity}',
                                                ),
                                                if (highlightedItem
                                                        .goodsDescription
                                                        ?.isNotEmpty ==
                                                    true)
                                                  _DetailItem(
                                                    icon: Icons
                                                        .description_rounded,
                                                    label: 'Goods Description',
                                                    value: highlightedItem
                                                        .goodsDescription!,
                                                  ),
                                                if (highlightedItem
                                                        .reasons?.isNotEmpty ==
                                                    true)
                                                  _DetailItem(
                                                    icon: Icons
                                                        .warning_amber_rounded,
                                                    label:
                                                        'Post Status Activity',
                                                    value: highlightedItem
                                                        .reasons!,
                                                  ),
                                              ],
                                            )
                                          : Column(
                                              children: [
                                                _DetailItem(
                                                  icon: Icons
                                                      .label_important_rounded,
                                                  label: 'Goods Name',
                                                  value:
                                                      highlightedItem.itemName,
                                                ),
                                                // Total Packages + Unit — always
                                                // shown (incl. Sold context) so the
                                                // popup lists the full item detail.
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: _DetailItem(
                                                        icon: Icons
                                                            .view_in_ar_rounded,
                                                        label: 'Total Packages',
                                                        value:
                                                            '${highlightedItem.effectiveQuantity}',
                                                      ),
                                                    ),
                                                    const Gap(12),
                                                    Expanded(
                                                      child: _DetailItem(
                                                        icon: Icons
                                                            .straighten_rounded,
                                                        label: 'Unit',
                                                        value: highlightedItem
                                                                    .unitOfMeasure ==
                                                                'Other'
                                                            ? (highlightedItem
                                                                    .unitOther ??
                                                                'Other')
                                                            : (highlightedItem
                                                                        .packagingLabel !=
                                                                    null
                                                                ? '${highlightedItem.effectiveQuantity} ${highlightedItem.effectiveUnit} (in ${highlightedItem.packagingLabel})'
                                                                : highlightedItem
                                                                    .effectiveUnit),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                // Valuation / disposal context: how
                                                // many of the total were actually
                                                // sent for disposal (e.g. 6 of 10).
                                                if (widget.valuationQty !=
                                                        null &&
                                                    widget.valuationQty !=
                                                        highlightedItem
                                                            .effectiveQuantity)
                                                  _DetailItem(
                                                    icon:
                                                        Icons.outbound_rounded,
                                                    label: 'Sent for Disposal',
                                                    value:
                                                        '${widget.valuationQty} of ${highlightedItem.effectiveQuantity}',
                                                    valueColor: context
                                                        .colors.primaryGold,
                                                  ),
                                                // Warehouse-entry count (Remaining /
                                                // Released) only when an entry exists
                                                // (never in the Sold context).
                                                if (!isSoldContext &&
                                                    widget.highlightEntry !=
                                                        null)
                                                  _DetailItem(
                                                    icon: widget
                                                            .useWarehouseSummary
                                                        ? Icons
                                                            .inventory_2_rounded
                                                        : Icons
                                                            .keyboard_return_rounded,
                                                    label: widget
                                                            .useWarehouseSummary
                                                        ? 'Remaining (Current)'
                                                        : (_actionCountLabel ??
                                                            'Released (This Receipt)'),
                                                    value:
                                                        '${widget.highlightEntry!.itemCount}',
                                                    valueColor: widget
                                                            .useWarehouseSummary
                                                        ? context
                                                            .colors.primaryGold
                                                        : context.colors
                                                            .successGreen,
                                                  ),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: _DetailItem(
                                                        icon: Icons.tag_rounded,
                                                        label: 'HS Code',
                                                        value: (highlightedItem
                                                                    .hsCode
                                                                    ?.isNotEmpty ==
                                                                true)
                                                            ? highlightedItem
                                                                .hsCode!
                                                            : '—',
                                                      ),
                                                    ),
                                                    const Gap(12),
                                                    Expanded(
                                                      child: _DetailItem(
                                                        icon: Icons
                                                            .payments_rounded,
                                                        // Total, with the unit
                                                        // price beneath —
                                                        // matching the tables.
                                                        label: 'Value (total)',
                                                        value:
                                                            'LKR ${NumberFormat('#,##0.00').format(highlightedItem.unitValue * highlightedItem.quantity)}'
                                                                '  ·  @ ${NumberFormat('#,##0.00').format(highlightedItem.unitValue)} × ${highlightedItem.quantity}',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                if (highlightedItem
                                                        .goodsDescription
                                                        ?.isNotEmpty ==
                                                    true)
                                                  _DetailItem(
                                                    icon: Icons
                                                        .description_rounded,
                                                    label: 'Goods Description',
                                                    value: highlightedItem
                                                        .goodsDescription!,
                                                  ),
                                                if (highlightedItem
                                                        .reasons?.isNotEmpty ==
                                                    true)
                                                  _DetailItem(
                                                    icon: Icons
                                                        .warning_amber_rounded,
                                                    label:
                                                        'Post Status Activity',
                                                    value: highlightedItem
                                                        .reasons!,
                                                  ),
                                              ],
                                            ),
                                    ),
                        ),
                        // Valuation Directorate cost (Central Disposal /
                        // Valuation request popups) — shown next to the package's
                        // own declared value.
                        // Sealed while the sale is still open: show that the
                        // figure is deliberately withheld, not simply missing.
                        if (widget.valuationSealedUntilSale)
                          _DetailSection(
                            title: 'Valuation',
                            icon: Icons.lock_outline_rounded,
                            delay: 320,
                            child: material.Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: context.colors.surfaceDark,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: context.colors.borderColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SealedValuation(),
                                  const Gap(6),
                                  Text(SealedValuation.tooltip,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: context.colors.textMuted)),
                                ],
                              ),
                            ),
                          )
                        else if (widget.valuationUnitCost != null)
                          _DetailSection(
                            title: 'Valuation',
                            icon: Icons.calculate_rounded,
                            delay: 320,
                            child: material.Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: context.colors.surfaceDark,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: context.colors.borderColor),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _DetailItem(
                                      icon: Icons.sell_rounded,
                                      label: 'Valuation Cost / item',
                                      value:
                                          'LKR ${NumberFormat('#,##0').format(widget.valuationUnitCost)}',
                                    ),
                                  ),
                                  const Gap(12),
                                  Expanded(
                                    child: _DetailItem(
                                      icon: Icons.functions_rounded,
                                      label: widget.valuationQty != null
                                          ? 'Total (× ${widget.valuationQty})'
                                          : 'Total Valuation',
                                      value:
                                          'LKR ${NumberFormat('#,##0').format(widget.valuationTotalCost ?? widget.valuationUnitCost)}',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        // Per-round valuation + bids, for unsold packages.
                        // Also sealed: each round carries its own valuation.
                        if (widget.tenderHistoryFor != null &&
                            !widget.valuationSealedUntilSale)
                          TenderHistorySection(
                            forfeited: widget.tenderHistoryFor!,
                            qty: widget.valuationQty,
                          ),
                        if (!widget.useWarehouseSummary)
                          _DetailSection(
                            title: 'Warehouse Summary',
                            icon: Icons.warehouse_rounded,
                            delay: 350,
                            child: legacyEntries.isEmpty
                                // Even with no warehouse entry, surface the yard
                                // so the cross-yard directorate views still show
                                // where the package belongs.
                                ? (widget.yardLabel != null
                                    ? material.Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: context.colors.surfaceDark,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color:
                                                  context.colors.borderColor),
                                        ),
                                        child: _DetailItem(
                                          icon: Icons.maps_home_work_rounded,
                                          label: 'Yard',
                                          value: widget.yardLabel!,
                                        ),
                                      )
                                    : const _EmptyState(
                                        message: 'No warehouse details'))
                                : material.Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: context.colors.surfaceDark,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: context.colors.borderColor),
                                    ),
                                    child: Column(
                                      children: [
                                        if (widget.yardLabel != null)
                                          _DetailItem(
                                            icon: Icons.maps_home_work_rounded,
                                            label: 'Yard',
                                            value: widget.yardLabel!,
                                          ),
                                        _DetailItem(
                                          icon: Icons.warehouse_rounded,
                                          label: 'Warehouse',
                                          value: legacyEntries
                                              .map((e) => e.warehouseName.trim())
                                              .where((w) => w.isNotEmpty)
                                              .toSet()
                                              .join(', '),
                                        ),
                                        _DetailItem(
                                          icon: Icons.location_on_rounded,
                                          label: 'Zone',
                                          value: () {
                                            final zones = legacyEntries
                                                .map((e) {
                                                  final zn = e.zone?.trim();
                                                  if (zn != null &&
                                                      zn.isNotEmpty) {
                                                    return zn.toLowerCase().startsWith('zone')
                                                        ? zn
                                                        : 'Zone $zn';
                                                  }
                                                  return e.warehouseCode.trim().isNotEmpty
                                                      ? e.warehouseCode.trim()
                                                      : null;
                                                })
                                                .where((z) => z != null)
                                                .cast<String>()
                                                .toSet();
                                            return zones.isEmpty
                                                ? '—'
                                                : zones.join(', ');
                                          }(),
                                        ),
                                        _DetailItem(
                                          icon: Icons.calendar_month_rounded,
                                          label: 'Entry Date',
                                          value: (p.entryDate ??
                                                      legacyEntries
                                                          .first.admittedAt) !=
                                                  null
                                              ? DateFormat('yyyy-MM-dd').format(
                                                  p.entryDate ??
                                                      legacyEntries
                                                          .first.admittedAt)
                                              : '—',
                                        ),
                                        if (releaseDateText != null)
                                          _DetailItem(
                                            icon: Icons.event_available_rounded,
                                            label: dispoDateLabel,
                                            value: releaseDateText,
                                          ),
                                        if (!isNoChargeContext &&
                                            !isSoldContext) ...[
                                          if (releasedCharge != null)
                                            _DetailItem(
                                              icon: Icons.payments_rounded,
                                              label: 'Warehouse Charge',
                                              value:
                                                  'LKR ${NumberFormat('#,##0.00').format(releasedCharge)}',
                                              valueColor:
                                                  context.colors.successGreen,
                                            ),
                                          _DetailItem(
                                            icon: Icons.receipt_long_rounded,
                                            label: 'Receipt No',
                                            value: returnedReceiptNo ?? '—',
                                          ),
                                          _DetailItem(
                                            icon: Icons.event_rounded,
                                            label: 'Receipt Date',
                                            value: returnedReceiptDate ?? '—',
                                          ),
                                        ],
                                        if (releaseNotesText != null &&
                                            releaseNotesText.isNotEmpty)
                                          _DetailItem(
                                            icon: Icons.notes_rounded,
                                            label: 'Release Notes',
                                            value: releaseNotesText,
                                          ),
                                      ],
                                    ),
                                  ),
                          ),
                      ] else
                        _DetailSection(
                          title: 'Package Item Summary',
                          icon: Icons.inventory_2_rounded,
                          delay: 300,
                          child: p.items.isEmpty
                              ? const _EmptyState(message: 'No package items')
                              : Column(
                                  children: p.items.map((item) {
                                    final relatedEntries = p.warehouseEntries
                                        .where(
                                            (e) => e.packageItemId == item.id)
                                        .toList();
                                    final heldQty = relatedEntries
                                        .where((e) => !e.isReturned)
                                        .fold<int>(
                                            0, (sum, e) => sum + e.itemCount);

                                    final currentWarehouses = relatedEntries
                                        .where((e) => !e.isReturned)
                                        .map((e) => e.warehouseName)
                                        .toSet()
                                        .toList();

                                    // ── Categorize returned entries by disposition ──
                                    // Releases carry no [STATUS] prefix in returnNotes;
                                    // dispositions are tagged e.g. [FORFEIT], [RE-EXPORT].
                                    final _returnedEntries = relatedEntries
                                        .where((e) => e.isReturned)
                                        .toList();
                                    int _releasedQty = 0;
                                    String? _releasedOfficer;
                                    double _releasedChargesPaid = 0;
                                    final Map<String, int> _dispoCounts = {};
                                    final Map<String, String?> _dispoOfficers =
                                        {};
                                    final Map<String, String> _dispoRawLabel =
                                        {};
                                    for (final e in _returnedEntries) {
                                      final notes =
                                          (e.returnNotes ?? '').trim();
                                      final m = RegExp(r'^\[([^\]]+)\]')
                                          .firstMatch(notes);
                                      final officer =
                                          e.returnedByName ?? e.returnedByBadge;
                                      if (m == null) {
                                        _releasedQty += e.itemCount;
                                        _releasedOfficer ??= officer;
                                        _releasedChargesPaid += e
                                            .calculatePackageCharge(
                                                [item], widget.storageRate);
                                      } else {
                                        final raw = m.group(1)!.trim();
                                        final key = raw.toUpperCase();
                                        _dispoCounts[key] =
                                            (_dispoCounts[key] ?? 0) +
                                                e.itemCount;
                                        _dispoOfficers[key] ??= officer;
                                        _dispoRawLabel[key] = raw;
                                      }
                                    }

                                    final _itemStatus =
                                        item.status?.toLowerCase() ?? '';
                                    final isItemForfeited =
                                        _itemStatus == 'confiscated' ||
                                            _itemStatus == 'forfeit' ||
                                            _itemStatus == 'forfeited' ||
                                            _itemStatus == 'forfiet';
                                    final isItemAbandoned =
                                        _itemStatus == 'abandoned';
                                    final isItemDetained =
                                        _itemStatus == 'detained' ||
                                            _itemStatus == 'detain';
                                    final isItemReexport =
                                        _itemStatus == 're-export';
                                    final isItemDestroy =
                                        _itemStatus == 'destroy';
                                    final isItemDisposed =
                                        isItemReexport || isItemDestroy;
                                    final isItemConfiscated = isItemForfeited;
                                    final isItemTerminal = isItemForfeited ||
                                        isItemAbandoned ||
                                        isItemDetained ||
                                        isItemDisposed;
                                    // A custom ("Other") status — anything that
                                    // is not a known disposition and not a
                                    // neutral working/left-yard state — should
                                    // still get a status badge in this card.
                                    const _neutralStatuses = {
                                      '',
                                      'pending',
                                      'held',
                                      'inspecting',
                                      'returned',
                                      'released',
                                      'sold',
                                      're-exported',
                                      'destroyed',
                                    };
                                    final isItemOther = !isItemTerminal &&
                                        !_neutralStatuses.contains(_itemStatus);
                                    // A fully-released item (all qty released, none
                                    // held, no other disposition) shows a RELEASED
                                    // badge instead of falling back to a neutral
                                    // 'returned' status with no badge.
                                    final isItemReleased = _releasedQty > 0 &&
                                        heldQty == 0 &&
                                        _dispoCounts.isEmpty;
                                    final showStatusBadge = isItemTerminal ||
                                        isItemOther ||
                                        isItemReleased;

                                    // Status-specific color
                                    Color _statusColor() {
                                      if (isItemForfeited)
                                        return const Color(0xFFE53935);
                                      if (isItemAbandoned)
                                        return const Color(0xFF9E9E9E);
                                      if (isItemDetained)
                                        return const Color(0xFFFF8F00);
                                      if (isItemReexport)
                                        return const Color(0xFF00ACC1);
                                      if (isItemDestroy)
                                        return const Color(0xFFE64A19);
                                      if (isItemReleased)
                                        return context.colors.successGreen;
                                      if (isItemOther)
                                        return context.colors.accentLightBlue;
                                      return context.colors.borderColor;
                                    }

                                    final itemStatusColor = _statusColor();

                                    // Status label for badge
                                    String _statusLabel() {
                                      if (isItemForfeited) return 'FORFEITED';
                                      if (isItemAbandoned) return 'ABANDONED';
                                      if (isItemDetained) return 'DETAINED';
                                      if (isItemReexport) return 'RE-EXPORT';
                                      if (isItemDestroy) return 'DESTROYED';
                                      if (isItemReleased) return 'RELEASED';
                                      if (isItemOther) {
                                        return (item.status ?? '')
                                            .toUpperCase();
                                      }
                                      return '';
                                    }

                                    return material.Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: isItemTerminal
                                            ? itemStatusColor.withOpacity(0.05)
                                            : context.colors.surfaceDark,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                            color: isItemTerminal
                                                ? itemStatusColor
                                                    .withOpacity(0.35)
                                                : context.colors.borderColor),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              top: 2),
                                                      child: Icon(
                                                          Icons
                                                              .label_important_rounded,
                                                          size: 16,
                                                          color: isItemTerminal
                                                              ? itemStatusColor
                                                              : context.colors
                                                                  .primaryGold),
                                                    ),
                                                    const Gap(12),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            item.itemName,
                                                            style: material
                                                                .TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 14,
                                                              color: isItemTerminal
                                                                  ? context
                                                                      .colors
                                                                      .textMuted
                                                                  : null,
                                                            ),
                                                          ),
                                                          if (item.category !=
                                                              null)
                                                            Text(item.category!,
                                                                style: material.TextStyle(
                                                                    color: context
                                                                        .colors
                                                                        .textMuted,
                                                                    fontSize:
                                                                        11)),
                                                          if (item.goodsDescription !=
                                                                  null &&
                                                              item.goodsDescription!
                                                                  .trim()
                                                                  .isNotEmpty)
                                                            Padding(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .only(
                                                                      top: 3),
                                                              child: Text(
                                                                item.goodsDescription!,
                                                                style: material
                                                                    .TextStyle(
                                                                  color: context
                                                                      .colors
                                                                      .textSecondary,
                                                                  fontSize: 12,
                                                                ),
                                                                maxLines: 2,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      if (showStatusBadge) ...[
                                                        material.Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal:
                                                                      10,
                                                                  vertical: 4),
                                                          decoration:
                                                              BoxDecoration(
                                                            color:
                                                                itemStatusColor
                                                                    .withOpacity(
                                                                        0.15),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        20),
                                                            border: Border.all(
                                                                color: itemStatusColor
                                                                    .withOpacity(
                                                                        0.4)),
                                                          ),
                                                          child: Text(
                                                            _statusLabel(),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: material
                                                                .TextStyle(
                                                              color:
                                                                  itemStatusColor,
                                                              fontSize: 10,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w900,
                                                              letterSpacing:
                                                                  0.5,
                                                            ),
                                                          ),
                                                        ),
                                                        const Gap(8),
                                                      ],
                                                      Text(
                                                        'x${item.effectiveQuantity}',
                                                        style:
                                                            material.TextStyle(
                                                          color: isItemTerminal
                                                              ? context.colors
                                                                  .textMuted
                                                              : context.colors
                                                                  .primaryGold,
                                                          fontWeight:
                                                              FontWeight.w900,
                                                          fontSize: 16,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          const Gap(12),
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: _DetailItem(
                                                  icon:
                                                      Icons.straighten_rounded,
                                                  label: 'Unit',
                                                  value: item.packagingLabel !=
                                                          null
                                                      ? '${item.effectiveQuantity} ${item.effectiveUnit} (in ${item.packagingLabel})'
                                                      : item.effectiveUnit,
                                                ),
                                              ),
                                              // Detain → show storage charges paid for
                                              // released portion. Forfeit/Abandoned →
                                              // hide value box (no charge). Else → Unit Value.
                                              if (isItemDetained) ...[
                                                const Gap(12),
                                                Expanded(
                                                  child: _DetailItem(
                                                    icon: Icons
                                                        .price_check_rounded,
                                                    label: 'Charges Paid',
                                                    value:
                                                        'LKR ${NumberFormat('#,##0.00').format(_releasedChargesPaid)}',
                                                    valueColor: context
                                                        .colors.successGreen,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: _DetailItem(
                                                  icon: Icons.tag_rounded,
                                                  label: 'HS Code',
                                                  value: (item.hsCode
                                                              ?.isNotEmpty ==
                                                          true)
                                                      ? item.hsCode!
                                                      : '—',
                                                ),
                                              ),
                                              const Gap(12),
                                              Expanded(
                                                child: _DetailItem(
                                                  icon: Icons.payments_rounded,
                                                  // The TOTAL, with the unit price beneath it — the same shape
                                                  // the Valuation column uses. This showed the bare unitValue
                                                  // under a label reading just "Value", while every table showed
                                                  // unitValue x quantity under that same word.
                                                  label: 'Value (total)',
                                                  value: 'LKR ${NumberFormat('#,##0.00').format(item.unitValue * item.quantity)}'
                                                      '  ·  @ ${NumberFormat('#,##0.00').format(item.unitValue)} × ${item.quantity}',
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (item.reasons != null &&
                                              item.reasons!.isNotEmpty)
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    material.Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              8),
                                                      decoration: BoxDecoration(
                                                        color: context
                                                            .colors.dangerRed
                                                            .withOpacity(0.1),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(10),
                                                      ),
                                                      child: Icon(
                                                        Icons
                                                            .warning_amber_rounded,
                                                        size: 16,
                                                        color: context
                                                            .colors.dangerRed,
                                                      ),
                                                    ),
                                                    const Gap(12),
                                                    Text(
                                                      'Reason',
                                                      style: material.TextStyle(
                                                        color: context
                                                            .colors.textMuted,
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        letterSpacing: 0.5,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const Gap(8),
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          bottom: 12),
                                                  child: Wrap(
                                                    spacing: 8,
                                                    runSpacing: 8,
                                                    children: item.reasons!
                                                        .split(',')
                                                        .map((reason) =>
                                                            material.Container(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                      horizontal:
                                                                          12,
                                                                      vertical:
                                                                          8),
                                                              decoration:
                                                                  BoxDecoration(
                                                                color: context
                                                                    .colors
                                                                    .dangerRed
                                                                    .withOpacity(
                                                                        0.05),
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            10),
                                                                border:
                                                                    Border.all(
                                                                  color: context
                                                                      .colors
                                                                      .dangerRed
                                                                      .withOpacity(
                                                                          0.2),
                                                                ),
                                                              ),
                                                              child: Text(
                                                                reason.trim(),
                                                                style: material
                                                                    .TextStyle(
                                                                  color: context
                                                                      .colors
                                                                      .dangerRed,
                                                                  fontSize: 12,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                              ),
                                                            ))
                                                        .toList(),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          if (currentWarehouses.isNotEmpty)
                                            _DetailItem(
                                              icon: Icons.warehouse_rounded,
                                              label: 'Current Warehouse',
                                              value: currentWarehouses.first,
                                            ),
                                          // Show the Disposition Breakdown whenever
                                          // the item is still held (detained) OR has
                                          // any released / disposed portion — so a
                                          // released item shows "Released x20" even
                                          // if its status isn't 'detained'.
                                          if (isItemDetained ||
                                              _releasedQty > 0 ||
                                              _dispoCounts.isNotEmpty) ...[
                                            const Gap(16),
                                            material.Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: context.colors.cardDark,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: context
                                                      .colors.borderColor,
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  material.Text(
                                                    'Disposition Breakdown',
                                                    style: material.TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: context
                                                          .colors.textPrimary,
                                                    ),
                                                  ),
                                                  const Gap(12),
                                                  _DispositionRow(
                                                    label: 'Currently Held',
                                                    count: heldQty,
                                                    color: context
                                                        .colors.primaryGold,
                                                    officer: null,
                                                  ),
                                                  if (_releasedQty > 0) ...[
                                                    const Gap(12),
                                                    _DispositionRow(
                                                      label: 'Released',
                                                      count: _releasedQty,
                                                      color: context
                                                          .colors.successGreen,
                                                      officer:
                                                          _releasedOfficer ??
                                                              'Unknown Officer',
                                                    ),
                                                  ],
                                                  // Each disposition type parsed from
                                                  // returnNotes (Forfeit, Re-export,
                                                  // Abandoned, Destroy, Other custom)
                                                  ..._dispoCounts.entries
                                                      .map((entry) {
                                                    return Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              top: 12),
                                                      child: _DispositionRow(
                                                        label: _dispoLabel(
                                                            entry.key,
                                                            _dispoRawLabel[entry
                                                                    .key] ??
                                                                entry.key),
                                                        count: entry.value,
                                                        color: _dispoColor(
                                                            entry.key),
                                                        officer: _dispoOfficers[
                                                                entry.key] ??
                                                            'Unknown Officer',
                                                      ),
                                                    );
                                                  }),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                        ),
                      const Gap(16),

                      // Officer Notice Section
                      if (p.notes != null && p.notes!.isNotEmpty) ...[
                        _DetailSection(
                          title: 'Officer Notice',
                          icon: Icons.notification_important_rounded,
                          delay: 400,
                          child: _NoteDisplay(
                            text: p.notes!,
                            isWarning: true,
                            icon: Icons.warning_amber_rounded,
                          ),
                        ),
                        const Gap(16),
                      ],

                      // Entry Person Section
                      _SystemEntrySection(
                        officerDisplay: officerDisplay,
                        badgeNumber: displayBadgeNumber,
                        delay: 500,
                      ),
                      const Gap(16),

                      // Released By Section
                      // For dispositions like Destroy/Re-export/Other, we change the label and icon.
                      if (!widget.useWarehouseSummary &&
                          widget.highlightEntry?.isReturned == true &&
                          !isSoldContext &&
                          (!isNoChargeContext ||
                              isDestroyedEntry ||
                              isReExportEntry ||
                              isOtherEntry)) ...[
                        material.Builder(builder: (context) {
                          String returnedOfficerTitle = 'Released By';
                          IconData returnedOfficerIcon =
                              Icons.keyboard_return_rounded;

                          if (isDestroyedEntry) {
                            returnedOfficerTitle = 'Destroyed By';
                            returnedOfficerIcon = Icons.delete_forever_rounded;
                          } else if (isReExportEntry) {
                            returnedOfficerTitle = 'Re-exported By';
                            returnedOfficerIcon = Icons.flight_takeoff_rounded;
                          } else if (isOtherEntry) {
                            String customText = 'Actioned';
                            final notes =
                                (widget.highlightEntry?.returnNotes ?? '')
                                    .trim();
                            // New "[OTHER: <text>]" tag — the disposition label
                            // lives inside the bracket.
                            final bracket = RegExp(r'^\[OTHER:\s*([^\]]*)\]',
                                    caseSensitive: false)
                                .firstMatch(notes);
                            if (bracket != null &&
                                bracket.group(1)!.trim().isNotEmpty) {
                              customText = bracket.group(1)!.trim();
                            } else {
                              // Legacy "[…] — <text>" form.
                              final m = RegExp(r'^\[([^\]]+)\](.*)')
                                  .firstMatch(notes);
                              if (m != null) {
                                final dashIndex = notes.indexOf('—');
                                if (dashIndex != -1) {
                                  customText =
                                      notes.substring(dashIndex + 1).trim();
                                } else {
                                  customText = 'Other';
                                }
                              }
                            }
                            returnedOfficerTitle = '$customText By';
                            returnedOfficerIcon = Icons.more_horiz_rounded;
                          }

                          return _SystemEntrySection(
                            officerDisplay: returnedOfficerDisplay,
                            badgeNumber: returnedOfficerBadge,
                            delay: 550,
                            customTitle: returnedOfficerTitle,
                            customIcon: returnedOfficerIcon,
                          );
                        }),
                        const Gap(16),
                      ],

                      // Skip on legacy summary — Receipt No/Date already shown in
                      // the Package Item Summary section above (avoids a duplicate).
                      if (!widget.useLegacySummary &&
                          !widget.useWarehouseSummary &&
                          widget.highlightEntry?.isReturned == true &&
                          (returnedReceiptNo != null ||
                              returnedReceiptDate != null)) ...[
                        _DetailSection(
                          title: 'Receipt Details',
                          icon: Icons.receipt_long_rounded,
                          delay: 560,
                          child: Row(
                            children: [
                              if (returnedReceiptNo != null)
                                Expanded(
                                  child: _DetailItem(
                                    icon: Icons.receipt_rounded,
                                    label: 'Receipt No',
                                    value: returnedReceiptNo!,
                                  ),
                                ),
                              if (returnedReceiptNo != null &&
                                  returnedReceiptDate != null)
                                const Gap(12),
                              if (returnedReceiptDate != null)
                                Expanded(
                                  child: _DetailItem(
                                    icon: Icons.event_rounded,
                                    label: 'Receipt Date',
                                    value: returnedReceiptDate!,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const Gap(16),
                      ],

                      // Warehouse Charges Section — hidden for no-charge
                      // (abandoned / forfeit / destroy) items and sold items.
                      // Skipped on legacy summary (charge shown in the summary
                      // above, entry-date based).
                      if (!widget.useLegacySummary &&
                          widget.highlightEntry != null &&
                          !isNoChargeContext &&
                          !isSoldContext)
                        _DetailSection(
                          title: 'Warehouse Charges',
                          icon: Icons.payments_rounded,
                          delay: 600,
                          child: Column(
                            children: [
                              _DetailItem(
                                icon: Icons.calculate_rounded,
                                label: 'Storage Fee (LKR)',
                                value:
                                    'LKR ${NumberFormat('#,##0.00').format(widget.highlightEntry!.calculatePackageCharge([
                                      highlightedItem!
                                    ], widget.storageRate))}',
                                valueColor: context.colors.successGreen,
                              ),
                            ],
                          ),
                        ),
                      if (() {
                        // Sold Packages page: always show Sale & Financial.
                        if (widget.isSoldPage) return true;

                        // All other pages: only show if entry is SOLD.
                        final entryNotes =
                            widget.highlightEntry?.returnNotes ?? '';
                        return entryNotes.toUpperCase().contains('SOLD');
                      }())
                        _SaleFinancialsSection(
                          package: p,
                          packageItemId: widget.highlightEntry?.packageItemId ??
                              widget.highlightItemId,
                          // Parse "[FINAL:SOLD] — Receipt: <no>" so the correct
                          // TSI row (price/taxes) is shown when an item was sold
                          // across several partial tenders.
                          receipt: (() {
                            final m = RegExp(r'Receipt:\s*([^\|—]+)',
                                    caseSensitive: false)
                                .firstMatch(
                                    widget.highlightEntry?.returnNotes ?? '');
                            return m?.group(1)?.trim();
                          }()),
                          // Who recorded the sale — shown here instead of in the
                          // Sold table.
                          soldBy: widget.highlightEntry?.returnedByName ??
                              widget.highlightEntry?.returnedByBadge,
                          // Prefer the caller's figure; fall back to the
                          // highlighted entry's own count so the popup still
                          // agrees with the row when no qty was passed.
                          valuationQty: widget.valuationQty ??
                              widget.highlightEntry?.itemCount,
                        ),
                      // Destroyed packages can also be delivered out — show a
                      // Delivered/Pending section with a Mark Delivered button
                      // (yard-side), mirroring the Sale & Financial section.
                      if (isDestroyedEntry)
                        _DestructionDeliverySection(
                          package: p,
                          packageItemId: widget.highlightEntry?.packageItemId,
                          valuationQty: widget.valuationQty ??
                              widget.highlightEntry?.itemCount,
                        ),
                      if (widget.srFinancials != null)
                        _DisposalExpensesSection(sr: widget.srFinancials!),
                    ],
                  ),
                ),
              ),
              if (widget.useWarehouseSummary || widget.allowEdit)
                material.Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.grey.shade50,
                    border: Border(
                        top: BorderSide(color: context.colors.borderColor)),
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(23)),
                  ),
                  child: Row(
                    children: [
                      material.Tooltip(
                        message: !canUpdatePackage
                            ? 'Package updates are restricted to DC / SDDC officers only'
                            : '',
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: canUpdatePackage
                                ? context.colors.primaryGold
                                : Colors.grey,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                          ),
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          label: const Text('Update'),
                          onPressed: !canUpdatePackage
                              ? null
                              : () {
                                  showDialog(
                                    context: context,
                                    builder: (_) => PackageUpdateDialog(
                                      package: p,
                                      highlightedItem: highlightedItem,
                                      highlightEntry: widget.highlightEntry,
                                      storageRate: widget.storageRate,
                                    ),
                                  );
                                },
                        ),
                      ),
                      const Gap(12),
                      // NOT offered on the WAREHOUSE dialog. Every status now
                      // has its own page (Detained / Abandoned / Forfeited /
                      // Other) where the goods are actioned, so the warehouse
                      // is a view of what it holds: look, and Update. The
                      // Appeal column in its table still shows where each item
                      // stands.
                      if (!widget.useWarehouseSummary &&
                          widget.highlightEntry != null &&
                          !widget.highlightEntry!.isReturned)
                        material.Tooltip(
                          message: isOfficer
                              ? 'Actions are restricted to DC / SDDC officers only'
                              : (isConfiscated
                                  ? 'Confiscated / Forfeited / Abandoned packages cannot be actioned'
                                  : ''),
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: (isConfiscated || isOfficer)
                                  ? Colors.grey
                                  : const Color(0xFF5C6BC0),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                            ),
                            icon: const Icon(Icons.bolt_rounded, size: 18),
                            label: const Text('Actions'),
                            // Officers can view but not action (same as Update).
                            onPressed: (isConfiscated || isOfficer)
                                ? null
                                : () => _showActionsDialog(
                                    context, widget.highlightEntry!,
                                    highlightedItem: highlightedItem),
                          ),
                        ),
                    ],
                  ),
                ),
              // ── Final Disposition footer ──
              // Shown for every appeal-expired item (allowFinalDisposition),
              // regardless of how it reached the Other/Abandoned table. Every
              // such item MUST still be actionable — Release / Re-export / Other
              // (recorded directly) or Sale / Destroy (Central Disposal request)
              // — so it can move on to its final-outcome table. Hidden only while
              // an appeal is still open, or once a FINAL disposition is recorded.
              // Footer action shows ONLY when the caller actually wires up the
              // disposition callback (Forfeited screen). Read-only viewers like
              // Central Disposal / Valuation pass no callback → no button.
              // NOT shown to the WAREHOUSE dialog, which is view + Update
              // only: goods are actioned on their own status page. The status
              // pages (Detained / Abandoned / Other / Forfeited) have no
              // Actions button, so this footer is their only route.
              if (widget.allowFinalDisposition &&
                  widget.onSaleOrDestroyRequest != null &&
                  !widget.useWarehouseSummary &&
                  (widget.useLegacySummary || widget.highlightItemId != null) &&
                  highlightedItem != null &&
                  (widget.forceFinalDisposition ||
                      !_hasFinalDisposition(p, highlightedItem.id)))
                material.Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.grey.shade50,
                    border: Border(
                        top: BorderSide(color: context.colors.borderColor)),
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(23)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Record the final outcome for these goods',
                          style: material.TextStyle(
                              color: context.colors.textMuted, fontSize: 12),
                        ),
                      ),
                      material.Tooltip(
                        message: isOfficer
                            ? 'Only DC / SDDC can record the final disposition'
                            : '',
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF5C6BC0),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor:
                                context.colors.textMuted.withOpacity(0.25),
                            disabledForegroundColor: context.colors.textMuted,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                          ),
                          icon: const Icon(Icons.outbound_rounded, size: 18),
                          label: const Text('Final Disposition'),
                          // Officers may view but never record the final
                          // disposition — the action is DC / SDDC only.
                          onPressed: isOfficer
                              ? null
                              : () => _showFinalDispositionDialog(
                                    context,
                                    item: highlightedItem,
                                    entry: widget.highlightEntry,
                                    isOfficer: isOfficer,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Generic footer action (e.g. Appeal Directorate Hold/Release) ──
              if (widget.footerActionLabel != null)
                material.Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.grey.shade50,
                    border: Border(
                        top: BorderSide(color: context.colors.borderColor)),
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(23)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.footerActionHint ?? '',
                          style: material.TextStyle(
                              color: context.colors.textMuted, fontSize: 12),
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.footerActionColor ??
                              context.colors.primaryGold,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                        ),
                        icon: Icon(
                            widget.footerActionIcon ?? Icons.check_rounded,
                            size: 18),
                        label: Text(widget.footerActionLabel!),
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onFooterAction?.call();
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisposalExpensesSection extends StatelessWidget {
  final SrFinancials sr;
  const _DisposalExpensesSection({required this.sr});

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0.00');
    final green = context.colors.successGreen;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _DetailSection(
      title: 'Disposal Expenses & Financials',
      icon: Icons.receipt_long_rounded,
      delay: 350,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _DetailItem(
                  icon: Icons.savings_rounded,
                  label: 'Destroying Deposit',
                  value: 'LKR ${money.format(sr.destroyingDeposit)}',
                  valueColor: green,
                ),
              ),
              const Gap(12),
              Expanded(
                child: _DetailItem(
                  icon: Icons.payments_rounded,
                  label: 'Total Expenses',
                  value: 'LKR ${money.format(sr.depositSpent)}',
                  valueColor:
                      sr.depositSpent > 0 ? context.colors.dangerRed : null,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _DetailItem(
                  icon: Icons.undo_rounded,
                  label: sr.deficit > 0 ? 'Shortfall' : 'Refund Amount',
                  value: sr.deficit > 0
                      ? '− LKR ${money.format(sr.deficit)}'
                      : 'LKR ${money.format(sr.refund)}',
                  valueColor: sr.deficit > 0 ? context.colors.dangerRed : green,
                ),
              ),
              const Gap(12),
              Expanded(
                child: _DetailItem(
                  icon: Icons.info_outline_rounded,
                  label: 'Expense Status',
                  value: sr.depositSpent == 0
                      ? 'Pending'
                      : (sr.deficit > 0 ? 'Shortfall' : 'Refundable'),
                  valueColor: sr.depositSpent == 0
                      ? context.colors.warningAmber
                      : (sr.deficit > 0 ? context.colors.dangerRed : green),
                ),
              ),
            ],
          ),
          const Gap(12),
          material.Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? context.colors.surfaceDark : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.colors.borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cost Breakdown',
                  style: material.TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Gap(8),
                Row(
                  children: [
                    Expanded(
                      child: _ExpenseCostBox(
                        label: 'Destruction',
                        amount: sr.destructionExpense,
                        color: context.colors.dangerRed,
                      ),
                    ),
                    const Gap(8),
                    Expanded(
                      child: _ExpenseCostBox(
                        label: 'Advertising',
                        amount: sr.advertisingExpense,
                        color: context.colors.warningAmber,
                      ),
                    ),
                    const Gap(8),
                    Expanded(
                      child: _ExpenseCostBox(
                        label: 'Labour',
                        amount: sr.labourExpense,
                        color: context.colors.accentLightBlue,
                      ),
                    ),
                  ],
                ),
                const Gap(8),
                Row(
                  children: [
                    Expanded(
                      child: _ExpenseCostBox(
                        label: 'Transport',
                        amount: sr.transportExpense,
                        color: context.colors.customsBlue,
                      ),
                    ),
                    const Gap(8),
                    Expanded(
                      child: _ExpenseCostBox(
                        label: 'Auction',
                        amount: sr.auctionExpense,
                        color: context.colors.primaryGold,
                      ),
                    ),
                    const Gap(8),
                    Expanded(
                      child: _ExpenseCostBox(
                        label: 'Deposit',
                        amount: sr.destroyingDeposit,
                        color: green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (sr.goods.isNotEmpty) ...[
            const Gap(14),
            material.Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    isDark ? context.colors.surfaceDark : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.colors.borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Goods Cost Distribution',
                    style: material.TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Gap(8),
                  Row(children: [
                    Expanded(
                        flex: 4,
                        child: Text('Goods Name',
                            style: TextStyle(
                                color: context.colors.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w700))),
                    Expanded(
                        child: Text('Qty',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                color: context.colors.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w700))),
                    Expanded(
                        flex: 2,
                        child: Text('Destruction',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                color: context.colors.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w700))),
                    Expanded(
                        flex: 2,
                        child: Text('Advertising',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                color: context.colors.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w700))),
                  ]),
                  material.Divider(
                      color: context.colors.borderColor, height: 12),
                  for (final g in sr.goods)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        Expanded(
                          flex: 4,
                          child: Text(g.goodsName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: context.colors.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ),
                        Expanded(
                          child: Text('${g.quantity}',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  color: context.colors.textSecondary,
                                  fontSize: 12)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                              g.destructionExpense == 0
                                  ? '—'
                                  : money.format(g.destructionExpense),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  color: g.destructionExpense == 0
                                      ? context.colors.textMuted
                                      : context.colors.dangerRed,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                              g.advertisingExpense == 0
                                  ? '—'
                                  : money.format(g.advertisingExpense),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  color: g.advertisingExpense == 0
                                      ? context.colors.textMuted
                                      : context.colors.warningAmber,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ]),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExpenseCostBox extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;

  const _ExpenseCostBox({
    required this.label,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0.00');
    return material.Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: material.TextStyle(
              color: context.colors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Gap(2),
          Text(
            amount == 0 ? '—' : 'LKR ${money.format(amount)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: material.TextStyle(
              color: amount == 0 ? context.colors.textMuted : color,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});
  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    final isPending = s.contains('pending');
    final isInspected = s.contains('inspected');
    final color = isPending
        ? context.colors.primaryGold
        : (isInspected ? context.colors.successGreen : Colors.blue);
    return material.Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          material.Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const Gap(6),
          Text(status.toUpperCase(),
              style: material.TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final int delay;

  const _DetailSection({
    required this.title,
    required this.icon,
    required this.child,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return material.Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? context.colors.surfaceDark.withOpacity(0.5)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          material.Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: context.colors.textPrimary.withOpacity(0.03),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
              border:
                  Border(bottom: BorderSide(color: context.colors.borderColor)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: context.colors.primaryGold),
                const Gap(10),
                Text(
                  title.toUpperCase(),
                  style: material.TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ).animate().slideX(
              delay: Duration(milliseconds: delay),
              duration: 300.ms,
              begin: -0.2),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ).animate().fadeIn(
              delay: Duration(milliseconds: delay + 100), duration: 400.ms),
        ],
      ),
    );
  }
}

class _DetailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? subValue;
  final Color? valueColor;

  const _DetailItem({
    required this.icon,
    required this.label,
    required this.value,
    this.subValue,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: material.Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.textPrimary.withOpacity(0.02),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: context.colors.borderColor.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            material.Container(
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
                  Text(
                    label,
                    style: material.TextStyle(
                      color: context.colors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Gap(2),
                  Text(
                    value,
                    style: material.TextStyle(
                      color: valueColor ?? context.colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (subValue != null) ...[
                    const Gap(2),
                    Text(
                      subValue!,
                      style: material.TextStyle(
                        color: context.colors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CargoItemTile extends StatelessWidget {
  final PackageItem item;
  final int index;

  const _CargoItemTile({required this.item, required this.index});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: material.Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.primaryGold.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: context.colors.primaryGold.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            material.Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: context.colors.primaryGold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: material.TextStyle(
                    color: context.colors.primaryGold,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.itemName,
                    style: material.TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  if (item.category != null)
                    Text(item.category!,
                        style: material.TextStyle(
                            color: context.colors.textMuted, fontSize: 11)),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      // "Value/unit", not "Value": the tables under the same
                      // word show unitValue × quantity.
                      'HS: ${(item.hsCode?.isNotEmpty == true) ? item.hsCode! : '—'}  ·  Value/unit: LKR ${NumberFormat('#,##0.00').format(item.unitValue)}',
                      style: material.TextStyle(
                          color: context.colors.textMuted, fontSize: 11),
                    ),
                  ),
                  if (item.reasons != null && item.reasons!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 10, color: context.colors.heldOrange),
                          const Gap(4),
                          Expanded(
                            child: Text(
                              item.reasons!,
                              style: material.TextStyle(
                                color: context.colors.heldOrange,
                                fontSize: 10,
                                fontStyle: FontStyle.italic,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Text(
              'x${item.quantity}',
              style: material.TextStyle(
                color: context.colors.primaryGold,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WarehouseHistoryTile extends StatelessWidget {
  final PackageModel package;
  final WarehouseEntryModel entry;
  final int index;
  final Map<DateTime, double> rate;
  final bool isHighlighted;
  final material.VoidCallback onRelease;

  const _WarehouseHistoryTile({
    required this.package,
    required this.entry,
    required this.index,
    required this.rate,
    required this.isHighlighted,
    required this.onRelease,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: material.Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isHighlighted
              ? context.colors.primaryGold.withOpacity(0.08)
              : context.colors.textPrimary.withOpacity(0.02),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isHighlighted
                ? context.colors.primaryGold.withOpacity(0.5)
                : context.colors.borderColor.withOpacity(0.5),
            width: isHighlighted ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                material.Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.colors.primaryGold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.warehouse_rounded,
                      size: 14, color: context.colors.primaryGold),
                ),
                const Gap(10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.warehouseName,
                        style: material.TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      ...entry.holdReason.split(',').map((reason) => Text(
                            reason.trim(),
                            style: material.TextStyle(
                                color: context.colors.textMuted, fontSize: 10),
                          )),
                    ],
                  ),
                ),
                if (entry.isReturned)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      material.Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: context.colors.successGreen.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('RELEASED',
                            style: material.TextStyle(
                                color: context.colors.successGreen,
                                fontSize: 9,
                                fontWeight: FontWeight.bold)),
                      ),
                      if (entry.returnedByName != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'By: ${entry.returnedByName}',
                            style: material.TextStyle(
                                color: context.colors.textMuted, fontSize: 9),
                          ),
                        ),
                    ],
                  )
                else
                  material.InkWell(
                    onTap: () {
                      final item = package.items
                          .where((i) => i.id == entry.packageItemId)
                          .firstOrNull;
                      final isConfiscated = item?.status == 'confiscated' ||
                          entry.isPackageConfiscated;
                      if (isConfiscated) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Confiscated items cannot be released'),
                                backgroundColor: Colors.red));
                        return;
                      }
                      onRelease();
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: material.Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: (package.items
                                        .where(
                                            (i) => i.id == entry.packageItemId)
                                        .firstOrNull
                                        ?.status ==
                                    'confiscated' ||
                                entry.isPackageConfiscated)
                            ? Colors.grey.withOpacity(0.15)
                            : context.colors.successGreen.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: (package.items
                                            .where((i) =>
                                                i.id == entry.packageItemId)
                                            .firstOrNull
                                            ?.status ==
                                        'confiscated' ||
                                    entry.isPackageConfiscated)
                                ? Colors.grey.withOpacity(0.4)
                                : context.colors.successGreen.withOpacity(0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_circle_fill_rounded,
                              size: 12,
                              color: (package.items
                                              .where((i) =>
                                                  i.id == entry.packageItemId)
                                              .firstOrNull
                                              ?.status ==
                                          'confiscated' ||
                                      entry.isPackageConfiscated)
                                  ? Colors.grey
                                  : context.colors.successGreen),
                          const Gap(6),
                          Text('RELEASE',
                              style: material.TextStyle(
                                  color: (package.items
                                                  .where((i) =>
                                                      i.id ==
                                                      entry.packageItemId)
                                                  .firstOrNull
                                                  ?.status ==
                                              'confiscated' ||
                                          entry.isPackageConfiscated)
                                      ? Colors.grey
                                      : context.colors.successGreen,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const Gap(6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'In: ${DateFormat('dd MMM yyyy').format(entry.admittedAt)}${entry.returnedAt != null ? "  Out: ${DateFormat('dd MMM yyyy').format(entry.returnedAt!)}" : ""}',
                  style: material.TextStyle(
                      color: context.colors.textMuted, fontSize: 10),
                ),
                if (entry.admittedByName != null)
                  Text(
                    'Entry by: ${entry.admittedByName}',
                    style: material.TextStyle(
                        color: context.colors.textMuted, fontSize: 10),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemEntrySection extends StatelessWidget {
  final String officerDisplay;
  final String? badgeNumber;
  final int delay;
  final String? customTitle;
  final IconData? customIcon;

  const _SystemEntrySection({
    required this.officerDisplay,
    this.badgeNumber,
    required this.delay,
    this.customTitle,
    this.customIcon,
  });

  @override
  Widget build(BuildContext context) {
    return material.Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            context.colors.primaryGold.withOpacity(0.1),
            context.colors.primaryGold.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.primaryGold.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              material.Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.colors.primaryGold.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(customIcon ?? Icons.verified_user_rounded,
                    size: 16, color: context.colors.primaryGold),
              ),
              const Gap(10),
              Text(
                (customTitle ?? 'System Entry By').toUpperCase(),
                style: material.TextStyle(
                  color: context.colors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const Gap(2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  officerDisplay,
                  style: material.TextStyle(
                    color: context.colors.primaryGold,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (badgeNumber != null && badgeNumber!.isNotEmpty)
                material.Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: context.colors.primaryGold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: context.colors.primaryGold.withOpacity(0.4)),
                  ),
                  child: Text(
                    'Salary No: $badgeNumber',
                    style: material.TextStyle(
                      color: context.colors.primaryGold,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ).animate().slideY(
        delay: Duration(milliseconds: delay), duration: 300.ms, begin: 0.1);
  }
}

class _SaleFinancialsSection extends ConsumerStatefulWidget {
  final PackageModel package;
  final String? packageItemId;

  /// Receipt number of THIS sale — pins the exact TSI row when one item was
  /// sold across several partial tenders (same package_item_id, distinct prices).
  final String? receipt;

  /// Officer who recorded the sale (shown here, not in the Sold table).
  final String? soldBy;

  /// Quantity this sale covers, as the table shows it. Without it the
  /// valuation row falls back to 1, because the sale query does not join
  /// package_items so `forfeited.packageDetails` is null here.
  final int? valuationQty;
  const _SaleFinancialsSection(
      {required this.package,
      this.packageItemId,
      this.receipt,
      this.soldBy,
      this.valuationQty});
  @override
  ConsumerState<_SaleFinancialsSection> createState() =>
      _SaleFinancialsSectionState();
}

class _SaleFinancialsSectionState
    extends ConsumerState<_SaleFinancialsSection> {
  bool _toggling = false;

  String get _saleItemKey =>
      '${widget.package.id}|${widget.packageItemId ?? ''}|${widget.receipt ?? ''}';

  Future<void> _toggleDelivery(TenderSaleItemModel item) async {
    setState(() => _toggling = true);
    final newValue = !item.isDelivered;
    try {
      await ref
          .read(disposalServiceProvider)
          .toggleDeliveryStatus(item.id, newValue);
      ref.invalidate(saleItemForPackageProvider(widget.package.id));
      ref.invalidate(saleItemForPackageItemProvider(_saleItemKey));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              newValue ? 'Marked as Delivered' : 'Marked as Not Delivered'),
          backgroundColor: newValue
              ? context.colors.successGreen
              : context.colors.warningAmber,
        ));
        // Close the details popup on success.
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: context.colors.dangerRed,
        ));
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(saleItemForPackageItemProvider(_saleItemKey));
    return async.when(
      loading: () => const material.Center(
        child: material.Padding(
            padding: EdgeInsets.all(16),
            child: material.CircularProgressIndicator()),
      ),
      error: (_, __) => const material.SizedBox.shrink(),
      data: (saleItem) {
        if (saleItem == null) return const material.SizedBox.shrink();

        double taxSum = 0;
        for (final t in saleItem.appliedTaxes) {
          taxSum += parseDbNum(t['amount']) ?? 0;
        }

        final profile = ref.watch(currentProfileProvider);
        // Only a yard (admin/officer) confirms delivery; Central Disposal views.
        final canEdit = profile != null && !profile.isDisposal;
        final delivered = saleItem.isDelivered;
        final actionColor = delivered
            ? context.colors.warningAmber
            : context.colors.successGreen;

        return _DetailSection(
          title: 'Sale & Financial Information',
          icon: Icons.sell_rounded,
          delay: 650,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.colors.surfaceDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.colors.borderColor),
            ),
            child: Column(
              children: [
                if (saleItem.receiptNumber?.trim().isNotEmpty == true)
                  _DetailItem(
                    icon: Icons.receipt_long_rounded,
                    label: 'Receipt No',
                    value: saleItem.receiptNumber!.trim(),
                  ),
                if (widget.soldBy?.trim().isNotEmpty == true)
                  _DetailItem(
                    icon: Icons.person_rounded,
                    label: 'Sold By',
                    value: widget.soldBy!.trim(),
                  ),
                // Valuation Directorate's valuation, for comparison with the
                // actual sold price below.
                if (() {
                  final fp = saleItem.forfeited;
                  return fp?.valuationCost != null;
                }())
                  _ValuationDetailRow(
                      fp: saleItem.forfeited!,
                      // The table's Qty column is the source of truth:
                      // the sale query does not join package_items, so
                      // fp.packageDetails is null here and the internal
                      // fallback would land on 1.
                      soldQty: widget.valuationQty),
                _DetailItem(
                  icon: Icons.payments_rounded,
                  label: 'Sold Price (Rs)',
                  value: saleItem.soldPrice.toStringAsFixed(2),
                ),
                if (saleItem.appliedTaxes.isNotEmpty)
                  ...saleItem.appliedTaxes.map((t) => _DetailItem(
                        icon: Icons.receipt_rounded,
                        label: '${t['name']} (${t['percentage']}%)',
                        value: ((t['amount'] as num?)?.toDouble() ?? 0)
                            .toStringAsFixed(2),
                      )),
                _DetailItem(
                  icon: Icons.account_balance_wallet_rounded,
                  label: 'Total Sale Value (Inc. Taxes)',
                  value: (saleItem.soldPrice + taxSum).toStringAsFixed(2),
                  valueColor: context.colors.primaryGold,
                ),
                _DetailItem(
                  icon: Icons.local_shipping_rounded,
                  label: 'Delivery Status',
                  value: delivered ? 'Delivered' : 'Pending',
                  valueColor: delivered
                      ? context.colors.successGreen
                      : context.colors.dangerRed,
                ),
                // Delivery date shown ONLY once delivered — the timestamp is
                // captured automatically when Mark Delivered is pressed.
                if (delivered && saleItem.deliveredAt != null)
                  _DetailItem(
                    icon: Icons.event_available_rounded,
                    label: 'Delivery Date',
                    value:
                        DateFormat('yyyy-MM-dd').format(saleItem.deliveredAt!),
                    valueColor: context.colors.successGreen,
                  ),
                // Only show the action while the package is still pending —
                // once delivered there is no "Mark as Not Delivered" revert.
                if (canEdit && !delivered) ...[
                  const Gap(10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed:
                          _toggling ? null : () => _toggleDelivery(saleItem),
                      icon: _toggling
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.local_shipping_rounded, size: 18),
                      label: const Text('Mark Delivered'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: actionColor,
                        side: BorderSide(color: actionColor.withOpacity(0.6)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Delivery section for a DESTROYED package — Delivered/Pending status + a
/// yard-side "Mark Delivered" button, mirroring the Sale & Financial section.
class _DestructionDeliverySection extends ConsumerStatefulWidget {
  final PackageModel package;
  final String? packageItemId;

  /// Quantity this destruction covers — see _SaleFinancialsSection.
  final int? valuationQty;
  const _DestructionDeliverySection(
      {required this.package, this.packageItemId, this.valuationQty});
  @override
  ConsumerState<_DestructionDeliverySection> createState() =>
      _DestructionDeliverySectionState();
}

class _DestructionDeliverySectionState
    extends ConsumerState<_DestructionDeliverySection> {
  bool _toggling = false;

  String get _key => '${widget.package.id}|${widget.packageItemId ?? ''}';

  Future<void> _toggle(DestructionItemModel item) async {
    setState(() => _toggling = true);
    final newValue = !item.delivered;
    try {
      await ref
          .read(disposalServiceProvider)
          .toggleDestructionDelivery(item.id, newValue);
      ref.read(destructionsRefreshProvider.notifier).trigger();
      ref.invalidate(destructionItemForPackageProvider(widget.package.id));
      ref.invalidate(destructionItemForPackageItemProvider(_key));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(material.SnackBar(
          content: material.Text(
              newValue ? 'Marked as Delivered' : 'Marked as Not Delivered'),
          backgroundColor: newValue
              ? context.colors.successGreen
              : context.colors.warningAmber,
        ));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(material.SnackBar(
          content: material.Text('Error: $e'),
          backgroundColor: context.colors.dangerRed,
        ));
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(destructionItemForPackageItemProvider(_key));
    return async.when(
      loading: () => const material.Center(
        child: material.Padding(
            padding: EdgeInsets.all(16),
            child: material.CircularProgressIndicator()),
      ),
      error: (_, __) => const material.SizedBox.shrink(),
      data: (item) {
        if (item == null) return const material.SizedBox.shrink();
        final profile = ref.watch(currentProfileProvider);
        // Only a yard (admin/officer) confirms delivery; Central Disposal views.
        final canEdit = profile != null && !profile.isDisposal;
        final delivered = item.delivered;
        final actionColor = delivered
            ? context.colors.warningAmber
            : context.colors.successGreen;
        return _DetailSection(
          title: 'Destruction & Delivery',
          icon: Icons.delete_forever_rounded,
          delay: 650,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.colors.surfaceDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.colors.borderColor),
            ),
            child: Column(
              children: [
                _DetailItem(
                  icon: Icons.delete_forever_rounded,
                  label: 'Status',
                  value: 'Destroyed',
                  valueColor: context.colors.dangerRed,
                ),
                // Receipt No + Notes are stored combined as
                // "Receipt No: <no> | Notes: <notes>" — split into two rows.
                if (_receiptNoOf(item.notes) != null)
                  _DetailItem(
                    icon: Icons.receipt_long_rounded,
                    label: 'Receipt No',
                    value: _receiptNoOf(item.notes)!,
                  ),
                if (_notesOf(item.notes) != null)
                  _DetailItem(
                    icon: Icons.notes_rounded,
                    label: 'Notes',
                    value: _notesOf(item.notes)!,
                  ),
                // Valuation Directorate valuation, for comparison.
                if (() {
                  final fp = item.forfeited;
                  return fp?.valuationCost != null;
                }())
                  _ValuationDetailRow(
                      fp: item.forfeited!, soldQty: widget.valuationQty),
                // Destruction records a price only — no taxes (unlike a sale).
                _DetailItem(
                  icon: Icons.payments_rounded,
                  label: 'Destruction Price (Rs)',
                  value: item.destroyedPrice.toStringAsFixed(2),
                  valueColor: context.colors.primaryGold,
                ),
                _DetailItem(
                  icon: Icons.local_shipping_rounded,
                  label: 'Delivery Status',
                  value: delivered ? 'Delivered' : 'Pending',
                  valueColor: delivered
                      ? context.colors.successGreen
                      : context.colors.dangerRed,
                ),
                // Delivery date shown ONLY once delivered — captured
                // automatically when Mark Delivered is pressed.
                if (delivered && item.deliveredAt != null)
                  _DetailItem(
                    icon: Icons.event_available_rounded,
                    label: 'Delivery Date',
                    value: DateFormat('yyyy-MM-dd').format(item.deliveredAt!),
                    valueColor: context.colors.successGreen,
                  ),
                if (canEdit && !delivered) ...[
                  const Gap(10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _toggling ? null : () => _toggle(item),
                      icon: _toggling
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.local_shipping_rounded, size: 18),
                      label: const Text('Mark Delivered'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: actionColor,
                        side: BorderSide(color: actionColor.withOpacity(0.6)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NoteDisplay extends StatelessWidget {
  final String text;
  final bool isWarning;
  final IconData? icon;

  const _NoteDisplay({required this.text, this.isWarning = false, this.icon});

  @override
  Widget build(BuildContext context) {
    return material.Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isWarning
            ? context.colors.primaryGold.withOpacity(0.05)
            : context.colors.textPrimary.withOpacity(0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (isWarning
                  ? context.colors.primaryGold
                  : context.colors.borderColor)
              .withOpacity(0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            material.Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: (isWarning
                        ? context.colors.primaryGold
                        : context.colors.textMuted)
                    .withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 14,
                color: isWarning
                    ? context.colors.primaryGold
                    : context.colors.textMuted,
              ),
            ),
            const Gap(12),
          ],
          Expanded(
            child: Text(
              text,
              style: material.TextStyle(
                color: context.colors.textPrimary,
                fontSize: 12,
                height: 1.5,
                fontWeight: isWarning ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;

  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_rounded,
                size: 32, color: context.colors.textMuted.withOpacity(0.4)),
            const Gap(2),
            Text(
              message,
              style: material.TextStyle(
                  color: context.colors.textMuted,
                  fontSize: 12,
                  fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact item-detail card shown when an abandoned / "Other" item has no
/// warehouse entry (registered on the SR form but never admitted). Uses the
/// item's registration data — no charges/receipts apply.
class _NoEntryItemCard extends StatelessWidget {
  final PackageItem item;
  const _NoEntryItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return material.Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        children: [
          _DetailItem(
            icon: Icons.label_important_rounded,
            label: 'Goods Name',
            value: item.itemName,
          ),
          Row(
            children: [
              Expanded(
                child: _DetailItem(
                  icon: Icons.view_in_ar_rounded,
                  label: 'Total Packages',
                  value: '${item.effectiveQuantity}',
                ),
              ),
              const Gap(12),
              Expanded(
                child: _DetailItem(
                  icon: Icons.straighten_rounded,
                  label: 'Unit',
                  value: item.unitOfMeasure == 'Other'
                      ? (item.unitOther ?? 'Other')
                      : (item.packagingLabel != null
                          ? '${item.effectiveQuantity} ${item.effectiveUnit} (in ${item.packagingLabel})'
                          : item.effectiveUnit),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _DetailItem(
                  icon: Icons.tag_rounded,
                  label: 'HS Code',
                  value: (item.hsCode?.isNotEmpty == true) ? item.hsCode! : '—',
                ),
              ),
              const Gap(12),
              Expanded(
                child: _DetailItem(
                  icon: Icons.payments_rounded,
                  // The TOTAL, with the unit price beneath it — the same shape
                  // the Valuation column uses. This showed the bare unitValue
                  // under a label reading just "Value", while every table showed
                  // unitValue x quantity under that same word.
                  label: 'Value (total)',
                  value: 'LKR ${NumberFormat('#,##0.00').format(item.unitValue * item.quantity)}'
                      '  ·  @ ${NumberFormat('#,##0.00').format(item.unitValue)} × ${item.quantity}',
                ),
              ),
            ],
          ),
          if (item.goodsDescription?.isNotEmpty == true)
            _DetailItem(
              icon: Icons.description_rounded,
              label: 'Goods Description',
              value: item.goodsDescription!,
            ),
          if (item.reasons?.isNotEmpty == true)
            _DetailItem(
              icon: Icons.warning_amber_rounded,
              label: 'Post Status Activity',
              value: item.reasons!,
            ),
        ],
      ),
    );
  }
}

class _DetailColumn extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _DetailColumn(this.label, this.value, {required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: context.colors.textMuted),
            const Gap(6),
            Text(label,
                style:
                    TextStyle(color: context.colors.textMuted, fontSize: 12)),
          ],
        ),
        Text(value,
            style: TextStyle(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 14)),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final String label;
  final String value;
  final BuildContext ctx;

  const _HistoryRow(this.label, this.value, this.ctx);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(label,
              style: TextStyle(color: ctx.colors.textMuted, fontSize: 12)),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  color: ctx.colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}

Widget _InfoChip(
    String label, String value, IconData icon, BuildContext context) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: context.colors.surfaceDark,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: context.colors.borderColor),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 14, color: context.colors.textMuted),
        const Gap(6),
        Text('$label: ',
            style: TextStyle(color: context.colors.textMuted, fontSize: 12)),
        Text(value,
            style: TextStyle(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 12)),
      ],
    ),
  );
}

// ============ PACKAGE UPDATE DIALOG ============
class PackageUpdateDialog extends ConsumerStatefulWidget {
  final PackageModel package;
  final PackageItem? highlightedItem;
  final WarehouseEntryModel? highlightEntry; // Added this
  final Map<DateTime, double> storageRate;

  const PackageUpdateDialog({
    super.key,
    required this.package,
    this.highlightedItem,
    this.highlightEntry, // Added this
    required this.storageRate,
  });

  @override
  ConsumerState<PackageUpdateDialog> createState() =>
      _PackageUpdateDialogState();
}

class _ItemRow {
  String id = '';
  final nameCtrl = TextEditingController();
  final goodsDescriptionCtrl = TextEditingController();
  final qtyCtrl = TextEditingController(text: '1');
  final unitOfMeasureCtrl = TextEditingController(text: 'Pieces');
  final unitOtherCtrl = TextEditingController();
  // Cartons only: inner unit type + inner quantity per carton.
  final innerUnitCtrl = TextEditingController(text: 'Pieces');
  final innerQtyCtrl = TextEditingController(text: '1');
  final valueCtrl = TextEditingController(text: '0');
  final hsCodeCtrl = TextEditingController();
  final categoryCtrl = TextEditingController();
  String status = 'Detain';
  final otherStatusCtrl = TextEditingController();
  final List<String?> selectedReasons = [null];
}

class _PackageUpdateDialogState extends ConsumerState<PackageUpdateDialog>
    with SingleTickerProviderStateMixin {
  late final _formKey = GlobalKey<FormState>();
  late final AnimationController _animCtrl;
  late final Animation<double> _anim;
  late final TextEditingController _consigneeCtrl;
  late final TextEditingController _consigneeNicCtrl;
  late final TextEditingController _consigneePhoneCtrl;
  late final TextEditingController _declarantCtrl;
  late final TextEditingController _cusdecCtrl;
  late final TextEditingController _cusdecDateCtrl;
  late final TextEditingController _entryDateCtrl;
  late final TextEditingController _caseNumberCtrl;
  late final TextEditingController _containerNumberCtrl;

  /// Package-level deposit against the cost of destruction.
  late final TextEditingController _destroyingDepositCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _reasonCtrl;
  late final TextEditingController _valueCtrl;
  late final TextEditingController _weightCtrl;
  late final TextEditingController _originCtrl;

  late String _statusValue;
  late List<_ItemRow> _items;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _anim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack);
    _animCtrl.forward();
    _consigneeCtrl = TextEditingController(text: widget.package.consigneeName);
    _consigneeNicCtrl =
        TextEditingController(text: widget.package.consigneeNic ?? '');
    _consigneePhoneCtrl =
        TextEditingController(text: widget.package.consigneePhone ?? '');
    _declarantCtrl =
        TextEditingController(text: widget.package.declarantName ?? '');
    _cusdecCtrl = TextEditingController(text: widget.package.cusdecNo ?? '');
    _cusdecDateCtrl =
        TextEditingController(text: widget.package.cusdecDate ?? '');
    _entryDateCtrl = TextEditingController(
        text: widget.package.entryDate != null
            ? '${widget.package.entryDate!.year}-${widget.package.entryDate!.month.toString().padLeft(2, '0')}-${widget.package.entryDate!.day.toString().padLeft(2, '0')}'
            : '');
    _caseNumberCtrl =
        TextEditingController(text: widget.package.caseNumber ?? '');
    _containerNumberCtrl =
        TextEditingController(text: widget.package.containerNumber ?? '');
    _destroyingDepositCtrl = TextEditingController(
        text: widget.package.destroyingDeposit?.toString() ?? '');
    _descCtrl = TextEditingController(text: widget.package.description ?? '');
    _notesCtrl = TextEditingController(text: widget.package.notes ?? '');
    _reasonCtrl = TextEditingController(text: widget.package.reason ?? '');
    _valueCtrl = TextEditingController(
        text: widget.package.declaredValue?.toString() ?? '');
    _weightCtrl =
        TextEditingController(text: widget.package.weightKg?.toString() ?? '');
    _originCtrl =
        TextEditingController(text: widget.package.originCountry ?? '');

    _statusValue = (widget.package.status == 'detained' ||
            widget.package.status == 'forfeited')
        ? 'held'
        : widget.package.status;

    // Initialize items
    _items = [];
    if (widget.highlightedItem != null) {
      // Show only the specific highlighted item if provided
      final row = _ItemRow();
      row.id = widget.highlightedItem!.id;
      row.nameCtrl.text = widget.highlightedItem!.itemName;
      row.goodsDescriptionCtrl.text =
          widget.highlightedItem!.goodsDescription ?? '';
      final hi = widget.highlightedItem!;
      if (hi.innerUnit == 'Cartons' && hi.innerQuantity != null) {
        row.unitOfMeasureCtrl.text = 'Cartons';
        row.qtyCtrl.text = (hi.innerQuantity ?? 1).toString();
        row.innerUnitCtrl.text = hi.unitOfMeasure;
        row.innerQtyCtrl.text = hi.quantity.toString();
      } else {
        row.qtyCtrl.text = hi.quantity.toString();
        row.unitOfMeasureCtrl.text = hi.unitOfMeasure;
        if (![
          'Pieces',
          'Cartons',
          'Boxes',
          'Bags',
          'Pallets',
          'Rolls',
          'Packages',
          'No of',
          'Bottles',
          'KG',
          'Meters',
          'Other'
        ].contains(row.unitOfMeasureCtrl.text)) {
          row.unitOtherCtrl.text = row.unitOfMeasureCtrl.text;
          row.unitOfMeasureCtrl.text = 'Other';
        }
      }

      row.valueCtrl.text = widget.highlightedItem!.unitValue.toString();
      row.hsCodeCtrl.text = widget.highlightedItem!.hsCode ?? '';
      row.categoryCtrl.text = widget.highlightedItem!.category ?? '';
      _applyStatusToRow(row, widget.highlightedItem!.status);

      // If the entry is returned, override item status to 'returned'
      if (widget.highlightEntry?.isReturned == true) {
        row.status = 'Other';
        row.otherStatusCtrl.text = 'returned';
      }

      if (widget.highlightedItem!.reasons != null &&
          widget.highlightedItem!.reasons!.isNotEmpty) {
        final rList = widget.highlightedItem!.reasons!
            .split(', ')
            .map((s) => s.trim())
            .toList();
        row.selectedReasons.clear();
        for (int i = 0; i < rList.length && i < 4; i++) {
          row.selectedReasons.add(rList[i]);
        }
        if (row.selectedReasons.isEmpty) row.selectedReasons.add(null);
      }
      _items.add(row);
    } else if (widget.package.items.isNotEmpty) {
      for (final item in widget.package.items) {
        final row = _ItemRow();
        row.id = item.id;
        row.nameCtrl.text = item.itemName;
        row.goodsDescriptionCtrl.text = item.goodsDescription ?? '';
        // Reconstruct the inverted Cartons storage: a packaged item keeps
        // 'Cartons' + carton count in innerUnit/innerQuantity and the inner
        // contents in quantity/unitOfMeasure.
        if (item.innerUnit == 'Cartons' && item.innerQuantity != null) {
          row.unitOfMeasureCtrl.text = 'Cartons';
          row.qtyCtrl.text = (item.innerQuantity ?? 1).toString();
          row.innerUnitCtrl.text = item.unitOfMeasure;
          row.innerQtyCtrl.text = item.quantity.toString();
        } else {
          row.qtyCtrl.text = item.quantity.toString();
          row.unitOfMeasureCtrl.text = item.unitOfMeasure;
          if (![
            'Pieces',
            'Cartons',
            'Boxes',
            'Bags',
            'Pallets',
            'Rolls',
            'Packages',
            'No of',
            'Bottles',
            'KG',
            'Meters',
            'Other'
          ].contains(row.unitOfMeasureCtrl.text)) {
            row.unitOtherCtrl.text = row.unitOfMeasureCtrl.text;
            row.unitOfMeasureCtrl.text = 'Other';
          }
        }

        row.valueCtrl.text = item.unitValue.toString();
        row.hsCodeCtrl.text = item.hsCode ?? '';
        row.categoryCtrl.text = item.category ?? '';
        _applyStatusToRow(row, item.status);
        if (item.reasons != null && item.reasons!.isNotEmpty) {
          final rList = item.reasons!.split(', ').map((s) => s.trim()).toList();
          row.selectedReasons.clear();
          for (int i = 0; i < rList.length && i < 4; i++) {
            row.selectedReasons.add(rList[i]);
          }
          if (row.selectedReasons.isEmpty) row.selectedReasons.add(null);
        }
        _items.add(row);
      }
    } else {
      _items.add(_ItemRow());
    }
  }

  @override
  void dispose() {
    _consigneeCtrl.dispose();
    _consigneeNicCtrl.dispose();
    _consigneePhoneCtrl.dispose();
    _declarantCtrl.dispose();
    _cusdecCtrl.dispose();
    _cusdecDateCtrl.dispose();
    _entryDateCtrl.dispose();
    _caseNumberCtrl.dispose();
    _containerNumberCtrl.dispose();
    _destroyingDepositCtrl.dispose();
    _descCtrl.dispose();
    _notesCtrl.dispose();
    _reasonCtrl.dispose();
    _valueCtrl.dispose();
    _weightCtrl.dispose();
    _originCtrl.dispose();
    for (final item in _items) {
      item.nameCtrl.dispose();
      item.goodsDescriptionCtrl.dispose();
      item.qtyCtrl.dispose();
      item.unitOfMeasureCtrl.dispose();
      item.unitOtherCtrl.dispose();
      item.valueCtrl.dispose();
      item.hsCodeCtrl.dispose();
      item.categoryCtrl.dispose();
      item.otherStatusCtrl.dispose();
    }
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _selectDate(TextEditingController controller) async {
    // Use the same custom picker as the SR form so the calendar looks identical
    // (same look/size) and dates read as YYYY-MM-DD — not the Material picker's
    // MM/DD/YYYY manual-entry box.
    final existing = DateTime.tryParse(controller.text.trim());
    final DateTime? picked = await showDialog<DateTime>(
      context: context,
      builder: (_) => OneTapDatePicker(
        initialDate: existing ?? DateTime.now(),
        lastDate: DateTime.now(),
      ),
    );
    if (picked != null) {
      setState(() {
        controller.text =
            "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
    }
  }

  void _applyStatusToRow(_ItemRow row, String status) {
    const statuses = ['Detain', 'Forfeit', 'Abandoned', 'Other'];
    if (statuses.contains(status)) {
      row.status = status;
      row.otherStatusCtrl.clear();
    } else {
      row.status = 'Other';
      row.otherStatusCtrl.text = status.isEmpty ? 'Detain' : status;
    }
  }

  String _rowStatus(_ItemRow row) {
    return row.status == 'Other' ? row.otherStatusCtrl.text.trim() : row.status;
  }

  Future<void> _updatePackage() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isUpdating = true);
    try {
      final List<PackageItem> itemsToUpsert;

      if (widget.highlightedItem != null) {
        // If we were editing a specific item, update just that one in the list
        itemsToUpsert = widget.package.items.map<PackageItem>((item) {
          if (item.id == widget.highlightedItem!.id) {
            final row = _items.first;
            return item.copyWith(
              itemName: row.nameCtrl.text,
              goodsDescription: row.goodsDescriptionCtrl.text.trim().isEmpty
                  ? null
                  : row.goodsDescriptionCtrl.text.trim(),
              // Cartons stored inverted: quantity/unit hold the inner contents;
              // packaging (Cartons + count) goes to innerUnit/innerQuantity.
              quantity: row.unitOfMeasureCtrl.text == 'Cartons'
                  ? (int.tryParse(row.innerQtyCtrl.text) ?? 1)
                  : (int.tryParse(row.qtyCtrl.text) ?? 1),
              unitValue: double.tryParse(row.valueCtrl.text) ?? 0,
              hsCode: row.hsCodeCtrl.text.trim().isEmpty
                  ? null
                  : row.hsCodeCtrl.text.trim(),
              category: row.categoryCtrl.text,
              unitOfMeasure: row.unitOfMeasureCtrl.text == 'Cartons'
                  ? row.innerUnitCtrl.text
                  : (row.unitOfMeasureCtrl.text == 'Other'
                      ? row.unitOtherCtrl.text
                      : row.unitOfMeasureCtrl.text),
              innerUnit:
                  row.unitOfMeasureCtrl.text == 'Cartons' ? 'Cartons' : null,
              innerQuantity: row.unitOfMeasureCtrl.text == 'Cartons'
                  ? (int.tryParse(row.qtyCtrl.text) ?? 1)
                  : null,
              status: _rowStatus(row),
              reasons:
                  row.selectedReasons.where((res) => res != null).join(', '),
            );
          }
          return item;
        }).toList();
      } else {
        // Otherwise use the bulk items list from the form
        itemsToUpsert = _items
            .where((r) => r.nameCtrl.text.isNotEmpty)
            .map((r) => PackageItem(
                  id: r.id,
                  packageId: '',
                  itemName: r.nameCtrl.text,
                  goodsDescription: r.goodsDescriptionCtrl.text.trim().isEmpty
                      ? null
                      : r.goodsDescriptionCtrl.text.trim(),
                  quantity: r.unitOfMeasureCtrl.text == 'Cartons'
                      ? (int.tryParse(r.innerQtyCtrl.text) ?? 1)
                      : (int.tryParse(r.qtyCtrl.text) ?? 1),
                  unitValue: double.tryParse(r.valueCtrl.text) ?? 0,
                  hsCode: r.hsCodeCtrl.text.trim().isEmpty
                      ? null
                      : r.hsCodeCtrl.text.trim(),
                  category: r.categoryCtrl.text,
                  unitOfMeasure: r.unitOfMeasureCtrl.text == 'Cartons'
                      ? r.innerUnitCtrl.text
                      : (r.unitOfMeasureCtrl.text == 'Other'
                          ? r.unitOtherCtrl.text
                          : r.unitOfMeasureCtrl.text),
                  innerUnit:
                      r.unitOfMeasureCtrl.text == 'Cartons' ? 'Cartons' : null,
                  innerQuantity: r.unitOfMeasureCtrl.text == 'Cartons'
                      ? (int.tryParse(r.qtyCtrl.text) ?? 1)
                      : null,
                  status: _rowStatus(r),
                  reasons:
                      r.selectedReasons.where((res) => res != null).join(', '),
                ))
            .toList();
      }

      final updatedPackage = widget.package.copyWith(
        consigneeName: _consigneeCtrl.text.trim(),
        consigneeNic: _consigneeNicCtrl.text.trim(),
        consigneePhone: _consigneePhoneCtrl.text.trim(),
        declarantName: _declarantCtrl.text.trim(),
        cusdecNo: _cusdecCtrl.text.trim(),
        cusdecDate: _cusdecDateCtrl.text.trim(),
        caseNumber: _caseNumberCtrl.text.trim().isEmpty
            ? null
            : _caseNumberCtrl.text.trim(),
        containerNumber: _containerNumberCtrl.text.trim().isEmpty
            ? null
            : _containerNumberCtrl.text.trim(),
        destroyingDeposit: double.tryParse(_destroyingDepositCtrl.text.trim()),
        entryDate: _entryDateCtrl.text.isNotEmpty
            ? DateTime.tryParse(_entryDateCtrl.text)
            : null,
        description: _descCtrl.text.trim(),
        reason: _reasonCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
        declaredValue: double.tryParse(_valueCtrl.text.trim()) ?? 0,
        weightKg: double.tryParse(_weightCtrl.text.trim()) ?? 0,
        originCountry: _originCtrl.text.trim(),
        status: _statusValue,
      );

      await ref
          .read(packageServiceProvider)
          .upsertPackage(updatedPackage, itemsToUpsert);

      // Trigger refreshes for all related dashboard and list providers
      ref.read(packagesRefreshTriggerProvider.notifier).trigger();
      ref.read(warehouseRefreshTriggerProvider.notifier).trigger();
      ref.invalidate(livePackagesProvider);
      ref.invalidate(dashboardStatsProvider); // Dashboard stats refresh
      ref.invalidate(recentPackagesProvider); // Recent inspections refresh
      ref.invalidate(allWarehouseEntriesProvider);
      ref.invalidate(categoryZoneSummaryProvider); // Inventory table refresh

      if (mounted) {
        Navigator.pop(context);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Package "${widget.package.srNumber}" updated successfully!'),
            backgroundColor: context.colors.successGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error updating package: $e'),
              backgroundColor: context.colors.dangerRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) {
          final value = _anim.value;
          return Transform.scale(
            scale: value,
            child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
          );
        },
        child: material.Container(
          width: 1000,
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.9),
          decoration: BoxDecoration(
            color: context.colors.scaffoldBg,
            borderRadius: BorderRadius.circular(24),
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              material.Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
                      const BorderRadius.vertical(top: Radius.circular(23)),
                ),
                child: Row(
                  children: [
                    material.Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.edit_document,
                          color: context.colors.primaryGold, size: 24),
                    ),
                    const Gap(16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'UPDATE SR REGISTER ENTRY',
                            style: material.TextStyle(
                              color: context.colors.primaryGold,
                              fontSize: 11,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            widget.package.srNumber,
                            style: material.TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded,
                          color: Colors.white.withOpacity(0.7)),
                      splashRadius: 24,
                    ),
                  ],
                ),
              ),
              // Form Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // SR Information Section
                        _UpdateSectionCard(
                          title: 'SR Register Information',
                          icon: Icons.inventory_2_rounded,
                          children: [
                            TextFormField(
                              enabled: false,
                              initialValue: widget.package.srNumber,
                              decoration: const InputDecoration(
                                  labelText: 'SR Number *'),
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _cusdecCtrl,
                                    decoration: const InputDecoration(
                                        labelText: 'Cusdec No *'),
                                    validator: (v) =>
                                        v!.isEmpty ? 'Required' : null,
                                  ),
                                ),
                                const Gap(12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _entryDateCtrl,
                                    inputFormatters: [
                                      MaskTextInputFormatter(
                                        mask: '####-##-##',
                                        filter: {"#": RegExp(r'[0-9]')},
                                        type: MaskAutoCompletionType.lazy,
                                      )
                                    ],
                                    decoration: InputDecoration(
                                      labelText: 'Entry Date *',
                                      hintText: 'YYYY-MM-DD',
                                      suffixIcon: IconButton(
                                        icon: Icon(Icons.calendar_month,
                                            color: context.colors.primaryGold),
                                        onPressed: () =>
                                            _selectDate(_entryDateCtrl),
                                      ),
                                    ),
                                    validator: (v) {
                                      if (v == null || v.isEmpty)
                                        return 'Required';
                                      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$')
                                          .hasMatch(v)) return 'Use YYYY-MM-DD';
                                      return null;
                                    },
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _caseNumberCtrl,
                                    decoration: const InputDecoration(
                                        labelText: 'Case Number'),
                                  ),
                                ),
                                const Gap(12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _cusdecDateCtrl,
                                    inputFormatters: [
                                      MaskTextInputFormatter(
                                        mask: '####-##-##',
                                        filter: {"#": RegExp(r'[0-9]')},
                                        type: MaskAutoCompletionType.lazy,
                                      )
                                    ],
                                    decoration: InputDecoration(
                                      labelText: 'Cusdec Date *',
                                      hintText: 'YYYY-MM-DD',
                                      suffixIcon: IconButton(
                                        icon: Icon(Icons.calendar_month,
                                            color: context.colors.primaryGold),
                                        onPressed: () =>
                                            _selectDate(_cusdecDateCtrl),
                                      ),
                                    ),
                                    validator: (v) {
                                      if (v == null || v.isEmpty)
                                        return 'Required';
                                      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$')
                                          .hasMatch(v)) return 'Use YYYY-MM-DD';
                                      return null;
                                    },
                                  ),
                                ),
                              ],
                            ),
                            TextFormField(
                              controller: _containerNumberCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Container Number'),
                              textCapitalization: TextCapitalization.characters,
                            ),
                            TextFormField(
                              controller: _destroyingDepositCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Destroying Deposit (LKR)'),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.]')),
                              ],
                              validator: (v) {
                                final t = (v ?? '').trim();
                                if (t.isEmpty) return null; // optional
                                final d = double.tryParse(t);
                                if (d == null) return 'Enter a number';
                                if (d < 0) return 'Cannot be negative';
                                return null;
                              },
                            ),
                            TextFormField(
                              controller: _descCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Package Description'),
                              maxLines: 2,
                            ),
                          ],
                        ),
                        const Gap(16),
                        // Consignee Information Section
                        _UpdateSectionCard(
                          title: 'Consignee Information',
                          icon: Icons.person_rounded,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _consigneeCtrl,
                                    decoration: const InputDecoration(
                                        labelText: 'Consignee Name *'),
                                    validator: (v) =>
                                        v!.isEmpty ? 'Required' : null,
                                  ),
                                ),
                                const Gap(12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _declarantCtrl,
                                    decoration: const InputDecoration(
                                        labelText: 'Declarant Name *'),
                                    validator: (v) =>
                                        v!.isEmpty ? 'Required' : null,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller:
                                        _descCtrl, // Reusing controller for address if needed, or stick to required fields
                                    decoration: const InputDecoration(
                                        labelText: 'Declarant Address'),
                                  ),
                                ),
                                const Gap(12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _consigneePhoneCtrl,
                                    decoration: const InputDecoration(
                                        labelText:
                                            'Declarant Phone Number (10 digits) *'),
                                    keyboardType: TextInputType.phone,
                                    validator: (v) {
                                      if (v == null || v.isEmpty)
                                        return 'Required';
                                      if (!RegExp(r'^\d{10}$').hasMatch(v)) {
                                        return 'Must be exactly 10 digits';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ).animate().slideY(
                            begin: 0.1, duration: 400.ms, delay: 200.ms),
                        const Gap(16),
                        // Package Goods Section
                        _UpdateSectionCard(
                          title: widget.highlightedItem != null
                              ? 'ITEM DETAILS'
                              : 'Package Goods',
                          icon: Icons.shopping_bag_rounded,
                          children: [
                            Column(
                              children: List.generate(
                                  _items.length,
                                  (i) => Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: _UpdateItemRowWidget(
                                          row: _items[i],
                                          index: widget.highlightedItem != null
                                              ? -1
                                              : i +
                                                  1, // -1 means don't show index
                                          onRemove: widget.highlightedItem !=
                                                  null
                                              ? null
                                              : (_items.length > 1
                                                  ? () => setState(
                                                      () => _items.removeAt(i))
                                                  : null),
                                          onChanged: () => setState(() {}),
                                        ),
                                      )),
                            ),
                            // Add Item below the list (not in the header) so a
                            // new item needs no scroll back to the top. Hidden
                            // in single-item edit mode.
                            if (widget.highlightedItem == null) ...[
                              const Gap(4),
                              material.Align(
                                alignment: material.Alignment.centerLeft,
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: const Text('Add Goods'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: context.colors.primaryGold,
                                    side: BorderSide(
                                        color: context.colors.primaryGold
                                            .withOpacity(0.5)),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 14),
                                  ),
                                  onPressed: () =>
                                      setState(() => _items.add(_ItemRow())),
                                ),
                              ),
                            ],
                          ],
                        ).animate().slideY(
                            begin: 0.1, duration: 400.ms, delay: 300.ms),
                        const Gap(16),
                        // Notes Section
                        _UpdateSectionCard(
                          title: 'OFFICER NOTES',
                          icon: Icons.note_rounded,
                          children: [
                            TextFormField(
                              controller: _notesCtrl,
                              decoration: const InputDecoration(
                                  hintText: 'Additional inspection notes...'),
                              maxLines: 3,
                            ),
                          ],
                        ).animate().slideY(
                            begin: 0.1, duration: 400.ms, delay: 500.ms),
                      ],
                    ),
                  ),
                ),
              ),
              // Footer Buttons
              material.Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : Colors.grey.shade50,
                  border: Border(
                      top: BorderSide(color: context.colors.borderColor)),
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(23)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const Gap(12),
                    ElevatedButton.icon(
                      icon: _isUpdating
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: context.colors.primaryNavy))
                          : const Icon(Icons.save_rounded),
                      label: Text(_isUpdating ? 'Updating...' : 'Update Entry'),
                      onPressed: _isUpdating ? null : _updatePackage,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Helper widget for update form sections
class _UpdateItemRowWidget extends ConsumerStatefulWidget {
  final _ItemRow row;
  final int index;
  final VoidCallback? onRemove;
  final VoidCallback onChanged;

  const _UpdateItemRowWidget({
    required this.row,
    required this.index,
    this.onRemove,
    required this.onChanged,
  });

  @override
  ConsumerState<_UpdateItemRowWidget> createState() =>
      _UpdateItemRowWidgetState();
}

class _UpdateItemRowWidgetState extends ConsumerState<_UpdateItemRowWidget> {
  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(packageCategoriesProvider);
    return material.Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderColor),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              material.Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: context.colors.primaryGold.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('Goods ${widget.index == -1 ? "1" : widget.index}',
                    style: TextStyle(
                        color: context.colors.primaryGold,
                        fontWeight: FontWeight.w700,
                        fontSize: 12)),
              ),
              const Spacer(),
              if (widget.onRemove != null)
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded,
                      size: 20, color: context.colors.dangerRed),
                  onPressed: widget.onRemove,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Remove item',
                ),
            ],
          ),
          const Gap(12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: widget.row.nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Goods Name *', isDense: true),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                  onChanged: (_) => widget.onChanged(),
                ),
              ),
              const Gap(10),
              Expanded(
                flex: 2,
                child: StyledDropdownFormField<String>(
                  label: 'Unit Type *',
                  menuWidth: 220,
                  columns: 2,
                  value: const [
                    'Pieces',
                    'Cartons',
                    'Boxes',
                    'Bags',
                    'Pallets',
                    'Rolls',
                    'Packages',
                    'No of',
                    'Bottles',
                    'KG',
                    'Meters',
                    'Other'
                  ].contains(widget.row.unitOfMeasureCtrl.text)
                      ? widget.row.unitOfMeasureCtrl.text
                      : 'Pieces',
                  options: const [
                    'Pieces',
                    'Cartons',
                    'Boxes',
                    'Bags',
                    'Pallets',
                    'Rolls',
                    'Packages',
                    'No of',
                    'Bottles',
                    'KG',
                    'Meters',
                    'Other'
                  ].map((u) => StyledDropdownOption(u, u)).toList(),
                  onChanged: (v) {
                    setState(() {
                      widget.row.unitOfMeasureCtrl.text = v ?? 'Pieces';
                    });
                    widget.onChanged();
                  },
                ),
              ),
              if (widget.row.unitOfMeasureCtrl.text == 'Other') ...[
                const Gap(8),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: widget.row.unitOtherCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Name *', isDense: true),
                    validator: (v) =>
                        widget.row.unitOfMeasureCtrl.text == 'Other' &&
                                (v == null || v.trim().isEmpty)
                            ? 'Req'
                            : null,
                    onChanged: (_) => widget.onChanged(),
                  ),
                ),
              ],
              const Gap(10),
              Expanded(
                flex: 1,
                child: TextFormField(
                  controller: widget.row.qtyCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Quantity *', isDense: true),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Req';
                    if (int.tryParse(v) == null || int.tryParse(v)! <= 0)
                      return 'Err';
                    return null;
                  },
                  onChanged: (_) => widget.onChanged(),
                ),
              ),
              if (widget.row.unitOfMeasureCtrl.text == 'Cartons') ...[
                const Gap(10),
                Expanded(
                  flex: 2,
                  child: StyledDropdownFormField<String>(
                    label: 'Inner Unit *',
                    menuWidth: 220,
                    columns: 2,
                    value: const [
                      'Pieces',
                      'Boxes',
                      'Bags',
                      'Pallets',
                      'Rolls',
                      'Packages',
                      'No of',
                      'Bottles',
                      'KG',
                      'Meters',
                    ].contains(widget.row.innerUnitCtrl.text)
                        ? widget.row.innerUnitCtrl.text
                        : 'Pieces',
                    options: const [
                      'Pieces',
                      'Boxes',
                      'Bags',
                      'Pallets',
                      'Rolls',
                      'Packages',
                      'No of',
                      'Bottles',
                      'KG',
                      'Meters',
                    ].map((u) => StyledDropdownOption(u, u)).toList(),
                    onChanged: (v) {
                      setState(
                          () => widget.row.innerUnitCtrl.text = v ?? 'Pieces');
                      widget.onChanged();
                    },
                  ),
                ),
                const Gap(8),
                Expanded(
                  flex: 1,
                  child: TextFormField(
                    controller: widget.row.innerQtyCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Inner Qty *', isDense: true),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) =>
                        widget.row.unitOfMeasureCtrl.text == 'Cartons' &&
                                (v == null || v.trim().isEmpty)
                            ? 'Req'
                            : null,
                    onChanged: (_) => widget.onChanged(),
                  ),
                ),
              ],
              const Gap(10),
              Expanded(
                flex: 2,
                child: StyledDropdownFormField<String>(
                  label: 'Status *',
                  menuWidth: 200,
                  value: const ['Detain', 'Forfeit', 'Abandoned', 'Other']
                          .contains(widget.row.status)
                      ? widget.row.status
                      : 'Other',
                  options: const ['Detain', 'Forfeit', 'Abandoned', 'Other']
                      .map((s) => StyledDropdownOption(s, s))
                      .toList(),
                  onChanged: (v) {
                    setState(() {
                      final previous = widget.row.status;
                      widget.row.status = v!;
                      // Detain and the disposal statuses offer different
                      // activities — drop selections that no longer apply.
                      if (postStatusActivitiesFor(previous) !=
                          postStatusActivitiesFor(widget.row.status)) {
                        widget.row.selectedReasons
                          ..clear()
                          ..add(null);
                      }
                    });
                    widget.onChanged();
                  },
                ),
              ),
              if (widget.row.status == 'Other') ...[
                const Gap(10),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: widget.row.otherStatusCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Other Status *', isDense: true),
                    validator: (v) => widget.row.status == 'Other' &&
                            (v == null || v.trim().isEmpty)
                        ? 'Required'
                        : null,
                    onChanged: (_) => widget.onChanged(),
                  ),
                ),
              ],
              const Gap(10),
              Expanded(
                flex: 2,
                child: categories.when(
                  loading: () => const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  error: (e, _) => IconButton(
                    icon: const Icon(Icons.refresh,
                        size: 16, color: Colors.orange),
                    onPressed: () => ref.refresh(packageCategoriesProvider),
                    tooltip: 'Error loading categories',
                  ),
                  data: (list) {
                    final selectedCategory = list
                        .where((c) => c.name == widget.row.categoryCtrl.text)
                        .firstOrNull;
                    return StyledDropdownFormField<String>(
                      label: 'Category',
                      menuWidth: 240,
                      value: selectedCategory?.name,
                      options: list
                          .map((c) => StyledDropdownOption(c.name, c.name))
                          .toList(),
                      onChanged: (v) {
                        widget.row.categoryCtrl.text = v ?? '';
                        setState(() {});
                        widget.onChanged();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
          const Gap(12),
          // ── HS Code & Value (per item) ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: widget.row.hsCodeCtrl,
                  decoration: const InputDecoration(
                      labelText: 'HS Code', isDense: true),
                  onChanged: (_) => widget.onChanged(),
                ),
              ),
              const Gap(12),
              Expanded(
                child: TextFormField(
                  controller: widget.row.valueCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Value', isDense: true, prefixText: 'LKR '),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                  ],
                  onChanged: (_) => widget.onChanged(),
                ),
              ),
            ],
          ),
          const Gap(16),
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 18, color: context.colors.heldOrange),
              const Gap(8),
              Text('Post Status Activity',
                  style: material.TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: context.colors.textPrimary)),
              const Spacer(),
              if (widget.row.selectedReasons.length < 4)
                TextButton.icon(
                  onPressed: () {
                    setState(() => widget.row.selectedReasons.add(null));
                    widget.onChanged();
                  },
                  icon: const Icon(Icons.add_circle_outline, size: 16),
                  label: const Text('Add Activity',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: TextButton.styleFrom(
                    foregroundColor: context.colors.primaryGold,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    backgroundColor:
                        context.colors.primaryGold.withOpacity(0.1),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
            ],
          ),
          const Gap(12),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: List.generate(widget.row.selectedReasons.length, (rIdx) {
              final activities = postStatusActivitiesFor(widget.row.status);
              return SizedBox(
                width: 380,
                child: Row(
                  children: [
                    Expanded(
                      child: StyledDropdownFormField<String>(
                        label: 'Activity ${rIdx + 1} *',
                        menuWidth: 300,
                        fillColor: context.colors.cardDark,
                        value: activities
                                .contains(widget.row.selectedReasons[rIdx])
                            ? widget.row.selectedReasons[rIdx]
                            : null,
                        validator: (v) => v == null ? 'Required' : null,
                        options: activities
                            .map((a) => StyledDropdownOption(a, a))
                            .toList(),
                        onChanged: (v) {
                          setState(() => widget.row.selectedReasons[rIdx] = v);
                          widget.onChanged();
                        },
                      ),
                    ),
                    if (widget.row.selectedReasons.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: IconButton(
                          icon: const Icon(Icons.remove_circle_outline,
                              size: 20, color: Colors.grey),
                          onPressed: () {
                            setState(() =>
                                widget.row.selectedReasons.removeAt(rIdx));
                            widget.onChanged();
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Remove activity',
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
          const Gap(12),
          TextFormField(
            controller: widget.row.goodsDescriptionCtrl,
            decoration: const InputDecoration(
                labelText: 'Goods Description', isDense: true, helperText: ' '),
            maxLines: 2,
            onChanged: (_) => widget.onChanged(),
          ),
        ],
      ),
    );
  }
}

class _UpdateSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? headerTrailing;

  _UpdateSectionCard({
    required this.title,
    required this.icon,
    required this.children,
    this.headerTrailing,
  });

  @override
  Widget build(BuildContext context) {
    return material.Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? context.colors.surfaceDark.withOpacity(0.5)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: context.colors.primaryGold),
              const Gap(10),
              Text(
                title.toUpperCase(),
                style: material.TextStyle(
                  color: context.colors.primaryGold,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              if (headerTrailing != null) ...[
                const Spacer(),
                headerTrailing!,
              ],
            ],
          ),
          const Gap(16),
          Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1) const Gap(10),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Package Actions Dialog ────────────────────────────────────────────────────

class _PackageActionsDialog extends ConsumerStatefulWidget {
  final String packageId;
  final String itemId;
  final WarehouseEntryModel fallbackEntry;

  /// When the goods entered the yard. Every status carries a 30-day appeal
  /// window from this date, and NO action may be taken while it is open.
  final DateTime? entryDate;
  // Return true when the action was applied.
  final Future<bool> Function(WarehouseEntryModel held, List<int> slots)
      onRelease;
  final Future<bool> Function(
      WarehouseEntryModel held, String type, List<int> slots) onDispose;
  // Invoked after a successful action so the caller can close the parent
  // details dialog too (this dialog pops itself first). When null, only this
  // dialog closes.
  final VoidCallback? onCompleted;

  const _PackageActionsDialog({
    required this.packageId,
    required this.itemId,
    required this.fallbackEntry,
    required this.entryDate,
    required this.onRelease,
    required this.onDispose,
    this.onCompleted,
  });

  @override
  ConsumerState<_PackageActionsDialog> createState() =>
      _PackageActionsDialogState();
}

class _PackageActionsDialogState extends ConsumerState<_PackageActionsDialog> {
  bool _otherExpanded = false;
  bool _isLoading = false;
  final _otherCtrl = TextEditingController();

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  void _showSuccess(BuildContext ctx, String message) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
          const Gap(12),
          Expanded(
              child: Text(message,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
        backgroundColor: const Color(0xFF2E7D32),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showError(BuildContext ctx, String message) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.error_rounded, color: Colors.white, size: 20),
          const Gap(12),
          Expanded(
              child: Text(message,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
        backgroundColor: const Color(0xFFC62828),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _runAction(BuildContext ctx, Future<bool> Function() action,
      String successMsg) async {
    setState(() => _isLoading = true);
    try {
      final ok = await action();
      if (!mounted) return;
      if (ok) {
        _showSuccess(ctx, successMsg);
        // Auto-close on success: pop this actions dialog, then ask the caller
        // to close the parent details dialog so we land back on the list.
        setState(() => _isLoading = false);
        Navigator.of(context).pop();
        widget.onCompleted?.call();
        return;
      } else {
        _showError(ctx, 'Action could not be completed. Please try again.');
      }
    } catch (e) {
      if (!mounted) return;
      _showError(ctx, 'Error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static const _actions = [
    _ActionDef(
      key: 'Release',
      icon: Icons.assignment_return_rounded,
      label: 'Release Package',
      description: 'Package returned to the owner. Storage charge applies.',
      color: Color(0xFF43A047),
    ),
    _ActionDef(
      key: 'Forfeit',
      icon: Icons.gavel_rounded,
      label: 'Forfeit',
      description: 'Package forfeited to the state. No further charges.',
      color: Color(0xFFE53935),
    ),
    _ActionDef(
      key: 'Abandoned',
      icon: Icons.inbox_rounded,
      label: 'Abandoned',
      description: 'Package declared abandoned. No further charges.',
      color: Color(0xFF9E9E9E),
    ),
    _ActionDef(
      key: 'Re-export',
      icon: Icons.flight_takeoff_rounded,
      label: 'Re-export',
      description: 'Package sent back to country of origin. Charge applies.',
      color: Color(0xFF00ACC1),
    ),
    _ActionDef(
      key: 'Destroy',
      icon: Icons.delete_forever_rounded,
      label: 'Destroy',
      description: 'Package destroyed. No further charges.',
      color: Color(0xFFE64A19),
    ),
    _ActionDef(
      key: 'Other',
      icon: Icons.more_horiz_rounded,
      label: 'Other',
      description: 'Enter a custom disposition type.',
      color: Color(0xFF7E57C2),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // Live data: recompute held / processed slots whenever package data changes,
    // so the dialog stays correct after an action without closing.
    final pkg = ref.watch(packageDataProvider(widget.packageId)).valueOrNull;
    final entries = pkg?.warehouseEntries ?? [widget.fallbackEntry];
    final item = pkg?.items.where((i) => i.id == widget.itemId).firstOrNull;
    final total = item?.quantity ?? widget.fallbackEntry.itemCount;
    final processed = _computeProcessedSlots(widget.itemId, total, entries);
    final heldEntry = entries
            .where((e) => e.packageItemId == widget.itemId && !e.isReturned)
            .firstOrNull ??
        widget.fallbackEntry;
    final heldCount = (total - processed.length).clamp(0, total);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Role-based action permissions.
    // - Officers: no disposition actions enabled at all.
    // - Admins: Release, Re-export, Abandoned, Forfeit and Other are enabled.
    //   Destroy remains disabled for everyone.
    final isOfficer = ref.watch(currentProfileProvider)?.role == 'officer';
    const _disabledForAll = {'Destroy'};
    // The 30-day appeal window freezes EVERY action, whatever the status:
    // the owner may still appeal, so the goods cannot be released, forfeited,
    // abandoned, re-exported or destroyed until it closes.
    //
    // …UNLESS the Appeal Directorate has already ruled. A decision ends the
    // wait: there is nothing left to appeal, so the goods become actionable
    // immediately rather than sitting out the remaining days. A HOLD does the
    // opposite and keeps them frozen, because that appeal is still open.
    final outcome =
        ref.watch(itemAppealOutcomesProvider(widget.packageId)).valueOrNull;
    final itemOutcome =
        outcome?[widget.itemId] ?? outcome?[''] ?? const ItemAppealOutcome();
    final decidedEarly = itemOutcome.unblocksAction;

    final inAppealWindow =
        isWithinAppealWindow(widget.entryDate) && !decidedEarly;
    final appealDaysRemaining = appealDaysLeft(widget.entryDate);
    // An open appeal blocks action even after the window closes.
    final blockedByHold = itemOutcome.onHold;
    // The action key matching an Appeal Directorate decision code. SALE and
    // DESTROY map to nothing here: those two are carried out by sending a
    // disposal request to Central Disposal, never from this sheet.
    String? actionKeyForDecision(String code) {
      switch (code.trim().toUpperCase()) {
        case 'RELEASE':
          return 'Release';
        case 'RE-EXPORT':
          return 'Re-export';
        case 'OTHER':
          return 'Other';
        default:
          return null;
      }
    }

    bool isActionEnabled(String key) {
      if (isOfficer) return false;
      if (_disabledForAll.contains(key)) return false;
      if (inAppealWindow || blockedByHold) return false;
      // Once the directorate has ruled, ONLY the decided action is open — the
      // yard carries out what was decided rather than choosing afresh. This
      // mirrors the Final Disposition sheet's own gating.
      if (itemOutcome.isDecided) {
        return key == actionKeyForDecision(itemOutcome.decision!);
      }
      return true;
    }

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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Stack(
          children: [
            material.Container(
              width: 580,
              constraints: const BoxConstraints(maxHeight: 750),
              decoration: BoxDecoration(
                color: context.colors.scaffoldBg,
                borderRadius: BorderRadius.circular(20),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [
                                context.colors.surfaceDark,
                                context.colors.cardDark
                              ]
                            : [
                                context.colors.customsBlue,
                                context.colors.customsBlueDark
                              ],
                      ),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.inventory_2_rounded,
                              color: context.colors.primaryGold, size: 24),
                        )
                            .animate()
                            .slideY(begin: 0.1, duration: 400.ms)
                            .fadeIn(),
                        const Gap(16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SR REGISTER ENTRY',
                                style: TextStyle(
                                  color: context.colors.primaryGold,
                                  fontSize: 11,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w800,
                                ),
                              )
                                  .animate()
                                  .slideY(
                                      begin: 0.1,
                                      duration: 400.ms,
                                      delay: 100.ms)
                                  .fadeIn(),
                              Text(
                                heldEntry.srNumber ?? '',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                                  .animate()
                                  .slideY(
                                      begin: 0.1,
                                      duration: 400.ms,
                                      delay: 150.ms)
                                  .fadeIn(),
                            ],
                          ),
                        ),
                        const Gap(12),
                        IconButton(
                          icon: Icon(Icons.close_rounded,
                              color: Colors.white.withOpacity(0.7)),
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
                          Row(
                            children: [
                              Icon(Icons.bolt_rounded,
                                  color: context.colors.primaryGold, size: 24),
                              const Gap(10),
                              Text(
                                'Goods Actions',
                                style: TextStyle(
                                  color: context.colors.textPrimary,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ).animate().fadeIn(delay: 200.ms),
                          const Gap(16),
                          // The directorate has ruled, so the wait is over even
                          // though the window has days left. Says which way.
                          if (decidedEarly)
                            material.Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: context.colors.successGreen
                                    .withOpacity(0.10),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: context.colors.successGreen
                                        .withOpacity(0.4)),
                              ),
                              child: Row(children: [
                                Icon(Icons.gavel_rounded,
                                    color: context.colors.successGreen,
                                    size: 18),
                                const Gap(10),
                                Expanded(
                                  child: Text(
                                      'Appeal decided \u00b7 '
                                      '${itemOutcome.decision}. '
                                      'These goods can be actioned now \u2014 the '
                                      '30-day window no longer applies.',
                                      style: TextStyle(
                                          color: context.colors.successGreen,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600)),
                                ),
                              ]),
                            ).animate().fadeIn(delay: 220.ms),
                          // An appeal is lodged and still open: frozen regardless
                          // of the deadline.
                          if (blockedByHold)
                            material.Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: context.colors.warningAmber
                                    .withOpacity(0.10),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: context.colors.warningAmber
                                        .withOpacity(0.4)),
                              ),
                              child: Row(children: [
                                Icon(Icons.pan_tool_rounded,
                                    color: context.colors.warningAmber,
                                    size: 18),
                                const Gap(10),
                                Expanded(
                                  child: Text(
                                      'On appeal hold. The Appeal Directorate is '
                                      'reviewing these goods \u2014 no action can '
                                      'be taken until it rules.',
                                      style: TextStyle(
                                          color: context.colors.warningAmber,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600)),
                                ),
                              ]),
                            ).animate().fadeIn(delay: 220.ms),
                          // Why everything is greyed out.
                          if (inAppealWindow && !blockedByHold)
                            material.Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: context.colors.warningAmber
                                    .withOpacity(0.10),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: context.colors.warningAmber
                                        .withOpacity(0.4)),
                              ),
                              child: Row(children: [
                                Icon(Icons.gavel_rounded,
                                    color: context.colors.warningAmber,
                                    size: 18),
                                const Gap(10),
                                Expanded(
                                  child: Text(
                                      'Appealing · $appealDaysRemaining day'
                                      '${appealDaysRemaining == 1 ? '' : 's'} left. '
                                      'No action can be taken until the 30-day '
                                      'appeal window closes.',
                                      style: TextStyle(
                                          color: context.colors.warningAmber,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600)),
                                ),
                              ]),
                            ).animate().fadeIn(delay: 220.ms),
                          if (heldCount <= 0)
                            material.Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: context.colors.successGreen
                                    .withOpacity(0.08),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: context.colors.successGreen
                                        .withOpacity(0.3)),
                              ),
                              child: Row(children: [
                                Icon(Icons.check_circle_rounded,
                                    color: context.colors.successGreen,
                                    size: 18),
                                const Gap(10),
                                Expanded(
                                  child: Text(
                                      'All $total packages have been processed.',
                                      style: TextStyle(
                                          color: context.colors.textSecondary,
                                          fontSize: 12)),
                                ),
                              ]),
                            ).animate().fadeIn(delay: 250.ms)
                          else
                            material.Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: material.Align(
                                alignment: material.Alignment.centerLeft,
                                child: Text(
                                    '$heldCount of $total packages remaining',
                                    style: TextStyle(
                                        color: context.colors.textMuted,
                                        fontSize: 13)),
                              ),
                            ).animate().fadeIn(delay: 250.ms),

                          // Show all actions
                          ..._actions.map((a) {
                            final isOther = a.key == 'Other';
                            // Disabled either by role-permission or because there
                            // are no packages left to act on.
                            final permitted = isActionEnabled(a.key);
                            final isDisabled = !permitted || heldCount <= 0;
                            // Greyed colour for disabled cards/labels.
                            final cardColor =
                                isDisabled ? context.colors.textMuted : a.color;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                material.Opacity(
                                  opacity: isDisabled ? 0.45 : 1.0,
                                  child: material.Card(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: (isOther && _otherExpanded)
                                            ? cardColor.withOpacity(0.6)
                                            : cardColor.withOpacity(0.2),
                                        width: (isOther && _otherExpanded)
                                            ? 1.5
                                            : 1,
                                      ),
                                    ),
                                    color: cardColor.withOpacity(0.04),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: isDisabled
                                          ? null
                                          : () async {
                                              if (isOther) {
                                                setState(() => _otherExpanded =
                                                    !_otherExpanded);
                                              } else {
                                                // Show selection dialog with live processed slots
                                                final slots =
                                                    await showDialog<Set<int>>(
                                                  context: context,
                                                  builder: (ctx) =>
                                                      _PackageSelectionDialog(
                                                    actionColor: a.color,
                                                    actionName:
                                                        a.key == 'Release'
                                                            ? 'Release'
                                                            : a.key,
                                                    totalQty: total,
                                                    processedSlots: processed,
                                                  ),
                                                );
                                                if (slots != null &&
                                                    slots.isNotEmpty) {
                                                  final list = slots.toList()
                                                    ..sort();
                                                  final ctx = context;
                                                  if (a.key == 'Release') {
                                                    await _runAction(
                                                      ctx,
                                                      () => widget.onRelease(
                                                          heldEntry, list),
                                                      '${list.length} package(s) released successfully.',
                                                    );
                                                  } else {
                                                    await _runAction(
                                                      ctx,
                                                      () => widget.onDispose(
                                                          heldEntry,
                                                          a.key,
                                                          list),
                                                      '${list.length} package(s) marked as ${a.label} successfully.',
                                                    );
                                                  }
                                                }
                                              }
                                            },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 14),
                                        child: Row(children: [
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color:
                                                  cardColor.withOpacity(0.12),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Icon(a.icon,
                                                color: cardColor, size: 20),
                                          ),
                                          const Gap(16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(a.label,
                                                    style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 15,
                                                        color: cardColor)),
                                                const Gap(4),
                                                Text(a.description,
                                                    style: TextStyle(
                                                        fontSize: 13,
                                                        color: context
                                                            .colors.textMuted)),
                                              ],
                                            ),
                                          ),
                                          Icon(
                                            isOther
                                                ? (_otherExpanded
                                                    ? Icons.expand_less_rounded
                                                    : Icons.expand_more_rounded)
                                                : Icons.chevron_right_rounded,
                                            color: cardColor.withOpacity(0.6),
                                            size: 22,
                                          ),
                                        ]),
                                      ),
                                    ),
                                  )
                                      .animate()
                                      .fadeIn(delay: 300.ms)
                                      .slideY(begin: 0.05),
                                ),
                                // Inline "Other" text field
                                if (isOther && _otherExpanded)
                                  Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(4, 0, 4, 16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        TextFormField(
                                          controller: _otherCtrl,
                                          autofocus: true,
                                          decoration: InputDecoration(
                                            labelText: 'Disposition Type *',
                                            hintText:
                                                'e.g. Transferred, Seized for Analysis...',
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: BorderSide(
                                                  color: context
                                                      .colors.borderColor),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: BorderSide(
                                                  color: context
                                                      .colors.borderColor),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: BorderSide(
                                                  color:
                                                      const Color(0xFF7E57C2),
                                                  width: 2),
                                            ),
                                            filled: true,
                                            fillColor: context
                                                .colors.textPrimary
                                                .withOpacity(0.02),
                                          ),
                                        ).animate().fadeIn(),
                                        const Gap(12),
                                        ElevatedButton.icon(
                                          icon: const Icon(Icons.check_rounded,
                                              size: 18),
                                          label: const Text(
                                              'Confirm Other Disposition',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                const Color(0xFF7E57C2),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 14),
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10)),
                                          ),
                                          onPressed: () async {
                                            final t = _otherCtrl.text.trim();
                                            if (t.isEmpty) return;

                                            final slots =
                                                await showDialog<Set<int>>(
                                              context: context,
                                              builder: (ctx) =>
                                                  _PackageSelectionDialog(
                                                actionColor:
                                                    const Color(0xFF7E57C2),
                                                actionName: t,
                                                totalQty: total,
                                                processedSlots: processed,
                                              ),
                                            );
                                            if (slots != null &&
                                                slots.isNotEmpty) {
                                              final list = slots.toList()
                                                ..sort();
                                              final ctx = context;
                                              // Prefix the custom text with the "Other:"
                                              // marker so the disposition is unambiguously
                                              // an "Other" outcome — tagged "[OTHER: <text>]"
                                              // in returnNotes (partial) and stored as item
                                              // status "Other: <text>" (full). This is what
                                              // the Other Packages table detects.
                                              await _runAction(
                                                ctx,
                                                () => widget.onDispose(
                                                    heldEntry,
                                                    'Other: $t',
                                                    list),
                                                '${list.length} package(s) marked as "$t" successfully.',
                                              );
                                            }
                                          },
                                        ).animate().fadeIn(),
                                      ],
                                    ),
                                  ),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                  ),

                  // ── Dialog Footer ──
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceDark,
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(20)),
                      border: Border(
                          top: BorderSide(color: context.colors.borderColor)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            foregroundColor: context.colors.textSecondary,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 14),
                          ),
                          child: const Text('Cancel',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── Loading overlay ──
            if (_isLoading)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Center(
                    child: CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFFFFB300)),
                      strokeWidth: 3,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionDef {
  final String key;
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  const _ActionDef({
    required this.key,
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
  });
}

// ── Final-disposition helpers ─────────────────────────────────────────────────

bool _hasFinalDisposition(PackageModel pkg, String itemId) {
  return pkg.warehouseEntries.any((e) {
    if (e.packageItemId != itemId) return false;
    final notes = (e.returnNotes ?? '').trim().toUpperCase();
    // NOTE: a bare "[OTHER…]" tag is a warehouse-Actions custom disposition
    // (like "[ABANDONED]"/"[FORFEIT]") — NOT a final-table move, so it does
    // NOT count here. The item must remain actionable via Final Disposition
    // until it is genuinely finalised ("[FINAL:OTHER]" etc.). Only the real
    // final markers below hide the button.
    return notes.contains('[FINAL:') ||
        notes.startsWith('[RE-EXPORT') ||
        notes.startsWith('[DESTROY') ||
        notes.startsWith('[SOLD');
  });
}

bool _isForfeitStatusLocal(String? s) {
  final v = (s ?? '').trim().toLowerCase();
  return v == 'forfeit' || v == 'forfeited' || v == 'forfiet';
}

/// Receipt/Notes are stored combined as "Receipt No: <no> | Notes: <notes>".
/// [_receiptNoOf] returns just the number; [_notesOf] returns just the notes.
/// Both handle a plain string (no prefix) gracefully.
String? _receiptNoOf(String? raw) {
  final s = raw?.trim();
  if (s == null || s.isEmpty) return null;
  final m =
      RegExp(r'Receipt No:\s*([^|]+)', caseSensitive: false).firstMatch(s);
  if (m != null) {
    final v = m.group(1)!.trim();
    return v.isEmpty ? null : v;
  }
  // No "Receipt No:" prefix — treat the part before any "| Notes:" as the no.
  final v = s.split(RegExp(r'\|?\s*Notes:', caseSensitive: false)).first.trim();
  return v.isEmpty ? null : v;
}

String? _notesOf(String? raw) {
  final s = raw?.trim();
  if (s == null || s.isEmpty) return null;
  final m = RegExp(r'Notes:\s*(.+)$', caseSensitive: false).firstMatch(s);
  final v = m?.group(1)?.trim();
  return (v == null || v.isEmpty) ? null : v;
}

/// True if the highlighted entry is itself an abandon/forfeit disposition —
/// used so partial abandon/forfeit rows (item status still 'detain') can
/// still receive a final disposition.
bool _isAbandonOrForfeitEntry(WarehouseEntryModel? e) {
  if (e == null || !e.isReturned) return false;
  final notes = (e.returnNotes ?? '').trim().toUpperCase();
  return notes.startsWith('[ABANDONED') ||
      notes.startsWith('[FORFEIT') ||
      notes.startsWith('[CONFISCATED');
}

// ── Per-package-number slot tracking ──────────────────────────────────────────

/// Parses the explicit package numbers encoded in a returnNotes string
/// ("... pkgs:2,5,17 ...").
Set<int> _parsePkgNums(String? notes) {
  if (notes == null) return {};
  final m = RegExp(r'pkgs:([\d,]+)').firstMatch(notes);
  if (m == null) return {};
  return m
      .group(1)!
      .split(',')
      .map((s) => int.tryParse(s.trim()))
      .whereType<int>()
      .toSet();
}

/// The set of package slot numbers (1..totalQty) that have already been
/// processed (released / disposed) for an item. Entries that recorded explicit
/// numbers are honoured exactly; legacy count-only entries fall back to the
/// lowest still-available slots.
Set<int> _computeProcessedSlots(
    String itemId, int totalQty, List<WarehouseEntryModel> entries) {
  final explicit = <int>{};
  int legacy = 0;
  for (final e in entries) {
    if (e.packageItemId != itemId || !e.isReturned) continue;
    final nums = _parsePkgNums(e.returnNotes);
    if (nums.isNotEmpty) {
      explicit.addAll(nums);
    } else {
      legacy += e.itemCount;
    }
  }
  final result = <int>{...explicit};
  for (int n = 1; n <= totalQty && legacy > 0; n++) {
    if (!result.contains(n)) {
      result.add(n);
      legacy--;
    }
  }
  return result;
}

// ── Final Disposition Dialog ──────────────────────────────────────────────────

/// Result of the per-action final-disposition confirm dialog.
class _FinalActionConfirmResult {
  final DateTime date;
  final String notes;
  const _FinalActionConfirmResult(this.date, this.notes);
}

/// Per-action confirmation for a Release / Re-export / Other final disposition —
/// mirrors the warehouse action final step: a date picker (defaults to today,
/// future blocked, same one-tap calendar as the SR form) plus optional notes.
class _FinalActionConfirmDialog extends StatefulWidget {
  final String label; // 'Release' / 'Re-export' / 'Other: nnn'
  final IconData icon;
  final Color color;
  final String description;
  final int qty;
  const _FinalActionConfirmDialog({
    required this.label,
    required this.icon,
    required this.color,
    required this.description,
    required this.qty,
  });

  @override
  State<_FinalActionConfirmDialog> createState() =>
      _FinalActionConfirmDialogState();
}

class _FinalActionConfirmDialogState extends State<_FinalActionConfirmDialog> {
  DateTime _date = DateTime.now();
  late final TextEditingController _dateCtrl;
  final _notesCtrl = TextEditingController();

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _dateCtrl = TextEditingController(text: _fmt(_date));
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return material.AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        Icon(widget.icon, color: widget.color, size: 22),
        const Gap(10),
        Flexible(child: Text('${widget.label} Package Item')),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: widget.color.withOpacity(0.3)),
            ),
            child: Text(widget.description,
                style: TextStyle(color: widget.color, fontSize: 13)),
          ),
          const Gap(16),
          // Date — defaults to today, future blocked, one-tap calendar.
          TextFormField(
            controller: _dateCtrl,
            readOnly: true,
            decoration: InputDecoration(
              labelText: '${widget.label} Date',
              isDense: true,
              suffixIcon: Icon(Icons.calendar_month, color: widget.color),
            ),
            onTap: () async {
              final picked = await showDialog<DateTime>(
                context: context,
                builder: (_) => OneTapDatePicker(
                  initialDate: _date,
                  lastDate: DateTime.now(),
                ),
              );
              if (picked != null) {
                setState(() {
                  _date = picked;
                  _dateCtrl.text = _fmt(picked);
                });
              }
            },
          ),
          const Gap(12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: widget.color.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Packages selected:',
                    style: TextStyle(
                        fontSize: 12, color: widget.color.withOpacity(0.7))),
                Text('${widget.qty}',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: widget.color)),
              ],
            ),
          ),
          const Gap(12),
          TextFormField(
            controller: _notesCtrl,
            decoration: const InputDecoration(
              labelText: 'Notes / Remarks (optional)',
              isDense: true,
            ),
            maxLines: 3,
            minLines: 2,
            keyboardType: TextInputType.multiline,
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton.icon(
          icon: Icon(widget.icon, size: 16),
          label: Text('Confirm ${widget.label}'),
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.color,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(
            context,
            _FinalActionConfirmResult(_date, _notesCtrl.text.trim()),
          ),
        ),
      ],
    );
  }
}

class _FinalActionDef {
  final String type; // RELEASED, SOLD, DESTROYED, RE-EXPORTED, OTHER
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final bool adminOnly;
  const _FinalActionDef({
    required this.type,
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.adminOnly,
  });
}

class _FinalDispositionDialog extends StatefulWidget {
  final PackageItem item;
  final int qty;
  final bool isOfficer;
  final Future<void> Function(String type, String? notes, DateTime date)
      onConfirm;
  // When supplied (Forfeited screen), Sale → 'sale' and Destroy → 'destruction'
  // route here to open the Central Disposal request flow instead of writing a
  // [FINAL:…] entry. When null, Sale / Destroy stay disabled.
  final void Function(String disposition)? onRequestDisposal;
  // Appeal Directorate decision code — when set, ONLY the matching action is
  // enabled (the yard must proceed exactly as decided).
  final String? decisionCode;

  const _FinalDispositionDialog({
    required this.item,
    required this.qty,
    required this.isOfficer,
    required this.onConfirm,
    this.onRequestDisposal,
    this.decisionCode,
  });

  @override
  State<_FinalDispositionDialog> createState() =>
      _FinalDispositionDialogState();
}

class _FinalDispositionDialogState extends State<_FinalDispositionDialog> {
  bool _otherExpanded = false;
  final _otherCtrl = TextEditingController();

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  static const _actions = [
    _FinalActionDef(
      type: 'RELEASED',
      icon: Icons.assignment_return_rounded,
      label: 'Release',
      description:
          'Return the goods to the owner. DC / SDDC approval required.',
      color: Color(0xFF43A047),
      adminOnly: true,
    ),
    _FinalActionDef(
      type: 'SOLD',
      icon: Icons.sell_rounded,
      label: 'Sale',
      description:
          'Send a disposal request to the Central Disposal Directorate.',
      color: Color(0xFFE8A826),
      adminOnly: false,
    ),
    _FinalActionDef(
      type: 'DESTROYED',
      icon: Icons.delete_forever_rounded,
      label: 'Destroy',
      description:
          'Send a disposal request to the Central Disposal Directorate.',
      color: Color(0xFFE64A19),
      adminOnly: false,
    ),
    _FinalActionDef(
      type: 'RE-EXPORTED',
      icon: Icons.flight_takeoff_rounded,
      label: 'Re-export',
      description: 'Goods sent back to origin. DC / SDDC approval required.',
      color: Color(0xFF00ACC1),
      adminOnly: true,
    ),
    _FinalActionDef(
      type: 'OTHER',
      icon: Icons.more_horiz_rounded,
      label: 'Other',
      description: 'Custom outcome. DC / SDDC approval required.',
      color: Color(0xFF7E57C2),
      adminOnly: true,
    ),
  ];

  // Sale and Destroy are never written as a [FINAL:…] entry from this dialog —
  // they are recorded by the Central Disposal Directorate. Picking one opens
  // the disposal REQUEST flow instead (see [onRequestDisposal]).
  static const _requestActions = {'SOLD', 'DESTROYED'};

  // The final-action type that matches an Appeal Directorate decision code.
  static String? _typeForDecision(String code) {
    switch (code.trim().toUpperCase()) {
      case 'RELEASE':
        return 'RELEASED';
      case 'SALE':
        return 'SOLD';
      case 'DESTROY':
        return 'DESTROYED';
      case 'RE-EXPORT':
        return 'RE-EXPORTED';
      case 'OTHER':
        return 'OTHER';
      default:
        return null;
    }
  }

  // Whether THIS user may trigger the given action.
  // - Officers: nothing is enabled.
  // - Sale / Destroy: ALWAYS disabled here. Those two outcomes belong to the
  //   Central Disposal Directorate, and the only way to start them is the
  //   "Send Disposal Request" button on the status page — one request, sent
  //   deliberately, rather than a per-item action buried in a details popup.
  // - When the Appeal Directorate has DECIDED, only the matching action is
  //   enabled (the yard must proceed exactly as decided). A SALE / DESTROY
  //   decision therefore enables nothing here — it is carried out by sending
  //   the disposal request.
  // - Otherwise (window passed, no decision): Release / Re-export / Other.
  bool _isActionEnabled(_FinalActionDef a) {
    if (widget.isOfficer) return false;
    if (_requestActions.contains(a.type)) return false;
    final code = widget.decisionCode;
    if (code != null && code.trim().isNotEmpty) {
      return a.type == _typeForDecision(code);
    }
    return true;
  }

  /// Opens the per-action confirmation dialog (date + notes) — mirroring the
  /// warehouse action final step — then records the disposition on that date.
  /// [otherDetail] carries the custom outcome text for the OTHER action.
  Future<void> _confirmFinalAction(_FinalActionDef a,
      {String? otherDetail}) async {
    final label = otherDetail != null ? 'Other: $otherDetail' : a.label;
    final result = await showDialog<_FinalActionConfirmResult>(
      context: context,
      builder: (_) => _FinalActionConfirmDialog(
        label: label,
        icon: a.icon,
        color: a.color,
        description: a.description,
        qty: widget.qty,
      ),
    );
    if (result == null) return;
    // For OTHER the outcome detail is the note; append any extra remarks.
    final String? notes;
    if (otherDetail != null) {
      notes =
          result.notes.isEmpty ? otherDetail : '$otherDetail — ${result.notes}';
    } else {
      notes = result.notes.isEmpty ? null : result.notes;
    }
    await widget.onConfirm(a.type, notes, result.date);
  }

  @override
  Widget build(BuildContext context) {
    // All actions are shown; disabled ones are greyed out and non-tappable.
    final visible = _actions;
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
          width: 520,
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
              // ── Header ──
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
                      const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    material.Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.outbound_rounded,
                          color: context.colors.primaryGold, size: 24),
                    ).animate().slideY(begin: 0.1, duration: 400.ms).fadeIn(),
                    const Gap(16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('FINAL DISPOSITION',
                                  style: material.TextStyle(
                                      color: context.colors.primaryGold,
                                      fontSize: 11,
                                      letterSpacing: 1.2,
                                      fontWeight: FontWeight.w800))
                              .animate()
                              .slideY(
                                  begin: 0.1, duration: 400.ms, delay: 100.ms)
                              .fadeIn(),
                          Text(
                            '${widget.item.itemName} · ${widget.qty} unit(s)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const material.TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold),
                          )
                              .animate()
                              .slideY(
                                  begin: 0.1, duration: 400.ms, delay: 150.ms)
                              .fadeIn(),
                        ],
                      ),
                    ),
                    const Gap(12),
                    IconButton(
                      icon: Icon(Icons.close_rounded,
                          color: Colors.white.withOpacity(0.7)),
                      splashRadius: 24,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // ── Body ──
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.assignment_ind_rounded,
                            size: 16, color: context.colors.primaryGold),
                        const Gap(8),
                        Text('Disposal Method',
                            style: material.TextStyle(
                                color: context.colors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3)),
                      ]).animate().fadeIn(delay: 200.ms),
                      if (widget.isOfficer) ...[
                        const Gap(6),
                        Text(
                          'Final disposition is restricted to DC / SDDC officers.',
                          style: material.TextStyle(
                              color: context.colors.textMuted,
                              fontSize: 11,
                              fontStyle: FontStyle.italic),
                        ),
                      ] else ...[
                        const Gap(6),
                        Text(
                          'Sale / Destroy go to the Central Disposal Directorate as a request; Release / Re-export / Other are recorded directly.',
                          style: material.TextStyle(
                              color: context.colors.textMuted,
                              fontSize: 11,
                              fontStyle: FontStyle.italic),
                        ),
                      ],
                      const Gap(16),
                      ...visible.map((a) {
                        final isOther = a.type == 'OTHER';
                        final isEnabled = _isActionEnabled(a);
                        final cardColor =
                            isEnabled ? a.color : context.colors.textMuted;
                        return Opacity(
                          opacity: isEnabled ? 1.0 : 0.45,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              material.Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: (isOther && _otherExpanded)
                                        ? cardColor.withOpacity(0.6)
                                        : cardColor.withOpacity(0.2),
                                    width:
                                        (isOther && _otherExpanded) ? 1.5 : 1,
                                  ),
                                ),
                                color: cardColor.withOpacity(0.04),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: !isEnabled
                                      ? null
                                      : () {
                                          if (isOther) {
                                            setState(() => _otherExpanded =
                                                !_otherExpanded);
                                          } else if (_requestActions
                                              .contains(a.type)) {
                                            // Sale / Destroy → disposal request (not a direct
                                            // [FINAL:…] write).
                                            widget.onRequestDisposal!(
                                                a.type == 'SOLD'
                                                    ? 'sale'
                                                    : 'destruction');
                                          } else {
                                            // Release / Re-export → per-action confirm dialog
                                            // (date + notes) before recording, like the
                                            // warehouse action final step.
                                            _confirmFinalAction(a);
                                          }
                                        },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                    child: Row(children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: cardColor.withOpacity(0.12),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Icon(a.icon,
                                            color: cardColor, size: 20),
                                      ),
                                      const Gap(14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(children: [
                                              Text(a.label,
                                                  style: material.TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 14,
                                                      color: cardColor)),
                                              if (_requestActions
                                                  .contains(a.type)) ...[
                                                const Gap(6),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 6,
                                                      vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: cardColor
                                                        .withOpacity(0.12),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4),
                                                  ),
                                                  child: Text(
                                                      'CENTRAL DISPOSAL',
                                                      style: material.TextStyle(
                                                          fontSize: 8,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: cardColor,
                                                          letterSpacing: 0.5)),
                                                ),
                                              ] else if (a.adminOnly) ...[
                                                const Gap(6),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 6,
                                                      vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: cardColor
                                                        .withOpacity(0.12),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4),
                                                  ),
                                                  child: Text('DC / SDDC',
                                                      style: material.TextStyle(
                                                          fontSize: 8,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: cardColor,
                                                          letterSpacing: 0.5)),
                                                ),
                                              ],
                                            ]),
                                            const Gap(2),
                                            Text(a.description,
                                                style: material.TextStyle(
                                                    fontSize: 12,
                                                    color: context
                                                        .colors.textMuted)),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        isOther
                                            ? (_otherExpanded
                                                ? Icons.expand_less_rounded
                                                : Icons.expand_more_rounded)
                                            : Icons.chevron_right_rounded,
                                        color: cardColor.withOpacity(0.6),
                                        size: 20,
                                      ),
                                    ]),
                                  ),
                                ),
                              ),
                              if (isOther && _otherExpanded)
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(4, 0, 4, 12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      TextFormField(
                                        controller: _otherCtrl,
                                        autofocus: true,
                                        decoration: const InputDecoration(
                                          labelText: 'Outcome detail *',
                                          hintText:
                                              'e.g. Donated, Transferred...',
                                          isDense: true,
                                        ),
                                      ),
                                      const Gap(10),
                                      ElevatedButton.icon(
                                        icon: const Icon(Icons.check_rounded,
                                            size: 16),
                                        label: const Text('Confirm Other'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF7E57C2),
                                          foregroundColor: Colors.white,
                                        ),
                                        onPressed: () {
                                          final t = _otherCtrl.text.trim();
                                          if (t.isEmpty) return;
                                          _confirmFinalAction(a,
                                              otherDetail: t);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ).animate().fadeIn(delay: 250.ms).slideY(begin: 0.05),
                        );
                      }),
                    ],
                  ),
                ),
              ),

              // ── Footer ──
              material.Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: context.colors.surfaceDark,
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(16)),
                  border: Border(
                      top: BorderSide(color: context.colors.borderColor)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: context.colors.textSecondary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                      ),
                      child: const Text('Cancel',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Disposition meta resolvers (by normalized returnNotes key) ────────────────

Color _dispoColor(String key) {
  switch (key) {
    case 'FORFEIT':
    case 'FORFEITED':
    case 'FORFIET':
    case 'CONFISCATED':
      return const Color(0xFFE53935);
    case 'RE-EXPORT':
    case 'REEXPORT':
      return const Color(0xFF00ACC1);
    case 'ABANDONED':
      return const Color(0xFF9E9E9E);
    case 'DESTROY':
    case 'DESTROYED':
      return const Color(0xFFE64A19);
    default:
      return const Color(0xFF7E57C2); // Other / custom
  }
}

String _dispoLabel(String key, String raw) {
  switch (key) {
    case 'FORFEIT':
    case 'FORFEITED':
    case 'FORFIET':
    case 'CONFISCATED':
      return 'Forfeited';
    case 'RE-EXPORT':
    case 'REEXPORT':
      return 'Re-export';
    case 'ABANDONED':
      return 'Abandoned';
    case 'DESTROY':
    case 'DESTROYED':
      return 'Destroy';
    default:
      // Title-case the custom "Other" type
      return raw
          .split(' ')
          .map((w) => w.isEmpty
              ? w
              : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
          .join(' ');
  }
}

// ── Disposition Row (shows status breakdown) ──────────────────────────────────

class _DispositionRow extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final String? officer;

  const _DispositionRow({
    required this.label,
    required this.count,
    required this.color,
    required this.officer,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const Gap(12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: material.TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textPrimary,
                ),
              ),
              if (officer != null) ...[
                const Gap(2),
                Text(
                  officer!,
                  style: material.TextStyle(
                    fontSize: 11,
                    color: context.colors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
        Text(
          'x$count',
          style: material.TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _DispositionMeta {
  final IconData icon;
  final Color color;
  final String label;
  final String description;
  const _DispositionMeta({
    required this.icon,
    required this.color,
    required this.label,
    required this.description,
  });
}

class _DispositionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _DispositionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: Icon(icon, size: 14, color: color),
      label: Text(label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withOpacity(0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        backgroundColor: color.withOpacity(0.05),
      ),
      onPressed: onPressed,
    );
  }
}

class _PackageSelectionDialog extends StatefulWidget {
  final Color actionColor;
  final String actionName;
  final int totalQty;
  final Set<int> processedSlots;

  const _PackageSelectionDialog({
    required this.actionColor,
    required this.actionName,
    required this.totalQty,
    required this.processedSlots,
  });

  @override
  State<_PackageSelectionDialog> createState() =>
      _PackageSelectionDialogState();
}

class _PackageSelectionDialogState extends State<_PackageSelectionDialog> {
  late Set<int> _selectedSlots;
  late final List<int> _heldSlots;
  // For large item counts (e.g. 1176 pieces) a tile-per-unit grid is unusable,
  // so we switch to a plain "how many to release" number field instead.
  late final bool _useQtyInput;
  final _qtyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _heldSlots = [
      for (int n = 1; n <= widget.totalQty; n++)
        if (!widget.processedSlots.contains(n)) n
    ];
    // By default, select all available (held) slots.
    _selectedSlots = _heldSlots.toSet();
    _useQtyInput = widget.totalQty > 50;
    _qtyCtrl.text = '${_heldSlots.length}';
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  void _toggleSlot(int slot) {
    setState(() {
      if (_selectedSlots.contains(slot)) {
        _selectedSlots.remove(slot);
      } else {
        _selectedSlots.add(slot);
      }
    });
  }

  // Quantity-input mode: select the first [n] available (held) slots.
  void _setQty(int n) {
    final clamped = n.clamp(0, _heldSlots.length);
    setState(() => _selectedSlots = _heldSlots.take(clamped).toSet());
  }

  void _selectAll() => setState(() {
        _selectedSlots = _heldSlots.toSet();
        _qtyCtrl.text = '${_heldSlots.length}';
      });
  void _clearAll() => setState(() {
        _selectedSlots.clear();
        _qtyCtrl.text = '0';
      });

  @override
  Widget build(BuildContext context) {
    final bool canProceed = _selectedSlots.isNotEmpty;

    return material.AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.all(24),
      title: Text('Select Packages to ${widget.actionName}'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select which specific packages you want to apply this action to.',
                style: TextStyle(color: context.colors.textMuted, fontSize: 13),
              ),
              const Gap(16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_selectedSlots.length} of ${_heldSlots.length} selected',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: _selectAll,
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          tapTargetSize:
                              material.MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Select All',
                            style: TextStyle(fontSize: 12)),
                      ),
                      const Gap(8),
                      TextButton(
                        onPressed: _clearAll,
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          tapTargetSize:
                              material.MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: context.colors.textMuted,
                        ),
                        child: const Text('Clear All',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
              const Gap(12),
              if (_useQtyInput)
                // Large counts → a single quantity field ("release N of M").
                Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: material.TextField(
                        controller: _qtyCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Quantity',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                        onChanged: (v) => _setQty(int.tryParse(v) ?? 0),
                      ),
                    ),
                    const Gap(12),
                    Text('of ${_heldSlots.length} available',
                        style: TextStyle(color: context.colors.textSecondary)),
                  ],
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(widget.totalQty, (index) {
                    final slotNumber = index + 1;
                    final isProcessed =
                        widget.processedSlots.contains(slotNumber);
                    final isSelected = _selectedSlots.contains(slotNumber);

                    return _PackageSlotChip(
                      slotNumber: slotNumber,
                      totalQty: widget.totalQty,
                      isProcessed: isProcessed,
                      isSelected: isSelected,
                      activeColor: widget.actionColor,
                      onTap: isProcessed ? null : () => _toggleSlot(slotNumber),
                    );
                  }),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:
              Text('Cancel', style: TextStyle(color: context.colors.textMuted)),
        ),
        ElevatedButton(
          onPressed:
              canProceed ? () => Navigator.pop(context, _selectedSlots) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.actionColor,
            foregroundColor: Colors.white,
            disabledBackgroundColor: widget.actionColor.withOpacity(0.3),
            disabledForegroundColor: Colors.white.withOpacity(0.5),
          ),
          child: Text('${widget.actionName} (${_selectedSlots.length})'),
        ),
      ],
    );
  }
}

class _PackageSlotChip extends StatelessWidget {
  final int slotNumber;
  final int totalQty;
  final bool isProcessed;
  final bool isSelected;
  final Color activeColor;
  final VoidCallback? onTap;

  const _PackageSlotChip({
    required this.slotNumber,
    required this.totalQty,
    required this.isProcessed,
    required this.isSelected,
    required this.activeColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = material.Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Color bgColor;
    Color borderColor;
    Color textColor;

    if (isProcessed) {
      bgColor = isDark ? Colors.grey[800]! : Colors.grey[200]!;
      borderColor = Colors.transparent;
      textColor = isDark ? Colors.grey[500]! : Colors.grey[500]!;
    } else if (isSelected) {
      bgColor = activeColor.withOpacity(0.1);
      borderColor = activeColor;
      textColor = activeColor;
    } else {
      bgColor = Colors.transparent;
      borderColor = isDark ? Colors.grey[700]! : Colors.grey[300]!;
      textColor = isDark ? Colors.grey[300]! : Colors.grey[700]!;
    }

    return material.InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: material.AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: borderColor, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              Icon(Icons.check_circle_rounded, size: 14, color: activeColor),
              const Gap(4),
            ],
            Text(
              '$slotNumber / $totalQty',
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: textColor,
                decoration:
                    isProcessed ? material.TextDecoration.lineThrough : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
