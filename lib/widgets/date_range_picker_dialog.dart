import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';

// ── Public date-range dialog ──────────────────────────────────────────────────

class DateRangePickerDialog extends StatefulWidget {
  final DateTimeRange? initialRange;
  const DateRangePickerDialog({super.key, this.initialRange});

  @override
  State<DateRangePickerDialog> createState() => _DateRangePickerDialogState();
}

class _DateRangePickerDialogState extends State<DateRangePickerDialog> {
  DateTime? _start;
  DateTime? _end;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTime _clamp(DateTime d, DateTime min, DateTime max) {
    if (d.isBefore(min)) return min;
    if (d.isAfter(max)) return max;
    return d;
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialRange != null) {
      _start = widget.initialRange!.start;
      _end = widget.initialRange!.end;
    }
  }

  Future<void> _pickFrom() async {
    final today = _today();
    final initial = _clamp(_start ?? today, DateTime(2020), today);
    final picked = await _showOneTapCalendar(
      context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: today,
      label: 'From Date',
    );
    if (!mounted || picked == null) return;
    setState(() {
      _start = picked;
      if (_end != null && _end!.isBefore(picked)) _end = null;
    });
    await _pickTo();
  }

  Future<void> _pickTo() async {
    final today = _today();
    final minDate = _start ?? DateTime(2020);
    final initial = _clamp(_end ?? today, minDate, today);
    final picked = await _showOneTapCalendar(
      context,
      initialDate: initial,
      firstDate: minDate,
      lastDate: today,
      label: 'To Date',
    );
    if (!mounted || picked == null) return;
    setState(() => _end = picked);
    if (_start != null && mounted) {
      Navigator.pop(context, DateTimeRange(start: _start!, end: _end!));
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
              Text('Select Date Range',
                  style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close_rounded,
                    color: context.colors.textMuted, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const Gap(4),
          Text('Select From date — To date opens automatically',
              style: TextStyle(
                  color: context.colors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.normal)),
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
              onTap: _pickFrom,
              icon: Icons.calendar_today_rounded,
            ),
            const Gap(12),
            _DateTile(
              label: 'To',
              date: _end,
              onTap: _pickTo,
              icon: Icons.event_available_rounded,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Clear Filter',
              style: TextStyle(color: context.colors.dangerRed)),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: (_start != null && _end != null)
              ? () => Navigator.pop(
                  context, DateTimeRange(start: _start!, end: _end!))
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: context.colors.primaryGold,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Apply Filter',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

// ── One-tap calendar dialog ───────────────────────────────────────────────────

Future<DateTime?> _showOneTapCalendar(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String label = 'Select date',
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (_) => _OneTapCalendarDialog(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      label: label,
    ),
  );
}

class _OneTapCalendarDialog extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final String label;

  const _OneTapCalendarDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    this.label = 'Select date',
  });

  @override
  State<_OneTapCalendarDialog> createState() => _OneTapCalendarDialogState();
}

