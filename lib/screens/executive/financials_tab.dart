import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../widgets/empty_table_state.dart';
import '../../widgets/table_pager.dart';
import '../../widgets/styled_dropdown.dart';
import '../../widgets/date_range_picker_dialog.dart' as custom;
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../core/yards.dart';
import '../../models/models.dart';
import '../../widgets/error_view.dart';
import '../../widgets/tooltip_text.dart';
import 'executive_header.dart';

/// The page's filters. Both the headline cards and the per-goods table read
/// them, so narrowing to a yard or date range narrows EVERY figure on the page.
final _finSearchProvider = StateProvider<String>((ref) => '');
final _finYardProvider = StateProvider<String?>((ref) => null); // null = all
final _finDateFilterTypeProvider = StateProvider<String>(
    (ref) => 'all'); // 'all', 'range', 'day', 'month', 'year'
final _finDateRangeProvider = StateProvider<DateTimeRange?>((ref) => null);
final _finPageProvider = StateProvider<int>((ref) => 0);

final _money = NumberFormat('#,##0.00');


String _lkr(double v) => 'LKR ${_money.format(v)}';

/// Top Management Directorate · Financials.
///
/// INCOME is derived from records the system already holds — storage charges,
/// destroying deposits, sale proceeds and the taxes on them.
///
/// EXPENDITURE comes from Central Disposal, who record the destruction and
/// advertising costs GOODS BY GOODS as they incur them. A refund is never
/// entered: the destroying deposit is held against those costs, so whatever is
/// left of it goes back —
///
///     refund = destroying deposit - (destruction + advertising)
///
/// Because every figure is attributed to a goods item, the whole ledger can be
/// read item by item (see [_GoodsBreakdown]) as well as in total.
///
/// The sale-proceeds distribution is shown SEPARATELY from the net balance:
/// it does not add to or subtract from the balance, it says where the proceeds
/// go afterwards.
class FinancialsTab extends ConsumerWidget {
  const FinancialsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = AppTheme.executiveTeal;
    final rowsAsync = ref.watch(srFinancialsProvider);
    final canEdit = !isExecutiveViewOnly(ref.watch(currentProfileProvider));
    final q = ref.watch(_finSearchProvider).trim().toLowerCase();
    final yardFilter = ref.watch(_finYardProvider);
    final dateFilterType = ref.watch(_finDateFilterTypeProvider);
    final dateRange = ref.watch(_finDateRangeProvider);

