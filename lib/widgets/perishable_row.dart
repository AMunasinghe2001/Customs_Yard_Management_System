import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

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
    return GestureDetector(
      onTap: () => onChanged(!selected),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: selected ? accent : context.colors.borderColor),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(selected ? Icons.check_rounded : Icons.eco_rounded,
              size: 15,
              color: selected ? accent : context.colors.textSecondary),
          const Gap(6),
          Text('Perishable',
              style: TextStyle(
                  color: selected ? accent : context.colors.textSecondary,
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
        ]),
      ),
    );
  }
}
