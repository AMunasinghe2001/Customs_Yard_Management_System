/// The ICT console's own chrome.
///
/// ICT is the app's one ADMIN console — four unrelated areas a system admin
/// moves between all day — so it is laid out as an ERP dashboard: a permanent
/// rail, metric tiles, one toolbar strip per screen, and tables that live
/// inside a titled card rather than floating under a page heading.
///
/// ⚠️ Everything here is PRIVATE TO ICT ON PURPOSE. The look is carried by
/// widgets in this file, never by edits to `AppTheme`, because the theme is
/// shared with every other portal and those must not change. Two consequences
/// worth knowing:
///   * [IctTableTheme] restyles DataTable2 locally, so a call site that also
///     passes `headingTextStyle`/`headingRowColor` would win over it. ICT's
///     tables deliberately pass neither.
///   * Every colour here is read from [AppColors]. This is a different LAYOUT
///     of the existing palette, not a different palette.
library;

import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../core/theme.dart';
import '../../widgets/styled_dropdown.dart';

/// Cards, controls and pills, so nothing in ICT rounds a corner by a
/// different amount than its neighbour.
const double kIctCardRadius = 12;
const double kIctControlRadius = 10;
const double kIctPillRadius = 6;

/// Every filter, search box and toolbar button is this tall, so a toolbar
/// reads as one strip instead of a set of controls that each chose a height.
const double kIctControlHeight = 42;

/// ⚠️ One width for every status pill in ICT. The widest label any of them
/// carries is "INACTIVE"; sizing each to its own text left a status column of
/// ragged boxes, which is a good part of why the tables looked hand-assembled.
const double kIctPillWidth = 92;

/// The ICT table row height, shared by DataTable2 and by the hand-built rows
/// in the Yards & Directorates tab so the two cannot drift apart.
const double kIctRowHeight = 50;
const double kIctHeadingHeight = 40;

// ── Surfaces ────────────────────────────────────────────────────────────────

/// A flat ERP surface: no shadow, one hairline border, one radius.
class IctCard extends StatelessWidget {
  const IctCard({
    super.key,
    required this.child,
    this.padding,
    this.clip = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;

  /// Clips the child to the card's radius. Tables need it — without it the
  /// heading row paints over the rounded corners and they read as square.
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final body =
        padding == null ? child : Padding(padding: padding!, child: child);
    return Container(
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(kIctCardRadius),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: clip
          ? ClipRRect(
              borderRadius: BorderRadius.circular(kIctCardRadius - 1),
              child: body)
          : body,
    );
  }
}

/// A card that names what it holds in its own header strip.
///
/// The section title, its explanation, the row count and the section's primary
/// action all sit ON the card rather than floating above it. That is the
/// difference between a page that has a table on it and an ERP module: the
/// card is the unit, and its header says what you are looking at and what you
/// can do to it.
class IctSectionCard extends StatelessWidget {
  const IctSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.subtitle,
    this.badge,
    this.actions = const [],
    this.height,
    this.padded = false,
    this.fill = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;

  /// A count, shown as a quiet pill beside the title ("264 records").
  final String? badge;
  final List<Widget> actions;
  final Widget child;

  /// A fixed body height, for a card inside a scrolling page.
  final double? height;

  /// Pads the body. Tables want it off so their rows reach the card's edges.
  final bool padded;