    return rowsAsync.when(
      loading: () => Center(child: CircularProgressIndicator(color: accent)),
      error: (e, _) =>
          ErrorView(error: e, onRetry: () => ref.refresh(srFinancialsProvider)),
      data: (all) {
        // Filter FIRST, then total — so every card on the page reports the
        // same slice the table below it lists.
        var filtered = all.where((r) => !r.isEmpty);
        if (yardFilter != null) {
          filtered = filtered.where((r) => matchesYardFilter(
              yardFilter, r.yard ?? yardOfSrNumber(r.srNumber), r.srNumber));
        }
        if (dateRange != null && dateFilterType != 'all') {
          filtered = filtered.where((r) => _matchesDateRange(r, dateRange));
        }
        if (q.isNotEmpty) {
          filtered =
              filtered.where((r) => r.srNumber.toLowerCase().contains(q));
        }
        final rows = filtered.toList();
        final sum = summariseSrs(rows);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title + subtitle · search · yard · date filter — header controls
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Financials',
                          style: TextStyle(
                              color: context.colors.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w700)),
                      const Gap(2),
                      Text(
                          canEdit
                              ? 'Income, expenditure and the distribution of sale proceeds'
                              : 'Income, expenditure and the distribution of sale proceeds \u00b7 view only',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: context.colors.textMuted, fontSize: 13)),
                    ],
                  ),
                ),
                const Gap(12),
                ExecutiveSearchField(
                  hint: 'Search SR / goods\u2026',
                  width: 200,
                  onChanged: (v) {
                    ref.read(_finSearchProvider.notifier).state = v;
                    ref.read(_finPageProvider.notifier).state = 0;
                  },
                ),
                const Gap(8),
                SizedBox(
                  width: 170,
                  child: ExecutiveYardFilter(
                    value: yardFilter,
                    onChanged: (v) {
                      ref.read(_finYardProvider.notifier).state = v;
                      ref.read(_finPageProvider.notifier).state = 0;
                    },
                  ),
                ),
                const Gap(8),
                // ── Date Filter Dropdown (Identical style & height to Yard Filter) ──
                SizedBox(
                  width: (dateRange != null && dateFilterType != 'all')
                      ? 220
                      : 170,
                  child: ExecutiveDateFilter(
                    filterType: dateFilterType,
                    label: _getDateFilterLabel(dateFilterType, dateRange),
                    onChanged: (v) {
                      _handleDatePick(context, ref, v ?? 'all');
                    },
                  ),
                ),
                if (dateRange != null && dateFilterType != 'all') ...[
                  const Gap(4),
                  IconButton(
                    icon: Icon(Icons.clear_rounded,
                        size: 18, color: context.colors.dangerRed),
                    tooltip: 'Clear date filter',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      ref.read(_finDateFilterTypeProvider.notifier).state =
                          'all';
                      ref.read(_finDateRangeProvider.notifier).state = null;
                      ref.read(_finPageProvider.notifier).state = 0;
                    },
                  ),
                ],
              ]).animate().fadeIn(duration: 300.ms),
              const Gap(12),

              // ── The three headline figures ──────────────────────────────
              Row(children: [
                Expanded(
                  child: _HeadlineCard(
                    label: 'Total Income',
                    value: sum.totalIncome,
                    icon: Icons.trending_up_rounded,
                    colour: context.colors.successGreen,
                  ),
                ),
                const Gap(14),
                Expanded(
                  child: _HeadlineCard(
                    label: 'Total Expenditure',
                    value: sum.totalExpenditure,
                    icon: Icons.trending_down_rounded,
                    colour: context.colors.dangerRed,
                  ),
                ),
                const Gap(14),
                Expanded(
                  child: _HeadlineCard(
                    label: 'Net Balance',
                    value: sum.netBalance,
                    icon: Icons.account_balance_rounded,
                    colour: sum.netBalance >= 0
                        ? context.colors.primaryGold
                        : context.colors.dangerRed,
                  ),
                ),
              ]).animate().fadeIn(duration: 350.ms).slideY(begin: 0.06),
              const Gap(12),

              // ── Income vs Expenditure, side by side ─────────────────────
              LayoutBuilder(builder: (context, c) {
                final stacked = c.maxWidth < 900;
                final income = _LedgerCard(
                  title: 'Income',
                  icon: Icons.savings_rounded,
                  colour: context.colors.successGreen,
                  total: sum.totalIncome,
                  lines: [
                    ('SR Charges', sum.srCharges),
                    ('Destroying Deposits', sum.destroyingDeposits),
                    ('Sale Proceeds', sum.saleProceeds),
                    ('Taxes', sum.taxes),
                  ],
                );
                final expenditure = _LedgerCard(
                  title: 'Expenditure',
                  icon: Icons.payments_rounded,
                  colour: context.colors.dangerRed,
                  total: sum.totalExpenditure,
                  lines: [
                    ('Destruction Expenses', sum.destructionExpenses),
                    ('Advertising Expenses', sum.advertisingExpenses),
                    ('Labour Costs', sum.labourExpenses),
                    ('Transport Costs', sum.transportExpenses),
                    ('Auction Expenses', sum.auctionExpenses),
                    ('Refunds (unspent deposits)', sum.refunds),
                  ],
                );
                if (stacked) {
                  return Column(children: [
                    income,
                    const Gap(10),
                    expenditure,
                  ]);
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: income),
                    const Gap(12),
                    Expanded(child: expenditure),
                  ],
                );
              }).animate().fadeIn(duration: 400.ms).slideY(begin: 0.06),
              const Gap(12),

              _ProceedsSplitCard(split: sum.split)
                  .animate()
                  .fadeIn(duration: 450.ms)
                  .slideY(begin: 0.06),
              const Gap(12),

              _GoodsBreakdown(rows: rows)
                  .animate()
                  .fadeIn(duration: 500.ms)
                  .slideY(begin: 0.06),
            ],
          ),
        );
      },
    );
  }
}

