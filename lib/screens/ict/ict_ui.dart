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

import 'dart:ui' show ImageFilter;

import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../core/theme.dart';
import '../../widgets/disposal_profile_dialog.dart';
import '../../widgets/styled_dropdown.dart';

/// Cards, controls and pills, so nothing in ICT rounds a corner by a
/// different amount than its neighbour.
const double kIctCardRadius = 12;
const double kIctControlRadius = 10;
const double kIctPillRadius = 6;

/// ⚠️ ONE height for every control in the console — filters, search boxes,
/// toolbar buttons, the header's own controls. Nothing in ICT sets its own.
///
/// The height of a FIELD — a search box, a filter, a segment.
///
/// ⚠️ It took four tries to land here, which is the useful part. 34 equalised
/// the two by shrinking the dropdowns to the smaller of them; 42 took the
/// larger and the strip grew with it into a second header; 38 was right for
/// the fields but the Add button still looked taller than them.
///
/// It was not. Measured in a real toolbar, the search box, the filter and the
/// button all came back at exactly 38, same top, same bottom. The difference
/// is OPTICAL: a solid filled block reads larger than an outlined box of the
/// same size, because its whole area is ink and theirs is an edge. So the
/// fields go up and the button comes down to meet them — see
/// [kIctPrimaryButtonHeight].
const double kIctControlHeight = 40;

/// The same as a field. See [kIctFieldPadY] for what makes that true.
const double kIctPrimaryButtonHeight = kIctControlHeight;

/// ⚠️ The vertical padding that makes a field PAINT its full height.
///
/// This is the number the whole "the button is taller" argument came down to.
/// An InputDecorator does not stretch its border to the box you give it: with
/// `isDense`, it sizes its own container to the content plus this padding and
/// CENTRES that inside the box. So a field in a SizedBox(40) with 8px padding
/// laid out at 40 and painted at 34, while the button's fill ran the whole 40
/// — and every `getRect` in the test suite reported 40 for both, because 40 is
/// what the layout said.
///
/// 11 makes the painted border exactly kIctControlHeight: content (~16) +
/// 2 x 11 + the 1px stroke top and bottom. Change one and re-run
/// tool/measure_toolbar.py, which reads the PAINTED pixels out of a golden
/// rather than asking the widget tree what it meant to do.
const double kIctFieldPadY = 11;

/// ⚠️ The whole filter strip, capped. A caption, a control and the padding
/// around them — and nothing else. The strip sits above the table on every
/// page, so every pixel it takes is a row the officer cannot see without
/// scrolling, and it is the first thing to grow when a control starts setting
/// its own height. A test measures it.
const double kIctToolbarMaxHeight = 72;

/// A control inside a table row, which has less height to give.
const double kIctDenseHeight = 30;

/// Square icon actions — row actions, the header's icon buttons. Same radius
/// and border as every other control; only the width is different.
const double kIctIconButtonSize = 30;

/// ⚠️ The console header and the rail's brand block are BOTH this tall.
///
/// They are two separate widgets either side of the rail's right border, so
/// nothing makes their heights agree on its own — and when they disagreed the
/// rail's divider sat a few pixels off the header's, which reads as a notch
/// in the corner where the two meet.
const double kIctTopBarHeight = 62;

