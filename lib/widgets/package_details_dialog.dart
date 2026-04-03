import 'package:flutter/material.dart' as material;
import 'package:flutter/material.dart' show Wrap, LinearProgressIndicator, RoundedRectangleBorder, Colors, Icons, Theme, FontWeight, BorderRadius, Radius, BoxConstraints, BoxShadow, Offset, Border, BorderSide, IconButton, ElevatedButton, CircularProgressIndicator, ScaffoldMessenger, SnackBar, showDatePicker, showDialog, BuildContext, Widget, Row, Column, Expanded, Icon, Text, Padding, EdgeInsets, Center, SingleChildScrollView, Form, GlobalKey, FormState, TextFormField, InputDecoration, DropdownButtonFormField, DropdownMenuItem, SizedBox, Brightness, Color, IconData, Dialog, Tween, TweenAnimationBuilder, Transform, Opacity, Curves, MainAxisSize, CrossAxisAlignment, BoxDecoration, StatelessWidget, LinearGradient, Flexible, Navigator, MainAxisAlignment, TextButton, BoxShape, FontStyle, TextStyle, Container, OutlinedButton, TextEditingController, MediaQuery, TextInputType, VoidCallback, Spacer, TextOverflow, StatefulWidget, StatefulBuilder, ConstrainedBox;
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../core/providers.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/services.dart';

class PackageDetailsDialog extends ConsumerStatefulWidget {
  final PackageModel package;
  final Map<DateTime, double> storageRate;
  final WarehouseEntryModel? highlightEntry; // Added highlightEntry
  final bool useLegacySummary;
  final bool useWarehouseSummary;

