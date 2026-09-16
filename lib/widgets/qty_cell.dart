import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/models.dart';

/// How a quantity reads in a table cell when the goods arrived in cartons.
///
/// ⚠️ THE RULE, given directly: goods registered in cartons are counted as
/// `cartons × per-carton`. `package_items.quantity` holds that TOTAL -- the
/// operational count every charge, capacity figure and total in the app reads
/// -- while `innerUnit`/`innerQuantity` keep the outer packaging ("20
/// Cartons") for display only.
///
/// A bare `quantity` therefore tells the truth about the count but loses how
/// the goods actually turned up, and an officer looking at a pallet of twenty
/// cartons cannot reconcile "1176" with what is in front of them. These two
/// helpers put the packaging back beside the number, in one wording, so the
/// twenty-odd tables that show a Qty column cannot drift into twenty
/// different ones.

/// The full sentence: "1176 Pieces (in 20 Cartons)".
///
/// Falls back to "1176 Pieces" when the goods carry no packaging wrapper, and
/// to a bare "1176" when the unit is unknown.
String qtyWithPackaging(PackageItem? item, {int? overrideQty}) {
  final qty = overrideQty ?? item?.effectiveQuantity ?? 0;
  final unit = item?.effectiveUnit.trim() ?? '';
  final packaging = item?.packagingLabel;

  final head = unit.isEmpty ? '$qty' : '$qty $unit';
  return packaging == null ? head : '$head (in $packaging)';
}

/// The compact table form: the total on top, the packaging beneath it.
///
/// ⚠️ Two lines, not one. A Qty column is narrow -- most are 60-80px -- and
/// "1176 Pieces (in 20 Cartons)" either overflows it or ellipses away the
/// very part that was added. Stacking keeps both readable in the width the
/// column already has, and rows with no packaging stay a single centred
/// number exactly as before.
class QtyCell extends StatelessWidget {
  const QtyCell({super.key, required this.item, this.overrideQty});

  /// The item the row is about. Null renders [overrideQty] alone.
  final PackageItem? item;

  /// The count to show instead of the item's own — a warehouse entry's
  /// `itemCount`, for instance, which can be a PART of the item.
  ///
  /// ⚠️ When this differs from the item's own total the packaging line is
  /// dropped: "(in 20 Cartons)" beside a partial count would be a claim
  /// about the part that is not true of it.
  final int? overrideQty;

  @override
  Widget build(BuildContext context) {
    final qty = overrideQty ?? item?.effectiveQuantity ?? 0;
    final packaging = item?.packagingLabel;
    final isWhole = overrideQty == null ||
        (item != null && overrideQty == item!.effectiveQuantity);

    if (packaging == null || !isWhole) {
      return Center(child: Text('$qty'));
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$qty',
              style: const TextStyle(fontWeight: FontWeight.w600, height: 1.1)),
          Text('in $packaging',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 10.5,
                  height: 1.2,
                  color: context.colors.textMuted)),
        ],
      ),
    );
  }
}
