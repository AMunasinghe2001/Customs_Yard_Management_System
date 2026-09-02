import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../executive/unsold_shared.dart' show unsoldQty;
import '../../core/yards.dart';
import '../../core/post_status_activities.dart';
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
import '../../widgets/package_details_dialog.dart';

/// The statuses a report row can actually carry, in lifecycle order: the three
/// registration dispositions (+ Other) followed by the terminal outcomes
/// resolved in `_goodsData`. These are the values shown in the reports' Status
/// column, so the Status filter offers exactly these and nothing else.
///
/// NOTE: `packages.status` (the legacy `pending`/`held`/`cleared` column) is
/// written once at registration and never updated, so it is NOT filtered on.
const List<String> kReportStatuses = [
  'Detain',
  'Forfeit',
  'Abandoned',
  'Other',
  'Released',
  'Sold',
  'Destroyed',
];

/// The valuation stages a package goes through, in order, mirroring the tender
/// names in [tenderRoundLabel]. Each column is ONE stage — nothing is
/// collapsed, so a figure always sits under the round that produced it:
///
///   * **Initial Valuation** — the Valuation Directorate's figure on the
///     disposal request, which prices the **Valuation Tender**.
///   * **Tender 1 / 2 / 3** — bid-driven re-valuations, one per unsold round.
///   * **Top Management Directorate Valuation** — the figure the ADG submitted from the tender
///     committee, pricing the final committee round. It lives on
///     `tender_committees.submitted_value`, not in the re-valuations.
const List<String> kValuationRounds = [
  'Initial Valuation',
  'Tender 1',
  'Tender 2',
  'Tender 3',
  'Top Management Directorate Valuation',
];

class ReportsScreen extends ConsumerStatefulWidget {
  /// Executive Office (DG / ADG) mode: shows a Yard selector and scopes every
  /// report to the picked yard. Officers/admins use the default (false), where
  /// RLS already limits data to their own yard.
  final bool executiveMode;

  /// Central Disposal Directorate mode: shows ONLY the Post Status Activity
  /// reports, cross-yard by default with an optional single-yard filter
  /// ("All Yards" = null). Disposal's `disposal_read_all` RLS grants SELECT on
  /// packages/package_items/warehouse_entries across every yard, which is
  /// exactly what these reports read.
  final bool disposalMode;

  const ReportsScreen({
    super.key,
    this.executiveMode = false,
    this.disposalMode = false,
  });

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  DateTime? _startDate;
  DateTime? _endDate;
  String _dateFilterType = 'range'; // 'range' | 'day' | 'month' | 'year'
  String _selectedStatus = 'all';

  /// Post Status Activity filter — 'all', or one of [kAllPostStatusActivities].
  /// Lets the SR Register Inventory be read one activity at a time.
  String _selectedActivity = 'all';
  String _selectedWarehouse = 'all';
  // Executive mode: the yard whose reports are generated (null = none picked).
  String? _reportYard;

  /// Which valuation column(s) the "List of Goods Valued" report shows:
  /// 'all' = every round side by side, else one of [kValuationRounds].
  String _valuationRound = 'all';

  /// The yard passed to the data services. Executive mode → the picked yard
  /// (report cards are only shown once one is picked, so it's non-null here);
  /// disposal mode → the picked yard, or null for "All Yards" (cross-yard);
  /// officer mode → null, so RLS scopes data to the officer's own yard.
  String? get _yardArg =>
      (widget.executiveMode || widget.disposalMode) ? _reportYard : null;

  /// Client-side yard filter for report lists whose service can't take a yard
  /// (e.g. forfeited packages). No-op in officer mode, and in disposal mode
  /// when "All Yards" is selected.
  List<T> _filterByYard<T>(List<T> rows, String? Function(T) yardOf) {
    if (!widget.executiveMode && !widget.disposalMode) return rows;
    if (_reportYard == null) return rows;
    return rows.where((r) => yardOf(r) == _reportYard).toList();
  }

  // Track loading state for each button uniquely
  final Map<String, bool> _loadingStates = {};
  final ScrollController _scrollController = ScrollController();

