import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';
import '../core/providers.dart';
import '../core/supabase_client.dart';
import '../models/models.dart';
import 'custom_dropdown.dart';

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
  ConsumerState<PackageDetailsDialog> createState() =>
      _PackageDetailsDialogState();
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
      final creator =
          await AuditLogService().getPackageCreator(widget.package.id);
      if (mounted) setState(() => _creatorFallback = creator);
    } catch (_) {}
    if (mounted) setState(() => _isLoadingCreator = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.package;
    String officerDisplay = 'Unknown Officer';

    if (p.inspectedByName != null) {
      officerDisplay =
          '${p.inspectedByName}${p.inspectedByBadge != null ? " (No: ${p.inspectedByBadge})" : ""}';
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
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
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
                color: isDark
                    ? context.colors.surfaceDark
                    : context.colors.customsBlueDark,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(18)),
                border: Border(
                    bottom: BorderSide(color: context.colors.borderColor)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: context.colors.primaryGold.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.inventory_2_rounded,
                        color: context.colors.primaryGold, size: 24),
                  ),
                  const Gap(16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SR Register Entry',
                          style: TextStyle(
                              color: isDark
                                  ? context.colors.textMuted
                                  : Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w500),
                        ),
                        Text(
                          p.srNumber,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _getStatusColor(
                              context, p.isReturned ? 'returned' : p.status)
                          .withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: _getStatusColor(
                                  context, p.isReturned ? 'returned' : p.status)
                              .withOpacity(0.5)),
                    ),
                    child: Text(
                      (p.isReturned ? 'returned' : p.status).toUpperCase(),
                      style: TextStyle(
                          color: _getStatusColor(
                              context, p.isReturned ? 'returned' : p.status),
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Gap(12),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon:
                        const Icon(Icons.close_rounded, color: Colors.white70),
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
                              Expanded(
                                  child: _DetailColumn(
                                      'Consignee', p.consigneeName,
                                      icon: Icons.person_rounded)),
                              if (p.consigneePhone != null)
                                Expanded(
                                    child: _DetailColumn(
                                        'Phone', p.consigneePhone!,
                                        icon: Icons.phone_rounded)),
                              if (p.declarantName != null)
                                Expanded(
                                    child: _DetailColumn(
                                        'Declarant', p.declarantName!,
                                        icon: Icons.business_rounded)),
                            ],
                          ),
                          const Gap(16),
                          const Divider(),
                          const Gap(16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (p.entryDate != null)
                                Expanded(
                                    child: _DetailColumn(
                                        'Entry Date',
                                        DateFormat('dd MMM yyyy')
                                            .format(p.entryDate!),
                                        icon: Icons.calendar_today_rounded)),
                              if (p.declaredValue > 0)
                                Expanded(
                                    child: _DetailColumn('Value',
                                        'LKR ${NumberFormat('#,##0.00').format(p.declaredValue)}',
                                        icon: Icons.payments_rounded)),
                              if (p.weightKg > 0)
                                Expanded(
                                    child: _DetailColumn(
                                        'Weight', '${p.weightKg} kg',
                                        icon: Icons.scale_rounded)),
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
                        if (p.reason != null && p.reason!.isNotEmpty)
                          _InfoChip('Reason', p.reason!,
                              Icons.info_outline_rounded, context),
                        if (p.cusdecNo != null)
                          _InfoChip(
                              'Cusdec',
                              '${p.cusdecNo} ${p.cusdecDate != null ? "(${p.cusdecDate})" : ""}',
                              Icons.description_rounded,
                              context),
                        if (p.consigneeNic != null)
                          _InfoChip('NIC', p.consigneeNic!, Icons.badge_rounded,
                              context),
                        if (p.originCountry.isNotEmpty)
                          _InfoChip('Origin', p.originCountry,
                              Icons.public_rounded, context),
                        _InfoChip('Officer', officerDisplay,
                            Icons.admin_panel_settings_rounded, context),
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
                        child: Text(p.description!,
                            style:
                                TextStyle(color: context.colors.textSecondary)),
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
                          border: Border.all(
                              color:
                                  context.colors.warningAmber.withOpacity(0.3)),
                        ),
                        child: Text(p.notes!,
                            style:
                                TextStyle(color: context.colors.textSecondary)),
                      ),
                    ],

                    if (p.items.isNotEmpty) ...[
                      const Gap(24),
                      _SectionHeader('Items Included', Icons.category_rounded),
                      ...p.items.map((item) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: context.colors.surfaceDark,
                              borderRadius: BorderRadius.circular(10),
                              border:
                                  Border.all(color: context.colors.borderColor),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                      color: context.colors.primaryGold
                                          .withOpacity(0.15),
                                      shape: BoxShape.circle),
                                  child: Text('${item.quantity}x',
                                      style: TextStyle(
                                          color: context.colors.primaryGold,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12)),
                                ),
                                const Gap(12),
                                Expanded(
                                    child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.itemName,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14)),
                                    if (item.category != null ||
                                        item.unitValue > 0)
                                      Row(
                                        children: [
                                          if (item.category != null)
                                            Text(item.category!,
                                                style: TextStyle(
                                                    color: context
                                                        .colors.textMuted,
                                                    fontSize: 12)),
                                          if (item.category != null &&
                                              item.unitValue > 0)
                                            Text(' • ',
                                                style: TextStyle(
                                                    color: context
                                                        .colors.textMuted,
                                                    fontSize: 12)),
                                          if (item.unitValue > 0)
                                            Text(
                                                'LKR ${NumberFormat('#,##0.00').format(item.unitValue)}/ea',
                                                style: TextStyle(
                                                    color: context
                                                        .colors.textMuted,
                                                    fontSize: 12)),
                                        ],
                                      ),
                                  ],
                                )),
                                if (item.isProhibited)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                        color: context.colors.dangerRed
                                            .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(6)),
                                    child: Row(
                                      children: [
                                        Icon(Icons.warning_amber_rounded,
                                            color: context.colors.dangerRed,
                                            size: 14),
                                        const Gap(4),
                                        Text('Prohibited',
                                            style: TextStyle(
                                                color: context.colors.dangerRed,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          )),
                    ],

                    if (p.warehouseEntries.isNotEmpty) ...[
                      const Gap(24),
                      _SectionHeader(
                          'Warehouse History', Icons.warehouse_rounded),
                      ...p.warehouseEntries.map((we) => Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: context.colors.surfaceDark,
                              borderRadius: BorderRadius.circular(12),
                              border:
                                  Border.all(color: context.colors.borderColor),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.02),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2))
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Header of history card
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: context.colors.primaryGold
                                        .withOpacity(0.05),
                                    borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(11)),
                                    border: Border(
                                        bottom: BorderSide(
                                            color: context.colors.borderColor)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.location_on_rounded,
                                          size: 16,
                                          color: context.colors.primaryGold),
                                      const Gap(8),
                                      Text(we.warehouseName,
                                          style: TextStyle(
                                              color: context.colors.primaryGold,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14)),
                                      const Spacer(),
                                      if (we.isReturned &&
                                          we.returnedAt != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                              color: context.colors.successGreen
                                                  .withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(6)),
                                          child: Text('RETURNED',
                                              style: TextStyle(
                                                  color: context
                                                      .colors.successGreen,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold)),
                                        )
                                      else if (we.isPackageConfiscated)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                              color: context.colors.dangerRed
                                                  .withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(6)),
                                          child: Text('CONFISCATED',
                                              style: TextStyle(
                                                  color:
                                                      context.colors.dangerRed,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold)),
                                        )
                                      else
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                              color: context.colors.heldOrange
                                                  .withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(6)),
                                          child: Text('ACTIVE',
                                              style: TextStyle(
                                                  color:
                                                      context.colors.heldOrange,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold)),
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
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _HistoryRow(
                                                'Admitted',
                                                DateFormat('dd MMM yyyy, HH:mm')
                                                    .format(we.admittedAt),
                                                context),
                                            const Gap(6),
                                            if (we.isReturned &&
                                                we.returnedAt != null) ...[
                                              _HistoryRow(
                                                  'Returned',
                                                  DateFormat('dd MMM yyyy')
                                                      .format(we.returnedAt!),
                                                  context),
                                              const Gap(6),
                                            ],
                                            _HistoryRow('Reason', we.holdReason,
                                                context),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: we.isPackageConfiscated
                                              ? context.colors.dangerRed
                                                  .withOpacity(0.05)
                                              : context.colors.accentLightBlue
                                                  .withOpacity(0.05),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                              color: we.isPackageConfiscated
                                                  ? context.colors.dangerRed
                                                      .withOpacity(0.2)
                                                  : context
                                                      .colors.accentLightBlue
                                                      .withOpacity(0.2)),
                                        ),
                                        child: Column(
                                          children: [
                                            Text('Storage Charge',
                                                style: TextStyle(
                                                    color: context
                                                        .colors.textMuted,
                                                    fontSize: 10)),
                                            const Gap(4),
                                            Text(
                                              'LKR ${NumberFormat('#,##0.00').format(we.calculateCharge(widget.storageRate))}',
                                              style: TextStyle(
                                                  color: we.isPackageConfiscated
                                                      ? context.colors.dangerRed
                                                      : context
                                                          .colors.primaryGold,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14),
                                            ),
                                            if (we.isPackageConfiscated)
                                              Text('(Waived)',
                                                  style: TextStyle(
                                                      color: context
                                                          .colors.dangerRed,
                                                      fontSize: 10)),
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
            // Footer Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: isDark
                    ? context.colors.surfaceDark
                    : context.colors.customsBlueDark,
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(18)),
                border:
                    Border(top: BorderSide(color: context.colors.borderColor)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                    ),
                    child: const Text('Close'),
                  ),
                  const Gap(12),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showUpdateForm(context, p);
                    },
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Update'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.primaryGold,
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showUpdateForm(BuildContext context, PackageModel package) {
    showDialog(
      context: context,
      builder: (_) => _PackageUpdateDialog(package: package),
    );
  }

  Color _getStatusColor(BuildContext context, String status) {
    switch (status.toLowerCase()) {
      case 'cleared':
        return context.colors.successGreen;
      case 'held':
        return context.colors.heldOrange;
      case 'pending':
        return context.colors.warningAmber;
      case 'confiscated':
        return context.colors.dangerRed;
      case 'returned':
        return context.colors.successGreen;
      default:
        return context.colors.textMuted;
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
          Text(title,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: context.colors.textPrimary)),
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
            Text(label,
                style:
                    TextStyle(color: context.colors.textMuted, fontSize: 12)),
          ],
        ),
        const Gap(4),
        Text(value,
            style: TextStyle(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 14)),
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
          child: Text(label,
              style: TextStyle(color: ctx.colors.textMuted, fontSize: 12)),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  color: ctx.colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}