  /// The body takes all the height the card is given, for a card placed in an
  /// [Expanded]. Off by default so a card can size to its own rows.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final body = padded
        ? Padding(padding: const EdgeInsets.all(16), child: child)
        : child;
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: c.cardDark,
        borderRadius: BorderRadius.circular(kIctCardRadius),
        border: Border.all(color: c.borderColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kIctCardRadius - 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: (height == null && !fill)
              ? MainAxisSize.min
              : MainAxisSize.max,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
              child: Row(children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: c.textSecondary),
                  const Gap(10),
                ],
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800)),
                      if (subtitle != null) ...[
                        const Gap(3),
                        Text(subtitle!,
                            style: TextStyle(
                                color: c.textMuted,
                                fontSize: 11.5,
                                height: 1.35)),
                      ],
                    ],
                  ),
                ),
                if (badge != null) ...[
                  const Gap(10),
                  IctCountBadge(text: badge!),
                ],
                const Spacer(),
                for (final a in actions) ...[const Gap(8), a],
              ]),
            ),
            Divider(height: 1, thickness: 1, color: c.borderColor),
            // ⚠️ Expanded ONLY when the card was given a height to fill.
            // A card that sizes to its own rows is often inside a scrolling
            // page, where the column's height is unbounded — and any flexed
            // child in an unbounded column is a layout assertion, not a
            // smaller card.
            if (height != null || fill) Expanded(child: body) else body,
          ],
        ),
      ),
    );
  }
}

/// The quiet count beside a section title.
class IctCountBadge extends StatelessWidget {
  const IctCountBadge({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.colors.surfaceDark,
        borderRadius: BorderRadius.circular(kIctPillRadius),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Text(text,
          style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700)),
    );
  }
}

/// An ERP metric tile: the measure's name, the number, then what the number
/// counts — in that order, because the number is what the eye came for.
class IctMetricCard extends StatelessWidget {
  const IctMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.color,
  });

  final String label, value, caption;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: c.cardDark,
        borderRadius: BorderRadius.circular(kIctCardRadius),
        border: Border.all(color: c.borderColor),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: c.textMuted,
                      fontSize: 10,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w800)),
              const Gap(9),
              Text(value,
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 26,
                      height: 1,
                      fontWeight: FontWeight.w800)),
              const Gap(7),
              Text(caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.textSecondary, fontSize: 11)),
            ],
          ),
        ),
        const Gap(12),
        // The measure's colour as a small square rather than a full wash:
        // four tinted tiles in a row would compete with the data below them.
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(kIctControlRadius),
            border: Border.all(color: color.withOpacity(0.28)),
          ),
          child: Icon(icon, color: color, size: 19),
        ),
      ]),
    );
  }
}

// ── Toolbar ─────────────────────────────────────────────────────────────────

/// The strip of controls above a table: search, filters, then the primary
/// action. One card, one row, one height — see [kIctControlHeight].
class IctToolbar extends StatelessWidget {
  const IctToolbar({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(kIctCardRadius),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const Gap(10),
          children[i],
        ],
      ]),
    );
  }
}

/// ICT's search box: neutral, not accent-tinted.
///
/// ⚠️ A search field is where the eye should land LAST, after the metrics and
/// the section title. ICT's was filled and bordered in the portal accent,
/// which made the loudest thing on the page the box you type into.
class IctSearchField extends StatelessWidget {
  const IctSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.accent,
    required this.onChanged,
    this.onClear,
  });

  final TextEditingController controller;
  final String hintText;
  final Color accent;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(kIctControlRadius),
      borderSide: BorderSide(color: c.borderColor),
    );
    return SizedBox(
      height: kIctControlHeight,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(
            color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          isDense: true,
          hintText: hintText,
          hintStyle: TextStyle(color: c.textMuted, fontSize: 13),
          prefixIcon: Icon(Icons.search_rounded, size: 18, color: c.textMuted),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 40, maxHeight: 20),
          suffixIcon: controller.text.isEmpty || onClear == null
              ? null
              : IconButton(
                  splashRadius: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 34),
                  icon: Icon(Icons.close_rounded, size: 15, color: c.textMuted),
                  onPressed: onClear,
                ),
          filled: true,
          fillColor: c.surfaceDark,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: border,
          enabledBorder: border,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(kIctControlRadius),
            borderSide: BorderSide(color: accent, width: 1.4),
          ),
        ),
      ),
    );
  }
}

