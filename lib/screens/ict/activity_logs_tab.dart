import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/yards.dart';
import '../../models/models.dart';
import '../../widgets/date_range_picker_dialog.dart' as custom;
import '../../widgets/empty_table_state.dart';
import '../../widgets/error_view.dart';
import '../../widgets/styled_dropdown.dart';
import '../../widgets/tooltip_text.dart';
import 'ict_ui.dart';

/// How the log's date window is being chosen.
///
/// The window itself is pushed into SQL (see [ictLogRangeProvider]); this only
/// says which shape of picker produced it, so the chip can read back what the
/// officer asked for rather than a pair of raw dates.
enum LogPeriod {
  all('All Time'),
  day('Single Day'),
  range('Date Range'),
  month('By Month'),
  year('By Year');

  final String label;
  const LogPeriod(this.label);
}

/// Every action taken anywhere in the application, for the ICT Directorate.
///
/// The yard admin's own Activity Logs tab is deliberately narrow: one yard,
/// and only that yard's own staff. ICT provisions every account in every
/// office, so this is the opposite — the whole log, with the filtering done
/// here rather than in the query's WHERE clause.
class ActivityLogsTab extends ConsumerStatefulWidget {
  final Color accent;
  const ActivityLogsTab({super.key, required this.accent});

  @override
  ConsumerState<ActivityLogsTab> createState() => _ActivityLogsTabState();
}

