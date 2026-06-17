import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/theme.dart';
import 'package:gap/gap.dart';

/// Friendly empty-state shown wherever a table / list has no rows. Renders a
/// softly-haloed icon, a primary message, and an optional [subtitle].
///
/// Wrapped in a [FittedBox] so it scales down (instead of overflowing) when it
/// lands in a tight box such as DataTable2's `empty` slot for a zero-row table.
class EmptyTableState extends StatelessWidget {
  final String message;
  final String? subtitle;
  final IconData icon;

  const EmptyTableState({
    super.key,
    required this.message,
    this.subtitle,
    this.icon = Icons.inventory_2_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.textMuted;
    final accent = context.colors.primaryGold;

    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Haloed icon — concentric tinted rings for a soft, polished look.
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    accent.withOpacity(0.12),
                    accent.withOpacity(0.0),
                  ],
                ),
              ),
              alignment: Alignment.center,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.colors.surfaceDark,
                  border: Border.all(color: muted.withOpacity(0.18)),
                ),
                child: Icon(icon, size: 28, color: muted.withOpacity(0.55)),
              ),
            )
                .animate()
                .scale(
                    begin: const Offset(0.85, 0.85),
                    duration: 400.ms,
                    curve: Curves.easeOutBack)
                .fadeIn(),
            const Gap(16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ).animate().fadeIn(delay: 120.ms),
            if (subtitle != null) ...[
              const Gap(6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: muted,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ).animate().fadeIn(delay: 200.ms),
            ],
          ],
        ),
      ),
    );
  }
}
