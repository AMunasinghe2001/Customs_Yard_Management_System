import 'package:flutter/material.dart';
import '../core/theme.dart';

/// The valuation is a RESERVE PRICE, and showing it before bidding closes
/// invites collusion: anyone who can see the figure knows the lowest bid that
/// will be accepted. Management's instruction is that it must not appear
/// anywhere — table, popup or report — until the tender or destruction sale
/// that the goods are in has actually run.
///
/// [saleEnded] is the sale's CLOSE moment (`sale_date` + `sale_end_time`), not
/// its start. A reserve price must stay hidden for as long as bidding is open,
/// so the start time is exactly the wrong gate — it is when the figure becomes
/// most dangerous, not safe. Mark Sold still unlocks on the start.
///
/// Pass `true` where no sale is in progress (unsold pools, re-valuation,
/// committee work, reports on concluded sales): nothing is left to protect.
bool valuationSealed({required bool saleEnded}) => !saleEnded;

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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded,
                  size: compact ? 12 : 14, color: muted),
              const SizedBox(width: 4),
              Text(
                'Sealed',
                style: TextStyle(
                    color: muted,
                    fontSize: compact ? 11 : 12,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          // The reason, not just the state. A lone "Sealed" reads as a glitch
          // or as "not valued yet", which sends people looking for the figure
          // somewhere else — exactly the leak this is meant to close.
          Text(
            'shown once the tender closes',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: muted, fontSize: compact ? 9.5 : 11),
          ),
        ],
      ),
    );
  }
}
