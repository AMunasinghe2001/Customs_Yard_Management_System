import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../widgets/table_pager.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../models/models.dart';
import '../../widgets/error_view.dart';
import '../../widgets/tooltip_text.dart';
import 'executive_header.dart';

/// The page's filters. Both the headline cards and the per-goods table read
/// them, so narrowing to a yard narrows EVERY figure on the page, not just the
/// table at the bottom — a yard's totals have to add up on their own.
final _finSearchProvider = StateProvider<String>((ref) => '');
final _finYardProvider = StateProvider<String?>((ref) => null); // null = all
final _finPageProvider = StateProvider<int>((ref) => 0);

final _money = NumberFormat('#,##0.00');
String _lkr(double v) => 'LKR ${_money.format(v)}';

/// High Panel · Financials.
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
    final rowsAsync = ref.watch(goodsFinancialsProvider);
    // The DC observes the High Panel but records nothing.
    final canEdit = !isExecutiveViewOnly(ref.watch(currentProfileProvider));
    final q = ref.watch(_finSearchProvider).trim().toLowerCase();
    final yardFilter = ref.watch(_finYardProvider);

    return rowsAsync.when(
      loading: () => Center(child: CircularProgressIndicator(color: accent)),
      error: (e, _) => ErrorView(
          error: e, onRetry: () => ref.refresh(goodsFinancialsProvider)),
      data: (all) {
        // Filter FIRST, then total — so every card on the page reports the
        // same slice the table below it lists.
        var filtered = all.where((r) => !r.isEmpty);
        if (yardFilter != null) {
          filtered = filtered.where((r) => r.yard == yardFilter);
        }
        if (q.isNotEmpty) {
          filtered = filtered.where((r) =>
              r.srNumber.toLowerCase().contains(q) ||
              r.goodsName.toLowerCase().contains(q));
        }
        final rows = filtered.toList();
        final sum = summariseGoods(rows);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title + subtitle · search · yard — the order every
              // other High Panel tab uses.
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
                const Gap(16),
                ExecutiveSearchField(
                  hint: 'Search SR / goods\u2026',
                  onChanged: (v) {
                    ref.read(_finSearchProvider.notifier).state = v;
                    ref.read(_finPageProvider.notifier).state = 0;
                  },
                ),
                const Gap(12),
                // Width only — NO fixed height; the dropdown takes its
                // height from kExecutiveFilterPadding, like the search field.
                SizedBox(
                  width: 220,
                  child: ExecutiveYardFilter(
                    value: yardFilter,
                    onChanged: (v) {
                      ref.read(_finYardProvider.notifier).state = v;
                      ref.read(_finPageProvider.notifier).state = 0;
                    },
                  ),
                ),
              ]).animate().fadeIn(duration: 300.ms),
              const Gap(20),

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
              const Gap(20),

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
                    ('Refunds (unspent deposits)', sum.refunds),
                  ],
                );
                if (stacked) {
                  return Column(children: [
                    income,
                    const Gap(14),
                    expenditure,
                  ]);
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: income),
                    const Gap(14),
                    Expanded(child: expenditure),
                  ],
                );
              }).animate().fadeIn(duration: 400.ms).slideY(begin: 0.06),
              const Gap(20),

              _ProceedsSplitCard(split: sum.split)
                  .animate()
                  .fadeIn(duration: 450.ms)
                  .slideY(begin: 0.06),
              const Gap(20),

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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colour.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colour.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 18, color: colour),
            const Gap(8),
            Text(label,
                style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ]),
          const Gap(10),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 18, color: colour),
            const Gap(8),
            Text(title,
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ]),
          const Gap(14),
          for (final (label, amount) in lines) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                          color: context.colors.textSecondary, fontSize: 13)),
                ),
                Text(_lkr(amount),
                    style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ],
          Divider(color: context.colors.borderColor, height: 18),
          Row(children: [
            Expanded(
              child: Text('Total',
                  style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800)),
            ),
            Text(_lkr(total),
                style: TextStyle(
                    color: colour, fontSize: 15, fontWeight: FontWeight.w800)),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.call_split_rounded, size: 18, color: gold),
            const Gap(8),
            Text('Distribution of Sale Proceeds',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            const Gap(10),
            Expanded(
              child: Text('of ${_lkr(split.proceeds)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: context.colors.textMuted, fontSize: 12.5)),
            ),
          ]),
          const Gap(16),

          // First split: 50 / 50.
          Row(children: [
            Expanded(
              child: _SplitTile(
                label: 'Reward Fund',
                share: '50% of proceeds',
                value: split.rewardFund,
                colour: green,
              ),
            ),
            const Gap(12),
            Expanded(
              child: _SplitTile(
                label: 'Deputy Secretary of the Treasury',
                share: '50% of proceeds',
                value: split.deputySecretaryTreasury,
                colour: blue,
              ),
            ),
          ]),

          const Gap(6),
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 8, bottom: 8),
            child: Row(children: [
              Icon(Icons.subdirectory_arrow_right_rounded,
                  size: 16, color: context.colors.textMuted),
              const Gap(6),
              Text('The Treasury\'s half splits again',
                  style:
                      TextStyle(color: context.colors.textMuted, fontSize: 12)),
            ]),
          ),

          // Second split: 60 / 40 OF the Treasury half.
          Row(children: [
            const Gap(24),
            Expanded(
              child: _SplitTile(
                label: 'Consolidated Fund',
                share: '60% of the Treasury half · 30% overall',
                value: split.consolidatedFund,
                colour: gold,
              ),
            ),
            const Gap(12),
            Expanded(
              child: _SplitTile(
                label: 'Comp Fund',
                share: '40% of the Treasury half · 20% overall',
                value: split.compFund,
                colour: purple,
              ),
            ),
          ]),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colour.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colour.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          const Gap(3),
          Text(share,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.colors.textMuted, fontSize: 11)),
          const Gap(8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(_lkr(value),
                style: TextStyle(
                    color: colour, fontSize: 17, fontWeight: FontWeight.w800)),
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
class _GoodsBreakdown extends ConsumerWidget {
  final List<GoodsFinancials> rows;
  const _GoodsBreakdown({required this.rows});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(_finPageProvider);

    // A filter can leave the pager past the end of the list.
    final maxPage = rows.isEmpty ? 0 : (rows.length - 1) ~/ kClientPageSize;
    final safePage = page > maxPage ? maxPage : page;
    final pageRows =
        rows.skip(safePage * kClientPageSize).take(kClientPageSize).toList();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.inventory_2_rounded,
                size: 18, color: AppTheme.executiveTeal),
            const Gap(8),
            Text('Per Goods',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            const Gap(10),
            Expanded(
              child: Text(
                  'Every figure above, item by item \u00b7 costs recorded by Central Disposal',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(color: context.colors.textMuted, fontSize: 12)),
            ),
          ]),
          const Gap(14),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text('Nothing recorded against these goods yet.',
                    style: TextStyle(
                        color: context.colors.textMuted, fontSize: 13)),
              ),
            )
          else ...[
            SizedBox(
              // Tall enough to read, short enough to leave the cards above
              // visible; the table scrolls inside itself.
              height: pageRows.length * 48.0 + 56,
              child: _GoodsBreakdownTable(rows: pageRows),
            ),
            TablePager(
              total: rows.length,
              page: safePage,
              onPageChanged: (p) =>
                  ref.read(_finPageProvider.notifier).state = p,
            ),
          ],
        ],
      ),
    );
  }
}

