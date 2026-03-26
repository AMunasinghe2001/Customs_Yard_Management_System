import 'package:flutter/material.dart' as material;
import 'package:flutter/material.dart' show Colors, Icons, Theme, FontWeight, BorderRadius, Radius, BoxConstraints, BoxShadow, Offset, Border, BorderSide, LinearGradient, Divider, IconButton, TextButton, ElevatedButton, CircularProgressIndicator, ScaffoldMessenger, SnackBar, DatePickerTheme, showDatePicker, showDialog, BuildContext, Widget, Row, Column, Expanded, Icon, Text, Padding, EdgeInsets, Center, SingleChildScrollView, Form, GlobalKey, FormState, TextFormField, InputDecoration, OutlineInputBorder, DropdownButtonFormField, DropdownMenuItem, InkWell, AnimatedContainer, BoxShape, Spacer, Stack, Positioned, ClipRRect, MediaQuery, Navigator, Curves, Tween, TweenAnimationBuilder, Transform, Opacity, Flexible, MainAxisSize, CrossAxisAlignment, MainAxisAlignment, ScrollPhysics, ClampingScrollPhysics, ListView, FontStyle, Brightness, Color, IconData, VoidCallback, TextAlign, TextInputType, AsyncValue, Dialog, TextEditingController, SizedBox, ConsumerStatefulWidget, ConsumerState, ConsumerWidget, WidgetRef, RoundedRectangleBorder, Alignment, State, Image, ImageProvider, NetworkImage, AssetImage, CircleAvatar, Key, StatelessWidget, BoxDecoration, Scrollbar, TextBaseline;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import '../core/theme.dart';
import '../core/providers.dart';
import '../core/supabase_client.dart';
import '../models/models.dart';
import 'custom_dropdown.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/services.dart';

