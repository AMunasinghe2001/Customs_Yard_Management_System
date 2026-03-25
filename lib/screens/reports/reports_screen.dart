import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import '../../core/theme.dart';
import '../../services/services.dart';
import '../../core/providers.dart';
import '../../services/report_service.dart';
import '../../models/models.dart';
import '../../widgets/custom_dropdown.dart';
import 'package:intl/intl.dart';
import 'package:gap/gap.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../widgets/error_view.dart';

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
  final ScrollController _scrollController = ScrollController();

  bool _isLoading(String key) => _loadingStates[key] ?? false;
  void _setLoading(String key, bool val) => setState(() => _loadingStates[key] = val);

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Report Generator', style: Theme.of(context).textTheme.headlineLarge),
                        Text('Choose periodic or standard warehouse reports.',
                            style: TextStyle(color: context.colors.textSecondary)),
                      ],
                    ),
                    // Icon removed to match other pages
                  ],
                ).animate().fadeIn(),
                const Gap(20),
                _buildFilterSection().animate().slideY(begin: 0.1).fadeIn(delay: 100.ms),
                const Gap(16),
              ],
            ),
          ),
          
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                child: _buildReportCards(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.primaryGold.withOpacity(0.35)),
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

        return FutureBuilder<ProfileModel?>(
          future: ref.read(authServiceProvider).getCurrentProfile(),
          builder: (context, snapshot) {
            final isAdmin = snapshot.data?.isAdmin ?? false;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (snapshot.hasError) 
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: ErrorView(error: snapshot.error!, onRetry: () => setState(() {})),
                  ),
                Text('Standard Reports', style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                const Gap(8),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 2.3,
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
                    if (isAdmin)
                      _buildReportCard(
                        title: 'Staff Audit',
                        description: 'Registered officers & admins.',
                        icon: Icons.people_alt_rounded,
                        color: Colors.redAccent,
                        onPdf: _generateStaffPdf,
                        onExcel: _exportStaffExcel,
                      ),
                  ],
                ),
                const Gap(16),
                Text('Periodic Summaries', style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                const Gap(8),
                 GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 2.3,
                  children: [
                    _buildSummaryCard('Daily Summary', Icons.calendar_view_day_rounded, Colors.purple, 'day'),
                    _buildSummaryCard('Weekly Summary', Icons.calendar_view_week_rounded, Colors.teal, 'week'),
                    _buildSummaryCard('Monthly Summary', Icons.calendar_view_month_rounded, Colors.indigo, 'month'),
                  ],
                ),
              ],
            ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 100.ms).fadeIn();
          },
        );
      },
    );
  }

  void _showPdfPreview(
    Future<Uint8List> Function(PdfPageFormat) buildPdf,
    String fileName,
  ) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => ReportPreviewDialog(
        buildPdf: buildPdf,
        fileName: fileName,
        onSave: (bytes, name) => _handleFileSave(bytes, name.replaceAll('.pdf', ''), 'pdf'),
      ),
    );
  }

  Widget _buildPreviewAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: color.withOpacity(0.2)),
              ),
              child: Icon(icon, color: color, size: 20),
            ).animate(onPlay: (controller) => controller.repeat(reverse: true))
             .shimmer(delay: 2.seconds, duration: 1500.ms, color: color.withOpacity(0.3)),
            const Gap(6),
            Text(label, style: TextStyle(color: context.colors.textPrimary, fontSize: 11, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
      _showPdfPreview(
        (format) => ReportService().generateWarehousePdf(
          filtered, 
          title: 'Current Warehouse Stock Report', 
          isReturnedReport: false,
          format: format,
        ),
        'Warehouse_Stock_Report.pdf',
      );
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
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => ExcelExportDialog(
              title: 'Export Warehouse Stock',
              recordCount: filtered.length,
              fileName: 'Warehouse_Stock_Report.xlsx',
              onExport: () => ReportService().exportWarehouseToExcel(filtered, isReturned: false),
              onSave: (bytes) => _handleFileSave(bytes, 'Warehouse_Status', 'xlsx'),
            ),
          );
        }
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
      _showPdfPreview(
        (format) => ReportService().generateWarehousePdf(
          filtered, 
          title: 'Returned Packages Report',
          isReturnedReport: true,
          format: format,
        ),
        'Returned_Packages_Report.pdf',
      );
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
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => ExcelExportDialog(
              title: 'Export Returned Data',
              recordCount: filtered.length,
              fileName: 'Returned_Packages_Report.xlsx',
              onExport: () => ReportService().exportWarehouseToExcel(filtered, isReturned: true),
              onSave: (bytes) => _handleFileSave(bytes, 'Returned_Packages', 'xlsx'),
            ),
          );
        }
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
        _showPdfPreview(
          (format) => ReportService().generateSummaryReportPdf(
            title: reportTitle,
            summaryData: summary,
            periodLabel: periodLabel,
            format: format,
          ), 
          '${reportTitle.replaceAll(' ', '_')}.pdf',
        );
      } else {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => ExcelExportDialog(
              title: 'Export Summary Data',
              recordCount: summary.length,
              fileName: '${reportTitle.replaceAll(' ', '_')}.xlsx',
              onExport: () => ReportService().exportSummaryToExcel(summary, periodLabel),
              onSave: (bytes) => _handleFileSave(bytes, reportTitle.replaceAll(' ', '_'), 'xlsx'),
            ),
          );
        }
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
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => ExcelExportDialog(
              title: 'Export Package Audit',
              recordCount: filtered.length,
              fileName: 'Package_Audit_Log.xlsx',
              onExport: () => ReportService().exportPackagesToExcel(filtered),
              onSave: (bytes) => _handleFileSave(bytes, 'Package_Audit_Log', 'xlsx'),
            ),
          );
        }
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(key, false);
    }
  }

  Future<void> _generateStaffPdf() async {
    const key = 'Staff Audit_pdf';
    _setLoading(key, true);
    try {
      final profiles = await ref.read(adminServiceProvider).getAllProfiles();
      _showPdfPreview(
        (format) => ReportService().generateStaffPdf(profiles, format: format),
        'Staff_Audit_Report.pdf',
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(key, false);
    }
  }


  Future<void> _exportSummaryExcel(String reportTitle, String periodLabel, List<Map<String, dynamic>> summary) async {
    final key = 'summary_xl';
    _setLoading(key, true);
    try {
      final fileName = '${reportTitle.replaceAll(' ', '_')}.xlsx';
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => ExcelExportDialog(
            title: 'Export Summary Data',
            recordCount: summary.length,
            fileName: fileName,
            onExport: () => ReportService().exportSummaryToExcel(summary, periodLabel),
            onSave: (bytes) => _handleFileSave(bytes, fileName.replaceAll('.xlsx', ''), 'xlsx'),
          ),
        );
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(key, false);
    }
  }

  Future<void> _exportStaffExcel() async {
    final key = 'staff_xl';
    _setLoading(key, true);
    try {
      final profiles = await ref.read(adminServiceProvider).getAllProfiles();
      final fileName = 'Staff_Audit_Report.xlsx';

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => ExcelExportDialog(
            title: 'Export Staff Audit',
            recordCount: profiles.length,
            fileName: fileName,
            onExport: () => ReportService().exportStaffToExcel(profiles),
            onSave: (bytes) => _handleFileSave(bytes, fileName.replaceAll('.xlsx', ''), 'xlsx'),
          ),
        );
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

class ReportPreviewDialog extends StatefulWidget {
  final Future<Uint8List> Function(PdfPageFormat) buildPdf;
  final String fileName;
  final Function(Uint8List, String) onSave;

  const ReportPreviewDialog({
    super.key,
    required this.buildPdf,
    required this.fileName,
    required this.onSave,
  });

  @override
  State<ReportPreviewDialog> createState() => _ReportPreviewDialogState();
}

class _ReportPreviewDialogState extends State<ReportPreviewDialog> {
  PdfPageFormat get _baseFormat => PdfPageFormat.a4;
  bool _isLandscape = false;
  Uint8List? _pdfBytes;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Start with Landscape if it looks like a wide report (like Warehouse)
    _isLandscape = widget.fileName.toLowerCase().contains('warehouse') || 
                   widget.fileName.toLowerCase().contains('returned');
    _generatePdf();
  }

  Future<void> _generatePdf() async {
    setState(() => _isLoading = true);
    try {
      final format = _isLandscape ? _baseFormat.landscape : _baseFormat.portrait;
      final bytes = await widget.buildPdf(format);
      setState(() {
        _pdfBytes = bytes;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) Navigator.pop(context);
    }
  }

  void _toggleOrientation() {
    setState(() => _isLandscape = !_isLandscape);
    _generatePdf();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.colors.scaffoldBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          _buildHeader(context),
          const Divider(height: 1),
          Expanded(child: _buildBody(context)),
          _buildBottomBar(context),
        ],
      ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.95, 0.95), curve: Curves.easeOutBack),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.description_rounded, color: context.colors.primaryGold, size: 20),
              const Gap(12),
              Text('Report Preview', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: context.colors.textPrimary)),
            ],
          ),
          IconButton(
            icon: Icon(Icons.close, color: context.colors.textSecondary),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: context.colors.primaryGold));
    }
    if (_pdfBytes == null) return const SizedBox();

    return PdfPreview(
      build: (format) => _pdfBytes!,
      useActions: false,
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,
      maxPageWidth: 700,
      pdfFileName: widget.fileName,
      loadingWidget: Center(child: CircularProgressIndicator(color: context.colors.primaryGold)),
      previewPageMargin: const EdgeInsets.all(20),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        border: Border(top: BorderSide(color: context.colors.borderColor)),
      ),
      child: Row(
        children: [
          // Simplified Orientation Toggle
          _buildOrientationButton(),
          const Gap(12),
          Text('(Standard A4 Format)', style: TextStyle(color: context.colors.textMuted, fontSize: 10)),
          const Spacer(),
          // Actions
          _buildActionItem(context, Icons.print_rounded, 'Send to Printer', context.colors.primaryGold, () {
            if (_pdfBytes != null) {
              Printing.layoutPdf(
                onLayout: (f) => _pdfBytes!, 
                name: widget.fileName,
                // Setting dynamicLayout to false ensures it follows our generated bytes strictly
                dynamicLayout: false,
              );
            }
          }),
          const Gap(24),
          _buildActionItem(context, Icons.download_rounded, 'Save PDF', Colors.green, () {
             if (_pdfBytes != null) widget.onSave(_pdfBytes!, widget.fileName);
          }),
        ],
      ).animate().slideY(begin: 0.5, curve: Curves.easeOutExpo).fadeIn(),
    );
  }

  Widget _buildFormatButton(String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? context.colors.primaryGold.withOpacity(0.15) : Colors.transparent,
          border: Border.all(color: isSelected ? context.colors.primaryGold : context.colors.borderColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: TextStyle(
          color: isSelected ? context.colors.primaryGold : context.colors.textSecondary,
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        )),
      ),
    );
  }

  Widget _buildOrientationButton() {
    return InkWell(
      onTap: _toggleOrientation,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          border: Border.all(color: context.colors.borderColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(_isLandscape ? Icons.landscape_rounded : Icons.portrait_rounded, 
                 size: 16, color: context.colors.textPrimary),
            const Gap(6),
            Text(_isLandscape ? 'Landscape' : 'Portrait', 
                 style: TextStyle(color: context.colors.textPrimary, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildActionItem(BuildContext context, IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const Gap(2),
          Text(label, style: TextStyle(color: context.colors.textPrimary, fontSize: 10)),
        ],
      ),
    );
  }
}

class ExcelExportDialog extends StatefulWidget {
  final String title;
  final int recordCount;
  final String fileName;
  final Future<Uint8List?> Function() onExport;
  final Function(Uint8List) onSave;

  const ExcelExportDialog({
    super.key,
    required this.title,
    required this.recordCount,
    required this.fileName,
    required this.onExport,
    required this.onSave,
  });

  @override
  State<ExcelExportDialog> createState() => _ExcelExportDialogState();
}

class _ExcelExportDialogState extends State<ExcelExportDialog> {
  bool _isExporting = false;

  Future<void> _handleExport() async {
    setState(() => _isExporting = true);
    try {
      final bytes = await widget.onExport();
      if (bytes != null && mounted) {
        Navigator.pop(context);
        widget.onSave(bytes);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.colors.scaffoldBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(24),
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.table_view_rounded, color: Colors.green, size: 48)
                .animate().scale(delay: 100.ms, curve: Curves.elasticOut),
            const Gap(16),
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const Gap(8),
            Text('Excel Data Export', style: TextStyle(color: context.colors.textSecondary)),
            const Gap(24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.colors.cardDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.colors.borderColor),
              ),
              child: Column(
                children: [
                  _buildStatRow('Total Records', widget.recordCount.toString()),
                  const Divider(height: 24),
                  _buildStatRow('File Format', '.xlsx (Excel)'),
                  const Divider(height: 24),
                  _buildStatRow('Default Name', widget.fileName),
                ],
              ),
            ),
            const Gap(32),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(color: context.colors.textSecondary)),
                  ),
                ),
                const Gap(12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _isExporting ? null : _handleExport,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: _isExporting 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Export Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ).animate().fadeIn().scale(begin: const Offset(0.9, 0.9)),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: context.colors.textSecondary, fontSize: 13)),
        Text(value, style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }
}