class _GoodsBreakdownTable extends StatelessWidget {
  final List<GoodsFinancials> rows;
  const _GoodsBreakdownTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    return DataTable2(
      // Fits without sideways scrolling.
      columnSpacing: 10,
      horizontalMargin: 12,
      headingRowColor: WidgetStateProperty.all(context.colors.surfaceDark),
      columns: const [
        DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
        DataColumn2(label: Text('Goods Name'), size: ColumnSize.L),
        DataColumn2(label: Text('Income'), size: ColumnSize.S, numeric: true),
        DataColumn2(label: Text('Deposit'), size: ColumnSize.S, numeric: true),
        DataColumn2(
            label: Text('Destruction'), size: ColumnSize.S, numeric: true),
        DataColumn2(
            label: Text('Advertising'), size: ColumnSize.S, numeric: true),
        DataColumn2(label: Text('Refund'), size: ColumnSize.S, numeric: true),
        DataColumn2(label: Text('Net'), size: ColumnSize.S, numeric: true),
      ],
      rows: [
        for (final r in rows)
          DataRow(cells: [
            DataCell(TooltipText(r.srNumber,
                style: TextStyle(
                    color: context.colors.accentLightBlue,
                    fontWeight: FontWeight.w700))),
            DataCell(TooltipText(r.goodsName)),
            DataCell(Text(_money.format(r.totalIncome),
                style: TextStyle(
                    color: context.colors.successGreen,
                    fontWeight: FontWeight.w600))),
            DataCell(Text(_dash(r.destroyingDeposit),
                style: TextStyle(color: context.colors.textPrimary))),
            DataCell(Text(_dash(r.destructionExpense),
                style: TextStyle(
                    color: r.destructionExpense == 0
                        ? context.colors.textMuted
                        : context.colors.dangerRed))),
            DataCell(Text(_dash(r.advertisingExpense),
                style: TextStyle(
                    color: r.advertisingExpense == 0
                        ? context.colors.textMuted
                        : context.colors.warningAmber))),
            // Derived, never entered: the unspent part of this item's deposit.
            // A shortfall shows as a negative instead.
            DataCell(r.deficit > 0
                ? Tooltip(
                    message: 'Costs exceed the deposit by ${_lkr(r.deficit)}',
                    child: Text('\u2212${_money.format(r.deficit)}',
                        style: TextStyle(
                            color: context.colors.dangerRed,
                            fontWeight: FontWeight.w700)),
                  )
                : Text(_dash(r.refund),
                    style: TextStyle(
                        color: r.refund == 0
                            ? context.colors.textMuted
                            : context.colors.successGreen,
                        fontWeight: FontWeight.w700))),
            DataCell(Text(_money.format(r.netBalance),
                style: TextStyle(
                    color: r.netBalance >= 0
                        ? context.colors.primaryGold
                        : context.colors.dangerRed,
                    fontWeight: FontWeight.w800))),
          ]),
      ],
    );
  }

  static String _dash(double v) => v == 0 ? '\u2014' : _money.format(v);
}