Widget _InfoChip(
    String label, String value, IconData icon, BuildContext context) {
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
        Text('$label: ',
            style: TextStyle(color: context.colors.textMuted, fontSize: 12)),
        Text(value,
            style: TextStyle(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 12)),
      ],
    ),
  );
}

class _PackageUpdateDialog extends ConsumerStatefulWidget {
  final PackageModel package;
  const _PackageUpdateDialog({required this.package});

  @override
  ConsumerState<_PackageUpdateDialog> createState() =>
      _PackageUpdateDialogState();
}

class _PackageUpdateDialogState extends ConsumerState<_PackageUpdateDialog> {
  final _formKey = GlobalKey<FormState>();
  
  // Register Information
  late TextEditingController _srNumberCtrl;
  late String _status;
  late TextEditingController _declarantNameCtrl;
  late TextEditingController _entryDateCtrl;
  late TextEditingController _cusdecNoCtrl;
  late TextEditingController _cusdecDateCtrl;
  late TextEditingController _descriptionCtrl;
  
  // Consignee Information
  late TextEditingController _consigneeNameCtrl;
  late TextEditingController _consigneeNicCtrl;
  late TextEditingController _consigneePhoneCtrl;
  
  // Additional Info
  late TextEditingController _declaredValueCtrl;
  late TextEditingController _weightCtrl;
  late TextEditingController _originCountryCtrl;
  