  bool _isLoading(String key) => _loadingStates[key] ?? false;
  void _setLoading(String key, bool val) =>
      setState(() => _loadingStates[key] = val);

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
                        Text('Report Generator',
                            style: Theme.of(context).textTheme.headlineLarge),
                        Text('Choose periodic or standard warehouse reports.',
                            style:
                                TextStyle(color: context.colors.textSecondary)),
                      ],
                    ),
                    // Icon removed to match other pages
                  ],
                ).animate().fadeIn(),
                const Gap(20),
                _buildFilterSection()
                    .animate()
                    .slideY(begin: 0.1)
                    .fadeIn(delay: 100.ms),
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
    final today = DateTime(now.year, now.month, now.day);
    if (_dateFilterType == 'day') {
      final initial = _startDate ?? today;
      final clampedInitial = initial.isAfter(today) ? today : initial;
      final picked = await showDatePicker(
        context: context,
        initialDate: clampedInitial,
        firstDate: DateTime(2020),
        lastDate: today,
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
    final currentMonth = DateTime.now().month;
    if (selectedYear > currentYear) selectedYear = currentYear;
    if (selectedYear == currentYear && selectedMonth > currentMonth) {
      selectedMonth = currentMonth;
    }
    final years = List.generate(10, (i) => currentYear - i);
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];

    return showDialog<({int year, int month})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final maxMonth = (selectedYear == currentYear) ? currentMonth : 12;
          if (selectedMonth > maxMonth) selectedMonth = maxMonth;

          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: context.colors.cardDark,
            title: Text('Select Month & Year',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 320,
              child: Row(
                children: [
                  Expanded(
                    child: StyledDropdownFormField<int>(
                      label: 'Month',
                      value: selectedMonth,
                      floatingLabelBehavior: FloatingLabelBehavior.never,
                      options: List.generate(
                        maxMonth,
                        (i) => StyledDropdownOption(i + 1, months[i]),
                      ),
                      menuWidth: 160,
                      onChanged: (v) {
                        if (v != null) setDlgState(() => selectedMonth = v);
                      },
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: StyledDropdownFormField<int>(
                      label: 'Year',
                      value: selectedYear,
                      floatingLabelBehavior: FloatingLabelBehavior.never,
                      options: years
                          .map((y) => StyledDropdownOption(y, '$y'))
                          .toList(),
                      menuWidth: 140,
                      onChanged: (v) {
                        if (v != null) {
                          setDlgState(() {
                            selectedYear = v;
                            if (selectedYear == currentYear &&
                                selectedMonth > currentMonth) {
                              selectedMonth = currentMonth;
                            }
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel',
                    style: TextStyle(color: context.colors.textMuted)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.primaryGold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.pop(
                    ctx, (year: selectedYear, month: selectedMonth)),
                child: const Text('Select',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<int?> _showYearPickerDialog(
      BuildContext context, int initialYear) async {
    int selectedYear = initialYear;
    final currentYear = DateTime.now().year;
    if (selectedYear > currentYear) selectedYear = currentYear;
    final years = List.generate(10, (i) => currentYear - i);

    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: context.colors.cardDark,
          title: Text('Select Year',
              style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 260,
            child: StyledDropdownFormField<int>(
              label: 'Year',
              value: selectedYear,
              floatingLabelBehavior: FloatingLabelBehavior.never,
              options: years.map((y) => StyledDropdownOption(y, '$y')).toList(),
              menuWidth: 200,
              onChanged: (v) {
                if (v != null) setDlgState(() => selectedYear = v);
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: TextStyle(color: context.colors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.primaryGold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(ctx, selectedYear),
              child: const Text('Select',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterSection() {
    // Warehouses are shared across yards, but each yard only uses some of
    // them — and how many differs. Once a yard is picked, narrow the list to
    // the warehouses that yard actually holds goods in.
    // In executive/disposal mode, if no yard is picked yet, show nothing —
    // the user must select a yard first so the list is meaningful.
    final yard = _yardArg;
    final List<WarehouseModel> warehouses;
    if (yard != null) {
      warehouses =
          ref.watch(warehousesForYardProvider(yard)).valueOrNull ?? const [];
    } else if (widget.executiveMode || widget.disposalMode) {
      // No yard selected yet → empty list; don't show all warehouses
      warehouses = const [];
    } else {
      // Officer mode: RLS scopes to the officer's own yard
      warehouses = ref.watch(warehousesProvider).valueOrNull ?? const [];
    }

    final hasDate = _startDate != null || _endDate != null;
    String dateLabel;
    if (!hasDate) {
      if (_dateFilterType == 'day')
        dateLabel = 'Pick Day';
      else if (_dateFilterType == 'month')
        dateLabel = 'Pick Month';
      else if (_dateFilterType == 'year')
        dateLabel = 'Pick Year';
      else
        dateLabel = 'Custom Range';
    } else {
      if (_dateFilterType == 'day') {
        dateLabel = 'Day: ${DateFormat('yyyy-MM-dd').format(_startDate!)}';
      } else if (_dateFilterType == 'month') {
        dateLabel = 'Month: ${DateFormat('MMM yyyy').format(_startDate!)}';
      } else if (_dateFilterType == 'year') {
        dateLabel = 'Year: ${_startDate!.year}';
      } else {
        dateLabel =
            '${DateFormat('MMM d').format(_startDate!)} - ${DateFormat('MMM d').format(_endDate!)}';
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
          // ── Yard (Executive Office picks one; Central Disposal defaults to
          //    every yard and can narrow to one) ──
          if (widget.executiveMode || widget.disposalMode)
            StyledDropdownButton<String>(
              value: _reportYard,
              allLabel: widget.disposalMode ? 'All Yards' : 'Select Yard',
              icon: Icons.location_city_rounded,
              menuWidth: 260,
              // A physical-yard picker -- reports are scoped by yard (server
              // query / RLS), not split by directorate, since a report at a
              // multi-directorate yard naturally covers all of that yard's
              // goods regardless of which directorate filed them.
              options: (ref.watch(yardsProvider).valueOrNull
                          ?.where((y) => y.isActive)
                          .toList() ??
                      kYards.map((y) => YardModel(code: y.code, name: y.name, srPrefix: y.srPrefix)).toList())
                  .map((y) => StyledDropdownOption(y.code, y.name))
                  .toList(),
              onChanged: (v) => setState(() {
                _reportYard = v;
                // Warehouses differ from yard to yard, so a selection made
                // under the previous yard may not exist under this one.
                _selectedWarehouse = 'all';
              }),
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
          // The real statuses the system produces: the three registration
          // dispositions plus the terminal outcomes resolved in [_goodsData].
          StyledDropdownButton<String>(
            value: _selectedStatus == 'all' ? null : _selectedStatus,
            allLabel: 'All Statuses',
            icon: Icons.flag_rounded,
            menuWidth: 220,
            options: kReportStatuses
                .map((s) => StyledDropdownOption(s, s.toUpperCase()))
                .toList(),
            onChanged: (v) => setState(() => _selectedStatus = v ?? 'all'),
          ),

          // ── Post Status Activity ──
          // Narrows the SR Register Inventory to one activity, so the stock
          // can be read "everything Pending Licence", "everything Supposed to
          // be Destroyed", and so on.
          StyledDropdownButton<String>(
            value: _selectedActivity == 'all' ? null : _selectedActivity,
            allLabel: 'Post Status Activity',
            icon: Icons.label_outline_rounded,
            menuWidth: 320,
            options: kAllPostStatusActivities
                .map((a) => StyledDropdownOption(a, a))
                .toList(),
            onChanged: (v) => setState(() => _selectedActivity = v ?? 'all'),
          ),

          // ── Valuation Round ──
          // Drives the "List of Goods Valued" report: every round side by
          // side, or one round on its own.
          StyledDropdownButton<String>(
            value: _valuationRound == 'all' ? null : _valuationRound,
            allLabel: 'All Valuations',
            icon: Icons.stacked_line_chart_rounded,
            menuWidth: 240,
            options: kValuationRounds
                .map((r) => StyledDropdownOption(r, r))
                .toList(),
            onChanged: (v) => setState(() => _valuationRound = v ?? 'all'),
          ),

          // ── Warehouse ──
          // Shown on every portal. Central Disposal reads `warehouses` through
          // the policy added in 20260838_disposal_read_warehouses.sql; before
          // that their list came back empty and the filter had to be hidden.
          StyledDropdownButton<String>(
            // A warehouse chosen before the yard narrowed the list may no
            // longer be in it; fall back to "All" rather than showing a
            // value the menu cannot offer.
            value: warehouses.any((w) => w.id == _selectedWarehouse)
                ? _selectedWarehouse
                : null,
            allLabel: 'All Warehouses',
            icon: Icons.warehouse_rounded,
            menuWidth: 320,
            options: warehouses
                .map((w) => StyledDropdownOption(w.id, '${w.code} - ${w.name}'))
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
              style: TextStyle(color: context.colors.textMuted, fontSize: 13)),
        ],
      ),
    );
  }

  // ── In-app report viewer ─────────────────────────────────────────────────
  // The primary way to consume a report is to view its rows right here in the
  // app (pretty table); PDF / Excel are secondary exports inside the viewer.

  static const List<String> _packageCols = [
    'SR Number',
    'Goods Name',
    'HS Code',
    'Qty',
    'Consignee',
    'Status',
    'Entry Date',
    'Value (LKR)'
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

  Future<void> _openDetailsForSr(String query,
      {String? itemId, String? itemName}) async {
    final storageRate =
        ref.read(storageRateProvider).valueOrNull ?? const <DateTime, double>{};
    try {
      final svc = ref.read(packageServiceProvider);
      final packages = await svc.getAllPackages(yard: _yardArg);
      final q = query.trim().toLowerCase();
      final pkg = packages
          .where((p) =>
              p.srNumber.toLowerCase() == q ||
              (p.oldSrNumber ?? '').toLowerCase() == q ||
              p.id == query)
          .firstOrNull;

      if (pkg != null && mounted) {
        String? resolvedItemId = itemId;
        if (resolvedItemId == null &&
            itemName != null &&
            itemName.isNotEmpty &&
            itemName != '—') {
          // Attempt to resolve item by item name if itemId is null
          final cleanName = itemName.split('+')[0].trim().toLowerCase();
          final match = pkg.items
              .where((i) => i.itemName.trim().toLowerCase() == cleanName)
              .firstOrNull;
          if (match != null) {
            resolvedItemId = match.id;
          }
        }

        showDialog(
          context: context,
          builder: (_) => PackageDetailsDialog(
            package: pkg,
            storageRate: storageRate,
            useLegacySummary: true,
            highlightItemId: resolvedItemId,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No package details found for "$query"'),
            backgroundColor: context.colors.primaryGold,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  /// The shared in-app table dialog. Print / Export Excel sit in the footer.
  /// [rowItemIds] is an optional list (same length as [rows]) where each entry
  /// is the package-item ID for that row; when non-null the Details button will
  /// open the popup filtered to that specific item.
  Future<void> _showReportTable({
    required String title,
    String? subtitle,
    required List<String> columns,
    required List<List<String>> rows,
    VoidCallback? onSavePdf,
    VoidCallback? onExportExcel,
    bool showDetailsButton = true,
    List<String?>? rowItemIds,
  }) async {
    if (rows.isEmpty) {
      _showNoDataMessage();
      return;
    }

    final hasSrCol = columns.isNotEmpty &&
        (columns.first.toLowerCase().contains('sr') ||
            columns.first.toLowerCase().contains('package'));
    final shouldAddDetails =
        showDetailsButton && hasSrCol && !columns.contains('Details');

    final effectiveCols = shouldAddDetails ? [...columns, 'Details'] : columns;

    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(28),
        backgroundColor: context.colors.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: 1180, maxHeight: MediaQuery.of(ctx).size.height * 0.86),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
                child: Row(children: [
                  // The Customs emblem, so the on-screen report is headed the
                  // same way the printed one is.
                  SvgPicture.asset('Sri_Lanka_Customs_logo_tinted.svg',
                      width: 30,
                      height: 30,
                      theme:
                          SvgTheme(currentColor: context.colors.primaryGold)),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: TextStyle(
                                color: context.colors.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w800)),
                        Text(
                            '${rows.length} record(s)${subtitle != null ? ' · $subtitle' : ''}',
                            style: TextStyle(
                                color: context.colors.textMuted, fontSize: 12)),
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
                    columns: effectiveCols
                        .map((c) => DataColumn2(
                            label: Center(
                              child: Text(c,
                                  style: TextStyle(
                                      color: context.colors.primaryGold,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12)),
                            ),
                            size: c == 'Details' ? ColumnSize.S : ColumnSize.M,
                            fixedWidth: c == 'Details' ? 70 : null))
                        .toList(),
                    rows: rows.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final r = entry.value;
                      final cells = r
                          .map((c) => DataCell(TooltipText(c,
                              style: TextStyle(
                                  color: context.colors.textPrimary,
                                  fontSize: 12.5))))
                          .toList();

                      if (shouldAddDetails) {
                        final sr = r[0];
                        final itemName = r.length > 1 ? r[1] : null;
                        final itemId =
                            (rowItemIds != null && idx < rowItemIds.length)
                                ? rowItemIds[idx]
                                : null;
                        cells.add(
                          DataCell(
                            Center(
                              child: IconButton(
                                icon: Icon(Icons.info_outline_rounded,
                                    color: context.colors.accentLightBlue,
                                    size: 18),
                                tooltip: 'View Package Details',
                                onPressed: () => _openDetailsForSr(sr,
                                    itemId: itemId, itemName: itemName),
                              ),
                            ),
                          ),
                        );
                      }
                      return DataRow(cells: cells);
                    }).toList(),
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
                      onPressed: () {
                        Navigator.pop(ctx);
                        onExportExcel();
                      },
                    ),
                  if (onExportExcel != null) const Gap(10),
                  if (onSavePdf != null)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: context.colors.customsBlue,
                          foregroundColor: Colors.white),
                      icon: const Icon(Icons.print_rounded, size: 16),
                      label: const Text('Print'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        onSavePdf();
                      },
                    ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _viewCategoryZone() async {
    const key = 'Category & Zone Summary_view';
    _setLoading(key, true);
    try {
      final packages =
          await ref.read(packageServiceProvider).getAllPackages(yard: _yardArg);
      final entries = await ref
          .read(warehouseServiceProvider)
          .getAllWarehouseEntries(yard: _yardArg);
      final withDatePkgs = _filterByDate(packages);
      final withDateEntries = _filterByDate(entries);
      if (withDatePkgs.isEmpty && withDateEntries.isEmpty) {
        _showNoDataMessage();
        return;
      }
      final columns = [
        'Category / Zone',
        'Package Count',
        'Item Count',
        'Total Declared Value (LKR)'
      ];
      final categoryMap = <String, ({int pkgs, int items, double val})>{};
      for (final p in withDatePkgs) {
        final cat = (p.items.isNotEmpty &&
                p.items.first.category != null &&
                p.items.first.category!.isNotEmpty)
            ? p.items.first.category!
            : 'Uncategorized';
        final cur = categoryMap[cat] ?? (pkgs: 0, items: 0, val: 0.0);
        categoryMap[cat] = (
          pkgs: cur.pkgs + 1,
          items: cur.items + (p.items.isNotEmpty ? p.items.length : 1),
          val: cur.val + p.declaredValue,
        );
      }
      final money = NumberFormat('#,##0');
      final rows = categoryMap.entries
          .map((e) => [
                e.key,
                '${e.value.pkgs}',
                '${e.value.items}',
                money.format(e.value.val),
              ])
          .toList();

      _showReportTable(
        title: 'Category & Zone Summary',
        columns: columns,
        rows: rows,
        onSavePdf: _generateCategoryZonePdf,
        onExportExcel: _exportCategoryZoneExcel,
        showDetailsButton: false,
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(key, false);
    }
  }

  Future<void> _viewWarehouseStock() async {
    const key = 'Warehouse Stock_view';
    _setLoading(key, true);
    try {
      final entries = await ref
          .read(warehouseServiceProvider)
          .getAllWarehouseEntries(isReturned: false, yard: _yardArg);
      final filtered = _filterByDate(entries);
      if (filtered.isEmpty) {
        _showNoDataMessage();
        return;
      }
      final df = DateFormat('yyyy-MM-dd');
      final columns = [
        'SR Number',
        'Goods Name',
        'Consignee',
        'Warehouse',
        'Reason',
        'Admitted Date'
      ];
      final rows = filtered
          .map((e) => [
                e.srNumber ?? '—',
                e.itemName ?? '—',
                e.consigneeName ?? '—',
                e.warehouseCode,
                e.holdReason,
                df.format(e.admittedAt),
              ])
          .toList();
      final itemIds = filtered.map((e) => e.packageItemId).toList();
      _showReportTable(
        title: 'Warehouse Stock',
        columns: columns,
        rows: rows,
        rowItemIds: itemIds,
        onSavePdf: _generateWarehouseStockPdf,
        onExportExcel: _exportWarehouseStockExcel,
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(key, false);
    }
  }

  Future<void> _viewReturnedPackages() async {
    const key = 'Released Packages_view';
    _setLoading(key, true);
    try {
      final entries = await ref
          .read(warehouseServiceProvider)
          .getAllWarehouseEntries(isReturned: true, yard: _yardArg);
      final filtered = _filterByDate(entries);
      if (filtered.isEmpty) {
        _showNoDataMessage();
        return;
      }
      final df = DateFormat('yyyy-MM-dd');
      final columns = [
        'SR Number',
        'Goods Name',
        'Consignee',
        'Warehouse',
        'Returned Date',
        'Return Notes'
      ];
      final rows = filtered
          .map((e) => [
                e.srNumber ?? '—',
                e.itemName ?? '—',
                e.consigneeName ?? '—',
                e.warehouseCode,
                e.returnedAt != null ? df.format(e.returnedAt!) : '—',
                e.returnNotes ?? '—',
              ])
          .toList();
      final itemIds = filtered.map((e) => e.packageItemId).toList();
      _showReportTable(
        title: 'Released Goods Report',
        columns: columns,
        rows: rows,
        rowItemIds: itemIds,
        onSavePdf: _generateReturnedPdf,
        onExportExcel: _exportReturnedExcel,
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(key, false);
    }
  }

  Future<void> _viewWarehousesList() async {
    const key = 'Warehouses List_view';
    _setLoading(key, true);
    try {
      final warehouses = ref.read(warehousesProvider).asData?.value ?? const [];
      if (warehouses.isEmpty) {
        _showNoDataMessage();
        return;
      }
      final columns = ['Warehouse Code', 'Warehouse Name', 'Capacity'];
      final rows = warehouses
          .map((w) => [
                w.code,
                w.name,
                '${w.capacity}',
              ])
          .toList();
      _showReportTable(
        title: 'Warehouses List',
        columns: columns,
        rows: rows,
        onSavePdf: _generateWarehousesListPdf,
        onExportExcel: _exportWarehousesListExcel,
        showDetailsButton: false,
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(key, false);
    }
  }

  Future<void> _viewStorageCharges() async {
    const key = 'Storage Charges_view';
    _setLoading(key, true);
    try {
      final entries = await ref
          .read(warehouseServiceProvider)
          .getAllWarehouseEntries(yard: _yardArg);
      final filteredEntries = _filterByDate(entries);
      if (filteredEntries.isEmpty) {
        _showNoDataMessage();
        return;
      }
      final df = DateFormat('yyyy-MM-dd');
      final columns = [
        'SR Number',
        'Goods Name',
        'Consignee',
        'Warehouse',
        'Admitted Date',
        'Status'
      ];
      final rows = filteredEntries
          .map((e) => [
                e.srNumber ?? '—',
                e.itemName ?? '—',
                e.consigneeName ?? '—',
                e.warehouseCode,
                df.format(e.admittedAt),
                e.isReturned ? 'Released' : 'Held',
              ])
          .toList();
      final itemIds = filteredEntries.map((e) => e.packageItemId).toList();
      _showReportTable(
        title: 'Storage Charges Report',
        columns: columns,
        rows: rows,
        rowItemIds: itemIds,
        onSavePdf: _generateStorageChargesPdf,
        onExportExcel: _exportStorageChargesExcel,
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(key, false);
    }
  }

  Future<void> _viewReleasedRevenue() async {
    const key = 'Released Revenue_view';
    _setLoading(key, true);
    try {
      final entries = await ref
          .read(warehouseServiceProvider)
          .getAllWarehouseEntries(isReturned: true, yard: _yardArg);
      final filtered = _filterByDate(entries);
      if (filtered.isEmpty) {
        _showNoDataMessage();
        return;
      }
      final df = DateFormat('yyyy-MM-dd');
      final columns = [
        'SR Number',
        'Goods Name',
        'Consignee',
        'Warehouse',
        'Admitted Date',
        'Released Date'
      ];
      final rows = filtered
          .map((e) => [
                e.srNumber ?? '—',
                e.itemName ?? '—',
                e.consigneeName ?? '—',
                e.warehouseCode,
                df.format(e.admittedAt),
                e.returnedAt != null ? df.format(e.returnedAt!) : '—',
              ])
          .toList();
      final itemIds = filtered.map((e) => e.packageItemId).toList();
      _showReportTable(
        title: 'Released Revenue Report',
        columns: columns,
        rows: rows,
        rowItemIds: itemIds,
        onSavePdf: _generateReleasedRevenuePdf,
        onExportExcel: _exportReleasedRevenueExcel,
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(key, false);
    }
  }

  /// The configured post status activities as report rows: the activity and
  /// the item statuses it is offered for.
  List<List<String>> _postStatusActivityRows() =>
      kAllPostStatusActivities.map((a) {
        final statuses = <String>[
          if (kDetainActivities.contains(a)) 'Detain',
          if (kDisposalActivities.contains(a)) 'Forfeit / Abandoned / Other',
        ];
        return [a, statuses.join(', ')];
      }).toList();

  Future<void> _viewPostStatusActivities() async {
    const key = 'Post Status Activity_view';
    _setLoading(key, true);
    try {
      final rows = _postStatusActivityRows();
      if (rows.isEmpty) {
        _showNoDataMessage();
        return;
      }
      _showReportTable(
        title: 'Post Status Activity List',
        columns: ['Activity', 'Applies To Status'],
        rows: rows,
        onSavePdf: _generatePostStatusActivitiesPdf,
        onExportExcel: _exportPostStatusActivitiesExcel,
        showDetailsButton: false,
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(key, false);
    }
  }

  Future<void> _viewCategories() async {
    const key = 'Item Categories_view';
    _setLoading(key, true);
    try {
      final categories =
          await ref.read(packageCategoryServiceProvider).getCategories();
      if (categories.isEmpty) {
        _showNoDataMessage();
        return;
      }
      final rows =
          categories.map((c) => [c.name, c.description ?? '—']).toList();
      _showReportTable(
        title: 'Item Categories List',
        columns: ['Category Name', 'Description'],
        rows: rows,
        onSavePdf: _generateCategoriesPdf,
        onExportExcel: _exportCategoriesExcel,
        showDetailsButton: false,
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(key, false);
    }
  }

  /// View a package-list report in-app (with PDF / Excel export).
  Future<void> _viewPackages(String status, String title,
      {String? subtitle}) async {
    final key = '${title}_view';
    _setLoading(key, true);
    try {
      // Status is resolved per ITEM inside _goodsData, not by the query — the
      // packages.status column is stale (always 'pending').
      final pkgs = _filterByWarehouse(_filterByDate(await ref
          .read(packageServiceProvider)
          .getAllPackages(yard: _yardArg)));
      final base = title.replaceAll(' ', '_');
      final data = await _goodsData(pkgs, statusFilter: status);
      if (data.$2.isEmpty) {
        _showNoDataMessage();
        return;
      }
      // Export exactly the rows on screen, so a Status filter applies to the
      // PDF/Excel too (they used to re-export every package).
      await _showReportTable(
        title: title,
        subtitle: subtitle,
        columns: data.$1,
        rows: data.$2,
        rowItemIds: data.$3,
        onSavePdf: () => _showPdfPreview(
            (f) => ReportService().generateStockRevenuePdf(
                  title: title.toUpperCase(),
                  periodLabel: subtitle ?? 'Full Historical Audit',
                  headline: '${data.$2.length} goods',
                  columns: data.$1,
                  rows: data.$2,
                  format: f.copyWith(
                      marginLeft: 20,
                      marginRight: 20,
                      marginTop: 20,
                      marginBottom: 20),
                ),
            '$base.pdf'),
        onExportExcel: () {
          if (!mounted) return;
          showDialog(
            context: context,
            builder: (c) => ExcelExportDialog(
              title: 'Export $title',
              recordCount: data.$2.length,
              fileName: '$base.xlsx',
              onExport: () => ReportService().exportTableToExcel(
                title: title.toUpperCase(),
                subTitle: subtitle ?? 'Full Historical Audit',
                columns: data.$1,
                rows: data.$2,
              ),
              onSave: (b) => _handleFileSave(b, base, 'xlsx'),
            ),
          );
        },
      );
    } finally {
      _setLoading(key, false);
    }
  }

  /// View stock & revenue reconciliation statement in-app.
  Future<void> _viewStockReconciliation() async {
    await _stockRevenueReport('reconciliation', 'view');
  }

  // ── Executive Office (DG / ADG) only reports ────────────────────────────
  // Three fixed-column listings the Top Management Directorate sign off on.
  // Column sets are exactly as specified — no extra columns.

  /// Emit one of the Top Management Directorate listings: shows it in-app, previews a PDF, or exports
  /// Excel, from a pre-built column/row set.
  Future<void> _emitDgReport({
    required String key,
    required String title,
    required String fileBase,
    required String format,
    required List<String> columns,
    required List<List<String>> rows,
    List<String?>? rowItemIds,
  }) async {
    if (rows.isEmpty) {
      _showNoDataMessage();
      return;
    }
    final String periodLabel;
    if (_startDate != null && _endDate != null) {
      periodLabel =
          'From ${DateFormat('yyyy-MM-dd').format(_startDate!)} To ${DateFormat('yyyy-MM-dd').format(_endDate!)}';
    } else if (key == 'Current Yard Stock') {
      periodLabel = 'Active Inventory Report (Currently in Yard)';
    } else {
      periodLabel = 'Full Historical Report';
    }

    void savePdf() => _showPdfPreview(
          (f) => ReportService().generateStockRevenuePdf(
            title: title,
            periodLabel: periodLabel,
            headline: '${rows.length} goods',
            columns: columns,
            rows: rows,
            format: f.copyWith(
                marginLeft: 15,
                marginRight: 15,
                marginTop: 15,
                marginBottom: 15),
          ),
          '$fileBase.pdf',
        );

    void exportExcel() {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (c) => ExcelExportDialog(
          title: 'Export $key',
          recordCount: rows.length,
          fileName: '$fileBase.xlsx',
          onExport: () => ReportService().exportTableToExcel(
            title: title,
            subTitle: periodLabel,
            columns: columns,
            rows: rows,
          ),
          onSave: (b) => _handleFileSave(b, fileBase, 'xlsx'),
        ),
      );
    }

    if (format == 'view') {
      await _showReportTable(
        title: key,
        subtitle: periodLabel,
        columns: columns,
        rows: rows,
        rowItemIds: rowItemIds,
        onSavePdf: savePdf,
        onExportExcel: exportExcel,
      );
    } else if (format == 'pdf') {
      savePdf();
    } else {
      exportExcel();
    }
  }

  /// **Released Goods Report**
  ///
  /// Columns: SR Number · Goods Name · Goods Description · Entry Date · Released Date · Quantity · Warehouse Charges (LKR).
  Future<void> _generateReleasedGoodsReport(String format) async {
    const key = 'Released Goods';
    _setLoading('${key}_$format', true);
    try {
      final packages = _filterByWarehouse(_filterByDate(await ref
          .read(packageServiceProvider)
          .getAllPackages(yard: _yardArg)));
      final rates = ref.read(storageRateProvider).valueOrNull;

      final rows = <List<String>>[];
      final itemIds = <String?>[];
      final df = DateFormat('yyyy-MM-dd');
      final money = NumberFormat('#,##0.00');

      for (final p in packages) {
        for (final entry in p.warehouseEntries) {
          if (!entry.isReturned) continue;

          PackageItem? matchItem;
          if (entry.packageItemId != null) {
            matchItem =
                p.items.where((i) => i.id == entry.packageItemId).firstOrNull;
          }
          matchItem ??= (p.items.isNotEmpty ? p.items.first : null);

          final itemName = entry.itemName ?? matchItem?.itemName ?? '—';
          final desc = matchItem?.goodsDescription?.trim();
          final goodsDesc = (desc?.isNotEmpty == true) ? desc! : '—';
          final entryDate = entry.admittedAt;
          final releasedDate = entry.returnedAt;
          final qty = entry.itemCount > 0
              ? entry.itemCount
              : (matchItem?.quantity ?? 1);

          final charge = (rates != null)
              ? entry.calculatePackageCharge(p.items, rates)
              : (entry.accumulatedCharge ?? 0.0);

          rows.add([
            p.srNumber,
            itemName,
            goodsDesc,
            df.format(entryDate),
            releasedDate != null ? df.format(releasedDate) : '—',
            '$qty',
            money.format(charge),
          ]);
          itemIds.add(matchItem?.id ?? entry.packageItemId);
        }
      }

      await _emitDgReport(
        key: key,
        title: 'RELEASED GOODS',
        fileBase: 'Released_Goods',
        format: format,
        columns: const [
          'SR Number',
          'Goods Name',
          'Goods Description',
          'Entry Date',
          'Released Date',
          'Quantity',
          'Warehouse Charges (LKR)',
        ],
        rows: rows,
        rowItemIds: itemIds,
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading('${key}_$format', false);
    }
  }

  /// **Inventory Report** — Current Yard Stock (active only) vs. All-Time SR Register (all).
  ///
  /// Columns: SR Number · Goods Name · Goods Description · Post Status Activity · Entry Date · Value (LKR).
  Future<void> _generateInventoryReport({
    required bool activeOnly,
    required String format,
  }) async {
    final key = activeOnly ? 'Current Yard Stock' : 'All-Time SR Register';
    _setLoading('${key}_$format', true);
    try {
      final packages = _filterByWarehouse(_filterByDate(await ref
          .read(packageServiceProvider)
          .getAllPackages(yard: _yardArg)));

      final rows = <List<String>>[];
      final itemIds = <String?>[];

      const inactiveStatuses = {
        'released',
        'returned',
        'sold',
        'destroyed',
        're-exported',
      };

      for (final p in packages) {
        for (final it in p.items) {
          final itemStatus =
              _normStatus(it.status.isNotEmpty ? it.status : p.status);

          if (activeOnly) {
            if (inactiveStatuses.contains(itemStatus.toLowerCase())) {
              continue;
            }
          }

          if (_selectedStatus != 'all' &&
              itemStatus.toLowerCase() != _selectedStatus.toLowerCase()) {
            continue;
          }

          final entry = p.warehouseEntries
              .where((e) => e.packageItemId == it.id)
              .firstOrNull;

          if (activeOnly && entry != null && entry.isReturned) {
            continue;
          }

          final activity = (it.reasons?.trim().isNotEmpty == true)
              ? it.reasons!.trim()
              : ((entry?.holdReason.trim().isNotEmpty ?? false)
                  ? entry!.holdReason.trim()
                  : '—');

          if (_selectedActivity != 'all' && activity != _selectedActivity) {
            continue;
          }

          final entryDate = p.entryDate ?? p.createdAt;
          final value = it.unitValue * it.quantity;

          rows.add([
            p.srNumber,
            it.itemName,
            (it.goodsDescription?.trim().isNotEmpty == true)
                ? it.goodsDescription!.trim()
                : '—',
            activity,
            DateFormat('yyyy-MM-dd').format(entryDate),
            NumberFormat('#,##0.##').format(value),
          ]);
          itemIds.add(it.id);
        }
      }

      final reportTitle =
          activeOnly ? 'CURRENT YARD STOCK' : 'SR REGISTER INVENTORY';
      final fileBase =
          activeOnly ? 'Current_Yard_Stock' : 'SR_Register_Inventory';

      await _emitDgReport(
        key: key,
        title: reportTitle,
        fileBase: fileBase,
        format: format,
        columns: const [
          'SR Number',
          'Goods Name',
          'Goods Description',
          'Post Status Activity',
          'Entry Date',
          'Value (LKR)',
        ],
        rows: rows,
        rowItemIds: itemIds,
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading('${key}_$format', false);
    }
  }

  /// **List of the SRs** — SR Number · Item Name · Goods Description ·
  /// Quantity · Status. One row per package item.
  Future<void> _generateSrListReport(String format) async {
    final key = 'List of the SRs';
    _setLoading('${key}_$format', true);
    try {
      final packages = _filterByWarehouse(_filterByDate(await ref
          .read(packageServiceProvider)
          .getAllPackages(yard: _yardArg)));

      final rows = <List<String>>[];
      final itemIds = <String?>[];
      for (final p in packages) {
        for (final it in p.items) {
          final status =
              _normStatus(it.status.isNotEmpty ? it.status : p.status);
          if (_selectedStatus != 'all' &&
              status.toLowerCase() != _selectedStatus.toLowerCase()) {
            continue;
          }
          // The Post Status Activity lives on the item's `reasons`, falling
          // back to the warehouse entry's hold reason (that is where the SR
          // form writes it).
          final entry = p.warehouseEntries
              .where((e) => e.packageItemId == it.id)
              .firstOrNull;
          final activity = (it.reasons?.trim().isNotEmpty == true)
              ? it.reasons!.trim()
              : ((entry?.holdReason.trim().isNotEmpty ?? false)
                  ? entry!.holdReason.trim()
                  : '—');
          // Narrowed by the Post Status Activity filter above, so the stock can
          // be read one activity at a time.
          if (_selectedActivity != 'all' && activity != _selectedActivity) {
            continue;
          }

          final entryDate = p.entryDate ?? p.createdAt;
          final value = it.unitValue * it.quantity;

          rows.add([
            p.srNumber,
            it.itemName,
            (it.goodsDescription?.trim().isNotEmpty == true)
                ? it.goodsDescription!.trim()
                : '—',
            activity,
            DateFormat('yyyy-MM-dd').format(entryDate),
            NumberFormat('#,##0.##').format(value),
          ]);
          itemIds.add(it.id);
        }
      }

      await _emitDgReport(
        key: key,
        title: 'SR REGISTER INVENTORY',
        fileBase: 'SR_Register_Inventory',
        format: format,
        columns: const [
          'SR Number',
          'Goods Name',
          'Goods Description',
          'Post Status Activity',
          'Entry Date',
          'Value (LKR)',
        ],
        rows: rows,
        rowItemIds: itemIds,
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading('${key}_$format', false);
    }
  }

  /// **List of Goods for Valuation** — SR Number · Item Name · Goods
  /// Description · Quantity · HS Code · Initial Value.
  ///
  /// "Initial Value" is the FIRST valuation given to a tender-sale package
  /// (`disposal_request_items.valuation_cost`), i.e. chain index 0.
  Future<void> _generateForValuationReport(String format) async {
    const key = 'List of Goods for Valuation';
    _setLoading('${key}_$format', true);
    try {
      final disposal = ref.read(disposalServiceProvider);
      final forfeited = _filterByYard(
          await disposal.getAllForfeitedForReports(), (f) => f.yard);
      final chains = await disposal.getValuationChains();

      final money = NumberFormat('#,##0.##');
      final rows = <List<String>>[];
      final itemIds = <String?>[];
      for (final f in _filterByDate(forfeited)) {
        final chain = chains[f.id];
        // Only goods that actually reached valuation belong on this list.
        if (chain == null || chain.isEmpty) continue;
        for (final it in _reportItemsOf(f)) {
          rows.add([
            f.srNumber,
            it?.itemName ?? f.itemName ?? '—',
            (it?.goodsDescription?.trim().isNotEmpty == true)
                ? it!.goodsDescription!.trim()
                : '—',
            '${f.entryQty ?? it?.quantity ?? '—'}',
            (it?.hsCode?.trim().isNotEmpty == true) ? it!.hsCode!.trim() : '—',
            money.format(chain.first),
          ]);
          itemIds.add(it?.id);
        }
      }

      await _emitDgReport(
        key: key,
        title: 'LIST OF GOODS FOR VALUATION',
        fileBase: 'List_of_Goods_for_Valuation',
        format: format,
        columns: const [
          'SR Number',
          'Goods Name',
          'Goods Description',
          'Quantity',
          'HS Code',
          'Initial Value',
        ],
        rows: rows,
        rowItemIds: itemIds,
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading('${key}_$format', false);
    }
  }

  /// **List of Goods Valued** — SR Number · Item Name · Goods Description,
  /// then the valuation columns chosen by the Valuation Round filter:
  /// every round side by side ('all'), or a single round on its own.
  Future<void> _generateValuedReport(String format) async {
    const key = 'List of Goods Valued';
    _setLoading('${key}_$format', true);
    try {
      final disposal = ref.read(disposalServiceProvider);
      final forfeited = _filterByYard(
          await disposal.getAllForfeitedForReports(), (f) => f.yard);
      final chains = await disposal.getValuationChains();

      final money = NumberFormat('#,##0.##');
      // 'all' → every round as its own column; otherwise just the picked one.
      final roundIdx = kValuationRounds.indexOf(_valuationRound);
      final showAll = _valuationRound == 'all' || roundIdx < 0;
      final valueCols =
          showAll ? kValuationRounds : [kValuationRounds[roundIdx]];

      /// The value for stage [i] of [chain] — strictly positional.
      ///
      /// The chain is built in stage order (initial, Tender 1-3, then the High
      /// Panel figure), so entry `i` IS stage `i`. The old code special-cased
      /// the last column to show `chain.last`, which put a Tender-1 figure
      /// under "Final Value" whenever the package never reached Tender 3.
      String valueAt(List<double> chain, int i) =>
          i < chain.length ? money.format(chain[i]) : '—';

      final rows = <List<String>>[];
      final itemIds = <String?>[];
      for (final f in _filterByDate(forfeited)) {
        final chain = chains[f.id];
        if (chain == null || chain.isEmpty) continue;
        // A single-round filter only lists goods that reached that round.
        if (!showAll && valueAt(chain, roundIdx) == '—') continue;
        for (final it in _reportItemsOf(f)) {
          rows.add([
            f.srNumber,
            it?.itemName ?? f.itemName ?? '—',
            (it?.goodsDescription?.trim().isNotEmpty == true)
                ? it!.goodsDescription!.trim()
                : '—',
            for (var i = 0; i < kValuationRounds.length; i++)
              if (showAll || i == roundIdx) valueAt(chain, i),
          ]);
          itemIds.add(it?.id);
        }
      }

      final label = showAll ? 'All Valuations' : _valuationRound;
      await _emitDgReport(
        key: '$key — $label',
        title: 'LIST OF GOODS VALUED — ${label.toUpperCase()}',
        fileBase:
            'List_of_Goods_Valued_${label.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}',
        format: format,
        columns: [
          'SR Number',
          'Goods Name',
          'Goods Description',
          ...valueCols,
        ],
        rows: rows,
        rowItemIds: itemIds,
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading('${key}_$format', false);
    }
  }

  /// **Top Management Directorate Valuation** — SR Number · Goods Name · Goods Description ·
  /// Final Valuation · Top Management Directorate Valuation.
  ///
  /// "Final Valuation" is the LAST price the Valuation Directorate set, i.e.
  /// the one Tender 3 was offered at. "Top Management Directorate Valuation" is the figure the
  /// appointed committee reached and the ADG submitted for the final tender.
  ///
  /// Only goods that reached the committee stage appear — anything the ADG has
  /// not submitted a value for has no Top Management Directorate valuation to report.
  Future<void> _generateHighPanelValuationReport(String format) async {
    const key = 'Top Management Directorate Valuation';
    _setLoading('${key}_$format', true);
    try {
      final disposal = ref.read(disposalServiceProvider);
      final forfeited = _filterByYard(
          await disposal.getAllForfeitedForReports(), (f) => f.yard);
      final chains = await disposal.getValuationChains();
      final committees = await disposal.getTenderCommittees();

      final money = NumberFormat('#,##0.##');
      final rows = <List<String>>[];
      final itemIds = <String?>[];
      for (final f in _filterByDate(forfeited)) {
        final c = committees[f.id];
        final panelValue = c?.submittedValue;
        if (panelValue == null) continue;

        // The ADG's submission ALSO writes a tender_revaluations row, so it is
        // the last link of the chain. The Valuation Directorate's own final
        // figure — what Tender 3 was priced at — is the link before it.
        final chain = chains[f.id] ?? const <double>[];
        final finalValuation =
            chain.length >= 2 ? chain[chain.length - 2] : null;

        for (final it in _reportItemsOf(f)) {
          rows.add([
            f.srNumber,
            it?.itemName ?? f.itemName ?? '—',
            (it?.goodsDescription?.trim().isNotEmpty == true)
                ? it!.goodsDescription!.trim()
                : '—',
            finalValuation != null ? money.format(finalValuation) : '—',
            money.format(panelValue),
          ]);
          itemIds.add(it?.id);
        }
      }

      await _emitDgReport(
        key: key,
        title: 'HIGH PANEL VALUATION',
        fileBase: 'High_Panel_Valuation',
        format: format,
        columns: const [
          'SR Number',
          'Goods Name',
          'Goods Description',
          'Final Valuation',
          'Top Management Directorate Valuation',
        ],
        rows: rows,
        rowItemIds: itemIds,
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading('${key}_$format', false);
    }
  }

  /// **Not Sold Packages** — SR Number · Item Name · Goods Description ·
  /// Top Management Directorate Committee Members · Proposed Decision.
  ///
  /// The goods that exhausted EVERY avenue: the Valuation Tender, Tender 1-3
  /// and the committee-priced final tender all failed. For each one it prints
  /// the committee the ADG appointed to value it and the final outcome the DG
  /// proposed (destroy / remand / government use / auction), or "Pending
  /// decision" when the DG has not ruled yet.
  Future<void> _generateNotSoldReport(String format) async {
    const key = 'Not Sold Packages';
    _setLoading('${key}_$format', true);
    try {
      final disposal = ref.read(disposalServiceProvider);
      final exhausted = await disposal.getExhaustedUnsoldPackages();
      final committees = await disposal.getTenderCommittees();
      final proposals = await disposal.getUnsoldProposals();

      final rows = <List<String>>[];
      final itemIds = <String?>[];
      for (final info in exhausted) {
        final f = info.forfeited;
        // Respect the portal's yard picker and the date range above.
        if (_yardArg != null && f.yard != _yardArg) continue;
        if (_startDate != null && f.forfeitedAt.isBefore(_startDate!)) continue;
        if (_endDate != null &&
            f.forfeitedAt.isAfter(DateTime(
                _endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59))) {
          continue;
        }

        // "Name (Designation) · Salary No" per member, one per line.
        final members = committees[f.id]?.members ?? const <CommitteeMember>[];
        final memberText = members.isEmpty
            ? 'No committee appointed'
            : members.map((m) {
                final desig = m.designation?.trim() ?? '';
                final sal = m.salaryNo?.trim() ?? '';
                return '${m.name.trim()}'
                    '${desig.isNotEmpty ? ' ($desig)' : ''}'
                    '${sal.isNotEmpty ? ' · $sal' : ''}';
              }).join('\n');

        final p = proposals[f.id];
        final decision = p == null
            ? 'Pending decision'
            : (p.note?.trim().isNotEmpty == true
                ? '${p.label}\n${p.note!.trim()}'
                : p.label);

        for (final it in _reportItemsOf(f)) {
          rows.add([
            f.srNumber,
            it?.itemName ?? f.itemName ?? '—',
            (it?.goodsDescription?.trim().isNotEmpty == true)
                ? it!.goodsDescription!.trim()
                : '—',
            memberText,
            decision,
          ]);
          itemIds.add(it?.id);
        }
      }

      await _emitDgReport(
        key: key,
        title: 'UNSOLD GOODS',
        fileBase: 'Unsold_Goods',
        format: format,
        columns: const [
          'SR Number',
          'Goods Name',
          'Goods Description',
          'Top Management Directorate Committee Members',
          'Proposed Decision',
        ],
        rows: rows,
        rowItemIds: itemIds,
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading('${key}_$format', false);
    }
  }

  /// Financials, SR BY SR — every figure the Top Management Directorate's Financials tab
  /// totals, listed per SR so a headline can be traced to what produced it.
  ///
  /// Reads the same [srFinancialsProvider] the tab does, so the report and
  /// the screen can never disagree. The refund column is DERIVED, never stored:
  /// it is the unspent part of that SR's destroying deposit.
  Future<void> _generateGoodsFinancialsReport(String format) async {
    const key = 'Goods Financials';
    _setLoading('${key}_$format', true);
    try {
      final all = await ref.read(srFinancialsProvider.future);
      final taxesAsync = await ref.read(disposalTaxesProvider.future);
      final configuredTaxNames =
          taxesAsync.where((t) => t.isActive).map((t) => t.name).toList();
      final taxNames = <String>[
        if (configuredTaxNames.isEmpty) ...['VAT', 'PAL'] else
          ...configuredTaxNames
      ];
      for (final r in all) {
        for (final k in r.taxesByName.keys) {
          if (!taxNames.contains(k)) taxNames.add(k);
        }
      }

      final rows = <List<String>>[];
      final itemIds = <String?>[];
      var srsCounted = 0;
      var totalSrCharges = 0.0;
      var totalDestroyingDeposit = 0.0;
      var totalSaleProceeds = 0.0;
      final taxTotalsMap = <String, double>{};
      var totalTaxes = 0.0;
      var totalDestruction = 0.0;
      var totalAdvertising = 0.0;
      var totalLabour = 0.0;
      var totalTransport = 0.0;
      var totalAuction = 0.0;
      var refundTotal = 0.0;

      for (final r in all) {
        // SRs with nothing recorded would only pad the report out.
        if (r.isEmpty) continue;
        // Respect the portal's yard picker. Falls back to the SR prefix when a
        // row carries no yard, the same way the tab's filter does.
        if (_yardArg != null &&
            (r.yard ?? yardOfSrNumber(r.srNumber)) != _yardArg) {
          continue;
        }

        final split = r.split;
        rows.add([
          r.srNumber,
          _reportMoney(r.srCharges),
          _reportMoney(r.destroyingDeposit),
          _reportMoney(r.saleProceeds),
          for (final tName in taxNames) _reportMoney(r.taxesByName[tName] ?? 0),
          _reportMoney(r.taxes),
          _reportMoney(r.totalIncome),
          _reportMoney(r.destructionExpense),
          _reportMoney(r.advertisingExpense),
          _reportMoney(r.labourExpense),
          _reportMoney(r.transportExpense),
          _reportMoney(r.auctionExpense),
          // A deficit prints as a negative so an overrun is never mistaken for
          // a refund of zero.
          r.deficit > 0
              ? '-${_reportMoney(r.deficit)}'
              : _reportMoney(r.refund),
          _reportMoney(r.totalExpenditure),
          _reportMoney(r.netBalance),
          _reportMoney(split.rewardFund),
          _reportMoney(split.deputySecretaryTreasury),
          _reportMoney(split.consolidatedFund),
          _reportMoney(split.compFund),
        ]);
        itemIds.add(r.goods.isNotEmpty ? r.goods.first.itemId : null);

        refundTotal += r.refund;
        srsCounted++;
        totalSrCharges += r.srCharges;
        totalDestroyingDeposit += r.destroyingDeposit;
        totalSaleProceeds += r.saleProceeds;
        for (final tName in taxNames) {
          taxTotalsMap[tName] =
              (taxTotalsMap[tName] ?? 0) + (r.taxesByName[tName] ?? 0);
        }
        totalTaxes += r.taxes;
        totalDestruction += r.destructionExpense;
        totalAdvertising += r.advertisingExpense;
        totalLabour += r.labourExpense;
        totalTransport += r.transportExpense;
        totalAuction += r.auctionExpense;
      }

      if (rows.isNotEmpty) {
        final totalIncome = totalSrCharges +
            totalDestroyingDeposit +
            totalSaleProceeds +
            totalTaxes;
        final totalSpent = totalDestruction +
            totalAdvertising +
            totalLabour +
            totalTransport +
            totalAuction;
        final splitTotal = SaleProceedsSplit(totalSaleProceeds);

        rows.add([
          'TOTAL ($srsCounted SRs)',
          _reportMoney(totalSrCharges),
          _reportMoney(totalDestroyingDeposit),
          _reportMoney(totalSaleProceeds),
          for (final tName in taxNames) _reportMoney(taxTotalsMap[tName] ?? 0),
          _reportMoney(totalTaxes),
          _reportMoney(totalIncome),
          _reportMoney(totalDestruction),
          _reportMoney(totalAdvertising),
          _reportMoney(totalLabour),
          _reportMoney(totalTransport),
          _reportMoney(totalAuction),
          _reportMoney(refundTotal),
          _reportMoney(totalSpent + refundTotal),
          _reportMoney(totalIncome - (totalSpent + refundTotal)),
          _reportMoney(splitTotal.rewardFund),
          _reportMoney(splitTotal.deputySecretaryTreasury),
          _reportMoney(splitTotal.consolidatedFund),
          _reportMoney(splitTotal.compFund),
        ]);
        itemIds.add(null);
      }

      await _emitDgReport(
        key: key,
        title: 'SR FINANCIALS',
        fileBase: 'SR_Financials',
        format: format,
        columns: [
          'SR Number',
          'SR Charges',
          'Destroy Deposit',
          'Sale Proceeds',
          for (final tName in taxNames) tName,
          'Total Tax',
          'Total Income',
          'Destruction',
          'Advertising',
          'Labour',
          'Transport',
          'Auction',
          'Refund',
          'Total Expenditure',
          'Net',
          'Reward Fund',
          'Treasury',
          'Consolidated Fund',
          'Comp Fund',
        ],
        rows: rows,
        rowItemIds: itemIds,
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading('${key}_$format', false);
    }
  }

  /// Money for a report cell: grouped, two decimals, and a bare dash for zero
  /// so a populated figure stands out in a wall of numbers.
  static String _reportMoney(double v) =>
      v == 0 ? '-' : NumberFormat('#,##0.00').format(v);

  /// Goods the Top Management Directorate decided a particular way — Unsold, Remand, Auction
  /// or Convert. One generator for all of them: the report differs only by
  /// which `unsold_proposals.proposal` it keeps.
  ///
  /// [outcome] null lists every exhausted-unsold package whatever was decided
  /// (including those still awaiting a decision), which is the Unsold report.
  Future<void> _generateOutcomeReport(
    String format, {
    required String key,
    required String title,
    required String fileBase,
    String? outcome,
  }) async {
    _setLoading('${key}_$format', true);
    try {
      final disposal = ref.read(disposalServiceProvider);
      final exhausted = await disposal.getExhaustedUnsoldPackages();
      final proposals = await disposal.getUnsoldProposals();

      final money = NumberFormat('#,##0.##');
      final rows = <List<String>>[];
      final itemIds = <String?>[];

      for (final info in exhausted) {
        final f = info.forfeited;
        if (_yardArg != null && f.yard != _yardArg) continue;
        if (_startDate != null && f.forfeitedAt.isBefore(_startDate!)) continue;
        if (_endDate != null &&
            f.forfeitedAt.isAfter(DateTime(
                _endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59))) {
          continue;
        }

        final p = proposals[f.id];
        // An outcome report keeps only goods decided that way.
        if (outcome != null && p?.proposal != outcome) continue;

        final qty = unsoldQty(f);
        final value = f.valuationCost != null ? f.valuationCost! * qty : null;

        for (final it in _reportItemsOf(f)) {
          rows.add([
            f.srNumber,
            it?.itemName ?? f.itemName ?? '\u2014',
            (it?.goodsDescription?.trim().isNotEmpty == true)
                ? it!.goodsDescription!.trim()
                : '\u2014',
            '$qty',
            f.consigneeName,
            value == null ? '\u2014' : money.format(value),
            p?.label ?? 'Awaiting decision',
          ]);
          itemIds.add(it?.id);
        }
      }

      await _emitDgReport(
        key: key,
        title: title,
        fileBase: fileBase,
        format: format,
        columns: const [
          'SR Number',
          'Goods Name',
          'Goods Description',
          'Qty',
          'Consignee',
          'Valuation (LKR)',
          'Final Outcome',
        ],
        rows: rows,
        rowItemIds: itemIds,
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading('${key}_$format', false);
    }
  }

  /// **Appeal Goods** — every goods item an appeal has touched.
  ///
  /// SR Number \u00b7 Goods Name \u00b7 Goods Description \u00b7 Appeal Date \u00b7 Decision.
  ///
  /// A goods item still under review reports **"Appeal Hold"** rather than a
  /// decision, which is the state the yard needs to see: it is why the goods
  /// cannot be acted on.
  Future<void> _generateAppealGoodsReport(String format) async {
    const key = 'Appeal Goods';
    _setLoading('${key}_$format', true);
    try {
      // Every forfeited row across all four sources — an appeal can be lodged
      // against Detain / Abandoned / Other as well as a genuine forfeit.
      final rowsIn = _filterByYard(
          await ref.read(disposalServiceProvider).getAllForfeitedForReports(),
          (f) => f.yard);

      final df = DateFormat('yyyy-MM-dd');
      final rows = <List<String>>[];
      final itemIds = <String?>[];

      for (final f in _filterByDate(rowsIn)) {
        for (final it in _reportItemsOf(f)) {
          final id = it?.id ?? f.itemId;

          final held = f.heldItemIds.isNotEmpty
              ? f.heldItemIds.contains(id)
              : f.appealHold;
          final decision = f.appealDecisionLabelForItem(id);

          // Only goods an appeal actually touched belong in this report.
          if (!held && decision == null) continue;

          // A hold outranks a decision: while it stands the goods are frozen.
          final state = held ? 'Appeal Hold' : (decision ?? '\u2014');

          final when = f.appealDecidedAt ?? f.appealHeldAt;

          rows.add([
            f.srNumber,
            it?.itemName ?? f.itemName ?? '\u2014',
            (it?.goodsDescription?.trim().isNotEmpty == true)
                ? it!.goodsDescription!.trim()
                : '\u2014',
            when != null ? df.format(when) : '\u2014',
            state,
          ]);
          itemIds.add(id);
        }
      }

      await _emitDgReport(
        key: key,
        title: 'APPEAL GOODS',
        fileBase: 'Appeal_Goods',
        format: format,
        columns: const [
          'SR Number',
          'Goods Name',
          'Goods Description',
          'Appeal Date',
          'Decision',
        ],
        rows: rows,
        rowItemIds: itemIds,
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading('${key}_$format', false);
    }
  }

  /// The package items a forfeited row covers: the one item it points at for
  /// per-item rows, otherwise every item of the package (`[null]` when the
  /// package details did not load, so the row still prints).
  List<PackageItem?> _reportItemsOf(ForfeitedPackageModel f) {
    final all = f.packageDetails?.items ?? const <PackageItem>[];
    if (f.itemId != null) {
      final match = all.where((i) => i.id == f.itemId).toList();
      return match.isNotEmpty ? match : <PackageItem?>[null];
    }
    return all.isEmpty ? <PackageItem?>[null] : all;
  }

  /// One report per Post Status Activity: every goods row whose item carries
  /// [activity]. Honours the Date / Warehouse / Status filters above, so e.g.
  /// "Pending Licence" + Status=Detain narrows to still-detained licence cases.
  Future<void> _generateActivityReport(String activity, String format) async {
    final key = '${activity}_$format';
    _setLoading(key, true);
    try {
      final packages =
          await ref.read(packageServiceProvider).getAllPackages(yard: _yardArg);
      final filtered = _filterByWarehouse(_filterByDate(packages));
      final data = await _goodsData(filtered,
          statusFilter: _selectedStatus, activityFilter: activity);
      if (data.$2.isEmpty) {
        _showNoDataMessage();
        return;
      }

      final title = '${activity.toUpperCase()} — POST STATUS ACTIVITY REPORT';
      final base =
          '${activity.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}_Activity';
      final periodLabel = (_startDate != null && _endDate != null)
          ? 'From ${DateFormat('yyyy-MM-dd').format(_startDate!)} To ${DateFormat('yyyy-MM-dd').format(_endDate!)}'
          : 'Full Historical Report';

      void savePdf() => _showPdfPreview(
            (f) => ReportService().generateStockRevenuePdf(
              title: title,
              periodLabel: periodLabel,
              headline: '${data.$2.length} goods',
              columns: data.$1,
              rows: data.$2,
              format: f.copyWith(
                  marginLeft: 20,
                  marginRight: 20,
                  marginTop: 20,
                  marginBottom: 20),
            ),
            '$base.pdf',
          );

      void exportExcel() {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (c) => ExcelExportDialog(
            title: 'Export $activity Report',
            recordCount: data.$2.length,
            fileName: '$base.xlsx',
            onExport: () => ReportService().exportTableToExcel(
              title: title,
              subTitle: periodLabel,
              columns: data.$1,
              rows: data.$2,
            ),
            onSave: (b) => _handleFileSave(b, base, 'xlsx'),
          ),
        );
      }

      if (format == 'view') {
        await _showReportTable(
          title: '$activity — Post Status Activity',
          subtitle: periodLabel,
          columns: data.$1,
          rows: data.$2,
          rowItemIds: data.$3,
          onSavePdf: savePdf,
          onExportExcel: exportExcel,
        );
      } else if (format == 'pdf') {
        savePdf();
      } else {
        exportExcel();
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(key, false);
    }
  }

  /// One report card per Post Status Activity, driven by
  /// [kAllPostStatusActivities] so the grid grows automatically when an
  /// activity is added there. Shared by the full Report Generator (as its
  /// Section 2) and the Central Disposal Reports tab (where it is the whole
  /// page).
  Widget _buildActivityGrid(int crossAxisCount) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: crossAxisCount,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 3.4,
      children: [
        for (final activity in kAllPostStatusActivities)
          _buildReportCard(
            title: activity,
            description: kDetainActivities.contains(activity) &&
                    kDisposalActivities.contains(activity)
                ? 'Goods with the "$activity" activity (any status).'
                : (kDetainActivities.contains(activity)
                    ? 'Detained goods pending this activity.'
                    : 'Goods marked "$activity".'),
            icon: _activityIcon(activity),
            color: _activityColor(activity),
            onView: () => _generateActivityReport(activity, 'view'),
            onPdf: () => _generateActivityReport(activity, 'pdf'),
            onExcel: () => _generateActivityReport(activity, 'excel'),
          ),
      ],
    );
  }

  Widget _buildReportCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Four across on a wide window: the cards hold a title, one line of
        // description and two buttons, so three columns left them far wider
        // than their content.
        final crossAxisCount = constraints.maxWidth > 1400
            ? 4
            : (constraints.maxWidth > 900
                ? 3
                : (constraints.maxWidth > 600 ? 2 : 1));

        return FutureBuilder<ProfileModel?>(
          future: ref.read(authServiceProvider).getCurrentProfile(),
          builder: (context, snapshot) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (snapshot.hasError)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: ErrorView(
                        error: snapshot.error!, onRetry: () => setState(() {})),
                  ),

                // ── Section 1: SR Register & Inventory Reports ──
                _buildSectionHeader(
                    'SR Register & Inventory Reports', Icons.article_rounded),
                const Gap(8),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 3.4,
                  children: [
                    _buildReportCard(
                      title: 'Current Yard Stock',
                      description:
                          'Active goods currently in the yard (excludes released / disposed).',
                      icon: Icons.inventory_2_rounded,
                      color: context.colors.primaryGold,
                      onView: () => _generateInventoryReport(
                          activeOnly: true, format: 'view'),
                      onPdf: () => _generateInventoryReport(
                          activeOnly: true, format: 'pdf'),
                      onExcel: () => _generateInventoryReport(
                          activeOnly: true, format: 'excel'),
                    ),
                    _buildReportCard(
                      title: 'All-Time SR Register',
                      description:
                          'Full historical register of all SR goods (past & present).',
                      icon: Icons.history_edu_rounded,
                      color: const Color(0xFF00897B),
                      onView: () => _generateInventoryReport(
                          activeOnly: false, format: 'view'),
                      onPdf: () => _generateInventoryReport(
                          activeOnly: false, format: 'pdf'),
                      onExcel: () => _generateInventoryReport(
                          activeOnly: false, format: 'excel'),
                    ),
                  ],
                ),

                // ── Section 2: Goods Disposition Reports ──
                // (How goods are classified: Forfeit / Abandon / Other / Re-export)
                const Gap(24),
                _buildSectionHeader('Goods Disposition Reports',
                    Icons.assignment_turned_in_rounded),
                const Gap(8),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 3.4,
                  children: [
                    _buildReportCard(
                      title: 'Forfeited Goods',
                      description: 'All forfeited goods in this yard.',
                      icon: Icons.gavel_rounded,
                      color: const Color(0xFFC62828),
                      onView: () => _generateForfeitedReport('view'),
                      onPdf: () => _generateForfeitedReport('pdf'),
                      onExcel: () => _generateForfeitedReport('excel'),
                    ),
                    _buildReportCard(
                      title: 'Abandoned Goods',
                      description: 'Goods abandoned by the consignee.',
                      icon: Icons.inbox_rounded,
                      color: const Color(0xFF8D6E63),
                      onView: () => _generateSourceForfeitedReport(
                          'abandoned', 'Abandoned Goods', 'view'),
                      onPdf: () => _generateSourceForfeitedReport(
                          'abandoned', 'Abandoned Goods', 'pdf'),
                      onExcel: () => _generateSourceForfeitedReport(
                          'abandoned', 'Abandoned Goods', 'excel'),
                    ),
                    _buildReportCard(
                      title: 'Other Goods',
                      description: 'Goods routed via "Other" disposition.',
                      icon: Icons.more_horiz_rounded,
                      color: const Color(0xFF5E35B1),
                      onView: () => _generateSourceForfeitedReport(
                          'other', 'Other Goods', 'view'),
                      onPdf: () => _generateSourceForfeitedReport(
                          'other', 'Other Goods', 'pdf'),
                      onExcel: () => _generateSourceForfeitedReport(
                          'other', 'Other Goods', 'excel'),
                    ),
                    _buildReportCard(
                      title: 'Appeal Goods',
                      description:
                          'Goods under appeal, with the decision or hold.',
                      icon: Icons.gavel_rounded,
                      color: const Color(0xFF7B1FA2),
                      onPdf: () => _generateAppealGoodsReport('pdf'),
                      onExcel: () => _generateAppealGoodsReport('excel'),
                    ),
                    _buildReportCard(
                      title: 'Re-exported Goods',
                      description: 'Goods routed via Re-export disposition.',
                      icon: Icons.flight_takeoff_rounded,
                      color: const Color(0xFF00796B),
                      onView: () => _generateReexportedReport('view'),
                      onPdf: () => _generateReexportedReport('pdf'),
                      onExcel: () => _generateReexportedReport('excel'),
                    ),
                  ],
                ),

                // ── Section 3: Valuation & Financial Reports ──
                const Gap(24),
                _buildSectionHeader("Valuation & Financial Reports",
                    Icons.account_balance_rounded),
                const Gap(8),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 3.4,
                  children: [
                    _buildReportCard(
                      title: 'List of Goods for Valuation',
                      description:
                          'Goods sent for valuation, with their initial value.',
                      icon: Icons.price_check_rounded,
                      color: const Color(0xFF00897B),
                      onView: () => _generateForValuationReport('view'),
                      onPdf: () => _generateForValuationReport('pdf'),
                      onExcel: () => _generateForValuationReport('excel'),
                    ),
                    _buildReportCard(
                      title: 'List of Goods Valued',
                      description: _valuationRound == 'all'
                          ? 'Every valuation round side by side.'
                          : 'Goods valued — ${_valuationRound.toLowerCase()} only.',
                      icon: Icons.stacked_line_chart_rounded,
                      color: const Color(0xFF3949AB),
                      onView: () => _generateValuedReport('view'),
                      onPdf: () => _generateValuedReport('pdf'),
                      onExcel: () => _generateValuedReport('excel'),
                    ),
                    _buildReportCard(
                      title: 'Top Management Directorate Valuation',
                      description:
                          'Final valuation vs. the committee\'s figure.',
                      icon: Icons.balance_rounded,
                      color: const Color(0xFF00695C),
                      onView: () => _generateHighPanelValuationReport('view'),
                      onPdf: () => _generateHighPanelValuationReport('pdf'),
                      onExcel: () => _generateHighPanelValuationReport('excel'),
                    ),
                    _buildReportCard(
                      title: 'Goods Financials',
                      description:
                          'Income, expenditure & the proceeds split, per SR.',
                      icon: Icons.account_balance_wallet_rounded,
                      color: const Color(0xFF00838F),
                      onView: () => _generateGoodsFinancialsReport('view'),
                      onPdf: () => _generateGoodsFinancialsReport('pdf'),
                      onExcel: () => _generateGoodsFinancialsReport('excel'),
                    ),
                    _buildReportCard(
                      title: 'Unsold Goods',
                      description:
                          'Committee members & the DG\'s proposed decision.',
                      icon: Icons.rule_folder_rounded,
                      color: const Color(0xFFEF6C00),
                      onView: () => _generateNotSoldReport('view'),
                      onPdf: () => _generateNotSoldReport('pdf'),
                      onExcel: () => _generateNotSoldReport('excel'),
                    ),
                    // ── The Outcomes, one report each ──
                    _buildReportCard(
                      title: 'Remanded Goods',
                      description: 'Unsold goods remanded for further action.',
                      icon: Icons.reply_all_rounded,
                      color: const Color(0xFF1565C0),
                      onView: () => _generateOutcomeReport('view',
                          key: 'Remanded Goods',
                          title: 'REMANDED GOODS',
                          fileBase: 'Remanded_Goods',
                          outcome: 'remand'),
                      onPdf: () => _generateOutcomeReport('pdf',
                          key: 'Remanded Goods',
                          title: 'REMANDED GOODS',
                          fileBase: 'Remanded_Goods',
                          outcome: 'remand'),
                      onExcel: () => _generateOutcomeReport('excel',
                          key: 'Remanded Goods',
                          title: 'REMANDED GOODS',
                          fileBase: 'Remanded_Goods',
                          outcome: 'remand'),
                    ),
                    _buildReportCard(
                      title: 'Auction Goods',
                      description: 'Unsold goods sent to public auction.',
                      icon: Icons.gavel_rounded,
                      color: const Color(0xFFF9A825),
                      onView: () => _generateOutcomeReport('view',
                          key: 'Auction Goods',
                          title: 'AUCTION GOODS',
                          fileBase: 'Auction_Goods',
                          outcome: 'auction'),
                      onPdf: () => _generateOutcomeReport('pdf',
                          key: 'Auction Goods',
                          title: 'AUCTION GOODS',
                          fileBase: 'Auction_Goods',
                          outcome: 'auction'),
                      onExcel: () => _generateOutcomeReport('excel',
                          key: 'Auction Goods',
                          title: 'AUCTION GOODS',
                          fileBase: 'Auction_Goods',
                          outcome: 'auction'),
                    ),
                    _buildReportCard(
                      title: 'Converted Goods',
                      description:
                          'Unsold goods converted to another use or form.',
                      icon: Icons.autorenew_rounded,
                      color: const Color(0xFF6A1B9A),
                      onView: () => _generateOutcomeReport('view',
                          key: 'Converted Goods',
                          title: 'CONVERTED GOODS',
                          fileBase: 'Converted_Goods',
                          outcome: 'convert'),
                      onPdf: () => _generateOutcomeReport('pdf',
                          key: 'Converted Goods',
                          title: 'CONVERTED GOODS',
                          fileBase: 'Converted_Goods',
                          outcome: 'convert'),
                      onExcel: () => _generateOutcomeReport('excel',
                          key: 'Converted Goods',
                          title: 'CONVERTED GOODS',
                          fileBase: 'Converted_Goods',
                          outcome: 'convert'),
                    ),
                  ],
                ),

                // ── Section 4: Goods Disposal & Release Reports ──
                // (What happens to goods: Sold via Tender / Destroyed / Released)
                const Gap(24),
                _buildSectionHeader('Goods Disposal & Release Reports',
                    Icons.recycling_rounded),
                const Gap(8),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 3.4,
                  children: [
                    _buildReportCard(
                      title: 'Sold Goods (Tender)',
                      description:
                          'Forfeited goods sold via tender during the period.',
                      icon: Icons.sell_rounded,
                      color: Colors.teal,
                      onView: () => _stockRevenueReport('sold', 'view'),
                      onPdf: () => _stockRevenueReport('sold', 'pdf'),
                      onExcel: () => _stockRevenueReport('sold', 'excel'),
                    ),
                    _buildReportCard(
                      title: 'Destroyed Goods',
                      description:
                          'Forfeited goods destroyed in destruction tender during the period.',
                      icon: Icons.local_fire_department_rounded,
                      color: Colors.deepOrange,
                      onView: () => _stockRevenueReport('destroyed', 'view'),
                      onPdf: () => _stockRevenueReport('destroyed', 'pdf'),
                      onExcel: () => _stockRevenueReport('destroyed', 'excel'),
                    ),
                    _buildReportCard(
                      title: 'Released Goods',
                      description:
                          'All released goods with entry & release dates & charges.',
                      icon: Icons.keyboard_return_rounded,
                      color: const Color(0xFF2E7D32),
                      onView: () => _generateReleasedGoodsReport('view'),
                      onPdf: () => _generateReleasedGoodsReport('pdf'),
                      onExcel: () => _generateReleasedGoodsReport('excel'),
                    ),
                    _buildReportCard(
                      title: 'All Tenders',
                      description:
                          'Every tender sale, with its goods, proceeds & status.',
                      icon: Icons.storefront_rounded,
                      color: const Color(0xFF00695C),
                      onView: () => _stockRevenueReport('all_tenders', 'view'),
                      onPdf: () => _stockRevenueReport('all_tenders', 'pdf'),
                      onExcel: () =>
                          _stockRevenueReport('all_tenders', 'excel'),
                    ),
                    // Top Management only: the sheet the DG carries INTO a
                    // tender sale, listing exactly what the Tender Sales page
                    // is showing at that moment. The card itself always stays
                    // put; it is the rows that come and go with each sale.
                    if (widget.executiveMode)
                      _buildReportCard(
                        title: 'Tender Sale Sheet',
                        description:
                            'Goods in the running tenders, with valuations, '
                            'to carry into the sale.',
                        icon: Icons.gavel_rounded,
                        color: const Color(0xFF4527A0),
                        onView: () =>
                            _stockRevenueReport('tender_day', 'view'),
                        onPdf: () => _stockRevenueReport('tender_day', 'pdf'),
                        onExcel: () =>
                            _stockRevenueReport('tender_day', 'excel'),
                      ),
                  ],
                ),

                if (!widget.executiveMode && !widget.disposalMode) ...[
                  // ── Section 5: QR Code Labels (Yard Mode Only) ──
                  const Gap(24),
                  _buildSectionHeader(
                      'QR Code Labels', Icons.qr_code_2_rounded),
                  const Gap(8),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 3.4,
                    children: [
                      _buildQrCard(),
                    ],
                  ),
                ],
              ],
            )
                .animate()
                .slideY(begin: 0.1, duration: 400.ms, delay: 100.ms)
                .fadeIn();
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
            Expanded(
                child: Text('Generate QR Labels',
                    style: TextStyle(
                        color: context.colors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14))),
          ]),
          const Gap(4),
          Text('Pick goods and print or download their QR-code labels.',
              style: TextStyle(color: context.colors.textMuted, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
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

  /// Card icon for a Post Status Activity. Falls back to a neutral icon so an
  /// activity added to [kAllPostStatusActivities] still renders sensibly.
  IconData _activityIcon(String activity) {
    switch (activity) {
      case 'Pending Licence':
        return Icons.badge_rounded;
      case 'Pending Classification / Valuation':
        return Icons.calculate_rounded;
      case 'Pending Inquiry':
        return Icons.help_center_rounded;
      case 'Supposed to be Sold / Auction':
        return Icons.gavel_rounded;
      case 'Supposed to be Destroyed':
        return Icons.local_fire_department_rounded;
      case 'Supposed to be Converted':
        return Icons.change_circle_rounded;
      case 'Supposed to be Donated':
        return Icons.volunteer_activism_rounded;
      default:
        return Icons.more_horiz_rounded;
    }
  }

  /// Card accent for a Post Status Activity: the pending (Detain) ones share a
  /// warm amber family, the disposal ones reuse their outcome colours.
  Color _activityColor(String activity) {
    switch (activity) {
      case 'Pending Licence':
        return const Color(0xFFEF6C00);
      case 'Pending Classification / Valuation':
        return const Color(0xFFF9A825);
      case 'Pending Inquiry':
        return const Color(0xFFD84315);
      case 'Supposed to be Sold / Auction':
        return Colors.teal;
      case 'Supposed to be Destroyed':
        return Colors.deepOrange;
      case 'Supposed to be Converted':
        return Colors.indigo;
      case 'Supposed to be Donated':
        return const Color(0xFF2E7D32);
      default:
        return const Color(0xFF5E35B1);
    }
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: context.colors.primaryGold),
        const Gap(8),
        Text(title,
            style: TextStyle(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
      ],
    );
  }

  Widget _buildStatusCard(
      String title, String status, IconData icon, Color color) {
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
      final packages = await ref
          .read(packageServiceProvider)
          .getAllPackages(status: status, yard: _yardArg);
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
            title: '${status.toUpperCase()} GOODS Report',
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
              onSave: (bytes) =>
                  _handleFileSave(bytes, '${status}_Packages', 'xlsx'),
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
      final packages =
          await ref.read(packageServiceProvider).getAllPackages(yard: _yardArg);
      final entries = await ref
          .read(warehouseServiceProvider)
          .getAllWarehouseEntries(yard: _yardArg);

      final withDatePkgs = _filterByDate(packages);
      final withDateEntries = _filterByDate(entries);

      if (withDatePkgs.isEmpty && withDateEntries.isEmpty) {
        _showNoDataMessage();
        return;
      }

      _showPdfPreview(
        (format) => ReportService()
            .generateCategoryAndZonePdf(withDatePkgs, withDateEntries),
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
      final packages =
          await ref.read(packageServiceProvider).getAllPackages(yard: _yardArg);
      final entries = await ref
          .read(warehouseServiceProvider)
          .getAllWarehouseEntries(yard: _yardArg);

      final withDatePkgs = _filterByDate(packages);
      final withDateEntries = _filterByDate(entries);

      if (withDatePkgs.isEmpty && withDateEntries.isEmpty) {
        _showNoDataMessage();
        return;
      }

      final bytes = await ReportService()
          .exportCategoryAndZoneToExcel(withDatePkgs, withDateEntries);
      if (bytes != null) {
        _handleFileSave(
            bytes,
            'Category_Zone_Summary_${DateFormat('yyyyMMdd').format(DateTime.now())}',
            'xlsx');
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
      // Status is resolved per ITEM (not from the stale packages.status column),
      // so it is applied inside _goodsData rather than in the query.
      final packages =
          await ref.read(packageServiceProvider).getAllPackages(yard: _yardArg);
      final withDate = _filterByDate(packages);
      final filtered = _filterByWarehouse(withDate);

      if (filtered.isEmpty) {
        _showNoDataMessage();
        return;
      }

      final statusTitle =
          _selectedStatus == 'all' ? 'ALL' : _selectedStatus.toUpperCase();

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
      final data = await _goodsData(filtered, statusFilter: _selectedStatus);
      if (data.$2.isEmpty) {
        _showNoDataMessage();
        return;
      }
      _showPdfPreview(
        (format) => ReportService().generateStockRevenuePdf(
          title: '$statusTitle PACKAGES INVENTORY AUDIT$warehouseTitle',
          periodLabel: dateRangeStr,
          headline: '${data.$2.length} goods',
          columns: data.$1,
          rows: data.$2,
          format: format.copyWith(
              marginLeft: 20, marginRight: 20, marginTop: 20, marginBottom: 20),
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
      all =
          await ref.read(packageServiceProvider).getAllPackages(yard: _yardArg);
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
            if (it.destroyed && iid != null)
              destroyedByItem[iid] = it.destroyedAt;
          }
        }
      } catch (_) {}

      _showPdfPreview(
        (format) => ReportService().generateSinglePackagePdf(pkg,
            format: format.copyWith(
                marginLeft: 20,
                marginRight: 20,
                marginTop: 20,
                marginBottom: 20),
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
      all =
          await ref.read(packageServiceProvider).getAllPackages(yard: _yardArg);
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
        'SR Number',
        'Goods Name',
        'HS Code',
        'Quantity',
        'Consignee',
        'Status',
        'Entry Date',
        'Reason'
      ];
      final rows = pkg.items
          .map((i) => [
                pkg.srNumber,
                i.itemName,
                i.hsCode ?? '—',
                '${i.quantity}',
                pkg.consigneeName,
                pkg.status.toUpperCase(),
                pkg.entryDate != null
                    ? DateFormat('yyyy-MM-dd').format(pkg.entryDate!)
                    : '—',
                i.reasons ?? pkg.reason ?? '—',
              ])
          .toList();

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => ExcelExportDialog(
            title: 'Export History for ${pkg.srNumber}',
            recordCount: rows.length,
            fileName:
                'Package_${pkg.srNumber.replaceAll('/', '-')}_History.xlsx',
            onExport: () => ReportService().exportTableToExcel(
              title: 'PACKAGE HISTORY - ${pkg.srNumber}',
              subTitle: 'Consignee: ${pkg.consigneeName}',
              columns: columns,
              rows: rows,
            ),
            onSave: (bytes) => _handleFileSave(bytes,
                'Package_${pkg.srNumber.replaceAll('/', '-')}_History', 'xlsx'),
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
    // "Other: <custom text>" (the SR form's Other marker) groups under Other so
    // the Status filter can match it; the custom text stays in the Reason
    // column.
    if (t == 'other' || t.startsWith('other:')) return 'Other';
    return '${t[0].toUpperCase()}${t.substring(1)}';
  }

  /// Whether [item] carries [activity] among its Post Status Activities. The
  /// activities are stored comma-joined in `package_items.reasons` (up to 4),
  /// so match the split parts rather than the raw string — otherwise
  /// "Pending Licence" would also match "Pending Licence, Pending Inquiry"
  /// only by luck of substring position.
  bool _hasActivity(PackageItem? item, String activity) {
    final raw = item?.reasons?.trim();
    if (raw == null || raw.isEmpty) return false;
    final want = activity.trim().toLowerCase();
    return raw
        .split(',')
        .map((a) => a.trim().toLowerCase())
        .any((a) => a == want);
  }

  /// Item-level "goods" rows with the full column set shared by the Inventory
  /// Audit, Initial Stock and Goods reports. Resolves each item's ACTUAL
  /// outcome (Released / Sold / Destroyed, else its disposition) with the
  /// matching date, plus reason, receipt and value.
  ///
  /// When [statusFilter] is set (anything but `all`) only rows whose resolved
  /// Status equals it are returned — the filter therefore always matches the
  /// Status column the reader actually sees.
  ///
  /// [activityFilter] narrows to items carrying that Post Status Activity in
  /// their `reasons` list (see [kAllPostStatusActivities]); an item may hold up
  /// to 4, so it is matched against the split parts, not the raw string.
  Future<(List<String>, List<List<String>>, List<String?>)> _goodsData(
      List<PackageModel> packages,
      {String statusFilter = 'all',
      String activityFilter = 'all'}) async {
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
          if (it.destroyed && iid != null)
            destroyedByItem[iid] = it.destroyedAt;
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
      'SR Number',
      'Goods Name',
      'HS Code',
      'Qty',
      'Consignee',
      'Reason',
      'Status',
      'Outcome Date',
      'Receipt No',
      'Value (LKR)',
      'Entry Date'
    ];
    final rows = <List<String>>[];
    final itemIds = <String?>[];
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
        final released = p.warehouseEntries.where(
            (e) => e.isReturned && (it == null || e.packageItemId == it.id));
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
        if (statusFilter != 'all' &&
            status.toLowerCase() != statusFilter.toLowerCase()) {
          continue;
        }
        if (activityFilter != 'all' && !_hasActivity(it, activityFilter)) {
          continue;
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
        itemIds.add(it?.id);
      }
    }
    return (columns, rows, itemIds);
  }

  /// Stock & revenue metric reports. [metric] ∈ initial, total, added, sold,
  /// destroyed, revenue. Period = the Date-Range filter above (day/week/month/
  /// year, whatever the user picked). "Goods" = packages.
  Future<void> _stockRevenueReport(String metric,
      [String format = 'pdf']) async {
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
      List<String?> rowItemIds = [];

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
          rowItemIds = data.$3;
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
          rowItemIds = [];
          for (final it in soldItems) {
            double tax = 0;
            for (final t in it.appliedTaxes) {
              tax += (t is Map ? parseDbNum(t['amount']) : 0) ?? 0;
            }
            totalRev += it.soldPrice + tax;
            final f = it.forfeited;
            final pkgItems = f?.packageDetails?.items ?? const <PackageItem>[];
            // Goods Description rather than HS Code / Sold Date: this listing
            // is about what was sold and for how much.
            if (f?.itemId != null) {
              final match =
                  pkgItems.where((i) => i.id == f!.itemId).firstOrNull;
              final name = f?.itemName ?? match?.itemName ?? '—';
              final desc = match?.goodsDescription?.trim();
              rows.add([
                f?.srNumber ?? '—',
                name,
                (desc?.isNotEmpty == true) ? desc! : '—',
                money.format(it.soldPrice),
                money.format(tax),
                money.format(it.soldPrice + tax),
              ]);
              rowItemIds.add(f?.itemId);
            } else if (pkgItems.isNotEmpty) {
              for (final i in pkgItems) {
                rows.add([
                  f?.srNumber ?? '—',
                  i.itemName,
                  (i.goodsDescription?.trim().isNotEmpty == true)
                      ? i.goodsDescription!.trim()
                      : '—',
                  money.format(it.soldPrice),
                  money.format(tax),
                  money.format(it.soldPrice + tax),
                ]);
                rowItemIds.add(i.id);
              }
            } else {
              rows.add([
                f?.srNumber ?? '—',
                f?.itemName ?? '—',
                '—',
                money.format(it.soldPrice),
                money.format(tax),
                money.format(it.soldPrice + tax),
              ]);
              rowItemIds.add(null);
            }
          }
          if (metric == 'sold') {
            title = 'GOODS SOLD IN TENDER';
            headline = '${rows.length} goods';
          } else {
            title = 'TENDER REVENUE & BALANCE';
            final added = packages
                .where((p) => inPeriod(p.entryDate))
                .fold<int>(
                    0, (s, p) => s + (p.items.isEmpty ? 1 : p.items.length));
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
            'SR Number',
            'Goods Name',
            'Goods Description',
            'Sold Value',
            'Total Tax',
            'Total Amount',
          ];
          break;

        case 'all_tenders':
          // Every tender held so far, listed by the GOODS that went into each
          // -- the sale number and date repeat down its own items, so one
          // tender reads as a block. Sold items show what they fetched;
          // unsold ones say so, since "no price" and "sold for nothing" are
          // different facts.
          final allSales = await disposal.getTenderSales();
          var tenders = allSales
              .where((sale) => inPeriod(sale.saleDate ?? sale.createdAt))
              .toList();
          if (_yardArg != null) {
            // Per ITEM, not the sale's own yard: a sale can mix items from a
            // multi-directorate yard, so the sale-level code cannot tell them
            // apart.
            tenders = tenders
                .where((sale) => sale.items.any((i) => i.yard == _yardArg))
                .toList();
          }
          tenders.sort((a, b) => (b.saleDate ?? b.createdAt)
              .compareTo(a.saleDate ?? a.createdAt));

          title = 'ALL TENDER SALES';
          columns = [
            'Tender No',
            'Sale Date',
            'SR Number',
            'Goods Name',
            'Qty',
            'Latest Valuation (LKR)',
            'Sold Price (LKR)',
            'Status',
          ];
          rows = [];
          rowItemIds = [];
          for (final sale in tenders) {
            final dateStr = sale.saleDate != null
                ? DateFormat('yyyy-MM-dd').format(sale.saleDate!)
                : '—';
            for (final it in sale.dedupedItems) {
              if (_yardArg != null && it.yard != _yardArg) continue;
              final f = it.forfeited;
              final pkgItems =
                  f?.packageDetails?.items ?? const <PackageItem>[];
              final match = f?.itemId == null
                  ? null
                  : pkgItems.where((i) => i.id == f!.itemId).firstOrNull;
              final qty = f?.entryQty ?? match?.quantity ?? 1;
              final unit = f?.valuationCost;
              rows.add([
                sale.saleNumber ?? '—',
                dateStr,
                f?.srNumber ?? '—',
                f?.itemName ?? match?.itemName ?? '—',
                '$qty',
                (unit != null && unit > 0) ? money.format(unit * qty) : '—',
                it.sold ? money.format(it.soldPrice) : '—',
                it.sold ? 'Sold' : 'Unsold',
              ]);
              rowItemIds.add(f?.itemId);
            }
          }
          headline = '${rows.length} goods';
          break;

        case 'tender_day':
          // The sheet the DG carries INTO a tender sale: exactly the goods
          // showing on Top Management's own Tender Sales page at that moment,
          // so the print and the screen cannot disagree.
          //
          // That page's rule -- unsold items remaining AND the window still
          // open -- is applied here too, which is why this report empties
          // when the page does and fills again on the next tender.
          final daySales = await disposal.getTenderSales();
          var live = daySales.where((sale) {
            final hasPending = sale.items.any((i) => !i.sold);
            if (!hasPending) return false;
            final windowClosed = sale.unsoldDeadline != null &&
                DateTime.now().isAfter(sale.unsoldDeadline!);
            return !windowClosed;
          }).toList();
          if (_yardArg != null) {
            live = live
                .where((sale) => sale.items.any((i) => i.yard == _yardArg))
                .toList();
          }
          live.sort((a, b) => (b.saleDate ?? b.createdAt)
              .compareTo(a.saleDate ?? a.createdAt));

          title = 'TENDER SALE — GOODS & VALUATIONS';
          columns = [
            'Tender No',
            'SR Number',
            'Goods Name',
            'Goods Description',
            'Qty',
            'Yard / Warehouse',
            'Latest Valuation (LKR)',
          ];
          rows = [];
          rowItemIds = [];
          for (final sale in live) {
            for (final it in sale.dedupedItems) {
              // Only the items still going under the hammer: one already
              // marked sold has left the sale, and the screen does not list
              // it either.
              if (it.sold) continue;
              if (_yardArg != null && it.yard != _yardArg) continue;
              final f = it.forfeited;
              final pkg = f?.packageDetails;
              final pkgItems = pkg?.items ?? const <PackageItem>[];
              final match = f?.itemId == null
                  ? null
                  : pkgItems.where((i) => i.id == f!.itemId).firstOrNull;
              final qty = f?.entryQty ?? match?.quantity ?? 1;
              final unit = f?.valuationCost;
              final desc = match?.goodsDescription?.trim();

              // Where the goods physically are, so they can be pulled for the
              // sale: the newest warehouse entry for this item.
              String location = '—';
              if (pkg != null && f?.itemId != null) {
                final entries = pkg.warehouseEntries
                    .where((e) => e.packageItemId == f!.itemId)
                    .toList()
                  ..sort((a, b) => b.admittedAt.compareTo(a.admittedAt));
                if (entries.isNotEmpty) {
                  final w = entries.first;
                  final zone = (w.zone?.isNotEmpty == true) ? ' · ${w.zone}' : '';
                  location = '${yardName(it.yard)} / ${w.warehouseName}$zone';
                }
              }
              if (location == '—') location = yardName(it.yard);

              rows.add([
                sale.saleNumber ?? '—',
                f?.srNumber ?? '—',
                f?.itemName ?? match?.itemName ?? '—',
                (desc?.isNotEmpty == true) ? desc! : '—',
                '$qty',
                location,
                (unit != null && unit > 0) ? money.format(unit * qty) : '—',
              ]);
              rowItemIds.add(f?.itemId);
            }
          }
          headline = '${rows.length} goods';
          break;

        case 'destroyed':
          // Destruction is no longer a tender: there is no buyer, so no
          // valuation is realised and no "destroyed price" exists. What the
          // report has to answer is what the destruction COST and what is
          // left of the deposit -- the same figures the Destroyed Goods pages
          // and the expense form show, read from the same provider so the
          // three can never disagree.
          final financials = await ref.read(srFinancialsProvider.future);
          final bySr = {
            for (final f in financials) f.srNumber.trim(): f,
          };

          // Every item currently marked destroyed OR pending destruction,
          // taken from the packages themselves rather than the old
          // destruction-tender tables.
          final destroyedRows = <({PackageModel pkg, PackageItem item})>[];
          for (final p in packages) {
            for (final i in p.items ?? const <PackageItem>[]) {
              final st = (i.status ?? '').toLowerCase();
              if (st == 'destroyed' ||
                  st == 'supposed to be destroyed' ||
                  st == 'destroy') {
                if (!inPeriod(p.updatedAt)) continue;
                destroyedRows.add((pkg: p, item: i));
              }
            }
          }

          title = 'DESTROYED GOODS';
          columns = [
            'SR Number',
            'Goods Name',
            'Goods Description',
            'Destroying Deposit (LKR)',
            'Total Costs (LKR)',
            'Refund (LKR)',
          ];
          rows = [];
          rowItemIds = [];

          for (final r in destroyedRows) {
            final fin = bySr[r.pkg.srNumber.trim()];
            final deposit = fin?.destroyingDeposit ?? 0;
            final spent = fin?.depositSpent ?? 0;
            // A shortfall is shown as a negative refund rather than hidden:
            // costs CAN exceed the deposit, and the report must say so.
            final refund = deposit - spent;
            final desc = r.item.goodsDescription?.trim();
            rows.add([
              r.pkg.srNumber,
              r.item.itemName,
              (desc?.isNotEmpty == true) ? desc! : '—',
              deposit > 0 ? money.format(deposit) : '—',
              spent > 0 ? money.format(spent) : '—',
              (deposit > 0 || spent > 0) ? money.format(refund) : '—',
            ]);
            rowItemIds.add(r.item.id);
          }

          headline = '${rows.length} goods';
          break;

        case 'reconciliation':
          // Initial stock
          final initialPkgs = packages
              .where((p) =>
                  start == null ||
                  (p.entryDate != null && !p.entryDate!.isAfter(start)))
              .toList();
          final initialData = await _goodsData(initialPkgs);
          final initialCnt = initialData.$2.length;
          double initialVal = 0;
          for (final r in initialData.$2) {
            final vStr = r[9].replaceAll(',', '').replaceAll('LKR', '').trim();
            initialVal += double.tryParse(vStr) ?? 0;
          }

          // Added goods
          final addedPkgs =
              packages.where((p) => inPeriod(p.entryDate)).toList();
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
                if (it.sold &&
                    inPeriod(it.soldAt) &&
                    (_yardArg == null || it.yard == _yardArg))
                  it
          ];
          double soldVal = 0;
          for (final it in soldItems) {
            double tax = 0;
            for (final t in it.appliedTaxes) {
              tax += (t is Map ? parseDbNum(t['amount']) : 0) ?? 0;
            }
            soldVal += it.soldPrice + tax;
          }
          final soldCnt = soldItems.length;

          // Destroyed goods
          final destructions = await disposal.getDestructions();
          final destroyedItems = [
            for (final dn in destructions)
              for (final it in dn.items)
                if (it.destroyed &&
                    inPeriod(it.destroyedAt) &&
                    (_yardArg == null || it.yard == _yardArg))
                  it
          ];
          final destCnt = destroyedItems.length;

          final balCnt = subCnt - soldCnt - destCnt;

          title = 'EXECUTIVE STOCK & REVENUE RECONCILIATION';
          headline =
              'Initial: $initialCnt (LKR ${money.format(initialVal)}) + Added: $addedCnt (LKR ${money.format(addedVal)}) = Subtotal: $subCnt\n'
              '− Sold: $soldCnt (Value of Goods Sold: LKR ${money.format(soldVal)}) − Destroyed: $destCnt = Net Balance: $balCnt goods';

          columns = [
            'SR Number',
            'Goods Name',
            'HS Code',
            'Qty',
            'Consignee',
            'Status / Movement',
            'Date',
            'Value (LKR)'
          ];
          rows = [];
          rowItemIds = [];
          for (var idx = 0; idx < addedData.$2.length; idx++) {
            final r = addedData.$2[idx];
            rows.add([r[0], r[1], r[2], r[3], r[4], 'ADDED', r[10], r[9]]);
            rowItemIds.add(addedData.$3[idx]);
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
            rowItemIds.add(f?.itemId);
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
            rowItemIds.add(f?.itemId);
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
          rowItemIds: rowItemIds,
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
                marginLeft: 20,
                marginRight: 20,
                marginTop: 20,
                marginBottom: 20),
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
              fileName:
                  '${title.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx',
              onExport: () => ReportService().exportTableToExcel(
                title: title,
                subTitle: periodLabel,
                columns: columns,
                rows: rows,
              ),
              onSave: (bytes) =>
                  _handleFileSave(bytes, title.replaceAll(' ', '_'), 'xlsx'),
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

  List<ForfeitedPackageModel> _filterByWarehouseForfeited(
      List<ForfeitedPackageModel> list) {
    if (_selectedWarehouse == 'all') return list;
    return list.where((f) {
      final entries = f.packageDetails?.warehouseEntries ?? const [];
      if (entries.isEmpty) return false;
      return entries.any((e) =>
          e.warehouseId == _selectedWarehouse ||
          e.warehouseCode == _selectedWarehouse);
    }).toList();
  }

  // ── Disposal Lifecycle Reports (yard pages) ──────────────────────────────

  /// Forfeited Packages page report (all genuine forfeits in this yard).
  Future<void> _generateForfeitedReport(String format) async {
    await _emitForfeitedReport(
      key: 'Forfeited Goods',
      title: 'FORFEITED GOODS',
      fileBase: 'Forfeited_Goods',
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
      key: 'Re-exported Goods',
      title: 'RE-EXPORTED GOODS',
      fileBase: 'Reexported_Goods',
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
      final reportData = ReportService()
          .buildForfeitedReportRows(list, dateHeader: dateHeader);
      final columns = reportData.$1;
      final rows = reportData.$2;
      final itemIds = reportData.$3;

      if (format == 'view') {
        await _showReportTable(
          title: title,
          columns: columns,
          rows: rows,
          rowItemIds: itemIds,
          onSavePdf: () => _showPdfPreview(
              (_) => ReportService().generateForfeitedPdf(list,
                  title: title, subTitle: dateRange, dateHeader: dateHeader),
              '${fileBase}_Report.pdf'),
          onExportExcel: () {
            if (!mounted) return;
            showDialog(
              context: context,
              builder: (ctx) => ExcelExportDialog(
                title: 'Export $key',
                recordCount: rows.length,
                fileName: '${fileBase}_Report.xlsx',
                onExport: () => ReportService().exportForfeitedToExcel(list,
                    title: title, dateHeader: dateHeader),
                onSave: (bytes) => _handleFileSave(bytes, fileBase, 'xlsx'),
              ),
            );
          },
        );
      } else if (format == 'pdf') {
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
            recordCount: rows.length,
            fileName: '${fileBase}_Report.xlsx',
            onExport: () => ReportService().exportForfeitedToExcel(list,
                title: title, dateHeader: dateHeader),
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
      all =
          await ref.read(packageServiceProvider).getAllPackages(yard: _yardArg);
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
        onSave: (bytes, name) =>
            _handleFileSave(bytes, name.replaceAll('.pdf', ''), 'pdf'),
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
            )
                .animate(
                    onPlay: (controller) => controller.repeat(reverse: true))
                .shimmer(
                    delay: 2.seconds,
                    duration: 1500.ms,
                    color: color.withOpacity(0.3)),
            const Gap(6),
            Text(label,
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500)),
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
              if (onPdf != null)
                Expanded(
                  child: _buildActionButton(
                    // Opens the preview, where the report is READ and printed.
                    // Saving a PDF is not offered — anything leaving the system
                    // does so on paper, or as Excel.
                    label: 'Print',
                    icon: Icons.print_rounded,
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          )
        : ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 32),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          );

    final child = isLoading
        ? const SizedBox(
            width: 14,
            height: 14,
            child:
                CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14),
              const Gap(4),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          );

    return isOutline
        ? OutlinedButton(
            onPressed: isLoading ? null : onTap, style: style, child: child)
        : ElevatedButton(
            onPressed: isLoading ? null : onTap, style: style, child: child);
  }

  Widget _buildSummaryCard(
      String title, IconData icon, Color color, String period) {
    return _buildReportCard(
      title: title,
      description: 'Package movement by $period.',
      icon: icon,
      color: color,
      onPdf: () => _generateSummaryReport(period, 'pdf'),
      onExcel: () => _generateSummaryReport(period, 'excel'),
    );
  }

  Future<void> _handleFileSave(
      Uint8List? bytes, String defaultName, String extension) async {
    if (bytes == null) return;

    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Report',
      fileName:
          '${defaultName}_${DateFormat('yyyyMMdd').format(DateTime.now())}.$extension',
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
      _showSuccess(
          'Report saved successfully to ${path.split(Platform.pathSeparator).last}');
    }
  }

  Future<void> _generateWarehouseStockPdf() async {
    const key = 'Warehouse Stock_pdf';
    _setLoading(key, true);
    try {
      final entries = await ref
          .read(warehouseServiceProvider)
          .getAllWarehouseEntries(isReturned: false, yard: _yardArg);
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
      final entries = await ref
          .read(warehouseServiceProvider)
          .getAllWarehouseEntries(isReturned: false, yard: _yardArg);
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
              onExport: () => ReportService()
                  .exportWarehouseToExcel(filtered, isReturned: false),
              onSave: (bytes) =>
                  _handleFileSave(bytes, 'Warehouse_Status', 'xlsx'),
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
      final entries = await ref
          .read(warehouseServiceProvider)
          .getAllWarehouseEntries(isReturned: true, yard: _yardArg);
      final filtered = _filterByDate(entries);
      if (filtered.isEmpty) {
        _showNoDataMessage();
        return;
      }
      _showPdfPreview(
        (format) => ReportService().generateWarehousePdf(
          filtered,
          title: 'Released Goods Report',
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
      final entries = await ref
          .read(warehouseServiceProvider)
          .getAllWarehouseEntries(isReturned: true, yard: _yardArg);
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
              onExport: () => ReportService()
                  .exportWarehouseToExcel(filtered, isReturned: true),
              onSave: (bytes) =>
                  _handleFileSave(bytes, 'Released_Packages', 'xlsx'),
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
          .where(
              (p) => p.oldSrNumber != null && p.oldSrNumber!.trim().isNotEmpty)
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
      final rows = oldEntries
          .map((p) => [
                p.oldSrNumber ?? '—',
                p.srNumber,
                (p.cusdecNo?.isNotEmpty == true) ? p.cusdecNo! : '—',
                (p.cusdecDate?.isNotEmpty == true) ? p.cusdecDate! : '—',
                p.entryDate != null ? df.format(p.entryDate!) : '—',
                p.consigneeName,
                _normStatus(p.status),
              ])
          .toList();

      final periodLabel = (_startDate != null && _endDate != null)
          ? '${df.format(_startDate!)} to ${df.format(_endDate!)}'
          : 'All time';

      if (format == 'view') {
        await _showReportTable(
          title: 'Old Entries (Migrated Packages)',
          subtitle: periodLabel,
          columns: columns,
          rows: rows,
          onSavePdf: () => _showPdfPreview(
            (fmt) => ReportService().generateStockRevenuePdf(
              title: 'OLD ENTRIES (MIGRATED PACKAGES)',
              periodLabel: periodLabel,
              headline: '${rows.length} migrated packages',
              columns: columns,
              rows: rows,
              format: fmt,
            ),
            'Old_Entries_Report.pdf',
          ),
          onExportExcel: () {
            if (!mounted) return;
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
          },
        );
      } else if (format == 'pdf') {
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
              onSave: (bytes) => _handleFileSave(bytes, 'Old_Entries', 'xlsx'),
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
    final title =
        '${periodType.toUpperCase()[0]}${periodType.substring(1)} Summary';
    final key = '${title}_$format';
    _setLoading(key, true);
    try {
      final admitted = await ref
          .read(warehouseServiceProvider)
          .getAllWarehouseEntries(yard: _yardArg);
      final filtered = _filterByDate(admitted);

      if (filtered.isEmpty) {
        _showNoDataMessage();
        return;
      }

      final summary = _calculateSummary(filtered, periodType);
      final reportTitle = '$title Package Summary Report';
      final periodLabel = periodType == 'day'
          ? 'Date'
          : (periodType == 'week' ? 'Week Reference' : 'Month');

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
              onExport: () =>
                  ReportService().exportSummaryToExcel(summary, periodLabel),
              onSave: (bytes) => _handleFileSave(
                  bytes, reportTitle.replaceAll(' ', '_'), 'xlsx'),
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
    'forfeit',
    'abandoned',
    're-export',
    'destroy',
    'sold',
    'other'
  ];

  String _periodKey(DateTime d, String periodType) {
    if (periodType == 'day') return DateFormat('yyyy-MM-dd').format(d);
    if (periodType == 'week')
      return 'Year ${d.year} - Week ${(d.day / 7).ceil()}';
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

  List<Map<String, dynamic>> _calculateSummary(
      List<WarehouseEntryModel> entries, String periodType) {
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
    return sortedKeys
        .map((k) => {
              'period': k,
              'admitted': groups[k]!['admitted'],
              'returned': groups[k]!['returned'],
              for (final c in _summaryDispoCols) c: groups[k]![c],
            })
        .toList();
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
      // Status is resolved per ITEM inside _goodsData (see _generateAllPackagesPdf).
      final packages =
          await ref.read(packageServiceProvider).getAllPackages(yard: _yardArg);

      final withDate = _filterByDate(packages);
      final filtered = _filterByWarehouse(withDate);

      if (filtered.isEmpty) {
        _showNoDataMessage();
      } else {
        final statusName =
            _selectedStatus == 'all' ? 'ALL' : _selectedStatus.toUpperCase();

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
          final data =
              await _goodsData(filtered, statusFilter: _selectedStatus);
          if (data.$2.isEmpty) {
            _showNoDataMessage();
            return;
          }

          showDialog(
            context: context,
            builder: (ctx) => ExcelExportDialog(
              title: 'Export $statusName$whSuffix Inventory Audit',
              recordCount: data.$2.length,
              fileName:
                  '${statusName}${whSuffix.replaceAll(' ', '_')}_Inventory_Audit.xlsx',
              onExport: () => ReportService().exportTableToExcel(
                title: '$statusName PACKAGES INVENTORY AUDIT$whSuffix',
                subTitle: dateRangeStr,
                columns: data.$1,
                rows: data.$2,
              ),
              onSave: (bytes) => _handleFileSave(
                  bytes,
                  '${statusName}${whSuffix.replaceAll(' ', '_')}_Inventory_Audit',
                  'xlsx'),
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

  Future<void> _generatePostStatusActivitiesPdf() async {
    const key = 'Post Status Activity_pdf';
    _setLoading(key, true);
    try {
      final rows = _postStatusActivityRows();
      if (rows.isEmpty) {
        _showNoDataMessage();
        return;
      }
      _showPdfPreview(
        (format) => ReportService().generatePostStatusActivitiesPdf(rows),
        'Post_Status_Activity_Audit.pdf',
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      _setLoading(key, false);
    }
  }

  Future<void> _exportPostStatusActivitiesExcel() async {
    const key = 'Post Status Activity_excel';
    _setLoading(key, true);
    try {
      final rows = _postStatusActivityRows();
      if (rows.isEmpty) {
        _showNoDataMessage();
        return;
      }

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => ExcelExportDialog(
            title: 'Export Post Status Activities',
            recordCount: rows.length,
            fileName: 'Post_Status_Activity_Audit.xlsx',
            onExport: () =>
                ReportService().exportPostStatusActivitiesToExcel(rows),
            onSave: (bytes) =>
                _handleFileSave(bytes, 'Post_Status_Activity_Audit', 'xlsx'),
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
      final cats =
          await ref.read(packageCategoryServiceProvider).getCategories();
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
      final cats =
          await ref.read(packageCategoryServiceProvider).getCategories();
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
            onSave: (bytes) =>
                _handleFileSave(bytes, 'Item_Categories_Audit', 'xlsx'),
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
      final warehouses =
          await ref.read(warehouseServiceProvider).getWarehouses();
      final stats =
          await ref.read(warehouseServiceProvider).getWarehouseStats();
      if (warehouses.isEmpty) {
        _showNoDataMessage();
      } else {
        _showPdfPreview(
          (format) =>
              ReportService().generateWarehousesListPdf(warehouses, stats),
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
      final warehouses =
          await ref.read(warehouseServiceProvider).getWarehouses();
      final stats =
          await ref.read(warehouseServiceProvider).getWarehouseStats();
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
              onExport: () => ReportService()
                  .exportWarehousesListToExcel(warehouses, stats),
              onSave: (bytes) =>
                  _handleFileSave(bytes, 'Warehouses_List_Audit', 'xlsx'),
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
      final entries = await ref
          .read(warehouseServiceProvider)
          .getAllWarehouseEntries(yard: _yardArg);
      final filteredEntries = _filterByDate(entries);
      if (filteredEntries.isEmpty) {
        _showNoDataMessage();
      } else {
        final packages = await ref
            .read(packageServiceProvider)
            .getAllPackages(yard: _yardArg);
        final rates = await ref.read(storageRateProvider.future);
        _showPdfPreview(
          (format) => ReportService().generateFinancialPdf(
              filteredEntries, packages, rates,
              isRevenue: false),
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
      final entries = await ref
          .read(warehouseServiceProvider)
          .getAllWarehouseEntries(yard: _yardArg);
      final filteredEntries = _filterByDate(entries);
      if (filteredEntries.isEmpty) {
        _showNoDataMessage();
      } else {
        final packages = await ref
            .read(packageServiceProvider)
            .getAllPackages(yard: _yardArg);
        final rates = await ref.read(storageRateProvider.future);
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => ExcelExportDialog(
              title: 'Export Storage Charges',
              recordCount: filteredEntries.length,
              fileName: 'Storage_Charges_Report.xlsx',
              onExport: () => ReportService().exportFinancialToExcel(
                  filteredEntries, packages, rates,
                  isRevenue: false),
              onSave: (bytes) =>
                  _handleFileSave(bytes, 'Storage_Charges_Report', 'xlsx'),
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
      final entries = await ref
          .read(warehouseServiceProvider)
          .getAllWarehouseEntries(isReturned: true, yard: _yardArg);
      final filteredEntries = _filterByDate(entries);
      if (filteredEntries.isEmpty) {
        _showNoDataMessage();
      } else {
        final packages = await ref
            .read(packageServiceProvider)
            .getAllPackages(yard: _yardArg);
        final rates = await ref.read(storageRateProvider.future);
        _showPdfPreview(
          (format) => ReportService().generateFinancialPdf(
              filteredEntries, packages, rates,
              isRevenue: true),
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
      final entries = await ref
          .read(warehouseServiceProvider)
          .getAllWarehouseEntries(isReturned: true, yard: _yardArg);
      final filteredEntries = _filterByDate(entries);
      if (filteredEntries.isEmpty) {
        _showNoDataMessage();
      } else {
        final packages = await ref
            .read(packageServiceProvider)
            .getAllPackages(yard: _yardArg);
        final rates = await ref.read(storageRateProvider.future);
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => ExcelExportDialog(
              title: 'Export Released Revenue',
              recordCount: filteredEntries.length,
              fileName: 'Released_Revenue_Report.xlsx',
              onExport: () => ReportService().exportFinancialToExcel(
                  filteredEntries, packages, rates,
                  isRevenue: true),
              onSave: (bytes) =>
                  _handleFileSave(bytes, 'Released_Revenue_Report', 'xlsx'),
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
        final start =
            DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
        if (dt.isBefore(start)) return false;
      }

      // End date normalization (end of day)
      if (_endDate != null) {
        final end = DateTime(
            _endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
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

  Future<void> _exportSummaryExcel(String reportTitle, String periodLabel,
      List<Map<String, dynamic>> summary) async {
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
            onExport: () =>
                ReportService().exportSummaryToExcel(summary, periodLabel),
            onSave: (bytes) => _handleFileSave(
                bytes, fileName.replaceAll('.xlsx', ''), 'xlsx'),
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
            onSave: (bytes) => _handleFileSave(
                bytes, fileName.replaceAll('.xlsx', ''), 'xlsx'),
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
    // Amber, not the default white/grey: an empty result is the one message
    // the reader MUST notice, and the default washed straight into the page.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: context.colors.warningAmber,
        content: Row(children: [
          const Icon(Icons.info_outline_rounded,
              color: Colors.black87, size: 18),
          const Gap(10),
          const Expanded(
            child: Text('No data found for the selected filters.',
                style: TextStyle(
                    color: Colors.black87, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Error: $msg'),
          backgroundColor: context.colors.dangerRed),
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

  /// The width a page opens at.
  ///
  /// A landscape page is 1.414x wider than a portrait one, so at 880 it filled
  /// far more of the dialog and read as roughly 125% while the label said
  /// 100%. Opening it at the SAME width as portrait means the whole sheet is
  /// visible at a comparable scale, and the reader zooms in from there.
  double get _defaultWidth => 680.0;
  late double _pageWidth;

  static const double _kMinPageWidth = 400;
  static const double _kMaxPageWidth = 3000;

  /// One press of + or -. Multiplicative, so each step feels the same size at
  /// any zoom level.
  static const double _kZoomStep = 1.25;

  void _zoomBy(double factor) => setState(() =>
      _pageWidth = (_pageWidth * factor).clamp(_kMinPageWidth, _kMaxPageWidth));

  void _resetZoom() => setState(() => _pageWidth = _defaultWidth);

  @override
  void initState() {
    super.initState();
    // Landscape for the reports whose tables are genuinely wide; portrait for
    // everything else. Matched on the FILE NAME, which is the only thing this
    // dialog knows about the report it is showing.
    //
    // 'register' / 'inventory' were in this list but their reports are six
    // narrow columns — they belong in portrait, and forcing landscape left a
    // half-empty sheet.
    final f = widget.fileName.toLowerCase();
    _isLandscape = f.contains('warehouse') ||
        f.contains('released') ||
        f.contains('financials') ||
        f.contains('valued') ||
        f.contains('valuation');
    _pageWidth = _defaultWidth;
    _generatePdf();
  }

  Future<void> _generatePdf() async {
    setState(() => _isLoading = true);
    try {
      final format =
          _isLandscape ? _baseFormat.landscape : _baseFormat.portrait;
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
    setState(() {
      _isLandscape = !_isLandscape;
      _pageWidth = _defaultWidth;
    });
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
      )
          .animate()
          .fadeIn(duration: 400.ms)
          .scale(begin: const Offset(0.95, 0.95), curve: Curves.easeOutBack),
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
              // The Customs emblem, tinted to the header accent. MUST use
              // SvgTheme(currentColor:) — a colorFilter srcIn flattens the
              // eye/ship detail into a solid blob.
              SvgPicture.asset('Sri_Lanka_Customs_logo_tinted.svg',
                  width: 26,
                  height: 26,
                  theme: SvgTheme(currentColor: context.colors.primaryGold)),
              const Gap(12),
              Text('Report Preview',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: context.colors.textPrimary)),
            ],
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            _zoomButton(
              context,
              icon: Icons.remove_rounded,
              tooltip: 'Zoom out',
              onPressed: _pageWidth <= _kMinPageWidth
                  ? null
                  : () => _zoomBy(1 / _kZoomStep),
            ),
            // Tap the percentage to snap back to the default fit.
            Tooltip(
              message: 'Reset zoom',
              child: TextButton(
                onPressed:
                    (_pageWidth - _defaultWidth).abs() < 1 ? null : _resetZoom,
                child: SizedBox(
                  width: 52,
                  child: Text(
                    '${(_pageWidth / _defaultWidth * 100).round()}%',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
            _zoomButton(
              context,
              icon: Icons.add_rounded,
              tooltip: 'Zoom in',
              onPressed: _pageWidth >= _kMaxPageWidth
                  ? null
                  : () => _zoomBy(_kZoomStep),
            ),
            const Gap(8),
            IconButton(
              icon: Icon(Icons.close, color: context.colors.textSecondary),
              onPressed: () => Navigator.pop(context),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _zoomButton(BuildContext context,
      {required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed}) {
    return IconButton(
      tooltip: tooltip,
      iconSize: 20,
      icon: Icon(icon,
          color: onPressed == null
              ? context.colors.textMuted
              : context.colors.primaryGold),
      onPressed: onPressed,
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return Center(
          child: CircularProgressIndicator(color: context.colors.primaryGold));
    }
    if (_pdfBytes == null) return const SizedBox();

    // Zoomed past the dialog's width, the page has to be pannable sideways —
    // PdfPreview only scrolls vertically, so it is wrapped in a horizontal
    // scroller and given exactly the width it was asked to draw at.
    return LayoutBuilder(builder: (context, c) {
      final preview = PdfPreview(
        // The key forces a re-layout when the zoom changes; without it the
        // preview keeps the page bitmap it already rasterised.
        key: ValueKey(_pageWidth),
        build: (format) => _pdfBytes!,
        useActions: false,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        maxPageWidth: _pageWidth,
        pdfFileName: widget.fileName,
        loadingWidget: Center(
            child:
                CircularProgressIndicator(color: context.colors.primaryGold)),
        previewPageMargin: const EdgeInsets.all(20),
      );

      // Below the dialog's width there is nothing to pan; let it fill.
      final needed = _pageWidth + 40; // + previewPageMargin
      if (needed <= c.maxWidth) return preview;

      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: needed, child: preview),
      );
    });
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
          Text('(Standard A4 Format)',
              style: TextStyle(color: context.colors.textMuted, fontSize: 10)),
          const Spacer(),
          // Actions
          _buildActionItem(context, Icons.print_rounded, 'Send to Printer',
              context.colors.primaryGold, () {
            if (_pdfBytes != null) {
              Printing.layoutPdf(
                onLayout: (f) => _pdfBytes!,
                name: widget.fileName,
                // Setting dynamicLayout to false ensures it follows our generated bytes strictly
                dynamicLayout: false,
              );
            }
          }),
          // Saving the PDF is deliberately not offered: the preview is for
          // READING the report on screen, and anything leaving the system does
          // so on paper. Print, or export to Excel from the card.
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
          color: isSelected
              ? context.colors.primaryGold.withOpacity(0.15)
              : Colors.transparent,
          border: Border.all(
              color: isSelected
                  ? context.colors.primaryGold
                  : context.colors.borderColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(
              color: isSelected
                  ? context.colors.primaryGold
                  : context.colors.textSecondary,
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
            Icon(
                _isLandscape ? Icons.landscape_rounded : Icons.portrait_rounded,
                size: 16,
                color: context.colors.textPrimary),
            const Gap(6),
            Text(_isLandscape ? 'Landscape' : 'Portrait',
                style:
                    TextStyle(color: context.colors.textPrimary, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildActionItem(BuildContext context, IconData icon, String label,
      Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const Gap(2),
          Text(label,
              style:
                  TextStyle(color: context.colors.textPrimary, fontSize: 10)),
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
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.table_view_rounded, color: Colors.green, size: 48)
                .animate()
                .scale(delay: 100.ms, curve: Curves.elasticOut),
            const Gap(16),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Gap(8),
            Text('Excel Data Export',
                style: TextStyle(color: context.colors.textSecondary)),
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
                    child: Text('Cancel',
                        style: TextStyle(color: context.colors.textSecondary)),
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
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Export Now',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
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
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
        ),
        const Gap(16),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
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
            final items =
                p.items.map((i) => i.itemName).join(' ').toLowerCase();
            return p.srNumber.toLowerCase().contains(q) ||
                p.consigneeName.toLowerCase().contains(q) ||
                items.contains(q);
          }).toList();
    final allShownSelected =
        filtered.isNotEmpty && filtered.every((p) => _selected.contains(p.id));

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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
                      const Text('Select Goods',
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
                          border: Border.all(color: context.colors.borderColor),
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
                                      : () => setState(() => _selected
                                          .addAll(filtered.map((p) => p.id))),
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
                                      : () => setState(() => _selected.clear()),
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
                                              color: context.colors.textMuted)),
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
                                          isSelected: _selected.contains(p.id),
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
