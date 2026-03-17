import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../services/services.dart';
import '../../services/report_service.dart';
import '../../models/models.dart';
import 'package:intl/intl.dart';
import 'package:gap/gap.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  DateTime? _startDate;
  DateTime? _endDate;
  String _selectedStatus = 'all';
  bool _isGenerating = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.summarize_rounded, color: context.colors.primaryGold, size: 32),
                const Gap(12),
                Text('Report Generator', 
                  style: TextStyle(color: context.colors.textPrimary, fontSize: 28, fontWeight: FontWeight.bold)),
              ],
            ),
            const Gap(8),
            Text('Generate PDF and Excel reports for packages and warehouse records.',
                style: TextStyle(color: context.colors.textMuted, fontSize: 16)),
            const Gap(32),

            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildFilterSection(),
                    const Gap(32),
                    _buildReportCards(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Filters', style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
          const Gap(20),
          Row(
            children: [
              Expanded(
                child: _buildDatePicker('Start Date', _startDate, (date) => setState(() => _startDate = date)),
              ),
              const Gap(16),
              Expanded(
                child: _buildDatePicker('End Date', _endDate, (date) => setState(() => _endDate = date)),
              ),
              const Gap(16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Status', style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
                    const Gap(6),
                    DropdownButtonFormField<String>(
                      value: _selectedStatus,
                      dropdownColor: context.colors.cardDark,
                      style: TextStyle(color: context.colors.textPrimary),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: ['all', 'pending', 'held', 'cleared'].map((s) => 
                        DropdownMenuItem(value: s, child: Text(s.toUpperCase()))).toList(),
                      onChanged: (val) => setState(() => _selectedStatus = val!),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDatePicker(String label, DateTime? value, Function(DateTime) onSelect) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
        const Gap(6),
        InkWell(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: value ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
            );
            if (date != null) onSelect(date);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: context.colors.borderColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today_rounded, size: 16, color: context.colors.primaryGold),
                const Gap(10),
                Text(value != null ? DateFormat('yyyy-MM-dd').format(value) : 'Select Date',
                    style: TextStyle(color: context.colors.textPrimary)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReportCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 800 ? 3 : (constraints.maxWidth > 500 ? 2 : 1);
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 20,
          mainAxisSpacing: 20,
          childAspectRatio: 1.2,
          children: [
            _buildReportCard(
              title: 'Package Summary',
              description: 'Overview of packages with their current status and consignee details.',
              icon: Icons.inventory_2_rounded,
              color: Colors.blue,
              actionLabel: 'Generate PDF',
              onTap: _generatePackagePdf,
            ),
            _buildReportCard(
              title: 'Warehouse Status',
              description: 'Report of all items currently held in warehouses.',
              icon: Icons.warehouse_rounded,
              color: Colors.orange,
              actionLabel: 'Generate PDF',
              onTap: _generateWarehousePdf,
            ),
            _buildReportCard(
              title: 'Data Export (Excel)',
              description: 'Complete package data export for detailed audit and analysis.',
              icon: Icons.table_chart_rounded,
              color: Colors.green,
              actionLabel: 'Export Excel',
              onTap: _exportExcel,
            ),
          ],
        );
      },
    );
  }

  Widget _buildReportCard({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required String actionLabel,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const Gap(16),
          Text(title, style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
          const Gap(8),
          Text(description, 
              style: TextStyle(color: context.colors.textMuted, fontSize: 13),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _isGenerating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.download_rounded, size: 18),
              label: Text(actionLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.customsBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _isGenerating ? null : onTap,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generatePackagePdf() async {
    setState(() => _isGenerating = true);
    try {
      final packages = await ref.read(packageServiceProvider).getAllPackages(
        status: _selectedStatus == 'all' ? null : _selectedStatus,
      );
      
      final filtered = _filterByDate(packages);
      
      if (filtered.isEmpty) {
        _showNoDataMessage();
      } else {
        await ReportService().generatePackagePdf(filtered, title: 'Package Summary Report');
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  Future<void> _generateWarehousePdf() async {
    setState(() => _isGenerating = true);
    try {
      // Fetch all warehouses first
      final warehouses = await ref.read(warehouseServiceProvider).getWarehouses();
      List<WarehouseEntryModel> allEntries = [];
      
      for (var w in warehouses) {
        final entries = await ref.read(warehouseServiceProvider).getEntriesByWarehouse(w.id, isReturned: false);
        allEntries.addAll(entries);
      }

      final filtered = _filterWarehouseByDate(allEntries);

      if (filtered.isEmpty) {
        _showNoDataMessage();
      } else {
        await ReportService().generateWarehousePdf(filtered, title: 'Warehouse Status Report');
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  Future<void> _exportExcel() async {
    setState(() => _isGenerating = true);
    try {
      final packages = await ref.read(packageServiceProvider).getAllPackages(
        status: _selectedStatus == 'all' ? null : _selectedStatus,
      );
      
      final filtered = _filterByDate(packages);
      
      if (filtered.isEmpty) {
        _showNoDataMessage();
      } else {
        await     ReportService().exportPackagesToExcel(filtered);
        _showSuccess('Excel file exported successfully to your Documents folder.');
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  List<PackageModel> _filterByDate(List<PackageModel> list) {
    if (_startDate == null && _endDate == null) return list;
    return list.where((p) {
      if (p.entryDate == null) return false;
      bool matches = true;
      if (_startDate != null) matches &= p.entryDate!.isAfter(_startDate!) || p.entryDate!.isAtSameMomentAs(_startDate!);
      if (_endDate != null) {
        final endOfDay = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
        matches &= p.entryDate!.isBefore(endOfDay);
      }
      return matches;
    }).toList();
  }

  List<WarehouseEntryModel> _filterWarehouseByDate(List<WarehouseEntryModel> list) {
    if (_startDate == null && _endDate == null) return list;
    return list.where((e) {
      bool matches = true;
      if (_startDate != null) matches &= e.admittedAt.isAfter(_startDate!) || e.admittedAt.isAtSameMomentAs(_startDate!);
      if (_endDate != null) {
        final endOfDay = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
        matches &= e.admittedAt.isBefore(endOfDay);
      }
      return matches;
    }).toList();
  }

  void _showNoDataMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No data found for the selected filters.')),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error: $msg'), backgroundColor: context.colors.dangerRed),
    );
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green),
    );
  }
}
