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
  String _selectedWarehouse = 'all';
  
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
    final warehouses = ref.watch(warehousesProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.primaryGold.withOpacity(0.35)),
      ),
      child: Column(
        children: [
          Row(
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
                      items: ['all', 'pending', 'held', 'cleared', 'returned', 'seized'].map((s) => 
                        DropdownMenuItem(value: s, child: Text(s.toUpperCase(), style: const TextStyle(fontSize: 12)))).toList(),
                      onChanged: (val) => setState(() => _selectedStatus = val!),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Gap(12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Warehouse Selection', style: TextStyle(color: context.colors.textSecondary, fontSize: 11)),
                    const Gap(4),
                    DropdownButtonFormField<String>(
                      value: _selectedWarehouse,
                      isExpanded: true,
                      dropdownColor: context.colors.cardDark,
                      style: TextStyle(color: context.colors.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: Icon(Icons.warehouse_rounded, size: 16, color: context.colors.primaryGold),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: [
                        const DropdownMenuItem(value: 'all', child: Text('ALL WAREHOUSES', style: TextStyle(fontSize: 12))),
                        ...warehouses.maybeWhen(
                          data: (list) => list.map((w) => DropdownMenuItem(
                            value: w.id, 
                            child: Text('${w.code} - ${w.name}'.toUpperCase(), style: const TextStyle(fontSize: 12))
                          )).toList(),
                          orElse: () => [],
                        ),
                      ],
                      onChanged: (val) => setState(() => _selectedWarehouse = val!),
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

                // ── Section 1: Standard Reports ──
                _buildSectionHeader('Standard Reports', Icons.article_rounded),
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
                      title: 'Packages Inventory Audit',
                      description: 'Generates report based on active filters above.',
                      icon: Icons.inventory_2_rounded,
                      color: context.colors.primaryGold,
                      onPdf: _generateAllPackagesPdf,
                      onExcel: _exportExcel,
                    ),
                    _buildReportCard(
                      title: 'Category & Zone Summary',
                      description: 'Inventory distribution by category & warehouse zones.',
                      icon: Icons.pie_chart_rounded,
                      color: Colors.purpleAccent,
                      onPdf: _generateCategoryZonePdf,
                      onExcel: _exportCategoryZoneExcel,
                    ),
                    _buildReportCard(
                      title: 'Confiscated Items',
                      description: 'All items seized/confiscated by customs.',
                      icon: Icons.gavel_rounded,
                      color: const Color(0xFFD32F2F),
                      onPdf: _generateConfiscatedPdf,
                      onExcel: _exportConfiscatedExcel,
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

                // ── Section 2: Warehouse & Movement Reports ──
                const Gap(24),
                _buildSectionHeader('Warehouse & Movement Reports', Icons.warehouse_rounded),
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
                      description: 'Currently held items in warehouses.',
                      icon: Icons.warehouse_rounded,
                      color: const Color(0xFF1565C0),
                      onPdf: _generateWarehouseStockPdf,
                      onExcel: _exportWarehouseStockExcel,
                    ),
                    _buildReportCard(
                      title: 'Returned Packages',
                      description: 'All released/returned package entries.',
                      icon: Icons.keyboard_return_rounded,
                      color: const Color(0xFF2E7D32),
                      onPdf: _generateReturnedPdf,
                      onExcel: _exportReturnedExcel,
                    ),
                    _buildReportCard(
                      title: 'Warehouses List',
                      description: 'Registered warehouses & current occupancy.',
                      icon: Icons.domain_rounded,
                      color: const Color(0xFF6A1B9A),
                      onPdf: _generateWarehousesListPdf,
                      onExcel: _exportWarehousesListExcel,
                    ),
                    _buildReportCard(
                      title: 'Daily Summary',
                      description: 'Package movement by day.',
                      icon: Icons.today_rounded,
                      color: const Color(0xFF00838F),
                      onPdf: () => _generateSummaryReport('day', 'pdf'),
                      onExcel: () => _generateSummaryReport('day', 'excel'),
                    ),
                    _buildReportCard(
                      title: 'Weekly Summary',
                      description: 'Package movement by week.',
                      icon: Icons.date_range_rounded,
                      color: const Color(0xFF4527A0),
                      onPdf: () => _generateSummaryReport('week', 'pdf'),
                      onExcel: () => _generateSummaryReport('week', 'excel'),
                    ),
                    _buildReportCard(
                      title: 'Monthly Summary',
                      description: 'Package movement by month.',
                      icon: Icons.calendar_month_rounded,
                      color: const Color(0xFFEF6C00),
                      onPdf: () => _generateSummaryReport('month', 'pdf'),
                      onExcel: () => _generateSummaryReport('month', 'excel'),
                    ),
                  ],
                ),

                // ── Section 3: Financial Reports ──
                const Gap(24),
                _buildSectionHeader('Financial Reports', Icons.payments_rounded),
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
                      title: 'Storage Charges',
                      description: 'Outstanding storage charges for held items.',
                      icon: Icons.account_balance_wallet_rounded,
                      color: const Color(0xFFC62828),
                      onPdf: _generateStorageChargesPdf,
                      onExcel: _exportStorageChargesExcel,
                    ),
                    _buildReportCard(
                      title: 'Released Revenue',
                      description: 'Storage charges collected on returned items.',
                      icon: Icons.receipt_long_rounded,
                      color: const Color(0xFF388E3C),
                      onPdf: _generateReleasedRevenuePdf,
                      onExcel: _exportReleasedRevenueExcel,
                    ),
                  ],
                ),

                // ── Section 4: System Configuration & Logs ──
                const Gap(24),
                _buildSectionHeader('System Configuration & Logs', Icons.settings_rounded),
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
                      title: 'Hold Reasons',
                      description: 'System-wide hold reasons list.',
                      icon: Icons.rule_rounded,
                      color: Colors.orange,
                      onPdf: _generateHoldReasonsPdf,
                      onExcel: _exportHoldReasonsExcel,
                    ),
                    _buildReportCard(
                      title: 'Item Categories',
                      description: 'Package classification rules.',
                      icon: Icons.category_rounded,
                      color: Colors.teal,
                      onPdf: _generateCategoriesPdf,
                      onExcel: _exportCategoriesExcel,
                    ),
                    _buildReportCard(
                      title: 'Audit Logs',
                      description: 'Date-filtered system activity.',
                      icon: Icons.history_rounded,
                      color: Colors.blueGrey,
                      onPdf: _generateLogsPdf,
                      onExcel: _exportLogsExcel,
                    ),
                  ],
                ),
              ],
            ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 100.ms).fadeIn();
          },
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: context.colors.primaryGold),
        const Gap(8),
        Text(title, style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }

  Widget _buildStatusCard(String title, String status, IconData icon, Color color) {
    return _buildReportCard(
      title: title,
      description: 'Filter-based $status list.',
      icon: icon,
      color: color,
      onPdf: () => _generateStatusReport(status, 'pdf'),
      onExcel: () => _generateStatusReport(status, 'excel'),
    );
  }

  Future<void> _generateStatusReport(String status, String format) async {
    final key = '${status}_$format';
    _setLoading(key, true);
    try {
      final packages = await ref.read(packageServiceProvider).getAllPackages(status: status);
      final withDate = _filterByDate(packages);
      final filtered = _filterByWarehouse(withDate);

      if (filtered.isEmpty) {
        _showNoDataMessage();
        return;
      }

      if (format == 'pdf') {
        _showPdfPreview(
          (format) => ReportService().generatePackagePdf(
            filtered,
            title: '${status.toUpperCase()} Packages Report',
            format: format,
          ),
          '${status}_Packages_Report.pdf',
        );
      } else {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => ExcelExportDialog(
              title: 'Export ${status.toUpperCase()} Data',
              recordCount: filtered.length,
              fileName: '${status}_Packages_Report.xlsx',
              onExport: () => ReportService().exportPackagesToExcel(filtered),
              onSave: (bytes) => _handleFileSave(bytes, '${status}_Packages', 'xlsx'),
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

  Future<void> _generateCategoryZonePdf() async {
    const key = 'Category & Zone Summary_pdf';
    _setLoading(key, true);
    try {
      final packages = await ref.read(packageServiceProvider).getAllPackages();
      final entries = await ref.read(warehouseServiceProvider).getAllWarehouseEntries();
      
      final withDatePkgs = _filterByDate(packages);
      final withDateEntries = _filterByDate(entries);

      if (withDatePkgs.isEmpty && withDateEntries.isEmpty) {
        _showNoDataMessage();
        return;
      }

      _showPdfPreview(
        (format) => ReportService().generateCategoryAndZonePdf(withDatePkgs, withDateEntries),
        'Category_Zone_Summary_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
      );
    } catch (e) {
      _showError('Error generating Category/Zone PDF: $e');
    } finally {
      _setLoading(key, false);
    }
  }

  Future<void> _exportCategoryZoneExcel() async {
    const key = 'Category & Zone Summary_excel';
    _setLoading(key, true);
    try {
      final packages = await ref.read(packageServiceProvider).getAllPackages();
      final entries = await ref.read(warehouseServiceProvider).getAllWarehouseEntries();
      
      final withDatePkgs = _filterByDate(packages);
      final withDateEntries = _filterByDate(entries);

      if (withDatePkgs.isEmpty && withDateEntries.isEmpty) {
        _showNoDataMessage();
        return;
      }

      final bytes = await ReportService().exportCategoryAndZoneToExcel(withDatePkgs, withDateEntries);
      if (bytes != null) {
        _handleFileSave(bytes, 'Category_Zone_Summary_${DateFormat('yyyyMMdd').format(DateTime.now())}', 'xlsx');
      }
    } catch (e) {
      _showError('Error exporting Category/Zone Excel: $e');
    } finally {
      _setLoading(key, false);
    }
  }

  Future<void> _generateAllPackagesPdf() async {
    const key = 'Packages Inventory Audit_pdf';
    _setLoading(key, true);
    try {
      final packages = await ref.read(packageServiceProvider).getAllPackages(
        status: _selectedStatus == 'all' ? null : _selectedStatus,
      );
      final withDate = _filterByDate(packages);
      final filtered = _filterByWarehouse(withDate);
      
      if (filtered.isEmpty) {
        _showNoDataMessage();
        return;
      }

      final statusTitle = _selectedStatus == 'all' ? 'ALL' : _selectedStatus.toUpperCase();
      
      String warehouseTitle = '';
      if (_selectedWarehouse != 'all') {
        final warehouses = ref.read(warehousesProvider).asData?.value;
        final wh = warehouses?.firstWhere((w) => w.id == _selectedWarehouse);
        if (wh != null) {
          warehouseTitle = ' - ${wh.code}';
        }
      }

      final dateRangeStr = (_startDate != null && _endDate != null) 
          ? 'From ${DateFormat('yyyy-MM-dd').format(_startDate!)} To ${DateFormat('yyyy-MM-dd').format(_endDate!)}'
          : 'Full Historical Audit';

      _showPdfPreview(
        (format) => ReportService().generatePackagePdf(
          filtered,
          title: '$statusTitle PACKAGES INVENTORY AUDIT$warehouseTitle',
          dateRange: dateRangeStr,
          format: format.copyWith(marginLeft: 20, marginRight: 20, marginTop: 20, marginBottom: 20),
        ),
        '${statusTitle.replaceAll(' ', '_')}${warehouseTitle.replaceAll(' ', '_')}_Audit_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(key, false);
    }
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
      final filtered = _filterByDate(entries);
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
      final filtered = _filterByDate(entries);
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
      final filtered = _filterByDate(entries);
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
      final filtered = _filterByDate(entries);
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
      final filtered = _filterByDate(admitted);
      
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

List<PackageModel> _filterByWarehouse(List<PackageModel> list) {
    if (_selectedWarehouse == 'all') return list;
    return list.where((p) {
      if (p.warehouseEntries.isEmpty) return false;
      return p.warehouseEntries.any((e) => e.warehouseId == _selectedWarehouse);
    }).toList();
  }

  Future<void> _exportExcel() async {
    const key = 'Packages Inventory Audit_excel';
    _setLoading(key, true);
    try {
      final packages = await ref.read(packageServiceProvider).getAllPackages(
        status: _selectedStatus == 'all' ? null : _selectedStatus,
      );

      final withDate = _filterByDate(packages);
      final filtered = _filterByWarehouse(withDate);

      if (filtered.isEmpty) {
        _showNoDataMessage();
      } else {
        final statusName = _selectedStatus == 'all' ? 'ALL' : _selectedStatus.toUpperCase();
        
        String whSuffix = '';
        if (_selectedWarehouse != 'all') {
          final warehouses = ref.read(warehousesProvider).asData?.value;
          final wh = warehouses?.firstWhere((w) => w.id == _selectedWarehouse);
          if (wh != null) whSuffix = ' - ${wh.code}';
        }

        if (mounted) {
          final dateRangeStr = (_startDate != null && _endDate != null) 
              ? 'From ${DateFormat('yyyy-MM-dd').format(_startDate!)} To ${DateFormat('yyyy-MM-dd').format(_endDate!)}'
              : 'Full Historical Audit';

          showDialog(
            context: context,
            builder: (ctx) => ExcelExportDialog(
              title: 'Export $statusName$whSuffix Inventory Audit',
              recordCount: filtered.length,
              fileName: '${statusName}${whSuffix.replaceAll(' ', '_')}_Inventory_Audit.xlsx',
              onExport: () => ReportService().exportPackagesToExcel(
                filtered,
                title: '$statusName PACKAGES INVENTORY AUDIT$whSuffix',
                subTitle: dateRangeStr,
              ),
              onSave: (bytes) => _handleFileSave(bytes, '${statusName}${whSuffix.replaceAll(' ', '_')}_Inventory_Audit', 'xlsx'),
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

  Future<void> _generateHoldReasonsPdf() async {
    const key = 'Hold Reasons_pdf';
    _setLoading(key, true);
    try {
      final reasons = await ref.read(holdReasonServiceProvider).getReasons();
      if (reasons.isEmpty) {
        _showNoDataMessage();
        return;
      }
      _showPdfPreview(
        (format) => ReportService().generateHoldReasonsPdf(reasons),
        'Hold_Reasons_Audit.pdf',
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(key, false);
    }
  }

  Future<void> _exportHoldReasonsExcel() async {
    const key = 'Hold Reasons_excel';
    _setLoading(key, true);
    try {
      final reasons = await ref.read(holdReasonServiceProvider).getReasons();
      if (reasons.isEmpty) {
        _showNoDataMessage();
        return;
      }
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => ExcelExportDialog(
            title: 'Export Hold Reasons',
            recordCount: reasons.length,
            fileName: 'Hold_Reasons_Audit.xlsx',
            onExport: () => ReportService().exportHoldReasonsToExcel(reasons),
            onSave: (bytes) => _handleFileSave(bytes, 'Hold_Reasons_Audit', 'xlsx'),
          ),
        );
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(key, false);
    }
  }

  Future<void> _generateCategoriesPdf() async {
    const key = 'Item Categories_pdf';
    _setLoading(key, true);
    try {
      final cats = await ref.read(packageCategoryServiceProvider).getCategories();
      if (cats.isEmpty) {
        _showNoDataMessage();
        return;
      }
      _showPdfPreview(
        (format) => ReportService().generateCategoriesPdf(cats),
        'Item_Categories_Audit.pdf',
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(key, false);
    }
  }

  Future<void> _exportCategoriesExcel() async {
    const key = 'Item Categories_excel';
    _setLoading(key, true);
    try {
      final cats = await ref.read(packageCategoryServiceProvider).getCategories();
      if (cats.isEmpty) {
        _showNoDataMessage();
        return;
      }

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => ExcelExportDialog(
            title: 'Export Item Categories',
            recordCount: cats.length,
            fileName: 'Item_Categories_Audit.xlsx',
            onExport: () => ReportService().exportCategoriesToExcel(cats),
            onSave: (bytes) => _handleFileSave(bytes, 'Item_Categories_Audit', 'xlsx'),
          ),
        );
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(key, false);
    }
  }
  Future<void> _generateLogsPdf() async {
    const key = 'Audit Logs_pdf';
    _setLoading(key, true);
    try {
      final allLogs = await ref.read(auditLogServiceProvider).getAllLogs();
      final filtered = _filterByDate(allLogs);
      
      if (filtered.isEmpty) {
        _showNoDataMessage();
        return;
      }

      final dateRangeStr = (_startDate != null && _endDate != null) 
          ? 'From ${DateFormat('yyyy-MM-dd').format(_startDate!)} To ${DateFormat('yyyy-MM-dd').format(_endDate!)}'
          : 'Full Historical Logs';

      _showPdfPreview(
        (format) => ReportService().generateLogsPdf(filtered, dateRangeStr),
        'System_Audit_Logs.pdf',
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(key, false);
    }
  }

  Future<void> _exportLogsExcel() async {
    const key = 'Audit Logs_excel';
    _setLoading(key, true);
    try {
      final allLogs = await ref.read(auditLogServiceProvider).getAllLogs();
      final filtered = _filterByDate(allLogs);

      if (filtered.isEmpty) {
        _showNoDataMessage();
        return;
      }

      final dateRangeStr = (_startDate != null && _endDate != null) 
          ? 'From ${DateFormat('yyyy-MM-dd').format(_startDate!)} To ${DateFormat('yyyy-MM-dd').format(_endDate!)}'
          : 'Full Historical Logs';

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => ExcelExportDialog(
            title: 'Export Audit Logs',
            recordCount: filtered.length,
            fileName: 'System_Audit_Logs.xlsx',
            onExport: () => ReportService().exportLogsToExcel(filtered, dateRangeStr),
            onSave: (bytes) => _handleFileSave(bytes, 'System_Audit_Logs', 'xlsx'),
          ),
        );
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(key, false);
    }
  }

  // ── New Report Handlers ──

  Future<void> _generateConfiscatedPdf() async {
    await _generateStatusReport('confiscated', 'pdf');
  }

  Future<void> _exportConfiscatedExcel() async {
    await _generateStatusReport('confiscated', 'excel');
  }

  Future<void> _generateWarehousesListPdf() async {
    const key = 'Warehouses List_pdf';
    _setLoading(key, true);
    try {
      final warehouses = await ref.read(warehouseServiceProvider).getWarehouses();
      final stats = await ref.read(warehouseServiceProvider).getWarehouseStats();
      if (warehouses.isEmpty) {
        _showNoDataMessage();
      } else {
        _showPdfPreview(
          (format) => ReportService().generateWarehousesListPdf(warehouses, stats),
          'Warehouses_List_Audit.pdf',
        );
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(key, false);
    }
  }

  Future<void> _exportWarehousesListExcel() async {
    const key = 'Warehouses List_excel';
    _setLoading(key, true);
    try {
      final warehouses = await ref.read(warehouseServiceProvider).getWarehouses();
      final stats = await ref.read(warehouseServiceProvider).getWarehouseStats();
      if (warehouses.isEmpty) {
        _showNoDataMessage();
      } else {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => ExcelExportDialog(
              title: 'Export Warehouses List',
              recordCount: warehouses.length,
              fileName: 'Warehouses_List_Audit.xlsx',
              onExport: () => ReportService().exportWarehousesListToExcel(warehouses, stats),
              onSave: (bytes) => _handleFileSave(bytes, 'Warehouses_List_Audit', 'xlsx'),
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

  Future<void> _generateStorageChargesPdf() async {
     const key = 'Storage Charges_pdf';
      _setLoading(key, true);
      try {
        final entries = await ref.read(warehouseServiceProvider).getAllWarehouseEntries(isReturned: false);
        final filteredEntries = _filterByDate(entries);
        if (filteredEntries.isEmpty) {
          _showNoDataMessage();
        } else {
          final packages = await ref.read(packageServiceProvider).getAllPackages();
          final rates = await ref.read(storageRateProvider.future);
          _showPdfPreview(
            (format) => ReportService().generateFinancialPdf(filteredEntries, packages, rates, isRevenue: false),
            'Storage_Charges_Report.pdf',
          );
        }
      } catch (e) {
        _showError(e.toString());
      } finally {
        _setLoading(key, false);
      }
  }

  Future<void> _exportStorageChargesExcel() async {
     const key = 'Storage Charges_excel';
      _setLoading(key, true);
      try {
        final entries = await ref.read(warehouseServiceProvider).getAllWarehouseEntries(isReturned: false);
        final filteredEntries = _filterByDate(entries);
        if (filteredEntries.isEmpty) {
          _showNoDataMessage();
        } else {
          final packages = await ref.read(packageServiceProvider).getAllPackages();
          final rates = await ref.read(storageRateProvider.future);
          if (mounted) {
            showDialog(
              context: context,
              builder: (ctx) => ExcelExportDialog(
                title: 'Export Storage Charges',
                recordCount: filteredEntries.length,
                fileName: 'Storage_Charges_Report.xlsx',
                onExport: () => ReportService().exportFinancialToExcel(filteredEntries, packages, rates, isRevenue: false),
                onSave: (bytes) => _handleFileSave(bytes, 'Storage_Charges_Report', 'xlsx'),
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

  Future<void> _generateReleasedRevenuePdf() async {
      const key = 'Released Revenue_pdf';
      _setLoading(key, true);
      try {
        final entries = await ref.read(warehouseServiceProvider).getAllWarehouseEntries(isReturned: true);
        final filteredEntries = _filterByDate(entries);
        if (filteredEntries.isEmpty) {
          _showNoDataMessage();
        } else {
          final packages = await ref.read(packageServiceProvider).getAllPackages();
          final rates = await ref.read(storageRateProvider.future);
          _showPdfPreview(
            (format) => ReportService().generateFinancialPdf(filteredEntries, packages, rates, isRevenue: true),
            'Released_Revenue_Report.pdf',
          );
        }
      } catch (e) {
        _showError(e.toString());
      } finally {
        _setLoading(key, false);
      }
  }

  Future<void> _exportReleasedRevenueExcel() async {
     const key = 'Released Revenue_excel';
      _setLoading(key, true);
      try {
        final entries = await ref.read(warehouseServiceProvider).getAllWarehouseEntries(isReturned: true);
        final filteredEntries = _filterByDate(entries);
        if (filteredEntries.isEmpty) {
          _showNoDataMessage();
        } else {
          final packages = await ref.read(packageServiceProvider).getAllPackages();
          final rates = await ref.read(storageRateProvider.future);
          if (mounted) {
            showDialog(
              context: context,
              builder: (ctx) => ExcelExportDialog(
                title: 'Export Released Revenue',
                recordCount: filteredEntries.length,
                fileName: 'Released_Revenue_Report.xlsx',
                onExport: () => ReportService().exportFinancialToExcel(filteredEntries, packages, rates, isRevenue: true),
                onSave: (bytes) => _handleFileSave(bytes, 'Released_Revenue_Report', 'xlsx'),
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


  List<T> _filterByDate<T>(List<T> list) {
    if (_startDate == null && _endDate == null) return list;
    return list.where((item) {
      DateTime? dt;
      if (item is PackageModel) {
        dt = item.entryDate;
      } else if (item is AuditLogModel) {
        dt = item.createdAt;
      } else if (item is ProfileModel) {
        dt = item.createdAt;
      } else if (item is WarehouseEntryModel) {
        dt = item.admittedAt;
      } else {
        return true;
      }

      if (dt == null) return false;

      // Start date normalization (midnight)
      if (_startDate != null) {
        final start = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
        if (dt.isBefore(start)) return false;
      }

      // End date normalization (end of day)
      if (_endDate != null) {
        final end = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
        if (dt.isAfter(end)) return false;
      }

      return true;
    }).toList();
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
