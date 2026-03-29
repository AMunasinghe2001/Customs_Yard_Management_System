import re
import sys

def patch_file():
    with open('lib/widgets/package_details_dialog.dart', 'r', encoding='utf-8') as f:
        content = f.read()

    # Replacements:
    # 1. replace _ItemRow definition inside package_details_dialog.dart
    old_item_row = '''class _ItemRow {
  final nameCtrl = TextEditingController();
  final qtyCtrl = TextEditingController(text: '1');
  final valueCtrl = TextEditingController(text: '0');
  final categoryCtrl = TextEditingController();
}'''
    
    new_item_row = '''class _ItemRow {
  final nameCtrl = TextEditingController();
  final qtyCtrl = TextEditingController(text: '1');
  final unitOfMeasureCtrl = TextEditingController(text: 'Pieces');
  final unitOtherCtrl = TextEditingController();
  final valueCtrl = TextEditingController(text: '0');
  final categoryCtrl = TextEditingController();
  String status = 'pending';
  final List<String?> selectedReasons = [null];
}'''

    content = content.replace(old_item_row, new_item_row)

    # 2. replace _items initialization
    old_init = '''    // Initialize items
    _items = [];
    if (widget.highlightedItem != null) {
      // Show only the specific highlighted item if provided
      final row = _ItemRow();
      row.nameCtrl.text = widget.highlightedItem!.itemName;
      row.qtyCtrl.text = widget.highlightedItem!.quantity.toString();
      row.valueCtrl.text = widget.highlightedItem!.unitValue.toString();
      row.categoryCtrl.text = widget.highlightedItem!.category ?? '';
      _items.add(row);
    } else if (widget.package.items.isNotEmpty) {
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
    }'''

    new_init = '''    // Initialize items
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
      if (widget.highlightedItem!.reasons != null && widget.highlightedItem!.reasons!.isNotEmpty) {
        final rList = widget.highlightedItem!.reasons!.split(',').map((s) => s.strip() if hasattr(s, "strip") else s.trim()).toList() if False else widget.highlightedItem!.reasons!.split(', ').map((s) => s.trim()).toList();
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
    }'''
    # wait python syntax error in dart
    new_init = new_init.replace('if False else widget.highlightedItem!.reasons!.split(\', \').map((s) => s.trim()).toList()', '')
    new_init = new_init.replace('widget.highlightedItem!.reasons!.split(\',\').map((s) => s.strip() if hasattr(s, "strip") else s.trim()).toList()', "widget.highlightedItem!.reasons!.split(', ').map((s) => s.trim()).toList()")

    content = content.replace(old_init, new_init)

    # 3. replace _items dispose
    old_dispose = '''    for (final item in _items) {
      item.nameCtrl.dispose();
      item.qtyCtrl.dispose();
      item.valueCtrl.dispose();
      item.categoryCtrl.dispose();
    }'''

    new_dispose = '''    for (final item in _items) {
      item.nameCtrl.dispose();
      item.qtyCtrl.dispose();
      item.unitOfMeasureCtrl.dispose();
      item.unitOtherCtrl.dispose();
      item.valueCtrl.dispose();
      item.categoryCtrl.dispose();
    }'''

    content = content.replace(old_dispose, new_dispose)

    # 4. replace _updatePackage
    old_update = '''        itemsToUpsert = widget.package.items.map<PackageItem>((item) {
          if (item.id == widget.highlightedItem!.id) {
            final row = _items.first;
            return item.copyWith(
              itemName: row.nameCtrl.text,
              quantity: int.tryParse(row.qtyCtrl.text) ?? 1,
              unitValue: double.tryParse(row.valueCtrl.text) ?? 0,
              category: row.categoryCtrl.text,
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
        )).toList();
      }'''

    new_update = '''        itemsToUpsert = widget.package.items.map<PackageItem>((item) {
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
      }'''

    content = content.replace(old_update, new_update)

    # 5. Replace _UpdateItemRowWidgetState inside package_details_dialog.dart
    
    old_row_widget_state_start = '''class _UpdateItemRowWidgetState extends ConsumerState<_UpdateItemRowWidget> {
  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(packageCategoriesProvider);
    return material.Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration('''

    old_row_widget_state_code = content[content.find(old_row_widget_state_start) : content.find('class _UpdateSectionCard extends StatelessWidget {')]
    
    new_row_widget_state_code = '''class _UpdateItemRowWidgetState extends ConsumerState<_UpdateItemRowWidget> {
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
                  items: ['pending', 'held', 'cleared', 'confiscated'].map((s) => DropdownMenuItem(value: s, child: Text(s.toUpperCase(), style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
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
'''
    content = content.replace(old_row_widget_state_code, new_row_widget_state_code)
    
    with open('lib/widgets/package_details_dialog.dart', 'w', encoding='utf-8') as f:
        f.write(content)
        
patch_file()
