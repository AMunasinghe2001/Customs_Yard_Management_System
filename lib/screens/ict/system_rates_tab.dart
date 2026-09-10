import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/services.dart';
import '../../widgets/account_cells.dart';
import '../../widgets/empty_table_state.dart';
import '../../widgets/error_view.dart';
import '../../widgets/styled_form_dialog.dart';
import '../../widgets/tooltip_text.dart';
import 'ict_ui.dart';

/// The rates the whole system charges by: the daily storage rate, and the
/// taxes applied to a sale.
///
/// ⚠️ These lived in two different portals, each editable by the people it
/// billed. The yard's Admin Panel set the storage rate that decides what the
/// yard collects; Central Disposal's Taxes tab set the levies applied to its
/// own sales. Neither is a yard decision or a directorate decision — they are
/// statutory figures that must be the SAME everywhere, and a rate one office
/// can change under another office's feet is not a rate, it is an argument.
///
/// ⚠️ They are also both HISTORIES, not settings. A storage rate change
/// applies from its own day forward and every charge already computed keeps
/// the rate it was computed at — see `calculatePackageCharge`, which walks
/// day by day through the rate history. Editing the current figure never
/// rewrites the past, which is exactly why this page can be a single form.
class SystemRatesTab extends ConsumerStatefulWidget {
  const SystemRatesTab({super.key, required this.accent});

  final Color accent;

  @override
  ConsumerState<SystemRatesTab> createState() => _SystemRatesTabState();
}

