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
import 'disposal_shared.dart';

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
    final rowsAsync = ref.watch(goodsFinancialsProvider);
    final page = ref.watch(_expensePageProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title · search · yard — the order every other tab uses.
          Row(children: [
            Text('Disposal Expenses',
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
              onChanged: (v) => ref
                  .read(disposalYardFilterProvider(_tabKey).notifier)
                  .state = v,
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
                  onRetry: () => ref.refresh(goodsFinancialsProvider)),
              data: (all) {
                final q =
                    ref.watch(disposalSearchProvider(_tabKey)).toLowerCase();
                final yf = ref.watch(disposalYardFilterProvider(_tabKey));

                // Only goods that carry a deposit or already have a cost are
                // worth listing — the rest have nothing to account for.
                var rows = all.where(
                    (r) => r.destroyingDeposit > 0 || r.depositSpent > 0);
                if (yf != null) {
                  // Fall back to the SR prefix when a row carries no yard of
                  // its own, so the filter cannot silently hide goods that
                  // plainly belong to the selected yard.
                  rows = rows.where(
                      (r) => (r.yard ?? yardOfSrNumber(r.srNumber)) == yf);
                }
                if (q.isNotEmpty) {
                  rows = rows.where((r) =>
                      r.srNumber.toLowerCase().contains(q) ||
                      r.goodsName.toLowerCase().contains(q));
                }
                final list = rows.toList();

                // A filter can leave the pager past the end.
                final maxPage =
                    list.isEmpty ? 0 : (list.length - 1) ~/ kClientPageSize;
                final safePage = page > maxPage ? maxPage : page;
                final pageRows = list
                    .skip(safePage * kClientPageSize)
                    .take(kClientPageSize)
                    .toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Counts the SAME rows the table shows.
                    Row(children: [
                      StatChip(
                          label: 'Goods with a deposit',
                          value: '${list.length}',
                          color: amber),
                      const Gap(12),
                      Expanded(child: _TotalsStrip(rows: list)),
                    ]),
                    const Gap(14),
                    Expanded(child: _ExpensesTable(rows: pageRows)),
                    TablePager(
                      total: list.length,
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

/// Page index for this tab's client-side pager.
final _expensePageProvider = StateProvider<int>((ref) => 0);

/// Running totals for whatever the table is currently showing.
class _TotalsStrip extends StatelessWidget {
  final List<GoodsFinancials> rows;
  const _TotalsStrip({required this.rows});

  @override
  Widget build(BuildContext context) {
    double deposit = 0, destruction = 0, advertising = 0, refund = 0;
    for (final r in rows) {
      deposit += r.destroyingDeposit;
      destruction += r.destructionExpense;
      advertising += r.advertisingExpense;
      refund += r.refund;
    }

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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: color),
        const Gap(10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style:
                    TextStyle(color: context.colors.textMuted, fontSize: 11.5)),
            Text('LKR ${NumberFormat('#,##0.00').format(value)}',
                style: TextStyle(
                    color: color, fontSize: 15, fontWeight: FontWeight.w800)),
          ],
        ),
      ]),
    );
  }
}

class _ExpensesTable extends ConsumerWidget {
  final List<GoodsFinancials> rows;
  const _ExpensesTable({required this.rows});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = NumberFormat('#,##0.00');

    // Same shell as every other table in the portal: a 14-radius bordered card
    // clipped to its own corners, with the heading row pinned.
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
          // Everything fits without sideways scrolling.
          columnSpacing: 12,
          horizontalMargin: 16,
          fixedTopRows: 1,
          headingRowColor: WidgetStateProperty.all(context.colors.surfaceDark),
          empty: const EmptyTableState(
              icon: Icons.receipt_long_outlined,
              message: 'No goods with a destroying deposit',
              subtitle:
                  'Goods carrying a deposit appear here once they are registered.'),
          columns: const [
            DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
            DataColumn2(label: Text('Goods Name'), size: ColumnSize.L),
            DataColumn2(
                label: Text('Deposit'), size: ColumnSize.S, numeric: true),
            DataColumn2(
                label: Text('Destruction'), size: ColumnSize.S, numeric: true),
            DataColumn2(
                label: Text('Advertising'), size: ColumnSize.S, numeric: true),
            DataColumn2(
                label: Text('Refund'), size: ColumnSize.S, numeric: true),
            DataColumn2(
                label: Center(child: Text('Record')),
                size: ColumnSize.S,
                fixedWidth: 110),
          ],
          rows: [
            for (final r in rows)
              DataRow(cells: [
                DataCell(TooltipText(r.srNumber,
                    style: TextStyle(
                        color: context.colors.accentLightBlue,
                        fontWeight: FontWeight.w700))),
                DataCell(TooltipText(r.goodsName)),
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
                // The whole point of the row: what goes back once the costs are
                // taken out of the deposit. A deficit is flagged in red instead.
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
                  child: IconButton(
                    tooltip: 'Record costs for these goods',
                    icon: Icon(Icons.edit_note_rounded,
                        size: 20, color: context.colors.successGreen),
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => _RecordExpenseDialog(goods: r),
                    ),
                  ),
                )),
              ]),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.03);
  }
}

