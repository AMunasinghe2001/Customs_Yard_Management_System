import re

with open('lib/screens/inspection/inspection_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Make ItemRowWidget uses TextFormField with validators
row_class_match = re.search(r'class _ItemRowWidgetState extends ConsumerState<_ItemRowWidget> \{[\s\S]*?\}\n\}', content)
if row_class_match:
    new_row_class = '''class _ItemRowWidgetState extends ConsumerState<_ItemRowWidget> {
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
          const Spacer(),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () {
              setState(() => widget.row.isProhibited = !widget.row.isProhibited);
              widget.onChanged();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  widget.row.isProhibited ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                  color: widget.row.isProhibited ? context.colors.dangerRed : context.colors.textMuted,
                  size: 20,
                ),
                const Gap(8),
                Text('Mark as Prohibited', style: TextStyle(color: widget.row.isProhibited ? context.colors.dangerRed : context.colors.textPrimary, fontSize: 13, fontWeight: widget.row.isProhibited ? FontWeight.w600 : FontWeight.normal)),
              ]),
            ),
          )
        ]),
      ]),
    );
  }
}'''
    content = content.replace(row_class_match.group(0), new_row_class)

    with open('lib/screens/inspection/inspection_screen.dart', 'w', encoding='utf-8') as f:
        f.write(content)
    print('UI patch complete')
else:
    print('Could not find row_class_match')
