import '../../widgets/sealed_valuation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:intl/intl.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/yards.dart';
import '../../models/models.dart';
import '../../widgets/error_view.dart';
import '../../widgets/tooltip_text.dart';
import '../../widgets/destruction_status_pill.dart';

/// ONE definition of the Unsold Packages table, shared by all three portals —
/// the yard's Unsold page, Central Disposal's Unsold tab and the Top Management Directorate's
/// Unsold tab. Previously each built its own columns, so the same package
/// showed different details (and different quantities) depending on where you
/// looked. Only the "Final Outcome" cell differs now: the DG gets a Decide
/// button, everyone else gets the read-only chip.

/// This row's own item name. Forfeiture is recorded PER ITEM, so a multi-item
/// package produces one row per item — resolve item_id rather than falling
/// through to items.first, which labelled every row with the first item.
String unsoldItemName(ForfeitedPackageModel f) {
  if (f.itemName != null) return f.itemName!;
  final items = f.packageDetails?.items ?? const [];
  if (items.isEmpty) return 'Multiple/Unspecified';
  if (f.itemId != null) {
    final m = items.where((i) => i.id == f.itemId).firstOrNull;
    if (m != null) return m.itemName;
  }
  if (items.length == 1) return items.first.itemName;
  return '${items.first.itemName} +${items.length - 1}';
}

/// This row's own quantity — NOT the package total.
int unsoldQty(ForfeitedPackageModel f) {
  if (f.entryQty != null) return f.entryQty!;
  if (f.itemId != null) {
    final it =
        f.packageDetails?.items.where((i) => i.id == f.itemId).firstOrNull;
    if (it != null) return it.quantity;
  }
  return f.packageDetails?.items.fold<int>(0, (s, i) => s + i.quantity) ?? 1;
}

/// A forfeited row's HS code.
///
/// ⚠️ Delegates, so there is ONE rule. This had its own copy with an
/// `items.first` fallback -- on a package of three items with no item_id
/// that stamped every row with the first item's code, which is a wrong
/// answer where the shared version gives none.
String? unsoldHsCodeOf(ForfeitedPackageModel f) =>
    unsoldHsCode(f.packageDetails, f.itemId);

/// This row's HS code, resolved from ITS OWN item.
///
/// ⚠️ Forfeiture is recorded per item, so a three-item package makes
/// three rows -- falling through to `items.first` would stamp all three
/// with one code. Several items and no way to say which returns null: a
/// code that might be wrong is worse than none.
String? unsoldHsCode(PackageModel? pkg, String? itemId) {
  final items = pkg?.items ?? const <PackageItem>[];
  if (itemId != null) {
    final match = items.where((i) => i.id == itemId).firstOrNull;
    if (match != null) return match.hsCode;
  }
  if (items.length == 1) return items.first.hsCode;
  return null;
}

/// This row's consignee, straight off the package.
String unsoldConsignee(PackageModel? pkg, String? fallback) {
  final name = (pkg?.consigneeName ?? '').trim();
  if (name.isNotEmpty) return name;
  final f = (fallback ?? '').trim();
  return f.isEmpty ? '\u2014' : f;
}

/// Yard · Warehouse · zone the item currently sits in (latest entry).
///
/// [yard] is the forfeited package's yard code — prepended so the
/// directorate tables (which show packages from every yard) identify
/// where each one is.
String unsoldLocation(PackageModel? pkg, String? itemId, [String? yard]) {
  final yName = (yard != null && yard.isNotEmpty) ? yardName(yard) : null;
  if (pkg == null) return yName ?? '—';
  var entries = itemId != null
      ? pkg.warehouseEntries.where((e) => e.packageItemId == itemId).toList()
      : <WarehouseEntryModel>[];
  if (entries.isEmpty) entries = [...pkg.warehouseEntries];
  if (entries.isEmpty) return yName ?? '—';
  entries.sort((a, b) => b.admittedAt.compareTo(a.admittedAt));
  final w = entries.first;
  final whPart = (w.zone != null && w.zone!.isNotEmpty)
      ? '${w.warehouseName} · ${w.zone}'
      : w.warehouseName;
  return yName != null ? '$yName · $whPart' : whPart;
}

