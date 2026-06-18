import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../services/report_service.dart';
import '../../models/models.dart';
import '../../widgets/print_barcode_dialog.dart';
import '../../widgets/styled_dropdown.dart';
import '../../widgets/date_range_picker_dialog.dart' as custom;
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
    final warehouses = ref.watch(warehousesProvider).valueOrNull ?? const [];

    final hasDate = _startDate != null || _endDate != null;
    final dateLabel = hasDate
        ? '${_startDate != null ? DateFormat('MMM d').format(_startDate!) : '…'} - ${_endDate != null ? DateFormat('MMM d').format(_endDate!) : '…'}'
        : 'Date Range';

    // Same look as the other pages' filter bar: gold-tinted card holding a row
    // of chip buttons + the shared StyledDropdownButton popups.
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.primaryGold.withOpacity(0.5)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // ── Date Range ──
          _filterChip(
            icon: Icons.date_range_rounded,
            label: dateLabel,
            active: hasDate,
            onTap: () async {
              final initial = (_startDate != null && _endDate != null)
                  ? DateTimeRange(start: _startDate!, end: _endDate!)
                  : null;
              final picked = await showDialog<dynamic>(
                context: context,
                builder: (_) =>
                    custom.DateRangePickerDialog(initialRange: initial),
              );
              if (picked is DateTimeRange) {
                setState(() {
                  _startDate = picked.start;
                  _endDate = picked.end;
                });
              } else if (picked == false) {
                setState(() {
                  _startDate = null;
                  _endDate = null;
                });
              }
            },
          ),
          if (hasDate)
            IconButton(
              icon: Icon(Icons.clear_rounded,
                  size: 16, color: context.colors.dangerRed),
              tooltip: 'Clear date filter',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => setState(() {
                _startDate = null;
                _endDate = null;
              }),
            ),
          // ── Status ── (null = All; styled popup like the other pages)
          StyledDropdownButton<String>(
            value: _selectedStatus == 'all' ? null : _selectedStatus,
            allLabel: 'All Statuses',
            icon: Icons.flag_rounded,
            options: const [
              StyledDropdownOption('pending', 'PENDING'),
              StyledDropdownOption('held', 'HELD'),
              StyledDropdownOption('cleared', 'CLEARED'),
              StyledDropdownOption('returned', 'RELEASED'),
            ],
            onChanged: (v) => setState(() => _selectedStatus = v ?? 'all'),
          ),
          // ── Warehouse ──
          StyledDropdownButton<String>(
            value: _selectedWarehouse == 'all' ? null : _selectedWarehouse,
            allLabel: 'All Warehouses',
            icon: Icons.warehouse_rounded,
            menuWidth: 320,
            options: warehouses
                .map((w) =>
                    StyledDropdownOption(w.id, '${w.code} - ${w.name}'))
                .toList(),
            onChanged: (v) => setState(() => _selectedWarehouse = v ?? 'all'),
          ),
        ],
      ),
    );
  }

  /// Outlined chip button (matches the other pages' Date Range / filter chips).
  Widget _filterChip({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final color =
        active ? context.colors.primaryGold : context.colors.textSecondary;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: color),
      label: Text(label,
          style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: active ? FontWeight.bold : FontWeight.normal)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(
            color: active
                ? context.colors.primaryGold
                : context.colors.borderColor),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  /// A chip that opens a popup menu of (value,label) choices — matches the
  /// "All Reasons" / "All Years" style popups on the other pages.
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
                    // (Removed "Confiscated Items" — it filtered on a package
                    // status 'confiscated' the app no longer uses, so it always
                    // returned empty. Forfeitures now live in forfeited_packages
                    // and are covered by the "Forfeited Packages" report below.)
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

                // ── Section: QR Code Labels ──
                const Gap(24),
                _buildSectionHeader('QR Code Labels', Icons.qr_code_2_rounded),
                const Gap(8),
                _QrLabelCard(onTap: _openQrLabelGenerator)
                    .animate()
                    .fadeIn()
                    .slideY(begin: 0.1),

                // ── Section: Disposal Lifecycle Reports (yard pages) ──
                const Gap(24),
                _buildSectionHeader(
                    'Disposal Lifecycle Reports', Icons.recycling_rounded),
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
                      title: 'Forfeited Packages',
                      description: 'All forfeited goods in this yard.',
                      icon: Icons.gavel_rounded,
                      color: const Color(0xFFC62828),
                      onPdf: () => _generateForfeitedReport('pdf'),
                      onExcel: () => _generateForfeitedReport('excel'),
                    ),
                    _buildReportCard(
                      title: 'Abandoned Packages',
                      description: 'Goods abandoned by the consignee.',
                      icon: Icons.inbox_rounded,
                      color: const Color(0xFF8D6E63),
                      onPdf: () => _generateSourceForfeitedReport(
                          'abandoned', 'Abandoned Packages', 'pdf'),
                      onExcel: () => _generateSourceForfeitedReport(
                          'abandoned', 'Abandoned Packages', 'excel'),
                    ),
                    _buildReportCard(
                      title: 'Other Packages',
                      description: 'Packages routed via "Other" disposition.',
                      icon: Icons.more_horiz_rounded,
                      color: const Color(0xFF5E35B1),
                      onPdf: () => _generateSourceForfeitedReport(
                          'other', 'Other Packages', 'pdf'),
                      onExcel: () => _generateSourceForfeitedReport(
                          'other', 'Other Packages', 'excel'),
                    ),
                    _buildReportCard(
                      title: 'Sold Packages',
                      description: 'Packages sold via tender in this yard.',
                      icon: Icons.sell_rounded,
                      color: const Color(0xFF2E7D32),
                      onPdf: () => _generateSoldReport('pdf'),
                      onExcel: () => _generateSoldReport('excel'),
                    ),
                    _buildReportCard(
                      title: 'Destroyed Packages',
                      description: 'Packages marked destroyed in this yard.',
                      icon: Icons.local_fire_department_rounded,
                      color: const Color(0xFFEF6C00),
                      onPdf: () => _generateDestroyedReport('pdf'),
                      onExcel: () => _generateDestroyedReport('excel'),
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
                      title: 'Released Packages',
                      description: 'All released package entries.',
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
                      description: 'Storage charges collected on released items.',
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
                    // (Audit Logs report removed per request.)
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

  // ── Disposal Lifecycle Reports (yard pages) ──────────────────────────────

  /// Forfeited Packages page report (all genuine forfeits in this yard).
  Future<void> _generateForfeitedReport(String format) async {
    await _emitForfeitedReport(
      key: 'Forfeited Packages',
      title: 'FORFEITED PACKAGES',
      fileBase: 'Forfeited_Packages',
      dateHeader: 'Forfeited On',
      format: format,
      fetch: () =>
          ref.read(forfeitedPackageServiceProvider).getForfeitedPackages(),
    );
  }

  /// Abandoned / "Other" page report — forfeited rows with a matching source.
  Future<void> _generateSourceForfeitedReport(
      String source, String label, String format) async {
    await _emitForfeitedReport(
      key: label,
      title: label.toUpperCase(),
      fileBase: label.replaceAll(' ', '_'),
      dateHeader: source == 'abandoned' ? 'Abandoned On' : 'Recorded On',
      format: format,
      fetch: () => ref
          .read(forfeitedPackageServiceProvider)
          .getForfeitedBySource(source),
    );
  }

  /// Shared emit for a forfeited-package list report (PDF preview or Excel).
  Future<void> _emitForfeitedReport({
    required String key,
    required String title,
    required String fileBase,
    required String format,
    required Future<List<ForfeitedPackageModel>> Function() fetch,
    String dateHeader = 'Date',
  }) async {
    final loadKey = '${key}_$format';
    _setLoading(loadKey, true);
    try {
      final list = _filterByDate(await fetch());
      if (list.isEmpty) {
        _showNoDataMessage();
        return;
      }
      final dateRange = (_startDate != null && _endDate != null)
          ? 'From ${DateFormat('yyyy-MM-dd').format(_startDate!)} To ${DateFormat('yyyy-MM-dd').format(_endDate!)}'
          : 'Full Historical Report';
      if (format == 'pdf') {
        _showPdfPreview(
          (_) => ReportService().generateForfeitedPdf(list,
              title: title, subTitle: dateRange, dateHeader: dateHeader),
          '${fileBase}_Report.pdf',
        );
      } else if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => ExcelExportDialog(
            title: 'Export $key',
            recordCount: list.length,
            fileName: '${fileBase}_Report.xlsx',
            onExport: () => ReportService()
                .exportForfeitedToExcel(list, title: title, dateHeader: dateHeader),
            onSave: (bytes) => _handleFileSave(bytes, fileBase, 'xlsx'),
          ),
        );
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(loadKey, false);
    }
  }

  /// Packages with a final SOLD warehouse tag in this yard.
  Future<void> _generateSoldReport(String format) =>
      _emitFinalTagPackageReport(
          tag: 'SOLD',
          key: 'Sold Packages',
          title: 'SOLD PACKAGES',
          fileBase: 'Sold_Packages',
          format: format);

  /// Packages with a final DESTROYED warehouse tag in this yard.
  Future<void> _generateDestroyedReport(String format) =>
      _emitFinalTagPackageReport(
          tag: 'DESTROYED',
          key: 'Destroyed Packages',
          title: 'DESTROYED PACKAGES',
          fileBase: 'Destroyed_Packages',
          format: format);

  /// Shared emit for packages bearing a `[FINAL:<tag>]` warehouse-entry tag
  /// (the Sold / Destroyed pages read the same tag).
  Future<void> _emitFinalTagPackageReport({
    required String tag,
    required String key,
    required String title,
    required String fileBase,
    required String format,
  }) async {
    final loadKey = '${key}_$format';
    _setLoading(loadKey, true);
    try {
      final all = await ref.read(packageServiceProvider).getAllPackages();
      final matches = all.where((p) => p.warehouseEntries.any((e) =>
          (e.returnNotes ?? '').toUpperCase().contains('[FINAL:$tag'))).toList();
      final list = _filterByDate(matches);
      if (list.isEmpty) {
        _showNoDataMessage();
        return;
      }
      final dateRange = (_startDate != null && _endDate != null)
          ? 'From ${DateFormat('yyyy-MM-dd').format(_startDate!)} To ${DateFormat('yyyy-MM-dd').format(_endDate!)}'
          : 'Full Historical Report';
      if (format == 'pdf') {
        _showPdfPreview(
          (fmt) => ReportService()
              .generatePackagePdf(list, title: title, dateRange: dateRange, format: fmt),
          '${fileBase}_Report.pdf',
        );
      } else if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => ExcelExportDialog(
            title: 'Export $key',
            recordCount: list.length,
            fileName: '${fileBase}_Report.xlsx',
            onExport: () =>
                ReportService().exportPackagesToExcel(list, title: title),
            onSave: (bytes) => _handleFileSave(bytes, fileBase, 'xlsx'),
          ),
        );
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(loadKey, false);
    }
  }

  /// Opens the QR-label generator: pick one/several packages, then print or
  /// download their QR-code labels (regenerated live from the package data, so
  /// any previously registered package's labels can be produced again anytime).
  Future<void> _openQrLabelGenerator() async {
    const key = 'QR Code Labels';
    _setLoading(key, true);
    List<PackageModel> all;
    try {
      all = await ref.read(packageServiceProvider).getAllPackages();
    } catch (e) {
      _showError(e.toString());
      return;
    } finally {
      _setLoading(key, false);
    }
    if (!mounted) return;
    if (all.isEmpty) {
      _showNoDataMessage();
      return;
    }
    final selected = await showDialog<List<PackageModel>>(
      context: context,
      builder: (_) => _QrLabelPickerDialog(packages: all),
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    // Reuse the existing print/save dialog for the chosen packages.
    showDialog(
      context: context,
      builder: (_) => PrintBarcodeDialog(packages: selected),
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
    const key = 'Released Packages_pdf';
    _setLoading(key, true);
    try {
      final entries = await ref.read(warehouseServiceProvider).getAllWarehouseEntries(isReturned: true);
      final filtered = _filterByDate(entries);
      _showPdfPreview(
        (format) => ReportService().generateWarehousePdf(
          filtered, 
          title: 'Released Packages Report',
          isReturnedReport: true,
          format: format,
        ),
        'Released_Packages_Report.pdf',
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(key, false);
    }
  }

  Future<void> _exportReturnedExcel() async {
    const key = 'Released Packages_excel';
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
              title: 'Export Released Data',
              recordCount: filtered.length,
              fileName: 'Released_Packages_Report.xlsx',
              onExport: () => ReportService().exportWarehouseToExcel(filtered, isReturned: true),
              onSave: (bytes) => _handleFileSave(bytes, 'Released_Packages', 'xlsx'),
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

  // The disposition buckets a period summary tracks, beyond admit/release.
  static const List<String> _summaryDispoCols = [
    'forfeit', 'abandoned', 're-export', 'destroy', 'sold', 'other'
  ];

  String _periodKey(DateTime d, String periodType) {
    if (periodType == 'day') return DateFormat('yyyy-MM-dd').format(d);
    if (periodType == 'week') return 'Year ${d.year} - Week ${(d.day / 7).ceil()}';
    return DateFormat('yyyy-MM').format(d);
  }

  /// Classify a released entry into a disposition bucket using its return-note
  /// tag (same tags the disposition pages read) — falling back to a plain
  /// release. Returns null for entries that aren't a disposition.
  String? _dispoOf(WarehouseEntryModel e) {
    final n = (e.returnNotes ?? '').toUpperCase();
    if (n.contains('FORFEIT')) return 'forfeit';
    if (n.contains('ABANDON')) return 'abandoned';
    if (n.contains('RE-EXPORT') || n.contains('REEXPORT')) return 're-export';
    if (n.contains('DESTROY')) return 'destroy';
    if (n.contains('SOLD') || n.contains('SALE')) return 'sold';
    if (n.contains('OTHER')) return 'other';
    return null; // plain release
  }

  List<Map<String, dynamic>> _calculateSummary(List<WarehouseEntryModel> entries, String periodType) {
    final Map<String, Map<String, int>> groups = {};
    Map<String, int> blank() => {
          'admitted': 0,
          'returned': 0,
          for (final c in _summaryDispoCols) c: 0,
        };

    for (var e in entries) {
      // Admissions counted by admit date.
      final aKey = _periodKey(e.admittedAt, periodType);
      groups[aKey] ??= blank();
      groups[aKey]!['admitted'] = groups[aKey]!['admitted']! + 1;

      // Releases / dispositions counted by the release date.
      if (e.isReturned && e.returnedAt != null) {
        final rKey = _periodKey(e.returnedAt!, periodType);
        groups[rKey] ??= blank();
        groups[rKey]!['returned'] = groups[rKey]!['returned']! + 1;
        final dispo = _dispoOf(e);
        if (dispo != null) {
          groups[rKey]![dispo] = (groups[rKey]![dispo] ?? 0) + 1;
        }
      }
    }

    final sortedKeys = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    return sortedKeys.map((k) => {
      'period': k,
      'admitted': groups[k]!['admitted'],
      'returned': groups[k]!['returned'],
      for (final c in _summaryDispoCols) c: groups[k]![c],
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

  // ── New Report Handlers ──

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
      } else if (item is ForfeitedPackageModel) {
        dt = item.forfeitedAt;
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
             widget.fileName.toLowerCase().contains('released');
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

/// A wide call-to-action card for the QR Code Labels generator.
class _QrLabelCard extends StatelessWidget {
  final VoidCallback onTap;
  const _QrLabelCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFF00897B); // teal
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [accent.withOpacity(0.10), context.colors.cardDark],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withOpacity(0.35)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: accent.withOpacity(0.4)),
            ),
            child: Icon(Icons.qr_code_2_rounded, color: accent, size: 26),
          ),
          const Gap(16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Generate QR Code Labels',
                    style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
                const Gap(3),
                Text(
                    'Pick one or more registered packages and print or download their QR-code labels anytime.',
                    style: TextStyle(
                        color: context.colors.textSecondary, fontSize: 12.5)),
              ],
            ),
          ),
          const Gap(12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: accent, foregroundColor: Colors.white),
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('Open'),
            onPressed: onTap,
          ),
        ]),
      ),
    );
  }
}

