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
    final rowsAsync = ref.watch(srFinancialsProvider);
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
                  error: e, onRetry: () => ref.refresh(srFinancialsProvider)),
              data: (all) {
                final q =
                    ref.watch(disposalSearchProvider(_tabKey)).toLowerCase();
                final yf = ref.watch(disposalYardFilterProvider(_tabKey));

                // Only SRs that carry a deposit or already have a cost are
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
                  rows =
                      rows.where((r) => r.srNumber.toLowerCase().contains(q));
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
                          label: 'SRs with a deposit',
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
  final List<SrFinancials> rows;
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
    // Same padding and single-line layout as [StatChip] beside it, so the
    // whole strip sits at one height.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: color),
        const Gap(8),
        Text(NumberFormat('#,##0.00').format(value),
            style: TextStyle(
                color: color, fontSize: 15, fontWeight: FontWeight.w800)),
        const Gap(8),
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
          columnSpacing: 10,
          horizontalMargin: 16,
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
                label: Text('Total Exp.'), size: ColumnSize.S, numeric: true),
            DataColumn2(
                label: Text('Refund'), size: ColumnSize.S, numeric: true),
            DataColumn2(
                label: Center(child: Text('Status')),
                size: ColumnSize.S,
                fixedWidth: 100),
            DataColumn2(
                label: Center(child: Text('Record')),
                size: ColumnSize.S,
                fixedWidth: 80),
            DataColumn2(
                label: Center(child: Text('Details')),
                size: ColumnSize.S,
                fixedWidth: 80),
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
                      builder: (_) => _RecordExpenseDialog(sr: r),
                    ),
                  ),
                )),
                DataCell(Center(
                  child: IconButton(
                    tooltip: 'Every goods under this SR',
                    icon: Icon(Icons.info_outline_rounded,
                        size: 18, color: context.colors.accentLightBlue),
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => _SrGoodsDialog(sr: r),
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
class _RecordExpenseDialog extends ConsumerStatefulWidget {
  final SrFinancials sr;
  const _RecordExpenseDialog({required this.sr});

  @override
  ConsumerState<_RecordExpenseDialog> createState() =>
      _RecordExpenseDialogState();
}

class _RecordExpenseDialogState extends ConsumerState<_RecordExpenseDialog> {
  late final TextEditingController _destruction;
  late final TextEditingController _advertising;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _destruction = TextEditingController(
        text: widget.sr.destructionExpense == 0
            ? ''
            : widget.sr.destructionExpense.toStringAsFixed(2));
    _advertising = TextEditingController(
        text: widget.sr.advertisingExpense == 0
            ? ''
            : widget.sr.advertisingExpense.toStringAsFixed(2));
    _destruction.addListener(_refresh);
    _advertising.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _destruction.dispose();
    _advertising.dispose();
    super.dispose();
  }

  double get _destructionValue =>
      double.tryParse(_destruction.text.trim()) ?? 0;
  double get _advertisingValue =>
      double.tryParse(_advertising.text.trim()) ?? 0;
  double get _spent => _destructionValue + _advertisingValue;
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
      await svc.addFinancialExpense(
        kind: 'destruction_expense',
        amount: _destructionValue,
        description: 'Destruction expense recorded',
        srNumber: widget.sr.srNumber,
        packageItemId: itemId,
      );
      await svc.addFinancialExpense(
        kind: 'advertising_expense',
        amount: _advertisingValue,
        description: 'Advertising expense recorded',
        srNumber: widget.sr.srNumber,
        packageItemId: itemId,
      );
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
      label: 'DISPOSAL EXPENSES',
      title: widget.sr.srNumber,
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
              TextField(
                controller: _destruction,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Destruction Expenses (LKR)',
                  hintText: '0.00',
                  isDense: true,
                  prefixIcon: Icon(Icons.local_fire_department_rounded,
                      color: context.colors.dangerRed),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const Gap(12),
              TextField(
                controller: _advertising,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Advertising Expenses (LKR)',
                  hintText: '0.00',
                  isDense: true,
                  prefixIcon: Icon(Icons.campaign_rounded,
                      color: context.colors.warningAmber),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const Gap(14),
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
                        'Notice: Destruction and advertising costs entered here are deducted from the lodged Destroying Deposit. Remaining balance will be calculated as a refund.',
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
