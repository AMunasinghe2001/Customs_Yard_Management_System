import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../core/providers.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'styled_form_dialog.dart';

/// What the yard collects before it hands goods over.
///
/// ⚠️ A hand-over is not a click. Storage has been accruing since the day the
/// goods arrived, and the yard cannot release them until that is paid: the
/// officer takes the money, writes a receipt, and only then do the goods
/// leave. The button used to skip all of it and simply set a flag, so the
/// charge on the row beside it was a figure nobody had ever collected.
class HandoverResult {
  /// The receipt the officer wrote for the storage charge.
  final String receiptNo;

  /// The day the goods actually changed hands.
  ///
  /// ⚠️ Editable, defaulting to today. A hand-over recorded on Monday for
  /// goods collected on Friday is normal, and forcing `now()` would put the
  /// wrong day on the receipt — the one document the owner keeps.
  final DateTime handedOverAt;

  /// The charge shown to the officer, so the receipt and the row agree.
  final double charge;

  const HandoverResult({
    required this.receiptNo,
    required this.handedOverAt,
    required this.charge,
  });
}

/// Collects the storage charge, a receipt number and the hand-over date.
///
/// Returns null if the officer cancels — nothing is written and the goods stay
/// where they are.
Future<HandoverResult?> showHandoverForm(
  BuildContext context, {
  required String title,
  required String actionLabel,
  required IconData icon,
  required String srNumber,
  required String itemName,
  required int quantity,
  required double charge,

  /// The line under the charge explaining what it covers.
  required String chargeCaption,
}) {
  return showDialog<HandoverResult>(
    context: context,
    builder: (_) => _HandoverFormDialog(
      title: title,
      actionLabel: actionLabel,
      icon: icon,
      srNumber: srNumber,
      itemName: itemName,
      quantity: quantity,
      charge: charge,
      chargeCaption: chargeCaption,
    ),
  );
}

class _HandoverFormDialog extends ConsumerStatefulWidget {
  const _HandoverFormDialog({
    required this.title,
    required this.actionLabel,
    required this.icon,
    required this.srNumber,
    required this.itemName,
    required this.quantity,
    required this.charge,
    required this.chargeCaption,
  });

  final String title;
  final String actionLabel;
  final IconData icon;
  final String srNumber;
  final String itemName;
  final int quantity;
  final double charge;
  final String chargeCaption;

  @override
  ConsumerState<_HandoverFormDialog> createState() =>
      _HandoverFormDialogState();
}

class _HandoverFormDialogState extends ConsumerState<_HandoverFormDialog> {
  final _receiptCtrl = TextEditingController();

  /// ⚠️ Today, pre-filled. Nearly every hand-over is recorded on the day it
  /// happens, and an empty date field makes the officer type what the system
  /// already knows — then get it wrong under pressure.
  DateTime _date = DateTime.now();
  String? _error;

  @override
  void dispose() {
    _receiptCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final receipt = _receiptCtrl.text.trim();
    if (receipt.isEmpty) {
      // ⚠️ The receipt is the whole point of the form. Without it the money
      // has no record, and the goods have left.
      setState(() => _error = 'Enter the receipt number for the storage charge');
      return;
    }
    Navigator.pop(
      context,
      HandoverResult(
        receiptNo: receipt,
        handedOverAt: _date,
        charge: widget.charge,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0.00');
    return StyledFormDialog(
      label: 'HAND-OVER',
      title: widget.title,
      icon: widget.icon,
      headerAccentColor: context.colors.primaryGold,
      width: 480,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: context.colors.successGreen,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.check_rounded, size: 16),
          label: Text(widget.actionLabel),
          onPressed: _submit,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          StyledFormSection(
            title: 'Goods',
            icon: Icons.inventory_2_rounded,
            children: [
              _row(context, 'SR Number', widget.srNumber),
              _row(context, 'Goods Name', widget.itemName),
              _row(context, 'Quantity', '${widget.quantity}'),
            ],
          ),
          const Gap(14),
          StyledFormSection(
            title: 'Storage Charge',
            icon: Icons.payments_rounded,
            children: [
              // ⚠️ The figure LEADS, because it is what the officer is about
              // to collect. A form that asks for a receipt number without
              // showing the amount makes them go and look it up elsewhere.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: context.colors.primaryGold.withOpacity(0.09),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: context.colors.primaryGold.withOpacity(0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('LKR ${money.format(widget.charge)}',
                        style: TextStyle(
                            color: context.colors.primaryGold,
                            fontSize: 22,
                            fontWeight: FontWeight.w800)),
                    const Gap(2),
                    Text(widget.chargeCaption,
                        style: TextStyle(
                            color: context.colors.textSecondary, fontSize: 11.5)),
                  ],
                ),
              ),
              const Gap(12),
              TextField(
                controller: _receiptCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Receipt Number *',
                  hintText: 'The receipt written for this charge',
                  errorText: _error,
                  prefixIcon: const Icon(Icons.receipt_long_rounded, size: 18),
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _submit(),
              ),
              const Gap(4),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.event_rounded,
                    color: context.colors.primaryGold, size: 20),
                title: const Text('Hand-over Date',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text(DateFormat('yyyy-MM-dd').format(_date)),
                trailing: OutlinedButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      // ⚠️ Not the future. Goods cannot have been collected
                      // on a day that has not happened.
                      lastDate: DateTime.now(),
                    );
                    if (d != null) setState(() => _date = d);
                  },
                  child: const Text('Change'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(label,
                  style: TextStyle(
                      color: context.colors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: Text(value,
                  style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

/// The storage charge for one warehouse entry, on the day it is handed over.
///
/// ⚠️ Charged from the SR's ENTRY DATE, not the warehouse admit date — the
/// same rule the Released Goods table has always used, so the form and the
/// row it sits on cannot disagree.
double handoverCharge(
  WarehouseEntryModel entry,
  PackageModel package,
  Map<DateTime, double> rates, {
  DateTime? until,
}) {
  final start = package.entryDate ?? entry.admittedAt;
  return WarehouseEntryModel(
    id: entry.id,
    packageId: entry.packageId,
    packageItemId: entry.packageItemId,
    warehouseId: entry.warehouseId,
    warehouseName: entry.warehouseName,
    warehouseCode: entry.warehouseCode,
    holdReason: entry.holdReason,
    itemCount: entry.itemCount,
    admittedAt: start,
    dailyRate: entry.dailyRate,
    // ⚠️ To the hand-over day, not to `returnedAt`. The entry closed when the
    // officer RULED; the goods sat here until somebody came for them, and the
    // owner owes for the days they sat.
    returnedAt: until ?? entry.returnedAt,
  ).calculatePackageCharge(package.items, rates);
}