typedef CustomContainer = material.Container;
typedef CustomTextStyle = material.TextStyle;

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
    final headerTextColor = Colors.white; // Header is always dark/blue
    final iconBgColor = context.colors.primaryGold.withOpacity(0.15);

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
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: _InfoGroup(
                              title: 'Recipient & Source',
                              icon: Icons.person_pin_rounded,
                              children: [
                                _ModernDetailRow(
                                  label: 'Consignee',
                                  value: p.consigneeName,
                                  subValue: (p.consigneeNic != null && p.consigneeNic!.isNotEmpty) ? 'NIC: ${p.consigneeNic}' : null,
                                  icon: Icons.person_rounded,
                                ),
                                _ModernDetailRow(
                                  label: 'Declarant',
                                  value: p.declarantName ?? 'N/A',
                                  icon: Icons.business_rounded,
                                ),
                                _ModernDetailRow(
                                  label: 'Origin',
                                  value: p.originCountry,
                                  icon: Icons.public_rounded,
                                ),
                              ],
                            ),
                          ),
                          const Gap(20),
                          Expanded(
                            flex: 2,
                            child: _InfoGroup(
                              title: 'Valuation & Specs',
                              icon: Icons.gavel_rounded,
                              children: [
                                _ModernDetailRow(
                                  label: 'Declared Value',
                                  value: 'LKR ${NumberFormat('#,##0').format(p.declaredValue)}',
                                  icon: Icons.payments_rounded,
                                  color: context.colors.successGreen,
                                ),
                                _ModernDetailRow(
                                  label: 'Total Weight',
                                  value: '${p.weightKg} kg',
                                  icon: Icons.scale_rounded,
                                ),
                                _ModernDetailRow(
                                  label: 'Entry Date',
                                  value: p.entryDate != null ? DateFormat('dd MMM yyyy').format(p.entryDate!) : 'N/A',
                                  icon: Icons.calendar_month_rounded,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ).animate().fadeIn(duration: 400.ms, delay: 100.ms).slideY(begin: 0.05),
                      const Gap(20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _InfoGroup(
                              title: 'Cargo Contents',
                              icon: Icons.inventory_2_outlined,
                              children: [
                                if (p.items.isNotEmpty)
                                  ...p.items.map((item) => _ItemRow(item: item))
                                else
                                  _ModernNoteBox(text: 'No item breakdown provided.'),
                              ],
                            ),
                          ),
                          const Gap(20),
                          Expanded(
                            child: _InfoGroup(
                              title: 'Administration',
                              icon: Icons.admin_panel_settings_rounded,
                              children: [
                                _CompactInfoRow('Cusdec No', p.cusdecNo ?? 'N/A'),
                                _CompactInfoRow('Cusdec Date', p.cusdecDate ?? 'N/A'),
                                if (p.consigneePhone != null && p.consigneePhone!.isNotEmpty)
                                  _CompactInfoRow('Contact', p.consigneePhone!),
                                
                                const Gap(12),
                                material.Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: context.colors.textPrimary.withOpacity(0.03),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: context.colors.borderColor),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.person_outline_rounded, size: 14, color: context.colors.primaryGold),
                                          const Gap(8),
                                          Text(
                                            'SYSTEM ENTRY BY',
                                            style: material.TextStyle(
                                              color: context.colors.textMuted,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Gap(4),
                                      Text(
                                        officerDisplay,
                                        style: material.TextStyle(
                                          color: context.colors.textPrimary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                if (p.warehouseEntries.isNotEmpty) ...[
                                  const Divider(height: 24),
                                  Text('WAREHOUSE HISTORY', 
                                    style: material.TextStyle(color: context.colors.textMuted, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)
                                  ),
                                  const Gap(8),
                                  ...p.warehouseEntries.map((we) => _HistorySummaryTile(entry: we, rate: widget.storageRate)),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ).animate().fadeIn(duration: 400.ms, delay: 250.ms).slideY(begin: 0.05),
                      if ((p.description != null && p.description!.isNotEmpty) || (p.notes != null && p.notes!.isNotEmpty)) ...[
                        const Gap(20),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (p.description != null && p.description!.isNotEmpty)
                              Expanded(
                                child: _InfoGroup(
                                  title: 'Description',
                                  icon: Icons.description_rounded,
                                  children: [_ModernNoteBox(text: p.description!)],
                                ),
                              ),
                            if (p.description != null && p.description!.isNotEmpty && p.notes != null && p.notes!.isNotEmpty) const Gap(20),
                            if (p.notes != null && p.notes!.isNotEmpty)
                              Expanded(
                                child: _InfoGroup(
                                  title: 'Internal Notes',
                                  icon: Icons.feedback_rounded,
                                  children: [_ModernNoteBox(text: p.notes!, isWarning: true)],
                                ),
                              ),
                          ],
                        ).animate().fadeIn(duration: 400.ms, delay: 400.ms).slideY(begin: 0.05),
                      ],
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
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Close Window', style: material.TextStyle(color: context.colors.textMuted, fontWeight: FontWeight.bold)),
                    ),
                    const Gap(16),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final result = await showDialog(context: context, builder: (context) => _PackageUpdateDialog(package: p));
                        if (result == true && context.mounted) Navigator.pop(context, true);
                      },
                      icon: const Icon(Icons.edit_rounded, size: 16),
                      label: const Text('Edit Details', style: material.TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.colors.primaryGold,
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
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

class _HistorySummaryTile extends StatelessWidget {
  final WarehouseEntryModel entry; final double rate;
  const _HistorySummaryTile({required this.entry, required this.rate});
  @override
  Widget build(BuildContext context) {
    return material.Container(
      margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: context.colors.textPrimary.withOpacity(0.04), borderRadius: BorderRadius.circular(8), border: Border.all(color: context.colors.borderColor.withOpacity(0.5))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on_rounded, size: 12, color: context.colors.primaryGold), const Gap(6),
              Expanded(child: Text(entry.warehouseName, style: material.TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.bold, fontSize: 12))),
              if (entry.isReturned)
                material.Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: context.colors.successGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(4)), child: Text('RELEASED', style: material.TextStyle(color: context.colors.successGreen, fontSize: 8, fontWeight: FontWeight.bold))),
            ],
          ),
          const Gap(4),
          Text('In: ${DateFormat('dd MMM').format(entry.admittedAt)}${entry.returnedAt != null ? "  Out: ${DateFormat('dd MMM').format(entry.returnedAt!)}" : ""}', style: material.TextStyle(color: context.colors.textMuted, fontSize: 10)),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});
  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase(); final isPending = s.contains('pending'); final isInspected = s.contains('inspected');
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

