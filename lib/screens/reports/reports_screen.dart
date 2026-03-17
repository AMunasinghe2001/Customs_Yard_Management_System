import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/theme.dart';
import '../../services/services.dart';
import '../../services/report_service.dart';
import '../../models/models.dart';
import 'package:intl/intl.dart';
import 'package:gap/gap.dart';
import 'package:flutter_animate/flutter_animate.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  DateTime? _startDate;
  DateTime? _endDate;
  String _selectedStatus = 'all';
  
  // Track loading state for each button uniquely
  final Map<String, bool> _loadingStates = {};

  bool _isLoading(String key) => _loadingStates[key] ?? false;
  void _setLoading(String key, bool val) => setState(() => _loadingStates[key] = val);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Report Generator', style: Theme.of(context).textTheme.headlineMedium),
                    Text('Choose periodic or standard warehouse reports.',
                        style: TextStyle(color: context.colors.textSecondary, fontSize: 13)),
                  ],
                ),
                Icon(Icons.summarize_rounded, color: context.colors.primaryGold.withOpacity(0.5), size: 32),
              ],
            ).animate().fadeIn(),
            const Gap(16),

            _buildFilterSection().animate().slideY(begin: 0.1).fadeIn(delay: 100.ms),
            const Gap(20),
            
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: _buildDatePicker('Start Date', _startDate, (date) => setState(() => _startDate = date)),
          ),
          const Gap(12),
          Expanded(
            flex: 2,
            child: _buildDatePicker('End Date', _endDate, (date) => setState(() => _endDate = date)),
          ),
          const Gap(12),
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Status', style: TextStyle(color: context.colors.textSecondary, fontSize: 11)),
                const Gap(4),
                DropdownButtonFormField<String>(
                  value: _selectedStatus,
                  isExpanded: true,
                  dropdownColor: context.colors.cardDark,
                  style: TextStyle(color: context.colors.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: ['all', 'pending', 'held', 'cleared'].map((s) => 
                    DropdownMenuItem(value: s, child: Text(s.toUpperCase(), style: const TextStyle(fontSize: 12)))).toList(),
                  onChanged: (val) => setState(() => _selectedStatus = val!),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatePicker(String label, DateTime? value, Function(DateTime) onSelect) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: context.colors.textSecondary, fontSize: 11)),
        const Gap(4),
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: context.colors.borderColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today_rounded, size: 14, color: context.colors.primaryGold),
                const Gap(8),
                Text(value != null ? DateFormat('yyyy-MM-dd').format(value) : 'Select Date',
                    style: TextStyle(color: context.colors.textPrimary, fontSize: 13)),
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
        final crossAxisCount = constraints.maxWidth > 900 ? 3 : (constraints.maxWidth > 600 ? 2 : 1);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Standard Reports', style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
            const Gap(12),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.8,
              children: [
                _buildReportCard(
                  title: 'Warehouse Stock',
                  description: 'Current stock across network.',
                  icon: Icons.warehouse_rounded,
                  color: Colors.blue,
                  onPdf: _generateWarehouseStockPdf,
                  onExcel: _exportWarehouseStockExcel,
                ),
                _buildReportCard(
                  title: 'Returned Packages',
                  description: 'Items returned from yard.',
                  icon: Icons.assignment_return_rounded,
                  color: Colors.orange,
                  onPdf: _generateReturnedPdf,
                  onExcel: _exportReturnedExcel,
                ),
                _buildReportCard(
                  title: 'Package Audit',
                  description: 'Full package audit log.',
                  icon: Icons.fact_check_rounded,
                  color: Colors.green,
                  onExcel: _exportExcel,
                ),
              ],
            ),
            const Gap(24),
            Text('Periodic Summaries', style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
            const Gap(12),
             GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.8,
              children: [
                _buildSummaryCard('Daily Summary', Icons.calendar_view_day_rounded, Colors.purple, 'day'),
                _buildSummaryCard('Weekly Summary', Icons.calendar_view_week_rounded, Colors.teal, 'week'),
                _buildSummaryCard('Monthly Summary', Icons.calendar_view_month_rounded, Colors.indigo, 'month'),
              ],
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
    Future<void> Function()? onPdf,
    Future<void> Function()? onExcel,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const Gap(8),
              Expanded(child: Text(title, style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14))),
            ],
          ),
          const Gap(4),
          Text(description, 
              style: TextStyle(color: context.colors.textMuted, fontSize: 11),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const Spacer(),
          Row(
            children: [
              if (onPdf != null) 
                Expanded(
                  child: _buildActionButton(
                    label: 'PDF',
                    icon: Icons.picture_as_pdf_outlined,
                    color: context.colors.customsBlue,
                    isLoading: _isLoading('${title}_pdf'),
                    onTap: onPdf,
                  ),
                ),
              if (onPdf != null && onExcel != null) const Gap(8),
              if (onExcel != null)
                Expanded(
                  child: _buildActionButton(
                    label: 'Excel',
                    icon: Icons.table_chart_outlined,
                    color: Colors.green,
                    isOutline: true,
                    isLoading: _isLoading('${title}_excel'),
                    onTap: onExcel,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required bool isLoading,
    required VoidCallback onTap,
    bool isOutline = false,
  }) {
    final style = isOutline 
      ? OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color),
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 36),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        )
      : ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 36),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        );

    final child = isLoading 
      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
      : Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14),
            const Gap(4),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        );

    return isOutline 
      ? OutlinedButton(onPressed: isLoading ? null : onTap, style: style, child: child)
      : ElevatedButton(onPressed: isLoading ? null : onTap, style: style, child: child);
  }

  Widget _buildSummaryCard(String title, IconData icon, Color color, String period) {
    return _buildReportCard(
      title: title,
      description: 'Package movement by $period.',
      icon: icon,
      color: color,
      onPdf: () => _generateSummaryReport(period, 'pdf'),
      onExcel: () => _generateSummaryReport(period, 'excel'),
    );
  }

  Future<void> _handleFileSave(Uint8List? bytes, String defaultName, String extension) async {
    if (bytes == null) return;
    
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Report',
      fileName: '${defaultName}_${DateFormat('yyyyMMdd').format(DateTime.now())}.$extension',
      allowedExtensions: [extension],
      type: FileType.custom,
    );

    if (result != null) {
      final file = File(result);
      await file.writeAsBytes(bytes);
      _showSuccess('Report saved successfully to ${result.split(Platform.pathSeparator).last}');
    }
  }

  Future<void> _generateWarehouseStockPdf() async {
    const key = 'Warehouse Stock_pdf';
    _setLoading(key, true);
    try {
      final entries = await ref.read(warehouseServiceProvider).getAllWarehouseEntries(isReturned: false);
      final filtered = _filterWarehouseByDate(entries);
      if (filtered.isEmpty) {
        _showNoDataMessage();
      } else {
        await ReportService().generateWarehousePdf(filtered, title: 'Current Warehouse Stock Report', isReturnedReport: false);
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(key, false);
    }
  }

  Future<void> _exportWarehouseStockExcel() async {
    const key = 'Warehouse Stock_excel';
    _setLoading(key, true);
    try {
      final entries = await ref.read(warehouseServiceProvider).getAllWarehouseEntries(isReturned: false);
      final filtered = _filterWarehouseByDate(entries);
      if (filtered.isEmpty) {
        _showNoDataMessage();
      } else {
        final bytes = await ReportService().exportWarehouseToExcel(filtered, isReturned: false);
        await _handleFileSave(bytes, 'Warehouse_Status', 'xlsx');
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(key, false);
    }
  }

  Future<void> _generateReturnedPdf() async {
    const key = 'Returned Packages_pdf';
    _setLoading(key, true);
    try {
      final entries = await ref.read(warehouseServiceProvider).getAllWarehouseEntries(isReturned: true);
      final filtered = _filterWarehouseByDate(entries);
      if (filtered.isEmpty) {
        _showNoDataMessage();
      } else {
        await ReportService().generateWarehousePdf(filtered, title: 'Returned Packages Report', isReturnedReport: true);
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(key, false);
    }
  }

  Future<void> _exportReturnedExcel() async {
    const key = 'Returned Packages_excel';
    _setLoading(key, true);
    try {
      final entries = await ref.read(warehouseServiceProvider).getAllWarehouseEntries(isReturned: true);
      final filtered = _filterWarehouseByDate(entries);
      if (filtered.isEmpty) {
        _showNoDataMessage();
      } else {
        final bytes = await ReportService().exportWarehouseToExcel(filtered, isReturned: true);
        await _handleFileSave(bytes, 'Returned_Packages', 'xlsx');
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(key, false);
    }
  }

  Future<void> _generateSummaryReport(String periodType, String format) async {
    final title = '${periodType.toUpperCase()[0]}${periodType.substring(1)} Summary';
    final key = '${title}_$format';
    _setLoading(key, true);
    try {
      final admitted = await ref.read(warehouseServiceProvider).getAllWarehouseEntries();
      final filtered = _filterWarehouseByDate(admitted);
      
      if (filtered.isEmpty) {
        _showNoDataMessage();
        return;
      }

      final summary = _calculateSummary(filtered, periodType);
      final reportTitle = '$title Package Summary Report';
      final periodLabel = periodType == 'day' ? 'Date' : (periodType == 'week' ? 'Week Reference' : 'Month');

      if (format == 'pdf') {
        await ReportService().generateSummaryReportPdf(
          title: reportTitle,
          summaryData: summary,
          periodLabel: periodLabel,
        );
      } else {
        final bytes = await ReportService().exportSummaryToExcel(summary, periodLabel);
        await _handleFileSave(bytes, reportTitle.replaceAll(' ', '_'), 'xlsx');
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(key, false);
    }
  }

  List<Map<String, dynamic>> _calculateSummary(List<WarehouseEntryModel> entries, String periodType) {
    final Map<String, Map<String, int>> groups = {};

    for (var e in entries) {
      String key;
      if (periodType == 'day') {
        key = DateFormat('yyyy-MM-dd').format(e.admittedAt);
      } else if (periodType == 'week') {
        final week = (e.admittedAt.day / 7).ceil();
        key = 'Year ${e.admittedAt.year} - Week $week';
      } else {
        key = DateFormat('yyyy-MM').format(e.admittedAt);
      }

      groups[key] ??= {'admitted': 0, 'returned': 0};
      groups[key]!['admitted'] = groups[key]!['admitted']! + 1;
      
      if (e.isReturned && e.returnedAt != null) {
        String rKey;
        if (periodType == 'day') {
          rKey = DateFormat('yyyy-MM-dd').format(e.returnedAt!);
        } else if (periodType == 'week') {
          final week = (e.returnedAt!.day / 7).ceil();
          rKey = 'Year ${e.returnedAt!.year} - Week $week';
        } else {
          rKey = DateFormat('yyyy-MM').format(e.returnedAt!);
        }
        
        groups[rKey] ??= {'admitted': 0, 'returned': 0};
        groups[rKey]!['returned'] = groups[rKey]!['returned']! + 1;
      }
    }

    final sortedKeys = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    return sortedKeys.map((k) => {
      'period': k,
      'admitted': groups[k]!['admitted'],
      'returned': groups[k]!['returned'],
    }).toList();
  }

  Future<void> _exportExcel() async {
    const key = 'Package Audit_excel';
    _setLoading(key, true);
    try {
      final packages = await ref.read(packageServiceProvider).getAllPackages(
        status: _selectedStatus == 'all' ? null : _selectedStatus,
      );
      
      final filtered = _filterByDate(packages);
      
      if (filtered.isEmpty) {
        _showNoDataMessage();
      } else {
        final bytes = await ReportService().exportPackagesToExcel(filtered);
        await _handleFileSave(bytes, 'Package_Audit_Log', 'xlsx');
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(key, false);
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
