import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:gap/gap.dart';

import 'dialog_close_button.dart';

import '../core/theme.dart';
import 'date_range_picker_dialog.dart' as custom;
import 'styled_dropdown.dart';
import '../widgets/app_dialog.dart';

/// One control for every "when" question a list can be asked — the same
/// shape the Report Generator uses: a mode dropdown that opens the matching
/// picker.
///
/// ⚠️ It replaces a PAIR of buttons — "Date Range" and "All Years" — that sat
/// side by side on thirteen pages. Two buttons for one decision meant the
/// reader had to know which of them held the filter actually applied, and on
/// a narrow window the pair wrapped onto its own line.
///
/// ⚠️ The two filters it merges are NOT the same field, and this deliberately
/// keeps them apart:
///
///   * **By Year** matches the trailing `/YYYY` of the SR NUMBER
///     (`sr_number ilike '%/2026'`). An SR is numbered in the year it is
///     registered, and that is how the register is filed and searched.
///   * **Single Day / By Month / Custom Range** match the ENTRY DATE.
///
/// Those can disagree — an SR numbered `/2025` can be admitted in January
/// 2026 — so mapping "By Year" onto a 1 Jan–31 Dec range, as the Report
/// Generator does, would silently change which rows come back on these
/// pages. Selecting one clears the other: one question at a time, and the
/// button's label always says which is live.
class DateFilterButton extends StatelessWidget {
  const DateFilterButton({
    super.key,
    required this.dateRange,
    required this.year,
    required this.years,
    required this.onChanged,
  });

  /// The entry-date filter currently applied, if any.
  final DateTimeRange? dateRange;

  /// The SR-number year currently applied, if any.
  final String? year;

  /// The years the register actually holds — build with `srYears()`, which
  /// also offers this year and the next so the list never goes stale.
  final List<String> years;

  /// Emits the new state. At most one of the two is ever non-null.
  final void Function(DateTimeRange? range, String? year) onChanged;

  bool get _active => dateRange != null || year != null;

  /// Which mode the live filter came from, so the button keeps its identity
  /// after the picker closes.
  String get _mode {
    if (year != null) return 'year';
    final r = dateRange;
    if (r == null) return 'range';
    if (r.start == r.end) return 'day';
    final lastOfMonth = DateTime(r.start.year, r.start.month + 1, 0);
    if (r.start.day == 1 &&
        r.end.year == lastOfMonth.year &&
        r.end.month == lastOfMonth.month &&
        r.end.day == lastOfMonth.day) {
      return 'month';
    }
    return 'range';
  }

  static const _modeLabels = {
    'range': 'Custom Date Range',
    'day': 'Single Day',
    'month': 'By Month',
    'year': 'By Year',
  };

  static const _modeIcons = {
    'range': Icons.date_range_rounded,
    'day': Icons.today_rounded,
    'month': Icons.calendar_view_month_rounded,
    'year': Icons.calendar_view_week_rounded,
  };

  /// The live selection, or the mode name when nothing is picked yet.
  String get _label {
    if (year != null) return 'Year: $year';
    final r = dateRange;
    if (r == null) return 'Date Filter';
    final f = DateFormat('yyyy-MM-dd');
    switch (_mode) {
      case 'day':
        return 'Day: ${f.format(r.start)}';
      case 'month':
        return 'Month: ${DateFormat('MMM yyyy').format(r.start)}';
      default:
        return '${f.format(r.start)} → ${f.format(r.end)}';
    }
  }