class _InfoGroup extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _InfoGroup({required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    return material.Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark 
            ? context.colors.surfaceDark.withOpacity(0.3) 
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
                Icon(icon, size: 16, color: context.colors.primaryGold),
                const Gap(10),
                Text(
                  title.toUpperCase(),
                  style: material.TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: children.asMap().entries.map((entry) => Padding(
                padding: EdgeInsets.only(bottom: entry.key == children.length - 1 ? 0 : 12),
                child: entry.value,
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final PackageItem item;
  const _ItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return material.Container(
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
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.shopping_bag_outlined, size: 14, color: context.colors.primaryGold),
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
    );
  }
}

class _ModernNoteBox extends StatelessWidget {
  final String text; final bool isWarning;
  const _ModernNoteBox({required this.text, this.isWarning = false});
  @override
  Widget build(BuildContext context) {
    final color = isWarning ? context.colors.primaryGold : context.colors.textMuted;
    return material.Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(10), border: Border(left: BorderSide(color: color.withOpacity(0.5), width: 3))),
      child: Text(text, style: material.TextStyle(color: context.colors.textPrimary.withOpacity(0.8), fontSize: 12, height: 1.4)),
    );
  }
}

class _ModernDetailRow extends StatelessWidget {
  final String label; 
  final String value; 
  final String? subValue; 
  final IconData icon; 
  final Color? color;

