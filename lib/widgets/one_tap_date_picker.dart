import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:gap/gap.dart';
import '../core/theme.dart';

/// Gold-themed, one-tap calendar dialog used across the app (SR registration,
/// tender placement, …). Tapping a day selects it immediately (no OK button);
/// the pencil icon switches to manual text entry. Returns the picked
/// [DateTime] via `Navigator.pop`, or `null` if cancelled.
///
/// Pass [lastDate] to disable dates after a cut-off (e.g. "no future dates")
/// and/or [firstDate] to disable dates before a cut-off (e.g. "not before the
/// entry date").
class OneTapDatePicker extends StatefulWidget {
  final DateTime initialDate;
  final DateTime? lastDate;
  final DateTime? firstDate;

  const OneTapDatePicker(
      {super.key,
      required this.initialDate,
      this.lastDate,
      this.firstDate});

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
    final fd = widget.firstDate;
    if (fd != null && d.isBefore(DateTime(fd.year, fd.month, fd.day))) {
      setState(() => _textError =
          'Date must be on or after ${DateFormat('yyyy-MM-dd').format(fd)}');
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
                      final isDisabled =
                          (widget.lastDate != null && date.isAfter(widget.lastDate!)) ||
                          (widget.firstDate != null && date.isBefore(widget.firstDate!));
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

/// Gold-themed, low-tap time picker matching [OneTapDatePicker]. Tapping an
/// hour jumps straight to the minute grid; tapping a minute selects and closes
/// immediately (no OK button). The pencil icon switches to manual HH:mm entry.
/// Returns the picked [TimeOfDay] via `Navigator.pop`, or `null` if cancelled.
class OneTapTimePicker extends StatefulWidget {
  final TimeOfDay initialTime;
  const OneTapTimePicker({super.key, required this.initialTime});

  @override
  State<OneTapTimePicker> createState() => _OneTapTimePickerState();
}

class _OneTapTimePickerState extends State<OneTapTimePicker> {
  late int _hour; // 0–23
  late int _minute; // 0–59
  bool _pickingMinute = false;
  bool _textMode = false;
  final _textCtrl = TextEditingController();
  String? _textError;

  @override
  void initState() {
    super.initState();
    _hour = widget.initialTime.hour;
    _minute = widget.initialTime.minute;
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  bool get _isPm => _hour >= 12;
  int get _hour12 {
    final h = _hour % 12;
    return h == 0 ? 12 : h;
  }

  void _finish() => Navigator.pop(context, TimeOfDay(hour: _hour, minute: _minute));

  void _tryApplyText() {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(_textCtrl.text.trim());
    if (m == null) {
      setState(() => _textError = 'Use HH:mm (24h)');
      return;
    }
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    if (h > 23 || min > 59) {
      setState(() => _textError = 'Invalid time');
      return;
    }
    Navigator.pop(context, TimeOfDay(hour: h, minute: min));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _textMode ? _buildTextMode(context) : _buildPicker(context),
        ),
      ),
    );
  }

  Widget _buildTextMode(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Enter Time', style: Theme.of(context).textTheme.titleMedium),
        const Gap(16),
        TextField(
          controller: _textCtrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'HH:mm (24h)',
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
              icon: const Icon(Icons.schedule_rounded),
              tooltip: 'Switch to clock',
              onPressed: () => setState(() { _textMode = false; _textError = null; }),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPicker(BuildContext context) {
    final hourStr = _hour12.toString().padLeft(2, '0');
    final minStr = _minute.toString().padLeft(2, '0');

    Widget ampmSeg(String label, bool pm) {
      final active = _isPm == pm;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() {
            if (pm && _hour < 12) _hour += 12;
            if (!pm && _hour >= 12) _hour -= 12;
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? context.colors.primaryGold : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: active
                        ? Colors.black
                        : context.colors.textSecondary)),
          ),
        ),
      );
    }

    Widget tab(String label, bool minuteTab) {
      final active = _pickingMinute == minuteTab;
      return InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _pickingMinute = minuteTab),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? context.colors.primaryGold.withOpacity(0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: active
                      ? context.colors.primaryGold
                      : context.colors.textPrimary)),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Select time',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textMuted,
                    letterSpacing: 0.5)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.keyboard_rounded, size: 18),
              tooltip: 'Enter time manually',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                _textCtrl.text =
                    '${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}';
                setState(() { _textMode = true; _textError = null; });
              },
            ),
          ],
        ),
        const Gap(8),
        // Big HH : mm display — tap either to edit that part.
        Row(children: [
          tab(hourStr, false),
          Text(' : ',
              style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: context.colors.textMuted)),
          tab(minStr, true),
          const Gap(12),
          SizedBox(
            width: 96,
            child: Row(children: [
              ampmSeg('AM', false),
              ampmSeg('PM', true),
            ]),
          ),
        ]),
        const Gap(20),
        // Analog dial — drag or tap. Hours first; selecting an hour swings the
        // dial to minutes; selecting a minute closes immediately (no OK).
        Center(
          child: _ClockDial(
            pickingMinute: _pickingMinute,
            hour12: _hour12,
            minute: _minute,
            onHour: (h12) => setState(() {
              _hour = _isPm
                  ? (h12 == 12 ? 12 : h12 + 12)
                  : (h12 == 12 ? 0 : h12);
            }),
            onHourCommitted: () => setState(() => _pickingMinute = true),
            onMinute: (m) => setState(() => _minute = m),
            onMinuteCommitted: _finish,
          ),
        ),
        const Gap(8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ),
      ],
    );
  }
}

