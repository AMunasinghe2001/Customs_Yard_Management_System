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
    return Container(
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 36, color: context.colors.textMuted.withOpacity(0.3)),
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
    );
  }
}
