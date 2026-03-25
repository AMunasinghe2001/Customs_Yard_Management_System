import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:uuid/uuid.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../services/services.dart';
import '../../models/models.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/error_view.dart';
import '../../widgets/custom_dropdown.dart';
import '../../widgets/warehouse_selection_dialog.dart';
import '../../core/supabase_client.dart';

class InspectionScreen extends ConsumerStatefulWidget {
  const InspectionScreen({super.key});
  @override
  ConsumerState<InspectionScreen> createState() => _InspectionScreenState();
}

class _InspectionScreenState extends ConsumerState<InspectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _srNumberCtrl = TextEditingController();
  final _originCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _consigneeCtrl = TextEditingController();
  final _consigneeNicCtrl = TextEditingController();
  final _consigneePhoneCtrl = TextEditingController();
  final _declarantCtrl = TextEditingController();
  final _cusdecCtrl = TextEditingController();
  final _cusdecDateCtrl = TextEditingController();
  final _entryDateCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _reasonCtrlMain = TextEditingController();
  final _notesCtrl = TextEditingController();

  final _dateMask = MaskTextInputFormatter(
    mask: '####-##-##', 
    filter: {"#": RegExp(r'[0-9]')},
    type: MaskAutoCompletionType.lazy,
  );
  
  final _srMask = MaskTextInputFormatter(
    mask: '## #/SR/##/####',
    filter: {
      "#": RegExp(r'[0-9]'),
      "A": RegExp(r'[A-Za-z]'),
    },
    type: MaskAutoCompletionType.lazy,
  );

  String _statusValue = 'pending';
  final List<_ItemRow> _items = [_ItemRow()];

  bool _isChecking = false;
  bool _isLookingUp = false;
  bool? _passed;
  List<String> _violations = [];
  String? _savedPackageId;
  String? _suggestedWarehouseId;
  bool _isUpdate = false;
  
  // Temporary storage for package data before warehouse confirmation
  PackageModel? _tempPackageData;
  List<PackageItem>? _tempPackageItems;

  /// Fetch an existing package by SR number and populate the form
  Future<void> _loadBySrNumber() async {
    final sr = _srNumberCtrl.text.trim();
    if (sr.isEmpty) return;
    setState(() => _isLookingUp = true);
    try {
      final pkg = await ref.read(packageServiceProvider).getPackageBySrNumber(sr);
      if (pkg == null) {
        setState(() => _isUpdate = false);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('SR "$sr" not found – filling as new entry.'),
              backgroundColor: context.colors.customsBlue));
        return;
      }
      _originCtrl.text = pkg.originCountry ?? '';
      _valueCtrl.text = pkg.declaredValue?.toString() ?? '';
      _weightCtrl.text = pkg.weightKg?.toString() ?? '';
      _consigneeCtrl.text = pkg.consigneeName;
      _consigneeNicCtrl.text = pkg.consigneeNic ?? '';
      _consigneePhoneCtrl.text = pkg.consigneePhone ?? '';
      _declarantCtrl.text = pkg.declarantName ?? '';
      _cusdecCtrl.text = pkg.cusdecNo ?? '';
      _cusdecDateCtrl.text = pkg.cusdecDate ?? '';
      _entryDateCtrl.text = pkg.entryDate != null
          ? '${pkg.entryDate!.year}-${pkg.entryDate!.month.toString().padLeft(2,'0')}-${pkg.entryDate!.day.toString().padLeft(2,'0')}'
          : '';
      _descCtrl.text = pkg.description ?? '';
      _reasonCtrlMain.text = pkg.reason ?? '';
      _notesCtrl.text = pkg.notes ?? '';
      setState(() {
        _statusValue = (pkg.status == 'detained' || pkg.status == 'forfeited') ? 'held' : pkg.status;
        _isUpdate = true;
        _items.clear();
        if (pkg.items != null && pkg.items!.isNotEmpty) {
          for (final item in pkg.items!) {
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
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('SR "$sr" loaded – you can edit and save.'),
            backgroundColor: context.colors.successGreen));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lookup error: $e'), backgroundColor: context.colors.dangerRed));
    } finally {
      setState(() => _isLookingUp = false);
    }
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

  @override
  void dispose() {
    _srNumberCtrl.dispose(); _originCtrl.dispose(); _valueCtrl.dispose();
    _weightCtrl.dispose(); _consigneeCtrl.dispose(); _consigneeNicCtrl.dispose();
    _consigneePhoneCtrl.dispose(); _declarantCtrl.dispose(); _cusdecCtrl.dispose();
    _cusdecDateCtrl.dispose(); _entryDateCtrl.dispose();
    _descCtrl.dispose(); _reasonCtrlMain.dispose(); _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkPackage() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isChecking = true; _passed = null; _violations = []; });
    try {
      final items = _items.where((r) => r.nameCtrl.text.isNotEmpty).map((r) => PackageItem(
        id: '', packageId: '', itemName: r.nameCtrl.text,
        quantity: int.tryParse(r.qtyCtrl.text) ?? 1,
        unitValue: double.tryParse(r.valueCtrl.text) ?? 0,
        category: r.categoryCtrl.text,
      )).toList();

      final violations = await ref.read(customsRulesServiceProvider).checkPackageAgainstRules(
        declaredValue: double.tryParse(_valueCtrl.text) ?? 0,
        weightKg: double.tryParse(_weightCtrl.text) ?? 0,
        itemCount: items.fold(0, (sum, i) => sum + i.quantity),
        items: items,
      );

      final pkg = PackageModel(
        id: '', srNumber: _srNumberCtrl.text.trim(),
        originCountry: _originCtrl.text.trim(),
        declaredValue: double.tryParse(_valueCtrl.text) ?? 0,
        weightKg: double.tryParse(_weightCtrl.text) ?? 0,
        totalItemCount: items.fold(0, (sum, i) => sum + i.quantity),
        description: _descCtrl.text, consigneeName: _consigneeCtrl.text.trim(),
        consigneeNic: _consigneeNicCtrl.text, consigneePhone: _consigneePhoneCtrl.text,
        declarantName: _declarantCtrl.text.trim(),
        cusdecNo: _cusdecCtrl.text.trim(),
        cusdecDate: _cusdecDateCtrl.text.trim(),
        entryDate: _entryDateCtrl.text.isNotEmpty ? DateTime.tryParse(_entryDateCtrl.text) : null,
        reason: _reasonCtrlMain.text.trim(),
        status: _statusValue,
        notes: _notesCtrl.text,
        inspectedBy: supabase.auth.currentUser?.id,
        inspectedAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      
      // Store temporarily - don't save to database yet
      _tempPackageData = pkg;
      _tempPackageItems = items;
      
      String? suggestedWh;
      final cats = ref.read(packageCategoriesProvider).value;
      if (cats != null) {
        for (var item in items) {
          final matched = cats.where((c) => c.name == item.category).firstOrNull;
          if (matched != null && matched.targetWarehouseId != null) {
            suggestedWh = matched.targetWarehouseId;
            break;
          }
        }
      }
      
      setState(() { 
        _passed = violations.isEmpty; 
        _violations = violations; 
        _suggestedWarehouseId = suggestedWh;
        _savedPackageId = null; // Clear any previous package ID
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: context.colors.dangerRed));
    } finally {
      setState(() => _isChecking = false);
    }
  }

  void _reset() {
    _formKey.currentState?.reset();
    _srNumberCtrl.clear();
    _originCtrl.clear(); _valueCtrl.clear(); _weightCtrl.clear();
    _consigneeCtrl.clear(); _consigneeNicCtrl.clear(); _consigneePhoneCtrl.clear();
    _declarantCtrl.clear(); _cusdecCtrl.clear(); _cusdecDateCtrl.clear(); _entryDateCtrl.clear();
    _descCtrl.clear(); _reasonCtrlMain.clear(); _notesCtrl.clear();
    _tempPackageData = null;
    _tempPackageItems = null;
    setState(() { _statusValue = 'pending'; _items.clear(); _items.add(_ItemRow()); _passed = null; _violations = []; _savedPackageId = null; _suggestedWarehouseId = null; });
  }

  String _formatWarehouseName(String name) {
    // Extract warehouse number from names like "SR Warehouse 03" -> "Warehouse 3"
    final regex = RegExp(r'(\d+)');
    final match = regex.firstMatch(name);
    if (match != null) {
      final number = int.tryParse(match.group(1)!);
      if (number != null) {
        return 'Warehouse $number';
      }
    }
    return name;
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      currentRoute: '/inspection',
      child: Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 6,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Package Inspection', style: Theme.of(context).textTheme.headlineLarge),
                          Text('Enter incoming package details for customs clearance check',
                              style: TextStyle(color: context.colors.textSecondary)),
                        ],
                      ).animate().fadeIn(),
                      const Gap(28),
                      _SectionCard(title: 'SR Register Information', icon: Icons.inventory_2_rounded, children: [
                        if (_isUpdate)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: context.colors.primaryGold.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: context.colors.primaryGold.withOpacity(0.4)),
                            ),
                            child: Row(children: [
                              Icon(Icons.edit_rounded, color: context.colors.primaryGold, size: 16),
                              const Gap(8),
                              Text('Editing existing SR entry – changes will update the record.',
                                  style: TextStyle(color: context.colors.primaryGold, fontSize: 13)),
                            ]),
                          ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _srNumberCtrl,
                                inputFormatters: [
                                  MaskTextInputFormatter(
                                    mask: 'AA #/SR/##/####', // Expect GL 1/SR/01/2025
                                    filter: {"#": RegExp(r'[0-9]'), "A": RegExp(r'[A-Za-z]')},
                                    type: MaskAutoCompletionType.lazy,
                                  )
                                ],
                                decoration: InputDecoration(
                                  labelText: 'SR Number *',
                                  hintText: 'e.g. GL 1/SR/01/2025',
                                  suffixIcon: IconButton(
                                    icon: _isLookingUp
                                      ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.primaryGold))
                                      : Icon(Icons.search_rounded, color: context.colors.primaryGold),
                                    onPressed: _isLookingUp ? null : _loadBySrNumber,
                                  ),
                                ),
                                validator: (v) => v!.isEmpty ? 'Required' : null,
                                onFieldSubmitted: (_) => _loadBySrNumber(),
                              ),
                            ),
                            const Gap(16),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: ['pending', 'held', 'cleared', 'confiscated'].contains(_statusValue) ? _statusValue : 'pending',
                                decoration: const InputDecoration(labelText: 'Status *'),
                                items: ['pending', 'held', 'cleared', 'confiscated']
                                    .map((s) => DropdownMenuItem(value: s, child: Text(s.toUpperCase()))).toList(),
                                onChanged: (v) => setState(() => _statusValue = v!),
                              ),
                            ),
                          ],
                        ),
                        const Gap(16),
                        Row(children: [
                          Expanded(child: TextFormField(controller: _declarantCtrl,
                              decoration: const InputDecoration(labelText: 'Declarant Name *'),
                              validator: (v) => v!.isEmpty ? 'Required' : null)),
                          const Gap(12),
                          Expanded(child: TextFormField(controller: _entryDateCtrl,
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
                                final reg = RegExp(r'^\d{4}-\d{2}-\d{2}$');
                                if (!reg.hasMatch(v)) return 'Use YYYY-MM-DD format';
                                return null;
                              })),
                        ]),
                        const Gap(16),
                        Row(children: [
                          Expanded(child: TextFormField(controller: _cusdecCtrl,
                              decoration: const InputDecoration(labelText: 'Cusdec No *'),
                              validator: (v) => v!.isEmpty ? 'Required' : null)),
                          const Gap(12),
                          Expanded(child: TextFormField(controller: _cusdecDateCtrl,
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
                                final reg = RegExp(r'^\d{4}-\d{2}-\d{2}$');
                                if (!reg.hasMatch(v)) return 'Use YYYY-MM-DD format';
                                return null;
                              })),
                        ]),
                        const Gap(16),
                        if (['held', 'confiscated'].contains(_statusValue))
                          ref.watch(holdReasonsProvider).when(
                            loading: () => const LinearProgressIndicator(),
                            error: (e, _) => Text('Error loading reasons: $e', style: TextStyle(color: context.colors.dangerRed, fontSize: 12)),
                              data: (list) {
                                final activeList = list.where((r) => r.isActive || r.reasonText == _reasonCtrlMain.text).toList();
                                return DropdownButtonFormField<String>(
                                  value: activeList.any((r) => r.reasonText == _reasonCtrlMain.text) ? _reasonCtrlMain.text : null,
                                  decoration: const InputDecoration(labelText: 'Reason *'),
                                  items: activeList.map((r) => DropdownMenuItem(value: r.reasonText, child: Text(r.reasonText))).toList(),
                                  onChanged: (v) => setState(() => _reasonCtrlMain.text = v ?? ''),
                                  validator: (v) => ['held', 'confiscated'].contains(_statusValue) && (v == null || v.isEmpty) ? 'Reason is required when status is held/confiscated' : null,
                                );
                              },
                          ),
                        const Gap(16),
                        TextFormField(controller: _descCtrl,
                            decoration: const InputDecoration(labelText: 'Package Description'), maxLines: 2),
                      ]).animate().slideY(begin: 0.1, duration: 400.ms, delay: 100.ms).fadeIn(),
                      const Gap(16),
                      _SectionCard(title: 'Consignee Information', icon: Icons.person_rounded, children: [
                        Row(children: [
                          Expanded(child: TextFormField(controller: _consigneeCtrl,
                              decoration: const InputDecoration(labelText: 'Consignee Name *'),
                              validator: (v) => v!.isEmpty ? 'Required' : null)),
                          const Gap(12),
                          Expanded(child: TextFormField(controller: _consigneeNicCtrl,
                              decoration: const InputDecoration(labelText: 'NIC Number'))),
                        ]),
                        const Gap(16),
                        TextFormField(controller: _consigneePhoneCtrl,
                            decoration: const InputDecoration(labelText: 'Phone Number (10 digits)'),
                            keyboardType: TextInputType.phone,
                            validator: (v) {
                              if (v != null && v.isNotEmpty && !RegExp(r'^\d{10}$').hasMatch(v)) {
                                return 'Must be exactly 10 digits';
                              }
                              return null;
                            }),
                      ]).animate().slideY(begin: 0.1, duration: 400.ms, delay: 200.ms).fadeIn(),
                      const Gap(16),
                      _SectionCard(
                        title: 'Package Items', icon: Icons.list_alt_rounded,
                        headerTrailing: TextButton.icon(
                          icon: const Icon(Icons.add, size: 16), label: const Text('Add Item'),
                          onPressed: () => setState(() => _items.add(_ItemRow())),
                        ),
                        children: List.generate(_items.length, (i) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ItemRowWidget(
                            row: _items[i], index: i + 1,
                            onRemove: _items.length > 1 ? () => setState(() => _items.removeAt(i)) : null,
                            onChanged: () => setState(() {}),
                          ),
                        )),
                      ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 300.ms).fadeIn(),
                      const Gap(16),
                      _SectionCard(
                        title: 'Additional Info (Optional)', icon: Icons.info_outline_rounded,
                        children: [
                          Row(children: [
                            Expanded(child: TextFormField(controller: _valueCtrl,
                                decoration: const InputDecoration(labelText: 'Declared Value (LKR)'),
                                keyboardType: TextInputType.number)),
                            const Gap(12),
                            Expanded(child: TextFormField(controller: _weightCtrl,
                                decoration: const InputDecoration(labelText: 'Weight (kg)'),
                                keyboardType: TextInputType.number)),
                            const Gap(12),
                            Expanded(child: TextFormField(controller: _originCtrl,
                                decoration: const InputDecoration(labelText: 'Origin Country'))),
                          ]),
                        ],
                      ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 400.ms).fadeIn(),
                      const Gap(16),
                      _SectionCard(title: 'Officer Notes', icon: Icons.note_rounded, children: [
                        TextFormField(controller: _notesCtrl,
                            decoration: const InputDecoration(hintText: 'Additional inspection notes...'),
                            maxLines: 3),
                      ]).animate().slideY(begin: 0.1, duration: 400.ms, delay: 500.ms).fadeIn(),
                      const Gap(24),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(height: 52,
                              child: ElevatedButton.icon(
                                icon: _isChecking
                                    ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.primaryNavy))
                                    : const Icon(Icons.save_rounded),
                                label: Text(_isChecking ? 'Saving...' : (_isUpdate ? 'Update SR Entry' : 'Save SR Entry')),
                                onPressed: _isChecking ? null : _checkPackage,
                              ),
                            ),
                          ),
                          const Gap(12),
                          OutlinedButton(onPressed: _reset, child: const Text('Reset')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_passed != null)
              Expanded(flex: 4, child: _ResultPanel(
                passed: _passed!, violations: _violations,
                suggestedWarehouseId: _suggestedWarehouseId,
                tempPackageData: _tempPackageData,
                tempPackageItems: _tempPackageItems,
                onReset: _reset,
              )),
          ],
        ),
      ),
    );
  }
}