  const _ModernDetailRow({
    required this.label, 
    required this.value, 
    this.subValue, 
    required this.icon, 
    this.color
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return material.Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.textPrimary.withOpacity(0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.textPrimary.withOpacity(0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          material.Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (color ?? context.colors.primaryGold).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color ?? context.colors.primaryGold),
          ),
          const Gap(16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: material.TextStyle(
                    color: context.colors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const Gap(2),
                Text(
                  value,
                  style: material.TextStyle(
                    color: color ?? context.colors.textPrimary,
                    fontSize: 14,
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
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactInfoRow extends StatelessWidget {
  final String label; final String value;
  const _CompactInfoRow(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ Text(label, style: material.TextStyle(color: context.colors.textMuted, fontSize: 11)), Text(value, style: material.TextStyle(color: context.colors.textPrimary.withOpacity(0.8), fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.right) ]),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final bool isDark;
  final Widget? trailing;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
    required this.isDark,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return material.Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: isDark ? context.colors.surfaceDark.withOpacity(0.4) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark 
              ? context.colors.primaryGold.withOpacity(0.15)
              : context.colors.customsBlue.withOpacity(0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          material.Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark 
                  ? context.colors.primaryGold.withOpacity(0.08)
                  : context.colors.customsBlue.withOpacity(0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(
                bottom: BorderSide(
                  color: isDark 
                      ? context.colors.primaryGold.withOpacity(0.2)
                      : context.colors.customsBlue.withOpacity(0.1),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: isDark ? context.colors.primaryGold : context.colors.customsBlue),
                const Gap(12),
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: material.TextStyle(
                      color: isDark ? context.colors.primaryGold : context.colors.customsBlue,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _PackageUpdateDialog extends ConsumerStatefulWidget {
  final PackageModel package;
  const _PackageUpdateDialog({required this.package});
  @override
  ConsumerState<_PackageUpdateDialog> createState() => _PackageUpdateDialogState();
}

class _PackageUpdateDialogState extends ConsumerState<_PackageUpdateDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _srCtrl; late TextEditingController _consigneeCtrl; late TextEditingController _nicCtrl; late TextEditingController _phoneCtrl; late TextEditingController _valueCtrl; late TextEditingController _weightCtrl; late TextEditingController _originCtrl; late TextEditingController _cusdecCtrl; late TextEditingController _cusdecDateCtrl; late TextEditingController _declarantCtrl; late TextEditingController _descCtrl; late TextEditingController _notesCtrl;
  final List<_ItemUpdateRow> _items = [];
  final _dateFormatter = MaskTextInputFormatter(mask: '####-##-##', filter: {"#": RegExp(r'[0-9]')});
  bool _isSaving = false;
  List<WarehouseModel> _warehouses = [];
  WarehouseModel? _selectedWarehouse;
  WarehouseEntryModel? _currentEntry;

  @override
  void initState() {
    super.initState();
    final p = widget.package;
    _srCtrl = TextEditingController(text: p.srNumber); _consigneeCtrl = TextEditingController(text: p.consigneeName); _nicCtrl = TextEditingController(text: p.consigneeNic); _phoneCtrl = TextEditingController(text: p.consigneePhone); _valueCtrl = TextEditingController(text: p.declaredValue.toString()); _weightCtrl = TextEditingController(text: p.weightKg.toString()); _originCtrl = TextEditingController(text: p.originCountry); _cusdecCtrl = TextEditingController(text: p.cusdecNo); _cusdecDateCtrl = TextEditingController(text: p.cusdecDate); _declarantCtrl = TextEditingController(text: p.declarantName); _descCtrl = TextEditingController(text: p.description); _notesCtrl = TextEditingController(text: p.notes);
    for (var it in p.items) { _items.add(_ItemUpdateRow(nameCtrl: TextEditingController(text: it.itemName), qtyCtrl: TextEditingController(text: it.quantity.toString()), categoryCtrl: TextEditingController(text: it.category))); }
    _loadWarehouses();
  }

  Future<void> _loadWarehouses() async {
    final res = await supabase.from('warehouses').select();
    _warehouses = (res as List).map((e) => WarehouseModel.fromJson(e)).toList();
    final entriesRes = await supabase.from('warehouse_entries').select().eq('package_id', widget.package.id).filter('returned_at', 'is', null);
    if ((entriesRes as List).isNotEmpty) { _currentEntry = WarehouseEntryModel.fromJson(entriesRes.first); }
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final updatedItems = _items.map((r) => PackageItem(id: '', packageId: widget.package.id, itemName: r.nameCtrl.text, quantity: int.tryParse(r.qtyCtrl.text) ?? 1, category: r.categoryCtrl.text.isEmpty ? null : r.categoryCtrl.text)).toList();
      final updatedPackage = widget.package.copyWith(srNumber: _srCtrl.text, consigneeName: _consigneeCtrl.text, consigneeNic: _nicCtrl.text, consigneePhone: _phoneCtrl.text, declaredValue: double.tryParse(_valueCtrl.text), weightKg: double.tryParse(_weightCtrl.text), originCountry: _originCtrl.text, cusdecNo: _cusdecCtrl.text, cusdecDate: _cusdecDateCtrl.text, declarantName: _declarantCtrl.text, description: _descCtrl.text, notes: _notesCtrl.text);
      await PackageService().upsertPackage(updatedPackage, updatedItems);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving: $e'), backgroundColor: context.colors.dangerRed));
    }
    if (mounted) setState(() => _isSaving = false);
  }

  Future<void> _selectDate(TextEditingController controller) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2050),
    );
    if (picked != null) {
      if (mounted) {
        setState(() {
          controller.text = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
        });
      }
    }
  }

  InputDecoration _getInputDeco({required String label, IconData? icon, VoidCallback? onIconPressed}) {
    return InputDecoration(
      labelText: label,
      labelStyle: material.TextStyle(color: context.colors.textMuted, fontSize: 13, fontWeight: FontWeight.w500),
      filled: true,
      fillColor: Theme.of(context).brightness == Brightness.dark 
          ? context.colors.surfaceDark.withOpacity(0.4) 
          : Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: context.colors.borderColor.withOpacity(0.5)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: context.colors.borderColor.withOpacity(0.5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: context.colors.primaryGold, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: context.colors.dangerRed, width: 1),
      ),
      suffixIcon: icon != null 
          ? IconButton(
              icon: Icon(icon, color: context.colors.primaryGold, size: 20),
              onPressed: onIconPressed,
            )
          : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      isDense: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: material.Container(
        width: 1000,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        decoration: BoxDecoration(
          color: context.colors.scaffoldBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.colors.primaryGold.withOpacity(0.4), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            material.Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [context.colors.surfaceDark, context.colors.cardDark]
                      : [context.colors.customsBlue, context.colors.customsBlueDark],
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(23)),
                border: Border(bottom: BorderSide(color: context.colors.primaryGold.withOpacity(0.5))),
              ),
              child: Row(
                children: [
                  material.Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.colors.primaryGold.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.colors.primaryGold.withOpacity(0.3)),
                    ),
                    child: Icon(Icons.edit_document, color: context.colors.primaryGold, size: 24),
                  ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
                  const Gap(20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Edit Package Record', 
                          style: material.TextStyle(color: context.colors.primaryGold, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 0.5)
                        ).animate().fadeIn(delay: 100.ms).slideX(begin: -0.1),
                        Text('Update information for SR: ${widget.package.srNumber}',
                          style: material.TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)
                        ).animate().fadeIn(delay: 200.ms),
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
            
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Form Controls Column
                      Expanded(
                        flex: 6,
                        child: Column(
                          children: [
                            _SectionCard(
                              title: 'Package Identity',
                              icon: Icons.inventory_2_rounded,
                              isDark: isDark,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _srCtrl,
                                        style: material.TextStyle(color: context.colors.textPrimary),
                                        decoration: _getInputDeco(label: 'SR Number *'),
                                        validator: (v) => v!.isEmpty ? 'Required' : null,
                                      ),
                                    ),
                                    const Gap(16),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _declarantCtrl,
                                        style: material.TextStyle(color: context.colors.textPrimary),
                                        decoration: _getInputDeco(label: 'Declarant Name'),
                                      ),
                                    ),
                                  ],
                                ),
                                const Gap(20),
                                TextFormField(
                                  controller: _consigneeCtrl,
                                  style: material.TextStyle(color: context.colors.textPrimary),
                                  decoration: _getInputDeco(label: 'Consignee Name *'),
                                  validator: (v) => v!.isEmpty ? 'Required' : null,
                                ),
                                const Gap(20),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _nicCtrl,
                                        style: material.TextStyle(color: context.colors.textPrimary),
                                        decoration: _getInputDeco(label: 'Consignee NIC'),
                                      ),
                                    ),
                                    const Gap(16),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _phoneCtrl,
                                        style: material.TextStyle(color: context.colors.textPrimary),
                                        decoration: _getInputDeco(label: 'Phone Number'),
                                        keyboardType: TextInputType.phone,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05),

                            _SectionCard(
                              title: 'Customs & Value',
                              icon: Icons.gavel_rounded,
                              isDark: isDark,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _cusdecCtrl,
                                        style: material.TextStyle(color: context.colors.textPrimary),
                                        decoration: _getInputDeco(label: 'Cusdec No'),
                                      ),
                                    ),
                                    const Gap(16),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _cusdecDateCtrl,
                                        style: material.TextStyle(color: context.colors.textPrimary),
                                        decoration: _getInputDeco(
                                          label: 'Cusdec Date',
                                          icon: Icons.calendar_month,
                                          onIconPressed: () => _selectDate(_cusdecDateCtrl),
                                        ),
                                        inputFormatters: [_dateFormatter],
                                      ),
                                    ),
                                  ],
                                ),
                                const Gap(20),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _valueCtrl,
                                        style: material.TextStyle(color: context.colors.textPrimary),
                                        decoration: _getInputDeco(label: 'Declared Value (LKR)'),
                                        keyboardType: TextInputType.number,
                                      ),
                                    ),
                                    const Gap(16),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _weightCtrl,
                                        style: material.TextStyle(color: context.colors.textPrimary),
                                        decoration: _getInputDeco(label: 'Weight (kg)'),
                                        keyboardType: TextInputType.number,
                                      ),
                                    ),
                                    const Gap(16),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _originCtrl,
                                        style: material.TextStyle(color: context.colors.textPrimary),
                                        decoration: _getInputDeco(label: 'Origin Country'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ).animate().fadeIn(duration: 400.ms, delay: 100.ms).slideY(begin: 0.05),

                            _SectionCard(
                              title: 'Package Items',
                              icon: Icons.shopping_bag_rounded,
                              isDark: isDark,
                              trailing: material.InkWell(
                                onTap: () => setState(() => _items.add(_ItemUpdateRow())),
                                borderRadius: BorderRadius.circular(20),
                                child: material.Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: context.colors.primaryGold.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.add, size: 14, color: context.colors.primaryGold),
                                      const Gap(4),
                                      Text(
                                        'Add Item',
                                        style: material.TextStyle(
                                          color: context.colors.primaryGold,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              children: [
                                ..._items.asMap().entries.map((e) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _ItemUpdateRowWidget(
                                    row: e.value,
                                    index: e.key + 1,
                                    onRemove: _items.length > 1 ? () => setState(() => _items.removeAt(e.key)) : null,
                                  ),
                                )),
                              ],
                            ).animate().fadeIn(duration: 400.ms, delay: 150.ms).slideY(begin: 0.05),

                            if (_warehouses.isNotEmpty)
                              _SectionCard(
                                title: 'Relocate Warehouse',
                                icon: Icons.warehouse_rounded,
                                isDark: isDark,
                                children: [
                                  material.Container(
                                    constraints: const BoxConstraints(maxHeight: 250),
                                    child: ListView.separated(
                                      shrinkWrap: true,
                                      itemCount: _warehouses.length,
                                      separatorBuilder: (_, __) => const Gap(8),
                                      itemBuilder: (context, index) {
                                        final w = _warehouses[index];
                                        final isSelected = _selectedWarehouse == w;
                                        final isCurrent = w.id == _currentEntry?.warehouseId;
                                        
                                        return InkWell(
                                          onTap: isCurrent ? null : () => setState(() => _selectedWarehouse = w),
                                          borderRadius: BorderRadius.circular(12),
                                          child: AnimatedContainer(
                                            duration: 200.ms,
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: isCurrent 
                                                  ? context.colors.textPrimary.withOpacity(0.04) 
                                                  : (isSelected ? context.colors.primaryGold.withOpacity(0.08) : Colors.transparent),
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(
                                                color: isSelected 
                                                    ? context.colors.primaryGold 
                                                    : context.colors.borderColor.withOpacity(0.4),
                                                width: isSelected ? 1.5 : 1,
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.warehouse_rounded,
                                                  color: isCurrent ? context.colors.textMuted : (isSelected ? context.colors.primaryGold : context.colors.textSecondary),
                                                  size: 20,
                                                ),
                                                const Gap(16),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(w.name, style: material.TextStyle(
                                                        color: isCurrent ? context.colors.textMuted : (isSelected ? context.colors.primaryGold : context.colors.textPrimary),
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 14,
                                                      )),
                                                      if (w.location != null)
                                                        Text(w.location!, style: material.TextStyle(color: context.colors.textMuted, fontSize: 11)),
                                                    ],
                                                  ),
                                                ),
                                                if (isCurrent)
                                                  material.Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                    decoration: BoxDecoration(color: context.colors.textMuted.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                                    child: Text('Current', style: material.TextStyle(color: context.colors.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
                                                  )
                                                else if (isSelected)
                                                  Icon(Icons.check_circle_rounded, color: context.colors.primaryGold, size: 22),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ).animate().fadeIn(duration: 400.ms, delay: 250.ms).slideY(begin: 0.05),

                            _SectionCard(
                              title: 'Additional Information',
                              icon: Icons.notes_rounded,
                              isDark: isDark,
                              children: [
                                TextFormField(
                                  controller: _descCtrl,
                                  maxLines: 2,
                                  style: material.TextStyle(color: context.colors.textPrimary),
                                  decoration: _getInputDeco(label: 'Package Description'),
                                ),
                                const Gap(16),
                                TextFormField(
                                  controller: _notesCtrl,
                                  maxLines: 2,
                                  style: material.TextStyle(color: context.colors.textPrimary),
                                  decoration: _getInputDeco(label: 'Internal Notes / Warnings'),
                                ),
                              ],
                            ).animate().fadeIn(duration: 400.ms, delay: 200.ms).slideY(begin: 0.05),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Footer
            material.Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: isDark ? Colors.black26 : Colors.grey.shade50,
                border: Border(top: BorderSide(color: context.colors.borderColor)),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(23)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('Discard Changes', 
                      style: material.TextStyle(
                        color: context.colors.textMuted, 
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      )
                    ),
                  ),
                  const Gap(12),
                  material.Container(
                    height: 44,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.colors.primaryGold,
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        elevation: 1,
                        shadowColor: context.colors.primaryGold.withOpacity(0.2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        textStyle: material.TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                      child: _isSaving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black87))
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.save_rounded, size: 18),
                                const Gap(8),
                                const Text('Update Record'),
                              ],
                            ),
                    ),
                  ).animate().scale(delay: 400.ms, duration: 300.ms, curve: Curves.easeOutBack),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemUpdateRow {
  final TextEditingController nameCtrl; final TextEditingController qtyCtrl; final TextEditingController categoryCtrl;
  _ItemUpdateRow({TextEditingController? nameCtrl, TextEditingController? qtyCtrl, TextEditingController? categoryCtrl,}) : nameCtrl = nameCtrl ?? TextEditingController(), qtyCtrl = qtyCtrl ?? TextEditingController(text: '1'), categoryCtrl = categoryCtrl ?? TextEditingController();
}