/// Icon + colour per final outcome, identical on every portal.
({IconData icon, Color colour}) unsoldOutcomeStyle(
    BuildContext context, String p) {
  switch (p) {
    case 'destroy':
      return (
        icon: Icons.delete_forever_rounded,
        colour: context.colors.dangerRed
      );
    case 'government_use':
      return (
        icon: Icons.account_balance_rounded,
        colour: context.colors.successGreen
      );
    case 'auction':
      return (icon: Icons.gavel_rounded, colour: context.colors.warningAmber);
    case 're_export':
      return (
        icon: Icons.flight_takeoff_rounded,
        colour: context.colors.accentLightBlue
      );
    case 'convert':
      return (
        icon: Icons.autorenew_rounded,
        colour: context.colors.primaryGold
      );
    case 'remove_from_premises':
      return (icon: Icons.logout_rounded, colour: context.colors.heldOrange);
    default:
      return (
        icon: Icons.help_outline_rounded,
        colour: context.colors.textMuted
      );
  }
}

/// Narrow enough to fit the window without sideways scrolling — the table
/// carries ONLY the columns needed to identify a package and act on it.
/// Everything else (case no, HS code, valuation breakdown, tender history)
/// lives behind the Details button.
const double kUnsoldTableMinWidth = 945;

/// The shared column set. Order and widths are fixed so the three tables line
/// up column-for-column.
///
/// Deliberately NOT here: **Tenders** — every package on this table has
/// exhausted all four rounds, so a "4×" badge on every row says nothing.
///
/// The same reasoning governs the last data column. On the Unsold Goods page
/// the outcome varies row to row, so **Final Outcome** earns its place. On a
/// single-outcome page (Government Use, Auction, Converted, Removed)
/// every row carries the SAME chip — it is the page's own title repeated — so
/// those pages show **Decided On** instead, which does differ per row.
const List<DataColumn2> kUnsoldColumns = [
  DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
  DataColumn2(label: Text('Goods Name'), size: ColumnSize.L),
  DataColumn2(label: Text('Qty'), size: ColumnSize.S, fixedWidth: 60),
  DataColumn2(label: Text('Consignee'), size: ColumnSize.M),
  DataColumn2(label: Text('Location'), size: ColumnSize.M),
  // "Latest Valuation": these rows carry the committee's figure when one
  // exists, not the original — see unsoldCells.
  DataColumn2(
      label: Text('Latest Valuation'), size: ColumnSize.S, fixedWidth: 130),
  DataColumn2(
      label: Center(child: Text('Final Outcome')),
      size: ColumnSize.M,
      // Wide enough for the longest outcome — "Remove from the Premises" —
      // beside its icon, so the chip is never cut short.
      fixedWidth: 235),
  DataColumn2(
      label: Center(child: Text('Details')),
      size: ColumnSize.S,
      fixedWidth: 66),
];

/// [kUnsoldColumns] with the outcome column replaced by **Decided On**, for a
/// page that already filters to one outcome.
const List<DataColumn2> kUnsoldDecidedColumns = [
  DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
  DataColumn2(label: Text('Goods Name'), size: ColumnSize.L),
  DataColumn2(label: Text('Qty'), size: ColumnSize.S, fixedWidth: 60),
  DataColumn2(label: Text('Consignee'), size: ColumnSize.M),
  DataColumn2(label: Text('Location'), size: ColumnSize.M),
  // "Latest Valuation": these rows carry the committee's figure when one
  // exists, not the original — see unsoldCells.
  DataColumn2(
      label: Text('Latest Valuation'), size: ColumnSize.S, fixedWidth: 130),
  DataColumn2(
      label: Center(child: Text('Decided On')),
      size: ColumnSize.M,
      fixedWidth: 235),
  // ⚠️ A decision is not a hand-over. These goods are still in the yard until
  // someone comes for them, and this column is what says so — the same
  // Pending/Mark Delivered/Delivered pill the Sold table uses.
  DataColumn2(
      label: Center(child: Text('Delivery')),
      size: ColumnSize.M,
      fixedWidth: kStatusPillWidth + 24),
  DataColumn2(
      label: Center(child: Text('Details')),
      size: ColumnSize.S,
      fixedWidth: 66),
];

