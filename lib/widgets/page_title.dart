import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import '../core/theme.dart';

/// A page heading with its mark beside it.
///
/// ⚠️ These were emoji at first, and emoji were the wrong tool. They render
/// from a colour font (Segoe UI Emoji on Windows), so they cannot be tinted --
/// the label stayed orange, the recycle mark stayed green -- and a row of them
/// read as confetti against a palette built from one gold accent. They also
/// ignored the light/dark theme completely, being the only thing on the page
/// that did not change with it.
///
/// An [IconData] takes the PORTAL's own accent -- Central Disposal's green,
/// the Appeal Directorate's purple -- so a heading belongs to the page it
/// icons, so the heading, the tab strip and the rail finally agree.
///
/// Pass the SAME icon the tab strip uses for that page: the eye should be able
/// to carry a mark from the tab it clicked to the heading that answers it.
class PageTitle extends StatelessWidget {
  final String text;
  final IconData icon;

  /// Matches the 22pt headings this replaces.
  final double fontSize;

  /// The mark's colour.
  ///
  /// ⚠️ Defaults to gold, which is the nav rail's colour and right for the
  /// yard. A directorate should pass its OWN accent: gold marks on Central
  /// Disposal's green pages looked borrowed from somewhere else, because they
  /// were.
  final Color? accent;

  const PageTitle(this.text, this.icon,
      {super.key, this.fontSize = 22, this.accent});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon,
            size: fontSize, color: accent ?? context.colors.primaryGold),
        const Gap(10),
        // ⚠️ Flexible, not a bare Text: this heading sits in a Row beside a
        // fixed-width search box and yard filter, so on a narrow window the
        // title is the only part that can give.
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
