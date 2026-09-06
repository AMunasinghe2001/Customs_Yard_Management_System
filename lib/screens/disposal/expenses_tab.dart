import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../core/yards.dart';
import '../../models/models.dart';
import '../../widgets/empty_table_state.dart';
import '../../widgets/error_view.dart';
import '../../widgets/styled_form_dialog.dart';
import '../../widgets/table_pager.dart';
import '../../widgets/tooltip_text.dart';
import '../../widgets/styled_dropdown.dart';
import '../../widgets/package_details_dialog.dart';
import '../../widgets/date_range_picker_dialog.dart' as custom;
import 'disposal_shared.dart';

/// Page index for this tab's client-side pager.
final _expensePageProvider = StateProvider<int>((ref) => 0);

/// Date filter providers for Expenses tab.
final _expenseDateFilterTypeProvider = StateProvider<String>((ref) => 'all');
final _expenseDateRangeProvider = StateProvider<DateTimeRange?>((ref) => null);

/// Central Disposal records what each GOODS ITEM cost to dispose of.
///
/// Two costs are entered, item by item — one SR can hold many goods and each is
/// destroyed and advertised on its own:
///
///   Destruction Expenses  — carrying out the destruction
///   Advertising Expenses  — advertising the tender
///
/// A REFUND is never typed in. The destroying deposit is money held against
/// these costs, so whatever is left over goes back:
///
///     refund = destroying deposit − (destruction + advertising)
///
/// The tab shows that arithmetic per goods so the officer can see, as they
/// enter a cost, exactly what will be refunded.
class ExpensesTab extends ConsumerWidget {
  const ExpensesTab({super.key});

  /// Keys this tab's shared search box and yard dropdown.
  static const _tabKey = 'expenses';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final green = context.colors.successGreen;
    final amber = context.colors.warningAmber;
    // ⚠️ One PAGE. `srFinancialsProvider` calls getAllPackages() AND
    // getTenderSales() and rolls the whole yard up in Dart -- per item, per
    // tax name. That was measured and left alone once, on ONE yard; this tab
    // shows twenty-eight. `sr_expense_summary` (postgres/30) settles which
    // SRs have money to account for, and the ledger is built for that page.
    final page = ref.watch(_expensePageProvider);
    final query = ExpenseQuery(
      page: page,
      search: ref.watch(disposalSearchProvider(_tabKey)),
      yardFilter: ref.watch(disposalYardFilterProvider(_tabKey)),
      dateStart: ref.watch(_expenseDateRangeProvider)?.start,
      dateEnd: ref.watch(_expenseDateRangeProvider)?.end,
    );
    final rowsAsync = ref.watch(expensePageProvider(query));
    final dateFilterType = ref.watch(_expenseDateFilterTypeProvider);
    final dateRange = ref.watch(_expenseDateRangeProvider);
    final dateLabel = _getExpenseDateFilterLabel(dateFilterType, dateRange);