/// [kUnsoldColumns] for PERISHABLE goods. Perishables only get one valuation
/// (from the Valuation Directorate), never a committee re-valuation, so the
/// column says **Valuation** rather than "Latest Valuation".
const List<DataColumn2> kUnsoldPerishableColumns = [
  DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
  DataColumn2(label: Text('Goods Name'), size: ColumnSize.L),
  DataColumn2(label: Text('Qty'), size: ColumnSize.S, fixedWidth: 60),
  DataColumn2(label: Text('Consignee'), size: ColumnSize.M),
  DataColumn2(label: Text('Location'), size: ColumnSize.M),
  DataColumn2(
      label: Text('Valuation'), size: ColumnSize.S, fixedWidth: 130),
  DataColumn2(
      label: Center(child: Text('Final Outcome')),
      size: ColumnSize.M,
      fixedWidth: 235),
  DataColumn2(
      label: Center(child: Text('Details')),
      size: ColumnSize.S,
      fixedWidth: 66),
];

/// [kUnsoldPerishableColumns] with **Decided On** + **Delivery** instead of
/// **Final Outcome**, for a perishable page that already filters to one outcome.
///
/// ⚠️ NOT WIRED UP YET. No perishable table filters to a single outcome
/// today -- Central Disposal's perishable tab shows them all -- so nothing
/// passes this. It is kept because it is the matching half of a pair: the
/// moment a perishable outcome tab exists, using [kUnsoldPerishableColumns]
/// there would put nine cells against eight columns, and data_table_2 throws.
const List<DataColumn2> kUnsoldPerishableDecidedColumns = [
  DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
  DataColumn2(label: Text('Goods Name'), size: ColumnSize.L),
  DataColumn2(label: Text('Qty'), size: ColumnSize.S, fixedWidth: 60),
  DataColumn2(label: Text('Consignee'), size: ColumnSize.M),
  DataColumn2(label: Text('Location'), size: ColumnSize.M),
  DataColumn2(
      label: Text('Valuation'), size: ColumnSize.S, fixedWidth: 130),
  DataColumn2(
      label: Center(child: Text('Decided On')),
      size: ColumnSize.M,
      fixedWidth: 235),
  DataColumn2(
      label: Center(child: Text('Delivery')),
      size: ColumnSize.M,
      fixedWidth: kStatusPillWidth + 24),
  DataColumn2(
      label: Center(child: Text('Details')),
      size: ColumnSize.S,
      fixedWidth: 66),
];

/// The date the Top Management Directorate recorded this outcome, for [kUnsoldDecidedColumns].
///
/// The note the DG left is worth surfacing, so it rides in the tooltip rather
/// than taking a column of its own.
Widget unsoldDecidedOnCell(
    BuildContext context, UnsoldProposalModel? proposal) {
  if (proposal == null) {
    return Center(
      child: Text('—', style: TextStyle(color: context.colors.textMuted)),
    );
  }
  final note = proposal.note?.trim();
  return Center(
    child: Tooltip(
      message: (note != null && note.isNotEmpty)
          ? '${proposal.label}\n$note'
          : proposal.label,
      waitDuration: const Duration(milliseconds: 300),
      child: Text(DateFormat('yyyy-MM-dd').format(proposal.decidedAt),
          style: TextStyle(
              color: context.colors.textSecondary,
              fontWeight: FontWeight.w600)),
    ),
  );
}

