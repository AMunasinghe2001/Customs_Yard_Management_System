import 'package:flutter/material.dart';
import '../core/theme.dart';

/// The valuation is a RESERVE PRICE, and showing it before bidding closes
/// invites collusion: anyone who can see the figure knows the lowest bid that
/// will be accepted. Management's instruction is that it must not appear
/// anywhere — table, popup or report — until the tender or destruction sale
/// that the goods are in has actually run.
///
/// [saleTimePassed] is the same clock gate that already unlocks Mark Sold, so
/// "the sale is over" means exactly one thing across the app.
///
/// Call [sealed] with the sale's own `saleTimePassed`; pass `true` where no
/// sale is in progress (unsold pools, re-valuation, committee work, reports on
/// concluded sales), because there is nothing left to protect there.
bool valuationSealed({required bool saleTimePassed}) => !saleTimePassed;

/// The placeholder shown in place of a valuation that is still sealed.
///
/// Deliberately says WHY the figure is missing — an empty cell reads as "not
/// valued yet" and prompts someone to go looking for the number elsewhere.
class SealedValuation extends StatelessWidget {
  /// Compact form for a narrow table cell; the long form suits a popup row.
  final bool compact;
  const SealedValuation({super.key, this.compact = false});

  static const String tooltip =
      'The valuation is hidden until the sale has taken place. It is the '
      'reserve price, so it stays sealed while bidding is still open.';

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.textMuted;
    return Tooltip(
      message: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline_rounded,
              size: compact ? 12 : 14, color: muted),
          const SizedBox(width: 4),
          Text(
            compact ? 'Sealed' : 'Sealed until sale',
            style: TextStyle(
                color: muted,
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
