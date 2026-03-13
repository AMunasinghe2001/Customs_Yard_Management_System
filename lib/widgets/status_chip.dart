import 'package:flutter/material.dart';
import '../core/theme.dart';

class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case 'cleared':
        color = context.colors.successGreen;
        label = 'CLEARED';
        break;
      case 'held':
        color = context.colors.heldOrange;
        label = 'HELD';
        break;
      case 'inspecting':
        color = context.colors.warningAmber;
        label = 'INSPECTING';
        break;
      default:
        color = context.colors.textMuted;
        label = 'PENDING';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}
