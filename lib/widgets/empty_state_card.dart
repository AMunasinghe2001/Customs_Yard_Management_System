import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import '../core/theme.dart';

/// Empty-state shown on pages that DON'T render a data table (e.g. Warehouses,
/// Zone Capacity). Renders a bordered card with a plain muted icon, a primary
/// message and an optional [subtitle] — matching the Tender Sale page style.
///
/// (For tables, use [EmptyTableState] instead — it renders a haloed icon that
/// sits inside DataTable2's `empty` slot.)
class EmptyStateCard extends StatelessWidget {
  final String message;
  final String? subtitle;
  final IconData icon;

  const EmptyStateCard({
    super.key,
    required this.message,
    this.subtitle,
    this.icon = Icons.inbox_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: context.colors.textMuted, size: 48),
          const Gap(12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 16,
            ),
          ),
          if (subtitle != null) ...[
            const Gap(6),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.textMuted,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn();
  }
}