/// A Material-style analog clock dial used by [OneTapTimePicker]. Shows 12
/// hour numbers (1–12) or 12 minute marks (00,05,…,55) around a circle with a
/// gold hand pointing at the selection. Tap or drag a number to pick it; the
/// picker handles the hour→minute swing and the close-on-minute behaviour.
class _ClockDial extends StatelessWidget {
  final bool pickingMinute;
  final int hour12; // 1–12
  final int minute; // 0–59
  final ValueChanged<int> onHour; // 1–12 while dragging
  final VoidCallback onHourCommitted; // pointer released on an hour
  final ValueChanged<int> onMinute; // 0–59 while dragging
  final VoidCallback onMinuteCommitted; // pointer released on a minute

  const _ClockDial({
    required this.pickingMinute,
    required this.hour12,
    required this.minute,
    required this.onHour,
    required this.onHourCommitted,
    required this.onMinute,
    required this.onMinuteCommitted,
  });

  static const double _size = 256;
  static const double _radius = 100; // number ring radius from centre

  // Resolve a local touch point to the nearest of 12 tick positions (12 at top,
  // clockwise). Returns 1..12 for hours, or the *index* 0..11 for minutes.
  int _valueFromOffset(Offset local) {
    final center = const Offset(_size / 2, _size / 2);
    final v = local - center;
    // Angle measured clockwise from 12 o'clock.
    var angle = math.atan2(v.dx, -v.dy); // 0 at top, +clockwise
    if (angle < 0) angle += 2 * math.pi;
    final step = (angle / (2 * math.pi) * 12).round() % 12; // 0..11, 0 = top
    return step;
  }

  void _handle(Offset local, {required bool commit}) {
    final step = _valueFromOffset(local);
    if (pickingMinute) {
      onMinute(step * 5);
      if (commit) onMinuteCommitted();
    } else {
      final h12 = step == 0 ? 12 : step;
      onHour(h12);
      if (commit) onHourCommitted();
    }
  }

  @override
  Widget build(BuildContext context) {
    final gold = context.colors.primaryGold;
    // Which tick is currently selected (0..11, 0 = top/12).
    final selectedStep =
        pickingMinute ? (minute ~/ 5) % 12 : (hour12 % 12);
    final handAngle = selectedStep / 12 * 2 * math.pi; // clockwise from top

    final numbers = <Widget>[];
    for (var i = 0; i < 12; i++) {
      // i = 0 sits at the top (12 / 00) and increases clockwise.
      final angle = i / 12 * 2 * math.pi;
      final dx = _size / 2 + _radius * math.sin(angle);
      final dy = _size / 2 - _radius * math.cos(angle);
      final label = pickingMinute
          ? (i * 5).toString().padLeft(2, '0')
          : (i == 0 ? 12 : i).toString();
      final isSel = i == selectedStep;
      numbers.add(Positioned(
        left: dx - 18,
        top: dy - 18,
        width: 36,
        height: 36,
        child: Center(
          child: Text(label,
              style: TextStyle(
                fontSize: pickingMinute ? 13 : 15,
                fontWeight: isSel ? FontWeight.w900 : FontWeight.w600,
                color: isSel ? Colors.black : context.colors.textPrimary,
              )),
        ),
      ));
    }

    return GestureDetector(
      onTapDown: (d) => _handle(d.localPosition, commit: false),
      onTapUp: (d) => _handle(d.localPosition, commit: true),
      onPanStart: (d) => _handle(d.localPosition, commit: false),
      onPanUpdate: (d) => _handle(d.localPosition, commit: false),
      onPanEnd: (_) => pickingMinute ? onMinuteCommitted() : onHourCommitted(),
      child: SizedBox(
        width: _size,
        height: _size,
        child: Stack(
          children: [
            // Dial face
            Container(
              width: _size,
              height: _size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.colors.textPrimary.withOpacity(0.04),
                border: Border.all(color: context.colors.borderColor),
              ),
            ),
            // Hand + selection knob
            CustomPaint(
              size: const Size(_size, _size),
              painter: _HandPainter(
                angle: handAngle,
                radius: _radius,
                color: gold,
              ),
            ),
            // Centre pin
            Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: gold),
              ),
            ),
            ...numbers,
          ],
        ),
      ),
    );
  }
}

class _HandPainter extends CustomPainter {
  final double angle; // clockwise from top
  final double radius;
  final Color color;
  _HandPainter(
      {required this.angle, required this.radius, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final end = Offset(
      center.dx + radius * math.sin(angle),
      center.dy - radius * math.cos(angle),
    );
    final line = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, end, line);
    // Selection knob behind the number.
    canvas.drawCircle(end, 18, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_HandPainter old) =>
      old.angle != angle || old.radius != radius || old.color != color;
}
