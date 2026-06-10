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

  const StyledFormDialog({
    super.key,
    required this.label,
    required this.title,
    required this.icon,
    required this.child,
    required this.actions,
    this.width = 460,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      backgroundColor: isDark ? context.colors.cardDark : context.colors.scaffoldBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [context.colors.surfaceDark, context.colors.cardDark]
                      : [
                          context.colors.customsBlue,
                          context.colors.customsBlueDark
                        ],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: context.colors.primaryGold, size: 24),
                  ),
                  const Gap(16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label.toUpperCase(),
                          style: TextStyle(
                            color: context.colors.primaryGold,
                            fontSize: 11,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded,
                        color: Colors.white.withOpacity(0.7)),
                    splashRadius: 24,
                  ),
                ],
              ),
            ),
            // ── Body ────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: child,
              ),
            ),
            // ── Footer ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: isDark ? Colors.black26 : Colors.grey.shade100,
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

  const StyledFormSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.gap = 12,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? context.colors.surfaceDark.withOpacity(0.5)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: context.colors.primaryGold),
              const Gap(10),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  color: context.colors.primaryGold,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const Gap(16),
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

  const StyledDialogPrimaryButton({
    super.key,
    required this.labelText,
    this.icon,
    this.loading = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: context.colors.primaryGold,
        foregroundColor: context.colors.primaryNavy,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
      icon: loading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: context.colors.primaryNavy))
          : Icon(icon ?? Icons.check_rounded, size: 18),
      label: Text(labelText, style: const TextStyle(fontWeight: FontWeight.w700)),
      onPressed: loading ? null : onPressed,
    );
  }
}
