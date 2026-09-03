import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import '../core/theme.dart';

/// A polished modal dialog matching the "Update SR Register Entry" form:
/// a gradient header (gold icon box + small label + big title + close button),
/// a scrollable body, and a footer action bar.
///
/// Wrap the body fields in [StyledFormSection]s to get the gold-headed cards.
class StyledFormDialog extends StatelessWidget {
  final String label; // small uppercase gold label, e.g. "CREATE OFFICER"
  final String title; // large white title, e.g. "New Officer Account"
  final IconData icon;
  final double width;
  final Widget child; // body content (usually a Column of StyledFormSections)
  final List<Widget> actions; // footer buttons (right-aligned)
  final Color? headerAccentColor;

  /// The ICT console's flatter shape: a plain header on the card colour with
  /// a rule under it, a 12px radius, and the title in the page's own text
  /// colour rather than white.
  ///
  /// ⚠️ OPT-IN, and it must stay opt-in. This dialog is the form chrome for
  /// every portal in the app, and only ICT was redesigned — the default is
  /// still the gradient-headed dialog the yard and the directorates use, and
  /// a test asserts no other screen passes this flag.
  ///
  /// The difference is not decoration. The gradient header reads as a moment:
  /// something has been opened, and the colour says so. An admin console's
  /// forms are opened dozens of times a day to do routine work, so they are
  /// drawn as a panel of the console rather than as an event.
  final bool erp;

  const StyledFormDialog({
    super.key,
    required this.label,
    required this.title,
    required this.icon,
    required this.child,
    required this.actions,
    this.width = 460,
    this.headerAccentColor,
    this.erp = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = headerAccentColor ?? context.colors.primaryGold;
    
    return Dialog(
      backgroundColor: isDark ? context.colors.cardDark : context.colors.scaffoldBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(erp ? 12 : 24),
        side: erp
            ? BorderSide(color: context.colors.borderColor)
            : BorderSide.none,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────
            Container(
              padding: erp
                  ? const EdgeInsets.fromLTRB(20, 16, 12, 16)
                  : const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: erp
                  ? BoxDecoration(
                      color: context.colors.cardDark,
                      border: Border(
                          bottom:
                              BorderSide(color: context.colors.borderColor)),
                    )
                  : BoxDecoration(
                      gradient: headerAccentColor != null
                          ? LinearGradient(colors: [
                              headerAccentColor!.withOpacity(0.15),
                              context.colors.cardDark,
                            ])
                          : LinearGradient(
                              colors: isDark
                                  ? [
                                      context.colors.surfaceDark,
                                      context.colors.cardDark
                                    ]
                                  : [
                                      context.colors.customsBlue,
                                      context.colors.customsBlueDark
                                    ],
                            ),
                    ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(erp ? 8 : 10),
                    decoration: BoxDecoration(
                      color: erp
                          ? accent.withOpacity(0.12)
                          : Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(erp ? 8 : 12),
                      border: erp
                          ? Border.all(color: accent.withOpacity(0.3))
                          : null,
                    ),
                    child: Icon(icon, color: accent, size: erp ? 18 : 24),
                  ),
                  Gap(erp ? 12 : 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label.toUpperCase(),
                          style: TextStyle(
                            color: erp ? context.colors.textMuted : accent,
                            fontSize: erp ? 9.5 : 11,
                            letterSpacing: erp ? 0.9 : 1.2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (erp) const Gap(2),
                        Text(
                          title,
                          style: TextStyle(
                            // ⚠️ Not white in ERP mode. Without the gradient
                            // behind it, white title on a light card is
                            // unreadable — the flat header has to take its
                            // colour from the page, not from the old one.
                            color: erp
                                ? context.colors.textPrimary
                                : Colors.white,
                            fontSize: erp ? 17 : 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded,
                        size: erp ? 20 : 24,
                        color: erp
                            ? context.colors.textMuted
                            : Colors.white.withOpacity(0.7)),
                    splashRadius: erp ? 18 : 24,
                  ),
                ],
              ),
            ),
            // ── Body ────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(erp ? 20 : 24),
                child: child,
              ),
            ),
            // ── Footer ──────────────────────────────────────────────
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: erp ? 20 : 24, vertical: erp ? 12 : 16),
              decoration: BoxDecoration(
                color: erp
                    ? context.colors.surfaceDark
                    : (isDark ? Colors.black26 : Colors.grey.shade100),
                border: Border(
                    top: BorderSide(color: context.colors.borderColor)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (int i = 0; i < actions.length; i++) ...[
                    if (i > 0) const Gap(12),
                    actions[i],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A gold-headed card used to group fields inside a [StyledFormDialog].
class StyledFormSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final double gap;

  /// The heading colour. Defaults to the app's gold; ICT passes its own so a
  /// form inside the console does not carry a second portal's colour.
  final Color? accentColor;

  /// The console's flatter section: a 12px radius to match [StyledFormDialog]
  /// in the same mode. Opt-in for the same reason the dialog's flag is.
  final bool erp;

  const StyledFormSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.gap = 12,
    this.accentColor,
    this.erp = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = accentColor ?? context.colors.primaryGold;
    return Container(
      padding: EdgeInsets.all(erp ? 14 : 16),
      decoration: BoxDecoration(
        color: isDark
            ? context.colors.surfaceDark.withOpacity(0.5)
            : Colors.white,
        borderRadius: BorderRadius.circular(erp ? 10 : 16),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: erp ? 16 : 18, color: accent),
              const Gap(10),
              Flexible(
                child: Text(
                  title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent,
                    fontSize: erp ? 10.5 : 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: erp ? 0.9 : 0.8,
                  ),
                ),
              ),
            ],
          ),
          Gap(erp ? 12 : 16),
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1) Gap(gap),
          ],
        ],
      ),
    );
  }
}

/// A pre-styled primary (gold) action button for [StyledFormDialog] footers.
class StyledDialogPrimaryButton extends StatelessWidget {
  final String labelText;
  final IconData? icon;
  final bool loading;
  final VoidCallback? onPressed;

  /// The button's fill. Defaults to the app's gold; ICT passes its own so a
  /// form inside the console does not end its footer in another portal's
  /// colour. White text is used with a custom accent — the navy-on-gold pair
  /// only reads on gold.
  final Color? accentColor;

  /// Matches [StyledFormDialog.erp]: the console's control height and radius.
  final bool erp;

  const StyledDialogPrimaryButton({
    super.key,
    required this.labelText,
    this.icon,
    this.loading = false,
    required this.onPressed,
    this.accentColor,
    this.erp = false,
  });

  @override
  Widget build(BuildContext context) {
    final fill = accentColor ?? context.colors.primaryGold;
    final on = accentColor == null ? context.colors.primaryNavy : Colors.white;
    final button = ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: fill,
        foregroundColor: on,
        elevation: erp ? 0 : null,
        padding: EdgeInsets.symmetric(
            horizontal: erp ? 16 : 20, vertical: erp ? 0 : 14),
        shape: erp
            ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
            : null,
      ),
      icon: loading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: on))
          : Icon(icon ?? Icons.check_rounded, size: erp ? 16 : 18),
      label: Text(labelText,
          style: TextStyle(
              fontSize: erp ? 12 : null, fontWeight: FontWeight.w700)),
      onPressed: loading ? null : onPressed,
    );
    // 36 is kIctControlHeight -- named there, not here, because this widget
    // is shared and must not import the console's kit.
    return erp ? SizedBox(height: 36, child: button) : button;
  }
}