// ── Result Panel ───────────────────────────────────────────────

class _ResultPanel extends ConsumerStatefulWidget {
  final bool passed;
  final List<String> violations;
  final String? suggestedWarehouseId;
  final PackageModel? tempPackageData;
  final List<PackageItem>? tempPackageItems;
  final VoidCallback onReset;
  const _ResultPanel({super.key, required this.passed, required this.violations, this.suggestedWarehouseId, this.tempPackageData, this.tempPackageItems, required this.onReset});
  @override
  ConsumerState<_ResultPanel> createState() => _ResultPanelState();
}

class _ResultPanelState extends ConsumerState<_ResultPanel> {
  String? _selectedWarehouseId;
  bool _isSending = false;
  bool _warehouseSent = false;

  @override
  void initState() {
    super.initState();
    if (widget.suggestedWarehouseId != null) {
      _selectedWarehouseId = widget.suggestedWarehouseId;
    }
  }

  @override
  void didUpdateWidget(_ResultPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.suggestedWarehouseId != oldWidget.suggestedWarehouseId && widget.suggestedWarehouseId != null) {
      setState(() {
        _selectedWarehouseId = widget.suggestedWarehouseId;
      });
    }
  }

  String _formatWarehouseName(String name) {
    final regex = RegExp(r'(\d+)');
    final match = regex.firstMatch(name);
    if (match != null) {
      final number = int.tryParse(match.group(1)!);
      if (number != null) {
        return 'Warehouse $number';
      }
    }
    return name;
  }

  Future<void> _sendToWarehouse() async {
    if (_selectedWarehouseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select a warehouse')));
      return;
    }
    
    if (widget.tempPackageData == null || widget.tempPackageItems == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Package data not found')));
      return;
    }
    
    setState(() => _isSending = true);
    try {
      // First save the package to database
      final saved = await ref.read(packageServiceProvider).upsertPackage(
        widget.tempPackageData!,
        widget.tempPackageItems!,
      );
      
      // Then add to warehouse
      await ref.read(warehouseServiceProvider).addEntry(
        packageId: saved.id,
        warehouseId: _selectedWarehouseId!,
        holdReason: 'System Assigned',
        itemCount: 1,
      );
      
      if (mounted) {
        setState(() => _warehouseSent = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('✅ Package sent to warehouse'), backgroundColor: context.colors.successGreen));
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            widget.onReset();
          }
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: context.colors.dangerRed));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final warehouses = ref.watch(warehousesProvider);
    return Container(
      height: double.infinity,
      decoration: BoxDecoration(border: Border(left: BorderSide(color: context.colors.borderColor))),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Inspection Result', style: Theme.of(context).textTheme.titleLarge),
            const Gap(20),
            if (_warehouseSent)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: context.colors.successGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: context.colors.successGreen.withOpacity(0.5),
                    width: 2,
                  ),
                ),
                child: Column(children: [
                  Icon(Icons.check_circle_rounded, color: context.colors.successGreen, size: 56).animate().scale(duration: 400.ms),
                  const Gap(12),
                  Text('ENTRY SAVED SUCCESSFULLY',
                    style: TextStyle(
                      color: context.colors.successGreen,
                      fontWeight: FontWeight.w800, fontSize: 18,
                    ), textAlign: TextAlign.center,
                  ).animate().slideY(begin: 0.3, duration: 300.ms, delay: 200.ms),
                  if (!widget.passed) ...[
                    const Gap(8),
                    Text('Customs Rule Violations Detected',
                      style: TextStyle(color: context.colors.warningAmber, fontWeight: FontWeight.w600, fontSize: 13)),
                  ],
                ]),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: context.colors.primaryGold.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: context.colors.primaryGold.withOpacity(0.5),
                    width: 2,
                  ),
                ),
                child: Column(children: [
                  Icon(Icons.warehouse, color: context.colors.primaryGold, size: 56).animate().scale(duration: 400.ms),
                  const Gap(12),
                  Text('SELECT WAREHOUSE TO COMPLETE',
                    style: TextStyle(
                      color: context.colors.primaryGold,
                      fontWeight: FontWeight.w800, fontSize: 18,
                    ), textAlign: TextAlign.center,
                  ).animate().slideY(begin: 0.3, duration: 300.ms, delay: 200.ms),
                  const Gap(8),
                  Text('Warehouse assignment is required to finalize the entry.',
                    style: TextStyle(color: context.colors.textSecondary, fontSize: 13)),
                ]),
              ),
            const Gap(20),
            if (!widget.passed) ...[
              Text('Violations', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: context.colors.dangerRed)),
              const Gap(8),
              ...widget.violations.map((v) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.colors.dangerRed.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.colors.dangerRed.withOpacity(0.25)),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.warning_amber_rounded, color: context.colors.warningAmber, size: 16),
                    const Gap(8),
                    Expanded(child: Text(v, style: TextStyle(color: context.colors.textSecondary, fontSize: 13))),
                  ]),
                ),
              )),
              const Gap(20),
            ],
            Text('Assign to Warehouse', style: Theme.of(context).textTheme.titleMedium),
            const Gap(4),
            Text('Select which warehouse should hold this package.',
                style: TextStyle(color: context.colors.textSecondary, fontSize: 13)),
            const Gap(12),
            warehouses.when(
              loading: () => const CircularProgressIndicator(),
              error: (e, _) => Text('Error: $e'),
              data: (ws) => Column(
                children: ws.map((w) {
                  final isSuggested = widget.suggestedWarehouseId == w.id;
                  final isOther = widget.suggestedWarehouseId != null && !isSuggested;
                  final isSelected = _selectedWarehouseId == w.id;
                  
                  return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: isOther ? null : () => setState(() => _selectedWarehouseId = w.id),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isOther ? context.colors.cardDark.withOpacity(0.5)
                            : (isSelected ? context.colors.primaryGold.withOpacity(0.15) : context.colors.cardDark),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? context.colors.primaryGold : (isOther ? context.colors.borderColor.withOpacity(0.3) : context.colors.borderColor),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(children: [
                        Icon(Icons.warehouse_rounded,
                            color: isOther ? context.colors.textMuted.withOpacity(0.3)
                                : (isSelected ? context.colors.primaryGold : context.colors.textMuted), size: 20),
                        const Gap(12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            _formatWarehouseName(w.name), 
                            style: TextStyle(
                              color: isOther ? context.colors.textMuted.withOpacity(0.5)
                                  : (isSelected ? context.colors.primaryGold : context.colors.textPrimary),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (w.location != null)
                            Text(w.location!, style: TextStyle(color: isOther ? context.colors.textMuted.withOpacity(0.3) : context.colors.textMuted, fontSize: 12)),
                        ])),
                        if (isSelected)
                          Icon(Icons.check_circle, color: context.colors.primaryGold, size: 20),
                        if (isSuggested)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: context.colors.primaryGold.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: context.colors.primaryGold.withOpacity(0.3)),
                            ),
                            child: Text('Suggested', style: TextStyle(color: context.colors.primaryGold, fontSize: 10, fontWeight: FontWeight.w600)),
                          ),
                      ]),
                    ),
                  ),
                );}).toList(),
              ),
            ),
            const Gap(20),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: context.colors.heldOrange, foregroundColor: Colors.white),
                icon: _isSending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.warehouse_rounded),
                label: Text(_isSending ? 'Sending...' : 'Send to Warehouse'),
                onPressed: _isSending ? null : _sendToWarehouse,
              ),
            ),
            const Gap(12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add_box_rounded, size: 18),
                label: const Text('New SR Entry'),
                onPressed: widget.onReset,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Helper Widgets ───

