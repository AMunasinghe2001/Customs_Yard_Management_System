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

  Future<void> _pickPeriod(BuildContext anchor, LogPeriod period) async {
    DateTimeRange? range;
    switch (period) {
      case LogPeriod.all:
        range = null;
      case LogPeriod.day:
        final d = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        if (d == null) return;
        range = DateTimeRange(start: d, end: d);
      case LogPeriod.range:
        final picked = await showDialog<dynamic>(
          context: context,
          builder: (_) => const custom.DateRangePickerDialog(),
        );
        if (picked is! DateTimeRange) return;
        range = picked;
      case LogPeriod.month:
        final m = await _pickMonth(anchor);
        if (m == null) return;
        // The 0th day of the NEXT month is the last day of this one, so the
        // window covers a short February without special-casing it.
        range = DateTimeRange(
            start: DateTime(m.year, m.month, 1),
            end: DateTime(m.year, m.month + 1, 0));
      case LogPeriod.year:
        final y = await _pickYear(anchor);
        if (y == null) return;
        range = DateTimeRange(
            start: DateTime(y, 1, 1), end: DateTime(y, 12, 31));
    }

    ref.read(ictLogRangeProvider.notifier).state = range;
    setState(() {
      _period = period;
      _resetPage();
    });
  }

  /// ⚠️ Anchored under the segment that opened it, using the SAME popup every
  /// other dropdown in the app opens (see showStyledOptionsMenu). Both pickers
  /// were a centred AlertDialog full of tall white boxes — a control that
  /// existed nowhere else in the app, for no reason other than that the menu
  /// helper used to be private.
  Future<DateTime?> _pickMonth(BuildContext anchor) {
    final now = DateTime.now();
    // A year of months back from today — the retention window, so every
    // option offered can actually return rows.
    final months = [
      for (var i = 0; i < 12; i++) DateTime(now.year, now.month - i)
    ];
    return showStyledOptionsMenu<DateTime>(
      anchor,
      menuWidth: 200,
      perPage: 12,
      options: [
        for (final m in months)
          StyledDropdownOption(m, DateFormat('MMMM yyyy').format(m)),
      ],
    );
  }

  Future<int?> _pickYear(BuildContext anchor) {
    final now = DateTime.now();
    return showStyledOptionsMenu<int>(
      anchor,
      menuWidth: 160,
      perPage: 8,
      options: [
        for (var y = now.year; y >= now.year - 4; y--)
          StyledDropdownOption(y, '$y'),
      ],
    );
  }

  /// What the period chip reads once a window is chosen.
  String _periodLabel(DateTimeRange? range) {
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
        return '${DateFormat('dd MMM').format(range.start)} — '
            '${DateFormat('dd MMM yyyy').format(range.end)}';
    }
  }

  // ── Filtering ───────────────────────────────────────────────────────────
  //
  // ⚠️ There is none here any more. Narrowing lives in SQL (see
  // getAllLogsAcrossOffices): with one page in hand, a filter applied here
  // would hide rows from the page you are on and leave every row behind it,
  // and the count under the table would be a different number from the rows
  // above it.

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
      // ⚠️ No page heading here. The console header names this section and
      // says what it holds; a screen that prints its own title again twenty
      // pixels below is the surest sign of a page designed on its own rather
      // than as one module of a console.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Period ────────────────────────────────────────────
          // One setting with five positions, so it is drawn as one track --
          // see IctSegmented for why five separate buttons read wrongly.
          Row(children: [
            IctSegmented(
              accent: accent,
              children: [
                for (final p in LogPeriod.values)
                  IctSegment(
                    label: p.label,
                    icon: switch (p) {
                      LogPeriod.all => Icons.all_inclusive_rounded,
                      LogPeriod.day => Icons.today_rounded,
                      LogPeriod.range => Icons.date_range_rounded,
                      LogPeriod.month => Icons.calendar_view_month_rounded,
                      LogPeriod.year => Icons.calendar_today_rounded,
                    },
                    selected: _period == p,
                    onTap: (anchor) => _pickPeriod(anchor, p),
                  ),
              ],
            ),
            const Gap(12),
            // The exact window in force, and a one-tap way out of it. Only
            // once one IS in force: with no window the segmented control
            // already says "All Time", and a chip repeating it is noise.
            if (range != null)
              _PeriodChip(
                label: _periodLabel(range),
                accent: accent,
                active: true,
                onClear: () {
                  ref.read(ictLogRangeProvider.notifier).state = null;
                  setState(() {
                    _period = LogPeriod.all;
                    _resetPage();
                  });
                },
              ),
          ]).animate().fadeIn(duration: 300.ms),
          const Gap(14),

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
                  // Every role that writes to the log, so ICT can watch one
                  // office at a time.
                  options: const [
                    StyledDropdownOption('all', 'All Roles'),
                    StyledDropdownOption('officer', 'Officer'),
                    StyledDropdownOption('admin', 'DC / SDDC'),
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
                  // Its own query, not the page's rows -- see
                  // ictLogEntityTypesProvider.
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
          ]).animate().fadeIn(duration: 300.ms, delay: 120.ms),
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

/// The window currently in force, with a clear button once one is set.
class _PeriodChip extends StatelessWidget {
  final String label;
  final Color accent;
  final bool active;
  final VoidCallback? onClear;

  const _PeriodChip({
    required this.label,
    required this.accent,
    required this.active,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? accent : context.colors.textMuted;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 7, active ? 4 : 12, 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.event_rounded, size: 15, color: color),
        const Gap(7),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 12.5, fontWeight: FontWeight.w700)),
        if (active) ...[
          const Gap(2),
          IconButton(
            icon: Icon(Icons.close_rounded, size: 15, color: color),
            onPressed: onClear,
            tooltip: 'Show all time',
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ]),
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
      'admin' => ('DC / SDDC', context.colors.primaryGold),
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