class _SystemRatesTabState extends ConsumerState<SystemRatesTab> {
  /// The newest rate in the history, which is the one in force.
  double? _currentRate(Map<DateTime, double>? rates) {
    if (rates == null || rates.isEmpty) return null;
    return rates.entries.reduce((a, b) => a.key.isAfter(b.key) ? a : b).value;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rates = ref.watch(storageRateProvider).valueOrNull;
    final history = ref.watch(storageRateHistoryProvider);
    final taxes = ref.watch(taxesProvider);
    final current = _currentRate(rates);
    final money = NumberFormat('#,##0.00');

    final activeTaxes =
        taxes.valueOrNull?.where((t) => t.isActive).toList() ?? const [];
    final totalPct =
        activeTaxes.fold<double>(0, (sum, t) => sum + t.percentage);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ⚠️ The two figures an officer came to check, before either table.
          // "What do we charge a day" and "what comes off a sale" are the
          // whole content of this page; the tables below are how each got
          // there.
          Row(children: [
            Expanded(
              child: IctMetricCard(
                label: 'DAILY STORAGE RATE',
                value: current == null
                    ? '—'
                    : 'LKR ${money.format(current)}',
                caption: 'Per package, per day in a warehouse',
                icon: Icons.warehouse_rounded,
                color: widget.accent,
              ),
            ),
            const Gap(12),
            Expanded(
              child: IctMetricCard(
                label: 'TAX ON A SALE',
                value: taxes.isLoading
                    ? '—'
                    : '${totalPct.toStringAsFixed(1)}%',
                caption: activeTaxes.isEmpty
                    ? 'No levy is currently active'
                    : '${activeTaxes.length} active '
                        '${activeTaxes.length == 1 ? 'levy' : 'levies'}, applied '
                        'to every sale',
                icon: Icons.receipt_long_rounded,
                color: c.successGreen,
              ),
            ),
          ]).animate().fadeIn(duration: 300.ms),
          const Gap(16),

          // ── Storage rate ────────────────────────────────────────────────
          IctSectionCard(
            icon: Icons.warehouse_rounded,
            title: 'Storage Rate',
            subtitle:
                'What a yard charges per package per day. A new rate applies '
                'from the day it is set — charges already computed keep the '
                'rate they were computed at.',
            badge: history.valueOrNull == null
                ? null
                : '${history.value!.length} '
                    '${history.value!.length == 1 ? 'change' : 'changes'}',
            actions: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: widget.accent,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.edit_rounded, size: 16),
                label: const Text('Set Rate',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                onPressed: () => _showRateDialog(context, current),
              ),
            ],
            height: 300,
            child: history.when(
              loading: () =>
                  Center(child: CircularProgressIndicator(color: widget.accent)),
              error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.refresh(storageRateHistoryProvider)),
              data: (list) => list.isEmpty
                  ? const EmptyTableState(message: 'No rate has been set yet')
                  : DataTable2(
                      columnSpacing: 12,
                      horizontalMargin: 16,
                      fixedTopRows: 1,
                      headingRowColor: WidgetStateProperty.all(
                          c.textPrimary.withOpacity(0.03)),
                      columns: const [
                        DataColumn2(
                            label: Text('Date & Time'), size: ColumnSize.M),
                        DataColumn2(label: Text('Set By'), size: ColumnSize.M),
                        DataColumn2(
                            label: Text('Rate'),
                            size: ColumnSize.S,
                            fixedWidth: 160),
                      ],
                      rows: [
                        for (final row in list)
                          DataRow(cells: [
                            DataCell(TooltipText(
                                DateFormat('dd MMM yyyy, HH:mm')
                                    .format(row.createdAt))),
                            DataCell(TooltipText(
                                (row.details?['set_by'] as String?)
                                        ?.trim()
                                        .isNotEmpty ==
                                    true
                                    ? (row.details!['set_by'] as String).trim()
                                    : 'System',
                                overflow: TextOverflow.ellipsis)),
                            DataCell(Text(
                                'LKR ${money.format(row.details?['rate'] ?? 0)}',
                                style: TextStyle(
                                    color: widget.accent,
                                    fontWeight: FontWeight.w700))),
                          ]),
                      ],
                    ),
            ),
          ).animate().slideY(begin: 0.04, duration: 350.ms).fadeIn(),
          const Gap(16),

          // ── Taxes ───────────────────────────────────────────────────────
          IctSectionCard(
            icon: Icons.receipt_long_rounded,
            title: 'Sale Taxes',
            subtitle:
                'Statutory levies applied to every tender sale. Deactivating '
                'one leaves it on the sales already recorded — it stops '
                'applying to new ones.',
            badge: taxes.valueOrNull == null
                ? null
                : '${taxes.value!.length} '
                    '${taxes.value!.length == 1 ? 'levy' : 'levies'}',
            actions: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: c.successGreen,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add Levy',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                onPressed: () => _showTaxDialog(context),
              ),
            ],
            height: 320,
            child: taxes.when(
              loading: () =>
                  Center(child: CircularProgressIndicator(color: widget.accent)),
              error: (e, _) => ErrorView(
                  error: e, onRetry: () => ref.refresh(taxesProvider)),
              data: (list) => list.isEmpty
                  ? const EmptyTableState(message: 'No levies configured')
                  : DataTable2(
                      columnSpacing: 12,
                      horizontalMargin: 16,
                      fixedTopRows: 1,
                      headingRowColor: WidgetStateProperty.all(
                          c.textPrimary.withOpacity(0.03)),
                      columns: const [
                        DataColumn2(label: Text('Name'), size: ColumnSize.L),
                        DataColumn2(
                            label: Center(child: Text('Percentage')),
                            size: ColumnSize.S,
                            fixedWidth: 130),
                        DataColumn2(
                            label: Center(child: Text('Status')),
                            size: ColumnSize.S,
                            fixedWidth: 120),
                        DataColumn2(
                            label: Center(child: Text('Actions')),
                            size: ColumnSize.S,
                            fixedWidth: 110),
                      ],
                      rows: [
                        for (final t in list)
                          DataRow(cells: [
                            DataCell(TooltipText(t.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600))),
                            DataCell(Center(
                              child: Text('${t.percentage}%',
                                  style: TextStyle(
                                      color: c.textPrimary,
                                      fontWeight: FontWeight.w600)),
                            )),
                            DataCell(Center(
                              child: _StatusPill(active: t.isActive),
                            )),
                            DataCell(Center(
                              child: RowActionButtons(
                                accent: widget.accent,
                                onEdit: () => _showTaxDialog(context, tax: t),
                                onDelete: () => _confirmDeleteTax(context, t),
                                editTooltip: 'Edit levy',
                                deleteTooltip: 'Delete levy',
                              ),
                            )),
                          ]),
                      ],
                    ),
            ),
          ).animate().slideY(begin: 0.04, duration: 350.ms).fadeIn(delay: 80.ms),
        ],
      ),
    );
  }

  // ── The storage rate form ─────────────────────────────────────────────
  Future<void> _showRateDialog(BuildContext context, double? current) async {
    final ctrl = TextEditingController(
        text: current == null ? '' : current.toStringAsFixed(2));
    String? error;
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => StyledFormDialog(
          label: 'STORAGE RATE',
          title: 'Set the daily rate',
          icon: Icons.warehouse_rounded,
          headerAccentColor: widget.accent,
          erp: true,
          width: 460,
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            const Gap(8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: widget.accent,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              ),
              icon: saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_rounded, size: 16),
              label: const Text('Set Rate'),
              onPressed: saving
                  ? null
                  : () async {
                      final value = double.tryParse(ctrl.text.trim());
                      // ⚠️ A rate of zero is not a rate. It would silently
                      // stop every warehouse charge in the country, and the
                      // only sign would be invoices reading LKR 0.
                      if (value == null || value <= 0) {
                        setDlg(() =>
                            error = 'Enter a rate greater than zero');
                        return;
                      }
                      setDlg(() {
                        error = null;
                        saving = true;
                      });
                      try {
                        await ref
                            .read(disposalServiceProvider)
                            .setStorageRate(value);
                        ref.invalidate(storageRateProvider);
                        ref.invalidate(storageRateHistoryProvider);
                        // ⚠️ `set_storage_rate` writes an audit row, and
                        // Activity Logs one tab over is already built. Without
                        // this the rate change is missing from the log until
                        // ICT navigates away and back -- the same bug the yard
                        // portal had before this page moved here.
                        ref.invalidate(ictAllOfficeLogsProvider);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                                'Daily storage rate set to LKR '
                                '${value.toStringAsFixed(2)}'),
                            backgroundColor: context.colors.successGreen,
                          ));
                        }
                      } catch (e) {
                        setDlg(() {
                          saving = false;
                          error = 'Could not save: $e';
                        });
                      }
                    },
            ),
          ],
          child: StyledFormSection(
            title: 'Daily charge per package',
            icon: Icons.attach_money_rounded,
            children: [
              Text(
                'Applies from today forward. Charges already computed keep the '
                'rate they were computed at, so this never rewrites a bill '
                'that has been issued.',
                style:
                    TextStyle(color: context.colors.textSecondary, fontSize: 12.5),
              ),
              const Gap(10),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Daily rate (LKR)',
                  prefixText: 'LKR ',
                  helperText: 'e.g. 150.00',
                  errorText: error,
                ),
                onChanged: (_) {
                  if (error != null) setDlg(() => error = null);
                },
              ),
            ],
          ),
        ),
      ),
    );
    ctrl.dispose();
  }

  // ── The tax form ──────────────────────────────────────────────────────
  Future<void> _showTaxDialog(BuildContext context,
      {DisposalTaxModel? tax}) async {
    final nameCtrl = TextEditingController(text: tax?.name ?? '');
    final pctCtrl =
        TextEditingController(text: tax == null ? '' : '${tax.percentage}');
    var active = tax?.isActive ?? true;
    String? error;
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => StyledFormDialog(
          label: tax == null ? 'NEW LEVY' : 'EDIT LEVY',
          title: tax == null ? 'Add a sale levy' : 'Edit ${tax.name}',
          icon: Icons.receipt_long_rounded,
          headerAccentColor: context.colors.successGreen,
          erp: true,
          width: 460,
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            const Gap(8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: context.colors.successGreen,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              ),
              icon: saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_rounded, size: 16),
              label: Text(tax == null ? 'Add Levy' : 'Save'),
              onPressed: saving
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      final pct = double.tryParse(pctCtrl.text.trim());
                      if (name.isEmpty) {
                        setDlg(() => error = 'Give the levy a name');
                        return;
                      }
                      // ⚠️ 0-100. A negative levy would pay the buyer and a
                      // figure over 100 would take more than the sale
                      // fetched; both compute happily and neither is a tax.
                      if (pct == null || pct < 0 || pct > 100) {
                        setDlg(() =>
                            error = 'Enter a percentage between 0 and 100');
                        return;
                      }
                      setDlg(() {
                        error = null;
                        saving = true;
                      });
                      try {
                        final svc = ref.read(disposalServiceProvider);
                        if (tax == null) {
                          await svc.createTax(name, pct, isActive: active);
                        } else {
                          await svc.updateTax(tax.id, name, pct, active);
                        }
                        ref.invalidate(taxesProvider);
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        setDlg(() {
                          saving = false;
                          error = 'Could not save: $e';
                        });
                      }
                    },
            ),
          ],
          child: StyledFormSection(
            title: 'Levy',
            icon: Icons.percent_rounded,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  helperText: 'e.g. VAT, Stamp Duty',
                ),
              ),
              const Gap(10),
              TextField(
                controller: pctCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Percentage',
                  suffixText: '%',
                  errorText: error,
                ),
                onChanged: (_) {
                  if (error != null) setDlg(() => error = null);
                },
              ),
              const Gap(6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: active,
                activeThumbColor: context.colors.successGreen,
                title: const Text('Applied to new sales',
                    style: TextStyle(fontSize: 13.5)),
                // ⚠️ Says what INACTIVE means. It reads as "deleted" unless
                // the form is explicit: sales already recorded keep the levy
                // they were charged.
                subtitle: Text(
                    active
                        ? 'This levy is charged on every sale recorded from now on.'
                        : 'Not charged on new sales. Sales already recorded keep it.',
                    style: TextStyle(
                        color: context.colors.textMuted, fontSize: 11.5)),
                onChanged: (v) => setDlg(() => active = v),
              ),
            ],
          ),
        ),
      ),
    );
    nameCtrl.dispose();
    pctCtrl.dispose();
  }

  Future<void> _confirmDeleteTax(
      BuildContext context, DisposalTaxModel tax) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StyledFormDialog(
        label: 'DELETE LEVY',
        title: 'Delete ${tax.name}?',
        icon: Icons.delete_forever_rounded,
        headerAccentColor: context.colors.dangerRed,
        erp: true,
        width: 460,
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          const Gap(8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.dangerRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            ),
            icon: const Icon(Icons.delete_rounded, size: 16),
            label: const Text('Delete'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
        child: StyledFormSection(
          title: 'This cannot be undone',
          icon: Icons.warning_amber_rounded,
          children: [
            // ⚠️ Offer the softer action, because it is nearly always the
            // right one. A levy that no longer applies should be switched
            // off, not deleted: deleting it loses the name a recorded sale's
            // tax line refers to.
            Text(
              'Sales already recorded keep the tax they were charged, but the '
              'levy disappears from this list and from every future sale.\n\n'
              'If it has simply stopped applying, edit it and switch it off '
              'instead — that keeps the record intact.',
              style: TextStyle(
                  color: context.colors.textSecondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(disposalServiceProvider).deleteTax(tax.id);
      ref.invalidate(taxesProvider);
    } catch (e) {
      if (mounted) showErrorSnack(context, e, action: 'Deleting the levy');
    }
  }
}

/// Active / inactive, in the two colours this app uses for the pair.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final tint =
        active ? context.colors.successGreen : context.colors.warningAmber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tint.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tint.withOpacity(0.4)),
      ),
      child: Text(active ? 'Active' : 'Inactive',
          style: TextStyle(
              color: tint, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}