/// One of the three big numbers across the top.
class _HeadlineCard extends StatelessWidget {
  final String label;
  final double value;
  final IconData icon;
  final Color colour;

  const _HeadlineCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.colour,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colour.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colour.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: colour),
            const Gap(6),
            Text(label,
                style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ]),
          const Gap(4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(_lkr(value),
                style: TextStyle(
                    color: colour, fontSize: 22, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

/// The Income / Expenditure breakdown, one line per source.
class _LedgerCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color colour;
  final double total;
  final List<(String, double)> lines;

  const _LedgerCard({
    required this.title,
    required this.icon,
    required this.colour,
    required this.total,
    required this.lines,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: colour),
            const Gap(6),
            Text(title,
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700)),
          ]),
          const Gap(8),
          for (final (label, amount) in lines) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                          color: context.colors.textSecondary, fontSize: 12.5)),
                ),
                Text(_lkr(amount),
                    style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ],
          Divider(color: context.colors.borderColor, height: 12),
          Row(children: [
            Expanded(
              child: Text('Total',
                  style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
            ),
            Text(_lkr(total),
                style: TextStyle(
                    color: colour,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800)),
          ]),
        ],
      ),
    );
  }
}

/// Where the sale proceeds go. Shown apart from the net balance because it is
/// a distribution of money already counted as income, not a further movement.
class _ProceedsSplitCard extends StatelessWidget {
  final SaleProceedsSplit split;
  const _ProceedsSplitCard({required this.split});

