import 'package:flutter/material.dart';
import '../core/theme.dart';
import 'package:gap/gap.dart';

class EmptyTableState extends StatelessWidget {
  final String message;
  final IconData icon;

  const EmptyTableState({
    super.key,
    required this.message,
    this.icon = Icons.inventory_2_outlined,
  });

  @override
  Widget build(BuildContext context) {
    // FittedBox lets the icon+text scale down when this lands in a tight box
    // (e.g. DataTable2's `empty` slot for a zero-row table), so it never throws
    // a vertical-overflow exception while still centring at full size elsewhere.
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 36, color: context.colors.textMuted.withOpacity(0.3)),
            const Gap(8),
            Text(
              message,
              style: TextStyle(
                color: context.colors.textMuted,
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