  // Notes & Charges
  late TextEditingController _notesCtrl;
  late TextEditingController _storageChargeCtrl;

  bool _isSaving = false;
  bool _isLoading = true;

  List<WarehouseModel> _warehouses = [];
  WarehouseModel? _selectedWarehouse;
  WarehouseEntryModel? _currentEntry;

  @override
  void initState() {
    super.initState();
    final pkg = widget.package;

    _srNumberCtrl = TextEditingController(text: pkg.srNumber);
    _status = pkg.status;
    _declarantNameCtrl = TextEditingController(text: pkg.declarantName ?? '');
    _entryDateCtrl = TextEditingController(text: pkg.entryDate != null ? DateFormat('yyyy-MM-dd').format(pkg.entryDate!) : '');
    _cusdecNoCtrl = TextEditingController(text: pkg.cusdecNo ?? '');
    _cusdecDateCtrl = TextEditingController(text: pkg.cusdecDate ?? '');
    _descriptionCtrl = TextEditingController(text: pkg.description ?? '');

    _consigneeNameCtrl = TextEditingController(text: pkg.consigneeName);
    _consigneeNicCtrl = TextEditingController(text: pkg.consigneeNic ?? '');
    _consigneePhoneCtrl = TextEditingController(text: pkg.consigneePhone ?? '');

    _declaredValueCtrl = TextEditingController(text: pkg.declaredValue?.toStringAsFixed(2) ?? '');
    _weightCtrl = TextEditingController(text: pkg.weightKg?.toStringAsFixed(2) ?? '');
    _originCountryCtrl = TextEditingController(text: pkg.originCountry ?? '');

    _notesCtrl = TextEditingController(text: pkg.notes ?? '');
    _storageChargeCtrl = TextEditingController();

    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final warehouses = await WarehouseService().getWarehouses();
      final entryData = await supabase
          .from('warehouse_entries')
          .select('*, warehouses(*)')
          .eq('package_id', widget.package.id)
          .eq('is_returned', false)
          .maybeSingle();

      WarehouseEntryModel? currentEntry;
      WarehouseModel? selectedWh;

      if (entryData != null) {
        currentEntry = WarehouseEntryModel.fromJson(entryData);
        final found = warehouses.where((w) => w.id == currentEntry?.warehouseId);
        if (found.isNotEmpty) selectedWh = found.first;
      }

      if (mounted) {
        setState(() {
          _warehouses = warehouses;
          _currentEntry = currentEntry;
          _selectedWarehouse = selectedWh;
          // Load the accumulated charge
          if (currentEntry?.accumulatedCharge != null && currentEntry!.accumulatedCharge! > 0) {
            _storageChargeCtrl.text = currentEntry.accumulatedCharge!.toStringAsFixed(2);
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading warehouse data: ');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _srNumberCtrl.dispose();
    _declarantNameCtrl.dispose();
    _entryDateCtrl.dispose();
    _cusdecNoCtrl.dispose();
    _cusdecDateCtrl.dispose();
    _descriptionCtrl.dispose();
    _consigneeNameCtrl.dispose();
    _consigneeNicCtrl.dispose();
    _consigneePhoneCtrl.dispose();
    _declaredValueCtrl.dispose();
    _weightCtrl.dispose();
    _originCountryCtrl.dispose();
    _notesCtrl.dispose();
    _storageChargeCtrl.dispose();
    super.dispose();
  }

  Future<void> _selectDate(TextEditingController ctrl) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        ctrl.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      if (_selectedWarehouse != null &&
          _currentEntry?.warehouseId != _selectedWarehouse?.id) {
        if (_currentEntry != null) {
          await WarehouseService().markAsReturned(
            _currentEntry!.id,
            returnNotes: 'Transferred to ',
          );
        }
        await WarehouseService().addEntry(
          packageId: widget.package.id,
          warehouseId: _selectedWarehouse!.id,
          holdReason: _currentEntry?.holdReason ?? 'Transferred',
          itemCount: _currentEntry?.itemCount ?? 1,
        );
      }

      final updatedPkg = widget.package.copyWith(
        status: _status,
        declarantName: _declarantNameCtrl.text.trim(),
        entryDate: _entryDateCtrl.text.isEmpty ? null : DateTime.tryParse(_entryDateCtrl.text),
        cusdecNo: _cusdecNoCtrl.text.trim(),
        cusdecDate: _cusdecDateCtrl.text.trim(),
        description: _descriptionCtrl.text.trim(),
        consigneeName: _consigneeNameCtrl.text.trim(),
        consigneeNic: _consigneeNicCtrl.text.trim(),
        consigneePhone: _consigneePhoneCtrl.text.trim(),
        declaredValue: double.tryParse(_declaredValueCtrl.text),
        weightKg: double.tryParse(_weightCtrl.text),
        originCountry: _originCountryCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
      );

      await PackageService().upsertPackage(updatedPkg, updatedPkg.items);

      // Update the accumulated storage charge if provided
      if (_storageChargeCtrl.text.isNotEmpty && _currentEntry != null) {
        final newCharge = double.tryParse(_storageChargeCtrl.text);
        if (newCharge != null) {
          await supabase
              .from('warehouse_entries')
              .update({'accumulated_storage_charge': newCharge})
              .eq('id', _currentEntry!.id);
        }
      }

      if (mounted) {
        ref.invalidate(livePackagesProvider);
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Package updated successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to update: '),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildSection(String title, IconData icon, List<Widget> children, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: context.colors.primaryGold, size: 20),
            const Gap(8),
            Text(title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: context.colors.primaryGold,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        const Gap(12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? context.colors.surfaceDark : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.colors.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
        const Gap(24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 800, // Widened to make it look like Inspection Form
        decoration: BoxDecoration(
          color: context.colors.cardDark,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: context.colors.primaryGold.withOpacity(0.3), width: 1.5),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: BoxDecoration(
                color: isDark
                    ? context.colors.surfaceDark
                    : context.colors.customsBlueDark,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(18)),
                border: Border(
                    bottom: BorderSide(color: context.colors.borderColor)),
              ),
              child: Row(
                children: [
                  Icon(Icons.edit_document, color: context.colors.primaryGold),
                  const Gap(12),
                  Expanded(
                    child: Text(
                      'Update Package - ',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon:
                        const Icon(Icons.close_rounded, color: Colors.white70),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(28),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSection(
                              'SR Register Information',
                              Icons.app_registration_rounded,
                              [
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _srNumberCtrl,
                                        readOnly: true,
                                        decoration: InputDecoration(
                                          labelText: 'SR Number *',
                                          filled: true,
                                          fillColor: isDark ? Colors.black12 : Colors.grey.shade100,
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                      ),
                                    ),
                                    const Gap(16),
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        value: _status,
                                        decoration: InputDecoration(
                                          labelText: 'Status *',
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        items: const [
                                          DropdownMenuItem(value: 'pending', child: Text('PENDING')),
                                          DropdownMenuItem(value: 'held', child: Text('HELD')),
                                          DropdownMenuItem(value: 'cleared', child: Text('CLEARED')),
                                        ],
                                        onChanged: (val) {
                                          if (val != null) setState(() => _status = val);
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const Gap(16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _declarantNameCtrl,
                                        decoration: InputDecoration(
                                          labelText: 'Declarant Name',
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                      ),
                                    ),
                                    const Gap(16),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _entryDateCtrl,
                                        readOnly: true,
                                        onTap: () => _selectDate(_entryDateCtrl),
                                        decoration: InputDecoration(
                                          labelText: 'Entry Date',
                                          suffixIcon: const Icon(Icons.calendar_month_rounded),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const Gap(16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _cusdecNoCtrl,
                                        decoration: InputDecoration(
                                          labelText: 'Cusdec No',
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                      ),
                                    ),
                                    const Gap(16),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _cusdecDateCtrl,
                                        readOnly: true,
                                        onTap: () => _selectDate(_cusdecDateCtrl),
                                        decoration: InputDecoration(
                                          labelText: 'Cusdec Date',
                                          suffixIcon: const Icon(Icons.calendar_month_rounded),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const Gap(16),
                                TextFormField(
                                  controller: _descriptionCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'Package Description',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  maxLines: 2,
                                ),
                              ],
                              isDark,
                            ),
                            _buildSection(
                              'Consignee Information',
                              Icons.person_rounded,
                              [
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _consigneeNameCtrl,
                                        decoration: InputDecoration(
                                          labelText: 'Consignee Name *',
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                                      ),
                                    ),
                                    const Gap(16),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _consigneeNicCtrl,
                                        decoration: InputDecoration(
                                          labelText: 'NIC Number',
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const Gap(16),
                                TextFormField(
                                  controller: _consigneePhoneCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'Phone Number',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ],
                              isDark,
                            ),
                            _buildSection(
                              'Additional Info',
                              Icons.info_rounded,
                              [
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _declaredValueCtrl,
                                        decoration: InputDecoration(
                                          labelText: 'Declared Value (LKR)',
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        keyboardType: TextInputType.number,
                                      ),
                                    ),
                                    const Gap(16),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _weightCtrl,
                                        decoration: InputDecoration(
                                          labelText: 'Weight (kg)',
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        keyboardType: TextInputType.number,
                                      ),
                                    ),
                                    const Gap(16),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _originCountryCtrl,
                                        decoration: InputDecoration(
                                          labelText: 'Origin Country',
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              isDark,
                            ),
                            if (_warehouses.isNotEmpty)
                              _buildSection(
                                'Assign to Warehouse',
                                Icons.warehouse_rounded,
                                [
                                  Column(
                                    children: _warehouses.map((w) {
                                      final isSelected = _selectedWarehouse == w;
                                      final isCurrent = w.id == _currentEntry?.warehouseId;
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 8),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(10),
                                          onTap: isCurrent
                                              ? null
                                              : () => setState(() => _selectedWarehouse = w),
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 200),
                                            padding: const EdgeInsets.all(14),
                                            decoration: BoxDecoration(
                                              color: isCurrent
                                                  ? (isDark ? Colors.grey.shade800 : Colors.grey.shade200)
                                                  : (isSelected
                                                      ? context.colors.primaryGold.withOpacity(0.15)
                                                      : context.colors.cardDark),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(
                                                color: isCurrent
                                                    ? (isDark ? Colors.grey.shade700 : Colors.grey.shade300)
                                                    : (isSelected
                                                        ? context.colors.primaryGold
                                                        : context.colors.borderColor),
                                                width: isSelected ? 2 : 1,
                                              ),
                                            ),
                                            child: Row(children: [
                                              Icon(Icons.warehouse_rounded,
                                                  color: isCurrent
                                                      ? Colors.grey.shade500
                                                      : (isSelected
                                                          ? context.colors.primaryGold
                                                          : context.colors.textMuted),
                                                  size: 20),
                                              const Gap(12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(w.name,
                                                        style: TextStyle(
                                                            color: isCurrent
                                                                ? Colors.grey.shade500
                                                                : (isSelected
                                                                    ? context.colors.primaryGold
                                                                    : context.colors.textPrimary),
                                                            fontWeight: FontWeight.w600)),
                                                    if (w.location != null)
                                                      Text(w.location!,
                                                          style: TextStyle(
                                                              color: isCurrent
                                                                  ? Colors.grey.shade500
                                                                  : context.colors.textMuted,
                                                              fontSize: 12)),
                                                  ],
                                                ),
                                              ),
                                              if (isCurrent)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey.shade500.withOpacity(0.2),
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: Text('Current',
                                                      style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.grey.shade500)),
                                                )
                                              else if (isSelected)
                                                Icon(Icons.check_circle_rounded, color: context.colors.primaryGold),
                                            ]),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                                isDark,
                              ),
                            _buildSection(
                              'Storage Charge',
                              Icons.currency_exchange_rounded,
                              [
                                TextFormField(
                                  controller: _storageChargeCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'Accumulated Storage Charge (LKR)',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    hintText: '0.00',
                                  ),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                ),
                              ],
                              isDark,
                            ),
                            _buildSection(
                              'Officer Notes',
                              Icons.notes_rounded,
                              [
                                TextFormField(
                                  controller: _notesCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'Notes',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  maxLines: 3,
                                ),
                              ],
                              isDark,
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: context.colors.borderColor)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const Gap(12),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      backgroundColor: context.colors.primaryGold,
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black87))
                        : const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.save_rounded, size: 18),
                              Gap(8),
                              Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
