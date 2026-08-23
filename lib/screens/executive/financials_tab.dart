import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../core/yards.dart';
import '../../models/models.dart';
import '../../widgets/error_view.dart';
import '../../widgets/styled_form_dialog.dart';
import '../../widgets/styled_dropdown.dart';

final _money = NumberFormat('#,##0.00');
String _lkr(double v) => 'LKR ${_money.format(v)}';

/// High Panel · Financials.
///
/// INCOME is derived from records the system already holds — storage charges,
/// destroying deposits, sale proceeds and the taxes on them. EXPENDITURE is
/// entered by hand (destruction costs, advertising, refunds), because nothing
/// else in the system records it.
///
/// The sale-proceeds distribution is shown SEPARATELY from the net balance:
/// it does not add to or subtract from the balance, it says where the proceeds
/// go afterwards.
class FinancialsTab extends ConsumerWidget {
  const FinancialsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = AppTheme.executiveTeal;
    final async = ref.watch(financialSummaryProvider);
    // The DC observes the High Panel but records nothing.
    final canEdit = !isExecutiveViewOnly(ref.watch(currentProfileProvider));

    return async.when(
      loading: () => Center(child: CircularProgressIndicator(color: accent)),
      error: (e, _) => ErrorView(
          error: e, onRetry: () => ref.refresh(financialSummaryProvider)),
      data: (sum) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('Financials',
                  style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700)),
              const Gap(10),
              Expanded(
                child: Text(
                    canEdit
                        ? 'Income, expenditure and the distribution of sale proceeds'
                        : 'Income, expenditure and the distribution of sale proceeds · view only',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: context.colors.textMuted, fontSize: 13)),
              ),
              if (canEdit)
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: accent),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Record Expense'),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const _AddExpenseDialog(),
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
                  ('Refunds', sum.refunds),
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

            _ExpenseLedger(canEdit: canEdit)
                .animate()
                .fadeIn(duration: 500.ms)
                .slideY(begin: 0.06),
          ],
        ),
      ),
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
              Text(
                  'The Treasury\'s half splits again',
                  style: TextStyle(
                      color: context.colors.textMuted, fontSize: 12)),
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