/// One ICT filter: a small caption, then the control.
///
/// ⚠️ The caption is a real label above the field, not a Material floating
/// label inside it. A floating label sits ON the border and shrinks as soon as
/// a value is chosen, so a row of filters showed four differently-sized
/// half-labels; an ERP filter bar names each control the same way every time,
/// whether or not it is set.
class IctSelect extends StatelessWidget {
  const IctSelect({
    super.key,
    required this.label,
    required this.icon,
    required this.accent,
    required this.value,
    required this.options,
    required this.onChanged,
    this.menuWidth = 240,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final String value;
  final List<StyledDropdownOption<String>> options;
  final ValueChanged<String?> onChanged;
  final double menuWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Set apart from the default: an unset filter is the norm, so it must not
    // look like a warning, but a filter that IS narrowing the table has to be
    // visible at a glance or people forget it is on.
    final set = value != 'all';
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(kIctControlRadius),
      borderSide:
          BorderSide(color: set ? accent.withOpacity(0.55) : c.borderColor),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: c.textMuted,
                fontSize: 9.5,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w800)),
        const Gap(6),
        SizedBox(
          height: kIctControlHeight,
          child: Theme(
            data: Theme.of(context).copyWith(
              inputDecorationTheme:
                  Theme.of(context).inputDecorationTheme.copyWith(
                        border: border,
                        enabledBorder: border,
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(kIctControlRadius),
                          borderSide: BorderSide(color: accent, width: 1.4),
                        ),
                      ),
            ),
            child: StyledDropdownFormField<String>(
              value: value,
              label: label,
              // Never floats: the caption above already names the control.
              floatingLabelBehavior: FloatingLabelBehavior.never,
              helperText: null,
              isDense: true,
              menuWidth: menuWidth,
              fillColor: set ? accent.withOpacity(0.07) : c.surfaceDark,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              prefixIcon: Icon(icon,
                  size: 17, color: set ? accent : c.textMuted),
              valueStyle: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: set ? accent : c.textPrimary),
              options: options,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

/// The ICT toolbar's primary action, at the toolbar's own height.
class IctPrimaryButton extends StatelessWidget {
  const IctPrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.accent,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kIctControlHeight,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 17, color: Colors.white),
        label: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kIctControlRadius)),
        ),
      ),
    );
  }
}

/// A quiet ICT action button — the same height and radius as everything else
/// on a toolbar or a card header, but carried by an outline rather than a fill
/// so it cannot compete with the primary action beside it.
class IctGhostButton extends StatelessWidget {
  const IctGhostButton({
    super.key,
    required this.label,
    required this.icon,
    required this.accent,
    required this.onPressed,
    this.dense = false,
  });

  final String label;
  final IconData icon;
  final Color accent;

  /// Null disables the button, exactly as an [OutlinedButton] would read it.
  final VoidCallback? onPressed;

  /// For a button inside a table row, which has less height to give.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final on = onPressed != null;
    final tint = on ? accent : context.colors.textMuted;
    return SizedBox(
      height: dense ? 32 : kIctControlHeight,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: dense ? 14 : 16),
        label: Text(label,
            style: TextStyle(
                fontSize: dense ? 11.5 : 12.5, fontWeight: FontWeight.w700)),
        style: OutlinedButton.styleFrom(
          foregroundColor: tint,
          backgroundColor: on ? accent.withOpacity(0.07) : Colors.transparent,
          side: BorderSide(color: tint.withOpacity(on ? 0.45 : 0.3)),
          padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kIctControlRadius)),
        ),
      ),
    );
  }
}

/// A segmented control — one choice out of a short, fixed set.
///
/// ⚠️ Segments are joined into a single track, not spaced apart as separate
/// buttons. Spaced buttons read as five independent toggles, any number of
/// which might be on; a track reads as one setting with five positions, which
/// is what a period picker actually is.
class IctSegmented extends StatelessWidget {
  const IctSegmented({
    super.key,
    required this.accent,
    required this.children,
  });

