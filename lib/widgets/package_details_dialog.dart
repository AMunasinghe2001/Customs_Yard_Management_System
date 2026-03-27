import 'package:flutter/material.dart' as material;
import 'package:flutter/material.dart' show Colors, Icons, Theme, FontWeight, BorderRadius, Radius, BoxConstraints, BoxShadow, Offset, Border, BorderSide, IconButton, ElevatedButton, CircularProgressIndicator, ScaffoldMessenger, SnackBar, showDatePicker, showDialog, BuildContext, Widget, Row, Column, Expanded, Icon, Text, Padding, EdgeInsets, Center, SingleChildScrollView, Form, GlobalKey, FormState, TextFormField, InputDecoration, DropdownButtonFormField, DropdownMenuItem, SizedBox, Brightness, Color, IconData, Dialog, Tween, TweenAnimationBuilder, Transform, Opacity, Curves, MainAxisSize, CrossAxisAlignment, BoxDecoration, StatelessWidget, LinearGradient, Flexible, Navigator, MainAxisAlignment, TextButton, BoxShape, FontStyle, TextStyle, Container, OutlinedButton, TextEditingController, MediaQuery, TextInputType, VoidCallback, Spacer, TextOverflow, StatefulWidget;
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
    final headerTextColor = Colors.white;

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
                    _StatusBadge(status: p.status).animate().fadeIn(duration: 400.ms, delay: 200.ms),
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
                      // Recipient & Source Section
                      _DetailSection(
                        title: 'Recipient & Source',
                        icon: Icons.person_pin_rounded,
                        delay: 100,
                        child: Column(
                          children: [
                            _DetailItem(
                              icon: Icons.person_rounded,
                              label: 'Consignee',
                              value: p.consigneeName,
                              subValue: (p.consigneeNic != null && p.consigneeNic!.isNotEmpty) ? 'NIC: ${p.consigneeNic}' : null,
                            ),
                            _DetailItem(
                              icon: Icons.business_rounded,
                              label: 'Declarant',
                              value: p.declarantName ?? 'N/A',
                            ),
                            _DetailItem(
                              icon: Icons.public_rounded,
                              label: 'Origin Country',
                              value: p.originCountry,
                            ),
                          ],
                        ),
                      ),

                      // Valuation & Specs Section
                      _DetailSection(
                        title: 'Valuation & Specifications',
                        icon: Icons.gavel_rounded,
                        delay: 200,
                        child: Column(
                          children: [
                            _DetailItem(
                              icon: Icons.payments_rounded,
                              label: 'Declared Value',
                              value: 'LKR ${NumberFormat('#,##0').format(p.declaredValue)}',
                              valueColor: context.colors.successGreen,
                            ),
                            _DetailItem(
                              icon: Icons.scale_rounded,
                              label: 'Total Weight',
                              value: '${p.weightKg} kg',
                            ),
                            _DetailItem(
                              icon: Icons.calendar_month_rounded,
                              label: 'Entry Date',
                              value: p.entryDate != null ? DateFormat('dd MMM yyyy').format(p.entryDate!) : 'N/A',
                            ),
                          ],
                        ),
                      ),

                      // Cargo Contents Section
                      _DetailSection(
                        title: 'Cargo Contents',
                        icon: Icons.shopping_bag_rounded,
                        delay: 300,
                        child: Column(
                          children: p.items.isNotEmpty
                              ? p.items.asMap().entries.map((e) => _CargoItemTile(item: e.value, index: e.key)).toList()
                              : [_EmptyState(message: 'No items specified')],
                        ),
                      ),

                      // Documentation & Tracking Section
                      _DetailSection(
                        title: 'Documentation & Tracking',
                        icon: Icons.folder_open_rounded,
                        delay: 400,
                        child: Column(
                          children: [
                            _DetailItem(
                              icon: Icons.receipt_long_rounded,
                              label: 'Case Number',
                                value: p.caseNumber ?? 'N/A',
                              ),
                              _DetailItem(
                                icon: Icons.receipt_long_rounded,
                                label: 'Cusdec Number',
                              value: p.cusdecNo ?? 'N/A',
                            ),
                            _DetailItem(
                              icon: Icons.date_range_rounded,
                              label: 'Cusdec Date',
                              value: p.cusdecDate ?? 'N/A',
                            ),
                            if (p.consigneePhone != null && p.consigneePhone!.isNotEmpty)
                              _DetailItem(
                                icon: Icons.phone_rounded,
                                label: 'Declarant Phone',
                                value: p.consigneePhone!,
                              ),
                          ],
                        ),
                      ),

                      // System Entry By Section
                      _SystemEntrySection(
                        officerDisplay: officerDisplay,
                        badgeNumber: displayBadgeNumber,
                        delay: 500,
                      ),

                      // Warehouse History Section
                      if (p.warehouseEntries.isNotEmpty)
                        _DetailSection(
                          title: 'Warehouse History',
                          icon: Icons.location_on_rounded,
                          delay: 600,
                          child: Column(
                            children: p.warehouseEntries
                                .asMap()
                                .entries
                                .map((e) => _WarehouseHistoryTile(entry: e.value, index: e.key, rate: widget.storageRate))
                                .toList(),
                          ),
                        ),

                      // Reason Section
                      if (p.reason != null && p.reason!.isNotEmpty)
                        _DetailSection(
                          title: 'Reason',
                          icon: Icons.priority_high_rounded,
                          delay: 650,
                          child: _NoteDisplay(
                            text: p.reason!,
                            isWarning: true,
                            icon: Icons.info_outline_rounded,
                          ),
                        ),

                      // Description Section
                      if (p.description != null && p.description!.isNotEmpty)
                        _DetailSection(
                          title: 'Description',
                          icon: Icons.description_rounded,
                          delay: 700,
                          child: _NoteDisplay(
                            text: p.description!,
                            icon: Icons.notes_rounded,
                          ),
                        ),

                      // Internal Notes Section
                      if (p.notes != null && p.notes!.isNotEmpty)
                        _DetailSection(
                          title: 'Internal Notes',
                          icon: Icons.warning_rounded,
                          delay: 800,
                          child: _NoteDisplay(
                            text: p.notes!,
                            isWarning: true,
                            icon: Icons.warning_amber_rounded,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              material.Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : Colors.grey.shade50,
                  border: Border(top: BorderSide(color: context.colors.borderColor)),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(23)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Update Button - Disabled for officers
                    material.Tooltip(
                      message: isOfficer ? 'Package updates are restricted to administrators only' : '',
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.edit_rounded, size: 16),
                        label: const Text('Update'),
                        onPressed: isOfficer ? null : () {
                          showDialog(
                            context: context,
                            builder: (_) => PackageUpdateDialog(package: p, storageRate: widget.storageRate),
                          );
                        },
                      ),
                    ),
                    // Close Window Button
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Close Window', style: material.TextStyle(color: context.colors.textMuted, fontWeight: FontWeight.bold)),
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
  final WarehouseEntryModel entry;
  final int index;
  final double rate;

  const _WarehouseHistoryTile({required this.entry, required this.index, required this.rate});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: material.Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.textPrimary.withOpacity(0.02),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.borderColor.withOpacity(0.5)),
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
                      Text(entry.holdReason, style: material.TextStyle(color: context.colors.textMuted, fontSize: 10)),
                    ],
                  ),
                ),
                if (entry.isReturned)
                  material.Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: context.colors.successGreen.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('RELEASED', style: material.TextStyle(color: context.colors.successGreen, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const Gap(2),
            Text(
              'In: ${DateFormat('dd MMM').format(entry.admittedAt)}${entry.returnedAt != null ? " � Out: ${DateFormat('dd MMM').format(entry.returnedAt!)}" : ""}',
              style: material.TextStyle(color: context.colors.textMuted, fontSize: 10),
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

  const _SystemEntrySection({required this.officerDisplay, this.badgeNumber, required this.delay});

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
                child: Icon(Icons.verified_user_rounded, size: 16, color: context.colors.primaryGold),
              ),
              const Gap(10),
              Text(
                'System Entry By'.toUpperCase(),
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
  final double storageRate;

  const PackageUpdateDialog({
    super.key,
    required this.package,
    required this.storageRate,
  });

  @override
  ConsumerState<PackageUpdateDialog> createState() => _PackageUpdateDialogState();
}

class _ItemRow {
  final nameCtrl = TextEditingController();
  final qtyCtrl = TextEditingController(text: '1');
  final valueCtrl = TextEditingController(text: '0');
  final categoryCtrl = TextEditingController();
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
    if (widget.package.items.isNotEmpty) {
      for (final item in widget.package.items) {
        final row = _ItemRow();
        row.nameCtrl.text = item.itemName;
        row.qtyCtrl.text = item.quantity.toString();
        row.valueCtrl.text = item.unitValue.toString();
        row.categoryCtrl.text = item.category ?? '';
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
    _descCtrl.dispose();
    _notesCtrl.dispose();
    _reasonCtrl.dispose();
    _valueCtrl.dispose();
    _weightCtrl.dispose();
    _originCtrl.dispose();
    for (final item in _items) {
      item.nameCtrl.dispose();
      item.qtyCtrl.dispose();
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
      final items = _items.where((r) => r.nameCtrl.text.isNotEmpty).map((r) => PackageItem(
        id: '',
        packageId: '',
        itemName: r.nameCtrl.text,
        quantity: int.tryParse(r.qtyCtrl.text) ?? 1,
        unitValue: double.tryParse(r.valueCtrl.text) ?? 0,
        category: r.categoryCtrl.text,
      )).toList();

      final updatedPackage = widget.package.copyWith(
        consigneeName: _consigneeCtrl.text.trim(),
        consigneeNic: _consigneeNicCtrl.text.trim(),
        consigneePhone: _consigneePhoneCtrl.text.trim(),
        declarantName: _declarantCtrl.text.trim(),
        cusdecNo: _cusdecCtrl.text.trim(),
        cusdecDate: _cusdecDateCtrl.text.trim(),
        entryDate: _entryDateCtrl.text.isNotEmpty ? DateTime.tryParse(_entryDateCtrl.text) : null,
        description: _descCtrl.text.trim(),
        reason: _reasonCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
        declaredValue: double.tryParse(_valueCtrl.text.trim()) ?? 0,
        weightKg: double.tryParse(_weightCtrl.text.trim()) ?? 0,
        originCountry: _originCtrl.text.trim(),
        status: _statusValue,
      );

      await ref.read(packageServiceProvider).upsertPackage(updatedPackage, items);

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
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    enabled: false,
                                    initialValue: widget.package.srNumber,
                                    decoration: const InputDecoration(labelText: 'SR Number'),
                                  ),
                                ),
                                const Gap(12),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: _statusValue,
                                    decoration: const InputDecoration(labelText: 'Status *'),
                                    items: ['pending', 'held', 'cleared', 'confiscated']
                                        .map((s) => DropdownMenuItem(value: s, child: Text(s.toUpperCase())))
                                        .toList(),
                                    onChanged: (v) => setState(() => _statusValue = v!),
                                  ),
                                ),
                              ],
                            ),
                            
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _declarantCtrl,
                                    decoration: const InputDecoration(labelText: 'Declarant Name *'),
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
                                    controller: _cusdecCtrl,
                                    decoration: const InputDecoration(labelText: 'Cusdec No *'),
                                    validator: (v) => v!.isEmpty ? 'Required' : null,
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
                            
                            ref.watch(holdReasonsProvider).when(
                              data: (reasons) {
                                final activeList = reasons.where((r) => r.isActive || r.reasonText == _reasonCtrl.text).toList();
                                String? currentValue = _reasonCtrl.text.isNotEmpty ? _reasonCtrl.text : null;
                                if (currentValue != null && !activeList.any((r) => r.reasonText == currentValue)) {
                                  currentValue = null;
                                }
                                return DropdownButtonFormField<String>(
                                  decoration: const InputDecoration(labelText: 'Reason'),
                                  value: currentValue,
                                  isExpanded: true,
                                  items: activeList.map((r) => DropdownMenuItem(
                                    value: r.reasonText,
                                    child: Text(r.reasonText, overflow: TextOverflow.ellipsis),
                                  )).toList(),
                                  onChanged: (v) {
                                    if (v != null) {
                                      setState(() {
                                        _reasonCtrl.text = v;
                                      });
                                    }
                                  },
                                );
                              },
                              loading: () => const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator())),
                              error: (_, __) => TextFormField(
                                controller: _reasonCtrl,
                                decoration: const InputDecoration(labelText: 'Reason (Manual Entry)'),
                              ),
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
                                    controller: _consigneeNicCtrl,
                                    decoration: const InputDecoration(labelText: 'NIC Number'),
                                  ),
                                ),
                              ],
                            ),
                            
                            TextFormField(
                              controller: _consigneePhoneCtrl,
                              decoration: const InputDecoration(labelText: 'Phone Number'),
                              keyboardType: TextInputType.phone,
                              validator: (v) {
                                if (v != null && v.isNotEmpty && !RegExp(r'^\d{10}$').hasMatch(v)) {
                                  return 'Must be exactly 10 digits';
                                }
                                return null;
                              },
                            ),
                          ],
                        ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 200.ms),
                        const Gap(16),
                        // Package Items Section
                        _UpdateSectionCard(
                          title: 'Package Items',
                          icon: Icons.shopping_bag_rounded,
                          headerTrailing: TextButton.icon(
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
                                  index: i + 1,
                                  onRemove: _items.length > 1 ? () => setState(() => _items.removeAt(i)) : null,
                                  onChanged: () => setState(() {}),
                                ),
                              )),
                            ),
                          ],
                        ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 300.ms),
                        const Gap(16),
                        // Additional Information Section
                        _UpdateSectionCard(
                          title: 'Additional Information',
                          icon: Icons.info_outline_rounded,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _valueCtrl,
                                    decoration: const InputDecoration(labelText: 'Declared Value (LKR)'),
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                                const Gap(12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _weightCtrl,
                                    decoration: const InputDecoration(labelText: 'Weight (kg)'),
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                                const Gap(12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _originCtrl,
                                    decoration: const InputDecoration(labelText: 'Origin Country'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 400.ms),
                        const Gap(16),
                        // Notes Section
                        _UpdateSectionCard(
                          title: 'Officer Notes',
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
                child: Text('Item ${widget.index}', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.w700, fontSize: 12)),
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
                  decoration: const InputDecoration(labelText: 'Qty *', isDense: true),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (int.tryParse(v) == null || int.tryParse(v)! <= 0) return 'Invalid';
                    return null;
                  },
                ),
              ),
              const Gap(12),
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
                      items: list.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis))).toList(),
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