  const PackageDetailsDialog({
    super.key,
    required this.package,
    required this.storageRate,
    this.highlightEntry, // Added highlightEntry
    this.useLegacySummary = false,
    this.useWarehouseSummary = false,
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

  Future<bool> _showReleaseConfirmation(BuildContext context, WarehouseEntryModel entry) async {
    final notesCtrl = TextEditingController();
    final receiptCtrl = TextEditingController();
    final dateCtrl = TextEditingController(text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
    
    // Find the specific item this entry refers to
    final specificItem = widget.package.items.firstWhere(
      (i) => i.id == entry.packageItemId,
      orElse: () => widget.package.items.first,
    );

    // Auto-repair display logic for old entries that saved 1 as itemCount
    int displayCount = entry.itemCount;
    if (displayCount == 1 && specificItem.quantity > 1 && !entry.isReturned) {
      final returnedSum = widget.package.warehouseEntries
          .where((e) => e.packageItemId == specificItem.id && e.isReturned)
          .fold(0, (sum, e) => sum + e.itemCount);
      displayCount = specificItem.quantity - returnedSum;
      if (displayCount < 1) displayCount = 1; // Fallback
    }

    final qtyCtrl = TextEditingController(text: displayCount.toString());
    final formKey = GlobalKey<FormState>();

    double getCharge(int count) {
      // Create a temporary entry with the specified count to calculate charge accurately
      final tempEntry = WarehouseEntryModel(
        id: entry.id,
        packageId: entry.packageId,
        packageItemId: entry.packageItemId,
        warehouseId: entry.warehouseId,
        warehouseName: entry.warehouseName,
        warehouseCode: entry.warehouseCode,
        holdReason: entry.holdReason,
        itemCount: count,
        admittedAt: entry.admittedAt,
        dailyRate: entry.dailyRate,
      );
      return tempEntry.calculatePackageCharge([specificItem], widget.storageRate);
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => material.AlertDialog(
          title: const Text('Release Package Item'),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: formKey,
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SR: ${widget.package.srNumber}', style: const material.TextStyle(fontWeight: FontWeight.bold)),
                Text('Item: ${specificItem.itemName}', style: material.TextStyle(color: context.colors.primaryGold)),
                Text('Warehouse: ${entry.warehouseName}', style: const material.TextStyle(fontSize: 12)),
                const Gap(16),
                material.Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.colors.surfaceDark,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total in Warehouse:'),
                          Text('$displayCount', style: const material.TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const Gap(12),
                      TextFormField(
                        controller: qtyCtrl,
                        decoration: const material.InputDecoration(
                          labelText: 'Quantity to Release',
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return 'Enter quantity';
                          final val = int.tryParse(value);
                          if (val == null || val <= 0) return 'Enter valid quantity';
                          if (val > displayCount) return 'Cannot exceed $displayCount packages';
                          return null;
                        },
                        onChanged: (val) {
                          setDialogState(() {});
                        },
                      ),
                      const Gap(8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Release Charge:'),
                          Text('LKR ${NumberFormat('#,##0.00').format(getCharge(int.tryParse(qtyCtrl.text) ?? 0))}',
                              style: material.TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),
                const Gap(16),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: receiptCtrl,
                        decoration: const material.InputDecoration(
                          labelText: 'Receipt No. *',
                          hintText: 'Enter receipt #',
                        ),
                        validator: (value) => 
                            (value == null || value.trim().isEmpty) ? 'Required' : null,
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: dateCtrl,
                        readOnly: true,
                        decoration: const material.InputDecoration(
                          labelText: 'Receipt Date *',
                          suffixIcon: Icon(Icons.calendar_today, size: 18),
                        ),
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (date != null) {
                            dateCtrl.text = DateFormat('yyyy-MM-dd').format(date);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const Gap(16),
                material.TextField(
                  controller: notesCtrl,
                  decoration: const material.InputDecoration(
                    labelText: 'Release Notes (Optional)',
                    hintText: 'Enter any additional details',
                  ),
                ),
              ],
            ),
            ),
          ),
          actions: [
            material.TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: context.colors.successGreen, foregroundColor: Colors.white),
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                
                final releaseQty = int.tryParse(qtyCtrl.text) ?? 0;
                if (releaseQty <= 0 || releaseQty > entry.itemCount) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Invalid quantity to release'), backgroundColor: Colors.red));
                  return;
                }

                try {
                  String finalNotes = "Receipt No: ${receiptCtrl.text.trim()} | Date: ${dateCtrl.text}";
                  if (notesCtrl.text.trim().isNotEmpty) {
                    finalNotes += " | Notes: ${notesCtrl.text.trim()}";
                  }

                  await ref.read(warehouseServiceProvider).markAsReturned(
                    entry.id,
                    returnNotes: finalNotes,
                    returnQty: releaseQty,
                  );
                  ref
                      .read(packagesRefreshTriggerProvider.notifier)
                      .trigger();
                  ref
                      .read(warehouseRefreshTriggerProvider.notifier)
                      .trigger();
                  ref.invalidate(liveWarehouseEntriesProvider(entry.warehouseId));
                  ref.invalidate(livePackagesProvider);
                  ref.invalidate(allWarehouseEntriesProvider);
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('Error: $e'), backgroundColor: context.colors.dangerRed));
                  }
                }
              },
              child: const Text('Confirm Release'),
            ),
          ],
        ),
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.package;
    String officerDisplay = 'Unknown Officer';
    String? salaryNumber;

    if (p.inspectedByName != null) {
      // Extract salary number if it's in the name format "(Salary No: XXXXX)"
      final match = RegExp(r'\(Salary No:\s*(\d+)\)').firstMatch(p.inspectedByName!);
      if (match != null) {
        salaryNumber = match.group(1);
      }
      // Clean up officer name - remove salary number if included
      officerDisplay = p.inspectedByName!.replaceAll(RegExp(r'\s*\(Salary No:.*?\)'), '');
    } else if (p.inspectedBy != null) {
      officerDisplay = 'ID: ${p.inspectedBy}';
    } else if (_isLoadingCreator) {
      officerDisplay = 'Loading...';
    } else if (_creatorFallback != null) {
      officerDisplay = _creatorFallback!;
    }

    // Use badge number if available, otherwise use extracted salary number
    final displayBadgeNumber = (p.inspectedByBadge != null && p.inspectedByBadge!.isNotEmpty) 
        ? p.inspectedByBadge 
        : salaryNumber;

    // Get current user's role to conditionally disable update button
    final currentProfile = ref.watch(currentProfileProvider);
    final isOfficer = currentProfile?.role == 'officer';

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Filter to find the highlighted entry's specific item if needed
    final highlightedItem = widget.highlightEntry != null
      ? p.items.firstWhere((i) => i.id == widget.highlightEntry!.packageItemId, orElse: () => p.items.first)
      : null;

    final legacyItems = (widget.highlightEntry != null && highlightedItem != null)
      ? [highlightedItem]
      : p.items;
    final legacyEntries = (widget.useLegacySummary && widget.highlightEntry != null)
      ? [widget.highlightEntry!]
      : (widget.highlightEntry != null && highlightedItem != null)
        ? p.warehouseEntries
          .where((e) => e.packageItemId == highlightedItem.id)
          .toList()
        : p.warehouseEntries;

    int? displayQty;
    if (highlightedItem != null && widget.highlightEntry != null) {
      displayQty = widget.highlightEntry!.itemCount;
      if (displayQty == 1 && highlightedItem.quantity > 1 && !widget.highlightEntry!.isReturned) {
        final returnedSum = widget.package.warehouseEntries
            .where((e) => e.packageItemId == highlightedItem.id && e.isReturned)
            .fold(0, (sum, e) => sum + e.itemCount);
        displayQty = highlightedItem.quantity - returnedSum;
        if (displayQty! < 1) displayQty = 1;
      }
    }

    String? returnedReceiptNo;
    String? returnedReceiptDate;
    final returnNotes = widget.highlightEntry?.returnNotes;
    if (returnNotes != null && returnNotes.trim().isNotEmpty) {
      for (final part in returnNotes.split('|')) {
        final text = part.trim();
        if (text.toLowerCase().startsWith('receipt no:')) {
          final idx = text.indexOf(':');
          if (idx != -1) returnedReceiptNo = text.substring(idx + 1).trim();
        } else if (text.toLowerCase().startsWith('date:')) {
          final idx = text.indexOf(':');
          if (idx != -1) returnedReceiptDate = text.substring(idx + 1).trim();
        }
      }
    }

      final highlightReturnedById = widget.highlightEntry?.returnedBy;
      final returnedOfficerDisplay =
        widget.highlightEntry?.returnedByName ??
          (highlightReturnedById != null &&
              highlightReturnedById == currentProfile?.id
            ? currentProfile?.fullName
            : null) ??
          'Unknown Officer';
      final returnedOfficerBadge =
        widget.highlightEntry?.returnedByBadge ??
          (highlightReturnedById != null &&
              highlightReturnedById == currentProfile?.id
            ? currentProfile?.badgeNumber
            : null);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 400),
        tween: Tween(begin: 0.0, end: 1.0),
        curve: Curves.easeOutBack,
        builder: (context, value, child) {
          return Transform.scale(
            scale: value,
            child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
          );
        },
        child: material.Container(
          width: 900,
          decoration: BoxDecoration(
            color: context.colors.scaffoldBg,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 40,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              material.Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [context.colors.surfaceDark, context.colors.cardDark]
                        : [context.colors.customsBlue, context.colors.customsBlueDark],
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(23)),
                ),
                child: Row(
                  children: [
                    material.Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.inventory_2_rounded, color: context.colors.primaryGold, size: 24),
                    ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
                    const Gap(16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SR REGISTER ENTRY',
                            style: material.TextStyle(
                              color: context.colors.primaryGold,
                              fontSize: 11,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w800,
                            ),
                          ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
                          Text(
                            p.srNumber,
                            style: material.TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ).animate().fadeIn(duration: 400.ms, delay: 150.ms).slideX(begin: -0.1),
                        ],
                      ),
                    ),
                    const Gap(12),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.7)),
                      splashRadius: 24,
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // SR Register Information Section
                      _DetailSection(
                        title: 'SR Register Information',
                        icon: Icons.assignment_rounded,
                        delay: 100,
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _DetailItem(
                                    icon: Icons.numbers_rounded,
                                    label: 'SR Number',
                                    value: p.srNumber,
                                  ),
                                ),
                                const Gap(12),
                                Expanded(
                                  child: _DetailItem(
                                    icon: Icons.calendar_today_rounded,
                                    label: 'Entry Date',
                                    value: p.entryDate != null ? DateFormat('yyyy-MM-dd').format(p.entryDate!) : 'N/A',
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: _DetailItem(
                                    icon: Icons.receipt_long_rounded,
                                    label: 'Cusdec No',
                                    value: p.cusdecNo ?? 'N/A',
                                  ),
                                ),
                                const Gap(12),
                                Expanded(
                                  child: _DetailItem(
                                    icon: Icons.calendar_month_rounded,
                                    label: 'Cusdec Date',
                                    value: p.cusdecDate ?? 'N/A',
                                  ),
                                ),
                              ],
                            ),
                            _DetailItem(
                              icon: Icons.gavel_rounded,
                              label: 'Case Number',
                              value: p.caseNumber ?? 'N/A',
                            ),
                            _DetailItem(
                              icon: Icons.description_rounded,
                              label: 'Package Description',
                              value: p.description ?? 'No description provided',
                            ),
                          ],
                        ),
                      ),

                      // Consignee Information Section
                      _DetailSection(
                        title: 'Consignee Information',
                        icon: Icons.person_pin_rounded,
                        delay: 200,
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _DetailItem(
                                    icon: Icons.person_rounded,
                                    label: 'Consignee Name',
                                    value: p.consigneeName,
                                  ),
                                ),
                                const Gap(12),
                                Expanded(
                                  child: _DetailItem(
                                    icon: Icons.badge_rounded,
                                    label: 'Declarant Name',
                                    value: p.declarantName ?? 'N/A',
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: _DetailItem(
                                    icon: Icons.home_rounded,
                                    label: 'Declarant Address',
                                    value: p.consigneeAddress ?? 'N/A',
                                  ),
                                ),
                                const Gap(12),
                                Expanded(
                                  child: _DetailItem(
                                    icon: Icons.phone_rounded,
                                    label: 'Declarant Phone Number',
                                    value: p.consigneePhone ?? 'N/A',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      if (widget.useLegacySummary || widget.useWarehouseSummary) ...[
                        _DetailSection(
                          title: 'Item Details',
                          icon: Icons.shopping_bag_rounded,
                          delay: 300,
                          child: (widget.highlightEntry == null || highlightedItem == null)
                              ? const _EmptyState(message: 'No returned item details')
                              : material.Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: context.colors.surfaceDark,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: context.colors.borderColor),
                                  ),
                                  child: Column(
                                    children: [
                                      _DetailItem(
                                        icon: Icons.label_important_rounded,
                                        label: 'Item Name',
                                        value: highlightedItem.itemName,
                                      ),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _DetailItem(
                                              icon: Icons.view_in_ar_rounded,
                                              label: 'Total Packages',
                                              value: '${highlightedItem.quantity}',
                                            ),
                                          ),
                                          const Gap(12),
                                          Expanded(
                                            child: _DetailItem(
                                              icon: widget.useWarehouseSummary
                                                  ? Icons.inventory_2_rounded
                                                  : Icons.keyboard_return_rounded,
                                              label: widget.useWarehouseSummary
                                                  ? 'Remaining (Current)'
                                                  : 'Released (This Receipt)',
                                              value: '${widget.highlightEntry!.itemCount}',
                                              valueColor: widget.useWarehouseSummary
                                                  ? context.colors.primaryGold
                                                  : context.colors.successGreen,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                        if (!widget.useWarehouseSummary)
                          _DetailSection(
                            title: 'Warehouse Summary',
                            icon: Icons.warehouse_rounded,
                            delay: 350,
                            child: legacyEntries.isEmpty
                                ? const _EmptyState(message: 'No warehouse details')
                                : material.Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: context.colors.surfaceDark,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: context.colors.borderColor),
                                    ),
                                    child: Column(
                                      children: [
                                        _DetailItem(
                                          icon: Icons.warehouse_rounded,
                                          label: 'Warehouse',
                                          value: legacyEntries.first.warehouseName,
                                        ),
                                        _DetailItem(
                                          icon: Icons.location_on_rounded,
                                          label: 'Zone',
                                          value: legacyEntries.first.warehouseCode,
                                        ),
                                        _DetailItem(
                                          icon: Icons.calendar_month_rounded,
                                          label: 'Date Range',
                                          value: '${DateFormat('yyyy-MM-dd').format(legacyEntries.first.admittedAt)} to ${legacyEntries.first.returnedAt != null ? DateFormat('yyyy-MM-dd').format(legacyEntries.first.returnedAt!) : '—'}',
                                        ),
                                        _DetailItem(
                                          icon: Icons.receipt_long_rounded,
                                          label: 'Receipt No',
                                          value: returnedReceiptNo ?? '—',
                                        ),
                                        _DetailItem(
                                          icon: Icons.event_rounded,
                                          label: 'Receipt Date',
                                          value: returnedReceiptDate ?? '—',
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                      ] else
                        _DetailSection(
                          title: 'Package Item Summary',
                          icon: Icons.inventory_2_rounded,
                          delay: 300,
                          child: p.items.isEmpty
                              ? const _EmptyState(message: 'No package items')
                              : Column(
                                  children: p.items.map((item) {
                                    final relatedEntries = p.warehouseEntries
                                        .where((e) => e.packageItemId == item.id)
                                        .toList();
                                    final returnedQty = relatedEntries
                                        .where((e) => e.isReturned)
                                        .fold<int>(0, (sum, e) => sum + e.itemCount);
                                    final heldQty = relatedEntries
                                        .where((e) => !e.isReturned)
                                        .fold<int>(0, (sum, e) => sum + e.itemCount);

                                    final currentWarehouses = relatedEntries
                                        .where((e) => !e.isReturned)
                                        .map((e) => e.warehouseName)
                                        .toSet()
                                        .toList();
                                    final historyWarehouses = relatedEntries
                                        .map((e) => e.warehouseName)
                                        .toSet()
                                        .toList();

                                    return material.Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: context.colors.surfaceDark,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: context.colors.borderColor),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: _DetailItem(
                                                  icon: Icons.label_important_rounded,
                                                  label: 'Item Name',
                                                  value: item.itemName,
                                                ),
                                              ),
                                              const Gap(12),
                                              Expanded(
                                                child: _DetailItem(
                                                  icon: Icons.view_in_ar_rounded,
                                                  label: 'Packages',
                                                  value: '${item.quantity}',
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: _DetailItem(
                                                  icon: Icons.category_rounded,
                                                  label: 'Category',
                                                  value: item.category ?? 'N/A',
                                                ),
                                              ),
                                              const Gap(12),
                                              Expanded(
                                                child: _DetailItem(
                                                  icon: Icons.straighten_rounded,
                                                  label: 'Unit',
                                                  value: item.unitOfMeasure,
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (item.reasons != null &&
                                              item.reasons!.isNotEmpty)
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    material.Container(
                                                      padding:
                                                          const EdgeInsets.all(8),
                                                      decoration: BoxDecoration(
                                                        color: context.colors
                                                            .dangerRed
                                                            .withOpacity(0.1),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                                10),
                                                      ),
                                                      child: Icon(
                                                        Icons.warning_amber_rounded,
                                                        size: 16,
                                                        color: context
                                                            .colors.dangerRed,
                                                      ),
                                                    ),
                                                    const Gap(12),
                                                    Text(
                                                      'Reason',
                                                      style: material.TextStyle(
                                                        color:
                                                            context.colors.textMuted,
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        letterSpacing: 0.5,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const Gap(8),
                                                Padding(
                                                  padding: const EdgeInsets.only(bottom: 12),
                                                  child: Wrap(
                                                    spacing: 8,
                                                    runSpacing: 8,
                                                    children: item.reasons!
                                                        .split(',')
                                                        .map((reason) =>
                                                            material.Container(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                      horizontal: 12,
                                                                      vertical: 8),
                                                              decoration: BoxDecoration(
                                                                color: context
                                                                    .colors.dangerRed
                                                                    .withOpacity(0.05),
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(10),
                                                                border: Border.all(
                                                                  color: context
                                                                      .colors.dangerRed
                                                                      .withOpacity(0.2),
                                                                ),
                                                              ),
                                                              child: Text(
                                                                reason.trim(),
                                                                style:
                                                                    material.TextStyle(
                                                                  color: context
                                                                      .colors.dangerRed,
                                                                  fontSize: 12,
                                                                  fontWeight:
                                                                      FontWeight.w600,
                                                                ),
                                                              ),
                                                            ))
                                                        .toList(),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: _DetailItem(
                                                  icon: Icons.keyboard_return_rounded,
                                                  label: 'Returned',
                                                  value: '$returnedQty',
                                                  valueColor: context.colors.successGreen,
                                                ),
                                              ),
                                              const Gap(12),
                                              Expanded(
                                                child: _DetailItem(
                                                  icon: Icons.pause_circle_filled_rounded,
                                                  label: 'Held',
                                                  value: '$heldQty',
                                                  valueColor: context.colors.primaryGold,
                                                ),
                                              ),
                                            ],
                                          ),
                                          _DetailItem(
                                            icon: Icons.warehouse_rounded,
                                            label: 'Current Warehouses',
                                            value: currentWarehouses.isNotEmpty
                                                ? currentWarehouses.join(', ')
                                                : '—',
                                          ),
                                          _DetailItem(
                                            icon: Icons.history_rounded,
                                            label: 'Warehouse History',
                                            value: historyWarehouses.isNotEmpty
                                                ? historyWarehouses.join(', ')
                                                : '—',
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                        ),

                      // Officer Notice Section
                      if (p.notes != null && p.notes!.isNotEmpty)
                        _DetailSection(
                          title: 'Officer Notice',
                          icon: Icons.notification_important_rounded,
                          delay: 400,
                          child: _NoteDisplay(
                            text: p.notes!,
                            isWarning: true,
                            icon: Icons.warning_amber_rounded,
                          ),
                        ),

                      // Entry Person Section
                      _SystemEntrySection(
                        officerDisplay: officerDisplay,
                        badgeNumber: displayBadgeNumber,
                        delay: 500,
                      ),

                      // Returned By Section
                      if (!widget.useWarehouseSummary && widget.highlightEntry?.isReturned == true)
                        _SystemEntrySection(
                          officerDisplay: returnedOfficerDisplay,
                          badgeNumber: returnedOfficerBadge,
                          delay: 550,
                          customTitle: 'Returned By',
                          customIcon: Icons.keyboard_return_rounded,
                        ),

                        if (!widget.useWarehouseSummary && widget.highlightEntry?.isReturned == true &&
                          (returnedReceiptNo != null ||
                              returnedReceiptDate != null))
                        _DetailSection(
                          title: 'Receipt Details',
                          icon: Icons.receipt_long_rounded,
                          delay: 560,
                          child: Row(
                            children: [
                              if (returnedReceiptNo != null)
                                Expanded(
                                  child: _DetailItem(
                                    icon: Icons.receipt_rounded,
                                    label: 'Receipt No',
                                    value: returnedReceiptNo!,
                                  ),
                                ),
                              if (returnedReceiptNo != null &&
                                  returnedReceiptDate != null)
                                const Gap(12),
                              if (returnedReceiptDate != null)
                                Expanded(
                                  child: _DetailItem(
                                    icon: Icons.event_rounded,
                                    label: 'Receipt Date',
                                    value: returnedReceiptDate!,
                                  ),
                                ),
                            ],
                          ),
                        ),

                      // Warehouse Charges Section
                      if (widget.highlightEntry != null)
                        _DetailSection(
                          title: 'Warehouse Charges',
                          icon: Icons.payments_rounded,
                          delay: 600,
                          child: Column(
                            children: [
                              _DetailItem(
                                icon: Icons.calculate_rounded,
                                label: 'Storage Fee (LKR)',
                                value: 'LKR ${NumberFormat('#,##0.00').format(widget.highlightEntry!.calculatePackageCharge([highlightedItem!], widget.storageRate))}',
                                valueColor: context.colors.successGreen,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (widget.useWarehouseSummary)
                material.Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.grey.shade50,
                    border: Border(top: BorderSide(color: context.colors.borderColor)),
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(23)),
                  ),
                  child: Row(
                    children: [
                      material.Tooltip(
                        message: isOfficer ? 'Package updates are restricted to administrators only' : '',
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.colors.primaryGold,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          label: const Text('Update'),
                          onPressed: isOfficer ? null : () {
                            showDialog(
                              context: context,
                              builder: (_) => PackageUpdateDialog(
                                package: p,
                                highlightedItem: highlightedItem,
                                highlightEntry: widget.highlightEntry,
                                storageRate: widget.storageRate,
                              ),
                            );
                          },
                        ),
                      ),
                      const Gap(12),
                      if (widget.highlightEntry != null && !widget.highlightEntry!.isReturned)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.colors.successGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                          icon: const Icon(Icons.assignment_return_rounded, size: 18),
                          label: const Text('Return Package'),
                          onPressed: () async {
                            final success = await _showReleaseConfirmation(context, widget.highlightEntry!);
                            if (success && mounted) {
                              Navigator.pop(context);
                            }
                          },
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});
  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    final isPending = s.contains('pending');
    final isInspected = s.contains('inspected');
    final color = isPending ? context.colors.primaryGold : (isInspected ? context.colors.successGreen : Colors.blue);
    return material.Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.3))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          material.Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const Gap(6),
          Text(status.toUpperCase(), style: material.TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final int delay;

  const _DetailSection({
    required this.title,
    required this.icon,
    required this.child,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return material.Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark 
            ? context.colors.surfaceDark.withOpacity(0.5) 
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          material.Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: context.colors.textPrimary.withOpacity(0.03),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(bottom: BorderSide(color: context.colors.borderColor)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: context.colors.primaryGold),
                const Gap(10),
                Text(
                  title.toUpperCase(),
                  style: material.TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ).animate().slideX(delay: Duration(milliseconds: delay), duration: 300.ms, begin: -0.2),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ).animate().fadeIn(delay: Duration(milliseconds: delay + 100), duration: 400.ms),
        ],
      ),
    );
  }
}

class _DetailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? subValue;
  final Color? valueColor;

  const _DetailItem({
    required this.icon,
    required this.label,
    required this.value,
    this.subValue,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: material.Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.textPrimary.withOpacity(0.02),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.borderColor.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            material.Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.colors.primaryGold.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 16, color: context.colors.primaryGold),
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: material.TextStyle(
                      color: context.colors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Gap(2),
                  Text(
                    value,
                    style: material.TextStyle(
                      color: valueColor ?? context.colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (subValue != null) ...[
                    const Gap(2),
                    Text(
                      subValue!,
                      style: material.TextStyle(
                        color: context.colors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CargoItemTile extends StatelessWidget {
  final PackageItem item;
  final int index;

  const _CargoItemTile({required this.item, required this.index});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: material.Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.primaryGold.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.primaryGold.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            material.Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: context.colors.primaryGold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: material.TextStyle(
                    color: context.colors.primaryGold,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.itemName,
                    style: material.TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  if (item.category != null)
                    Text(item.category!, style: material.TextStyle(color: context.colors.textMuted, fontSize: 11)),
                  if (item.reasons != null && item.reasons!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 10, color: context.colors.heldOrange),
                          const Gap(4),
                          Expanded(
                            child: Text(
                              item.reasons!,
                              style: material.TextStyle(
                                color: context.colors.heldOrange,
                                fontSize: 10,
                                fontStyle: FontStyle.italic,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Text(
              'x${item.quantity}',
              style: material.TextStyle(
                color: context.colors.primaryGold,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WarehouseHistoryTile extends StatelessWidget {
  final PackageModel package;
  final WarehouseEntryModel entry;
  final int index;
  final Map<DateTime, double> rate;
  final bool isHighlighted;
  final material.VoidCallback onRelease;

  const _WarehouseHistoryTile({
    required this.package, 
    required this.entry, 
    required this.index, 
    required this.rate,
    required this.isHighlighted,
    required this.onRelease,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: material.Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isHighlighted 
              ? context.colors.primaryGold.withOpacity(0.08) 
              : context.colors.textPrimary.withOpacity(0.02),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isHighlighted 
                ? context.colors.primaryGold.withOpacity(0.5) 
                : context.colors.borderColor.withOpacity(0.5),
            width: isHighlighted ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                material.Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.colors.primaryGold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.warehouse_rounded, size: 14, color: context.colors.primaryGold),
                ),
                const Gap(10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.warehouseName,
                        style: material.TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      ...entry.holdReason.split(',').map((reason) => Text(
                        reason.trim(),
                        style: material.TextStyle(color: context.colors.textMuted, fontSize: 10),
                      )),
                    ],
                  ),
                ),
                if (entry.isReturned)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      material.Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: context.colors.successGreen.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('RELEASED', 
                            style: material.TextStyle(color: context.colors.successGreen, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                      if (entry.returnedByName != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'By: ${entry.returnedByName}',
                            style: material.TextStyle(color: context.colors.textMuted, fontSize: 9),
                          ),
                        ),
                    ],
                  )
                else
                  material.InkWell(
                    onTap: onRelease,
                    borderRadius: BorderRadius.circular(6),
                    child: material.Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: context.colors.successGreen.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: context.colors.successGreen.withOpacity(0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_circle_fill_rounded, size: 12, color: context.colors.successGreen),
                          const Gap(6),
                          Text('RELEASE', 
                              style: material.TextStyle(color: context.colors.successGreen, fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const Gap(6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'In: ${DateFormat('dd MMM yyyy').format(entry.admittedAt)}${entry.returnedAt != null ? "  Out: ${DateFormat('dd MMM yyyy').format(entry.returnedAt!)}" : ""}',
                  style: material.TextStyle(color: context.colors.textMuted, fontSize: 10),
                ),
                if (entry.admittedByName != null)
                  Text(
                    'Entry by: ${entry.admittedByName}',
                    style: material.TextStyle(color: context.colors.textMuted, fontSize: 10),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemEntrySection extends StatelessWidget {
  final String officerDisplay;
  final String? badgeNumber;
  final int delay;
  final String? customTitle;
  final IconData? customIcon;

  const _SystemEntrySection({
    required this.officerDisplay, 
    this.badgeNumber, 
    required this.delay,
    this.customTitle,
    this.customIcon,
  });

  @override
  Widget build(BuildContext context) {
    return material.Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            context.colors.primaryGold.withOpacity(0.1),
            context.colors.primaryGold.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.primaryGold.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              material.Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.colors.primaryGold.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(customIcon ?? Icons.verified_user_rounded, size: 16, color: context.colors.primaryGold),
              ),
              const Gap(10),
              Text(
                (customTitle ?? 'System Entry By').toUpperCase(),
                style: material.TextStyle(
                  color: context.colors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const Gap(2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  officerDisplay,
                  style: material.TextStyle(
                    color: context.colors.primaryGold,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (badgeNumber != null && badgeNumber!.isNotEmpty)
                material.Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: context.colors.primaryGold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.colors.primaryGold.withOpacity(0.4)),
                  ),
                  child: Text(
                    'Salary No: $badgeNumber',
                    style: material.TextStyle(
                      color: context.colors.primaryGold,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ).animate().slideY(delay: Duration(milliseconds: delay), duration: 300.ms, begin: 0.1);
  }
}

class _NoteDisplay extends StatelessWidget {
  final String text;
  final bool isWarning;
  final IconData? icon;

  const _NoteDisplay({required this.text, this.isWarning = false, this.icon});

  @override
  Widget build(BuildContext context) {
    return material.Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isWarning
            ? context.colors.primaryGold.withOpacity(0.05)
            : context.colors.textPrimary.withOpacity(0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (isWarning ? context.colors.primaryGold : context.colors.borderColor).withOpacity(0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            material.Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: (isWarning ? context.colors.primaryGold : context.colors.textMuted).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 14,
                color: isWarning ? context.colors.primaryGold : context.colors.textMuted,
              ),
            ),
            const Gap(12),
          ],
          Expanded(
            child: Text(
              text,
              style: material.TextStyle(
                color: context.colors.textPrimary,
                fontSize: 12,
                height: 1.5,
                fontWeight: isWarning ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;

  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_rounded, size: 32, color: context.colors.textMuted.withOpacity(0.4)),
            const Gap(2),
            Text(
              message,
              style: material.TextStyle(color: context.colors.textMuted, fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
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

// ============ PACKAGE UPDATE DIALOG ============
class PackageUpdateDialog extends ConsumerStatefulWidget {
  final PackageModel package;
  final PackageItem? highlightedItem;
  final WarehouseEntryModel? highlightEntry; // Added this
  final Map<DateTime, double> storageRate;

  const PackageUpdateDialog({
    super.key,
    required this.package,
    this.highlightedItem,
    this.highlightEntry, // Added this
    required this.storageRate,
  });

  @override
  ConsumerState<PackageUpdateDialog> createState() => _PackageUpdateDialogState();
}

class _ItemRow {
  final nameCtrl = TextEditingController();
  final qtyCtrl = TextEditingController(text: '1');
  final unitOfMeasureCtrl = TextEditingController(text: 'Pieces');
  final unitOtherCtrl = TextEditingController();
  final valueCtrl = TextEditingController(text: '0');
  final categoryCtrl = TextEditingController();
  String status = 'pending';
  final List<String?> selectedReasons = [null];
}

class _PackageUpdateDialogState extends ConsumerState<PackageUpdateDialog> {
  late final _formKey = GlobalKey<FormState>();
  late final TextEditingController _consigneeCtrl;
  late final TextEditingController _consigneeNicCtrl;
  late final TextEditingController _consigneePhoneCtrl;
  late final TextEditingController _declarantCtrl;
  late final TextEditingController _cusdecCtrl;
  late final TextEditingController _cusdecDateCtrl;
  late final TextEditingController _entryDateCtrl;
  late final TextEditingController _caseNumberCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _reasonCtrl;
  late final TextEditingController _valueCtrl;
  late final TextEditingController _weightCtrl;
  late final TextEditingController _originCtrl;

  late String _statusValue;
  late List<_ItemRow> _items;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _consigneeCtrl = TextEditingController(text: widget.package.consigneeName);
    _consigneeNicCtrl = TextEditingController(text: widget.package.consigneeNic ?? '');
    _consigneePhoneCtrl = TextEditingController(text: widget.package.consigneePhone ?? '');
    _declarantCtrl = TextEditingController(text: widget.package.declarantName ?? '');
    _cusdecCtrl = TextEditingController(text: widget.package.cusdecNo ?? '');
    _cusdecDateCtrl = TextEditingController(text: widget.package.cusdecDate ?? '');
    _entryDateCtrl = TextEditingController(text: widget.package.entryDate != null 
        ? '${widget.package.entryDate!.year}-${widget.package.entryDate!.month.toString().padLeft(2, '0')}-${widget.package.entryDate!.day.toString().padLeft(2, '0')}' 
        : '');
    _caseNumberCtrl = TextEditingController(text: widget.package.caseNumber ?? '');
    _descCtrl = TextEditingController(text: widget.package.description ?? '');
    _notesCtrl = TextEditingController(text: widget.package.notes ?? '');
    _reasonCtrl = TextEditingController(text: widget.package.reason ?? '');
    _valueCtrl = TextEditingController(text: widget.package.declaredValue?.toString() ?? '');
    _weightCtrl = TextEditingController(text: widget.package.weightKg?.toString() ?? '');
    _originCtrl = TextEditingController(text: widget.package.originCountry ?? '');
    
    _statusValue = (widget.package.status == 'detained' || widget.package.status == 'forfeited') 
        ? 'held' 
        : widget.package.status;

    // Initialize items
    _items = [];
    if (widget.highlightedItem != null) {
      // Show only the specific highlighted item if provided
      final row = _ItemRow();
      row.nameCtrl.text = widget.highlightedItem!.itemName;
      row.qtyCtrl.text = widget.highlightedItem!.quantity.toString();
      
      row.unitOfMeasureCtrl.text = widget.highlightedItem!.unitOfMeasure;
      if (!['Pieces', 'Cartons', 'Boxes', 'Bags', 'Pallets', 'KG', 'Meters', 'Other'].contains(row.unitOfMeasureCtrl.text)) {
        row.unitOtherCtrl.text = row.unitOfMeasureCtrl.text;
        row.unitOfMeasureCtrl.text = 'Other';
      }
      
      row.valueCtrl.text = widget.highlightedItem!.unitValue.toString();
      row.categoryCtrl.text = widget.highlightedItem!.category ?? '';
      row.status = widget.highlightedItem!.status.isNotEmpty ? widget.highlightedItem!.status : 'pending';
      
      // If the entry is returned, override item status to 'returned'
      if (widget.highlightEntry?.isReturned == true) {
        row.status = 'returned';
      }

      if (widget.highlightedItem!.reasons != null && widget.highlightedItem!.reasons!.isNotEmpty) {
        final rList = widget.highlightedItem!.reasons!.split(', ').map((s) => s.trim()).toList() ;
        row.selectedReasons.clear();
        for (int i = 0; i < rList.length && i < 4; i++) {
          row.selectedReasons.add(rList[i]);
        }
        if (row.selectedReasons.isEmpty) row.selectedReasons.add(null);
      }
      _items.add(row);
    } else if (widget.package.items.isNotEmpty) {
      for (final item in widget.package.items) {
        final row = _ItemRow();
        row.nameCtrl.text = item.itemName;
        row.qtyCtrl.text = item.quantity.toString();
        
        row.unitOfMeasureCtrl.text = item.unitOfMeasure;
        if (!['Pieces', 'Cartons', 'Boxes', 'Bags', 'Pallets', 'KG', 'Meters', 'Other'].contains(row.unitOfMeasureCtrl.text)) {
          row.unitOtherCtrl.text = row.unitOfMeasureCtrl.text;
          row.unitOfMeasureCtrl.text = 'Other';
        }
        
        row.valueCtrl.text = item.unitValue.toString();
        row.categoryCtrl.text = item.category ?? '';
        row.status = item.status.isNotEmpty ? item.status : 'pending';
        if (item.reasons != null && item.reasons!.isNotEmpty) {
          final rList = item.reasons!.split(', ').map((s) => s.trim()).toList();
          row.selectedReasons.clear();
          for (int i = 0; i < rList.length && i < 4; i++) {
            row.selectedReasons.add(rList[i]);
          }
          if (row.selectedReasons.isEmpty) row.selectedReasons.add(null);
        }
        _items.add(row);
      }
    } else {
      _items.add(_ItemRow());
    }
  }

  @override
  void dispose() {
    _consigneeCtrl.dispose();
    _consigneeNicCtrl.dispose();
    _consigneePhoneCtrl.dispose();
    _declarantCtrl.dispose();
    _cusdecCtrl.dispose();
    _cusdecDateCtrl.dispose();
    _entryDateCtrl.dispose();
    _caseNumberCtrl.dispose();
    _descCtrl.dispose();
    _notesCtrl.dispose();
    _reasonCtrl.dispose();
    _valueCtrl.dispose();
    _weightCtrl.dispose();
    _originCtrl.dispose();
    for (final item in _items) {
      item.nameCtrl.dispose();
      item.qtyCtrl.dispose();
      item.unitOfMeasureCtrl.dispose();
      item.unitOtherCtrl.dispose();
      item.valueCtrl.dispose();
      item.categoryCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _selectDate(TextEditingController controller) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2050),
    );
    if (picked != null) {
      setState(() {
        controller.text = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
    }
  }

  Future<void> _updatePackage() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isUpdating = true);
    try {
      final List<PackageItem> itemsToUpsert;
      
      if (widget.highlightedItem != null) {
        // If we were editing a specific item, update just that one in the list
        itemsToUpsert = widget.package.items.map<PackageItem>((item) {
          if (item.id == widget.highlightedItem!.id) {
            final row = _items.first;
            return item.copyWith(
              itemName: row.nameCtrl.text,
              quantity: int.tryParse(row.qtyCtrl.text) ?? 1,
              unitValue: double.tryParse(row.valueCtrl.text) ?? 0,
              category: row.categoryCtrl.text,
              unitOfMeasure: row.unitOfMeasureCtrl.text == 'Other' ? row.unitOtherCtrl.text : row.unitOfMeasureCtrl.text,
              status: row.status,
              reasons: row.selectedReasons.where((res) => res != null).join(', '),
            );
          }
          return item;
        }).toList();
      } else {
        // Otherwise use the bulk items list from the form
        itemsToUpsert = _items.where((r) => r.nameCtrl.text.isNotEmpty).map((r) => PackageItem(
          id: '',
          packageId: '',
          itemName: r.nameCtrl.text,
          quantity: int.tryParse(r.qtyCtrl.text) ?? 1,
          unitValue: double.tryParse(r.valueCtrl.text) ?? 0,
          category: r.categoryCtrl.text,
          unitOfMeasure: r.unitOfMeasureCtrl.text == 'Other' ? r.unitOtherCtrl.text : r.unitOfMeasureCtrl.text,
          status: r.status,
          reasons: r.selectedReasons.where((res) => res != null).join(', '),
        )).toList();
      }

      final updatedPackage = widget.package.copyWith(
        consigneeName: _consigneeCtrl.text.trim(),
        consigneeNic: _consigneeNicCtrl.text.trim(),
        consigneePhone: _consigneePhoneCtrl.text.trim(),
        declarantName: _declarantCtrl.text.trim(),
        cusdecNo: _cusdecCtrl.text.trim(),
        cusdecDate: _cusdecDateCtrl.text.trim(),
        caseNumber: _caseNumberCtrl.text.trim().isEmpty ? null : _caseNumberCtrl.text.trim(),
        entryDate: _entryDateCtrl.text.isNotEmpty ? DateTime.tryParse(_entryDateCtrl.text) : null,
        description: _descCtrl.text.trim(),
        reason: _reasonCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
        declaredValue: double.tryParse(_valueCtrl.text.trim()) ?? 0,
        weightKg: double.tryParse(_weightCtrl.text.trim()) ?? 0,
        originCountry: _originCtrl.text.trim(),
        status: _statusValue,
      );

      await ref.read(packageServiceProvider).upsertPackage(updatedPackage, itemsToUpsert);

      if (mounted) {
        Navigator.pop(context);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Package "${widget.package.srNumber}" updated successfully!'),
            backgroundColor: context.colors.successGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating package: $e'), backgroundColor: context.colors.dangerRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 400),
        tween: Tween(begin: 0.0, end: 1.0),
        curve: Curves.easeOutBack,
        builder: (context, value, child) {
          return Transform.scale(
            scale: value,
            child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
          );
        },
        child: material.Container(
          width: 1000,
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
          decoration: BoxDecoration(
            color: context.colors.scaffoldBg,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 40,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              material.Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [context.colors.surfaceDark, context.colors.cardDark]
                        : [context.colors.customsBlue, context.colors.customsBlueDark],
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(23)),
                ),
                child: Row(
                  children: [
                    material.Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.edit_document, color: context.colors.primaryGold, size: 24),
                    ),
                    const Gap(16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'UPDATE SR REGISTER ENTRY',
                            style: material.TextStyle(
                              color: context.colors.primaryGold,
                              fontSize: 11,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            widget.package.srNumber,
                            style: material.TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.7)),
                      splashRadius: 24,
                    ),
                  ],
                ),
              ),
              // Form Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // SR Information Section
                        _UpdateSectionCard(
                          title: 'SR Register Information',
                          icon: Icons.inventory_2_rounded,
                          children: [
                            TextFormField(
                              enabled: false,
                              initialValue: widget.package.srNumber,
                              decoration: const InputDecoration(labelText: 'SR Number *'),
                            ),
                            
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _cusdecCtrl,
                                    decoration: const InputDecoration(labelText: 'Cusdec No *'),
                                    validator: (v) => v!.isEmpty ? 'Required' : null,
                                  ),
                                ),
                                const Gap(12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _entryDateCtrl,
                                    inputFormatters: [
                                      MaskTextInputFormatter(
                                        mask: '####-##-##',
                                        filter: {"#": RegExp(r'[0-9]')},
                                        type: MaskAutoCompletionType.lazy,
                                      )
                                    ],
                                    decoration: InputDecoration(
                                      labelText: 'Entry Date *',
                                      hintText: 'YYYY-MM-DD',
                                      suffixIcon: IconButton(
                                        icon: Icon(Icons.calendar_month, color: context.colors.primaryGold),
                                        onPressed: () => _selectDate(_entryDateCtrl),
                                      ),
                                    ),
                                    validator: (v) {
                                      if (v == null || v.isEmpty) return 'Required';
                                      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) return 'Use YYYY-MM-DD';
                                      return null;
                                    },
                                  ),
                                ),
                              ],
                            ),
                            
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _caseNumberCtrl,
                                    decoration: const InputDecoration(labelText: 'Case Number'),
                                  ),
                                ),
                                const Gap(12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _cusdecDateCtrl,
                                    inputFormatters: [
                                      MaskTextInputFormatter(
                                        mask: '####-##-##',
                                        filter: {"#": RegExp(r'[0-9]')},
                                        type: MaskAutoCompletionType.lazy,
                                      )
                                    ],
                                    decoration: InputDecoration(
                                      labelText: 'Cusdec Date *',
                                      hintText: 'YYYY-MM-DD',
                                      suffixIcon: IconButton(
                                        icon: Icon(Icons.calendar_month, color: context.colors.primaryGold),
                                        onPressed: () => _selectDate(_cusdecDateCtrl),
                                      ),
                                    ),
                                    validator: (v) {
                                      if (v == null || v.isEmpty) return 'Required';
                                      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) return 'Use YYYY-MM-DD';
                                      return null;
                                    },
                                  ),
                                ),
                              ],
                            ),
                            
                            TextFormField(
                              controller: _descCtrl,
                              decoration: const InputDecoration(labelText: 'Package Description'),
                              maxLines: 2,
                            ),
                          ],
                        ),
                        const Gap(16),
                        // Consignee Information Section
                        _UpdateSectionCard(
                          title: 'Consignee Information',
                          icon: Icons.person_rounded,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _consigneeCtrl,
                                    decoration: const InputDecoration(labelText: 'Consignee Name *'),
                                    validator: (v) => v!.isEmpty ? 'Required' : null,
                                  ),
                                ),
                                const Gap(12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _declarantCtrl,
                                    decoration: const InputDecoration(labelText: 'Declarant Name *'),
                                    validator: (v) => v!.isEmpty ? 'Required' : null,
                                  ),
                                ),
                              ],
                            ),
                            
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _descCtrl, // Reusing controller for address if needed, or stick to required fields
                                    decoration: const InputDecoration(labelText: 'Declarant Address'),
                                  ),
                                ),
                                const Gap(12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _consigneePhoneCtrl,
                                    decoration: const InputDecoration(labelText: 'Declarant Phone Number (10 digits) *'),
                                    keyboardType: TextInputType.phone,
                                    validator: (v) {
                                      if (v == null || v.isEmpty) return 'Required';
                                      if (!RegExp(r'^\d{10}$').hasMatch(v)) {
                                        return 'Must be exactly 10 digits';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 200.ms),
                        const Gap(16),
                        // Package Items Section
                        _UpdateSectionCard(
                          title: widget.highlightedItem != null ? 'ITEM DETAILS' : 'Package Items',
                          icon: Icons.shopping_bag_rounded,
                          headerTrailing: widget.highlightedItem != null ? null : TextButton.icon(
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add Item'),
                            onPressed: () => setState(() => _items.add(_ItemRow())),
                          ),
                          children: [
                            Column(
                              children: List.generate(_items.length, (i) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _UpdateItemRowWidget(
                                  row: _items[i],
                                  index: widget.highlightedItem != null ? -1 : i + 1, // -1 means don't show index
                                  onRemove: widget.highlightedItem != null ? null : (_items.length > 1 ? () => setState(() => _items.removeAt(i)) : null),
                                  onChanged: () => setState(() {}),
                                ),
                              )),
                            ),
                          ],
                        ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 300.ms),
                        const Gap(16),
                        // Notes Section
                        _UpdateSectionCard(
                          title: 'OFFICER NOTES',
                          icon: Icons.note_rounded,
                          children: [
                            TextFormField(
                              controller: _notesCtrl,
                              decoration: const InputDecoration(hintText: 'Additional inspection notes...'),
                              maxLines: 3,
                            ),
                          ],
                        ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 500.ms),
                      ],
                    ),
                  ),
                ),
              ),
              // Footer Buttons
              material.Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : Colors.grey.shade50,
                  border: Border(top: BorderSide(color: context.colors.borderColor)),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(23)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const Gap(12),
                    ElevatedButton.icon(
                      icon: _isUpdating
                          ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.primaryNavy))
                          : const Icon(Icons.save_rounded),
                      label: Text(_isUpdating ? 'Updating...' : 'Update Entry'),
                      onPressed: _isUpdating ? null : _updatePackage,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Helper widget for update form sections
class _UpdateItemRowWidget extends ConsumerStatefulWidget {
  final _ItemRow row;
  final int index;
  final VoidCallback? onRemove;
  final VoidCallback onChanged;

  const _UpdateItemRowWidget({
    required this.row,
    required this.index,
    this.onRemove,
    required this.onChanged,
  });

  @override
  ConsumerState<_UpdateItemRowWidget> createState() => _UpdateItemRowWidgetState();
}

class _UpdateItemRowWidgetState extends ConsumerState<_UpdateItemRowWidget> {
  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(packageCategoriesProvider);
    return material.Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderColor),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              material.Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: context.colors.primaryGold.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('Item ${widget.index == -1 ? "1" : widget.index}', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
              const Spacer(),
              if (widget.onRemove != null)
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded, size: 20, color: context.colors.dangerRed),
                  onPressed: widget.onRemove,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Remove item',
                ),
            ],
          ),
          const Gap(12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: widget.row.nameCtrl,
                  decoration: const InputDecoration(labelText: 'Item Name *', isDense: true),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                  onChanged: (_) => widget.onChanged(),
                ),
              ),
              const Gap(12),
              Expanded(
                flex: 1,
                child: TextFormField(
                  controller: widget.row.qtyCtrl,
                  decoration: const InputDecoration(labelText: 'Pkgs *', isDense: true),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Req';
                    if (int.tryParse(v) == null || int.tryParse(v)! <= 0) return 'Err';
                    return null;
                  },
                  onChanged: (_) => widget.onChanged(),
                ),
              ),
              const Gap(10),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  isDense: true,
                  value: ['Pieces', 'Cartons', 'Boxes', 'Bags', 'Pallets', 'KG', 'Meters', 'Other'].contains(widget.row.unitOfMeasureCtrl.text)
                      ? widget.row.unitOfMeasureCtrl.text
                      : 'Pieces',
                  decoration: const InputDecoration(labelText: 'Unit *', isDense: true),
                  items: ['Pieces', 'Cartons', 'Boxes', 'Bags', 'Pallets', 'KG', 'Meters', 'Other'].map((u) => DropdownMenuItem(value: u, child: Text(u, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) {
                    setState(() {
                      widget.row.unitOfMeasureCtrl.text = v ?? 'Pieces';
                    });
                    widget.onChanged();
                  },
                ),
              ),
              if (widget.row.unitOfMeasureCtrl.text == 'Other') ...[
                const Gap(8),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: widget.row.unitOtherCtrl,
                    decoration: const InputDecoration(labelText: 'Name *', isDense: true),
                    validator: (v) => widget.row.unitOfMeasureCtrl.text == 'Other' && (v == null || v.trim().isEmpty) ? 'Req' : null,
                    onChanged: (_) => widget.onChanged(),
                  ),
                ),
              ],
              const Gap(10),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  isDense: true,
                  value: widget.row.status,
                  decoration: const InputDecoration(labelText: 'Status *', isDense: true),
                  items: ['pending', 'held', 'cleared', 'confiscated', 'returned'].map((s) => DropdownMenuItem(value: s, child: Text(s.toUpperCase(), style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) {
                    setState(() => widget.row.status = v!);
                    widget.onChanged();
                  },
                ),
              ),
              const Gap(10),
              Expanded(
                flex: 2,
                child: categories.when(
                  loading: () => const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  error: (e, _) => IconButton(
                    icon: const Icon(Icons.refresh, size: 16, color: Colors.orange),
                    onPressed: () => ref.refresh(packageCategoriesProvider),
                    tooltip: 'Error loading categories',
                  ),
                  data: (list) {
                    final selectedCategory = list.where((c) => c.name == widget.row.categoryCtrl.text).firstOrNull;
                    return DropdownButtonFormField<String>(
                      isDense: true,
                      value: selectedCategory?.name,
                      decoration: const InputDecoration(labelText: 'Category', isDense: true),
                      items: list.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (v) {
                        widget.row.categoryCtrl.text = v ?? '';
                        setState(() {});
                        widget.onChanged();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
          const Gap(16),
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 18, color: context.colors.heldOrange),
              const Gap(8),
              Text('Hold Reasons', style: material.TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: context.colors.textPrimary)),
              const Spacer(),
              if (widget.row.selectedReasons.length < 4)
                TextButton.icon(
                  onPressed: () {
                    setState(() => widget.row.selectedReasons.add(null));
                    widget.onChanged();
                  },
                  icon: const Icon(Icons.add_circle_outline, size: 16),
                  label: const Text('Add Reason', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: TextButton.styleFrom(
                    foregroundColor: context.colors.primaryGold,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    backgroundColor: context.colors.primaryGold.withOpacity(0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
            ],
          ),
          const Gap(12),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: List.generate(widget.row.selectedReasons.length, (rIdx) {
              return SizedBox(
                width: 380,
                child: Row(
                  children: [
                    Expanded(
                      child: ref.watch(holdReasonsProvider).when(
                        loading: () => const LinearProgressIndicator(),
                        error: (e, _) => Text('Error loading reasons', style: TextStyle(color: context.colors.dangerRed, fontSize: 11)),
                        data: (reasons) => DropdownButtonFormField<String>(
                          isDense: true,
                          value: widget.row.selectedReasons[rIdx],
                          decoration: InputDecoration(
                            labelText: 'Reason ${rIdx + 1} *',
                            labelStyle: const TextStyle(fontSize: 12),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            filled: true,
                            fillColor: context.colors.cardDark,
                          ),
                          validator: (v) => v == null ? 'Required' : null,
                          items: reasons.map((r) => DropdownMenuItem(value: r.reasonText, child: Text(r.reasonText, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis))).toList(),
                          onChanged: (v) {
                            setState(() => widget.row.selectedReasons[rIdx] = v);
                            widget.onChanged();
                          },
                        ),
                      ),
                    ),
                    if (widget.row.selectedReasons.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: IconButton(
                          icon: const Icon(Icons.remove_circle_outline, size: 20, color: Colors.grey),
                          onPressed: () {
                            setState(() => widget.row.selectedReasons.removeAt(rIdx));
                            widget.onChanged();
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Remove reason',
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
class _UpdateSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? headerTrailing;

  _UpdateSectionCard({
    required this.title,
    required this.icon,
    required this.children,
    this.headerTrailing,
  });

  @override
  Widget build(BuildContext context) {
    return material.Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? context.colors.surfaceDark.withOpacity(0.5)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: context.colors.primaryGold),
              const Gap(10),
              Text(
                title.toUpperCase(),
                style: material.TextStyle(
                  color: context.colors.primaryGold,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              if (headerTrailing != null) ...[
                const Spacer(),
                headerTrailing!,
              ],
            ],
          ),
          const Gap(16),
          Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1) const Gap(10),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