/// ⚠️ Material gives a button a 48px minimum tap target and its own padding,
/// both of which beat a SizedBox around it. Without this the Add Officer
/// button stood taller than the filters it sits beside, which is exactly what
/// kIctControlHeight exists to prevent.
const _kIctShrink = (
  minimumSize: Size.zero,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

/// ⚠️ One width for every status pill in ICT. The widest label any of them
/// carries is "INACTIVE"; sizing each to its own text left a status column of
/// ragged boxes, which is a good part of why the tables looked hand-assembled.
const double kIctPillWidth = 88;
const double kIctPillHeight = 22;

/// The ICT table row height, shared by DataTable2 and by the hand-built rows
/// in the Yards & Directorates tab so the two cannot drift apart.
const double kIctRowHeight = 44;
const double kIctHeadingHeight = 36;

/// ⚠️ The audit trail alone. Its card fills the window, so at kIctRowHeight
/// a page of 25 rows stopped well short of the bottom and left a band of bare
/// card under the table. The rows take that space instead.
const double kIctLogRowHeight = 52;

/// The gap between two columns of a table row.
const double kIctCellGap = 12;

/// ⚠️ The Status and Actions columns are FIXED, never flex. Given a flex share
/// they end up the narrowest columns in a wide row — which is how the Yards
/// table got a pill touching a button and a toggle 6px past the card's edge.
/// Wide enough for a kIctPillWidth pill, and for two icon buttons and the gap
/// between them, plus the cell gap on each side.
const double kIctStatusColumnWidth = kIctPillWidth + 16;
const double kIctActionsColumnWidth = kIctIconButtonSize * 2 + 8 + 16;

/// The portal accent, carried down the tree.
///
/// ⚠️ Every ICT widget needs the accent and almost none of them are given it —
/// a card header, a pager, a filter. Threading it through every constructor
/// would mean a required parameter on widgets that only want it to paint one
/// line, so the console publishes it once at the top instead.
class IctAccent extends InheritedWidget {
  const IctAccent({super.key, required this.color, required super.child});

  final Color color;

  /// Falls back to the app's plum, so a widget used outside the console (a
  /// test pumping one card, say) still paints something sensible.
  static Color of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<IctAccent>()?.color ??
      AppTheme.ictCyan;

  @override
  bool updateShouldNotify(IctAccent old) => old.color != color;
}

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
            Container(
              // ⚠️ A tinted strip. On a white page a white header over a white
              // table has only its rule to separate them, which is why the
              // console read as one long sheet of paper: the header is what
              // says "a new thing starts here", and it needs a surface of its
              // own to say it.
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    IctAccent.of(context).withOpacity(0.07),
                    IctAccent.of(context).withOpacity(0.02),
                  ],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: IctAccent.of(context)),
                  const Gap(10),
                ],
                // ⚠️ Expanded, not Flexible-plus-Spacer.
                //
                // Flexible takes only what it needs, and the Spacer took the
                // rest — so the actions ended up wherever the SUBTITLE
                // happened to stop. Two cards on one page with subtitles of
                // different lengths put their Add buttons at two different
                // x positions, which is what made them look scattered.
                // Expanded gives the title exactly the leftover, so the
                // actions are always against the card's right edge.
                Expanded(
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
                for (final a in actions) ...[const Gap(12), a],
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
      // Tight: four of these sit above the table, and every pixel they
      // take is a row the officer cannot see without scrolling.
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      // ⚠️ The measure's colour reaches the CARD, not just the icon beside it.
      //
      // Four white boxes with four small coloured squares is a spreadsheet;
      // the tinted wash and the top rule are what make a metric tile read as
      // a metric tile at a glance. Kept to 0.05 so the number stays the
      // loudest thing on it — the tile is a frame for the figure, not a
      // block of colour.
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withOpacity(0.05), c.cardDark),
        borderRadius: BorderRadius.circular(kIctCardRadius),
        border: Border.all(color: color.withOpacity(0.22)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
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
                      // The measure's own colour names it, so four tiles in a
                      // row are told apart by their headings as well as by
                      // their icons.
                      color: color,
                      fontSize: 10,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w800)),
              const Gap(6),
              Text(value,
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 21,
                      height: 1,
                      fontWeight: FontWeight.w800)),
              const Gap(5),
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
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.28)),
          ),
          child: Icon(icon, color: color, size: 16),
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
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(kIctCardRadius),
        border: Border.all(color: context.colors.borderColor),
      ),
      // ⚠️ Aligned on the BOTTOM. Every field carries a caption above it, so
      // aligning on the top would step the controls down the row by the
      // height of their own labels.
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const Gap(10),
          children[i],
        ],
      ]),
    );
  }
}

/// Opens the profile over a BLURRED console.
///
/// ⚠️ The blur is the point, not decoration. A dialog on a flat grey scrim
/// still sits on a page of sharp text and tables, and the eye keeps reading
/// past it; blurring what is behind takes the console out of focus so the
/// dialog is the only thing left to read. Material's default barrier is a
/// flat scrim, so the filter has to be supplied here.
Future<void> showIctProfileDialog(BuildContext context, Color accent) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Profile',
    // ⚠️ The blur alone was not enough. A light scrim over a blurred page
    // still reads as the console, slightly smudged — the dialog has to look
    // like it is IN FRONT of something, and darkness is what does that. This
    // matches the scrim every other dialog in the app drops.
    barrierColor: Colors.black.withOpacity(0.45),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, _, __) =>
        DisposalProfileDialog(accent: accent, erp: true),
    transitionBuilder: (context, animation, _, child) {
      final t = Curves.easeOut.transform(animation.value);
      return BackdropFilter(
        // Ramped with the animation: a blur that snaps to full strength on
        // the first frame reads as the window glitching.
        filter: ImageFilter.blur(sigmaX: 6 * t, sigmaY: 6 * t),
        child: Opacity(
          opacity: t,
          child: Transform.scale(scale: 0.98 + 0.02 * t, child: child),
        ),
      );
    },
  );
}