class _OneTapCalendarDialogState extends State<_OneTapCalendarDialog> {
  late DateTime _visibleMonth;
  bool _textMode = false;
  final _textCtrl = TextEditingController();
  String? _textError;

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _weekDays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  @override
  void initState() {
    super.initState();
    _visibleMonth =
        DateTime(widget.initialDate.year, widget.initialDate.month);
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  bool get _atFirstMonth =>
      _visibleMonth.year < widget.firstDate.year ||
      (_visibleMonth.year == widget.firstDate.year &&
          _visibleMonth.month <= widget.firstDate.month);

  bool get _atLastMonth =>
      _visibleMonth.year > widget.lastDate.year ||
      (_visibleMonth.year == widget.lastDate.year &&
          _visibleMonth.month >= widget.lastDate.month);

  void _tryApplyText() {
    final text = _textCtrl.text.trim();
    DateTime? parsed;
    for (final fmt in ['MM/dd/yyyy', 'yyyy-MM-dd', 'dd/MM/yyyy']) {
      try {
        parsed = DateFormat(fmt).parseStrict(text);
        break;
      } catch (_) {}
    }
    if (parsed == null) {
      setState(() => _textError = 'Use MM/DD/YYYY format');
      return;
    }
    final d = DateTime(parsed.year, parsed.month, parsed.day);
    if (d.isBefore(widget.firstDate) || d.isAfter(widget.lastDate)) {
      setState(() => _textError = 'Date out of range');
      return;
    }
    Navigator.pop(context, d);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _textMode ? _buildTextMode(context) : _buildCalendar(context),
        ),
      ),
    );
  }

  Widget _buildTextMode(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Enter Date', style: Theme.of(context).textTheme.titleMedium),
        const Gap(16),
        TextField(
          controller: _textCtrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'MM/DD/YYYY',
            errorText: _textError,
            isDense: true,
          ),
          onSubmitted: (_) => _tryApplyText(),
        ),
        const Gap(20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.calendar_month_rounded),
              tooltip: 'Switch to calendar',
              onPressed: () => setState(() {
                _textMode = false;
                _textError = null;
              }),
            ),
            Row(children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const Gap(8),
              ElevatedButton(
                onPressed: _tryApplyText,
                child: const Text('OK'),
              ),
            ]),
          ],
        ),
      ],
    );
  }

  Widget _buildCalendar(BuildContext context) {
    final firstDay = DateTime(_visibleMonth.year, _visibleMonth.month);
    final leadingEmpty = firstDay.weekday % 7;
    final dayCount =
        DateUtils.getDaysInMonth(_visibleMonth.year, _visibleMonth.month);
    final cellCount = ((leadingEmpty + dayCount + 6) ~/ 7) * 7;

    // Left panel date strings
    final dateLabel = DateFormat('EEE,').format(widget.initialDate);
    final monthDayLabel = DateFormat('MMM d').format(widget.initialDate);

    // Determine accent color based on label
    final isFrom = widget.label.toLowerCase().contains('from');
    final isTo = widget.label.toLowerCase().contains('to');
    final labelColor = isFrom
        ? const Color(0xFF42A5F5) // blue for From
        : isTo
            ? const Color(0xFF66BB6A) // green for To
            : context.colors.primaryGold;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Left panel ────────────────────────────────────────────────
        SizedBox(
          width: 120,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Label badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: labelColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  widget.label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: labelColor,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const Gap(12),
              Text(
                dateLabel,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: context.colors.textPrimary,
                  height: 1.1,
                ),
              ),
              Text(
                monthDayLabel,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: context.colors.textPrimary,
                  height: 1.2,
                ),
              ),
              const Gap(32),
              // Pencil icon — fixed position below date text
              IconButton(
                icon: const Icon(Icons.edit_rounded, size: 18),
                tooltip: 'Enter date manually',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  _textCtrl.text =
                      DateFormat('MM/dd/yyyy').format(widget.initialDate);
                  setState(() {
                    _textMode = true;
                    _textError = null;
                  });
                },
              ),
            ],
          ),
        ),
        // ── Vertical divider ─────────────────────────────────────────
        Container(
          width: 1,
          height: 260,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          color: context.colors.borderColor,
        ),
        // ── Calendar grid ─────────────────────────────────────────────
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Month header + nav
              Row(children: [
                Expanded(
                  child: Text(
                    '${_monthNames[_visibleMonth.month - 1]} ${_visibleMonth.year}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.chevron_left_rounded,
                      color: _atFirstMonth
                          ? Colors.grey.withOpacity(0.3)
                          : null),
                  onPressed: _atFirstMonth
                      ? null
                      : () => setState(() => _visibleMonth =
                          DateTime(_visibleMonth.year, _visibleMonth.month - 1)),
                  tooltip: 'Previous month',
                ),
                IconButton(
                  icon: Icon(Icons.chevron_right_rounded,
                      color: _atLastMonth
                          ? Colors.grey.withOpacity(0.3)
                          : null),
                  onPressed: _atLastMonth
                      ? null
                      : () => setState(() => _visibleMonth =
                          DateTime(_visibleMonth.year, _visibleMonth.month + 1)),
                  tooltip: 'Next month',
                ),
              ]),
              const Gap(4),
              // Weekday header row (Table — no size issues)
              Table(
                children: [
                  TableRow(
                    children: _weekDays
                        .map((d) => Center(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Text(d,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11)),
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ),
              // Day cells (Table — avoids GridView's unbounded-height issue)
              Table(
                children: List.generate(
                  cellCount ~/ 7,
                  (row) => TableRow(
                    children: List.generate(7, (col) {
                      final idx = row * 7 + col;
                      final day = idx - leadingEmpty + 1;
                      if (day < 1 || day > dayCount) {
                        return const SizedBox(height: 36);
                      }
                      final date = DateTime(
                          _visibleMonth.year, _visibleMonth.month, day);
                      final isSelected =
                          DateUtils.isSameDay(date, widget.initialDate);
                      final isDisabled = date.isBefore(widget.firstDate) ||
                          date.isAfter(widget.lastDate);

                      return Padding(
                        padding: const EdgeInsets.all(2),
                        child: GestureDetector(
                          onTap: isDisabled
                              ? null
                              : () => Navigator.pop(context, date),
                          child: Container(
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected && !isDisabled
                                  ? labelColor
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$day',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected && !isDisabled
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                                color: isDisabled
                                    ? Colors.grey.withOpacity(0.3)
                                    : isSelected && !isDisabled
                                        ? Colors.white
                                        : null,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Date tile (From / To row) ─────────────────────────────────────────────────

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
          border: Border.all(
              color: date != null
                  ? context.colors.primaryGold.withOpacity(0.5)
                  : context.colors.borderColor),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: date != null
                    ? context.colors.primaryGold.withOpacity(0.1)
                    : context.colors.surfaceDark,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon,
                  color: date != null
                      ? context.colors.primaryGold
                      : context.colors.textMuted,
                  size: 20),
            ),
            const Gap(16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: context.colors.textMuted, fontSize: 12)),
                Text(
                  date != null
                      ? DateFormat('MMMM d, yyyy').format(date!)
                      : 'Select Date',
                  style: TextStyle(
                    color: date != null
                        ? context.colors.textPrimary
                        : context.colors.textMuted,
                    fontSize: 15,
                    fontWeight:
                        date != null ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Icon(Icons.chevron_right_rounded,
                color: context.colors.textMuted),
          ],
        ),
      ),
    );
  }
}