    return Padding(
      // ⚠️ 16, not 24 — see the dashboard's own tab bodies. Vertical chrome
      // on a table page is rows the officer cannot see.
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title · search · yard · date — the standard filter header.
          Row(children: [
            Text('💰  Disposal Expenses',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            const DisposalSearch(
                tabKey: _tabKey, hint: 'Search SR / goods\u2026'),
            const Gap(12),
            YardAllFilter(
              value: ref.watch(disposalYardFilterProvider(_tabKey)),
              onChanged: (v) {
                ref.read(disposalYardFilterProvider(_tabKey).notifier).state =
                    v;
                ref.read(_expensePageProvider.notifier).state = 0;
              },
            ),
            const Gap(12),
            DisposalDateFilter(
              filterType: dateFilterType,
              label: dateLabel,
              onChanged: (type) =>
                  _handleExpenseDatePick(context, ref, type ?? 'all'),
            ),
          ]).animate().fadeIn(duration: 300.ms),
          const Gap(14),
          Expanded(
            child: rowsAsync.when(
              skipLoadingOnReload: true,
              loading: () =>
                  Center(child: CircularProgressIndicator(color: green)),
              error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.refresh(expensePageProvider(query))),
              data: (result) {
                // Filtered, sorted and paged by the database, including
                // the "carries a deposit or has a cost" rule -- an SR with
                // neither has nothing to show.
                final pageRows = result.rows;
                final total = result.total;
                final maxPage =
                    total == 0 ? 0 : (total - 1) ~/ kDispositionPageSize;
                final safePage = page > maxPage ? maxPage : page;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Counts the SAME rows the table shows.
                    Row(children: [
                      StatChip(
                          label: 'SRs with a deposit',
                          // The DATABASE's count for this filter.
                          value: '$total',
                          color: amber),
                      const Gap(12),
                      // ⚠️ Totals across EVERY filtered SR, from their own
                      // query -- summing the page would report a fraction of
                      // the money and understate what has been spent.
                      Expanded(child: _TotalsStrip(totals: result.totals)),
                    ]),
                    const Gap(14),
                    Expanded(child: _ExpensesTable(rows: pageRows)),
                    TablePager(
                      total: total,
                      page: safePage,
                      onPageChanged: (p) =>
                          ref.read(_expensePageProvider.notifier).state = p,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class DisposalDateFilter extends StatelessWidget {
  final String? filterType;
  final String label;
  final ValueChanged<String?> onChanged;

  const DisposalDateFilter({
    super.key,
    required this.filterType,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final gold = context.colors.primaryGold;
    final isSelected = filterType != null && filterType != 'all';

    return SizedBox(
      width: 200,
      child: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
                filled: true,
                fillColor: gold.withOpacity(isSelected ? 0.12 : 0.06),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                        color: gold.withOpacity(isSelected ? 1.0 : 0.4))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                        color: gold.withOpacity(isSelected ? 1.0 : 0.4))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: gold, width: 1.5)),
              ),
        ),
        child: StyledDropdownFormField<String>(
          label: isSelected ? label : 'Date Filter',
          floatingLabelBehavior: FloatingLabelBehavior.never,
          value:
              (filterType == null || filterType == 'all') ? '_all' : filterType,
          helperText: null,
          isDense: true,
          menuWidth: 200,
          splashRadius: 14,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          prefixIcon: Icon(
            filterType == 'day'
                ? Icons.today_rounded
                : (filterType == 'month'
                    ? Icons.calendar_view_month_rounded
                    : (filterType == 'year'
                        ? Icons.calendar_view_week_rounded
                        : Icons.calendar_month_rounded)),
            color: gold,
            size: 20,
          ),
          options: const [
            StyledDropdownOption('_all', 'All Time'),
            StyledDropdownOption('range', 'Custom Date Range'),
            StyledDropdownOption('day', 'Single Day'),
            StyledDropdownOption('month', 'By Month'),
            StyledDropdownOption('year', 'By Year'),
          ],
          onChanged: (v) => onChanged((v == null || v == '_all') ? 'all' : v),
        ),
      ),
    );
  }
}

// ⚠️ `_matchesDateRange` moved into `sr_expense_summary`'s `activity_date`
// (postgres/30), fallbacks and all — when money was last spent, then the SR's
// entry date, then created_at, and finally THE YEAR IN THE SR NUMBER.
//
// That last one is the reason it needed care: a legacy SR can carry no usable
// date, and the app matched it on its number's year rather than dropping it
// from every date filter. The view's verify block asserts no row is dateless,
// because a dateless row is one a range filter hides without saying so.

String _getExpenseDateFilterLabel(String type, DateTimeRange? range) {
  if (range == null || type == 'all') return 'All Time';
  if (type == 'day') {
    return DateFormat('MMM d, yyyy').format(range.start);
  }
  if (type == 'month') {
    return DateFormat('MMM yyyy').format(range.start);
  }
  if (type == 'year') {
    return '${range.start.year}';
  }
  return '${DateFormat('MMM d').format(range.start)} - ${DateFormat('MMM d').format(range.end)}';
}

