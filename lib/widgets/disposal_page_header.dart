import 'package:flutter/material.dart';

import '../core/theme.dart';

/// The header the four "Send Disposal Request" pages share — Detained,
/// Forfeited, Abandoned and Other.
///
/// All four used a [Wrap] holding the title block and an unbreakable Row of
/// stat chips plus the action button. A Wrap child cannot shrink, so the whole
/// stats-and-button Row dropped to its own line the moment the title block no
/// longer left it room — and because the four pages carry subtitles of very
/// different lengths, they broke at four different window widths. Detained,
/// whose subtitle is the longest, dropped while there was still plenty of
/// space.
///
/// Here the TITLE is the part that gives. The trailing block is laid out
/// first, capped so it can never take more than what leaves [minTitleWidth]
/// for the title; the title then fills whatever remains, wrapping to a second
/// line and ellipsizing. So the stats and the button keep their place at every
/// width, and a long subtitle narrows itself instead of pushing them down.
///
/// The cap is what makes this safe rather than merely tidy: at the app's
/// minimum window the chips and the button together want more room than the
/// content area has, so without it the Row would overflow. Capped, the
/// trailing block scrolls horizontally instead.
class DisposalPageHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  /// Stat chips and the action button, in order. Laid out at their natural
  /// size — this is the part that must not move.
  final List<Widget> trailing;

  /// Gap between the trailing children.
  final double trailingGap;

  /// The width the title block always keeps, however wide the trailing block
  /// would like to be. Enough for the title plus a readable slice of subtitle.
  final double minTitleWidth;

  /// The mark's colour, when one is shown. Defaults to gold.
  final Color? titleIconColor;

  /// Optional mark beside the title, tinted [AppColors.primaryGold] like the
  /// nav rail's icons. ⚠️ An icon, never an emoji -- emoji come from a colour
  /// font, so they ignore the theme and stay multi-coloured against a palette
  /// built from one accent.
  final IconData? titleIcon;

  const DisposalPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.titleIcon,
    this.titleIconColor,
    required this.trailing,
    this.trailingGap = 8,
    this.minTitleWidth = 190,
  });

  static const double _gap = 16;

  List<Widget> get _spacedTrailing {
    final out = <Widget>[];
    for (var i = 0; i < trailing.length; i++) {
      if (i > 0) out.add(SizedBox(width: trailingGap));
      out.add(trailing[i]);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        // What the trailing block may occupy at most. A Row lays its
        // non-flexible children out before the flexible one, so this cap is
        // what guarantees the title keeps its minimum.
        final trailingCap =
            (available - minTitleWidth - _gap).clamp(0.0, available);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (titleIcon != null) ...[
                        Icon(titleIcon,
                            // Matches headlineLarge's height, so the mark sits
                            // on the title rather than beside and above it.
                            size: Theme.of(context)
                                    .textTheme
                                    .headlineLarge
                                    ?.fontSize ??
                                22,
                            color: titleIconColor ??
                                context.colors.primaryGold),
                        const SizedBox(width: 10),
                      ],
                      // The title is the part that gives on a narrow window.
                      Flexible(
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.headlineLarge),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: context.colors.textSecondary, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(width: _gap),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: trailingCap),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                // Right-aligned when it does fit, so the button stays pinned
                // to the edge the way it always has.
                reverse: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: _spacedTrailing,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
