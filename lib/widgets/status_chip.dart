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
      case 'returned':
        color = context.colors.successGreen;
        label = 'RELEASED';
        break;
      case 'held':
      case 'detained':
        color = context.colors.heldOrange;
        label = 'HELD';
        break;
      case 'Detain':
        color = context.colors.heldOrange;
        label = 'DETAIN';
        break;
      case 'Forfeit':
      case 'forfeited':
        color = context.colors.dangerRed;
        label = 'FORFEIT';
        break;
      case 'Abandoned':
        color = const Color(0xFF9E9E9E);
        label = 'ABANDONED';
        break;
      case 'inspecting':
        color = context.colors.warningAmber;
        label = 'INSPECTING';
        break;
      case 'confiscated':
        color = context.colors.dangerRed;
        label = 'CONFISCATED';
        break;
      default:
        color = context.colors.textMuted;
        label = status.isNotEmpty ? status.toUpperCase() : 'PENDING';
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
        maxLines: 1,
        softWrap: false,
      ),
    );
  }
}
