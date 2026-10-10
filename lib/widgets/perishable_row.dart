import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/models.dart';

/// Whether these goods are PERISHABLE.
///
/// ⚠️ `forfeited_packages.source` is the authority, not a guess from the
/// item's nature or its name. postgres/07 made 'perishable' a real source
/// value for exactly this reason, so a screen reads what the goods ARE
/// rather than inferring it through a join that may not be loaded.
///
/// Falls back to the item's own `nature` for goods that never reached a
/// forfeited record — a perishable can be sold or released straight out of
/// the yard without one.
bool isPerishableGoods({ForfeitedPackageModel? forfeited, PackageItem? item}) {
  if (forfeited?.source.trim().toLowerCase() == kNaturePerishable) return true;
  return item?.nature.trim().toLowerCase() == kNaturePerishable;
}

/// The wash a perishable row carries in a mixed table.
///
/// ⚠️ Far fainter than the amber the tender cards use. There the colour
/// means "act now, these are spoiling"; here it only means "this row is a
/// different kind of goods", and a row of full-strength amber down a
/// twenty-row table reads as a warning nobody can act on. It has to be
/// findable at a glance and ignorable at a distance, so the tint sits at
/// roughly a tenth of the card's.
///
/// Null for ordinary goods, so a caller can hand it straight to
/// `DataRow.color` without a branch.
Color? perishableRowColor(BuildContext context, bool isPerishable) =>
    isPerishable ? context.colors.warningAmber.withOpacity(0.06) : null;

/// The same colour at chip strength, for a legend or a badge.
Color perishableAccent(BuildContext context) => context.colors.warningAmber;

/// The "Perishable" narrowing chip, for any table that mixes them in.
///
/// ⚠️ Two states, not three. A "non-perishable" option would be a question
/// nobody asks, and an unselected chip already means "all goods" — so the
/// off state is null at the query, never `false`, which would hide every
/// perishable row instead of showing them all.
///
/// Lives here rather than on one screen because the Sold / Destroyed /
/// Re-exported / Released pages and the Unsold / Final Outcome pages all
/// need the identical control; two copies of it drift.
class PerishableFilterChip extends StatelessWidget {
  const PerishableFilterChip({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = perishableAccent(context);
    final fg = selected ? accent : context.colors.textSecondary;

    // ⚠️ An OutlinedButton.icon, with the SAME numbers the Date Filter and
    // the All / Delivered / Pending buttons beside it use: font 12, icon 16,
    // horizontal padding 12, radius 8. It used to be a hand-rolled Container
    // on the segmented-chip metrics (padding 14/9, radius 10, icon 15,
    // 12.5pt), which is a different control's shape — so it sat visibly
    // shorter and rounder than every button it shared the row with, and a
    // Wrap's `spacing` could not hide it because the gap is only equal when
    // the boxes are.
    return OutlinedButton.icon(
      onPressed: () => onChanged(!selected),
      icon: Icon(selected ? Icons.check_rounded : Icons.eco_rounded,
          size: 16, color: fg),
      label: Text('Perishable',
          style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      style: OutlinedButton.styleFrom(
        backgroundColor:
            selected ? accent.withOpacity(0.15) : Colors.transparent,
        side: BorderSide(color: selected ? accent : context.colors.borderColor),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