class _ItemRow {
  final nameCtrl = TextEditingController();
  final qtyCtrl = TextEditingController(text: '1');
  final valueCtrl = TextEditingController(text: '0');
  final categoryCtrl = TextEditingController();
}

class _ItemRowWidget extends ConsumerStatefulWidget {
  final _ItemRow row; final int index; final VoidCallback? onRemove; final VoidCallback onChanged;
  const _ItemRowWidget({required this.row, required this.index, this.onRemove, required this.onChanged});
  @override ConsumerState<_ItemRowWidget> createState() => _ItemRowWidgetState();
}

class _ItemRowWidgetState extends ConsumerState<_ItemRowWidget> {
  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(packageCategoriesProvider);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: context.colors.surfaceDark, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.borderColor), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0,2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: context.colors.primaryGold.withOpacity(0.2), borderRadius: BorderRadius.circular(6)), child: Text('Item ${widget.index}', style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.w700, fontSize: 12))),
          const Spacer(),
          if (widget.onRemove != null)
            IconButton(icon: Icon(Icons.delete_outline_rounded, size: 20, color: context.colors.dangerRed),
                onPressed: widget.onRemove, padding: EdgeInsets.zero, constraints: const BoxConstraints(), tooltip: 'Remove item'),
        ]),
        const Gap(12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextFormField(controller: widget.row.nameCtrl,
                  decoration: const InputDecoration(labelText: 'Item Name *', isDense: true),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                  onChanged: (_) => widget.onChanged()),
            ),
            const Gap(12),
            Expanded(
              flex: 1,
              child: TextFormField(controller: widget.row.qtyCtrl,
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
                error: (e, _) => IconButton(icon: const Icon(Icons.refresh, size: 16, color: Colors.orange),
                    onPressed: () => ref.refresh(packageCategoriesProvider), tooltip: 'Error loading categories'),
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
        const Gap(12),
        Row(children: [
          categories.when(
            data: (list) {
              final cat = list.where((c) => c.name == widget.row.categoryCtrl.text).firstOrNull;
              if (cat != null && cat.targetWarehouseId != null) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: context.colors.primaryGold.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: context.colors.primaryGold.withOpacity(0.3))
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.route_rounded, size: 14, color: context.colors.primaryGold),
                    const Gap(6),
                    Text('Routes to: ${cat.targetWarehouseId ?? ''}', 
                      style: TextStyle(color: context.colors.primaryGold, fontSize: 11, fontWeight: FontWeight.w600)
                    )
                  ]),
                );
              }
              return const SizedBox.shrink();
            },
            loading: () => const SizedBox.shrink(),
            error: (_,__) => const SizedBox.shrink()
          ),

        ]),
      ]),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title; final IconData icon; final List<Widget> children; final Widget? headerTrailing;
  const _SectionCard({required this.title, required this.icon, required this.children, this.headerTrailing});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: context.colors.cardDark, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.colors.borderColor)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: context.colors.primaryGold, size: 18),
          const Gap(10),
          Text(title, style: TextStyle(color: context.colors.primaryGold, fontWeight: FontWeight.w700, fontSize: 14)),
          const Spacer(),
          if (headerTrailing != null) headerTrailing!,
        ]),
        const Gap(16),
        ...children,
      ]),
    );
  }
}