/// Every recorded outgoing, so a figure in the Expenditure card can be traced.
class _ExpenseLedger extends ConsumerWidget {
  final bool canEdit;
  const _ExpenseLedger({required this.canEdit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(financialExpensesProvider);
    final df = DateFormat('yyyy-MM-dd');

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
            Icon(Icons.receipt_long_rounded,
                size: 18, color: context.colors.dangerRed),
            const Gap(8),
            Text('Recorded Expenses',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ]),
          const Gap(14),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('Could not load expenses: $e',
                style: TextStyle(color: context.colors.dangerRed)),
            data: (list) {
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                        canEdit
                            ? 'No expenses recorded yet — use Record Expense above.'
                            : 'No expenses recorded yet.',
                        style: TextStyle(
                            color: context.colors.textMuted, fontSize: 13)),
                  ),
                );
              }
              return Column(
                children: [
                  for (final e in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        _KindChip(kind: e.kind),
                        const Gap(12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  e.description?.trim().isNotEmpty == true
                                      ? e.description!.trim()
                                      : e.kindLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: context.colors.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              Text(
                                  [
                                    df.format(e.incurredOn),
                                    if (e.srNumber != null) e.srNumber!,
                                    if (e.yard != null) yardName(e.yard),
                                  ].join('  ·  '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: context.colors.textMuted,
                                      fontSize: 11.5)),
                            ],
                          ),
                        ),
                        const Gap(12),
                        Text(_lkr(e.amount),
                            style: TextStyle(
                                color: context.colors.dangerRed,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                        if (canEdit) ...[
                          const Gap(6),
                          IconButton(
                            tooltip: 'Delete',
                            icon: Icon(Icons.delete_outline_rounded,
                                size: 18, color: context.colors.textMuted),
                            onPressed: () async {
                              await ref
                                  .read(disposalServiceProvider)
                                  .deleteFinancialExpense(e.id);
                              ref
                                  .read(financialExpensesRefreshProvider
                                      .notifier)
                                  .trigger();
                            },
                          ),
                        ],
                      ]),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  final String kind;
  const _KindChip({required this.kind});

  @override
  Widget build(BuildContext context) {
    final (label, colour) = switch (kind) {
      'destruction_expense' => ('Destruction', context.colors.dangerRed),
      'advertising_expense' => ('Advertising', context.colors.accentLightBlue),
      _ => ('Refund', context.colors.warningAmber),
    };
    return Container(
      width: 96,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colour.withOpacity(0.12),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: colour.withOpacity(0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: colour, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

/// Record one outgoing.
class _AddExpenseDialog extends ConsumerStatefulWidget {
  const _AddExpenseDialog();
  @override
  ConsumerState<_AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends ConsumerState<_AddExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _srCtrl = TextEditingController();
  String _kind = 'destruction_expense';
  String? _yard;
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    _srCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await ref.read(disposalServiceProvider).addFinancialExpense(
            kind: _kind,
            amount: double.parse(_amountCtrl.text.trim()),
            description: _descCtrl.text,
            yard: _yard,
            srNumber: _srCtrl.text,
            incurredOn: _date,
          );
      ref.read(financialExpensesRefreshProvider.notifier).trigger();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${expenseKindLabel(_kind)} recorded'),
          backgroundColor: context.colors.successGreen));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: context.colors.dangerRed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.executiveTeal;
    return StyledFormDialog(
      label: 'Financials',
      title: 'Record Expense',
      headerAccentColor: accent,
      icon: Icons.receipt_long_rounded,
      width: 520,
      child: Form(
        key: _formKey,
        child: StyledFormSection(
          title: 'Expense Details',
          icon: Icons.payments_rounded,
          children: [
            StyledDropdownFormField<String>(
              label: 'Type *',
              value: _kind,
              helperText: null,
              isDense: true,
              menuWidth: 440,
              options: [
                for (final e in kExpenseKinds.entries)
                  StyledDropdownOption(e.key, e.value),
              ],
              onChanged: (v) => setState(() => _kind = v ?? _kind),
            ),
            const Gap(14),
            TextFormField(
              controller: _amountCtrl,
              decoration: const InputDecoration(
                  isDense: true, labelText: 'Amount (LKR) *'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return 'Required';
                final d = double.tryParse(t);
                if (d == null) return 'Enter a number';
                if (d < 0) return 'Cannot be negative';
                return null;
              },
            ),
            const Gap(14),
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                  isDense: true, labelText: 'Description'),
              maxLines: 2,
            ),
            const Gap(14),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _srCtrl,
                  decoration: const InputDecoration(
                      isDense: true, labelText: 'SR Number (optional)'),
                  textCapitalization: TextCapitalization.characters,
                ),
              ),
              const Gap(12),
              Expanded(
                child: StyledDropdownFormField<String>(
                  label: 'Yard (optional)',
                  value: _yard ?? '_none',
                  helperText: null,
                  isDense: true,
                  menuWidth: 220,
                  options: [
                    const StyledDropdownOption('_none', 'Not specified'),
                    for (final y in kYards)
                      StyledDropdownOption(y.code, y.name),
                  ],
                  onChanged: (v) => setState(
                      () => _yard = (v == null || v == '_none') ? null : v),
                ),
              ),
            ]),
            const Gap(14),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (picked != null) setState(() => _date = picked);
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                    isDense: true, labelText: 'Date incurred'),
                child: Text(DateFormat('yyyy-MM-dd').format(_date),
                    style: TextStyle(color: context.colors.textPrimary)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: accent),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Save Expense'),
        ),
      ],
    );
  }
}