/// The small caption over a toolbar control.
///
/// ⚠️ Every field in the strip has one — including the search box, which is
/// why it exists as its own widget. Without it the search box was a lone
/// 34px box beside three cells that were a caption AND a box, so although
/// every control measured the same it read as the small one in the row. The
/// controls were never different heights; the cells were.
class IctFieldLabel extends StatelessWidget {
  const IctFieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(text.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          // ⚠️ height: 1 -- the caption is a label, not a line of prose, and
          // the font's default line spacing added several pixels of air above
          // and below it that the strip then had to carry on every page.
          style: TextStyle(
              color: context.colors.textMuted,
              fontSize: 9.5,
              height: 1,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w800)),
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
    this.label = 'Search',
  });

  final TextEditingController controller;
  final String hintText;

  /// The caption above the box, so this cell matches the filters beside it.
  final String label;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        IctFieldLabel(label),
        SizedBox(
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
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: kIctFieldPadY),
          border: border,
          enabledBorder: border,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(kIctControlRadius),
            borderSide: BorderSide(color: accent, width: 1.4),
          ),
        ),
      ),
        ),
      ],
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
        IctFieldLabel(label),
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
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: kIctFieldPadY),
              prefixIcon: Icon(icon,
                  size: 16, color: set ? accent : c.textMuted),
              // ⚠️ Constrained, exactly as IctSearchField constrains its own.
              //
              // A Material prefix icon is a 48x48 tap target by default, so
              // the decorator's INTRINSIC height was 48 against the search
              // box's 36. Both were then forced into a 34px SizedBox: the
              // search box fitted and the dropdown overflowed, painting its
              // border taller than the box it was given. Every measurement of
              // the LAYOUT agreed the two were 34 -- and they were; what
              // differed was what got painted. Measured now by the probe in
              // ict_control_heights_test, which asserts the INTRINSIC heights
              // match before anything is forced.
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 38, maxHeight: 20),
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
      height: kIctPrimaryButtonHeight,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16, color: Colors.white),
        label: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: _kIctShrink.minimumSize,
          tapTargetSize: _kIctShrink.tapTargetSize,
          padding: const EdgeInsets.symmetric(horizontal: 14),
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
      height: dense ? kIctDenseHeight : kIctControlHeight,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: dense ? 13 : 16),
        label: Text(label,
            style: TextStyle(
                fontSize: dense ? 11 : 12, fontWeight: FontWeight.w700)),
        style: OutlinedButton.styleFrom(
          foregroundColor: tint,
          backgroundColor: on ? accent.withOpacity(0.07) : Colors.transparent,
          side: BorderSide(color: tint.withOpacity(on ? 0.45 : 0.3)),
          minimumSize: _kIctShrink.minimumSize,
          tapTargetSize: _kIctShrink.tapTargetSize,
          padding: EdgeInsets.symmetric(horizontal: dense ? 9 : 14),
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
      height: kIctControlHeight,
      padding: const EdgeInsets.all(3),
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

  /// ⚠️ Handed the SEGMENT's own context. A picker opened from here is
  /// anchored under the segment that opened it, the way every dropdown in the
  /// app opens — not floated in the middle of the screen as a modal.
  final void Function(BuildContext) onTap;
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
      child: Builder(builder: (segmentContext) {
        return InkWell(
        borderRadius: BorderRadius.circular(kIctPillRadius),
        onTap: () => segment.onTap(segmentContext),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
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
                    fontSize: 12,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
          ]),
        ),
        );
      }),
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
        // ⚠️ DataTable takes its row divider from ThemeData.dividerColor, NOT
        // from DataTableThemeData -- there is no divider colour on the table
        // theme at all. Setting it here is the only way to make the rule
        // between rows lighter than the borders around the card.
        dividerColor: c.borderColor.withOpacity(0.5),
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

/// Row fill for row [i].
///
/// ⚠️ Rows are told apart by a light RULE between them (see the dividerColor
/// in [IctTableTheme]), not by banding. Banding and a rule together is one
/// pattern too many: the eye ends up reading the stripes as groups. So this
/// leaves the row transparent and only answers the pointer.
WidgetStateProperty<Color?> ictRowColor(BuildContext context, int i) {
  final c = context.colors;
  return WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.hovered)) return c.surfaceDark;
    return Colors.transparent;
  });
}

