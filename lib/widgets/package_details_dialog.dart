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
          width: 900, // Widened to fit columns
          decoration: BoxDecoration(
            color: context.colors.cardDark,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 40, offset: const Offset(0, 15)),
              if (isDark) BoxShadow(color: context.colors.primaryGold.withOpacity(0.1), blurRadius: 20, spreadRadius: -5),
            ],
            border: Border.all(color: context.colors.primaryGold.withOpacity(isDark ? 0.3 : 0.6), width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min, // Hug content, no scrolling if small
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              material.Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [context.colors.surfaceDark, context.colors.cardDark]
                        : [context.colors.customsBlue, context.colors.customsBlueDark],
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
                  border: Border(bottom: BorderSide(color: context.colors.primaryGold.withOpacity(0.5))),
                ),
                child: Row(
                  children: [
                    material.Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: iconBgColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: context.colors.primaryGold.withOpacity(0.3)),
                      ),
                      child: Icon(Icons.inventory_2_rounded, color: context.colors.primaryGold, size: 24),
                    ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
                    const Gap(16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('SR REGISTER ENTRY', style: material.TextStyle(color: context.colors.primaryGold, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
                              const Gap(8),
                              if (p.status == 'returned')
                                material.Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: context.colors.successGreen.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                                  child: Text('RETURNED', style: material.TextStyle(color: context.colors.successGreen, fontSize: 9, fontWeight: FontWeight.bold)),
                                ),
                            ],
                          ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
                          Text(p.srNumber, style: material.TextStyle(color: headerTextColor, fontSize: 22, letterSpacing: 0.5, fontWeight: FontWeight.bold)).animate().fadeIn(duration: 400.ms, delay: 150.ms).slideX(begin: -0.1),
                        ],
                      ),
                    ),
                    _StatusBadge(status: p.status).animate().fadeIn(duration: 400.ms, delay: 200.ms),
                    const Gap(16),
                    IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close_rounded, color: headerTextColor.withOpacity(0.7)), splashRadius: 20),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: _GlassCard(
                              child: Column(
                                children: [
                                  _ModernDetailRow(label: 'Consignee', value: p.consigneeName, subValue: p.consigneeNic != null && p.consigneeNic!.isNotEmpty ? 'NIC: ${p.consigneeNic}' : null, icon: Icons.person_rounded),
                                  const Gap(8),
                                  _ModernDetailRow(label: 'Declarant', value: p.declarantName ?? 'N/A', icon: Icons.business_rounded),
                                  const Gap(8),
                                  _ModernDetailRow(label: 'Origin', value: p.originCountry, icon: Icons.public_rounded),
                                ],
                              ),
                            ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 100.ms).fadeIn(),
                          ),
                          const Gap(16),
                          Expanded(
                            flex: 2,
                            child: _GlassCard(
                              child: Column(
                                children: [
                                  _ModernDetailRow(label: 'Value', value: 'LKR ${NumberFormat('#,##0').format(p.declaredValue)}', icon: Icons.payments_rounded, color: context.colors.successGreen),
                                  const Gap(8),
                                  _ModernDetailRow(label: 'Weight', value: '${p.weightKg} kg', icon: Icons.scale_rounded),
                                  const Gap(8),
                                  _ModernDetailRow(label: 'Entry Date', value: p.entryDate != null ? DateFormat('dd MMM yyyy').format(p.entryDate!) : 'N/A', icon: Icons.calendar_month_rounded),
                                ],
                              ),
                            ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 200.ms).fadeIn(),
                          ),
                        ],
                      ),
                      const Gap(16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _SectionHeader('Package Items', Icons.list_alt_rounded),
                                const Gap(8),
                                if (p.items.isNotEmpty)
                                  material.Container(
                                    constraints: const BoxConstraints(maxHeight: 180),
                                    child: ListView.separated(
                                      shrinkWrap: true,
                                      physics: const ClampingScrollPhysics(),
                                      itemCount: p.items.length,
                                      separatorBuilder: (_, __) => const Gap(6),
                                      itemBuilder: (context, index) => _ItemTile(item: p.items[index]).animate().slideY(begin: 0.2, duration: 300.ms, delay: (250 + (index * 50)).ms).fadeIn(),
                                    ),
                                  )
                                else
                                  Text('No items specified', style: material.TextStyle(color: context.colors.textMuted, fontSize: 13, fontStyle: FontStyle.italic)),
                              ],
                            ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 300.ms).fadeIn(),
                          ),
                          const Gap(20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _SectionHeader('Tracking Details', Icons.qr_code_rounded),
                                const Gap(8),
                                _CompactInfoRow('Cusdec No', p.cusdecNo ?? 'N/A'),
                                _CompactInfoRow('Cusdec Date', p.cusdecDate ?? 'N/A'),
                                _CompactInfoRow('Officer', officerDisplay),
                                if (p.consigneePhone != null && p.consigneePhone!.isNotEmpty) _CompactInfoRow('Contact', p.consigneePhone!),
                                
                                if (p.warehouseEntries.isNotEmpty) ...[
                                  const Gap(16),
                                  _SectionHeader('Warehouse History', Icons.warehouse_rounded),
                                  const Gap(8),
                                  material.Container(
                                    constraints: const BoxConstraints(maxHeight: 100),
                                    child: ListView(
                                      shrinkWrap: true,
                                      children: p.warehouseEntries.map((we) => _HistorySummaryTile(entry: we, rate: widget.storageRate)).toList()
                                    ),
                                  )
                                ],
                              ],
                            ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 400.ms).fadeIn(),
                          ),
                        ],
                      ),
                      if ((p.description != null && p.description!.isNotEmpty) || (p.notes != null && p.notes!.isNotEmpty)) ...[
                        const Gap(16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (p.description != null && p.description!.isNotEmpty)
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _SectionHeader('Description', Icons.description_rounded).animate().fadeIn(delay: 450.ms),
                                    const Gap(8),
                                    _ModernNoteBox(text: p.description!).animate().slideY(begin: 0.1, delay: 500.ms).fadeIn(),
                                  ],
                                ),
                              ),
                            if (p.description != null && p.description!.isNotEmpty && p.notes != null && p.notes!.isNotEmpty) const Gap(16),
                            if (p.notes != null && p.notes!.isNotEmpty)
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _SectionHeader('Officer Notes', Icons.note_alt_rounded).animate().fadeIn(delay: 550.ms),
                                    const Gap(8),
                                    _ModernNoteBox(text: p.notes!, isWarning: true).animate().slideY(begin: 0.1, delay: 600.ms).fadeIn(),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              material.Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: context.colors.borderColor)),
                  color: isDark ? Colors.black26 : Colors.grey.shade50,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(19)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: Text('Close', style: material.TextStyle(color: context.colors.textMuted))),
                    const Gap(12),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final result = await showDialog(context: context, builder: (context) => _PackageUpdateDialog(package: p));
                        if (result == true && context.mounted) Navigator.pop(context, true);
                      },
                      icon: const Icon(Icons.edit_rounded, size: 16),
                      label: const Text('Edit Details', style: material.TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(backgroundColor: context.colors.primaryGold, foregroundColor: Colors.black87, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    ).animate().scale(delay: 400.ms, duration: 300.ms),
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

class _SectionHeader extends StatelessWidget {
  final String title; final IconData icon;
  const _SectionHeader(this.title, this.icon);
  @override
  Widget build(BuildContext context) {
    return Row(children: [ Icon(icon, size: 16, color: context.colors.primaryGold), const Gap(8), Text(title.toUpperCase(), style: material.TextStyle(color: context.colors.primaryGold, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)) ]);
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});
  @override
  Widget build(BuildContext context) {
    return material.Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: context.colors.textPrimary.withOpacity(0.02), borderRadius: BorderRadius.circular(12), border: Border.all(color: context.colors.textPrimary.withOpacity(0.06))),
      child: child,
    );
  }
}

