import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import '../models/models.dart';
import 'package:intl/intl.dart';

class ReportService {
  static final ReportService _instance = ReportService._internal();
  factory ReportService() => _instance;
  ReportService._internal();

  pw.Font? _font;
  pw.Font? _fontBold;

  /// The Customs emblem, as raw SVG. Loaded once and reused — every report
  /// header draws it, and re-reading the asset per page would be wasteful.
  ///
  /// Null when the asset cannot be read; the header then falls back to the
  /// "SLC" monogram rather than failing to render at all.
  static String? _logoSvg;

  static Future<void> _loadLogo() async {
    if (_logoSvg != null && _logoSvg!.isNotEmpty) return;
    try {
      final raw =
          await rootBundle.loadString('Sri_Lanka_Customs_logo_tinted.svg');
      _logoSvg = raw.replaceAll('currentColor', '#0D47A1');
      return;
    } catch (e) {
      debugPrint('report logo: tinted SVG unavailable ($e), trying plain');
    }
    try {
      final raw = await rootBundle.loadString('Sri_Lanka_Customs_logo.svg');
      _logoSvg = raw;
    } catch (e) {
      // Falling back to the lettered "SLC" monogram. Logged, because an
      // emblem silently missing from every report reads as a design choice
      // rather than a failed asset load.
      debugPrint('report logo: no SVG could be loaded ($e), using SLC');
      _logoSvg = null;
    }
  }

