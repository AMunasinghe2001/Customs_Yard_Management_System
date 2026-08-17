import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../core/yards.dart';
import '../../services/report_service.dart';
import '../../models/models.dart';
import '../../widgets/print_barcode_dialog.dart';
import '../../widgets/styled_dropdown.dart';
import '../../widgets/date_range_picker_dialog.dart' as custom;
import '../../widgets/tooltip_text.dart';
import 'package:intl/intl.dart';
import 'package:gap/gap.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../widgets/error_view.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  /// Executive Office (DG / ADG) mode: shows a Yard selector and scopes every
  /// report to the picked yard. Officers/admins use the default (false), where
  /// RLS already limits data to their own yard.
  final bool executiveMode;
  const ReportsScreen({super.key, this.executiveMode = false});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  DateTime? _startDate;
  DateTime? _endDate;
  String _dateFilterType = 'range'; // 'range' | 'day' | 'month' | 'year'
  String _selectedStatus = 'all';
  String _selectedWarehouse = 'all';
  // Executive mode: the yard whose reports are generated (null = none picked).
  String? _reportYard;

  /// The yard passed to the data services. Executive mode → the picked yard
  /// (report cards are only shown once one is picked, so it's non-null here);
  /// officer mode → null, so RLS scopes data to the officer's own yard.
  String? get _yardArg => widget.executiveMode ? _reportYard : null;

  /// Client-side yard filter for report lists whose service can't take a yard
  /// (e.g. forfeited packages). No-op in officer mode.
  List<T> _filterByYard<T>(List<T> rows, String? Function(T) yardOf) {
    if (!widget.executiveMode || _reportYard == null) return rows;
    return rows.where((r) => yardOf(r) == _reportYard).toList();
  }
  
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
                child: (widget.executiveMode && _reportYard == null)
                    ? _selectYardPrompt()
                    : _buildReportCards(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleDatePick() async {
    final now = DateTime.now();
    if (_dateFilterType == 'day') {
      final picked = await showDatePicker(
        context: context,
        initialDate: _startDate ?? now,
        firstDate: DateTime(2020),
        lastDate: DateTime(2030),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.dark(
                primary: context.colors.primaryGold,
                onPrimary: Colors.black,
                surface: context.colors.cardDark,
                onSurface: context.colors.textPrimary,
              ),
            ),
            child: child!,
          );
        },
      );
      if (picked != null) {
        setState(() {
          _startDate = DateTime(picked.year, picked.month, picked.day);
          _endDate = DateTime(picked.year, picked.month, picked.day);
        });
      }
    } else if (_dateFilterType == 'month') {
      final initialY = _startDate?.year ?? now.year;
      final initialM = _startDate?.month ?? now.month;
      final picked = await _showMonthPickerDialog(context, initialY, initialM);
      if (picked != null) {
        setState(() {
          _startDate = DateTime(picked.year, picked.month, 1);
          _endDate = DateTime(picked.year, picked.month + 1, 0);
        });
      }
    } else if (_dateFilterType == 'year') {
      final initialY = _startDate?.year ?? now.year;
      final picked = await _showYearPickerDialog(context, initialY);
      if (picked != null) {
        setState(() {
          _startDate = DateTime(picked, 1, 1);
          _endDate = DateTime(picked, 12, 31);
        });
      }
    } else {
      final initial = (_startDate != null && _endDate != null)
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null;
      final picked = await showDialog<dynamic>(
        context: context,
        builder: (_) => custom.DateRangePickerDialog(initialRange: initial),
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
    }
  }

  Future<({int year, int month})?> _showMonthPickerDialog(
      BuildContext context, int initialYear, int initialMonth) async {
    int selectedYear = initialYear;
    int selectedMonth = initialMonth;
    final currentYear = DateTime.now().year;
    final years = List.generate(10, (i) => currentYear - i);
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];

    return showDialog<({int year, int month})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: context.colors.cardDark,
          title: Text('Select Month & Year',
              style: TextStyle(color: context.colors.textPrimary)),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: selectedMonth,
                  dropdownColor: context.colors.cardDark,
                  style: TextStyle(color: context.colors.textPrimary),
                  items: List.generate(
                      12,
                      (i) => DropdownMenuItem(
                            value: i + 1,
                            child: Text(months[i]),
                          )),
                  onChanged: (v) {
                    if (v != null) setDlgState(() => selectedMonth = v);
                  },
                ),
              ),
              const Gap(12),
              Expanded(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: selectedYear,
                  dropdownColor: context.colors.cardDark,
                  style: TextStyle(color: context.colors.textPrimary),
                  items: years
                      .map((y) => DropdownMenuItem(
                            value: y,
                            child: Text('$y'),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDlgState(() => selectedYear = v);
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(ctx, (year: selectedYear, month: selectedMonth)),
              child: const Text('Select'),
            ),
          ],
        ),
      ),
    );
  }

  Future<int?> _showYearPickerDialog(
      BuildContext context, int initialYear) async {
    int selectedYear = initialYear;
    final currentYear = DateTime.now().year;
    final years = List.generate(10, (i) => currentYear - i);

    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: context.colors.cardDark,
          title: Text('Select Year',
              style: TextStyle(color: context.colors.textPrimary)),
          content: SizedBox(
            width: 240,
            child: DropdownButton<int>(
              isExpanded: true,
              value: selectedYear,
              dropdownColor: context.colors.cardDark,
              style: TextStyle(color: context.colors.textPrimary),
              items: years
                  .map((y) => DropdownMenuItem(
                        value: y,
                        child: Text('$y'),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setDlgState(() => selectedYear = v);
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, selectedYear),
              child: const Text('Select'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterSection() {
    final warehouses = ref.watch(warehousesProvider).valueOrNull ?? const [];

    final hasDate = _startDate != null || _endDate != null;
    String dateLabel;
    if (!hasDate) {
      if (_dateFilterType == 'day') dateLabel = 'Pick Day';
      else if (_dateFilterType == 'month') dateLabel = 'Pick Month';
      else if (_dateFilterType == 'year') dateLabel = 'Pick Year';
      else dateLabel = 'Custom Range';
    } else {
      if (_dateFilterType == 'day') {
        dateLabel = 'Day: ${DateFormat('yyyy-MM-dd').format(_startDate!)}';
      } else if (_dateFilterType == 'month') {
        dateLabel = 'Month: ${DateFormat('MMM yyyy').format(_startDate!)}';
      } else if (_dateFilterType == 'year') {
        dateLabel = 'Year: ${_startDate!.year}';
      } else {
        dateLabel = '${DateFormat('MMM d').format(_startDate!)} - ${DateFormat('MMM d').format(_endDate!)}';
      }
    }

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
          // ── Yard (Executive Office only) ──
          if (widget.executiveMode)
            StyledDropdownButton<String>(
              value: _reportYard,
              allLabel: 'Select Yard',
              icon: Icons.location_city_rounded,
              menuWidth: 260,
              options: kYards
                  .map((y) => StyledDropdownOption(y.code, y.name))
                  .toList(),
              onChanged: (v) => setState(() => _reportYard = v),
            ),

          // ── Date Filter Mode Selector ──
          StyledDropdownButton<String>(
            value: _dateFilterType,
            allLabel: 'Date Filter',
            icon: Icons.calendar_month_rounded,
            menuWidth: 200,
            options: const [
              StyledDropdownOption('range', 'Custom Date Range'),
              StyledDropdownOption('day', 'Single Day'),
              StyledDropdownOption('month', 'By Month'),
              StyledDropdownOption('year', 'By Year'),
            ],
            onChanged: (v) {
              if (v != null && v != _dateFilterType) {
                setState(() {
                  _dateFilterType = v;
                  _startDate = null;
                  _endDate = null;
                });
                _handleDatePick();
              }
            },
          ),

          // ── Date Picker Action Chip ──
          _filterChip(
            icon: _dateFilterType == 'day'
                ? Icons.today_rounded
                : (_dateFilterType == 'month'
                    ? Icons.calendar_view_month_rounded
                    : (_dateFilterType == 'year'
                        ? Icons.calendar_view_week_rounded
                        : Icons.date_range_rounded)),
            label: dateLabel,
            active: hasDate,
            onTap: _handleDatePick,
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

          // ── Status ──
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
  /// Executive Office prompt shown until a yard is picked (reports are
  /// per-yard, so no report can run without one).
  Widget _selectYardPrompt() {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_city_rounded,
              size: 56, color: context.colors.textMuted),
          const Gap(16),
          Text('Select a yard to generate reports',
              style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const Gap(6),
          Text('Use the “Select Yard” dropdown above.',
              style:
                  TextStyle(color: context.colors.textMuted, fontSize: 13)),
        ],
      ),
    );
  }

  // ── In-app report viewer ─────────────────────────────────────────────────
  // The primary way to consume a report is to view its rows right here in the
  // app (pretty table); PDF / Excel are secondary exports inside the viewer.

  static const List<String> _packageCols = [
    'SR Number', 'Item', 'HS Code', 'Qty', 'Consignee', 'Status',
    'Entry Date', 'Value (LKR)'
  ];
  List<List<String>> _packageRows(List<PackageModel> pkgs) {
    final f = NumberFormat('#,##0');
    return pkgs.map((p) {
      final item = p.items.isNotEmpty ? p.items.first : null;
      final name = p.items.isEmpty
          ? '—'
          : (p.items.length == 1
              ? item!.itemName
              : '${item!.itemName} +${p.items.length - 1}');
      return [
        p.srNumber,
        name,
        item?.hsCode ?? '—',
        '${p.effectiveItemCount}',
        p.consigneeName,
        p.status.toUpperCase(),
        p.entryDate != null
            ? DateFormat('yyyy-MM-dd').format(p.entryDate!)
            : '—',
        f.format(p.declaredValue),
      ];
    }).toList();
  }

  static const List<String> _forfeitedCols = [
    'SR Number', 'Item', 'HS Code', 'Qty', 'Consignee', 'Forfeited On'
  ];
  List<List<String>> _forfeitedRows(List<ForfeitedPackageModel> list) {
    return list.map((fp) {
      final items = fp.packageDetails?.items ?? const <PackageItem>[];
      final item = items.isNotEmpty ? items.first : null;
      final qty = fp.entryQty ??
          (item?.quantity ?? items.fold<int>(0, (s, i) => s + i.quantity));
      return [
        fp.srNumber,
        fp.itemName ?? item?.itemName ?? '—',
        item?.hsCode ?? '—',
        '$qty',
        fp.consigneeName,
        DateFormat('yyyy-MM-dd').format(fp.forfeitedAt),
      ];
    }).toList();
  }

  /// The shared in-app table dialog. Save PDF / Export Excel sit in the footer.
  Future<void> _showReportTable({
    required String title,
    String? subtitle,
    required List<String> columns,
    required List<List<String>> rows,
    VoidCallback? onSavePdf,
    VoidCallback? onExportExcel,
  }) async {
    if (rows.isEmpty) {
      _showNoDataMessage();
      return;
    }
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(28),
        backgroundColor: context.colors.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: 1150,
              maxHeight: MediaQuery.of(ctx).size.height * 0.86),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: TextStyle(
                                color: context.colors.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w800)),
                        Text('${rows.length} record(s)${subtitle != null ? ' · $subtitle' : ''}',
                            style: TextStyle(
                                color: context.colors.textMuted,
                                fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded,
                        color: context.colors.textMuted),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ]),
              ),
              const Divider(height: 1),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DataTable2(
                    columnSpacing: 12,
                    horizontalMargin: 12,
                    fixedTopRows: 1,
                    isVerticalScrollBarVisible: true,
                    columns: columns
                        .map((c) => DataColumn2(
                            label: Text(c,
                                style: TextStyle(
                                    color: context.colors.primaryGold,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12))))
                        .toList(),
                    rows: rows
                        .map((r) => DataRow(
                            cells: r
                                .map((c) => DataCell(TooltipText(c,
                                    style: TextStyle(
                                        color: context.colors.textPrimary,
                                        fontSize: 12.5))))
                                .toList()))
                        .toList(),
                  ),
                ),
              ),
              const Divider(height: 1),
              // Footer — secondary exports
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  const Spacer(),
                  if (onExportExcel != null)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.green),
                      icon: const Icon(Icons.table_chart_outlined, size: 16),
                      label: const Text('Export Excel'),
                      onPressed: onExportExcel,
                    ),
                  if (onExportExcel != null) const Gap(10),
                  if (onSavePdf != null)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: context.colors.customsBlue,
                          foregroundColor: Colors.white),
                      icon: const Icon(Icons.picture_as_pdf_outlined,
                          size: 16),
                      label: const Text('Save PDF'),
                      onPressed: onSavePdf,
                    ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// View a package-list report in-app (with PDF / Excel export).
  Future<void> _viewPackages(String status, String title,
      {String? subtitle}) async {
    final key = '${title}_view';
    _setLoading(key, true);
    try {
      final pkgs = _filterByWarehouse(_filterByDate(
          await ref.read(packageServiceProvider).getAllPackages(
              status: status == 'all' ? null : status, yard: _yardArg)));
      final base = title.replaceAll(' ', '_');
      await _showReportTable(
        title: title,
        subtitle: subtitle,
        columns: _packageCols,
        rows: _packageRows(pkgs),
        onSavePdf: () => _showPdfPreview(
            (f) => ReportService()
                .generatePackagePdf(pkgs, title: title, format: f),
            '$base.pdf'),
        onExportExcel: () {
          if (!mounted) return;
          showDialog(
            context: context,
            builder: (c) => ExcelExportDialog(
              title: 'Export $title',
              recordCount: pkgs.length,
              fileName: '$base.xlsx',
              onExport: () => ReportService().exportPackagesToExcel(pkgs),
              onSave: (b) => _handleFileSave(b, base, 'xlsx'),
            ),
          );
        },
      );
    } finally {
      _setLoading(key, false);
    }
  }

  /// View a forfeited-list report in-app (with PDF / Excel export).
  Future<void> _viewForfeited(String key, String title, String dateHeader,
      Future<List<ForfeitedPackageModel>> Function() fetch) async {
    _setLoading('${title}_view', true);
    try {
      final list =
          _filterByDate(_filterByYard(await fetch(), (f) => f.yard));
      final base = title.replaceAll(' ', '_');
      await _showReportTable(
        title: title,
        columns: _forfeitedCols,
        rows: _forfeitedRows(list),
        onSavePdf: () => _showPdfPreview(
            (_) => ReportService().generateForfeitedPdf(list,
                title: title,
                subTitle: 'Full Historical Report',
                dateHeader: dateHeader),
            '${base}_Report.pdf'),
        onExportExcel: () {
          if (!mounted) return;
          showDialog(
            context: context,
            builder: (c) => ExcelExportDialog(
              title: 'Export $title',
              recordCount: list.length,
              fileName: '${base}_Report.xlsx',
              onExport: () => ReportService()
                  .exportForfeitedToExcel(list, title: title, dateHeader: dateHeader),
              onSave: (b) => _handleFileSave(b, base, 'xlsx'),
            ),
          );
        },
      );
    } finally {
      _setLoading('${title}_view', false);
    }
  }

  /// View stock & revenue reconciliation statement in-app.
  Future<void> _viewStockReconciliation() async {
    await _stockRevenueReport('reconciliation', 'view');
  }

  Widget _buildReportCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 900 ? 3 : (constraints.maxWidth > 600 ? 2 : 1);

        return FutureBuilder<ProfileModel?>(
          future: ref.read(authServiceProvider).getCurrentProfile(),
          builder: (context, snapshot) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (snapshot.hasError) 
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: ErrorView(error: snapshot.error!, onRetry: () => setState(() {})),
                  ),

                // ── Section 1: SR Register & Inventory Reports ──
                _buildSectionHeader('SR Register & Inventory Reports', Icons.article_rounded),
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
                      onView: () =>
                          _viewPackages(_selectedStatus, 'Packages Inventory Audit'),
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
                      title: 'Package History',
                      description:
                          'Full details of a single package by its SR number.',
                      icon: Icons.description_rounded,
                      color: context.colors.accentLightBlue,
                      onPdf: _generatePackageHistoryPdf,
                      onExcel: _exportPackageHistoryExcel,
                    ),
                    _buildReportCard(
                      title: 'Old Entries (Migrated Packages)',
                      description:
                          'Packages migrated from a previous register (old SR → new SR).',
                      icon: Icons.history_rounded,
                      color: const Color(0xFF5D4037),
                      onPdf: () => _generateOldEntriesReport('pdf'),
                      onExcel: () => _generateOldEntriesReport('excel'),
                    ),
                  ],
                ),

                // ── Section 2: Goods Disposition Reports ──
                // (How goods are classified: Forfeit / Abandon / Other / Re-export)
                const Gap(24),
                _buildSectionHeader(
                    'Goods Disposition Reports', Icons.assignment_turned_in_rounded),
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
                      title: 'Forfeited Packages (Forfeited Goods)',
                      description: 'All forfeited goods in this yard.',
                      icon: Icons.gavel_rounded,
                      color: const Color(0xFFC62828),
                      onView: () => _viewForfeited(
                          'Forfeited',
                          'Forfeited Packages (Forfeited Goods)',
                          'Forfeited On',
                          () => ref
                              .read(forfeitedPackageServiceProvider)
                              .getForfeitedPackages()),
                      onPdf: () => _generateForfeitedReport('pdf'),
                      onExcel: () => _generateForfeitedReport('excel'),
                    ),
                    _buildReportCard(
                      title: 'Abandoned Packages (Abandoned Goods)',
                      description: 'Goods abandoned by the consignee.',
                      icon: Icons.inbox_rounded,
                      color: const Color(0xFF8D6E63),
                      onView: () => _viewForfeited(
                          'Abandoned',
                          'Abandoned Packages (Abandoned Goods)',
                          'Abandoned On',
                          () => ref
                              .read(forfeitedPackageServiceProvider)
                              .getForfeitedBySource('abandoned')),
                      onPdf: () => _generateSourceForfeitedReport(
                          'abandoned', 'Abandoned Packages (Abandoned Goods)', 'pdf'),
                      onExcel: () => _generateSourceForfeitedReport(
                          'abandoned', 'Abandoned Packages (Abandoned Goods)', 'excel'),
                    ),
                    _buildReportCard(
                      title: 'Other Packages (Other Goods)',
                      description: 'Packages routed via "Other" disposition.',
                      icon: Icons.more_horiz_rounded,
                      color: const Color(0xFF5E35B1),
                      onView: () => _viewForfeited(
                          'Other',
                          'Other Packages (Other Goods)',
                          'Recorded On',
                          () => ref
                              .read(forfeitedPackageServiceProvider)
                              .getForfeitedBySource('other')),
                      onPdf: () => _generateSourceForfeitedReport(
                          'other', 'Other Packages (Other Goods)', 'pdf'),
                      onExcel: () => _generateSourceForfeitedReport(
                          'other', 'Other Packages (Other Goods)', 'excel'),
                    ),
                    _buildReportCard(
                      title: 'Re-exported Packages (Re-exported Goods)',
                      description: 'Packages routed via Re-export disposition.',
                      icon: Icons.flight_takeoff_rounded,
                      color: const Color(0xFF00796B),
                      onPdf: () => _generateReexportedReport('pdf'),
                      onExcel: () => _generateReexportedReport('excel'),
                    ),
                  ],
                ),

                // ── Section 3: Goods Disposal Reports ──
                // (What happens to forfeited goods: Sold via Tender / Destroyed)
                const Gap(24),
                _buildSectionHeader(
                    'Goods Disposal Reports', Icons.recycling_rounded),
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
                      title: 'Sold Packages (Goods Sold - Tender)',
                      description: 'Forfeited goods sold via tender during the period.',
                      icon: Icons.sell_rounded,
                      color: Colors.teal,
                      onPdf: () => _stockRevenueReport('sold', 'pdf'),
                      onExcel: () => _stockRevenueReport('sold', 'excel'),
                    ),
                    _buildReportCard(
                      title: 'Destroyed Packages (Goods Destroyed)',
                      description:
                          'Forfeited goods destroyed in destruction tender during the period.',
                      icon: Icons.local_fire_department_rounded,
                      color: Colors.deepOrange,
                      onPdf: () => _stockRevenueReport('destroyed', 'pdf'),
                      onExcel: () => _stockRevenueReport('destroyed', 'excel'),
                    ),
                  ],
                ),

                // ── Section 4: Stock & Revenue Reports ──
                const Gap(24),
                _buildSectionHeader(
                    'Stock & Revenue Reports', Icons.inventory_rounded),
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
                      title: 'Initial Stock (Goods in SR)',
                      description:
                          'Goods in the SR register as at the period start date.',
                      icon: Icons.warehouse_rounded,
                      color: context.colors.primaryGold,
                      onPdf: () => _stockRevenueReport('initial', 'pdf'),
                      onExcel: () => _stockRevenueReport('initial', 'excel'),
                    ),
                    _buildReportCard(
                      title: 'Packages Inventory (Goods in SR)',
                      description:
                          'Total goods currently in the SR register.',
                      icon: Icons.inventory_2_rounded,
                      color: context.colors.accentLightBlue,
                      onPdf: () => _stockRevenueReport('total', 'pdf'),
                      onExcel: () => _stockRevenueReport('total', 'excel'),
                    ),
                    _buildReportCard(
                      title: 'Packages Added (Goods Added)',
                      description:
                          'Goods added during the selected period.',
                      icon: Icons.add_box_rounded,
                      color: context.colors.successGreen,
                      onPdf: () => _stockRevenueReport('added', 'pdf'),
                      onExcel: () => _stockRevenueReport('added', 'excel'),
                    ),
                    _buildReportCard(
                      title: 'Revenue & Balance',
                      description:
                          'Tender revenue (sold price + taxes) & net stock balance.',
                      icon: Icons.payments_rounded,
                      color: Colors.indigo,
                      onPdf: () => _stockRevenueReport('revenue', 'pdf'),
                      onExcel: () => _stockRevenueReport('revenue', 'excel'),
                    ),
                    _buildReportCard(
                      title: 'Executive Stock & Revenue Reconciliation',
                      description:
                          'Initial + Added − Sold − Destroyed = Net Balance & Value.',
                      icon: Icons.account_balance_rounded,
                      color: context.colors.primaryGold,
                      onView: () => _viewStockReconciliation(),
                      onPdf: () => _stockRevenueReport('reconciliation', 'pdf'),
                      onExcel: () => _stockRevenueReport('reconciliation', 'excel'),
                    ),
                  ],
                ),

                // ── Section 5: Warehouse & Movement Reports ──
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
                      title: 'Warehouse Stock (Held Goods)',
                      description: 'Currently held items in warehouses.',
                      icon: Icons.warehouse_rounded,
                      color: const Color(0xFF1565C0),
                      onPdf: _generateWarehouseStockPdf,
                      onExcel: _exportWarehouseStockExcel,
                    ),
                    _buildReportCard(
                      title: 'Released Packages (Released Goods)',
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
                  ],
                ),

                // ── Section 6: Financial Reports ──
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

                // ── Section 7: System Configuration & Logs ──
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
                  ],
                ),

                // ── Section 8: QR Code Labels ──
                const Gap(24),
                _buildSectionHeader('QR Code Labels', Icons.qr_code_2_rounded),
                const Gap(8),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 2.3,
                  children: [
                    _buildQrCard(),
                  ],
                ),
              ],
            ).animate().slideY(begin: 0.1, duration: 400.ms, delay: 100.ms).fadeIn();
          },
        );
      },
    );
  }

  Widget _buildQrCard() {
    const color = Color(0xFF00897B);
    const key = 'QR Code Labels';
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
          Row(children: [
            const Icon(Icons.qr_code_2_rounded, color: color, size: 18),
            const Gap(8),
            Expanded(child: Text('Generate QR Labels',
                style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14))),
          ]),
          const Gap(4),
          Text('Pick packages and print or download their QR-code labels.',
              style: TextStyle(color: context.colors.textMuted, fontSize: 11),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: _buildActionButton(
              label: 'Open',
              icon: Icons.open_in_new_rounded,
              color: color,
              isLoading: _isLoading(key),
              onTap: _openQrLabelGenerator,
            ),
          ),
        ],
      ),
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
      final packages = await ref.read(packageServiceProvider).getAllPackages(status: status, yard: _yardArg);
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
      final packages = await ref.read(packageServiceProvider).getAllPackages(yard: _yardArg);
      final entries = await ref.read(warehouseServiceProvider).getAllWarehouseEntries(yard: _yardArg);
      
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
      final packages = await ref.read(packageServiceProvider).getAllPackages(yard: _yardArg);
      final entries = await ref.read(warehouseServiceProvider).getAllWarehouseEntries(yard: _yardArg);
      
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
        yard: _yardArg,
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

      // Same item-level full column set as the Stock / Initial-Stock reports.
      final data = await _goodsData(filtered);
      _showPdfPreview(
        (format) => ReportService().generateStockRevenuePdf(
          title: '$statusTitle PACKAGES INVENTORY AUDIT$warehouseTitle',
          periodLabel: dateRangeStr,
          headline: '${data.$2.length} goods',
          columns: data.$1,
          rows: data.$2,
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

  /// Prompt for an SR number (with autocomplete over existing SRs), fetch that
  /// single package, and preview a full-details PDF.
  Future<void> _generatePackageHistoryPdf() async {
    // Load all package SRs up front so the field can autocomplete/auto-fill.
    List<PackageModel> all;
    try {
      all = await ref.read(packageServiceProvider).getAllPackages(yard: _yardArg);
    } catch (e) {
      _showError(e.toString());
      return;
    }
    final srList = all.map((p) => p.srNumber).toList()..sort();

    final sr = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String current = '';
        return AlertDialog(
          backgroundColor: context.colors.cardDark,
          title: Text('Package History',
              style: TextStyle(color: context.colors.textPrimary)),
          content: SizedBox(
            width: 380,
            child: Autocomplete<String>(
              optionsBuilder: (v) {
                final q = v.text.trim().toLowerCase();
                if (q.isEmpty) return const Iterable<String>.empty();
                return srList
                    .where((s) => s.toLowerCase().contains(q))
                    .take(8);
              },
              onSelected: (s) => current = s,
              fieldViewBuilder: (context, ctrl, focus, onSubmit) {
                ctrl.addListener(() => current = ctrl.text.trim());
                return TextField(
                  controller: ctrl,
                  focusNode: focus,
                  autofocus: true,
                  style: TextStyle(color: context.colors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'SR Number',
                    hintText: 'e.g. GL1/SR/13/2026',
                    prefixIcon: Icon(Icons.tag_rounded),
                  ),
                  onSubmitted: (_) => Navigator.pop(ctx, current.trim()),
                );
              },
              optionsViewBuilder: (context, onSelected, options) => Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(8),
                  color: context.colors.cardDark,
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxHeight: 240, maxWidth: 380),
                    child: ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      children: options
                          .map((o) => InkWell(
                                onTap: () => onSelected(o),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  child: Text(o,
                                      style: TextStyle(
                                          color: context.colors.textPrimary)),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, current.trim()),
              child: const Text('Generate'),
            ),
          ],
        );
      },
    );
    if (sr == null || sr.isEmpty) return;

    const key = 'Package History_pdf';
    _setLoading(key, true);
    try {
      final pkg = all
          .where((p) => p.srNumber.toLowerCase() == sr.toLowerCase())
          .firstOrNull;
      if (pkg == null) {
        _showError('No package found for SR "$sr".');
        return;
      }

      final disposal = ref.read(disposalServiceProvider);
      final rates = await ref.read(storageRateProvider.future);

      final soldByItem = <String, ({DateTime? at, String? receipt})>{};
      try {
        for (final s in await disposal.getTenderSales()) {
          for (final it in s.dedupedItems) {
            final iid = it.forfeited?.itemId;
            if (it.sold && iid != null) {
              soldByItem[iid] = (at: it.soldAt, receipt: it.receiptNumber);
            }
          }
        }
      } catch (_) {}

      final destroyedByItem = <String, DateTime?>{};
      try {
        for (final dn in await disposal.getDestructions()) {
          for (final it in dn.items) {
            final iid = it.forfeited?.itemId;
            if (it.destroyed && iid != null) destroyedByItem[iid] = it.destroyedAt;
          }
        }
      } catch (_) {}

      _showPdfPreview(
        (format) => ReportService().generateSinglePackagePdf(pkg,
            format: format.copyWith(
                marginLeft: 20, marginRight: 20, marginTop: 20, marginBottom: 20),
            soldByItem: soldByItem,
            destroyedByItem: destroyedByItem,
            rates: rates),
        'Package_${pkg.srNumber.replaceAll('/', '-')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(key, false);
    }
  }

  Future<void> _exportPackageHistoryExcel() async {
    List<PackageModel> all;
    try {
      all = await ref.read(packageServiceProvider).getAllPackages(yard: _yardArg);
    } catch (e) {
      _showError(e.toString());
      return;
    }
    final srList = all.map((p) => p.srNumber).toList()..sort();

    final sr = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String current = '';
        return AlertDialog(
          backgroundColor: context.colors.cardDark,
          title: Text('Package History (Excel)',
              style: TextStyle(color: context.colors.textPrimary)),
          content: SizedBox(
            width: 380,
            child: Autocomplete<String>(
              optionsBuilder: (v) {
                final q = v.text.trim().toLowerCase();
                if (q.isEmpty) return const Iterable<String>.empty();
                return srList.where((s) => s.toLowerCase().contains(q)).take(8);
              },
              onSelected: (s) => current = s,
              fieldViewBuilder: (context, ctrl, focus, onSubmit) {
                ctrl.addListener(() => current = ctrl.text.trim());
                return TextField(
                  controller: ctrl,
                  focusNode: focus,
                  autofocus: true,
                  style: TextStyle(color: context.colors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'SR Number',
                    hintText: 'e.g. GL1/SR/13/2026',
                    prefixIcon: Icon(Icons.tag_rounded),
                  ),
                  onSubmitted: (_) => Navigator.pop(ctx, current.trim()),
                );
              },
              optionsViewBuilder: (context, onSelected, options) => Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(8),
                  color: context.colors.cardDark,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240, maxWidth: 380),
                    child: ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      children: options
                          .map((o) => InkWell(
                                onTap: () => onSelected(o),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  child: Text(o,
                                      style: TextStyle(
                                          color: context.colors.textPrimary)),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, current.trim()),
              child: const Text('Export'),
            ),
          ],
        );
      },
    );
    if (sr == null || sr.isEmpty) return;

    const key = 'Package History_excel';
    _setLoading(key, true);
    try {
      final pkg = all
          .where((p) => p.srNumber.toLowerCase() == sr.toLowerCase())
          .firstOrNull;
      if (pkg == null) {
        _showError('No package found for SR "$sr".');
        return;
      }

      final columns = [
        'SR Number', 'Item Name', 'HS Code', 'Quantity', 'Consignee',
        'Status', 'Entry Date', 'Reason'
      ];
      final rows = pkg.items.map((i) => [
        pkg.srNumber,
        i.itemName,
        i.hsCode ?? '—',
        '${i.quantity}',
        pkg.consigneeName,
        pkg.status.toUpperCase(),
        pkg.entryDate != null ? DateFormat('yyyy-MM-dd').format(pkg.entryDate!) : '—',
        i.reasons ?? pkg.reason ?? '—',
      ]).toList();

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => ExcelExportDialog(
            title: 'Export History for ${pkg.srNumber}',
            recordCount: rows.length,
            fileName: 'Package_${pkg.srNumber.replaceAll('/', '-')}_History.xlsx',
            onExport: () => ReportService().exportTableToExcel(
              title: 'PACKAGE HISTORY - ${pkg.srNumber}',
              subTitle: 'Consignee: ${pkg.consigneeName}',
              columns: columns,
              rows: rows,
            ),
            onSave: (bytes) => _handleFileSave(bytes, 'Package_${pkg.srNumber.replaceAll('/', '-')}_History', 'xlsx'),
          ),
        );
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(key, false);
    }
  }

  /// Normalise a raw item/package status to the four real dispositions the
  /// system offers. The internal 'held'/'pending'/'detained' all mean "Detain".
  String _normStatus(String s) {
    final t = s.trim().toLowerCase();
    if (t == 'held' || t == 'pending' || t == 'detained' || t == 'detain') {
      return 'Detain';
    }
    if (t == 'forfeit' || t == 'forfeited' || t == 'forfiet') return 'Forfeit';
    if (t == 'abandoned') return 'Abandoned';
    if (t.isEmpty) return 'Detain';
    return '${t[0].toUpperCase()}${t.substring(1)}';
  }

  /// Item-level "goods" rows with the full column set shared by the Inventory
  /// Audit, Initial Stock and Goods reports. Resolves each item's ACTUAL
  /// outcome (Released / Sold / Destroyed, else its disposition) with the
  /// matching date, plus reason, receipt and value.
  Future<(List<String>, List<List<String>>)> _goodsData(
      List<PackageModel> packages) async {
    final df = DateFormat('yyyy-MM-dd');
    final money = NumberFormat('#,##0');
    final disposal = ref.read(disposalServiceProvider);

    // Sold / destroyed lookups keyed by the PACKAGE ITEM id (resolved via each
    // outcome item's forfeited package, which carries its item_id).
    final soldByItem = <String, ({DateTime? at, String? receipt})>{};
    try {
      for (final s in await disposal.getTenderSales()) {
        for (final it in s.dedupedItems) {
          final iid = it.forfeited?.itemId;
          if (it.sold && iid != null) {
            soldByItem[iid] = (at: it.soldAt, receipt: it.receiptNumber);
          }
        }
      }
    } catch (_) {}
    final destroyedByItem = <String, DateTime?>{};
    try {
      for (final dn in await disposal.getDestructions()) {
        for (final it in dn.items) {
          final iid = it.forfeited?.itemId;
          if (it.destroyed && iid != null) destroyedByItem[iid] = it.destroyedAt;
        }
      }
    } catch (_) {}

    String receiptFromNotes(String? notes) {
      if (notes == null || notes.trim().isEmpty) return '';
      for (final part in notes.split('|')) {
        final t = part.trim();
        if (t.toLowerCase().startsWith('receipt no:')) {
          final i = t.indexOf(':');
          if (i != -1) return t.substring(i + 1).trim();
        }
      }
      return '';
    }

    final columns = [
      'SR Number', 'Item', 'HS Code', 'Qty', 'Consignee', 'Reason',
      'Status', 'Outcome Date', 'Receipt No', 'Value (LKR)', 'Entry Date'
    ];
    final rows = <List<String>>[];
    for (final p in packages) {
      final entry = p.entryDate != null ? df.format(p.entryDate!) : '—';
      final items = p.items.isEmpty ? <PackageItem?>[null] : p.items;
      for (final it in items) {
        // Determine outcome for this specific item.
        String status;
        String outDate = '—';
        String receipt = '—';
        final iid = it?.id;
        // Released? — a returned warehouse entry for this item.
        final released = p.warehouseEntries.where((e) =>
            e.isReturned &&
            (it == null || e.packageItemId == it.id));
        if (iid != null && soldByItem.containsKey(iid)) {
          status = 'Sold';
          final s = soldByItem[iid]!;
          outDate = s.at != null ? df.format(s.at!) : '—';
          receipt = (s.receipt?.isNotEmpty == true) ? s.receipt! : '—';
        } else if (iid != null && destroyedByItem.containsKey(iid)) {
          status = 'Destroyed';
          final dt = destroyedByItem[iid];
          outDate = dt != null ? df.format(dt) : '—';
        } else if (released.isNotEmpty) {
          status = 'Released';
          final e = released.first;
          outDate = e.returnedAt != null ? df.format(e.returnedAt!) : '—';
          final r = receiptFromNotes(e.returnNotes);
          if (r.isNotEmpty) receipt = r;
        } else {
          status = _normStatus(
              (it?.status.isNotEmpty == true ? it!.status : p.status));
        }
        rows.add([
          p.srNumber,
          it?.itemName ?? '—',
          (it?.hsCode?.trim().isNotEmpty == true) ? it!.hsCode!.trim() : '—',
          '${it?.quantity ?? '—'}',
          p.consigneeName,
          (it?.reasons?.trim().isNotEmpty == true) ? it!.reasons!.trim() : '—',
          status,
          outDate,
          receipt,
          money.format(it?.unitValue ?? p.declaredValue),
          entry,
        ]);
      }
    }
    return (columns, rows);
  }

  /// Stock & revenue metric reports. [metric] ∈ initial, total, added, sold,
  /// destroyed, revenue. Period = the Date-Range filter above (day/week/month/
  /// year, whatever the user picked). "Goods" = packages.
  Future<void> _stockRevenueReport(String metric, [String format = 'pdf']) async {
    final key = '${metric}_$format';
    _setLoading(key, true);
    final money = NumberFormat('#,##0.##');
    final df = DateFormat('yyyy-MM-dd');
    final start = _startDate;
    final end = _endDate;
    bool inPeriod(DateTime? d) {
      if (d == null) return false;
      if (start != null && d.isBefore(start)) return false;
      if (end != null && d.isAfter(end.add(const Duration(days: 1)))) {
        return false;
      }
      return true;
    }

    final periodLabel = (start != null && end != null)
        ? '${df.format(start)} to ${df.format(end)}'
        : 'All time';
    try {
      final svc = ref.read(packageServiceProvider);
      final disposal = ref.read(disposalServiceProvider);
      final packages = await svc.getAllPackages(yard: _yardArg);

      String title;
      String headline;
      List<String> columns;
      List<List<String>> rows;

      switch (metric) {
        case 'initial':
        case 'total':
        case 'added':
          // A single SR can hold MANY goods (items) — each item on its own row
          // with the SAME full column set as the Packages Inventory Audit.
          final cut = start;
          final list = packages.where((p) {
            if (metric == 'total') return true;
            if (metric == 'added') return inPeriod(p.entryDate);
            // initial: registered on/before the period start.
            return cut == null ||
                (p.entryDate != null && !p.entryDate!.isAfter(cut));
          }).toList();
          final data = await _goodsData(list);
          columns = data.$1;
          rows = data.$2;
          title = metric == 'total'
              ? 'GOODS IN SR REGISTER'
              : metric == 'added'
                  ? 'GOODS ADDED'
                  : 'INITIAL STOCK';
          headline = '${rows.length} goods';
          break;

        case 'sold':
        case 'revenue':
          final sales = await disposal.getTenderSales();
          final soldItems = [
            for (final s in sales)
              for (final it in s.dedupedItems)
                if (it.sold &&
                    inPeriod(it.soldAt) &&
                    (_yardArg == null || it.yard == _yardArg))
                  it
          ];
          double totalRev = 0;

          rows = [];
          for (final it in soldItems) {
            double tax = 0;
            for (final t in it.appliedTaxes) {
              tax += (t is Map ? (t['amount'] as num?)?.toDouble() : 0) ?? 0;
            }
            totalRev += it.soldPrice + tax;
            final f = it.forfeited;
            final pkgItems = f?.packageDetails?.items ?? const <PackageItem>[];
            if (f?.itemId != null) {
              final match = pkgItems.where((i) => i.id == f!.itemId).firstOrNull;
              final name = f?.itemName ?? match?.itemName ?? '—';
              final hs = match?.hsCode ?? '—';
              rows.add([
                f?.srNumber ?? '—',
                name,
                (hs.trim().isNotEmpty) ? hs.trim() : '—',
                it.soldAt != null ? df.format(it.soldAt!) : '—',
                money.format(it.soldPrice),
                money.format(tax),
                money.format(it.soldPrice + tax),
              ]);
            } else if (pkgItems.isNotEmpty) {
              for (final i in pkgItems) {
                rows.add([
                  f?.srNumber ?? '—',
                  i.itemName,
                  (i.hsCode?.trim().isNotEmpty == true) ? i.hsCode!.trim() : '—',
                  it.soldAt != null ? df.format(it.soldAt!) : '—',
                  money.format(it.soldPrice),
                  money.format(tax),
                  money.format(it.soldPrice + tax),
                ]);
              }
            } else {
              rows.add([
                f?.srNumber ?? '—',
                f?.itemName ?? '—',
                '—',
                it.soldAt != null ? df.format(it.soldAt!) : '—',
                money.format(it.soldPrice),
                money.format(tax),
                money.format(it.soldPrice + tax),
              ]);
            }
          }
          if (metric == 'sold') {
            title = 'GOODS SOLD IN TENDER';
            headline = '${rows.length} goods';
          } else {
            title = 'TENDER REVENUE & BALANCE';
            final added = packages
                .where((p) => inPeriod(p.entryDate))
                .fold<int>(0, (s, p) => s + (p.items.isEmpty ? 1 : p.items.length));
            final destructions = await disposal.getDestructions();
            final destroyed = [
              for (final dn in destructions)
                for (final it in dn.items)
                  if (it.destroyed &&
                      inPeriod(it.destroyedAt) &&
                      (_yardArg == null || it.yard == _yardArg))
                    it
            ].length;
            final balance = added - soldItems.length - destroyed;
            headline =
                'Revenue LKR ${money.format(totalRev)}   |   Balance: $balance goods\n(added $added − sold ${soldItems.length} − destroyed $destroyed)';
          }
          columns = [
            'SR Number', 'Item', 'HS Code', 'Sold Date', 'Sold Price', 'Tax', 'Total'
          ];
          break;

        case 'destroyed':
          final destructions = await disposal.getDestructions();
          final items = [
            for (final dn in destructions)
              for (final it in dn.items)
                if (it.destroyed &&
                    inPeriod(it.destroyedAt) &&
                    (_yardArg == null || it.yard == _yardArg))
                  it
          ];
          title = 'GOODS DESTROYED IN DESTRUCTION TENDER';
          columns = ['SR Number', 'Item', 'HS Code', 'Destroyed Date', 'Qty'];
          rows = [];
          for (final it in items) {
            final f = it.forfeited;
            final pkgItems = f?.packageDetails?.items ?? const <PackageItem>[];
            if (f?.itemId != null) {
              final match = pkgItems.where((i) => i.id == f!.itemId).firstOrNull;
              final name = f?.itemName ?? match?.itemName ?? '—';
              final hs = match?.hsCode ?? '—';
              final qty = match?.quantity ?? f?.entryQty ?? 1;
              rows.add([
                f?.srNumber ?? '—',
                name,
                (hs.trim().isNotEmpty) ? hs.trim() : '—',
                it.destroyedAt != null ? df.format(it.destroyedAt!) : '—',
                '$qty',
              ]);
            } else if (pkgItems.isNotEmpty) {
              for (final i in pkgItems) {
                rows.add([
                  f?.srNumber ?? '—',
                  i.itemName,
                  (i.hsCode?.trim().isNotEmpty == true) ? i.hsCode!.trim() : '—',
                  it.destroyedAt != null ? df.format(it.destroyedAt!) : '—',
                  '${i.quantity}',
                ]);
              }
            } else {
              rows.add([
                f?.srNumber ?? '—',
                f?.itemName ?? '—',
                '—',
                it.destroyedAt != null ? df.format(it.destroyedAt!) : '—',
                '${f?.entryQty ?? '—'}',
              ]);
            }
          }
          headline = '${rows.length} goods';
          break;

        case 'reconciliation':
          // Initial stock
          final initialPkgs = packages.where((p) => start == null || (p.entryDate != null && !p.entryDate!.isAfter(start))).toList();
          final initialData = await _goodsData(initialPkgs);
          final initialCnt = initialData.$2.length;
          double initialVal = 0;
          for (final r in initialData.$2) {
            final vStr = r[9].replaceAll(',', '').replaceAll('LKR', '').trim();
            initialVal += double.tryParse(vStr) ?? 0;
          }

          // Added goods
          final addedPkgs = packages.where((p) => inPeriod(p.entryDate)).toList();
          final addedData = await _goodsData(addedPkgs);
          final addedCnt = addedData.$2.length;
          double addedVal = 0;
          for (final r in addedData.$2) {
            final vStr = r[9].replaceAll(',', '').replaceAll('LKR', '').trim();
            addedVal += double.tryParse(vStr) ?? 0;
          }

          // Subtotal
          final subCnt = initialCnt + addedCnt;

          // Sold goods
          final sales = await disposal.getTenderSales();
          final soldItems = [
            for (final s in sales)
              for (final it in s.dedupedItems)
                if (it.sold && inPeriod(it.soldAt) && (_yardArg == null || it.yard == _yardArg)) it
          ];
          double soldVal = 0;
          for (final it in soldItems) {
            double tax = 0;
            for (final t in it.appliedTaxes) {
              tax += (t is Map ? (t['amount'] as num?)?.toDouble() : 0) ?? 0;
            }
            soldVal += it.soldPrice + tax;
          }
          final soldCnt = soldItems.length;

          // Destroyed goods
          final destructions = await disposal.getDestructions();
          final destroyedItems = [
            for (final dn in destructions)
              for (final it in dn.items)
                if (it.destroyed && inPeriod(it.destroyedAt) && (_yardArg == null || it.yard == _yardArg)) it
          ];
          final destCnt = destroyedItems.length;

          final balCnt = subCnt - soldCnt - destCnt;

          title = 'EXECUTIVE STOCK & REVENUE RECONCILIATION';
          headline =
              'Initial: $initialCnt (LKR ${money.format(initialVal)}) + Added: $addedCnt (LKR ${money.format(addedVal)}) = Subtotal: $subCnt\n'
              '− Sold: $soldCnt (Value of Goods Sold: LKR ${money.format(soldVal)}) − Destroyed: $destCnt = Net Balance: $balCnt goods';

          columns = [
            'SR Number', 'Item', 'HS Code', 'Qty', 'Consignee', 'Status / Movement', 'Date', 'Value (LKR)'
          ];
          rows = [];
          for (final r in addedData.$2) {
            rows.add([r[0], r[1], r[2], r[3], r[4], 'ADDED', r[10], r[9]]);
          }
          for (final it in soldItems) {
            final f = it.forfeited;
            rows.add([
              f?.srNumber ?? '—',
              f?.itemName ?? '—',
              '—',
              '1',
              f?.consigneeName ?? '—',
              'SOLD',
              it.soldAt != null ? df.format(it.soldAt!) : '—',
              money.format(it.soldPrice),
            ]);
          }
          for (final it in destroyedItems) {
            final f = it.forfeited;
            rows.add([
              f?.srNumber ?? '—',
              f?.itemName ?? '—',
              '—',
              '1',
              f?.consigneeName ?? '—',
              'DESTROYED',
              it.destroyedAt != null ? df.format(it.destroyedAt!) : '—',
              '—',
            ]);
          }
          break;

        default:
          return;
      }

      if (rows.isEmpty) {
        _showNoDataMessage();
        return;
      }

      if (format == 'view') {
        _showReportTable(
          title: title,
          subtitle: periodLabel,
          columns: columns,
          rows: rows,
          onSavePdf: () => _stockRevenueReport(metric, 'pdf'),
          onExportExcel: () => _stockRevenueReport(metric, 'excel'),
        );
      } else if (format == 'pdf') {
        _showPdfPreview(
          (format) => ReportService().generateStockRevenuePdf(
            title: title,
            periodLabel: periodLabel,
            headline: headline,
            columns: columns,
            rows: rows,
            format: format.copyWith(
                marginLeft: 20, marginRight: 20, marginTop: 20, marginBottom: 20),
          ),
          '${title.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
        );
      } else {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => ExcelExportDialog(
              title: 'Export $title',
              recordCount: rows.length,
              fileName: '${title.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx',
              onExport: () => ReportService().exportTableToExcel(
                title: title,
                subTitle: periodLabel,
                columns: columns,
                rows: rows,
              ),
              onSave: (bytes) => _handleFileSave(bytes, title.replaceAll(' ', '_'), 'xlsx'),
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

  List<ForfeitedPackageModel> _filterByWarehouseForfeited(List<ForfeitedPackageModel> list) {
    if (_selectedWarehouse == 'all') return list;
    return list.where((f) {
      final entries = f.packageDetails?.warehouseEntries ?? const [];
      if (entries.isEmpty) return false;
      return entries.any((e) => e.warehouseId == _selectedWarehouse || e.warehouseCode == _selectedWarehouse);
    }).toList();
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

  /// Packages marked Re-exported in this yard.
  Future<void> _generateReexportedReport(String format) async {
    await _emitForfeitedReport(
      key: 'Re-exported Packages',
      title: 'RE-EXPORTED PACKAGES',
      fileBase: 'Reexported_Packages',
      dateHeader: 'Re-exported On',
      format: format,
      fetch: () async {
        final fSvc = ref.read(forfeitedPackageServiceProvider);
        final list = await fSvc.getForfeitedBySource('re-export');
        if (list.isNotEmpty) return list;
        final allF = await fSvc.getForfeitedPackages();
        return allF.where((f) {
          final s = f.source.toLowerCase();
          if (s == 're-export' || s == 'reexport') return true;
          final entries = f.packageDetails?.warehouseEntries ?? const [];
          return entries.any((e) {
            final n = (e.returnNotes ?? '').toUpperCase();
            return n.contains('RE-EXPORT');
          });
        }).toList();
      },
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
      final raw = await fetch();
      final yardFiltered = _filterByYard(raw, (f) => f.yard);
      final dateFiltered = _filterByDate(yardFiltered);
      final list = _filterByWarehouseForfeited(dateFiltered);
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



  /// Opens the QR-label generator: pick one/several packages, then print or
  /// download their QR-code labels (regenerated live from the package data, so
  /// any previously registered package's labels can be produced again anytime).
  Future<void> _openQrLabelGenerator() async {
    const key = 'QR Code Labels';
    _setLoading(key, true);
    List<PackageModel> all;
    try {
      all = await ref.read(packageServiceProvider).getAllPackages(yard: _yardArg);
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
    Future<void> Function()? onView,
    Future<void> Function()? onPdf,
    Future<void> Function()? onExcel,
  }) {
    final showView = widget.executiveMode && onView != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Gap(4),
          Text(
            description,
            style: TextStyle(color: context.colors.textMuted, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          Row(
            children: [
              if (showView)
                Expanded(
                  child: _buildActionButton(
                    label: 'View',
                    icon: Icons.table_rows_rounded,
                    color: color,
                    isLoading: _isLoading('${title}_view'),
                    onTap: onView,
                  ),
                ),
              if (showView && (onPdf != null || onExcel != null)) const Gap(4),
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
              if (onPdf != null && onExcel != null) const Gap(4),
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
          minimumSize: const Size(0, 32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        )
      : ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 32),
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
      // Windows' save dialog doesn't auto-append the extension, so force it.
      var path = result;
      if (!path.toLowerCase().endsWith('.${extension.toLowerCase()}')) {
        path = '$path.$extension';
      }
      final file = File(path);
      await file.writeAsBytes(bytes);
      _showSuccess('Report saved successfully to ${path.split(Platform.pathSeparator).last}');
    }
  }

  Future<void> _generateWarehouseStockPdf() async {
    const key = 'Warehouse Stock_pdf';
    _setLoading(key, true);
    try {
      final entries = await ref.read(warehouseServiceProvider).getAllWarehouseEntries(isReturned: false, yard: _yardArg);
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
      final entries = await ref.read(warehouseServiceProvider).getAllWarehouseEntries(isReturned: false, yard: _yardArg);
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
      final entries = await ref.read(warehouseServiceProvider).getAllWarehouseEntries(isReturned: true, yard: _yardArg);
      final filtered = _filterByDate(entries);
      if (filtered.isEmpty) {
        _showNoDataMessage();
        return;
      }
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
      final entries = await ref.read(warehouseServiceProvider).getAllWarehouseEntries(isReturned: true, yard: _yardArg);
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

  /// Old Entries (Migrated Packages) report — PDF or Excel.
  Future<void> _generateOldEntriesReport(String format) async {
    final key = 'Old Entries_$format';
    _setLoading(key, true);
    try {
      final svc = ref.read(packageServiceProvider);
      final packages = await svc.getAllPackages(yard: _yardArg);
      // Only packages that carry a legacy SR number.
      var oldEntries = packages
          .where((p) =>
              p.oldSrNumber != null && p.oldSrNumber!.trim().isNotEmpty)
          .toList();
      oldEntries = _filterByDate(oldEntries);
      oldEntries.sort((a, b) => (b.createdAt).compareTo(a.createdAt));

      if (oldEntries.isEmpty) {
        _showNoDataMessage();
        return;
      }

      final df = DateFormat('yyyy-MM-dd');
      final columns = [
        'Old SR Number',
        'New SR Number',
        'Cusdec No',
        'Cusdec Date',
        'Entry Date',
        'Consignee',
        'Status',
      ];
      final rows = oldEntries.map((p) => [
        p.oldSrNumber ?? '—',
        p.srNumber,
        (p.cusdecNo?.isNotEmpty == true) ? p.cusdecNo! : '—',
        (p.cusdecDate?.isNotEmpty == true) ? p.cusdecDate! : '—',
        p.entryDate != null ? df.format(p.entryDate!) : '—',
        p.consigneeName,
        _normStatus(p.status),
      ]).toList();

      final periodLabel = (_startDate != null && _endDate != null)
          ? '${df.format(_startDate!)} to ${df.format(_endDate!)}'
          : 'All time';

      if (format == 'pdf') {
        _showPdfPreview(
          (fmt) => ReportService().generateStockRevenuePdf(
            title: 'OLD ENTRIES (MIGRATED PACKAGES)',
            periodLabel: periodLabel,
            headline: '${rows.length} migrated packages',
            columns: columns,
            rows: rows,
            format: fmt,
          ),
          'Old_Entries_Report.pdf',
        );
      } else {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => ExcelExportDialog(
              title: 'Export Old Entries',
              recordCount: rows.length,
              fileName: 'Old_Entries_Report.xlsx',
              onExport: () => ReportService().exportTableToExcel(
                title: 'Old Entries (Migrated Packages)',
                subTitle: periodLabel,
                columns: columns,
                rows: rows,
              ),
              onSave: (bytes) =>
                  _handleFileSave(bytes, 'Old_Entries', 'xlsx'),
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
      final admitted = await ref.read(warehouseServiceProvider).getAllWarehouseEntries(yard: _yardArg);
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
        yard: _yardArg,
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
        // Include BOTH in-warehouse and released entries so the report shows
        // released packages too (with their release date + receipt number).
        final entries = await ref.read(warehouseServiceProvider).getAllWarehouseEntries(yard: _yardArg);
        final filteredEntries = _filterByDate(entries);
        if (filteredEntries.isEmpty) {
          _showNoDataMessage();
        } else {
          final packages = await ref.read(packageServiceProvider).getAllPackages(yard: _yardArg);
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
        final entries = await ref.read(warehouseServiceProvider).getAllWarehouseEntries(yard: _yardArg);
        final filteredEntries = _filterByDate(entries);
        if (filteredEntries.isEmpty) {
          _showNoDataMessage();
        } else {
          final packages = await ref.read(packageServiceProvider).getAllPackages(yard: _yardArg);
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
        final entries = await ref.read(warehouseServiceProvider).getAllWarehouseEntries(isReturned: true, yard: _yardArg);
        final filteredEntries = _filterByDate(entries);
        if (filteredEntries.isEmpty) {
          _showNoDataMessage();
        } else {
          final packages = await ref.read(packageServiceProvider).getAllPackages(yard: _yardArg);
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
        final entries = await ref.read(warehouseServiceProvider).getAllWarehouseEntries(isReturned: true, yard: _yardArg);
        final filteredEntries = _filterByDate(entries);
        if (filteredEntries.isEmpty) {
          _showNoDataMessage();
        } else {
          final packages = await ref.read(packageServiceProvider).getAllPackages(yard: _yardArg);
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
                                // Select All + Clear All as two distinct
                                // actions (like the disposal-request dialog).
                                TextButton.icon(
                                  onPressed: allShownSelected
                                      ? null
                                      : () => setState(() => _selected.addAll(
                                          filtered.map((p) => p.id))),
                                  icon: Icon(Icons.done_all_rounded,
                                      size: 16, color: gold),
                                  label: Text('Select All',
                                      style: TextStyle(
                                          color: gold,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700)),
                                ),
                                TextButton.icon(
                                  onPressed: _selected.isEmpty
                                      ? null
                                      : () =>
                                          setState(() => _selected.clear()),
                                  icon: Icon(Icons.remove_done_rounded,
                                      size: 16,
                                      color: context.colors.dangerRed),
                                  label: Text('Clear All',
                                      style: TextStyle(
                                          color: context.colors.dangerRed,
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