  final Color accent;
  final List<IctSegment> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surfaceDark,
        borderRadius: BorderRadius.circular(kIctControlRadius),
        border: Border.all(color: c.borderColor),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final s in children) _IctSegmentTile(segment: s, accent: accent),
      ]),
    );
  }
}

/// One position of an [IctSegmented].
class IctSegment {
  const IctSegment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
}

class _IctSegmentTile extends StatelessWidget {
  const _IctSegmentTile({required this.segment, required this.accent});
  final IctSegment segment;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final on = segment.selected;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(kIctPillRadius),
        onTap: segment.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: on ? c.cardDark : Colors.transparent,
            borderRadius: BorderRadius.circular(kIctPillRadius),
            border: Border.all(
                color: on ? accent.withOpacity(0.5) : Colors.transparent),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(segment.icon,
                size: 14, color: on ? accent : c.textSecondary),
            const Gap(7),
            Text(segment.label,
                style: TextStyle(
                    color: on ? accent : c.textSecondary,
                    fontSize: 12.5,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
          ]),
        ),
      ),
    );
  }
}

// ── Table pieces ────────────────────────────────────────────────────────────

/// ICT's table look, applied locally.
///
/// ⚠️ Wrap ICT tables in this instead of editing `AppTheme.dataTableTheme` —
/// the theme is shared, and every other portal's tables must keep the gold
/// title-case headings. Inside an ERP card the heading row is a QUIET rule
/// over the data (small, uppercase, muted), because the card's own header is
/// already saying what the table is.
class IctTableTheme extends StatelessWidget {
  const IctTableTheme({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Theme(
      data: Theme.of(context).copyWith(
        dataTableTheme: Theme.of(context).dataTableTheme.copyWith(
              headingTextStyle: TextStyle(
                color: c.textMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.9,
              ),
              headingRowColor: WidgetStateProperty.all(c.surfaceDark),
              dataTextStyle: TextStyle(color: c.textPrimary, fontSize: 12.5),
              dividerThickness: 1,
            ),
      ),
      child: child,
    );
  }
}

/// A column heading, uppercased in one place.
///
/// ⚠️ Uppercasing is done HERE and not by typing capitals into the strings, so
/// the label stays readable in the source and every ICT table gets the same
/// treatment without anyone having to remember.
DataColumn2 ictCol(
  String label, {
  ColumnSize size = ColumnSize.M,
  double? fixedWidth,
  bool center = false,
}) {
  final text = Text(label.toUpperCase());
  return DataColumn2(
    label: center ? Center(child: text) : text,
    size: size,
    fixedWidth: fixedWidth,
  );
}

/// Zebra striping for row [i].
///
/// ⚠️ Alternating fills, not a divider under every row. At ICT's row heights a
/// full-width rule every 50px turns a long table into a ladder; a very faint
/// band on every other row tracks the eye across a wide row just as well and
/// leaves the data as the only thing with edges.
WidgetStateProperty<Color?> ictRowColor(BuildContext context, int i) {
  final c = context.colors;
  return WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.hovered)) return c.surfaceDark;
    return i.isEven ? Colors.transparent : c.surfaceDark.withOpacity(0.45);
  });
}

/// A status pill: a dot, then the state, at one width for the whole console.
///
/// The dot carries the state on its own, so the pill still reads at a glance
/// in a column of thirty rows where nobody is going to read the words.
class IctStatusPill extends StatelessWidget {
  const IctStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.tooltip,
    this.width = kIctPillWidth,
    this.dot = true,
  });

  final String label;
  final Color color;
  final String? tooltip;
  final double width;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      width: width,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(kIctPillRadius),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const Gap(6),
        ],
        Flexible(
          child: Text(label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color,
                  fontSize: 10,
                  letterSpacing: 0.4,
                  fontWeight: FontWeight.w800)),
        ),
      ]),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip!, child: pill);
  }
}
