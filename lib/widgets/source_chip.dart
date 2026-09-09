import 'package:flutter/material.dart';

import '../core/theme.dart';

/// How goods came to be in the yard: forfeit, abandoned, detained, other, or
/// perishable.
///
/// ⚠️ ONE definition. It lived private inside Central Disposal, and the
/// Valuation Directorate needed the same tag on the same packages — a copy
/// would be two colour tables for one fact, and the first time somebody added
/// a source they would update one of them.
///
/// ⚠️ The tag decides what may be DONE with the goods, which is why it belongs
/// beside the disposition rather than buried in a popup: a valuer pricing an
/// abandoned lot and a valuer pricing a forfeited one are answering different
/// questions about the same figure.
class SourceChip extends StatelessWidget {
  const SourceChip({super.key, required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (source.trim().toLowerCase()) {
      'abandoned' => ('Abandoned', context.colors.heldOrange),
      'other' => ('Other', context.colors.warningAmber),
      'perishable' => ('Perishable', context.colors.dangerRed),
      // ⚠️ Detained is its OWN source, not a kind of forfeit. It was falling
      // into the default and reading "Forfeit" — goods still under inquiry
      // labelled as goods the state has taken.
      'detain' || 'detained' => ('Detained', context.colors.accentLightBlue),
      '' || '—' => ('—', context.colors.textMuted),
      _ => ('Forfeit', context.colors.accentBlue),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}