Future<void> _handleExpenseDatePick(
    BuildContext context, WidgetRef ref, String filterType) async {
  final currentRange = ref.read(_expenseDateRangeProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  ref.read(_expenseDateFilterTypeProvider.notifier).state = filterType;

  if (filterType == 'all') {
    ref.read(_expenseDateRangeProvider.notifier).state = null;
    ref.read(_expensePageProvider.notifier).state = 0;
    return;
  }

  if (filterType == 'day') {
    final initial = currentRange?.start ?? today;
    final clampedInitial = initial.isAfter(today) ? today : initial;
    final picked = await showDatePicker(
      context: context,
      initialDate: clampedInitial,
      firstDate: DateTime(2020),
      lastDate: today,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.dark(
            primary: context.colors.primaryGold,
            onPrimary: Colors.black,
            surface: context.colors.cardDark,
            onSurface: context.colors.textPrimary,
          ),
          dialogBackgroundColor: context.colors.cardDark,
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      ref.read(_expenseDateRangeProvider.notifier).state = DateTimeRange(
        start: DateTime(picked.year, picked.month, picked.day, 0, 0, 0),
        end: DateTime(picked.year, picked.month, picked.day, 23, 59, 59),
      );
      ref.read(_expensePageProvider.notifier).state = 0;
    }
  } else if (filterType == 'month') {
    final initialY = currentRange?.start.year ?? now.year;
    final initialM = currentRange?.start.month ?? now.month;
    final picked =
        await _showExpenseMonthPickerDialog(context, initialY, initialM);
    if (picked != null) {
      final lastDay = DateTime(picked.year, picked.month + 1, 0).day;
      ref.read(_expenseDateRangeProvider.notifier).state = DateTimeRange(
        start: DateTime(picked.year, picked.month, 1, 0, 0, 0),
        end: DateTime(picked.year, picked.month, lastDay, 23, 59, 59),
      );
      ref.read(_expensePageProvider.notifier).state = 0;
    }
  } else if (filterType == 'year') {
    final initialY = currentRange?.start.year ?? now.year;
    final picked = await _showExpenseYearPickerDialog(context, initialY);
    if (picked != null) {
      ref.read(_expenseDateRangeProvider.notifier).state = DateTimeRange(
        start: DateTime(picked, 1, 1, 0, 0, 0),
        end: DateTime(picked, 12, 31, 23, 59, 59),
      );
      ref.read(_expensePageProvider.notifier).state = 0;
    }
  } else if (filterType == 'range') {
    final picked = await showDialog<dynamic>(
      context: context,
      builder: (ctx) =>
          custom.DateRangePickerDialog(initialRange: currentRange),
    );
    if (picked is DateTimeRange) {
      ref.read(_expenseDateRangeProvider.notifier).state = DateTimeRange(
        start: DateTime(
            picked.start.year, picked.start.month, picked.start.day, 0, 0, 0),
        end: DateTime(
            picked.end.year, picked.end.month, picked.end.day, 23, 59, 59),
      );
      ref.read(_expensePageProvider.notifier).state = 0;
    } else if (picked == false) {
      ref.read(_expenseDateFilterTypeProvider.notifier).state = 'all';
      ref.read(_expenseDateRangeProvider.notifier).state = null;
      ref.read(_expensePageProvider.notifier).state = 0;
    }
  }
}

Future<({int year, int month})?> _showExpenseMonthPickerDialog(
    BuildContext context, int initialYear, int initialMonth) async {
  int selectedYear = initialYear;
  int selectedMonth = initialMonth;
  final currentYear = DateTime.now().year;
  final currentMonth = DateTime.now().month;

  if (selectedYear > currentYear) selectedYear = currentYear;
  if (selectedYear == currentYear && selectedMonth > currentMonth) {
    selectedMonth = currentMonth;
  }

  final years = List.generate(10, (i) => currentYear - i);
  final months = [
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

  return showDialog<({int year, int month})>(
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
                  fontSize: 18,
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
                    options: List.generate(
                      maxMonth,
                      (i) => StyledDropdownOption(i + 1, months[i]),
                    ),
                    menuWidth: 160,
                    onChanged: (m) {
                      if (m != null) setDlgState(() => selectedMonth = m);
                    },
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: StyledDropdownFormField<int>(
                    label: 'Year',
                    value: selectedYear,
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                    options: years
                        .map((y) => StyledDropdownOption(y, '$y'))
                        .toList(),
                    menuWidth: 140,
                    onChanged: (y) {
                      if (y != null) {
                        setDlgState(() {
                          selectedYear = y;
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
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: TextStyle(color: context.colors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.primaryGold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(
                  ctx, (year: selectedYear, month: selectedMonth)),
              child: const Text('Select',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    ),
  );
}

Future<int?> _showExpenseYearPickerDialog(
    BuildContext context, int initialYear) async {
  int selectedYear = initialYear;
  final currentYear = DateTime.now().year;
  if (selectedYear > currentYear) selectedYear = currentYear;
  final years = List.generate(10, (i) => currentYear - i);

  return showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDlgState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: context.colors.cardDark,
        title: Text('Select Year',
            style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 260,
          child: StyledDropdownFormField<int>(
            label: 'Year',
            value: selectedYear,
            floatingLabelBehavior: FloatingLabelBehavior.never,
            options: years.map((y) => StyledDropdownOption(y, '$y')).toList(),
            menuWidth: 200,
            onChanged: (v) {
              if (v != null) setDlgState(() => selectedYear = v);
            },
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, selectedYear),
            child: const Text('Select',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ),
  );
}

/// Running totals for whatever the table is currently showing.
class _TotalsStrip extends StatelessWidget {
  /// Summed in SQL across every SR the filter matches — see
  /// `getExpenseTotals`.
  ///
  /// ⚠️ It used to add up the rows on screen. That was right while the table
  /// held every row and became wrong the moment it held twenty: the strip
  /// would have reported one page's worth of money as the directorate's total.
  final Map<String, double> totals;
  const _TotalsStrip({required this.totals});

  @override
  Widget build(BuildContext context) {
    final deposit = totals['deposit'] ?? 0;
    final destruction = totals['destruction'] ?? 0;
    final advertising = totals['advertising'] ?? 0;
    final labour = totals['labour'] ?? 0;
    final transport = totals['transport'] ?? 0;
    final auction = totals['auction'] ?? 0;
    final refund = totals['refund'] ?? 0;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _TotalChip(
            label: 'Destroying Deposits',
            value: deposit,
            color: context.colors.accentLightBlue,
            icon: Icons.savings_rounded),
        _TotalChip(
            label: 'Destruction Expenses',
            value: destruction,
            color: context.colors.dangerRed,
            icon: Icons.local_fire_department_rounded),
        _TotalChip(
            label: 'Advertising Expenses',
            value: advertising,
            color: context.colors.warningAmber,
            icon: Icons.campaign_rounded),
        _TotalChip(
            label: 'Labour Costs',
            value: labour,
            color: context.colors.accentLightBlue,
            icon: Icons.engineering_rounded),
        _TotalChip(
            label: 'Transport Costs',
            value: transport,
            color: context.colors.customsBlue,
            icon: Icons.local_shipping_rounded),
        _TotalChip(
            label: 'Auction Expenses',
            value: auction,
            color: context.colors.primaryGold,
            icon: Icons.gavel_rounded),
        _TotalChip(
            label: 'Refunds',
            value: refund,
            color: context.colors.successGreen,
            icon: Icons.undo_rounded),
      ],
    ).animate().fadeIn(duration: 350.ms);
  }
}

class _TotalChip extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final IconData icon;
  const _TotalChip(
      {required this.label,
      required this.value,
      required this.color,
      required this.icon});

  @override
  Widget build(BuildContext context) {
    // Same padding and single-line layout as [StatChip] beside it, so the
    // whole strip sits at one uniform height.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: color),
        const Gap(6),
        Text(NumberFormat('#,##0.00').format(value),
            style: TextStyle(
                color: color, fontSize: 14, fontWeight: FontWeight.w800)),
        const Gap(6),
        Text(label,
            style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _ExpensesTable extends ConsumerWidget {
  final List<SrFinancials> rows;
  const _ExpensesTable({required this.rows});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = NumberFormat('#,##0.00');
    final packages = ref.watch(livePackagesProvider).valueOrNull ?? [];
    final storageRate = ref.watch(storageRateProvider).valueOrNull ?? const {};

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: DataTable2(
          columnSpacing: 6,
          horizontalMargin: 8,
          fixedTopRows: 1,
          headingRowColor: WidgetStateProperty.all(context.colors.surfaceDark),
          empty: const EmptyTableState(
              icon: Icons.receipt_long_outlined,
              message: 'No SRs with a destroying deposit',
              subtitle: 'SRs carrying a deposit appear here once registered.'),
          columns: const [
            DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
            DataColumn2(
                label: Text('Destroy Deposit'),
                size: ColumnSize.S,
                numeric: true),
            DataColumn2(
                label: Text('Destruction'), size: ColumnSize.S, numeric: true),
            DataColumn2(
                label: Text('Advertising'), size: ColumnSize.S, numeric: true),
            DataColumn2(
                label: Text('Labour'), size: ColumnSize.S, numeric: true),
            DataColumn2(
                label: Text('Transport'), size: ColumnSize.S, numeric: true),
            DataColumn2(
                label: Text('Auction'), size: ColumnSize.S, numeric: true),
            DataColumn2(
                label: Text('Total Exp.'), size: ColumnSize.S, numeric: true),
            DataColumn2(
                label: Text('Refund'), size: ColumnSize.S, numeric: true),
            DataColumn2(
                label: Center(child: Text('Status')),
                size: ColumnSize.S,
                fixedWidth: 85),
            DataColumn2(
                label: Center(child: Text('Record')),
                size: ColumnSize.S,
                fixedWidth: 55),
            DataColumn2(
                label: Center(child: Text('Details')),
                size: ColumnSize.S,
                fixedWidth: 55),
          ],
          rows: [
            for (final r in rows)
              DataRow(cells: [
                DataCell(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TooltipText(r.srNumber,
                          style: TextStyle(
                              color: context.colors.accentLightBlue,
                              fontWeight: FontWeight.w700)),
                      if (r.goodsName != '—')
                        Text(r.goodsName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: context.colors.textMuted, fontSize: 11)),
                    ],
                  ),
                ),
                DataCell(Text(money.format(r.destroyingDeposit))),
                DataCell(Text(
                    r.destructionExpense == 0
                        ? '—'
                        : money.format(r.destructionExpense),
                    style: TextStyle(
                        color: r.destructionExpense == 0
                            ? context.colors.textMuted
                            : context.colors.dangerRed,
                        fontWeight: FontWeight.w600))),
                DataCell(Text(
                    r.advertisingExpense == 0
                        ? '—'
                        : money.format(r.advertisingExpense),
                    style: TextStyle(
                        color: r.advertisingExpense == 0
                            ? context.colors.textMuted
                            : context.colors.warningAmber,
                        fontWeight: FontWeight.w600))),
                // The three costs added alongside destruction / advertising.
                // All five come out of the same destroying deposit.
                DataCell(Text(
                    r.labourExpense == 0 ? '—' : money.format(r.labourExpense),
                    style: TextStyle(
                        color: r.labourExpense == 0
                            ? context.colors.textMuted
                            : context.colors.accentLightBlue,
                        fontWeight: FontWeight.w600))),
                DataCell(Text(
                    r.transportExpense == 0
                        ? '—'
                        : money.format(r.transportExpense),
                    style: TextStyle(
                        color: r.transportExpense == 0
                            ? context.colors.textMuted
                            : context.colors.customsBlue,
                        fontWeight: FontWeight.w600))),
                DataCell(Text(
                    r.auctionExpense == 0
                        ? '—'
                        : money.format(r.auctionExpense),
                    style: TextStyle(
                        color: r.auctionExpense == 0
                            ? context.colors.textMuted
                            : context.colors.primaryGold,
                        fontWeight: FontWeight.w600))),
                DataCell(Text(
                    r.depositSpent == 0 ? '—' : money.format(r.depositSpent),
                    style: TextStyle(
                        color: r.depositSpent == 0
                            ? context.colors.textMuted
                            : context.colors.textPrimary,
                        fontWeight: FontWeight.w700))),
                DataCell(r.deficit > 0
                    ? Tooltip(
                        message:
                            'Costs exceed the deposit by LKR ${money.format(r.deficit)}',
                        child: Text('−${money.format(r.deficit)}',
                            style: TextStyle(
                                color: context.colors.dangerRed,
                                fontWeight: FontWeight.w800)),
                      )
                    : Text(money.format(r.refund),
                        style: TextStyle(
                            color: context.colors.successGreen,
                            fontWeight: FontWeight.w800))),
                DataCell(Center(
                  child: _StatusBadge(r: r),
                )),
                DataCell(Center(
                  child: IconButton(
                    tooltip: 'Record costs for this SR',
                    icon: Icon(Icons.edit_note_rounded,
                        size: 20, color: context.colors.successGreen),
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => RecordExpenseDialog(sr: r),
                    ),
                  ),
                )),
                DataCell(Center(
                  child: IconButton(
                    tooltip: 'View complete SR details',
                    icon: Icon(Icons.info_outline_rounded,
                        size: 18, color: context.colors.accentLightBlue),
                    onPressed: () {
                      final pkg = packages
                          .where((p) => p.srNumber.trim() == r.srNumber.trim())
                          .firstOrNull;
                      if (pkg != null) {
                        showDialog(
                          context: context,
                          builder: (_) => PackageDetailsDialog(
                            package: pkg,
                            storageRate: storageRate,
                            useLegacySummary: true,
                            yardLabel: yardName(
                                r.yard ?? yardOfSrNumber(pkg.srNumber)),
                            headerAccentColor: context.colors.successGreen,
                            srFinancials: r,
                          ),
                        );
                      } else {
                        showDialog(
                          context: context,
                          builder: (_) => _SrGoodsDialog(sr: r),
                        );
                      }
                    },
                  ),
                )),
              ]),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.03);
  }
}

/// Every goods item an SR covers, with what each one cost.
///
/// The table lists SRs because the destroying deposit is lodged once per SR —
/// this is where that row is opened up. The deposit and the refund are shown
/// once, at the SR level, because that is the only level they exist at; the
/// per-goods columns are the costs that were charged against them.
class _SrGoodsDialog extends StatelessWidget {
  final SrFinancials sr;
  const _SrGoodsDialog({required this.sr});

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0.00');
    final green = context.colors.successGreen;

    return StyledFormDialog(
      label: 'SR DETAILS',
      title: sr.srNumber,
      icon: Icons.inventory_2_rounded,
      headerAccentColor: green,
      width: 640,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          StyledFormSection(
            title: 'The SR',
            icon: Icons.folder_rounded,
            children: [
              _KeyValue(label: 'Packages', value: '${sr.packageCount}'),
              _KeyValue(label: 'Total Quantity', value: '${sr.quantity}'),
              _KeyValue(
                label: 'Destroying Deposit',
                value: 'LKR ${money.format(sr.destroyingDeposit)}',
                emphasise: true,
                color: green,
              ),
            ],
          ),
          const Gap(14),
          StyledFormSection(
            title: 'Goods under this SR',
            icon: Icons.list_alt_rounded,
            children: [
              // A header line, then one line per package. Costs only — the
              // deposit and the refund belong to the SR, not to any one item.
              Row(children: [
                Expanded(
                    flex: 4,
                    child: Text('Goods',
                        style: TextStyle(
                            color: context.colors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700))),
                Expanded(
                    child: Text('Qty',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            color: context.colors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700))),
                Expanded(
                    flex: 2,
                    child: Text('Destruction',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            color: context.colors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700))),
                Expanded(
                    flex: 2,
                    child: Text('Advertising',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            color: context.colors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700))),
              ]),
              Divider(color: context.colors.borderColor, height: 14),
              for (final g in sr.goods)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(
                      flex: 4,
                      child: Text(g.goodsName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: context.colors.textPrimary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600)),
                    ),
                    Expanded(
                      child: Text('${g.quantity}',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 12.5)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                          g.destructionExpense == 0
                              ? '\u2014'
                              : money.format(g.destructionExpense),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              color: g.destructionExpense == 0
                                  ? context.colors.textMuted
                                  : context.colors.dangerRed,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                          g.advertisingExpense == 0
                              ? '\u2014'
                              : money.format(g.advertisingExpense),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              color: g.advertisingExpense == 0
                                  ? context.colors.textMuted
                                  : context.colors.warningAmber,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
            ],
          ),
          const Gap(14),
          // The arithmetic that produced the row's Refund, at SR level.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: (sr.deficit > 0 ? context.colors.dangerRed : green)
                  .withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: (sr.deficit > 0 ? context.colors.dangerRed : green)
                      .withOpacity(0.3)),
            ),
            child: Column(children: [
              _KeyValue(
                  label: 'Deposit',
                  value: 'LKR ${money.format(sr.destroyingDeposit)}'),
              _KeyValue(
                  label: 'Less costs (all packages)',
                  value: '\u2212 LKR ${money.format(sr.depositSpent)}'),
              Divider(color: context.colors.borderColor, height: 18),
              _KeyValue(
                label: sr.deficit > 0 ? 'Shortfall' : 'Refund',
                value: sr.deficit > 0
                    ? '\u2212 LKR ${money.format(sr.deficit)}'
                    : 'LKR ${money.format(sr.refund)}',
                emphasise: true,
                color: sr.deficit > 0 ? context.colors.dangerRed : green,
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final SrFinancials r;
  const _StatusBadge({required this.r});

  @override
  Widget build(BuildContext context) {
    String label;
    Color color;

    if (r.depositSpent == 0) {
      label = 'Pending';
      color = context.colors.warningAmber;
    } else if (r.deficit > 0) {
      label = 'Shortfall';
      color = context.colors.dangerRed;
    } else {
      label = 'Refundable';
      color = context.colors.successGreen;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Records both costs for ONE SR, and previews the resulting refund
/// live so the officer sees the consequence before saving.
class RecordExpenseDialog extends ConsumerStatefulWidget {
  final SrFinancials sr;
  /// Opened from the Destroyed Goods table: hides Auction Expenses (it never
  /// applies to a destruction) and adjusts the copy to talk about destruction
  /// specifically instead of disposal in general.
  final bool forDestruction;
  const RecordExpenseDialog(
      {super.key, required this.sr, this.forDestruction = false});

  @override
  ConsumerState<RecordExpenseDialog> createState() =>
      _RecordExpenseDialogState();
}

class _RecordExpenseDialogState extends ConsumerState<RecordExpenseDialog> {
  /// One controller per recordable kind, keyed the same way the database is.
  /// Driving the form off `kRecordableExpenseKinds` means adding another cost
  /// needs no change here — only that map, and the icon table below.
  late final Map<String, TextEditingController> _fields;
  bool _saving = false;

  /// Kinds a destruction never incurs. The goods are handed straight to the
  /// destroying contractor, so nothing is advertised and nothing is auctioned
  /// -- what a destruction costs is the destruction itself plus getting the
  /// goods and the hands there.
  static const _notForDestruction = {'advertising_expense', 'auction_expense'};

  /// The kinds this dialog offers.
  Iterable<MapEntry<String, String>> get _kinds => widget.forDestruction
      ? kRecordableExpenseKinds.entries
          .where((e) => !_notForDestruction.contains(e.key))
      : kRecordableExpenseKinds.entries;

  /// What is already recorded under the kinds this dialog does NOT offer.
  ///
  /// The deposit pays for every cost booked against the SR, not just the ones
  /// on screen. Leaving these out of the arithmetic would show a refund larger
  /// than the depositor is actually owed whenever an earlier advertising or
  /// auction cost exists.
  double get _hiddenSpend => widget.forDestruction
      ? _notForDestruction.fold<double>(0, (a, k) => a + _existing(k))
      : 0;

  /// The figure already recorded for [kind] on this SR.
  double _existing(String kind) {
    switch (kind) {
      case 'destruction_expense':
        return widget.sr.destructionExpense;
      case 'advertising_expense':
        return widget.sr.advertisingExpense;
      case 'labour_expense':
        return widget.sr.labourExpense;
      case 'transport_expense':
        return widget.sr.transportExpense;
      case 'auction_expense':
        return widget.sr.auctionExpense;
      default:
        return 0;
    }
  }

  static const _icons = <String, IconData>{
    'destruction_expense': Icons.local_fire_department_rounded,
    'advertising_expense': Icons.campaign_rounded,
    'labour_expense': Icons.engineering_rounded,
    'transport_expense': Icons.local_shipping_rounded,
    'auction_expense': Icons.gavel_rounded,
  };

  Color _colourFor(BuildContext context, String kind) {
    switch (kind) {
      case 'destruction_expense':
        return context.colors.dangerRed;
      case 'advertising_expense':
        return context.colors.warningAmber;
      case 'labour_expense':
        return context.colors.accentLightBlue;
      case 'transport_expense':
        return context.colors.customsBlue;
      default:
        return context.colors.primaryGold;
    }
  }

  @override
  void initState() {
    super.initState();
    _fields = {
      for (final kind in _kinds.map((e) => e.key))
        kind: TextEditingController(
            text:
                _existing(kind) == 0 ? '' : _existing(kind).toStringAsFixed(2))
          ..addListener(_refresh),
    };
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  double _valueOf(String kind) =>
      double.tryParse(_fields[kind]?.text.trim() ?? '') ?? 0;

  double get _spent =>
      _fields.keys.fold<double>(0, (a, k) => a + _valueOf(k)) + _hiddenSpend;

  double get _refund {
    final left = widget.sr.destroyingDeposit - _spent;
    return left > 0 ? left : 0;
  }

  double get _deficit {
    final over = _spent - widget.sr.destroyingDeposit;
    return over > 0 ? over : 0;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final svc = ref.read(disposalServiceProvider);
      final itemId =
          widget.sr.goods.isNotEmpty ? widget.sr.goods.first.itemId : null;
      // Every kind is written, zeros included: clearing a field must record
      // the zero, not leave the old figure standing.
      for (final entry in _kinds) {
        await svc.addFinancialExpense(
          kind: entry.key,
          amount: _valueOf(entry.key),
          description: '${entry.value} recorded',
          srNumber: widget.sr.srNumber,
          packageItemId: itemId,
        );
      }
      ref.read(financialExpensesRefreshProvider.notifier).trigger();
      if (!mounted) return;
      Navigator.pop(context);
      context.showSuccess('Costs recorded for ${widget.sr.srNumber}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.showError('Could not record the costs: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0.00');
    final green = context.colors.successGreen;

    return StyledFormDialog(
      label: widget.forDestruction ? 'DESTRUCTION EXPENSES' : 'DISPOSAL EXPENSES',
      title: widget.sr.srNumber,
      icon: widget.forDestruction
          ? Icons.local_fire_department_rounded
          : Icons.receipt_long_rounded,
      headerAccentColor: green,
      width: 520,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        const Gap(8),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: green,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_rounded, size: 18),
          label: const Text('Save Costs',
              style: TextStyle(fontWeight: FontWeight.bold)),
          onPressed: _saving ? null : _save,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          StyledFormSection(
            title: 'SR Details',
            icon: Icons.folder_rounded,
            children: [
              _KeyValue(label: 'SR Number', value: widget.sr.srNumber),
              if (widget.sr.goodsName != '—')
                _KeyValue(label: 'Goods', value: widget.sr.goodsName),
              _KeyValue(
                label: 'Destroying Deposit',
                value: 'LKR ${money.format(widget.sr.destroyingDeposit)}',
                emphasise: true,
                color: green,
              ),
            ],
          ),
          const Gap(14),
          StyledFormSection(
            title: 'Costs Incurred',
            icon: Icons.payments_rounded,
            children: [
              // One field per recordable kind, driven off the shared map so
              // this form never drifts from what the database accepts.
              for (final entry in _kinds) ...[
                TextField(
                  controller: _fields[entry.key],
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: '${entry.value} (LKR)',
                    hintText: '0.00',
                    isDense: true,
                    prefixIcon: Icon(
                        _icons[entry.key] ?? Icons.payments_rounded,
                        color: _colourFor(context, entry.key)),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const Gap(12),
              ],
              const Gap(2),
              // ── Notice Box (Replaces Note Input Field) ──
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.colors.accentLightBlue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: context.colors.accentLightBlue.withOpacity(0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 18, color: context.colors.accentLightBlue),
                    const Gap(10),
                    Expanded(
                      child: Text(
                        widget.forDestruction
                            ? 'Notice: Costs entered here are deducted from the lodged Destroying Deposit. Remaining balance will be calculated as a refund.'
                            : 'Notice: Destruction and advertising costs entered here are deducted from the lodged Destroying Deposit. Remaining balance will be calculated as a refund.',
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Gap(14),
          // Live arithmetic refund calculation card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: (_deficit > 0 ? context.colors.dangerRed : green)
                  .withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: (_deficit > 0 ? context.colors.dangerRed : green)
                      .withOpacity(0.3)),
            ),
            child: Column(children: [
              _KeyValue(
                  label: 'Deposit',
                  value: 'LKR ${money.format(widget.sr.destroyingDeposit)}'),
              _KeyValue(
                  label: 'Less costs', value: '− LKR ${money.format(_spent)}'),
              Divider(color: context.colors.borderColor, height: 18),
              _KeyValue(
                label: _deficit > 0 ? 'Shortfall' : 'Refund',
                value: _deficit > 0
                    ? '− LKR ${money.format(_deficit)}'
                    : 'LKR ${money.format(_refund)}',
                emphasise: true,
                color: _deficit > 0 ? context.colors.dangerRed : green,
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasise;
  final Color? color;
  const _KeyValue(
      {required this.label,
      required this.value,
      this.emphasise = false,
      this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Text(label,
            style: TextStyle(color: context.colors.textMuted, fontSize: 12.5)),
        const Spacer(),
        Expanded(
          child: Text(value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color ?? context.colors.textPrimary,
                  fontSize: emphasise ? 14.5 : 13,
                  fontWeight: emphasise ? FontWeight.w800 : FontWeight.w600)),
        ),
      ]),
    );
  }
}