class _ItemTile extends StatelessWidget {
  final PackageItem item;
  const _ItemTile({required this.item});
  @override
  Widget build(BuildContext context) {
    return material.Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: context.colors.textPrimary.withOpacity(0.03), borderRadius: BorderRadius.circular(10), border: Border.all(color: context.colors.borderColor.withOpacity(0.5))),
      child: Row(
        children: [
          material.Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: context.colors.primaryGold.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Icon(Icons.shopping_bag_outlined, color: context.colors.primaryGold, size: 16)),
          const Gap(10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ Text(item.itemName, style: material.TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)), if (item.category != null) Text(item.category!, style: material.TextStyle(color: context.colors.textMuted, fontSize: 11)) ])),
          Text('x${item.quantity}', style: material.TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.w900, fontSize: 14)),
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
  final String label; final String value; final String? subValue; final IconData icon; final Color? color;
  const _ModernDetailRow({required this.label, required this.value, this.subValue, required this.icon, this.color});
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: color ?? context.colors.textMuted), const Gap(10),
        Expanded(child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            SizedBox(width: 80, child: Text(label, style: material.TextStyle(color: context.colors.textMuted, fontSize: 11, fontWeight: FontWeight.bold))),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: material.TextStyle(color: color ?? context.colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                if (subValue != null) Text(subValue!, style: material.TextStyle(color: context.colors.textMuted.withOpacity(0.8), fontSize: 10)),
              ],
            )),
          ],
        )),
      ],
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

  Widget _buildSection(String title, IconData icon, List<Widget> children, bool isDark) {
    return material.Container(
      margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: context.colors.textPrimary.withOpacity(0.015), borderRadius: BorderRadius.circular(12), border: Border.all(color: context.colors.textPrimary.withOpacity(0.06))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [ Icon(icon, size: 16, color: context.colors.primaryGold), const Gap(8), Text(title.toUpperCase(), style: material.TextStyle(color: context.colors.primaryGold, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)) ]),
        const Gap(16),
        ...children,
      ]),
    );
  }

  InputDecoration _getInputDeco(String label) {
    return InputDecoration(
      labelText: label, labelStyle: material.TextStyle(color: context.colors.textMuted, fontSize: 12),
      filled: true, fillColor: context.colors.textPrimary.withOpacity(0.02),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: context.colors.borderColor)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: context.colors.borderColor)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: context.colors.primaryGold, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), isDense: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      backgroundColor: Colors.transparent, insetPadding: const EdgeInsets.all(24),
      child: material.Container(
        width: 1000, constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.95), // Wider layout for columns
        decoration: BoxDecoration(color: context.colors.cardDark, borderRadius: BorderRadius.circular(20), border: Border.all(color: context.colors.primaryGold.withOpacity(0.3))),
        child: Column(
          children: [
            material.Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.colors.primaryGold.withOpacity(0.2))), color: context.colors.textPrimary.withOpacity(0.02), borderRadius: const BorderRadius.vertical(top: Radius.circular(19))),
              child: Row(children: [ 
                material.Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: context.colors.primaryGold.withOpacity(0.15), borderRadius: BorderRadius.circular(6)), child: Icon(Icons.edit_document, color: context.colors.primaryGold, size: 20)).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
                const Gap(12), Text('Update Package Details', style: material.TextStyle(color: context.colors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)).animate().fadeIn(delay: 100.ms).slideX(begin: -0.1), const Spacer(),
                IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close, color: context.colors.textSecondary, size: 20), splashRadius: 20)
              ])
            ),
            Expanded(
              child: Form(
                key: _formKey, 
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // LEFT COLUMN
                    Expanded(
                      flex: 1,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(children: [
                          _buildSection('Consignee & Declarant', Icons.person_rounded, [
                            Row(children: [
                              Expanded(child: TextFormField(controller: _srCtrl, decoration: _getInputDeco('SR Number *'), style: material.TextStyle(color: context.colors.textPrimary, fontSize: 13), validator: (v) => v!.isEmpty ? 'Required' : null)),
                              const Gap(12),
                              Expanded(child: TextFormField(controller: _declarantCtrl, decoration: _getInputDeco('Declarant Name'), style: material.TextStyle(color: context.colors.textPrimary, fontSize: 13))),
                            ]),
                            const Gap(12),
                            TextFormField(controller: _consigneeCtrl, decoration: _getInputDeco('Consignee Name *'), style: material.TextStyle(color: context.colors.textPrimary, fontSize: 13), validator: (v) => v!.isEmpty ? 'Required' : null),
                            const Gap(12),
                            Row(children: [
                              Expanded(child: TextFormField(controller: _nicCtrl, decoration: _getInputDeco('Consignee NIC'), style: material.TextStyle(color: context.colors.textPrimary, fontSize: 13))),
                              const Gap(12),
                              Expanded(child: TextFormField(controller: _phoneCtrl, decoration: _getInputDeco('Phone Number'), style: material.TextStyle(color: context.colors.textPrimary, fontSize: 13), keyboardType: TextInputType.phone)),
                            ]),
                          ], isDark).animate().slideY(begin: 0.1, duration: 400.ms, delay: 100.ms).fadeIn(),
                          
                          _buildSection('Documentation', Icons.description_rounded, [
                            Row(children: [
                              Expanded(child: TextFormField(controller: _cusdecCtrl, decoration: _getInputDeco('Cusdec No'), style: material.TextStyle(color: context.colors.textPrimary, fontSize: 13))),
                              const Gap(12),
                              Expanded(child: TextFormField(controller: _cusdecDateCtrl, decoration: _getInputDeco('Cusdec Date (YYYY-MM-DD)'), style: material.TextStyle(color: context.colors.textPrimary, fontSize: 13), inputFormatters: [_dateFormatter])),
                            ]),
                            const Gap(12),
                            Row(children: [
                              Expanded(child: TextFormField(controller: _valueCtrl, decoration: _getInputDeco('Declared Value (LKR)'), style: material.TextStyle(color: context.colors.textPrimary, fontSize: 13), keyboardType: TextInputType.number)),
                              const Gap(12),
                              Expanded(child: TextFormField(controller: _weightCtrl, decoration: _getInputDeco('Weight (kg)'), style: material.TextStyle(color: context.colors.textPrimary, fontSize: 13), keyboardType: TextInputType.number)),
                            ]),
                            const Gap(12),
                            TextFormField(controller: _originCtrl, decoration: _getInputDeco('Origin Country'), style: material.TextStyle(color: context.colors.textPrimary, fontSize: 13)),
                          ], isDark).animate().slideY(begin: 0.1, duration: 400.ms, delay: 200.ms).fadeIn(),

                          _buildSection('Notes', Icons.notes_rounded, [ 
                            TextFormField(controller: _notesCtrl, decoration: _getInputDeco('Additional Notes / Warning'), style: material.TextStyle(color: context.colors.textPrimary, fontSize: 13), maxLines: 2), 
                          ], isDark).animate().slideY(begin: 0.1, duration: 400.ms, delay: 300.ms).fadeIn(),
                        ]),
                      ),
                    ),
                    
                    // Vertical Divider
                    material.Container(width: 1, color: context.colors.borderColor),

                    // RIGHT COLUMN
                    Expanded(
                      flex: 1,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(children: [
                          _buildSection('Items', Icons.shopping_bag_rounded, [
                            ..._items.asMap().entries.map((e) => Padding(padding: const EdgeInsets.only(bottom: 8), child: _ItemUpdateRowWidget(row: e.value, index: e.key + 1, onRemove: _items.length > 1 ? () => setState(() => _items.removeAt(e.key)) : null))),
                            const Gap(8),
                            TextButton.icon(
                              onPressed: () => setState(() => _items.add(_ItemUpdateRow())), 
                              icon: const Icon(Icons.add_circle_outline, size: 16), label: const Text('Add Item', style: material.TextStyle(fontSize: 12)),
                              style: TextButton.styleFrom(foregroundColor: context.colors.primaryGold, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: context.colors.primaryGold.withOpacity(0.3)))),
                            ),
                          ], isDark).animate().slideY(begin: 0.1, duration: 400.ms, delay: 150.ms).fadeIn(),

                          if (_warehouses.isNotEmpty) _buildSection('Warehouse Location', Icons.warehouse_rounded, [
                            material.Container(
                              constraints: const BoxConstraints(maxHeight: 200),
                              child: Scrollbar(
                                thumbVisibility: true,
                                child: ListView(
                                  shrinkWrap: true,
                                  children: _warehouses.map((w) {
                                  final isSelected = _selectedWarehouse == w; final isCurrent = w.id == _currentEntry?.warehouseId;
                                  return Padding(padding: const EdgeInsets.only(bottom: 6, right: 8), child: InkWell(borderRadius: BorderRadius.circular(8), onTap: isCurrent ? null : () => setState(() => _selectedWarehouse = w), child: AnimatedContainer(duration: const Duration(milliseconds: 200), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: isCurrent ? context.colors.textPrimary.withOpacity(0.05) : (isSelected ? context.colors.primaryGold.withOpacity(0.1) : context.colors.textPrimary.withOpacity(0.02)), borderRadius: BorderRadius.circular(8), border: Border.all(color: isCurrent ? context.colors.textPrimary.withOpacity(0.1) : (isSelected ? context.colors.primaryGold : context.colors.borderColor), width: isSelected ? 1.5 : 1),), child: Row(children: [ Icon(Icons.warehouse_rounded, color: isCurrent ? context.colors.textMuted : (isSelected ? context.colors.primaryGold : context.colors.textSecondary), size: 16), const Gap(12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ Text(w.name, style: material.TextStyle(color: isCurrent ? context.colors.textMuted : (isSelected ? context.colors.primaryGold : context.colors.textPrimary), fontWeight: FontWeight.w600, fontSize: 13)), if (w.location != null) Text(w.location!, style: material.TextStyle(color: isCurrent ? context.colors.textMuted.withOpacity(0.6) : context.colors.textSecondary, fontSize: 11)), ])), if (isCurrent) material.Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: context.colors.textPrimary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text('Current', style: material.TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: context.colors.textMuted))) else if (isSelected) Icon(Icons.check_circle_rounded, color: context.colors.primaryGold, size: 18), ]), ), ), );
                                }).toList()),
                              ),
                            ),
                          ], isDark).animate().slideY(begin: 0.1, duration: 400.ms, delay: 250.ms).fadeIn(),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            material.Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: context.colors.borderColor)), color: isDark ? Colors.black26 : Colors.grey.shade50, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(19))),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => Navigator.pop(context), style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14)), child: Text('Cancel', style: material.TextStyle(color: context.colors.textSecondary, fontWeight: FontWeight.bold, fontSize: 13))),
                const Gap(12),
                ElevatedButton(
                  onPressed: _isSaving ? null : _save, 
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14), backgroundColor: context.colors.primaryGold, foregroundColor: Colors.black87, elevation: 1, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), 
                  child: _isSaving 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black87)) 
                    : Row(mainAxisSize: MainAxisSize.min, children: [ const Icon(Icons.save_rounded, size: 16), const Gap(8), Text('Save Changes', style: material.TextStyle(fontWeight: FontWeight.bold, fontSize: 13)) ])
                ).animate().scale(delay: 400.ms, duration: 300.ms),
              ]),
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
              value: row.categoryCtrl.text.isEmpty ? null : row.categoryCtrl.text,
              items: categoriesList.map((c) => DropdownMenuItem(value: c, child: Text(c, style: material.TextStyle(color: context.colors.textPrimary, fontSize: 12)))).toList(),
              onChanged: (val) { if (val != null) row.categoryCtrl.text = val; },
              decoration: const InputDecoration(border: OutlineInputBorder(borderSide: BorderSide.none), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0)),
              dropdownColor: context.colors.cardDark,
              hint: Text('Category', style: material.TextStyle(color: context.colors.textMuted, fontSize: 11)),
              icon: Icon(Icons.expand_more_rounded, color: context.colors.textMuted, size: 16),
            ),
          )),
        ]),
      ]),
    );
  }
}