  /// The emblem for a report header, or the lettered fallback.
  static pw.Widget _logoWidget({double size = 46}) {
    final svg = _logoSvg;
    if (svg != null && svg.isNotEmpty) {
      return pw.SizedBox(
        width: size,
        height: size,
        child: pw.SvgImage(svg: svg),
      );
    }
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColor.fromInt(0xFF0D47A1), width: 2),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(
        'SLC',
        style: pw.TextStyle(
          fontSize: 18,
          fontWeight: pw.FontWeight.bold,
          color: PdfColor.fromInt(0xFF0D47A1),
        ),
      ),
    );
  }

  pw.Font? _fontSinhala;

  Future<void> _ensureFontsLoaded() async {
    // The emblem rides along with the fonts: every report needs both, and this
    // runs before each one is built.
    await _loadLogo();
    if (_font != null && _fontBold != null && _fontSinhala != null) return;
    _font = await PdfGoogleFonts.notoSansRegular();
    _fontBold = await PdfGoogleFonts.notoSansBold();
    _fontSinhala = await PdfGoogleFonts.notoSansSinhalaRegular();
  }

  // ── Item-identity helpers (every report shows the item name + HS code so a
  //    package is easy to identify, not just the SR number) ──────────────────

  /// A readable item label for a list of package items: the single item's name,
  /// or "<first> +N" for several, or '—' when none.
  static String itemLabel(List<PackageItem> items) {
    if (items.isEmpty) return '—';
    if (items.length == 1) return items.first.itemName;
    return '${items.first.itemName} +${items.length - 1}';
  }

  /// A readable HS-code label: the single code, 'Multiple' when they differ,
  /// or '—' when none recorded.
  static String hsLabel(List<PackageItem> items) {
    final codes = items
        .map((i) => i.hsCode?.trim())
        .where((c) => c != null && c.isNotEmpty)
        .toSet();
    if (codes.isEmpty) return '—';
    if (codes.length == 1) return codes.first!;
    return 'Multiple';
  }

  /// Warehouse label(s) a forfeited package is/was held in — distinct warehouse
  /// codes from its (joined) warehouse entries. '—' when none recorded.
  /// When [itemId] is passed, returns warehouse codes specifically for that item.
  static String warehouseLabel(ForfeitedPackageModel f, [String? itemId]) {
    final entries = f.packageDetails?.warehouseEntries ?? const [];
    if (itemId != null) {
      final itemEntries =
          entries.where((e) => e.packageItemId == itemId).toList();
      final codes = itemEntries
          .map((e) => e.warehouseCode.trim())
          .where((c) => c.isNotEmpty)
          .toSet()
          .toList();
      if (codes.isNotEmpty) return codes.join(', ');
    }
    final codes = entries
        .map((e) => e.warehouseCode.trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();
    if (codes.isEmpty) return '—';
    if (codes.length == 1) return codes.first;
    return codes.join(', ');
  }

  /// Reason helper: resolves the hold reason from forfeited package, item, or parent package.
  static String reasonOf(ForfeitedPackageModel f, PackageItem? match) {
    if (f.reason.trim().isNotEmpty) return f.reason.trim();
    if (match?.reasons?.trim().isNotEmpty == true)
      return match!.reasons!.trim();
    if (f.packageDetails?.reason?.trim().isNotEmpty == true)
      return f.packageDetails!.reason!.trim();
    return '—';
  }

  /// Generates a PDF report for report items with category summary and zone summary
  Future<Uint8List> generateCategoryAndZonePdf(
      List<PackageModel> packages, List<WarehouseEntryModel> entries) async {
    await _ensureFontsLoaded();
    final pdf = pw.Document();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    // Grouping by Category (total item quantity per category), sorted desc.
    final categoryCounts = <String, int>{};
    for (var pkg in packages) {
      for (var item in pkg.items) {
        final cat = (item.category?.trim().isNotEmpty == true)
            ? item.category!.trim()
            : 'Uncategorized';
        categoryCounts[cat] = (categoryCounts[cat] ?? 0) + item.quantity;
      }
    }
    final catSorted = categoryCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final catTotal = categoryCounts.values.fold(0, (s, v) => s + v);

    // Grouping by Warehouse + Zone (current/held entries only), sorted desc.
    // Keyed "WH · Zone" so a bare zone like "7" reads with its warehouse.
    final zoneCounts = <String, int>{};
    for (var entry in entries) {
      if (!entry.isReturned) {
        final zone = (entry.zone?.trim().isNotEmpty == true)
            ? entry.zone!.trim()
            : 'No Zone';
        final key = '${entry.warehouseCode} · Zone $zone';
        zoneCounts[key] = (zoneCounts[key] ?? 0) + entry.itemCount;
      }
    }
    final zoneSorted = zoneCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final zoneTotal = zoneCounts.values.fold(0, (s, v) => s + v);

    String pct(int v, int total) =>
        total == 0 ? '0%' : '${(v * 100 / total).toStringAsFixed(1)}%';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader('Category & Zone Summary', dateStr,
              'How held inventory is distributed across item categories and warehouse zones'),
          pw.SizedBox(height: 18),

          // ── Category section ──
          pw.Text('Inventory by Item Category',
              style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromInt(0xFF0D47A1))),
          pw.Text(
              'Total item quantity registered under each category (all items).',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: ['#', 'Category', 'Total Qty', 'Share'],
            data: [
              for (var i = 0; i < catSorted.length; i++)
                [
                  '${i + 1}',
                  catSorted[i].key,
                  NumberFormat('#,##0').format(catSorted[i].value),
                  pct(catSorted[i].value, catTotal),
                ],
              ['', 'TOTAL', NumberFormat('#,##0').format(catTotal), '100%'],
            ],
            headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 9,
                color: PdfColors.white),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0D47A1)),
            rowDecoration: const pw.BoxDecoration(
                border:
                    pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200))),
            columnWidths: {0: const pw.FixedColumnWidth(28)},
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight
            },
          ),

          pw.SizedBox(height: 26),

          // ── Zone section ──
          pw.Text('Active Inventory by Warehouse Zone',
              style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromInt(0xFF0D47A1))),
          pw.Text(
              'Currently held item quantity per warehouse zone (released items excluded).',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: ['#', 'Warehouse · Zone', 'Held Qty', 'Share'],
            data: [
              for (var i = 0; i < zoneSorted.length; i++)
                [
                  '${i + 1}',
                  zoneSorted[i].key,
                  NumberFormat('#,##0').format(zoneSorted[i].value),
                  pct(zoneSorted[i].value, zoneTotal),
                ],
              ['', 'TOTAL', NumberFormat('#,##0').format(zoneTotal), '100%'],
            ],
            headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 9,
                color: PdfColors.white),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0D47A1)),
            rowDecoration: const pw.BoxDecoration(
                border:
                    pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200))),
            columnWidths: {0: const pw.FixedColumnWidth(28)},
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight
            },
          ),

          pw.SizedBox(height: 18),
          _buildFooter(packages.length, label: 'Packages Scanned:'),
        ],
      ),
    );

    return pdf.save();
  }

  /// Exports category and zone data to Excel
  Future<Uint8List?> exportCategoryAndZoneToExcel(
      List<PackageModel> packages, List<WarehouseEntryModel> entries) async {
    var excel = Excel.createExcel();
    excel.delete('Sheet1');

    String pct(int v, int total) =>
        total == 0 ? '0%' : '${(v * 100 / total).toStringAsFixed(1)}%';

    // Category Sheet (sorted desc, with Share % and a TOTAL row).
    Sheet catSheet = excel['Category Summary'];
    catSheet.appendRow([TextCellValue('CATEGORY INVENTORY SUMMARY')]);
    catSheet.appendRow([
      TextCellValue('#'),
      TextCellValue('Item Category'),
      TextCellValue('Total Quantity'),
      TextCellValue('Share')
    ]);

    final categoryCounts = <String, int>{};
    for (var pkg in packages) {
      for (var item in pkg.items) {
        final cat = (item.category?.trim().isNotEmpty == true)
            ? item.category!.trim()
            : 'Uncategorized';
        categoryCounts[cat] = (categoryCounts[cat] ?? 0) + item.quantity;
      }
    }
    final catSorted = categoryCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final catTotal = categoryCounts.values.fold(0, (s, v) => s + v);
    for (var i = 0; i < catSorted.length; i++) {
      catSheet.appendRow([
        IntCellValue(i + 1),
        TextCellValue(catSorted[i].key),
        IntCellValue(catSorted[i].value),
        TextCellValue(pct(catSorted[i].value, catTotal)),
      ]);
    }
    catSheet.appendRow([
      TextCellValue(''),
      TextCellValue('TOTAL'),
      IntCellValue(catTotal),
      TextCellValue('100%')
    ]);

    // Zone Sheet (warehouse · zone, held qty, sorted desc, Share + TOTAL).
    Sheet zoneSheet = excel['Zone Summary'];
    zoneSheet.appendRow([TextCellValue('WAREHOUSE ZONE OCCUPANCY (HELD)')]);
    zoneSheet.appendRow([
      TextCellValue('#'),
      TextCellValue('Warehouse · Zone'),
      TextCellValue('Held Quantity'),
      TextCellValue('Share')
    ]);

    final zoneCounts = <String, int>{};
    for (var entry in entries) {
      if (!entry.isReturned) {
        final zone = (entry.zone?.trim().isNotEmpty == true)
            ? entry.zone!.trim()
            : 'No Zone';
        final key = '${entry.warehouseCode} · Zone $zone';
        zoneCounts[key] = (zoneCounts[key] ?? 0) + entry.itemCount;
      }
    }
    final zoneSorted = zoneCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final zoneTotal = zoneCounts.values.fold(0, (s, v) => s + v);
    for (var i = 0; i < zoneSorted.length; i++) {
      zoneSheet.appendRow([
        IntCellValue(i + 1),
        TextCellValue(zoneSorted[i].key),
        IntCellValue(zoneSorted[i].value),
        TextCellValue(pct(zoneSorted[i].value, zoneTotal)),
      ]);
    }
    zoneSheet.appendRow([
      TextCellValue(''),
      TextCellValue('TOTAL'),
      IntCellValue(zoneTotal),
      TextCellValue('100%')
    ]);

    return Uint8List.fromList(excel.encode()!);
  }

  /// Generates a PDF report for a list of packages
  Future<Uint8List> generatePackagePdf(
    List<PackageModel> packages, {
    String? title,
    String? dateRange,
    PdfPageFormat? format,
  }) async {
    // Loads the fonts AND the Customs emblem; without it this report
    // fell back to the lettered "SLC" monogram.
    await _ensureFontsLoaded();
    final pdf = pw.Document();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format ?? PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader(
              title ?? 'Package Inventory Audit', dateStr, dateRange ?? ''),
          pw.SizedBox(height: 20),
          _buildPackageTable(packages),
          pw.SizedBox(height: 20),
          _buildFooter(packages.length),
        ],
      ),
    );

    return pdf.save();
  }

  /// Generates a PDF report for warehouse entries
  Future<Uint8List> generateWarehousePdf(
    List<WarehouseEntryModel> entries, {
    String? title,
    bool isReturnedReport = false,
    PdfPageFormat? format,
  }) async {
    // Loads the fonts AND the Customs emblem; without it this report
    // fell back to the lettered "SLC" monogram.
    await _ensureFontsLoaded();
    final pdf = pw.Document();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format ?? PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader(
              title ??
                  (isReturnedReport
                      ? 'Released Packages Report'
                      : 'Warehouse Status Report'),
              dateStr,
              ''),
          pw.SizedBox(height: 20),
          _buildWarehouseTable(entries, isReturnedReport: isReturnedReport),
          pw.SizedBox(height: 20),
          _buildFooter(entries.length),
        ],
      ),
    );

    return pdf.save();
  }

  /// Full-detail report for ONE package (mirrors the on-screen package-details
  /// popup): SR register, consignee/declarant, items, and warehouse holdings.
  /// Full-detail report for ONE package (mirrors the on-screen package-details
  /// popup): SR register, consignee/declarant, items, and warehouse holdings.
  Future<Uint8List> generateSinglePackagePdf(PackageModel p,
      {PdfPageFormat? format,
      Map<String, ({DateTime? at, String? receipt})>? soldByItem,
      Map<String, DateTime?>? destroyedByItem,
      Map<DateTime, double>? rates}) async {
    await _ensureFontsLoaded();
    final pdf = pw.Document();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    String v(String? s) => (s == null || s.trim().isEmpty) ? 'N/A' : s.trim();
    String d(DateTime? dt) =>
        dt == null ? 'N/A' : DateFormat('yyyy-MM-dd').format(dt);

    String normStatus(String s) {
      final t = s.trim().toLowerCase();
      if (t == 'held' || t == 'pending' || t == 'detained' || t == 'detain') {
        return 'Detain';
      }
      if (t == 'forfeit' || t == 'forfeited' || t == 'forfiet')
        return 'Forfeit';
      if (t == 'abandoned') return 'Abandoned';
      if (t.isEmpty) return 'Detain';
      return '${t[0].toUpperCase()}${t.substring(1)}';
    }

    String receiptOf(String? notes) {
      if (notes == null || notes.trim().isEmpty) return '—';
      for (final part in notes.split('|')) {
        final t = part.trim();
        if (t.toLowerCase().startsWith('receipt no:')) {
          final idx = t.indexOf(':');
          if (idx != -1) {
            final r = t.substring(idx + 1).trim();
            if (r.isNotEmpty) return r;
          }
        }
      }
      return '—';
    }

    // Helper to resolve an item's status, outcome date, receipt, and hold reason
    ({String status, String outDate, String receipt, String reason})
        resolveItemOutcome(PackageItem? it) {
      final iid = it?.id;
      final releasedEntries = p.warehouseEntries.where((e) =>
          e.isReturned &&
          (iid == null || e.packageItemId == null || e.packageItemId == iid));

      String status;
      String outDate = '—';
      String receipt = '—';

      String reason = '—';
      if (it?.reasons?.trim().isNotEmpty == true) {
        reason = it!.reasons!.trim();
      } else if (p.reason?.trim().isNotEmpty == true) {
        reason = p.reason!.trim();
      } else if (p.warehouseEntries.isNotEmpty) {
        reason = p.warehouseEntries.first.holdReason;
      }

      if (iid != null && soldByItem != null && soldByItem.containsKey(iid)) {
        status = 'Sold';
        final s = soldByItem[iid]!;
        outDate = s.at != null ? DateFormat('yyyy-MM-dd').format(s.at!) : '—';
        receipt = (s.receipt?.isNotEmpty == true) ? s.receipt! : '—';
      } else if (iid != null &&
          destroyedByItem != null &&
          destroyedByItem.containsKey(iid)) {
        status = 'Destroyed';
        final dt = destroyedByItem[iid];
        outDate = dt != null ? DateFormat('yyyy-MM-dd').format(dt) : '—';
      } else if (releasedEntries.isNotEmpty) {
        status = 'Released';
        final e = releasedEntries.first;
        outDate = e.returnedAt != null
            ? DateFormat('yyyy-MM-dd').format(e.returnedAt!)
            : '—';
        final r = receiptOf(e.returnNotes);
        if (r != '—') receipt = r;
      } else {
        status =
            normStatus(it?.status.isNotEmpty == true ? it!.status : p.status);
      }

      return (
        status: status,
        outDate: outDate,
        receipt: receipt,
        reason: reason
      );
    }

    // Overall package status for top summary block
    final itemOutcomes = p.items.isEmpty
        ? [resolveItemOutcome(null)]
        : p.items.map((it) => resolveItemOutcome(it)).toList();
    final distinctStatuses = itemOutcomes.map((o) => o.status).toSet().toList();
    final overallStatus = distinctStatuses.length == 1
        ? distinctStatuses.first
        : distinctStatuses.join(' / ');

    // A labelled two-column field grid (like the popup cards).
    pw.Widget section(String title, List<List<String>> fields) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 14),
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title.toUpperCase(),
                style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromInt(0xFF0D47A1))),
            pw.SizedBox(height: 8),
            pw.Wrap(
              spacing: 0,
              runSpacing: 8,
              children: [
                for (final f in fields)
                  pw.Container(
                    width: 250,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(f[0],
                            style: const pw.TextStyle(
                                fontSize: 8, color: PdfColors.grey600)),
                        pw.Text(f[1],
                            style: pw.TextStyle(
                                fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format ?? PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: pw.ThemeData.withFont(base: _font, bold: _fontBold),
        build: (context) => [
          _buildHeader('SR REGISTER ENTRY', dateStr, p.srNumber),
          pw.SizedBox(height: 18),
          section('SR Register Information', [
            ['SR Number', p.srNumber],
            ['Entry Date', d(p.entryDate)],
            if (p.oldSrNumber != null && p.oldSrNumber!.isNotEmpty)
              ['Old SR Number', p.oldSrNumber!],
            ['Cusdec No', v(p.cusdecNo)],
            ['Cusdec Date', v(p.cusdecDate)],
            ['Case Number', v(p.caseNumber)],
            ['Container Number', v(p.containerNumber)],
            ['Package Description', v(p.description)],
          ]),
          section('Consignee / Declarant Information', [
            ['Consignee Name', v(p.consigneeName)],
            ['Consignee NIC', v(p.consigneeNic)],
            ['Consignee Address', v(p.consigneeAddress)],
            ['Consignee Phone', v(p.consigneePhone)],
            ['Declarant Name', v(p.declarantName)],
          ]),
          pw.Text('PACKAGE ITEM SUMMARY',
              style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromInt(0xFF0D47A1))),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: [
              '#',
              'Item',
              'HS Code',
              'Qty',
              'Reason',
              'Status',
              'Outcome Date',
              'Unit Value (LKR)'
            ],
            data: [
              if (p.items.isEmpty)
                [
                  '1',
                  '—',
                  '—',
                  '${p.totalItemCount}',
                  v(p.reason),
                  overallStatus,
                  '—',
                  NumberFormat('#,##0.##').format(p.declaredValue),
                ]
              else
                for (var i = 0; i < p.items.length; i++) ...[
                  (() {
                    final item = p.items[i];
                    final outcome = resolveItemOutcome(item);
                    final qtyStr = '${item.quantity} ${item.unitOfMeasure}';
                    return [
                      '${i + 1}',
                      item.itemName,
                      item.hsCode ?? '—',
                      qtyStr,
                      outcome.reason,
                      outcome.status,
                      outcome.outDate,
                      NumberFormat('#,##0.##').format(item.unitValue),
                    ];
                  })()
                ],
            ],
            headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 8,
                color: PdfColors.white),
            cellStyle: const pw.TextStyle(fontSize: 7.5),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0D47A1)),
            rowDecoration: const pw.BoxDecoration(
                border:
                    pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200))),
            cellAlignments: {
              0: pw.Alignment.center,
              2: pw.Alignment.center,
              3: pw.Alignment.center,
              5: pw.Alignment.center,
              6: pw.Alignment.center,
              7: pw.Alignment.centerRight,
            },
          ),
          pw.SizedBox(height: 16),
          if (p.warehouseEntries.isNotEmpty) ...[
            pw.Text('WAREHOUSE SUMMARY',
                style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromInt(0xFF0D47A1))),
            pw.SizedBox(height: 6),
            (() {
              int getItemIndex(WarehouseEntryModel e) {
                if (e.packageItemId != null) {
                  final idx =
                      p.items.indexWhere((i) => i.id == e.packageItemId);
                  if (idx != -1) return idx;
                }
                if (e.itemName != null && e.itemName!.isNotEmpty) {
                  final idx = p.items.indexWhere((i) =>
                      i.itemName.trim().toLowerCase() ==
                      e.itemName!.trim().toLowerCase());
                  if (idx != -1) return idx;
                }
                return 999;
              }

              final sortedEntries =
                  List<WarehouseEntryModel>.from(p.warehouseEntries)
                    ..sort((a, b) {
                      final idxA = getItemIndex(a);
                      final idxB = getItemIndex(b);
                      if (idxA != idxB) return idxA.compareTo(idxB);
                      return a.admittedAt.compareTo(b.admittedAt);
                    });

              return pw.TableHelper.fromTextArray(
                headers: [
                  '#',
                  'Item',
                  'Warehouse',
                  'Zone',
                  'Qty',
                  'Admitted Date',
                  'Status',
                  'Release Date',
                  'Storage Charge (LKR)',
                  'Receipt No'
                ],
                data: [
                  for (final e in sortedEntries) ...[
                    (() {
                      final itemIdx = getItemIndex(e);
                      final itemNumStr = (itemIdx != 999 && p.items.isNotEmpty)
                          ? '${itemIdx + 1}'
                          : '—';
                      final itemNameStr = (itemIdx != 999 && p.items.isNotEmpty)
                          ? p.items[itemIdx].itemName
                          : (e.itemName ?? '—');
                      final charge = (rates != null)
                          ? e.calculatePackageCharge(p.items, rates)
                          : (e.accumulatedCharge ?? 0.0);
                      final rDate = (e.isReturned && e.returnedAt != null)
                          ? DateFormat('yyyy-MM-dd').format(e.returnedAt!)
                          : '—';
                      final rNo = e.isReturned ? receiptOf(e.returnNotes) : '—';
                      final chargeStr = (e.isReturned || charge > 0)
                          ? NumberFormat('#,##0.00').format(charge)
                          : '—';
                      return [
                        itemNumStr,
                        itemNameStr,
                        e.warehouseName,
                        e.zone ?? '—',
                        '${e.itemCount}',
                        DateFormat('yyyy-MM-dd').format(e.admittedAt),
                        e.isReturned ? 'Released' : 'In Warehouse',
                        rDate,
                        chargeStr,
                        rNo,
                      ];
                    })()
                  ],
                ],
                headerStyle: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 8,
                    color: PdfColors.white),
                cellStyle: const pw.TextStyle(fontSize: 7.5),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0D47A1)),
                rowDecoration: const pw.BoxDecoration(
                    border: pw.Border(
                        bottom: pw.BorderSide(color: PdfColors.grey200))),
                cellAlignments: {
                  0: pw.Alignment.center,
                  1: pw.Alignment.centerLeft,
                  4: pw.Alignment.center,
                  5: pw.Alignment.center,
                  6: pw.Alignment.center,
                  7: pw.Alignment.center,
                  8: pw.Alignment.centerRight,
                  9: pw.Alignment.center,
                },
              );
            })(),
          ],
        ],
      ),
    );
    return pdf.save();
  }

  /// A stock / revenue metric report: a headline count/amount + a supporting
  /// table of the goods (packages) that make up the figure.
  Future<Uint8List> generateStockRevenuePdf({
    required String title,
    required String periodLabel,
    required String headline, // e.g. "42 goods" or "LKR 1,250,000"
    required List<String> columns,
    required List<List<String>> rows,
    PdfPageFormat? format,
  }) async {
    await _ensureFontsLoaded();
    final pdf = pw.Document();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final pageFmt = format ?? PdfPageFormat.a4;
    final isLandscape = pageFmt.width > pageFmt.height;
    final colCount = columns.length;

    final double headerFontSize = isLandscape
        ? (colCount > 12 ? 6.5 : (colCount > 7 ? 7.5 : 8.5))
        : (colCount > 7 ? 6.0 : (colCount > 5 ? 7.0 : 8.0));
    final double cellFontSize = isLandscape
        ? (colCount > 12 ? 6.0 : (colCount > 7 ? 7.0 : 8.0))
        : (colCount > 7 ? 5.5 : (colCount > 5 ? 6.5 : 7.5));
    final double cellPaddingH = (colCount > 7) ? 2.5 : 4.0;
    final double cellPaddingV = (colCount > 7) ? 2.5 : 4.0;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFmt,
        margin: const pw.EdgeInsets.all(24),
        theme: pw.ThemeData.withFont(base: _font, bold: _fontBold),
        build: (context) => [
          _buildHeader(title, dateStr, periodLabel),
          pw.SizedBox(height: 14),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFE3F2FD),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Total',
                    style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey700)),
                pw.SizedBox(height: 2),
                pw.Text(headline,
                    style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        color: const PdfColor.fromInt(0xFF0D47A1))),
              ],
            ),
          ),
          pw.SizedBox(height: 14),
          if (rows.isEmpty)
            pw.Text('No records for this period.',
                style:
                    const pw.TextStyle(fontSize: 10, color: PdfColors.grey600))
          else
            pw.TableHelper.fromTextArray(
              headers: columns,
              data: rows,
              headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: headerFontSize,
                  color: PdfColors.white),
              cellStyle: pw.TextStyle(fontSize: cellFontSize),
              cellPadding: pw.EdgeInsets.symmetric(
                  horizontal: cellPaddingH, vertical: cellPaddingV),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0D47A1)),
              rowDecoration: const pw.BoxDecoration(
                  border: pw.Border(
                      bottom: pw.BorderSide(color: PdfColors.grey200))),
            ),
          pw.SizedBox(height: 14),
          _buildFooter(rows.length, label: 'Goods:'),
        ],
      ),
    );
    return pdf.save();
  }

  /// Generates a summary report PDF
  Future<Uint8List> generateSummaryReportPdf({
    required String title,
    required List<Map<String, dynamic>> summaryData,
    required String periodLabel,
    PdfPageFormat? format,
  }) async {
    await _ensureFontsLoaded();
    final pdf = pw.Document();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    // Disposition breakdown columns (in addition to admit/release/net).
    const dispoCols = [
      'forfeit',
      'abandoned',
      're-export',
      'destroy',
      'sold',
      'other'
    ];
    const dispoHeaders = [
      'Forfeit',
      'Abandoned',
      'Re-export',
      'Destroy',
      'Sold',
      'Other'
    ];

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format ?? PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          _buildHeader(title, dateStr, ''),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headers: [
              periodLabel,
              'Admitted',
              'Released',
              ...dispoHeaders,
              'Net Change'
            ],
            data: summaryData
                .map((d) => [
                      d['period'],
                      d['admitted'].toString(),
                      d['returned'].toString(),
                      for (final c in dispoCols) (d[c] ?? 0).toString(),
                      (d['admitted'] - d['returned']).toString(),
                    ])
                .toList(),
            headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 8,
                color: PdfColors.white),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF0D47A1)), // Customs Blue
            rowDecoration: const pw.BoxDecoration(
                border:
                    pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200))),
            cellAlignment: pw.Alignment.center,
            cellAlignments: {0: pw.Alignment.centerLeft},
          ),
          pw.SizedBox(height: 20),
          _buildFooter(summaryData.length, label: 'Total Periods:'),
        ],
      ),
    );

    return pdf.save();
  }

  /// Exports warehouse data to Excel bytes
  Future<Uint8List?> exportWarehouseToExcel(List<WarehouseEntryModel> entries,
      {bool isReturned = false}) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel[isReturned ? 'Released' : 'In_Warehouse'];
    excel.delete('Sheet1');

    // Add Headers
    List<String> headers = [
      'SR Number',
      'Item',
      'HS Code',
      'Consignee',
      'Warehouse',
      'Admitted At',
      'Reason',
      'Items'
    ];
    if (isReturned) {
      headers.addAll(['Released At', 'Release Notes']);
    }

    sheetObject.appendRow(headers.map((e) => TextCellValue(e)).toList());

    // Style the header row
    var headerRow = sheetObject.row(0);
    var cellStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#E3F2FD'), // Light Blue
    );
    for (var cell in headerRow) {
      if (cell != null) cell.cellStyle = cellStyle;
    }

    // Add Data
    for (var e in entries) {
      List<CellValue> row = [
        TextCellValue(e.srNumber ?? ''),
        TextCellValue(e.itemName ?? ''),
        TextCellValue(
            (e.hsCode?.trim().isNotEmpty == true) ? e.hsCode!.trim() : ''),
        TextCellValue(e.consigneeName ?? ''),
        TextCellValue(e.warehouseCode),
        TextCellValue(DateFormat('yyyy-MM-dd HH:mm').format(e.admittedAt)),
        TextCellValue(e.holdReason),
        IntCellValue(e.itemCount),
      ];
      if (isReturned) {
        row.add(TextCellValue(e.returnedAt != null
            ? DateFormat('yyyy-MM-dd HH:mm').format(e.returnedAt!)
            : ''));
        row.add(TextCellValue(e.returnNotes ?? ''));
      }
      sheetObject.appendRow(row);
    }

    return Uint8List.fromList(excel.encode()!);
  }

  /// Exports summary data to Excel bytes
  Future<Uint8List?> exportSummaryToExcel(
      List<Map<String, dynamic>> summaryData, String periodLabel) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Summary'];
    excel.delete('Sheet1');

    const dispoCols = [
      'forfeit',
      'abandoned',
      're-export',
      'destroy',
      'sold',
      'other'
    ];
    const dispoHeaders = [
      'Forfeit',
      'Abandoned',
      'Re-export',
      'Destroy',
      'Sold',
      'Other'
    ];

    sheetObject.appendRow([
      TextCellValue(periodLabel),
      TextCellValue('Admitted'),
      TextCellValue('Released'),
      ...dispoHeaders.map((h) => TextCellValue(h)),
      TextCellValue('Net Change')
    ]);

    // Style the header row
    var headerRow = sheetObject.row(0);
    var cellStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#E3F2FD'),
    );
    for (var cell in headerRow) {
      if (cell != null) cell.cellStyle = cellStyle;
    }

    for (var d in summaryData) {
      sheetObject.appendRow([
        TextCellValue(d['period'].toString()),
        IntCellValue(d['admitted']),
        IntCellValue(d['returned']),
        ...dispoCols.map((c) => IntCellValue((d[c] ?? 0) as int)),
        IntCellValue(d['admitted'] - d['returned']),
      ]);
    }

    return Uint8List.fromList(excel.encode()!);
  }

  /// Exports package data to Excel bytes
  Future<Uint8List?> exportPackagesToExcel(List<PackageModel> packages,
      {String? title, String? subTitle}) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Packages'];
    excel.delete('Sheet1');

    if (title != null) {
      sheetObject.appendRow([TextCellValue(title.toUpperCase())]);
      sheetObject.appendRow([TextCellValue(subTitle ?? '')]);
      sheetObject.appendRow([
        TextCellValue(
            'Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}')
      ]);
      sheetObject.appendRow([TextCellValue('')]);
    }

    // Add Headers (one row per item)
    List<String> headers = [
      'SR Number',
      'Item',
      'HS Code',
      'Qty',
      'Date',
      'Consignee',
      'NIC',
      'Status',
      'Value (LKR)',
      'Cusdec No',
      'Description'
    ];
    sheetObject.appendRow(headers.map((e) => TextCellValue(e)).toList());

    // Style the header row
    int headerRowIndex = title != null ? 4 : 0;
    var headerRow = sheetObject.row(headerRowIndex);
    var cellStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#E3F2FD'),
    );
    for (var cell in headerRow) {
      if (cell != null) cell.cellStyle = cellStyle;
    }

    // Add Data — one row per item (same SR repeats for each of its items).
    for (var p in packages) {
      final dateStr = p.entryDate != null
          ? DateFormat('yyyy-MM-dd').format(p.entryDate!)
          : '';
      final items = p.items.isEmpty ? [null] : p.items;
      for (final it in items) {
        sheetObject.appendRow([
          TextCellValue(p.srNumber),
          TextCellValue(it?.itemName ?? '—'),
          TextCellValue((it?.hsCode?.trim().isNotEmpty == true)
              ? it!.hsCode!.trim()
              : '—'),
          IntCellValue(it?.quantity ?? 0),
          TextCellValue(dateStr),
          TextCellValue(p.consigneeName),
          TextCellValue(p.consigneeNic ?? ''),
          TextCellValue((it?.status.isNotEmpty == true ? it!.status : p.status)
              .toUpperCase()),
          DoubleCellValue(it?.unitValue ?? p.declaredValue),
          TextCellValue(p.cusdecNo ?? ''),
          TextCellValue(it?.goodsDescription ?? p.description ?? ''),
        ]);
      }
    }

    return Uint8List.fromList(excel.encode()!);
  }

  /// Generates a PDF report of the post status activities, each with the item
  /// statuses it is offered for.
  Future<Uint8List> generatePostStatusActivitiesPdf(
      List<List<String>> rows) async {
    // Loads the fonts AND the Customs emblem; without it this report
    // fell back to the lettered "SLC" monogram.
    await _ensureFontsLoaded();
    final pdf = pw.Document();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader('POST STATUS ACTIVITY CONFIGURATION REPORT', dateStr,
              'System Configuration Audit'),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
            cellAlignment: pw.Alignment.centerLeft,
            headers: ['Activity', 'Applies To Status'],
            data: rows,
          ),
          _buildFooter(rows.length, label: 'Total Configuration Entries:'),
        ],
      ),
    );
    return pdf.save();
  }

  /// Generates a PDF report for package categories
  Future<Uint8List> generateCategoriesPdf(
      List<PackageCategory> categories) async {
    // Loads the fonts AND the Customs emblem; without it this report
    // fell back to the lettered "SLC" monogram.
    await _ensureFontsLoaded();
    final pdf = pw.Document();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader('PACKAGE CATEGORIES AUDIT', dateStr,
              'Classification & Routing Rules'),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
            headers: [
              'Category Name',
              'Description',
              'Target Warehouse',
              'Zone'
            ],
            data: categories
                .map((c) => [
                      c.name,
                      c.description ?? '-',
                      c.targetWarehouseName ?? 'Default',
                      c.targetZone ?? 'General',
                    ])
                .toList(),
          ),
          _buildFooter(categories.length, label: 'Total Active Categories:'),
        ],
      ),
    );
    return pdf.save();
  }

  /// Generates a PDF report for audit logs
  Future<Uint8List> generateLogsPdf(
      List<AuditLogModel> logs, String dateRange) async {
    await _ensureFontsLoaded();
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: _font,
        bold: _fontBold,
        fontFallback: [_fontSinhala!],
      ),
    );
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader('SYSTEM ACTIVITY LOG AUDIT', dateStr, dateRange),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                font: _fontBold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
            cellAlignment: pw.Alignment.centerLeft,
            cellStyle: pw.TextStyle(fontSize: 8, font: _font),
            headers: ['Timestamp', 'Officer', 'Action', 'Entity', 'Details'],
            data: logs.map((l) {
              String detailsText =
                  l.details != null ? l.details.toString() : '-';
              if (detailsText.length > 200)
                detailsText = '${detailsText.substring(0, 197)}...';

              return [
                DateFormat('yyyy-MM-dd HH:mm').format(l.createdAt),
                l.userFullName ?? 'System',
                l.action,
                '${l.entityType.toUpperCase()} (#${l.entityId.length > 8 ? l.entityId.substring(0, 8) : l.entityId})',
                detailsText,
              ];
            }).toList(),
          ),
          pw.SizedBox(height: 20),
          _buildFooter(logs.length, label: 'Total Activity Records:'),
        ],
      ),
    );
    return pdf.save();
  }

  /// Exports the post status activities to Excel.
  Future<Uint8List?> exportPostStatusActivitiesToExcel(
      List<List<String>> rows) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['PostStatusActivities'];
    excel.delete('Sheet1');

    sheetObject.appendRow(
        [TextCellValue('POST STATUS ACTIVITY CONFIGURATION REPORT')]);
    sheetObject.appendRow([
      TextCellValue(
          'Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}')
    ]);
    sheetObject.appendRow([TextCellValue('')]);

    List<String> headers = ['Activity', 'Applies To Status'];
    sheetObject.appendRow(headers.map((e) => TextCellValue(e)).toList());

    var headerRow = sheetObject.row(3);
    for (var cell in headerRow) {
      if (cell != null)
        cell.cellStyle = CellStyle(
            bold: true,
            backgroundColorHex: ExcelColor.fromHexString('#E3F2FD'));
    }

    for (var r in rows) {
      sheetObject.appendRow(r.map((c) => TextCellValue(c)).toList());
    }
    return Uint8List.fromList(excel.encode()!);
  }

  /// Exports package categories to Excel
  Future<Uint8List?> exportCategoriesToExcel(
      List<PackageCategory> categories) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Categories'];
    excel.delete('Sheet1');

    sheetObject.appendRow([TextCellValue('PACKAGE CATEGORIES AUDIT')]);
    sheetObject.appendRow([TextCellValue('')]);

    List<String> headers = ['Name', 'Description', 'Target Warehouse', 'Zone'];
    sheetObject.appendRow(headers.map((e) => TextCellValue(e)).toList());

    for (var c in categories) {
      sheetObject.appendRow([
        TextCellValue(c.name),
        TextCellValue(c.description ?? ''),
        TextCellValue(c.targetWarehouseName ?? ''),
        TextCellValue(c.targetZone ?? ''),
      ]);
    }
    return Uint8List.fromList(excel.encode()!);
  }

  /// Exports audit logs to Excel
  Future<Uint8List?> exportLogsToExcel(
      List<AuditLogModel> logs, String subTitle) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['AuditLogs'];
    excel.delete('Sheet1');

    sheetObject.appendRow([TextCellValue('SYSTEM ACTIVITY LOG AUDIT')]);
    sheetObject.appendRow([TextCellValue(subTitle)]);
    sheetObject.appendRow([TextCellValue('')]);

    List<String> headers = [
      'Timestamp',
      'Officer',
      'Action',
      'Entity',
      'Details'
    ];
    sheetObject.appendRow(headers.map((e) => TextCellValue(e)).toList());

    for (var l in logs) {
      sheetObject.appendRow([
        TextCellValue(DateFormat('yyyy-MM-dd HH:mm').format(l.createdAt)),
        TextCellValue(l.userFullName ?? 'System'),
        TextCellValue(l.action),
        TextCellValue(l.entityType),
        TextCellValue(l.details?.toString() ?? ''),
      ]);
    }
    return Uint8List.fromList(excel.encode()!);
  }

  /// Generates a PDF report for registered staff
  Future<Uint8List> generateStaffPdf(List<ProfileModel> profiles,
      {PdfPageFormat? format}) async {
    // Loads the fonts AND the Customs emblem; without it this report
    // fell back to the lettered "SLC" monogram.
    await _ensureFontsLoaded();
    final pdf = pw.Document();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format ?? PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader('Registered Staff Audit Report', dateStr, ''),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headers: [
              'Full Name',
              'Badge No',
              'Role',
              'Status',
              'Registered Date'
            ],
            data: profiles
                .map((p) => [
                      p.fullName,
                      p.badgeNumber ?? 'N/A',
                      p.role.toUpperCase(),
                      p.isActive ? 'Active' : 'Deactivated',
                      DateFormat('yyyy-MM-dd').format(p.createdAt),
                    ])
                .toList(),
          ),
          _buildFooter(profiles.length,
              label: 'Confidential Staff Audit Log - Total:'),
        ],
      ),
    );

    return pdf.save();
  }

  /// Exports registered staff data to Excel bytes
  Future<Uint8List?> exportStaffToExcel(List<ProfileModel> profiles) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Staff'];
    excel.delete('Sheet1');

    // Add Headers
    List<String> headers = [
      'Full Name',
      'Badge Number',
      'Role',
      'Status',
      'Registered Date'
    ];
    sheetObject.appendRow(headers.map((e) => TextCellValue(e)).toList());

    // Style the header row
    var headerRow = sheetObject.row(0);
    var cellStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#E3F2FD'),
    );
    for (var cell in headerRow) {
      if (cell != null) cell.cellStyle = cellStyle;
    }

    // Add Data
    for (var p in profiles) {
      sheetObject.appendRow([
        TextCellValue(p.fullName),
        TextCellValue(p.badgeNumber ?? ''),
        TextCellValue(p.role.toUpperCase()),
        TextCellValue(p.isActive ? 'Active' : 'Inactive'),
        TextCellValue(DateFormat('yyyy-MM-dd').format(p.createdAt)),
      ]);
    }

    return Uint8List.fromList(excel.encode()!);
  }

  // ── New Financial & Warehouse Reports ──

  /// Generates a PDF report for Warehouses List
  Future<Uint8List> generateWarehousesListPdf(
      List<WarehouseModel> warehouses, Map<String, int> stats) async {
    await _ensureFontsLoaded();
    final pdf = pw.Document();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader('REGISTERED WAREHOUSES AUDIT', dateStr,
              'Warehouse Occupancy & Status'),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
            headers: [
              'Code',
              'Name',
              'Location',
              'Capacity',
              'Active Held Items'
            ],
            data: warehouses.map((w) {
              final activeCount = stats[w.code] ?? 0;
              return [
                w.code,
                w.name,
                w.location ?? 'General',
                w.capacity?.toString() ?? 'N/A',
                activeCount.toString(),
              ];
            }).toList(),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.center,
              4: pw.Alignment.center
            },
          ),
          _buildFooter(warehouses.length, label: 'Total Warehouses:'),
        ],
      ),
    );
    return pdf.save();
  }

  /// Exports Warehouses List to Excel
  Future<Uint8List?> exportWarehousesListToExcel(
      List<WarehouseModel> warehouses, Map<String, int> stats) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Warehouses'];
    excel.delete('Sheet1');

    sheetObject.appendRow([TextCellValue('REGISTERED WAREHOUSES AUDIT')]);
    sheetObject.appendRow([
      TextCellValue(
          'Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}')
    ]);
    sheetObject.appendRow([TextCellValue('')]);

    List<String> headers = [
      'Code',
      'Name',
      'Location',
      'Capacity',
      'Active Held Items'
    ];
    sheetObject.appendRow(headers.map((e) => TextCellValue(e)).toList());

    var headerRow = sheetObject.row(3);
    for (var cell in headerRow) {
      if (cell != null)
        cell.cellStyle = CellStyle(
            bold: true,
            backgroundColorHex: ExcelColor.fromHexString('#E3F2FD'));
    }

    for (var w in warehouses) {
      sheetObject.appendRow([
        TextCellValue(w.code),
        TextCellValue(w.name),
        TextCellValue(w.location ?? 'General'),
        TextCellValue(w.capacity?.toString() ?? 'N/A'),
        IntCellValue(stats[w.code] ?? 0),
      ]);
    }
    return Uint8List.fromList(excel.encode()!);
  }

  /// Generates a PDF report for Storage Charges (Financial)
  Future<Uint8List> generateFinancialPdf(List<WarehouseEntryModel> entries,
      List<PackageModel> packages, Map<DateTime, double> rates,
      {required bool isRevenue}) async {
    await _ensureFontsLoaded();
    final pdf = pw.Document();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    // Receipt number embedded in the release notes as "Receipt No: XXX".
    String receiptOf(String? notes) {
      if (notes == null || notes.trim().isEmpty) return '—';
      for (final part in notes.split('|')) {
        final t = part.trim();
        if (t.toLowerCase().startsWith('receipt no:')) {
          final idx = t.indexOf(':');
          if (idx != -1) {
            final r = t.substring(idx + 1).trim();
            if (r.isNotEmpty) return r;
          }
        }
      }
      return '—';
    }

    double totalCharge = 0;
    final rowData = <List<String>>[];

    for (var entry in entries) {
      final package = packages.firstWhere((p) => p.id == entry.packageId,
          orElse: () => packages.first);
      final charge = entry.calculatePackageCharge(package.items, rates);
      totalCharge += charge;

      rowData.add([
        entry.srNumber ?? '-',
        entry.itemName ?? itemLabel(package.items),
        (entry.hsCode?.trim().isNotEmpty == true)
            ? entry.hsCode!.trim()
            : hsLabel(package.items),
        DateFormat('yyyy-MM-dd').format(entry.admittedAt),
        entry.isReturned
            ? (entry.returnedAt != null
                ? DateFormat('yyyy-MM-dd').format(entry.returnedAt!)
                : 'Released')
            : 'In Warehouse',
        entry.isReturned ? receiptOf(entry.returnNotes) : '—',
        entry.itemCount.toString(),
        entry.storageDays.toString(),
        NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 2).format(charge),
      ]);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader(
              isRevenue
                  ? 'RELEASED REVENUE REPORT'
                  : 'OUTSTANDING STORAGE CHARGES REPORT',
              dateStr,
              'Financial Audit'),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
            headers: [
              'SR Number',
              'Item',
              'HS Code',
              'Entry Date',
              'Release Date / Status',
              'Receipt No',
              'Items',
              'Days',
              'Calculated Charge'
            ],
            data: rowData,
            cellStyle: const pw.TextStyle(fontSize: 7.5),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.center,
              3: pw.Alignment.center,
              4: pw.Alignment.centerLeft,
              5: pw.Alignment.center,
              6: pw.Alignment.center,
              7: pw.Alignment.center,
              8: pw.Alignment.centerRight,
            },
          ),
          pw.SizedBox(height: 10),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
            pw.Text('Total: ',
                style:
                    pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
            pw.Text(
                NumberFormat.currency(symbol: 'LKR ', decimalDigits: 2)
                    .format(totalCharge),
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 14,
                    color: PdfColors.blue900)),
          ]),
          pw.SizedBox(height: 10),
          _buildFooter(entries.length, label: 'Total Entries:'),
        ],
      ),
    );
    return pdf.save();
  }

  /// Exports Financial Data to Excel
  Future<Uint8List?> exportFinancialToExcel(List<WarehouseEntryModel> entries,
      List<PackageModel> packages, Map<DateTime, double> rates,
      {required bool isRevenue}) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Financial'];
    excel.delete('Sheet1');

    sheetObject.appendRow([
      TextCellValue(isRevenue
          ? 'RELEASED REVENUE REPORT'
          : 'OUTSTANDING STORAGE CHARGES REPORT')
    ]);
    sheetObject.appendRow([
      TextCellValue(
          'Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}')
    ]);
    sheetObject.appendRow([TextCellValue('')]);

    String receiptOf(String? notes) {
      if (notes == null || notes.trim().isEmpty) return '—';
      for (final part in notes.split('|')) {
        final t = part.trim();
        if (t.toLowerCase().startsWith('receipt no:')) {
          final idx = t.indexOf(':');
          if (idx != -1) {
            final r = t.substring(idx + 1).trim();
            if (r.isNotEmpty) return r;
          }
        }
      }
      return '—';
    }

    List<String> headers = [
      'SR Number',
      'Item',
      'HS Code',
      'Entry Date',
      'Release Date / Status',
      'Receipt No',
      'Items',
      'Days',
      'Calculated Charge (LKR)'
    ];
    sheetObject.appendRow(headers.map((e) => TextCellValue(e)).toList());

    var headerRow = sheetObject.row(3);
    for (var cell in headerRow) {
      if (cell != null)
        cell.cellStyle = CellStyle(
            bold: true,
            backgroundColorHex: ExcelColor.fromHexString('#E3F2FD'));
    }

    double totalCharge = 0;
    for (var entry in entries) {
      final package = packages.firstWhere((p) => p.id == entry.packageId,
          orElse: () => packages.first);
      final charge = entry.calculatePackageCharge(package.items, rates);
      totalCharge += charge;

      sheetObject.appendRow([
        TextCellValue(entry.srNumber ?? '-'),
        TextCellValue(entry.itemName ?? itemLabel(package.items)),
        TextCellValue((entry.hsCode?.trim().isNotEmpty == true)
            ? entry.hsCode!.trim()
            : hsLabel(package.items)),
        TextCellValue(DateFormat('yyyy-MM-dd').format(entry.admittedAt)),
        TextCellValue(entry.isReturned
            ? (entry.returnedAt != null
                ? DateFormat('yyyy-MM-dd').format(entry.returnedAt!)
                : 'Released')
            : 'In Warehouse'),
        TextCellValue(entry.isReturned ? receiptOf(entry.returnNotes) : '—'),
        IntCellValue(entry.itemCount),
        IntCellValue(entry.storageDays),
        DoubleCellValue(charge),
      ]);
    }

    sheetObject.appendRow([TextCellValue('')]);
    sheetObject.appendRow([
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue('Total:'),
      DoubleCellValue(totalCharge)
    ]);

    return Uint8List.fromList(excel.encode()!);
  }

  pw.Widget _buildHeader(String title, String date, String subTitle) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    title,
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromInt(0xFF0D47A1),
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    subTitle,
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Sri Lanka Customs - SR Management System',
                    style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 20),
            // The Customs emblem, beside the title.
            _logoWidget(),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Report Type: Status Specific Inventory Audit',
                style:
                    const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            pw.Text('Generated on: $date',
                style:
                    const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          ],
        ),
        pw.Divider(thickness: 1.5, color: PdfColor.fromInt(0xFF0D47A1)),
      ],
    );
  }

  pw.Widget _buildPackageTable(List<PackageModel> packages) {
    const headers = [
      'SR Number',
      'Item',
      'HS Code',
      'Qty',
      'Consignee',
      'Status',
      'Date',
      'Value (LKR)'
    ];

    // One row PER ITEM (an SR with several items shows several rows under the
    // same SR number). Packages with no items still get a single fallback row.
    final rows = <List<String>>[];
    for (final p in packages) {
      final dateStr = p.entryDate != null
          ? DateFormat('yyyy-MM-dd').format(p.entryDate!)
          : '-';
      if (p.items.isEmpty) {
        rows.add([
          p.srNumber,
          '—',
          '—',
          '—',
          p.consigneeName,
          p.status.toUpperCase(),
          dateStr,
          NumberFormat('#,##0').format(p.declaredValue),
        ]);
      } else {
        for (final it in p.items) {
          rows.add([
            p.srNumber,
            it.itemName,
            (it.hsCode?.trim().isNotEmpty == true) ? it.hsCode!.trim() : '—',
            '${it.quantity}',
            p.consigneeName,
            (it.status.isNotEmpty ? it.status : p.status).toUpperCase(),
            dateStr,
            NumberFormat('#,##0').format(it.unitValue),
          ]);
        }
      }
    }

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerStyle: pw.TextStyle(
          fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.white),
      cellStyle: const pw.TextStyle(fontSize: 7),
      headerDecoration:
          const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0D47A1)),
      rowDecoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200))),
      cellHeight: 20,
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.center,
        3: pw.Alignment.center,
        4: pw.Alignment.centerLeft,
        5: pw.Alignment.center,
        6: pw.Alignment.center,
        7: pw.Alignment.centerRight,
      },
    );
  }

  pw.Widget _buildWarehouseTable(List<WarehouseEntryModel> entries,
      {bool isReturnedReport = false}) {
    final headers = [
      'SR No',
      'Item',
      'HS Code',
      'Consignee',
      'Warehouse',
      'Reason',
      'Admitted',
      'Items'
    ];
    if (isReturnedReport) {
      headers.add('Released');
    }

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: entries.map((e) {
        final row = [
          e.srNumber ?? '-',
          e.itemName ?? '—',
          (e.hsCode?.trim().isNotEmpty == true) ? e.hsCode!.trim() : '—',
          e.consigneeName ?? '-',
          e.warehouseCode,
          e.holdReason,
          DateFormat('yyyy-MM-dd').format(e.admittedAt),
          e.itemCount.toString(),
        ];
        if (isReturnedReport) {
          row.add(e.returnedAt != null
              ? DateFormat('yyyy-MM-dd').format(e.returnedAt!)
              : '-');
        }
        return row;
      }).toList(),
      headerStyle: pw.TextStyle(
          fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
      cellStyle: const pw.TextStyle(fontSize: 8),
      headerDecoration:
          const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0D47A1)),
      rowDecoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200))),
      cellHeight: 20,
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.center,
        3: pw.Alignment.centerLeft,
        4: pw.Alignment.center,
        5: pw.Alignment.centerLeft,
        6: pw.Alignment.center,
        7: pw.Alignment.center,
        8: pw.Alignment.center,
      },
    );
  }

  pw.Widget _buildFooter(int count, {String label = 'Total Records:'}) {
    return pw.Column(
      children: [
        pw.Divider(thickness: 1, color: PdfColors.grey300),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Report validated by SR Management System',
                style:
                    const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
            pw.Text('$label $count',
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 11,
                    color: PdfColor.fromInt(0xFF0D47A1))),
          ],
        ),
      ],
    );
  }

  // ── Generic forfeited-package list report (Forfeited / Sold / Destroyed) ──

  /// Helper that builds consistent headers, table rows, and item IDs for
  /// forfeited package reports (used by View, PDF, and Excel).
  /// Rows for the Forfeited / Abandoned / Other goods reports.
  ///
  /// Five columns: SR Number \u00b7 Goods Name \u00b7 Goods Description \u00b7 the date
  /// the status was recorded \u00b7 the FINAL DISPOSITION.
  ///
  /// The final disposition is what ultimately happened to the goods, read from
  /// the `[FINAL:...]` warehouse entry the disposition dialog writes. Goods
  /// still awaiting one report "Pending".
  (List<String>, List<List<String>>, List<String?>) buildForfeitedReportRows(
    List<ForfeitedPackageModel> packages, {
    String dateHeader = 'Date',
  }) {
    final headers = [
      'SR Number',
      'Goods Name',
      'Goods Description',
      dateHeader,
      'Final Disposition',
    ];
    final rows = <List<String>>[];
    final itemIds = <String?>[];

    /// What finally happened to one item, from its `[FINAL:...]` entry.
    String dispositionOf(PackageModel? pkg, String? itemId) {
      if (pkg == null) return 'Pending';
      for (final e in pkg.warehouseEntries) {
        if (itemId != null && e.packageItemId != itemId) continue;
        final note = (e.returnNotes ?? '').trim();
        if (!note.toUpperCase().startsWith('[FINAL:')) continue;
        // "[FINAL:DESTROYED]" or "[FINAL:OTHER] \u2014 <text>".
        final close = note.indexOf(']');
        if (close <= 7) continue;
        final tag = note.substring(7, close).trim();
        final rest = note
            .substring(close + 1)
            .replaceFirst(RegExp(r'^\s*[\u2014-]\s*'), '')
            .trim();
        final label = tag.isEmpty
            ? 'Recorded'
            : tag[0].toUpperCase() + tag.substring(1).toLowerCase();
        return rest.isEmpty ? label : '$label \u2014 $rest';
      }
      return 'Pending';
    }

    String descOf(PackageItem? i) {
      final d = i?.goodsDescription?.trim();
      return (d != null && d.isNotEmpty) ? d : '\u2014';
    }

    for (final f in packages) {
      final pkg = f.packageDetails;
      final items = pkg?.items ?? const <PackageItem>[];
      final dateStr = DateFormat('yyyy-MM-dd').format(f.forfeitedAt);

      if (f.itemId != null) {
        PackageItem? match;
        for (final i in items) {
          if (i.id == f.itemId) {
            match = i;
            break;
          }
        }
        rows.add([
          f.srNumber,
          f.itemName ?? match?.itemName ?? '\u2014',
          descOf(match),
          dateStr,
          dispositionOf(pkg, f.itemId),
        ]);
        itemIds.add(f.itemId);
      } else if (pkg != null) {
        // Package-level row: expand only the items genuinely in this status.
        final forfeitItems =
            items.where((i) => pkg.isItemForfeited(i.id)).toList();
        final effectiveItems = forfeitItems.isNotEmpty ? forfeitItems : items;

        if (effectiveItems.isNotEmpty) {
          for (final i in effectiveItems) {
            rows.add([
              f.srNumber,
              i.itemName,
              descOf(i),
              dateStr,
              dispositionOf(pkg, i.id),
            ]);
            itemIds.add(i.id);
          }
        } else {
          rows.add([
            f.srNumber,
            f.itemName ?? '\u2014',
            '\u2014',
            dateStr,
            dispositionOf(pkg, null),
          ]);
          itemIds.add(null);
        }
      } else {
        rows.add([
          f.srNumber,
          f.itemName ?? '\u2014',
          '\u2014',
          dateStr,
          'Pending',
        ]);
        itemIds.add(null);
      }
    }

    return (headers, rows, itemIds);
  }

  Future<Uint8List> generateForfeitedPdf(
    List<ForfeitedPackageModel> packages, {
    required String title,
    String subTitle = '',
    String dateHeader = 'Date',
  }) async {
    // Loads the fonts AND the Customs emblem; without it this report
    // fell back to the lettered "SLC" monogram.
    await _ensureFontsLoaded();
    final pdf = pw.Document();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final data = buildForfeitedReportRows(packages, dateHeader: dateHeader);
    final headers = data.$1;
    final rows = data.$2;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader(title, dateStr, subTitle),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headers: headers,
            headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 9,
                color: PdfColors.white),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1A237E)),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignment: pw.Alignment.centerLeft,
            data: rows,
          ),
          pw.SizedBox(height: 20),
          _buildFooter(rows.length),
        ],
      ),
    );
    return pdf.save();
  }

  /// Excel for any list of forfeited packages.
  Future<Uint8List?> exportForfeitedToExcel(
    List<ForfeitedPackageModel> packages, {
    required String title,
    String dateHeader = 'Date',
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['Report'];
    excel.delete('Sheet1');
    sheet.appendRow([TextCellValue(title.toUpperCase())]);
    sheet.appendRow([
      TextCellValue(
          'Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}')
    ]);
    sheet.appendRow([TextCellValue('')]);
    final data = buildForfeitedReportRows(packages, dateHeader: dateHeader);
    sheet.appendRow(data.$1.map((e) => TextCellValue(e)).toList());
    for (final row in data.$2) {
      sheet.appendRow(row.map((e) => TextCellValue(e)).toList());
    }
    return Uint8List.fromList(excel.encode()!);
  }

  // ── Tender Packages PDF Report ────────────────────────────────

  /// Generates a PDF report for packages selected for a tender
  Future<Uint8List> generateTenderPackagesPdf(
    List<ForfeitedPackageModel> packages, {
    required String tenderNumber,
    required DateTime tenderDate,
  }) async {
    await _ensureFontsLoaded();
    final pdf = pw.Document();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final tenderDateStr = DateFormat('yyyy-MM-dd').format(tenderDate);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader(
            'TENDER PACKAGES REPORT',
            dateStr,
            'Tender No: $tenderNumber  |  Tender Date: $tenderDateStr',
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Packages with Expired Appeal Period (>30 Days)',
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromInt(0xFFC62828),
            ),
          ),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: [
              'SR Number',
              'Consignee',
              'Forfeited Date',
              'Appeal Deadline',
              'Days Overdue',
              'Reason',
            ],
            data: packages.map((p) {
              final overdue =
                  DateTime.now().difference(p.appealDeadline).inDays;
              return [
                p.srNumber,
                p.consigneeName,
                DateFormat('yyyy-MM-dd').format(p.forfeitedAt),
                DateFormat('yyyy-MM-dd').format(p.appealDeadline),
                overdue > 0 ? '+$overdue days' : '${overdue.abs()} days',
                p.reason.isNotEmpty ? p.reason : '-',
              ];
            }).toList(),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 9,
              color: PdfColors.white,
            ),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFC62828),
            ),
            rowDecoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey200),
              ),
            ),
            cellHeight: 22,
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.center,
              3: pw.Alignment.center,
              4: pw.Alignment.center,
              5: pw.Alignment.centerLeft,
            },
          ),
          pw.SizedBox(height: 20),
          _buildFooter(packages.length, label: 'Total Packages for Tender:'),
        ],
      ),
    );

    return pdf.save();
  }

  /// Exports tender packages to Excel
  Future<Uint8List?> exportTenderPackagesToExcel(
    List<ForfeitedPackageModel> packages, {
    required String tenderNumber,
    required DateTime tenderDate,
  }) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Tender Packages'];
    excel.delete('Sheet1');

    sheetObject.appendRow([TextCellValue('TENDER PACKAGES REPORT')]);
    sheetObject.appendRow([TextCellValue('Tender No: $tenderNumber')]);
    sheetObject.appendRow([
      TextCellValue(
          'Tender Date: ${DateFormat('yyyy-MM-dd').format(tenderDate)}')
    ]);
    sheetObject.appendRow([
      TextCellValue(
          'Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}')
    ]);
    sheetObject.appendRow([TextCellValue('')]);

    final headers = [
      'SR Number',
      'Consignee',
      'Forfeited Date',
      'Appeal Deadline',
      'Days Overdue',
      'Reason',
    ];
    sheetObject.appendRow(headers.map((e) => TextCellValue(e)).toList());

    final headerRow = sheetObject.row(5);
    for (var cell in headerRow) {
      if (cell != null) {
        cell.cellStyle = CellStyle(
          bold: true,
          backgroundColorHex: ExcelColor.fromHexString('#FFCDD2'),
        );
      }
    }

    for (var p in packages) {
      final overdue = DateTime.now().difference(p.appealDeadline).inDays;
      sheetObject.appendRow([
        TextCellValue(p.srNumber),
        TextCellValue(p.consigneeName),
        TextCellValue(DateFormat('yyyy-MM-dd').format(p.forfeitedAt)),
        TextCellValue(DateFormat('yyyy-MM-dd').format(p.appealDeadline)),
        TextCellValue(overdue > 0 ? '+$overdue days' : '${overdue.abs()} days'),
        TextCellValue(p.reason),
      ]);
    }

    return Uint8List.fromList(excel.encode()!);
  }

  /// Generic table export to Excel for any headers and string rows.
  Future<Uint8List?> exportTableToExcel({
    required String title,
    String? subTitle,
    required List<String> columns,
    required List<List<String>> rows,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['Report'];
    excel.delete('Sheet1');

    sheet.appendRow([TextCellValue(title.toUpperCase())]);
    if (subTitle != null && subTitle.isNotEmpty) {
      sheet.appendRow([TextCellValue(subTitle)]);
    }
    sheet.appendRow([
      TextCellValue(
          'Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}')
    ]);
    sheet.appendRow([TextCellValue('')]);

    sheet.appendRow(columns.map((e) => TextCellValue(e)).toList());
    for (final row in rows) {
      sheet.appendRow(row.map((e) => TextCellValue(e)).toList());
    }
    return Uint8List.fromList(excel.encode()!);
  }
}