/// The shared cells, in the same order as [kUnsoldColumns].
///
/// [outcome] is the only portal-specific widget — the DG passes a Decide
/// button, the yard and Central Disposal pass an [UnsoldOutcomeChip].
/// [onDetails] is null when the package record could not be loaded.
List<DataCell> unsoldCells(
  BuildContext context, {
  required ReTenderSaleInfo info,
  required Color srColor,
  required Widget outcome,
  required VoidCallback? onDetails,

  /// The hand-over cell, for the decided tables. Null on the undecided table,
  /// where the column does not exist — pass one exactly when the columns are
  /// [kUnsoldDecidedColumns], or the cells and columns will not line up.
  Widget? delivery,

  /// The price this package was LAST TENDERED AT by the committee round —
  /// the ADG's **submitted** value, not the committee's bare recommendation.
  ///
  /// ⚠️ Pass `submittedValue`, never `committeeValue` on its own. A recorded
  /// committee figure with no submission is a reserve price that has not been
  /// tendered yet, and printing it here would leak it. Every row in this table
  /// comes from `exhaustedUnsoldProvider`, which already requires the ADG's
  /// submission, so the submitted value is always the one to show.
  ///
  /// It supersedes the original: by the time a package is unsold it has been
  /// through the Valuation tender, up to three re-valued rounds and then the
  /// committee round, and the committee's figure is the last price it was
  /// actually offered at.
  double? committeeUnitValue,

  /// Colour of the Valuation figure. The directorate tables highlight it in
  /// green because the money is what they act on; the yard is only being told
  /// what happened, so it reads as ordinary body text there.
  Color? valuationColor,
}) {
  final f = info.forfeited;
  final pkg = f.packageDetails;
  final qty = unsoldQty(f);
  // Committee figure first, then the original. Both are PER UNIT.
  final unit = committeeUnitValue ?? f.valuationCost;
  final value = unit != null ? unit * qty : null;
  final isCommittee = committeeUnitValue != null;
  // Sealed while the newest round is still to be held: its reserve price is
  // live until bidding closes. Derived from `info` rather than passed in, so
  // no caller can forget it. Ordered by the sale MOMENT — `latestSale` is
  // newest-by-created_at, and those two can disagree.
  final currentSale = info.sales.isEmpty
      ? null
      : (info.sales.toList()
            ..sort((a, b) {
              final am = a.saleMoment, bm = b.saleMoment;
              if (am == null || bm == null) return 0;
              return am.compareTo(bm);
            }))
          .last;
  final sealed = currentSale != null && !currentSale.saleEnded;
  // The yard belongs in the row's tooltip, not its own column: the yard page
  // shows one yard only, and the other two portals have a Yard dropdown.
  final srTip = '${f.srNumber} · ${yardName(f.yard)}'
      '${pkg?.caseNumber != null ? ' · ${pkg!.caseNumber}' : ''}';

  return [
    DataCell(Tooltip(
      message: srTip,
      waitDuration: const Duration(milliseconds: 300),
      child: Text(f.srNumber,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: srColor, fontWeight: FontWeight.w700)),
    )),
    DataCell(TooltipText(unsoldItemName(f), overflow: TextOverflow.ellipsis)),
    DataCell(TooltipText('$qty')),
    DataCell(TooltipText(f.consigneeName, overflow: TextOverflow.ellipsis)),
    DataCell(TooltipText(unsoldLocation(pkg, f.itemId, f.yard),
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: context.colors.textSecondary, fontSize: 12))),
    if (sealed)
      const DataCell(SealedValuation(compact: true))
    else
      DataCell(Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TooltipText(
              value == null
                  ? '—'
                  : 'LKR ${NumberFormat('#,##0').format(value)}',
              style: TextStyle(
                  color: valuationColor ?? context.colors.successGreen,
                  fontWeight: FontWeight.w700)),
          // Says WHOSE figure this is, so a committee price cannot be mistaken
          // for the original valuation.
          if (value != null)
            Text(
                isCommittee
                    ? 'committee · @ ${NumberFormat('#,##0').format(unit)} × $qty'
                    : '@ ${NumberFormat('#,##0').format(unit)} × $qty',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontSize: 10, color: context.colors.textMuted)),
        ],
      )),
    DataCell(outcome),
    if (delivery != null) DataCell(Center(child: delivery)),
    DataCell(Center(
      child: IconButton(
        icon: Icon(Icons.info_outline_rounded,
            color: context.colors.accentLightBlue, size: 18),
        onPressed: onDetails,
      ),
    )),
  ];
}

/// Hand-over for a package whose final outcome is already decided.
///
/// The mirror of the Sold table's delivery cell, and deliberately the same
/// pill: an officer reading the two tables side by side is reading one
/// question -- have these goods actually left the yard -- and it should not
/// look like two.
///
/// ⚠️ Marking delivered CLOSES THE WAREHOUSE ENTRY, inside the same statement
/// (see `disposal_toggle_outcome_delivery`). Goods that have gone must stop
/// counting against zone capacity and stop accruing storage, so this is not a
/// display flag -- it is the moment the yard stops holding them.
class UnsoldDeliveryCell extends ConsumerStatefulWidget {
  /// Null while the DG has not decided: nothing to hand over yet.
  final UnsoldProposalModel? proposal;

  const UnsoldDeliveryCell({super.key, required this.proposal});

  @override
  ConsumerState<UnsoldDeliveryCell> createState() => _UnsoldDeliveryCellState();
}

class _UnsoldDeliveryCellState extends ConsumerState<UnsoldDeliveryCell> {
  bool _saving = false;

