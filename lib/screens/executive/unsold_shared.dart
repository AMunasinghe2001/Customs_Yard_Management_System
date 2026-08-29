import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/yards.dart';
import '../../models/models.dart';
import '../../widgets/tooltip_text.dart';

/// ONE definition of the Unsold Packages table, shared by all three portals —
/// the yard's Unsold page, Central Disposal's Unsold tab and the High Panel's
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

String? unsoldHsCode(ForfeitedPackageModel f) {
  final items = f.packageDetails?.items ?? const [];
  if (f.itemId != null) {
    final m = items.where((i) => i.id == f.itemId).firstOrNull;
    if (m != null) return m.hsCode;
  }
  return items.isNotEmpty ? items.first.hsCode : null;
}

/// Warehouse · zone the item currently sits in (latest entry).
String unsoldLocation(PackageModel? pkg, String? itemId) {
  if (pkg == null) return '—';
  var entries = itemId != null
      ? pkg.warehouseEntries.where((e) => e.packageItemId == itemId).toList()
      : <WarehouseEntryModel>[];
  if (entries.isEmpty) entries = [...pkg.warehouseEntries];
  if (entries.isEmpty) return '—';
  entries.sort((a, b) => b.admittedAt.compareTo(a.admittedAt));
  final w = entries.first;
  return (w.zone != null && w.zone!.isNotEmpty)
      ? '${w.warehouseName} · ${w.zone}'
      : w.warehouseName;
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
    case 'remand':
      return (
        icon: Icons.reply_all_rounded,
        colour: context.colors.accentLightBlue
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
/// single-outcome page (Government Use, Remanded, Auction, Converted, Removed)
/// every row carries the SAME chip — it is the page's own title repeated — so
/// those pages show **Decided On** instead, which does differ per row.
const List<DataColumn2> kUnsoldColumns = [
  DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
  DataColumn2(label: Text('Goods Name'), size: ColumnSize.L),
  DataColumn2(label: Text('Qty'), size: ColumnSize.S, fixedWidth: 60),
  DataColumn2(label: Text('Consignee'), size: ColumnSize.M),
  DataColumn2(label: Text('Location'), size: ColumnSize.M),
  DataColumn2(label: Text('Valuation'), size: ColumnSize.S, fixedWidth: 120),
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
  DataColumn2(label: Text('Valuation'), size: ColumnSize.S, fixedWidth: 120),
  DataColumn2(
      label: Center(child: Text('Decided On')),
      size: ColumnSize.M,
      fixedWidth: 235),
  DataColumn2(
      label: Center(child: Text('Details')),
      size: ColumnSize.S,
      fixedWidth: 66),
];

/// The date the High Panel recorded this outcome, for [kUnsoldDecidedColumns].
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

  /// Colour of the Valuation figure. The directorate tables highlight it in
  /// green because the money is what they act on; the yard is only being told
  /// what happened, so it reads as ordinary body text there.
  Color? valuationColor,
}) {
  final f = info.forfeited;
  final pkg = f.packageDetails;
  final qty = unsoldQty(f);
  final value = f.valuationCost != null ? f.valuationCost! * qty : null;
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
    DataCell(TooltipText(unsoldLocation(pkg, f.itemId),
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: context.colors.textSecondary, fontSize: 12))),
    DataCell(TooltipText(
        value == null ? '—' : 'LKR ${NumberFormat('#,##0').format(value)}',
        style: TextStyle(
            color: valuationColor ?? context.colors.successGreen,
            fontWeight: FontWeight.w700))),
    DataCell(outcome),
    DataCell(Center(
      child: IconButton(
        icon: Icon(Icons.info_outline_rounded,
            color: context.colors.accentLightBlue, size: 18),
        onPressed: onDetails,
      ),
    )),
  ];
}

/// The DG's decision, read-only. Shown on the yard page, on Central Disposal's
/// tab, and to the ADG.
class UnsoldOutcomeChip extends StatelessWidget {
  final UnsoldProposalModel? proposal;

  /// What to show while no outcome has been set. Defaults to naming the High
  /// Panel, which is right for the yard and Central Disposal — but INSIDE the
  /// High Panel portal that reads as telling them to wait for themselves, so
  /// the ADG's view passes [kAwaitingDg] to name the officer instead.
  final String pendingLabel;

  const UnsoldOutcomeChip({
    super.key,
    required this.proposal,
    this.pendingLabel = 'Awaiting High Panel',
  });

  /// Pending label for use inside the High Panel portal itself.
  static const String kAwaitingDg = 'Awaiting DG decision';

  @override
  Widget build(BuildContext context) {
    final p = proposal;
    if (p == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: context.colors.warningAmber.withOpacity(0.10),
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: context.colors.warningAmber.withOpacity(0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.hourglass_bottom_rounded,
              size: 13, color: context.colors.warningAmber),
          const Gap(5),
          Flexible(
            child: Text(pendingLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: context.colors.warningAmber,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
      );
    }
    final st = unsoldOutcomeStyle(context, p.proposal);
    return Tooltip(
      message: p.note?.trim().isNotEmpty == true
          ? p.note!.trim()
          : 'Decided ${DateFormat('yyyy-MM-dd').format(p.decidedAt)}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: st.colour.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: st.colour.withOpacity(0.45)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(st.icon, size: 13, color: st.colour),
          const Gap(5),
          Flexible(
            child: Text(p.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: st.colour,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
    );
  }
}
