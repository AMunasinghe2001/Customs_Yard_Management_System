import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';

class DateRangePickerDialog extends StatefulWidget {
  final DateTimeRange? initialRange;
  const DateRangePickerDialog({super.key, this.initialRange});

  @override
  State<DateRangePickerDialog> createState() => _DateRangePickerDialogState();
}

class _DateRangePickerDialogState extends State<DateRangePickerDialog> {
  DateTime? _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    if (widget.initialRange != null) {
      _start = widget.initialRange!.start;
      _end = widget.initialRange!.end;
    }
  }

  Future<void> _selectDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _start : _end) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.dark(
            primary: context.colors.primaryGold,
            onPrimary: Colors.black,
            surface: context.colors.surfaceDark,
            onSurface: context.colors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _start = picked;
          if (_end != null && _start!.isAfter(_end!)) _end = null;
        } else {
          _end = picked;
          if (_start != null && _end!.isBefore(_start!)) _start = null;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: context.colors.surfaceDark,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Select Date Range', style: TextStyle(color: context.colors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close_rounded, color: context.colors.textMuted, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const Gap(4),
          Text('Filter records by a specific time period', style: TextStyle(color: context.colors.textMuted, fontSize: 12, fontWeight: FontWeight.normal)),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DateTile(
              label: 'From',
              date: _start,
              onTap: () => _selectDate(true),
              icon: Icons.calendar_today_rounded,
            ),
            const Gap(12),
            _DateTile(
              label: 'To',
              date: _end,
              onTap: () => _selectDate(false),
              icon: Icons.event_available_rounded,
            ),
            if (_start != null && _end != null && _start!.isAfter(_end!))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Start date must be before end date', style: TextStyle(color: context.colors.dangerRed, fontSize: 11)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Clear Filter', style: TextStyle(color: context.colors.dangerRed)),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: (_start != null && _end != null)
              ? () => Navigator.pop(context, DateTimeRange(start: _start!, end: _end!))
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: context.colors.primaryGold,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Apply Filter', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

class _DateTile extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  final IconData icon;

  const _DateTile({
    required this.label,
    required this.date,
    required this.onTap,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.colors.cardDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: date != null ? context.colors.primaryGold.withOpacity(0.5) : context.colors.borderColor),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: date != null ? context.colors.primaryGold.withOpacity(0.1) : context.colors.surfaceDark,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: date != null ? context.colors.primaryGold : context.colors.textMuted, size: 20),
            ),
            const Gap(16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: context.colors.textMuted, fontSize: 12)),
                Text(
                  date != null ? DateFormat('MMMM d, yyyy').format(date!) : 'Select Date',
                  style: TextStyle(
                    color: date != null ? context.colors.textPrimary : context.colors.textMuted,
                    fontSize: 15,
                    fontWeight: date != null ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Icon(Icons.chevron_right_rounded, color: context.colors.textMuted),
          ],
        ),
      ),
    );
  }
}