/// Records both costs for ONE goods item, and previews the resulting refund
/// live so the officer sees the consequence before saving.
class _RecordExpenseDialog extends ConsumerStatefulWidget {
  final GoodsFinancials goods;
  const _RecordExpenseDialog({required this.goods});

  @override
  ConsumerState<_RecordExpenseDialog> createState() =>
      _RecordExpenseDialogState();
}

class _RecordExpenseDialogState extends ConsumerState<_RecordExpenseDialog> {
  late final TextEditingController _destruction;
  late final TextEditingController _advertising;
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Pre-filled with what is already recorded: saving REPLACES the figure
    // rather than adding to it, so the field must show the current value.
    _destruction = TextEditingController(
        text: widget.goods.destructionExpense == 0
            ? ''
            : widget.goods.destructionExpense.toStringAsFixed(2));
    _advertising = TextEditingController(
        text: widget.goods.advertisingExpense == 0
            ? ''
            : widget.goods.advertisingExpense.toStringAsFixed(2));
    _destruction.addListener(_refresh);
    _advertising.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _destruction.dispose();
    _advertising.dispose();
    _note.dispose();
    super.dispose();
  }

  double get _destructionValue =>
      double.tryParse(_destruction.text.trim()) ?? 0;
  double get _advertisingValue =>
      double.tryParse(_advertising.text.trim()) ?? 0;
  double get _spent => _destructionValue + _advertisingValue;
  double get _refund {
    final left = widget.goods.destroyingDeposit - _spent;
    return left > 0 ? left : 0;
  }

  double get _deficit {
    final over = _spent - widget.goods.destroyingDeposit;
    return over > 0 ? over : 0;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final svc = ref.read(disposalServiceProvider);
      final note = _note.text.trim().isEmpty ? null : _note.text.trim();
      // Both are upserts keyed on (item, kind), so re-saving corrects the
      // figure instead of double-counting it against the deposit.
      await svc.addFinancialExpense(
        kind: 'destruction_expense',
        amount: _destructionValue,
        description: note,
        srNumber: widget.goods.srNumber,
        packageItemId: widget.goods.itemId,
      );
      await svc.addFinancialExpense(
        kind: 'advertising_expense',
        amount: _advertisingValue,
        description: note,
        srNumber: widget.goods.srNumber,
        packageItemId: widget.goods.itemId,
      );
      ref.read(financialExpensesRefreshProvider.notifier).trigger();
      if (!mounted) return;
      Navigator.pop(context);
      context.showSuccess('Costs recorded for ${widget.goods.goodsName}');
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
      label: 'DISPOSAL EXPENSES',
      title: widget.goods.goodsName,
      icon: Icons.receipt_long_rounded,
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
              backgroundColor: green, foregroundColor: Colors.white),
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_rounded, size: 18),
          label: const Text('Save Costs'),
          onPressed: _saving ? null : _save,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          StyledFormSection(
            title: 'Goods',
            icon: Icons.inventory_2_rounded,
            children: [
              _KeyValue(label: 'SR Number', value: widget.goods.srNumber),
              _KeyValue(label: 'Quantity', value: '${widget.goods.quantity}'),
              _KeyValue(
                label: 'Destroying Deposit',
                value: 'LKR ${money.format(widget.goods.destroyingDeposit)}',
                emphasise: true,
              ),
            ],
          ),
          const Gap(14),
          StyledFormSection(
            title: 'Costs Incurred',
            icon: Icons.payments_rounded,
            children: [
              TextField(
                controller: _destruction,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Destruction Expenses (LKR)',
                  hintText: '0.00',
                  prefixIcon: Icon(Icons.local_fire_department_rounded),
                ),
              ),
              const Gap(12),
              TextField(
                controller: _advertising,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Advertising Expenses (LKR)',
                  hintText: '0.00',
                  prefixIcon: Icon(Icons.campaign_rounded),
                ),
              ),
              const Gap(12),
              TextField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
            ],
          ),
          const Gap(14),
          // The arithmetic, spelled out — a refund is never typed in, it is
          // what the deposit has left after these costs.
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
                  value: 'LKR ${money.format(widget.goods.destroyingDeposit)}'),
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
        Text(value,
            style: TextStyle(
                color: color ?? context.colors.textPrimary,
                fontSize: emphasise ? 14.5 : 13,
                fontWeight: emphasise ? FontWeight.w800 : FontWeight.w600)),
      ]),
    );
  }
}
