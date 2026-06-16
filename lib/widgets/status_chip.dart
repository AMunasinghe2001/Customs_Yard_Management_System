import 'package:flutter/material.dart';
import '../core/theme.dart';

class StatusChip extends StatelessWidget {
  final String status;
  /// When set, every chip renders at this exact width (label centred, ellipsis
  /// if too long) so a column of chips lines up uniformly. Null = size to text.
  final double? fixedWidth;
  const StatusChip({super.key, required this.status, this.fixedWidth});

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
      case 'Forfiet': // typo variant in older data
      case 'forfeit':
      case 'forfiet':
      case 'forfeited':
        color = context.colors.dangerRed;
        label = 'FORFEIT';
        break;
      case 'Abandoned':
      case 'abandoned':
        color = const Color(0xFF9E9E9E);
        label = 'ABANDONED';
        break;
      case 'Re-export':
      case 're-export':
        color = const Color(0xFF00ACC1); // teal
        label = 'RE-EXPORT';
        break;
      case 'Destroy':
      case 'destroy':
        color = const Color(0xFFE64A19); // deep orange
        label = 'DESTROY';
        break;
      case 'inspecting':
        color = context.colors.warningAmber;
        label = 'INSPECTING';
        break;
      case 'confiscated':
        color = context.colors.dangerRed;
        label = 'FORFEITED';
        break;
      default:
        // "Other: <custom text>" disposition marker → show the custom label.
        if (status.toLowerCase().startsWith('other:')) {
          color = context.colors.warningAmber;
          final custom = status.substring(6).trim();
          label = custom.isEmpty ? 'OTHER' : custom.toUpperCase();
          break;
        }
        if (status.toLowerCase() == 'other') {
          color = context.colors.warningAmber;
          label = 'OTHER';
          break;
        }
        color = context.colors.textMuted;
        label = status.isNotEmpty ? status.toUpperCase() : 'PENDING';
    }
    return Container(
      width: fixedWidth,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      alignment: fixedWidth != null ? Alignment.center : null,
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        textAlign: fixedWidth != null ? TextAlign.center : TextAlign.start,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
