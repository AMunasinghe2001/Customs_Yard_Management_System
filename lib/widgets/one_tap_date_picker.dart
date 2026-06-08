import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:gap/gap.dart';
import '../core/theme.dart';

/// Gold-themed, one-tap calendar dialog used across the app (SR registration,
/// tender placement, …). Tapping a day selects it immediately (no OK button);
/// the pencil icon switches to manual text entry. Returns the picked
/// [DateTime] via `Navigator.pop`, or `null` if cancelled.
///
/// Pass [lastDate] to disable dates after a cut-off (e.g. "no future dates").
class OneTapDatePicker extends StatefulWidget {
  final DateTime initialDate;
  final DateTime? lastDate;

  const OneTapDatePicker({super.key, required this.initialDate, this.lastDate});

  @override
  State<OneTapDatePicker> createState() => _OneTapDatePickerState();
}

class _OneTapDatePickerState extends State<OneTapDatePicker> {
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
    _visibleMonth = DateTime(widget.initialDate.year, widget.initialDate.month);
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  bool get _atLastMonth {
    final ld = widget.lastDate;
    return ld != null &&
        (_visibleMonth.year > ld.year ||
            (_visibleMonth.year == ld.year &&
                _visibleMonth.month >= ld.month));
  }

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
      setState(() => _textError = 'Use MM/DD/YYYY');
      return;
    }
    final d = DateTime(parsed.year, parsed.month, parsed.day);
    final ld = widget.lastDate;
    if (ld != null && d.isAfter(ld)) {
      setState(() => _textError = 'Date must be before today');
      return;
    }
    Navigator.pop(context, d);
  }

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(_visibleMonth.year, _visibleMonth.month);
    final leadingEmpty = firstDay.weekday % 7;
    final dayCount = DateUtils.getDaysInMonth(_visibleMonth.year, _visibleMonth.month);
    final cellCount = ((leadingEmpty + dayCount + 6) ~/ 7) * 7;

    final dateLabel = DateFormat('EEE,').format(widget.initialDate);
    final monthDayLabel = DateFormat('MMM d').format(widget.initialDate);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _textMode
              ? _buildTextMode(context)
              : _buildCalendar(context, leadingEmpty, dayCount, cellCount,
                  dateLabel, monthDayLabel),
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
              onPressed: () => setState(() { _textMode = false; _textError = null; }),
            ),
            Row(children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const Gap(8),
              ElevatedButton(onPressed: _tryApplyText, child: const Text('OK')),
            ]),
          ],
        ),
      ],
    );
  }

  Widget _buildCalendar(BuildContext context, int leadingEmpty, int dayCount,
      int cellCount, String dateLabel, String monthDayLabel) {
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
              Text('Select date',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textMuted,
                      letterSpacing: 0.5)),
              const Gap(12),
              Text(dateLabel,
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: context.colors.textPrimary,
                      height: 1.1)),
              Text(monthDayLabel,
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: context.colors.textPrimary,
                      height: 1.2)),
              const Gap(32),
              IconButton(
                icon: const Icon(Icons.edit_rounded, size: 18),
                tooltip: 'Enter date manually',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  _textCtrl.text = DateFormat('MM/dd/yyyy').format(widget.initialDate);
                  setState(() { _textMode = true; _textError = null; });
                },
              ),
            ],
          ),
        ),
        // ── Divider ───────────────────────────────────────────────────
        Container(
          width: 1,
          height: 260,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          color: context.colors.borderColor,
        ),
        // ── Calendar ──────────────────────────────────────────────────
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
                  tooltip: 'Previous month',
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: () => setState(() =>
                      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1)),
                ),
                IconButton(
                  tooltip: 'Next month',
                  icon: Icon(Icons.chevron_right_rounded,
                      color: _atLastMonth ? Colors.grey.withOpacity(0.3) : null),
                  onPressed: _atLastMonth
                      ? null
                      : () => setState(() =>
                          _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1)),
                ),
              ]),
              const Gap(4),
              // Weekday headers
              Table(
                children: [
                  TableRow(
                    children: _weekDays
                        .map((d) => Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Text(d,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700, fontSize: 11)),
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ),
              // Day grid — tap immediately selects (no OK button)
              Table(
                children: List.generate(cellCount ~/ 7, (row) {
                  return TableRow(
                    children: List.generate(7, (col) {
                      final day = row * 7 + col - leadingEmpty + 1;
                      if (day < 1 || day > dayCount) return const SizedBox(height: 36);
                      final date = DateTime(_visibleMonth.year, _visibleMonth.month, day);
                      final selected = DateUtils.isSameDay(date, widget.initialDate);
                      final isDisabled = widget.lastDate != null && date.isAfter(widget.lastDate!);
                      return Padding(
                        padding: const EdgeInsets.all(2),
                        child: GestureDetector(
                          onTap: isDisabled ? null : () => Navigator.pop(context, date),
                          child: Container(
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected && !isDisabled
                                  ? context.colors.primaryGold
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$day',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: selected && !isDisabled
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                                color: isDisabled
                                    ? Colors.grey.withOpacity(0.3)
                                    : selected && !isDisabled
                                        ? Colors.black
                                        : null,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  );
                }),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
