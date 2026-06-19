import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:data_table_2/data_table_2.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/services.dart';
import '../../widgets/empty_table_state.dart';
import '../../widgets/styled_form_dialog.dart';

final taxesProvider = FutureProvider<List<DisposalTaxModel>>((ref) async {
  return DisposalService().getTaxes();
});

final _taxSearchProvider = StateProvider<String>((ref) => '');

class TaxesTab extends ConsumerWidget {
  const TaxesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taxesAsync = ref.watch(taxesProvider);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Tax Configuration',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Spacer(),
              SizedBox(
                width: 260,
                child: TextField(
                  onChanged: (v) =>
                      ref.read(_taxSearchProvider.notifier).state = v,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search tax…',
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 11),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const Gap(12),
              ElevatedButton.icon(
                onPressed: () => _showTaxDialog(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Add Tax'),
              ),
            ],
          ),
          const Gap(16),
          Expanded(
            child: Card(
              child: taxesAsync.when(
                data: (taxes) {
                  final q = ref.watch(_taxSearchProvider).toLowerCase();
                  final filtered = q.isEmpty
                      ? taxes
                      : taxes
                          .where((t) => t.name.toLowerCase().contains(q))
                          .toList();
                  return _buildTable(context, ref, filtered);
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Center(child: Text('Error: $e')),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(
      BuildContext context, WidgetRef ref, List<DisposalTaxModel> taxes) {
    return DataTable2(
      empty: const EmptyTableState(message: 'No taxes configured'),
      columns: const [
        DataColumn2(label: Text('Name'), size: ColumnSize.L),
        DataColumn2(label: Text('Percentage (%)'), size: ColumnSize.S),
        DataColumn2(label: Text('Status'), size: ColumnSize.S),
        DataColumn2(label: Text('Actions'), size: ColumnSize.S),
      ],
      rows: taxes.map((tax) {
        return DataRow(cells: [
          DataCell(Text(tax.name)),
          DataCell(Text('${tax.percentage}%')),
          DataCell(
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: tax.isActive
                    ? Colors.green.withOpacity(0.1)
                    : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                tax.isActive ? 'Active' : 'Inactive',
                style: TextStyle(
                  color: tax.isActive ? Colors.green : Colors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          DataCell(Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit, size: 20),
                onPressed: () => _showTaxDialog(context, ref, tax: tax),
              ),
              IconButton(
                icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                onPressed: () => _deleteTax(context, ref, tax),
              ),
            ],
          )),
        ]);
      }).toList(),
    );
  }

  void _showTaxDialog(BuildContext context, WidgetRef ref,
      {DisposalTaxModel? tax}) {
    showDialog(
      context: context,
      builder: (context) => _TaxDialog(tax: tax),
    ).then((_) => ref.refresh(taxesProvider));
  }

  Future<void> _deleteTax(
      BuildContext context, WidgetRef ref, DisposalTaxModel tax) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Tax'),
        content: Text('Are you sure you want to delete "${tax.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await DisposalService().deleteTax(tax.id);
        ref.refresh(taxesProvider);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}

class _TaxDialog extends StatefulWidget {
  final DisposalTaxModel? tax;
  const _TaxDialog({this.tax});

  @override
  State<_TaxDialog> createState() => _TaxDialogState();
}

class _TaxDialogState extends State<_TaxDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _percentCtrl;
  bool _isActive = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.tax?.name ?? '');
    _percentCtrl = TextEditingController(
        text: widget.tax != null ? widget.tax!.percentage.toString() : '');
    _isActive = widget.tax?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _percentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final name = _nameCtrl.text.trim();
      final percent = double.parse(_percentCtrl.text.trim());

      if (widget.tax == null) {
        await DisposalService().createTax(name, percent);
      } else {
        await DisposalService()
            .updateTax(widget.tax!.id, name, percent, _isActive);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.tax != null;
    return StyledFormDialog(
      label: 'Tax Configuration',
      title: isEdit ? 'Edit Tax' : 'Add Tax',
      headerAccentColor: context.colors.successGreen,
      icon: Icons.receipt_long_rounded,
      width: 460,
      child: Form(
        key: _formKey,
        child: StyledFormSection(
          title: 'Tax Details',
          icon: Icons.percent_rounded,
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration:
                  const InputDecoration(labelText: 'Tax Name (e.g. VAT)'),
              validator: (v) => v!.isEmpty ? 'Required' : null,
            ),
            TextFormField(
              controller: _percentCtrl,
              decoration: const InputDecoration(
                  labelText: 'Percentage (%)', suffixText: '%'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v!.isEmpty) return 'Required';
                if (double.tryParse(v) == null) return 'Invalid number';
                return null;
              },
            ),
            if (isEdit)
              Container(
                decoration: BoxDecoration(
                  color: context.colors.textPrimary.withOpacity(0.02),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.colors.borderColor),
                ),
                child: SwitchListTile(
                  title: const Text('Active'),
                  activeColor: context.colors.primaryGold,
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        StyledDialogPrimaryButton(
          labelText: 'Save',
          icon: Icons.save_rounded,
          loading: _isLoading,
          onPressed: _isLoading ? null : _save,
        ),
      ],
    );
  }
}