  Future<void> _pick(BuildContext context, String mode) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (mode) {
      case 'day':
        final initial = dateRange?.start ?? today;
        // ⚠️ The app's own calendar, not Material's showDatePicker. The
        // stock one arrives unthemed — a white sheet with its own type and
        // its own OK/Cancel — beside dialogs that are dark, rounded and
        // blurred. Same picker the date-range dialog uses.
        final picked = await custom.showOneTapCalendar(
          context,
          initialDate: initial.isAfter(today) ? today : initial,
          firstDate: DateTime(2020),
          lastDate: today,
          label: 'Select Day',
        );
        if (picked != null) {
          final d = DateTime(picked.year, picked.month, picked.day);
          onChanged(DateTimeRange(start: d, end: d), null);
        }
        break;

      case 'month':
        final picked = await _pickMonth(
          context,
          dateRange?.start.year ?? now.year,
          dateRange?.start.month ?? now.month,
        );
        if (picked != null) {
          onChanged(
            DateTimeRange(
              start: DateTime(picked.year, picked.month, 1),
              end: DateTime(picked.year, picked.month + 1, 0),
            ),
            null,
          );
        }
        break;

      case 'year':
        final picked = await _pickYear(context);
        // ⚠️ Emits a YEAR, not a range: on these pages the year filter reads
        // the SR number, not the entry date.
        if (picked != null) onChanged(null, picked);
        break;

      default:
        final picked = await showAppDialog<dynamic>(
          context: context,
          builder: (_) => custom.DateRangePickerDialog(initialRange: dateRange),
        );
        if (picked is DateTimeRange) {
          onChanged(picked, null);
        } else if (picked == false) {
          onChanged(null, null);
        }
    }
  }

  Future<({int year, int month})?> _pickMonth(
      BuildContext context, int initialYear, int initialMonth) {
    final opts = _yearOptions();
    var y = opts.contains(initialYear) ? initialYear : opts.first;
    var m = initialMonth;
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];

    return showAppDialog<({int year, int month})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlg) => AlertDialog(
          // Same chrome as the range dialog next to it: 20px corners, the
          // surface colour, a title row that carries the close button, and
          // a line of help under it.
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: context.colors.surfaceDark,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Select Month & Year',
                      style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const DialogCloseButton(),
                ],
              ),
              const Gap(4),
              Text('The whole month is included, first day to last',
                  style: TextStyle(
                      color: context.colors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.normal)),
            ],
          ),
          content: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 150,
              child: StyledDropdownFormField<int>(
                label: 'Month',
                value: m,
                floatingLabelBehavior: FloatingLabelBehavior.never,
                options: [
                  for (var i = 0; i < 12; i++)
                    StyledDropdownOption(i + 1, months[i]),
                ],
                menuWidth: 170,
                onChanged: (v) => v == null ? null : setDlg(() => m = v),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              child: StyledDropdownFormField<int>(
                label: 'Year',
                value: y,
                floatingLabelBehavior: FloatingLabelBehavior.never,
                options: [
                  for (final o in opts) StyledDropdownOption(o, '$o'),
                ],
                menuWidth: 140,
                onChanged: (v) => v == null ? null : setDlg(() => y = v),
              ),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: TextStyle(color: context.colors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.primaryGold,
                foregroundColor: Colors.black,
              ),
              onPressed: () => Navigator.pop(ctx, (year: y, month: m)),
              child: const Text('Select'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _pickYear(BuildContext context) {
    final opts = _yearOptions();
    var y = year != null && opts.contains(int.tryParse(year!))
        ? int.parse(year!)
        : opts.first;

    return showAppDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlg) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: context.colors.surfaceDark,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Select Year',
                      style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const DialogCloseButton(),
                ],
              ),
              const Gap(4),
              // Says WHICH year, because it is not the entry date.
              Text('Matches the year in the SR number',
                  style: TextStyle(
                      color: context.colors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.normal)),
            ],
          ),
          content: SizedBox(
            width: 260,
            child: StyledDropdownFormField<int>(
              label: 'Year',
              value: y,
              floatingLabelBehavior: FloatingLabelBehavior.never,
              options: [for (final o in opts) StyledDropdownOption(o, '$o')],
              menuWidth: 200,
              onChanged: (v) => v == null ? null : setDlg(() => y = v),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: TextStyle(color: context.colors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.primaryGold,
                foregroundColor: Colors.black,
              ),
              onPressed: () => Navigator.pop(ctx, '$y'),
              child: const Text('Select'),
            ),
          ],
        ),
      ),
    );
  }

  /// [years] as ints, newest first. Falls back to this year and the next
  /// while the SR numbers are still loading — an empty picker is worse than
  /// a short one.
  List<int> _yearOptions() {
    final parsed = years.map(int.tryParse).whereType<int>().toList()
      ..sort((a, b) => b.compareTo(a));
    if (parsed.isEmpty) {
      final y = DateTime.now().year;
      return [y + 1, y];
    }
    return parsed;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StyledDropdownButton<String>(
          value: _active ? _mode : null,
          allLabel: _active ? _label : 'Date Filter',
          icon: _modeIcons[_mode]!,
          menuWidth: 210,
          options: [
            for (final e in _modeLabels.entries)
              StyledDropdownOption(e.key, e.value),
          ],
          // ⚠️ No "same value" guard. Re-picking the mode already showing is
          // how the reader changes the day or month they are looking at.
          onChanged: (v) => v == null ? null : _pick(context, v),
        ),
        if (_active)
          IconButton(
            icon: Icon(Icons.clear_rounded,
                size: 16, color: context.colors.dangerRed),
            tooltip: 'Clear date filter',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => onChanged(null, null),
          ),
      ],
    );
  }
}