class _ActivityLogsTabState extends ConsumerState<ActivityLogsTab> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  String _selectedYard = 'all';
  String _selectedRole = 'all';
  String _selectedEntity = 'all';
  LogPeriod _period = LogPeriod.all;
  int _page = 0;

  static const int _pageSize = 25;

  /// ⚠️ Pushes the filters into the QUERY rather than applying them to rows.
  ///
  /// The screen holds one page now, so filtering here would filter that page —
  /// hiding rows from the page you are on while leaving the ones behind it
  /// untouched, and disagreeing with the count. Every narrowing has to reach
  /// the WHERE clause, so it all goes through here.
  void _pushQuery() {
    ref.read(ictLogQueryProvider.notifier).state = IctLogQuery(
      // The dropdown's value is a YardFilterOption key: a bare yard code, or
      // "<yard>|<directorate>" for one entry of a multi-directorate yard.
      // Only the yard half is stamped on a log row.
      yard: _selectedYard == 'all' ? null : _selectedYard.split('|').first,
      role: _selectedRole == 'all' ? null : _selectedRole,
      entityType: _selectedEntity == 'all' ? null : _selectedEntity,
      search: _search.trim(),
      page: _page,
      pageSize: _pageSize,
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Back to the first page, then re-ask the server. A narrowing that
  /// left the page number alone would land you on page 7 of a 2-page
  /// result, which comes back empty.
  void _resetPage() {
    _page = 0;
    _pushQuery();
  }

  // ── Date window ─────────────────────────────────────────────────────────
  // Each picker produces a DateTimeRange; the provider turns that into the
  // query's bounds. "All Time" clears it, and retention keeps the table to a
  // year regardless.

  Future<void> _pickSingleDay() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final range = ref.read(ictLogRangeProvider);
    final initial = range?.start ?? today;
    final clampedInitial = initial.isAfter(today) ? today : initial;

    final picked = await custom.showOneTapCalendar(
      context,
      initialDate: clampedInitial,
      firstDate: DateTime(2020),
      lastDate: today,
      label: 'Single Day',
      accentColor: widget.accent,
    );
    if (picked == null) return;
    final start = DateTime(picked.year, picked.month, picked.day);
    final end = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
    ref.read(ictLogRangeProvider.notifier).state =
        DateTimeRange(start: start, end: end);
    setState(() {
      _period = LogPeriod.day;
      _resetPage();
    });
  }

  Future<void> _pickCustomRange() async {
    final initial = ref.read(ictLogRangeProvider);
    final picked = await showIctDialog<dynamic>(
      context: context,
      builder: (_) => custom.DateRangePickerDialog(
        initialRange: initial,
        accentColor: widget.accent,
      ),
    );
    if (picked is DateTimeRange) {
      ref.read(ictLogRangeProvider.notifier).state = picked;
      setState(() {
        _period = LogPeriod.range;
        _resetPage();
      });
    } else if (picked == false) {
      ref.read(ictLogRangeProvider.notifier).state = null;
      setState(() {
        _period = LogPeriod.all;
        _resetPage();
      });
    }
  }

  Future<void> _pickMonthDialog() async {
    final now = DateTime.now();
    final range = ref.read(ictLogRangeProvider);
    int selectedYear = range?.start.year ?? now.year;
    int selectedMonth = range?.start.month ?? now.month;
    final currentYear = now.year;
    final currentMonth = now.month;
    if (selectedYear > currentYear) selectedYear = currentYear;
    if (selectedYear == currentYear && selectedMonth > currentMonth) {
      selectedMonth = currentMonth;
    }
    final years = List.generate(10, (i) => currentYear - i);
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];

    final res = await showIctDialog<({int year, int month})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final maxMonth = (selectedYear == currentYear) ? currentMonth : 12;
          if (selectedMonth > maxMonth) selectedMonth = maxMonth;

          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: context.colors.cardDark,
            title: Text('Select Month & Year',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 320,
              child: Row(
                children: [
                  Expanded(
                    child: StyledDropdownFormField<int>(
                      label: 'Month',
                      value: selectedMonth,
                      floatingLabelBehavior: FloatingLabelBehavior.never,
                      accentColor: widget.accent,
                      options: List.generate(
                        maxMonth,
                        (i) => StyledDropdownOption(i + 1, months[i]),
                      ),
                      menuWidth: 160,
                      onChanged: (v) {
                        if (v != null) setDlgState(() => selectedMonth = v);
                      },
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: StyledDropdownFormField<int>(
                      label: 'Year',
                      value: selectedYear,
                      floatingLabelBehavior: FloatingLabelBehavior.never,
                      accentColor: widget.accent,
                      options: years
                          .map((y) => StyledDropdownOption(y, '$y'))
                          .toList(),
                      menuWidth: 140,
                      onChanged: (v) {
                        if (v != null) {
                          setDlgState(() {
                            selectedYear = v;
                            if (selectedYear == currentYear &&
                                selectedMonth > currentMonth) {
                              selectedMonth = currentMonth;
                            }
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel',
                    style: TextStyle(color: context.colors.textMuted)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(
                    context, (year: selectedYear, month: selectedMonth)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                child: const Text('Select',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );

    if (res != null) {
      final start = DateTime(res.year, res.month, 1);
      final end = DateTime(res.year, res.month + 1, 0, 23, 59, 59);
      ref.read(ictLogRangeProvider.notifier).state =
          DateTimeRange(start: start, end: end);
      setState(() {
        _period = LogPeriod.month;
        _resetPage();
      });
    }
  }

  Future<void> _pickYearDialog() async {
    final now = DateTime.now();
    final range = ref.read(ictLogRangeProvider);
    int selectedYear = range?.start.year ?? now.year;
    final currentYear = now.year;
    if (selectedYear > currentYear) selectedYear = currentYear;
    final years = List.generate(10, (i) => currentYear - i);

    final res = await showIctDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: context.colors.cardDark,
            title: Text('Select Year',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 280,
              child: StyledDropdownFormField<int>(
                label: 'Year',
                value: selectedYear,
                floatingLabelBehavior: FloatingLabelBehavior.never,
                accentColor: widget.accent,
                options:
                    years.map((y) => StyledDropdownOption(y, '$y')).toList(),
                menuWidth: 260,
                onChanged: (v) {
                  if (v != null) setDlgState(() => selectedYear = v);
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel',
                    style: TextStyle(color: context.colors.textMuted)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, selectedYear),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                child: const Text('Select',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );

    if (res != null) {
      final start = DateTime(res, 1, 1);
      final end = DateTime(res, 12, 31, 23, 59, 59);
      ref.read(ictLogRangeProvider.notifier).state =
          DateTimeRange(start: start, end: end);
      setState(() {
        _period = LogPeriod.year;
        _resetPage();
      });
    }
  }

  String _dateDropdownDisplay(DateTimeRange? range) {
    if (range == null) return 'All Time';
    switch (_period) {
      case LogPeriod.day:
        return DateFormat('dd MMM yyyy').format(range.start);
      case LogPeriod.month:
        return DateFormat('MMMM yyyy').format(range.start);
      case LogPeriod.year:
        return '${range.start.year}';
      case LogPeriod.range:
      case LogPeriod.all:
        return '${DateFormat('dd MMM').format(range.start)} – ${DateFormat('dd MMM yyyy').format(range.end)}';
    }
  }

  // ── Filtering ───────────────────────────────────────────────────────────

  String _prettyEntity(String raw) => raw
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  String _prettyDetails(AuditLogModel l) {
    final d = l.details;
    if (d == null || d.isEmpty) return '—';
    return d.entries.map((e) => '${e.key}: ${e.value}').join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final async = ref.watch(ictAllOfficeLogsProvider);
    final range = ref.watch(ictLogRangeProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Toolbar ───────────────────────────────────────────
          IctToolbar(children: [
            Expanded(
              flex: 3,
              child: IctSearchField(
                controller: _searchCtrl,
                accent: accent,
                hintText: 'Search action, user, entity or details',
                onChanged: (v) => setState(() {
                  _search = v;
                  _resetPage();
                }),
                onClear: () {
                  _searchCtrl.clear();
                  setState(() {
                    _search = '';
                    _resetPage();
                  });
                },
              ),
            ),
            Expanded(
              flex: 2,
              child: IctSelect(
                label: 'Yard',
                icon: Icons.warehouse_rounded,
                accent: accent,
                value: _selectedYard,
                options: [
                  const StyledDropdownOption('all', 'All Yards'),
                  for (final o
                      in ref.watch(yardFilterOptionsProvider).valueOrNull ??
                          [
                            for (final y in kYards)
                              YardFilterOption(
                                  value: y.code,
                                  label: y.name,
                                  filterYard: y.code)
                          ])
                    StyledDropdownOption(o.value, o.label),
                ],
                onChanged: (v) => setState(() {
                  _selectedYard = v ?? 'all';
                  _resetPage();
                }),
              ),
            ),
            Expanded(
              flex: 2,
              child: IctSelect(
                label: 'Directorate / Role',
                icon: Icons.badge_rounded,
                accent: accent,
                value: _selectedRole,
                options: const [
                  StyledDropdownOption('all', 'All Roles'),
                  StyledDropdownOption('officer', 'Officer'),
                  StyledDropdownOption('admin', 'SDDC / DDC'),
                  StyledDropdownOption('disposal', 'Central Disposal'),
                  StyledDropdownOption('valuation', 'Valuation'),
                  StyledDropdownOption('appeal', 'Appeal'),
                  StyledDropdownOption('executive', 'Top Management'),
                  StyledDropdownOption('ict', 'ICT'),
                ],
                onChanged: (v) => setState(() {
                  _selectedRole = v ?? 'all';
                  _resetPage();
                }),
              ),
            ),
            Expanded(
              flex: 2,
              child: IctSelect(
                label: 'Activity',
                icon: Icons.category_rounded,
                accent: accent,
                value: _selectedEntity,
                options: [
                  const StyledDropdownOption('all', 'All Activity'),
                  for (final e
                      in ref.watch(ictLogEntityTypesProvider).valueOrNull ??
                          const <String>[])
                    StyledDropdownOption(e, _prettyEntity(e)),
                ],
                onChanged: (v) => setState(() {
                  _selectedEntity = v ?? 'all';
                  _resetPage();
                }),
              ),
            ),
            Expanded(
              flex: 2,
              child: IctSelect(
                label: 'Date / Period',
                icon: Icons.date_range_rounded,
                accent: accent,
                value: range == null ? 'all' : _period.name,
                customDisplayLabel: _dateDropdownDisplay(range),
                options: const [
                  StyledDropdownOption('all', 'All Time'),
                  StyledDropdownOption('day', 'Single Day'),
                  StyledDropdownOption('range', 'Custom Date Range'),
                  StyledDropdownOption('month', 'By Month'),
                  StyledDropdownOption('year', 'By Year'),
                ],
                onChanged: (v) {
                  if (v == 'all') {
                    ref.read(ictLogRangeProvider.notifier).state = null;
                    setState(() {
                      _period = LogPeriod.all;
                      _resetPage();
                    });
                  } else if (v == 'day') {
                    _pickSingleDay();
                  } else if (v == 'range') {
                    _pickCustomRange();
                  } else if (v == 'month') {
                    _pickMonthDialog();
                  } else if (v == 'year') {
                    _pickYearDialog();
                  }
                },
              ),
            ),
          ]).animate().fadeIn(duration: 300.ms),
          const Gap(16),

          // ── Table ─────────────────────────────────────────────
          Expanded(
            child: async.when(
              skipLoadingOnReload: true,
              loading: () =>
                  Center(child: CircularProgressIndicator(color: accent)),
              error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.refresh(ictAllOfficeLogsProvider)),
              data: (result) {
                final pageRows = result.rows;
                final total = result.total;
                final maxPage = total == 0 ? 0 : (total - 1) ~/ _pageSize;
                final page = _page.clamp(0, maxPage);

                return IctSectionCard(
                  icon: Icons.history_rounded,
                  title: 'Audit Trail',
                  subtitle: 'Every action across all yards and directorates.',
                  // The count of everything the filters matched, which is
                  // what the server counted -- not the length of this page.
                  badge: '$total ${total == 1 ? 'action' : 'actions'}',
                  fill: true,
                  child: Column(children: [
                    Expanded(
                      child: IctTableTheme(
                        child: DataTable2(
                          columnSpacing: 16,
                          horizontalMargin: 20,
                          fixedTopRows: 1,
                          minWidth: 1080,
                          headingRowHeight: kIctHeadingHeight,
                          // ⚠️ Taller than the other tables on purpose. The
                          // audit trail is the one ICT page whose card fills
                          // the window, so at kIctRowHeight its 25 rows ended
                          // well short of the bottom and left a band of empty
                          // card under them. Taller rows spend that space on
                          // the data instead, and a log line — a timestamp, a
                          // long action and a details string — reads better
                          // with the room.
                          dataRowHeight: kIctLogRowHeight,
                          isHorizontalScrollBarVisible: false,
                          empty: const EmptyTableState(
                            icon: Icons.history_rounded,
                            message: 'No activity for these filters',
                            subtitle:
                                'Try a wider date window, or clear a filter.',
                          ),
                          columns: [
                            ictCol('When',
                                size: ColumnSize.S, fixedWidth: 150),
                            ictCol('User', size: ColumnSize.M),
                            ictCol('Role',
                                size: ColumnSize.S,
                                fixedWidth: 120,
                                center: true),
                            ictCol('Yard',
                                size: ColumnSize.S, fixedWidth: 120),
                            ictCol('Action', size: ColumnSize.L),
                            ictCol('Activity',
                                size: ColumnSize.S, fixedWidth: 130),
                            ictCol('Details', size: ColumnSize.L),
                          ],
                          rows: pageRows.asMap().entries.map((entry) {
                            final l = entry.value;
                            return DataRow2(
                              color: ictRowColor(context, entry.key),
                              cells: [
                                DataCell(TooltipText(
                                    DateFormat('dd MMM yyyy, HH:mm')
                                        .format(l.createdAt),
                                    style: TextStyle(
                                        color: context.colors.textMuted,
                                        fontSize: 12.5))),
                                DataCell(TooltipText(
                                    l.userFullName ?? 'Unknown',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: context.colors.textPrimary,
                                        fontWeight: FontWeight.w600))),
                                DataCell(Center(
                                    child: _RoleChip(role: l.userRole))),
                                DataCell(TooltipText(
                                    l.yard == null || l.yard!.isEmpty
                                        ? '—'
                                        : yardName(l.yard),
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: context.colors.textSecondary,
                                        fontSize: 12.5))),
                                DataCell(TooltipText(l.action,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: context.colors.accentLightBlue,
                                        fontSize: 12.5))),
                                DataCell(TooltipText(
                                    _prettyEntity(l.entityType),
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: context.colors.textMuted,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700))),
                                DataCell(TooltipText(_prettyDetails(l),
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: context.colors.textMuted,
                                        fontSize: 12))),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    // The pager belongs to the table, so it sits on the same
                    // card rather than floating under it.
                    Divider(
                        height: 1,
                        thickness: 1,
                        color: context.colors.borderColor),
                    IctPager(
                      total: total,
                      page: page,
                      pageSize: _pageSize,
                      accent: accent,
                      onPageChanged: (p) => setState(() {
                        _page = p;
                        _pushQuery();
                      }),
                    ),
                  ]),
                ).animate().slideY(begin: 0.05, duration: 400.ms).fadeIn();
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The actor's role, coloured per office so one is picked out at a glance.
class _RoleChip extends StatelessWidget {
  final String? role;
  const _RoleChip({required this.role});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (role) {
      'officer' => ('Officer', context.colors.accentLightBlue),
      'admin' => ('SDDC / DDC', context.colors.primaryGold),
      'disposal' => ('Disposal', context.colors.successGreen),
      'valuation' => ('Valuation', context.colors.warningAmber),
      'appeal' => ('Appeal', context.colors.heldOrange),
      'executive' => ('Top Mgmt', context.colors.customsBlue),
      'ict' => ('ICT', context.colors.dangerRed),
      _ => (role?.toUpperCase() ?? '—', context.colors.textMuted),
    };
    // No dot: this is WHO acted, not a state, and a column of coloured dots
    // beside a column of status dots would read as the same kind of thing.
    return IctStatusPill(label: label, color: color, dot: false, width: 88);
  }
}