class _ItemUpdateRowWidget extends ConsumerWidget {
  final _ItemUpdateRow row; final int index; final VoidCallback? onRemove;
  const _ItemUpdateRowWidget({required this.row, required this.index, this.onRemove});
  
  InputDecoration _getSoftDeco(BuildContext context, String label) {
    return InputDecoration(
      labelText: label, labelStyle: material.TextStyle(color: context.colors.textMuted, fontSize: 11),
      filled: true, fillColor: context.colors.textPrimary.withOpacity(0.02),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: context.colors.borderColor)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: context.colors.borderColor)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: context.colors.primaryGold, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), isDense: true,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesValue = ref.watch(packageCategoriesProvider);
    final List<String> categoriesList = categoriesValue.maybeWhen(data: (list) => list.map((c) => c.name).toList(), orElse: () => []);

    return material.Container(
      padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: context.colors.textPrimary.withOpacity(0.01), borderRadius: BorderRadius.circular(8), border: Border.all(color: context.colors.borderColor)),
      child: Column(children: [
        Row(children: [ 
          material.Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: context.colors.primaryGold.withOpacity(0.1), borderRadius: BorderRadius.circular(4)), child: Text('Item $index', style: material.TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 0.5))), 
          const Spacer(), 
          if (onRemove != null) IconButton(onPressed: onRemove, icon: Icon(Icons.delete_outline_rounded, color: context.colors.dangerRed.withOpacity(0.8), size: 16), constraints: const BoxConstraints(), padding: EdgeInsets.zero, splashRadius: 16) 
        ]),
        const Gap(8),
        Row(children: [
          Expanded(flex: 3, child: TextFormField(controller: row.nameCtrl, decoration: _getSoftDeco(context, 'Name *'), style: material.TextStyle(color: context.colors.textPrimary, fontSize: 12), validator: (v) => v!.isEmpty ? 'Req' : null)),
          const Gap(8),
          Expanded(flex: 1, child: TextFormField(controller: row.qtyCtrl, decoration: _getSoftDeco(context, 'Qty *'), style: material.TextStyle(color: context.colors.textPrimary, fontSize: 12), keyboardType: TextInputType.number, validator: (v) => v!.isEmpty ? 'Req' : null)),
          const Gap(8),
          Expanded(flex: 3, child: material.Container(
            height: 38,
            decoration: BoxDecoration(color: context.colors.textPrimary.withOpacity(0.02), borderRadius: BorderRadius.circular(6), border: Border.all(color: context.colors.borderColor)),
            child: DropdownButtonFormField<String>(
              value: categoriesList.contains(row.categoryCtrl.text) ? row.categoryCtrl.text : null,
              items: categoriesList.map((c) => DropdownMenuItem(value: c, child: Text(c, style: material.TextStyle(color: context.colors.textPrimary, fontSize: 12)))).toList(),
              onChanged: (val) { if (val != null) row.categoryCtrl.text = val; },
              decoration: const InputDecoration(border: OutlineInputBorder(borderSide: BorderSide.none), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0)),
              dropdownColor: Theme.of(context).brightness == Brightness.dark ? context.colors.surfaceDark : Colors.white,
              icon: Icon(Icons.expand_more_rounded, color: context.colors.textMuted, size: 16),
            ),
          )),
        ]),
      ]),
    );
  }
}
