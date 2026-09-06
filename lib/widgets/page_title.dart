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
/// An [IconData] takes [AppColors.primaryGold] exactly like the nav rail's
/// icons, so the heading, the tab strip and the rail finally agree.
///
/// Pass the SAME icon the tab strip uses for that page: the eye should be able
/// to carry a mark from the tab it clicked to the heading that answers it.
class PageTitle extends StatelessWidget {
  final String text;
  final IconData icon;

  /// Matches the 22pt headings this replaces.
  final double fontSize;

  const PageTitle(this.text, this.icon, {super.key, this.fontSize = 22});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: fontSize, color: context.colors.primaryGold),
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