/// The one square icon action in the console.
///
/// ⚠️ Every icon-only action in ICT is this: the row's Edit, the row's
/// activate/deactivate, the header's theme toggle. They were an IconButton at
/// 34px, a tinted square at 27px and a bare 20px icon — three sizes for the
/// same kind of thing, and the 34px one is what pushed the Yards table's
/// Actions column past its edge.
class IctIconButton extends StatelessWidget {
  const IctIconButton({
    super.key,
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
    this.filled = true,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onPressed;

  /// A tinted fill, as a row action wants. Off for a button on a surface that
  /// is already tinted.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: kIctIconButtonSize,
            height: kIctIconButtonSize,
            decoration: BoxDecoration(
              color: filled ? color.withOpacity(0.1) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(filled ? 0.3 : 0.25)),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
        ),
      ),
    );
  }
}

/// The console's pager: the range on the left, numbered pages on the right.
///
/// ⚠️ Numbered, not just Prev/Next. With a single "Page 3" label the only way
/// to reach page 9 of an audit trail is to press Next six times, and there is
/// nothing on screen that says how many pages there even are. First and last
/// are always shown, the current page keeps two neighbours, and the gaps
/// collapse to an ellipsis — so the bar stays the same width at 3 pages and
/// at 3,000.
///
/// It sits INSIDE the table card, on the card's own footer rule, so the range
/// text and the numbers belong to the table rather than floating under it.
class IctPager extends StatelessWidget {
  const IctPager({
    super.key,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.accent,
    required this.onPageChanged,
  });

  final int total;

  /// Zero-based.
  final int page;
  final int pageSize;
  final Color accent;
  final ValueChanged<int> onPageChanged;

  /// The page numbers to draw, with nulls where an ellipsis goes.
  static List<int?> windowFor(int page, int pageCount) {
    if (pageCount <= 7) return [for (var i = 0; i < pageCount; i++) i];
    final out = <int?>[0];
    var from = page - 1, to = page + 1;
    if (page <= 2) {
      from = 1;
      to = 3;
    }
    if (page >= pageCount - 3) {
      from = pageCount - 4;
      to = pageCount - 2;
    }
    if (from > 1) out.add(null);
    for (var i = from; i <= to; i++) {
      if (i > 0 && i < pageCount - 1) out.add(i);
    }
    if (to < pageCount - 2) out.add(null);
    out.add(pageCount - 1);
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pageCount = total == 0 ? 0 : ((total - 1) ~/ pageSize) + 1;
    final from = total == 0 ? 0 : page * pageSize + 1;
    final to = ((page + 1) * pageSize).clamp(0, total);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(children: [
        Text(
            total == 0
                ? 'No records'
                : 'Showing $from–$to of $total',
            style: TextStyle(color: c.textSecondary, fontSize: 12)),
        const Spacer(),
        _PagerStep(
          icon: Icons.chevron_left_rounded,
          tooltip: 'Previous page',
          onPressed: page > 0 ? () => onPageChanged(page - 1) : null,
        ),
        const Gap(6),
        for (final p in windowFor(page, pageCount)) ...[
          if (p == null)
            SizedBox(
              width: 22,
              child: Text('…',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.textMuted, fontSize: 13)),
            )
          else
            _PagerNumber(
              number: p + 1,
              selected: p == page,
              accent: accent,
              onPressed: () => onPageChanged(p),
            ),
          const Gap(4),
        ],
        const Gap(2),
        _PagerStep(
          icon: Icons.chevron_right_rounded,
          tooltip: 'Next page',
          onPressed: to < total ? () => onPageChanged(page + 1) : null,
        ),
      ]),
    );
  }
}

class _PagerNumber extends StatelessWidget {
  const _PagerNumber({
    required this.number,
    required this.selected,
    required this.accent,
    required this.onPressed,
  });

  final int number;
  final bool selected;
  final Color accent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: selected ? null : onPressed,
        child: Container(
          constraints: const BoxConstraints(minWidth: 28),
          height: 28,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            color: selected ? accent : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: selected ? accent : c.borderColor),
          ),
          child: Text('$number',
              style: TextStyle(
                  color: selected ? Colors.white : c.textSecondary,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
        ),
      ),
    );
  }
}

class _PagerStep extends StatelessWidget {
  const _PagerStep({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;

  /// Null at the end of the run, which greys the arrow out.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final on = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: on ? c.borderColor : c.borderColor.withOpacity(0.4)),
            ),
            child: Icon(icon,
                size: 17, color: on ? c.textSecondary : c.textMuted),
          ),
        ),
      ),
    );
  }
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
      height: kIctPillHeight,
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