  Future<void> _markDelivered(UnsoldProposalModel p) async {
    setState(() => _saving = true);
    try {
      await ref.read(disposalServiceProvider).toggleOutcomeDelivery(p.id, true);
      // ⚠️ Both proposal providers, not just the one this page reads. Central
      // Disposal's outcome tabs read the SAME row through the by-item map, so
      // refreshing one would leave the two portals disagreeing about whether
      // the goods had been handed over -- which is the exact bug the sold
      // flow's comment warns about.
      ref.invalidate(unsoldProposalsProvider);
      ref.invalidate(unsoldProposalsByItemProvider);
      // The hand-over closed the warehouse entry, so every page that asks
      // "where is this now" has to be told.
      ref.read(warehouseRefreshTriggerProvider.notifier).trigger();
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
    final p = widget.proposal;
    if (p == null) {
      return Text('—', style: TextStyle(color: context.colors.textMuted));
    }
    // Only a yard hands goods over; Central Disposal and the DG watch.
    final profile = ref.watch(currentProfileProvider);
    final canEdit = profile != null && !profile.isDisposal && !profile.isExecutive;

    return Tooltip(
      message: p.delivered
          ? (p.deliveredAt != null
              ? 'Handed over on '
                  '${DateFormat('yyyy-MM-dd').format(p.deliveredAt!)}'
              : 'The goods have left the yard')
          : (canEdit
              ? 'Confirm the goods have left the yard'
              : 'Awaiting the yard to confirm hand-over'),
      child: DeliveryStatusPill(
        delivered: p.delivered,
        busy: _saving,
        onMark: canEdit ? () => _markDelivered(p) : null,
      ),
    );
  }
}

/// The DG's decision, read-only. Shown on the yard page, on Central Disposal's
/// tab, and to the ADG.
class UnsoldOutcomeChip extends StatelessWidget {
  final UnsoldProposalModel? proposal;

  /// What to show while no outcome has been set. Defaults to naming the High
  /// Panel, which is right for the yard and Central Disposal — but INSIDE the
  /// Top Management Directorate portal that reads as telling them to wait for themselves, so
  /// the ADG's view passes [kAwaitingDg] to name the officer instead.
  final String pendingLabel;

  /// The price it fetched, when the goods SOLD at tender instead.
  ///
  /// ⚠️ A sale is a different ending from a proposal, and the two must not be
  /// confused: a perishable that sells never reaches the DG at all. Reading
  /// the outcome from unsold_proposals alone left CED/GL1/SR/30/2026 sold for
  /// Rs 5,533,000 and still showing "Awaiting Top Management".
  final double? soldPrice;

  const UnsoldOutcomeChip({
    super.key,
    required this.proposal,
    this.soldPrice,
    // ⚠️ Short enough to READ in the pill. The full
    // "Awaiting Top Management Directorate" was always clipped, so the word
    // that mattered -- who is being waited for -- was the part cut off. The
    // tooltip carries the full wording.
    this.pendingLabel = 'Awaiting Top Management',
  });

  /// Pending label for use inside the Top Management Directorate portal itself.
  static const String kAwaitingDg = 'Awaiting DG decision';

  @override
  Widget build(BuildContext context) {
    // ⚠️ Sold is checked FIRST. Selling is the outcome; there is nothing left
    // for anyone to decide, so a pending label here would be wrong even if a
    // proposal row somehow existed alongside it.
    final sold = soldPrice;
    if (sold != null) {
      return statusPill(
        context,
        color: context.colors.successGreen,
        icon: Icons.sell_rounded,
        label: 'Sold',
        tooltip: 'Sold at tender for Rs ${sold.toStringAsFixed(2)} — these '
            'goods never went to the Top Management Directorate',
      );
    }

    final p = proposal;
    // ⚠️ The SAME fixed box the Destroyed and Delivered columns use. Sizing
    // each pill to its own text made a column of them ragged -- "Convert"
    // came out half the width of "Remove from the Premises", so the eye
    // could not scan down the column, and the three tables that show these
    // side by side did not line up.
    if (p == null) {
      return statusPill(
        context,
        color: context.colors.warningAmber,
        icon: Icons.hourglass_bottom_rounded,
        label: pendingLabel,
        tooltip: pendingLabel,
      );
    }
    final st = unsoldOutcomeStyle(context, p.proposal);
    return statusPill(
      context,
      color: st.colour,
      icon: st.icon,
      label: p.label,
      tooltip: p.note?.trim().isNotEmpty == true
          ? p.note!.trim()
          : 'Decided ${DateFormat('yyyy-MM-dd').format(p.decidedAt)}',
    );
  }
}