  @override
  Widget build(BuildContext context) {
    final gold = context.colors.primaryGold;
    final blue = context.colors.accentLightBlue;
    final green = context.colors.successGreen;
    final purple = AppTheme.appealPurple;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.call_split_rounded, size: 16, color: gold),
            const Gap(6),
            Text('Distribution of Sale Proceeds',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700)),
            const Gap(8),
            Expanded(
              child: Text('of ${_lkr(split.proceeds)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(color: context.colors.textMuted, fontSize: 12)),
            ),
          ]),
          const Gap(8),

          // First split: 50 / 50, with Treasury sub-funds nested directly inside the Treasury column.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _SplitTile(
                  label: 'Reward Fund',
                  share: '50% of proceeds',
                  value: split.rewardFund,
                  colour: green,
                ),
              ),
              const Gap(10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: blue.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: blue.withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SplitTile(
                        label: 'Deputy Secretary of the Treasury',
                        share: '50% of proceeds',
                        value: split.deputySecretaryTreasury,
                        colour: blue,
                      ),
                      const Gap(6),
                      Row(children: [
                        Icon(Icons.subdirectory_arrow_right_rounded,
                            size: 14, color: context.colors.textMuted),
                        const Gap(4),
                        Text('Treasury half splits into:',
                            style: TextStyle(
                                color: context.colors.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ]),
                      const Gap(4),
                      Row(children: [
                        Expanded(
                          child: _SplitTile(
                            label: 'Consolidated Fund',
                            share: '60% of Treasury · 30% overall',
                            value: split.consolidatedFund,
                            colour: gold,
                          ),
                        ),
                        const Gap(6),
                        Expanded(
                          child: _SplitTile(
                            label: 'Comp Fund',
                            share: '40% of Treasury · 20% overall',
                            value: split.compFund,
                            colour: purple,
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SplitTile extends StatelessWidget {
  final String label;
  final String share;
  final double value;
  final Color colour;

  const _SplitTile({
    required this.label,
    required this.share,
    required this.value,
    required this.colour,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colour.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700)),
          const Gap(2),
          Text(share,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  TextStyle(color: context.colors.textMuted, fontSize: 10.5)),
          const Gap(4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(_lkr(value),
                style: TextStyle(
                    color: colour, fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

/// The ledger read GOODS BY GOODS.
///
/// Costs are incurred item by item, so this is the shape the figures are
/// actually kept in — the headline cards above are simply the sum of these
/// rows. Central Disposal enters the destruction and advertising columns; the
/// refund column is derived from what is left of each item's deposit.
///
/// Takes the rows already filtered by the page header, so the table and the
/// cards above it always describe the same slice.
///
/// Laid out like every other table in the portal: the heading sits ABOVE the
/// card, and the card holds nothing but the table.
class _GoodsBreakdown extends ConsumerWidget {
  final List<SrFinancials> rows;
  const _GoodsBreakdown({required this.rows});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(_finPageProvider);

    // A filter can leave the pager past the end of the list.
    final maxPage = rows.isEmpty ? 0 : (rows.length - 1) ~/ kClientPageSize;
    final safePage = page.clamp(0, maxPage);
    final pageRows =
        rows.skip(safePage * kClientPageSize).take(kClientPageSize).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Heading above the card, not inside it.
        Row(children: [
          Icon(Icons.inventory_2_rounded,
              size: 18, color: AppTheme.executiveTeal),
          const Gap(8),
          Text('Per SR',
              style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          const Gap(10),
          Expanded(
            child: Text(
                'Every figure above, SR by SR \u00b7 costs recorded by Central Disposal',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(color: context.colors.textMuted, fontSize: 12)),
          ),
        ]),
        const Gap(12),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: context.colors.cardDark,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.colors.borderColor),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              // The page scrolls vertically, so the table is given the exact
              // height its rows need. The +56 covers the pinned heading row.
              height: pageRows.isEmpty ? 220.0 : pageRows.length * 48.0 + 56,
              child: _GoodsBreakdownTable(rows: pageRows),
            ),
          ),
        ),
        TablePager(
          total: rows.length,
          page: safePage,
          onPageChanged: (p) => ref.read(_finPageProvider.notifier).state = p,
        ),
      ],
    );
  }
}

/// Every figure on the page, one row per SR.
///
/// The columns follow the cards above in the same order — the four income
/// lines, the three expenditure lines, the net, then the proceeds split — so a
/// reader can trace any headline figure down to the SR that produced it.
class _GoodsBreakdownTable extends ConsumerWidget {
  final List<SrFinancials> rows;
  const _GoodsBreakdownTable({required this.rows});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final green = context.colors.successGreen;
    final red = context.colors.dangerRed;
    final gold = context.colors.primaryGold;

    final taxesAsync = ref.watch(disposalTaxesProvider);
    final configuredTaxNames = taxesAsync.value
            ?.where((t) => t.isActive)
            .map((t) => t.name)
            .toList() ??
        const ['VAT', 'PAL'];
    final taxNames = <String>[...configuredTaxNames];
    for (final r in rows) {
      final tMap = r.taxesByName;
      for (final k in tMap.keys) {
        if (!taxNames.contains(k)) taxNames.add(k);
      }
    }

    return DataTable2(
      horizontalMargin: 8,
      fixedTopRows: 1,
      columnSpacing: 4,
      headingRowColor: WidgetStateProperty.all(context.colors.surfaceDark),
      empty: const EmptyTableState(
          icon: Icons.inventory_2_outlined,
          message: 'Nothing recorded against these SRs yet',
          subtitle:
              'Central Disposal records the destruction and advertising costs.'),
      columns: [
        DataColumn2(
            label: Text('SR Number',
                style: TextStyle(
                    color: gold, fontWeight: FontWeight.w700, fontSize: 13)),
            size: ColumnSize.M),

        // ── Income ──────────────────────────────────────────────
        _money2('Charges', gold),
        _money2('Deposit', gold),
        _money2('Proceeds', gold),
        for (final tName in taxNames) _money2(tName, gold),
        _money2('Tax', gold),
        _money2('Income', gold),

        // ── Expenditure ─────────────────────────────────────────
        _money2('Destroy', gold),
        _money2('Advert.', gold),
        _money2('Labour', gold),
        _money2('Transport', gold),
        _money2('Auction', gold),
        _money2('Refund', gold),
        _money2('Expend.', gold),

        // ── Balance ─────────────────────────────────────────────
        _money2('Net', gold),

        // ── Distribution of this SR's sale proceeds ───────────
        _money2('Reward', gold),
        _money2('Treasury', gold),
        _money2('Consol.', gold),
        _money2('Comp', gold),
      ],
      rows: [
        for (final r in rows)
          DataRow(cells: [
            DataCell(Tooltip(
              message: '${r.srNumber} \u00b7 ${yardName(r.yard)}',
              waitDuration: const Duration(milliseconds: 300),
              child: Text(r.srNumber,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppTheme.executiveTeal,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
            )),

            // ── Income ──────────────────────────────────────────
            _cell(context, r.srCharges),
            _cell(context, r.destroyingDeposit),
            _cell(context, r.saleProceeds),
            for (final tName in taxNames)
              _cell(context, r.taxesByName[tName] ?? 0),
            _cell(context, r.taxes),
            _cell(context, r.totalIncome, colour: green, bold: true),

            // ── Expenditure ─────────────────────────────────────
            _cell(context, r.destructionExpense),
            _cell(context, r.advertisingExpense),
            _cell(context, r.labourExpense),
            _cell(context, r.transportExpense),
            _cell(context, r.auctionExpense),
            DataCell(r.deficit > 0
                ? Tooltip(
                    message: 'Costs exceed the deposit by ${_lkr(r.deficit)}',
                    child: Text('\u2212${_money.format(r.deficit)}',
                        style: TextStyle(
                            color: red,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
                  )
                : Text(_dash(r.refund),
                    style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600))),
            _cell(context, r.totalExpenditure, colour: red, bold: true),

            // ── Balance ─────────────────────────────────────────
            DataCell(Text(_money.format(r.netBalance),
                style: TextStyle(
                    color: r.netBalance >= 0 ? gold : red,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800))),

            // ── Distribution of this SR\'s sale proceeds ───────
            _cell(context, r.split.rewardFund),
            _cell(context, r.split.deputySecretaryTreasury),
            _cell(context, r.split.consolidatedFund),
            _cell(context, r.split.compFund),
          ]),
      ],
    );
  }

  /// A right-aligned money column with standard header typography.
  static DataColumn2 _money2(String label, Color colour,
          {ColumnSize size = ColumnSize.S}) =>
      DataColumn2(
        label: Text(label,
            style: TextStyle(
                color: colour, fontWeight: FontWeight.w700, fontSize: 13)),
        size: size,
        numeric: true,
      );

  /// A money cell. Zero reads as an em dash so a populated figure stands out.
  static DataCell _cell(BuildContext context, double v,
      {Color? colour, bool bold = false}) {
    final isZero = v == 0;
    final text = Text(_dash(v),
        style: TextStyle(
            fontSize: 12.5,
            color: isZero
                ? context.colors.textMuted
                : (colour ?? context.colors.textPrimary),
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600));
    return DataCell(isZero
        ? text
        : Tooltip(
            message: 'LKR ${_money.format(v)}',
            waitDuration: const Duration(milliseconds: 300),
            child: text));
  }

  static String _dash(double v) => v == 0 ? '\u2014' : _money.format(v);
}

bool _matchesDateRange(SrFinancials r, DateTimeRange range) {
  final d = r.date;
  if (d != null) {
    return !d.isBefore(range.start) && !d.isAfter(range.end);
  }
  final yearMatch = RegExp(r'\b(20\d{2})\b').firstMatch(r.srNumber);
  if (yearMatch != null) {
    final srYear = int.tryParse(yearMatch.group(1)!);
    if (srYear != null) {
      return srYear >= range.start.year && srYear <= range.end.year;
    }
  }
  return true;
}

String _getDateFilterLabel(String type, DateTimeRange? range) {
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

Future<void> _handleDatePick(
    BuildContext context, WidgetRef ref, String filterType) async {
  final currentRange = ref.read(_finDateRangeProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  ref.read(_finDateFilterTypeProvider.notifier).state = filterType;

  if (filterType == 'all') {
    ref.read(_finDateRangeProvider.notifier).state = null;
    ref.read(_finPageProvider.notifier).state = 0;
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
            primary: AppTheme.executiveTeal,
            onPrimary: Colors.white,
            surface: context.colors.cardDark,
            onSurface: context.colors.textPrimary,
          ),
          dialogBackgroundColor: context.colors.cardDark,
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      ref.read(_finDateRangeProvider.notifier).state = DateTimeRange(
        start: DateTime(picked.year, picked.month, picked.day, 0, 0, 0),
        end: DateTime(picked.year, picked.month, picked.day, 23, 59, 59),
      );
      ref.read(_finPageProvider.notifier).state = 0;
    }
  } else if (filterType == 'month') {
    final initialY = currentRange?.start.year ?? now.year;
    final initialM = currentRange?.start.month ?? now.month;
    final picked = await _showMonthPickerDialog(context, initialY, initialM);
    if (picked != null) {
      final lastDay = DateTime(picked.year, picked.month + 1, 0).day;
      ref.read(_finDateRangeProvider.notifier).state = DateTimeRange(
        start: DateTime(picked.year, picked.month, 1, 0, 0, 0),
        end: DateTime(picked.year, picked.month, lastDay, 23, 59, 59),
      );
      ref.read(_finPageProvider.notifier).state = 0;
    }
  } else if (filterType == 'year') {
    final initialY = currentRange?.start.year ?? now.year;
    final picked = await _showYearPickerDialog(context, initialY);
    if (picked != null) {
      ref.read(_finDateRangeProvider.notifier).state = DateTimeRange(
        start: DateTime(picked, 1, 1, 0, 0, 0),
        end: DateTime(picked, 12, 31, 23, 59, 59),
      );
      ref.read(_finPageProvider.notifier).state = 0;
    }
  } else if (filterType == 'range') {
    final picked = await showDialog<dynamic>(
      context: context,
      builder: (ctx) =>
          custom.DateRangePickerDialog(initialRange: currentRange),
    );
    if (picked is DateTimeRange) {
      ref.read(_finDateRangeProvider.notifier).state = DateTimeRange(
        start: DateTime(
            picked.start.year, picked.start.month, picked.start.day, 0, 0, 0),
        end: DateTime(
            picked.end.year, picked.end.month, picked.end.day, 23, 59, 59),
      );
      ref.read(_finPageProvider.notifier).state = 0;
    } else if (picked == false) {
      ref.read(_finDateFilterTypeProvider.notifier).state = 'all';
      ref.read(_finDateRangeProvider.notifier).state = null;
      ref.read(_finPageProvider.notifier).state = 0;
    }
  }
}

Future<({int year, int month})?> _showMonthPickerDialog(
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
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: TextStyle(color: context.colors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.executiveTeal,
                foregroundColor: Colors.white,
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

Future<int?> _showYearPickerDialog(
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
              backgroundColor: AppTheme.executiveTeal,
              foregroundColor: Colors.white,
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
