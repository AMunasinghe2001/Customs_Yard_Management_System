import 'package:flutter/material.dart';

import '../models/models.dart';
import 'styled_dropdown.dart';

/// Narrows a list to ONE final outcome.
///
/// ⚠️ This replaces a three-chip "All / Awaiting decision / Decided" filter,
/// which answered a question nobody was asking. An officer looking at a page
/// of decided goods does not need to be told THAT they were decided -- every
/// row says so already. What they want is the ones sent to auction, or the
/// ones going back out of the country; "Decided" lumped all six outcomes into
/// one bucket.
///
/// Awaiting is still reachable -- it is an entry in the list, because "nobody
/// has ruled yet" is an answer like any other.
class OutcomeFilter extends StatelessWidget {
  /// The chosen outcome, [awaiting], [sold], or null for all of them.
  final String? value;
  final ValueChanged<String?> onChanged;

  /// Which outcomes this page can actually show.
  ///
  /// ⚠️ Given, not assumed. Offering an outcome a page can never contain is a
  /// filter that only ever returns nothing.
  final List<String> outcomes;

  /// Whether to offer "Sold at tender" as well.
  ///
  /// Only Perishable Goods needs it: a perishable that sells ends there and
  /// never reaches the DG, so on that page a sale IS a final outcome.
  final bool includeSold;

  /// The value used for the "not decided yet" entry.
  static const String awaiting = '__awaiting__';

  /// The value used for the "sold at tender" entry.
  static const String sold = '__sold__';

  /// The portal's colour for a chosen value.
  final Color? accent;

  /// Draw at the size of Central Disposal's segmented filter chips.
  ///
  /// ⚠️ The two portals put this control in different company, and it has to
  /// match whichever it is in. Central Disposal sets it beside the
  /// All / Destroyed / Pending chips -- 13pt, a tinted fill when chosen. The
  /// yard sets it in a row of filter BUTTONS (Date Range, Post Status
  /// Activity, the year) which are smaller and outlined. Forcing the chip
  /// shape on the yard made it taller than its neighbours and filled where
  /// they are not.
  final bool chipStyle;

  const OutcomeFilter({
    super.key,
    required this.value,
    required this.onChanged,
    required this.outcomes,
    this.includeSold = false,
    this.accent,
    this.chipStyle = false,
  });

  @override
  Widget build(BuildContext context) {
    return StyledDropdownButton<String>(
      value: value,
      allLabel: 'All outcomes',
      icon: Icons.flag_rounded,
      // Chip beside chips, button beside buttons -- see [chipStyle].
      chipStyle: chipStyle,
      accentColor: accent,
      onChanged: onChanged,
      options: [
        // ⚠️ First, not last. On a page waiting for the DG it is the state
        // most rows are in, so it belongs at the top rather than under six
        // outcomes the officer has to read past.
        const StyledDropdownOption(awaiting, 'Awaiting decision'),
        if (includeSold) const StyledDropdownOption(sold, 'Sold at tender'),
        for (final o in outcomes)
          StyledDropdownOption(o, unsoldProposalLabel(o)),
      ],
    );
  }
}
