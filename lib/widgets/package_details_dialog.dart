import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';
import '../models/models.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/services.dart';

class PackageDetailsDialog extends ConsumerStatefulWidget {
  final PackageModel package;
  final double storageRate;

  const PackageDetailsDialog({
    super.key,
    required this.package,
    required this.storageRate,
  });

  @override
  ConsumerState<PackageDetailsDialog> createState() => _PackageDetailsDialogState();
}

class _PackageDetailsDialogState extends ConsumerState<PackageDetailsDialog> {
  String? _creatorFallback;
  bool _isLoadingCreator = false;

  @override
  void initState() {
    super.initState();
    if (widget.package.inspectedBy == null) {
      _lookupCreator();
    }
  }

  Future<void> _lookupCreator() async {
    setState(() => _isLoadingCreator = true);
    try {
      final creator = await AuditLogService().getPackageCreator(widget.package.id);
      if (mounted) setState(() => _creatorFallback = creator);
    } catch (_) {}
    if (mounted) setState(() => _isLoadingCreator = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.package;
    String officerDisplay = 'Unknown Officer';
    
    if (p.inspectedByName != null) {
      officerDisplay = '${p.inspectedByName}${p.inspectedByBadge != null ? " (No: ${p.inspectedByBadge})" : ""}';
    } else if (p.inspectedBy != null) {
      officerDisplay = 'ID: ${p.inspectedBy}';
    } else if (_isLoadingCreator) {
      officerDisplay = 'Loading...';
    } else if (_creatorFallback != null) {
      officerDisplay = _creatorFallback!;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 600,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        decoration: BoxDecoration(
          color: context.colors.cardDark,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
          border: Border.all(
            color: context.colors.primaryGold.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: BoxDecoration(
                color: isDark ? context.colors.surfaceDark : context.colors.customsBlueDark,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                border: Border(bottom: BorderSide(color: context.colors.borderColor)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: context.colors.primaryGold.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.inventory_2_rounded, color: context.colors.primaryGold, size: 24),
                  ),
                  const Gap(16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SR Register Entry',
                          style: TextStyle(color: isDark ? context.colors.textMuted : Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        Text(
                          p.srNumber,
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _getStatusColor(context, p.isReturned ? 'returned' : p.status).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _getStatusColor(context, p.isReturned ? 'returned' : p.status).withOpacity(0.5)),
                    ),
                    child: Text(
                      (p.isReturned ? 'returned' : p.status).toUpperCase(),
                      style: TextStyle(color: _getStatusColor(context, p.isReturned ? 'returned' : p.status), fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Gap(12),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    splashRadius: 24,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Main Details Grid
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: context.colors.surfaceDark,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.colors.borderColor),
                      ),
                      child: Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _DetailColumn('Consignee', p.consigneeName, icon: Icons.person_rounded)),
                              if (p.consigneePhone != null) Expanded(child: _DetailColumn('Phone', p.consigneePhone!, icon: Icons.phone_rounded)),
                              if (p.declarantName != null) Expanded(child: _DetailColumn('Declarant', p.declarantName!, icon: Icons.business_rounded)),
                            ],
                          ),
                          const Gap(16),
                          const Divider(),
                          const Gap(16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (p.entryDate != null) Expanded(child: _DetailColumn('Entry Date', DateFormat('dd MMM yyyy').format(p.entryDate!), icon: Icons.calendar_today_rounded)),
                              if (p.declaredValue > 0) Expanded(child: _DetailColumn('Value', 'LKR ${NumberFormat('#,##0.00').format(p.declaredValue)}', icon: Icons.payments_rounded)),
                              if (p.weightKg > 0) Expanded(child: _DetailColumn('Weight', '${p.weightKg} kg', icon: Icons.scale_rounded)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Gap(16),

                    // Additional Info Wrap
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        if (p.reason != null && p.reason!.isNotEmpty) _InfoChip('Reason', p.reason!, Icons.info_outline_rounded, context),
                        if (p.cusdecNo != null) _InfoChip('Cusdec', '${p.cusdecNo} ${p.cusdecDate != null ? "(${p.cusdecDate})" : ""}', Icons.description_rounded, context),
                        if (p.consigneeNic != null) _InfoChip('NIC', p.consigneeNic!, Icons.badge_rounded, context),
                        if (p.originCountry.isNotEmpty) _InfoChip('Origin', p.originCountry, Icons.public_rounded, context),
                        _InfoChip('Officer', officerDisplay, Icons.admin_panel_settings_rounded, context),
                      ],
                    ),

                    if (p.description != null && p.description!.isNotEmpty) ...[
                      const Gap(20),
                      _SectionHeader('Description', Icons.description_rounded),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: context.colors.surfaceDark.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: context.colors.borderColor),
                        ),
                        child: Text(p.description!, style: TextStyle(color: context.colors.textSecondary)),
                      ),
                    ],

                    if (p.notes != null && p.notes!.isNotEmpty) ...[
                      const Gap(20),
                      _SectionHeader('Notes', Icons.note_alt_rounded),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: context.colors.warningAmber.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: context.colors.warningAmber.withOpacity(0.3)),
                        ),
                        child: Text(p.notes!, style: TextStyle(color: context.colors.textSecondary)),
                      ),
                    ],

                    if (p.items.isNotEmpty) ...[
                      const Gap(24),
                      _SectionHeader('Items Included', Icons.category_rounded),
                      ...p.items.map((item) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: context.colors.surfaceDark,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: context.colors.borderColor),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: context.colors.primaryGold.withOpacity(0.15), shape: BoxShape.circle),
                              child: Text('${item.quantity}x', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                            const Gap(12),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.itemName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                if (item.category != null || item.unitValue > 0)
                                  Row(
                                    children: [
                                      if (item.category != null) Text(item.category!, style: TextStyle(color: context.colors.textMuted, fontSize: 12)),
                                      if (item.category != null && item.unitValue > 0) Text(' • ', style: TextStyle(color: context.colors.textMuted, fontSize: 12)),
                                      if (item.unitValue > 0) Text('LKR ${NumberFormat('#,##0.00').format(item.unitValue)}/ea', style: TextStyle(color: context.colors.textMuted, fontSize: 12)),
                                    ],
                                  ),
                              ],
                            )),
                            if (item.isProhibited)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: context.colors.dangerRed.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                                child: Row(
                                  children: [
                                    Icon(Icons.warning_amber_rounded, color: context.colors.dangerRed, size: 14),
                                    const Gap(4),
                                    Text('Prohibited', style: TextStyle(color: context.colors.dangerRed, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      )),
                    ],

                    if (p.warehouseEntries.isNotEmpty) ...[
                      const Gap(24),
                      _SectionHeader('Warehouse History', Icons.warehouse_rounded),
                      ...p.warehouseEntries.map((we) => Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: context.colors.surfaceDark,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: context.colors.borderColor),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header of history card
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: context.colors.primaryGold.withOpacity(0.05),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                                border: Border(bottom: BorderSide(color: context.colors.borderColor)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.location_on_rounded, size: 16, color: context.colors.primaryGold),
                                  const Gap(8),
                                  Text(we.warehouseName, style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.w700, fontSize: 14)),
                                  const Spacer(),
                                  if (we.isReturned && we.returnedAt != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: context.colors.successGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                                      child: Text('RETURNED', style: TextStyle(color: context.colors.successGreen, fontSize: 10, fontWeight: FontWeight.bold)),
                                    )
                                  else if (we.isPackageConfiscated)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: context.colors.dangerRed.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                                      child: Text('CONFISCATED', style: TextStyle(color: context.colors.dangerRed, fontSize: 10, fontWeight: FontWeight.bold)),
                                    )
                                  else
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: context.colors.heldOrange.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                                      child: Text('ACTIVE', style: TextStyle(color: context.colors.heldOrange, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                ],
                              ),
                            ),
                            // Body of history card
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _HistoryRow('Admitted', DateFormat('dd MMM yyyy, HH:mm').format(we.admittedAt), context),
                                        const Gap(6),
                                        if (we.isReturned && we.returnedAt != null) ...[
                                          _HistoryRow('Returned', DateFormat('dd MMM yyyy').format(we.returnedAt!), context),
                                          const Gap(6),
                                        ],
                                        _HistoryRow('Reason', we.holdReason, context),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: we.isPackageConfiscated 
                                          ? context.colors.dangerRed.withOpacity(0.05)
                                          : context.colors.accentLightBlue.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: we.isPackageConfiscated 
                                            ? context.colors.dangerRed.withOpacity(0.2)
                                            : context.colors.accentLightBlue.withOpacity(0.2)
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Text('Storage Charge', style: TextStyle(color: context.colors.textMuted, fontSize: 10)),
                                        const Gap(4),
                                        Text(
                                          'LKR ${NumberFormat('#,##0.00').format(we.calculateCharge(widget.storageRate))}',
                                          style: TextStyle(
                                            color: we.isPackageConfiscated ? context.colors.dangerRed : context.colors.primaryGold,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14
                                          ),
                                        ),
                                        if (we.isPackageConfiscated)
                                          Text('(Waived)', style: TextStyle(color: context.colors.dangerRed, fontSize: 10)),
                                      ],
                                    ),
                                  )
                                ],
                              ),
                            ),
                          ],
                        ),
                      )),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(BuildContext context, String status) {
    switch (status.toLowerCase()) {
      case 'cleared': return context.colors.successGreen;
      case 'held': return context.colors.heldOrange;
      case 'pending': return context.colors.warningAmber;
      case 'confiscated': return context.colors.dangerRed;
      case 'returned': return context.colors.successGreen;
      default: return context.colors.textMuted;
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader(this.title, this.icon);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: context.colors.textSecondary),
          const Gap(8),
          Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: context.colors.textPrimary)),
        ],
      ),
    );
  }
}

class _DetailColumn extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _DetailColumn(this.label, this.value, {required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: context.colors.textMuted),
            const Gap(6),
            Text(label, style: TextStyle(color: context.colors.textMuted, fontSize: 12)),
          ],
        ),
        const Gap(4),
        Text(value, style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final String label;
  final String value;
  final BuildContext ctx;

  const _HistoryRow(this.label, this.value, this.ctx);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(label, style: TextStyle(color: ctx.colors.textMuted, fontSize: 12)),
        ),
        Expanded(
          child: Text(value, style: TextStyle(color: ctx.colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}

Widget _InfoChip(String label, String value, IconData icon, BuildContext context) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: context.colors.surfaceDark,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: context.colors.borderColor),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 14, color: context.colors.textMuted),
        const Gap(6),
        Text('$label: ', style: TextStyle(color: context.colors.textMuted, fontSize: 12)),
        Text(value, style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 12)),
      ],
    ),
  );
}
