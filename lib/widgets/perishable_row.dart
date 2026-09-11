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
