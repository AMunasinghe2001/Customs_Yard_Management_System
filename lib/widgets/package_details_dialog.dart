import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';
import '../models/models.dart';

class PackageDetailsDialog extends StatelessWidget {
  final PackageModel package;
  final double storageRate;

  const PackageDetailsDialog({
    super.key,
    required this.package,
    required this.storageRate,
  });

  @override
  Widget build(BuildContext context) {
    final p = package;
    return AlertDialog(
      title: Text('SR Register Entry: ${p.srNumber}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _Row('Status', (p.isReturned ? 'returned' : p.status).toUpperCase()),
              _Row('Reason', p.reason ?? '-'),
              _Row('Consignee', p.consigneeName),
              if (p.consigneeNic != null) _Row('NIC', p.consigneeNic!),
              if (p.consigneePhone != null) _Row('Phone', p.consigneePhone!),
              _Row('Declarant', p.declarantName ?? '-'),
              _Row('Cusdec No', p.cusdecNo ?? '-'),
              _Row('Cusdec Date', p.cusdecDate ?? '-'),
              if (p.entryDate != null) _Row('Entry Date', DateFormat('dd/MM/yyyy').format(p.entryDate!)),
              if (p.originCountry.isNotEmpty) _Row('Origin', p.originCountry),
              if (p.declaredValue > 0) _Row('Value', 'LKR ${NumberFormat('#,##0.00').format(p.declaredValue)}'),
              if (p.weightKg > 0) _Row('Weight', '${p.weightKg} kg'),
              if (p.description != null && p.description!.isNotEmpty) _Row('Description', p.description!),
              if (p.notes != null && p.notes!.isNotEmpty) _Row('Notes', p.notes!),
              _Row('Created At', DateFormat('dd/MM/yyyy HH:mm').format(p.createdAt)),
              if (p.items.isNotEmpty) ...[
                const Gap(16),
                Text('Items', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.w700)),
                const Gap(8),
                ...p.items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(color: context.colors.primaryGold, shape: BoxShape.circle)),
                    const Gap(8),
                    Expanded(child: Text(item.itemName)),
                    Text('x${item.quantity}', style: TextStyle(color: context.colors.textMuted)),
                    if (item.category != null) ...[const Gap(8), Text('[${item.category}]', style: TextStyle(color: context.colors.textMuted, fontSize: 12))],
                    if (item.isProhibited) ...[const Gap(8), Icon(Icons.warning_amber_rounded, color: context.colors.dangerRed, size: 14)],
                  ]),
                )),
              ],
              if (p.warehouseEntries.isNotEmpty) ...[
                const Gap(16),
                Text('Warehouse History', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.w700)),
                const Gap(8),
                ...p.warehouseEntries.map((we) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: context.colors.surfaceDark, borderRadius: BorderRadius.circular(8)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(we.warehouseName, style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.w600)),
                    Text('Admitted: ${DateFormat('dd/MM/yy HH:mm').format(we.admittedAt)}', style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
                    Text('Reason: ${we.holdReason}', style: const TextStyle(fontSize: 13)),
                    Text('Items: ${we.itemCount}', style: TextStyle(color: context.colors.textMuted, fontSize: 12)),
                    if (we.isReturned && we.returnedAt != null)
                      Text('Returned: ${DateFormat('dd/MM/yy').format(we.returnedAt!)}',
                          style: TextStyle(color: context.colors.successGreen, fontSize: 12)),
                    Text('Charge: LKR ${NumberFormat('#,##0.00').format(we.calculateCharge(storageRate))}',
                        style: TextStyle(color: we.isPackageConfiscated ? context.colors.textMuted : context.colors.primaryGold, fontSize: 12, fontWeight: FontWeight.bold)),
                  ]),
                )),
              ],
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}

class _Row extends StatelessWidget {
  final String label, value;
  const _Row(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 130, child: Text(label, style: TextStyle(color: context.colors.textMuted, fontSize: 13, fontWeight: FontWeight.w500))),
        Expanded(child: Text(value, style: TextStyle(color: context.colors.textPrimary, fontSize: 13))),
      ]),
    );
  }
}