/// Searchable multi-select package picker. Returns the chosen packages (or null
/// if cancelled) so the caller can generate their QR labels.
class _QrLabelPickerDialog extends StatefulWidget {
  final List<PackageModel> packages;
  const _QrLabelPickerDialog({required this.packages});

  @override
  State<_QrLabelPickerDialog> createState() => _QrLabelPickerDialogState();
}

class _QrLabelPickerDialogState extends State<_QrLabelPickerDialog> {
  final _selected = <String>{};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gold = context.colors.primaryGold;
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.packages
        : widget.packages.where((p) {
            final items = p.items.map((i) => i.itemName).join(' ').toLowerCase();
            return p.srNumber.toLowerCase().contains(q) ||
                p.consigneeName.toLowerCase().contains(q) ||
                items.contains(q);
          }).toList();
    final allShownSelected = filtered.isNotEmpty &&
        filtered.every((p) => _selected.contains(p.id));

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 720,
        decoration: BoxDecoration(
          color: context.colors.scaffoldBg,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 40,
                offset: const Offset(0, 15)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header (matches the New Disposal Request dialog) ──
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [context.colors.surfaceDark, context.colors.cardDark]
                      : [
                          context.colors.customsBlue,
                          context.colors.customsBlueDark
                        ],
                ),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.qr_code_2_rounded, color: gold, size: 24),
                ),
                const Gap(16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('QR CODE LABELS',
                          style: TextStyle(
                              color: gold,
                              fontSize: 11,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w800)),
                      const Text('Select Packages',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
            ),
            // ── Body ──
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Search
                    TextField(
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search SR #, consignee or item…',
                        prefixIcon: Icon(Icons.search_rounded,
                            color: context.colors.textMuted),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                    const Gap(14),
                    // Section card (matches the disposal dialog's list card)
                    Flexible(
                      child: Container(
                        decoration: BoxDecoration(
                          color: context.colors.cardDark,
                          borderRadius: BorderRadius.circular(14),
                          border:
                              Border.all(color: context.colors.borderColor),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Card header: count + Select/Clear all
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                              child: Row(children: [
                                Text(
                                    '${_selected.length} of ${widget.packages.length} selected',
                                    style: TextStyle(
                                        color: context.colors.textSecondary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                                const Spacer(),
                                TextButton.icon(
                                  onPressed: () => setState(() {
                                    if (allShownSelected) {
                                      _selected.removeAll(
                                          filtered.map((p) => p.id));
                                    } else {
                                      _selected
                                          .addAll(filtered.map((p) => p.id));
                                    }
                                  }),
                                  icon: Icon(
                                      allShownSelected
                                          ? Icons.remove_done_rounded
                                          : Icons.done_all_rounded,
                                      size: 16,
                                      color: gold),
                                  label: Text(
                                      allShownSelected
                                          ? 'Clear All'
                                          : 'Select All',
                                      style: TextStyle(
                                          color: gold,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700)),
                                ),
                              ]),
                            ),
                            Divider(
                                height: 1, color: context.colors.borderColor),
                            // List
                            Flexible(
                              child: filtered.isEmpty
                                  ? Padding(
                                      padding: const EdgeInsets.all(28),
                                      child: Text('No matching packages',
                                          style: TextStyle(
                                              color:
                                                  context.colors.textMuted)),
                                    )
                                  : ListView.separated(
                                      shrinkWrap: true,
                                      itemCount: filtered.length,
                                      separatorBuilder: (_, __) => Divider(
                                          height: 1,
                                          color: context.colors.borderColor
                                              .withOpacity(0.5)),
                                      itemBuilder: (context, i) {
                                        final p = filtered[i];
                                        return _QrPackageRow(
                                          package: p,
                                          isSelected:
                                              _selected.contains(p.id),
                                          onToggle: () => setState(() {
                                            if (_selected.contains(p.id)) {
                                              _selected.remove(p.id);
                                            } else {
                                              _selected.add(p.id);
                                            }
                                          }),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ── Footer ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              child: Row(children: [
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel',
                      style: TextStyle(color: context.colors.textSecondary)),
                ),
                const Gap(8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: gold,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14)),
                  icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                  label: Text('Generate (${_selected.length})'),
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.pop(
                            context,
                            widget.packages
                                .where((p) => _selected.contains(p.id))
                                .toList(),
                          ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// One package row in the QR picker — styled like the disposal-request rows:
/// leading gold checkbox, accent SR number, item · consignee subline, and a
/// gold tint when selected.
class _QrPackageRow extends StatelessWidget {
  final PackageModel package;
  final bool isSelected;
  final VoidCallback onToggle;
  const _QrPackageRow({
    required this.package,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final itemLabel = package.items.isEmpty
        ? '—'
        : (package.items.length == 1
            ? package.items.first.itemName
            : '${package.items.first.itemName} +${package.items.length - 1}');
    return InkWell(
      onTap: onToggle,
      child: Container(
        color: isSelected
            ? context.colors.primaryGold.withOpacity(0.06)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(children: [
          Checkbox(
            activeColor: context.colors.primaryGold,
            value: isSelected,
            onChanged: (_) => onToggle(),
          ),
          const Gap(4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(package.srNumber,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: context.colors.accentLightBlue)),
                Text('$itemLabel · ${package.consigneeName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: context.colors.textSecondary)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
