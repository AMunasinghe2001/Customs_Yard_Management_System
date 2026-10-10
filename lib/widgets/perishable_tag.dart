import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../core/theme.dart';
import '../models/models.dart';

/// Marks a request or a tender sale as carrying PERISHABLE goods.
///
/// ⚠️ Perishables arrive together, as their own request and their own sale --
/// they may only enter a Special Tender Sale, so they are never mixed with
/// normal goods. That makes a header label exactly right: it describes the
/// whole batch, and there is nothing else in it to contradict.
///
/// Without it an officer had no way to tell: a valued perishable looked like
/// any other line on the Disposal Requests page, yet it is on a completely
/// different clock -- no warehouse, no appeal window, one sale and then the
/// DG decides.
class PerishableTag extends StatelessWidget {
  /// Smaller, for sitting inside a dense header row.
  final bool compact;
  const PerishableTag({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final green = context.colors.successGreen;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10, vertical: compact ? 4 : 6),
      decoration: BoxDecoration(
        color: green.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: green.withOpacity(0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.eco_rounded, size: compact ? 12 : 14, color: green),
        Gap(compact ? 5 : 6),
        Text('Perishable Goods',
            style: TextStyle(
                color: green,
                fontSize: compact ? 10.5 : 12,
                fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// True when every item in [items] is perishable.
///
/// ⚠️ EVERY item, not any. The tag speaks for the whole batch, so a mixed set
/// must not wear it -- that would tell the officer the normal goods beside it
/// are also on the perishable clock.
bool allPerishable(Iterable<PackageItem> items) =>
    items.isNotEmpty && items.every((i) => i.nature == kNaturePerishable);
