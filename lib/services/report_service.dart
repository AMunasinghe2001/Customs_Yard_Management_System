import 'dart:io';
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
  pw.Font? _fontSinhala;

  Future<void> _ensureFontsLoaded() async {
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
  static String warehouseLabel(ForfeitedPackageModel f) {
    final entries = f.packageDetails?.warehouseEntries ?? const [];
    final codes = entries
        .map((e) => e.warehouseCode.trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();
    if (codes.isEmpty) return '—';
    if (codes.length == 1) return codes.first;
    return codes.join(', ');
  }

  /// Generates a PDF report for report items with category summary and zone summary
  Future<Uint8List> generateCategoryAndZonePdf(List<PackageModel> packages, List<WarehouseEntryModel> entries) async {
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
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF0D47A1))),
          pw.Text('Total item quantity registered under each category (all items).',
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
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0D47A1)),
            rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200))),
            columnWidths: {0: const pw.FixedColumnWidth(28)},
            cellAlignments: {0: pw.Alignment.center, 1: pw.Alignment.centerLeft, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight},
          ),

          pw.SizedBox(height: 26),

          // ── Zone section ──
          pw.Text('Active Inventory by Warehouse Zone',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF0D47A1))),
          pw.Text('Currently held item quantity per warehouse zone (released items excluded).',
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
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0D47A1)),
            rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200))),
            columnWidths: {0: const pw.FixedColumnWidth(28)},
            cellAlignments: {0: pw.Alignment.center, 1: pw.Alignment.centerLeft, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight},
          ),

          pw.SizedBox(height: 18),
          _buildFooter(packages.length, label: 'Packages Scanned:'),
        ],
      ),
    );

    return pdf.save();
  }

  /// Exports category and zone data to Excel
  Future<Uint8List?> exportCategoryAndZoneToExcel(List<PackageModel> packages, List<WarehouseEntryModel> entries) async {
    var excel = Excel.createExcel();
    excel.delete('Sheet1');

    String pct(int v, int total) =>
        total == 0 ? '0%' : '${(v * 100 / total).toStringAsFixed(1)}%';

    // Category Sheet (sorted desc, with Share % and a TOTAL row).
    Sheet catSheet = excel['Category Summary'];
    catSheet.appendRow([TextCellValue('CATEGORY INVENTORY SUMMARY')]);
    catSheet.appendRow([
      TextCellValue('#'), TextCellValue('Item Category'),
      TextCellValue('Total Quantity'), TextCellValue('Share')
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
      TextCellValue(''), TextCellValue('TOTAL'),
      IntCellValue(catTotal), TextCellValue('100%')
    ]);

    // Zone Sheet (warehouse · zone, held qty, sorted desc, Share + TOTAL).
    Sheet zoneSheet = excel['Zone Summary'];
    zoneSheet.appendRow([TextCellValue('WAREHOUSE ZONE OCCUPANCY (HELD)')]);
    zoneSheet.appendRow([
      TextCellValue('#'), TextCellValue('Warehouse · Zone'),
      TextCellValue('Held Quantity'), TextCellValue('Share')
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
      TextCellValue(''), TextCellValue('TOTAL'),
      IntCellValue(zoneTotal), TextCellValue('100%')
    ]);

    return Uint8List.fromList(excel.encode()!);
  }

  /// Generates a PDF report for a list of packages
  Future<Uint8List> generatePackagePdf(List<PackageModel> packages, {
    String? title, 
    String? dateRange,
    PdfPageFormat? format,
  }) async {
    final pdf = pw.Document();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format ?? PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader(title ?? 'Package Inventory Audit', dateStr, dateRange ?? ''),
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
  Future<Uint8List> generateWarehousePdf(List<WarehouseEntryModel> entries, {
    String? title, 
    bool isReturnedReport = false,
    PdfPageFormat? format,
  }) async {
    final pdf = pw.Document();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format ?? PdfPageFormat.a4.landscape, 
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader(title ?? (isReturnedReport ? 'Released Packages Report' : 'Warehouse Status Report'), dateStr, ''),
          pw.SizedBox(height: 20),
          _buildWarehouseTable(entries, isReturnedReport: isReturnedReport),
          pw.SizedBox(height: 20),
          _buildFooter(entries.length),
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
    final pdf = pw.Document();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    // Disposition breakdown columns (in addition to admit/release/net).
    const dispoCols = ['forfeit', 'abandoned', 're-export', 'destroy', 'sold', 'other'];
    const dispoHeaders = ['Forfeit', 'Abandoned', 'Re-export', 'Destroy', 'Sold', 'Other'];

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format ?? PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          _buildHeader(title, dateStr, ''),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headers: [
              periodLabel, 'Admitted', 'Released', ...dispoHeaders, 'Net Change'
            ],
            data: summaryData.map((d) => [
              d['period'],
              d['admitted'].toString(),
              d['returned'].toString(),
              for (final c in dispoCols) (d[c] ?? 0).toString(),
              (d['admitted'] - d['returned']).toString(),
            ]).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.white),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0D47A1)), // Customs Blue
            rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200))),
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
  Future<Uint8List?> exportWarehouseToExcel(List<WarehouseEntryModel> entries, {bool isReturned = false}) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel[isReturned ? 'Released' : 'In_Warehouse'];
    excel.delete('Sheet1');

    // Add Headers
    List<String> headers = [
      'SR Number', 'Item', 'HS Code', 'Consignee', 'Warehouse', 'Admitted At',
      'Reason', 'Items'
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
        TextCellValue((e.hsCode?.trim().isNotEmpty == true) ? e.hsCode!.trim() : ''),
        TextCellValue(e.consigneeName ?? ''),
        TextCellValue(e.warehouseCode),
        TextCellValue(DateFormat('yyyy-MM-dd HH:mm').format(e.admittedAt)),
        TextCellValue(e.holdReason),
        IntCellValue(e.itemCount),
      ];
      if (isReturned) {
        row.add(TextCellValue(e.returnedAt != null ? DateFormat('yyyy-MM-dd HH:mm').format(e.returnedAt!) : ''));
        row.add(TextCellValue(e.returnNotes ?? ''));
      }
      sheetObject.appendRow(row);
    }

    return Uint8List.fromList(excel.encode()!);
  }

  /// Exports summary data to Excel bytes
  Future<Uint8List?> exportSummaryToExcel(List<Map<String, dynamic>> summaryData, String periodLabel) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Summary'];
    excel.delete('Sheet1');

    const dispoCols = ['forfeit', 'abandoned', 're-export', 'destroy', 'sold', 'other'];
    const dispoHeaders = ['Forfeit', 'Abandoned', 'Re-export', 'Destroy', 'Sold', 'Other'];

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
  Future<Uint8List?> exportPackagesToExcel(List<PackageModel> packages, {String? title, String? subTitle}) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Packages'];
    excel.delete('Sheet1');

    if (title != null) {
      sheetObject.appendRow([TextCellValue(title.toUpperCase())]);
      sheetObject.appendRow([TextCellValue(subTitle ?? '')]);
      sheetObject.appendRow([TextCellValue('Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}')]);
      sheetObject.appendRow([TextCellValue('')]);
    }

    // Add Headers (one row per item)
    List<String> headers = [
      'SR Number', 'Item', 'HS Code', 'Qty', 'Date', 'Consignee', 'NIC',
      'Status', 'Value (LKR)', 'Cusdec No', 'Description'
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
      final dateStr =
          p.entryDate != null ? DateFormat('yyyy-MM-dd').format(p.entryDate!) : '';
      final items = p.items.isEmpty ? [null] : p.items;
      for (final it in items) {
        sheetObject.appendRow([
          TextCellValue(p.srNumber),
          TextCellValue(it?.itemName ?? '—'),
          TextCellValue((it?.hsCode?.trim().isNotEmpty == true) ? it!.hsCode!.trim() : '—'),
          IntCellValue(it?.quantity ?? 0),
          TextCellValue(dateStr),
          TextCellValue(p.consigneeName),
          TextCellValue(p.consigneeNic ?? ''),
          TextCellValue((it?.status.isNotEmpty == true ? it!.status : p.status).toUpperCase()),
          DoubleCellValue(it?.unitValue ?? p.declaredValue),
          TextCellValue(p.cusdecNo ?? ''),
          TextCellValue(it?.goodsDescription ?? p.description ?? ''),
        ]);
      }
    }

    return Uint8List.fromList(excel.encode()!);
  }

  /// Generates a PDF report for hold reasons
  Future<Uint8List> generateHoldReasonsPdf(List<HoldReasonModel> reasons) async {
    final pdf = pw.Document();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader('HOLD REASONS CONFIGURATION REPORT', dateStr, 'System Configuration Audit'),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
            cellAlignment: pw.Alignment.centerLeft,
            headers: ['Reason Text', 'Description', 'Status'],
            data: reasons.map((r) => [
              r.reasonText,
              r.description ?? '-',
              r.isActive ? 'ACTIVE' : 'INACTIVE',
            ]).toList(),
          ),
          _buildFooter(reasons.length, label: 'Total Configuration Entries:'),
        ],
      ),
    );
    return pdf.save();
  }

  /// Generates a PDF report for package categories
  Future<Uint8List> generateCategoriesPdf(List<PackageCategory> categories) async {
    final pdf = pw.Document();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader('PACKAGE CATEGORIES AUDIT', dateStr, 'Classification & Routing Rules'),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
            headers: ['Category Name', 'Description', 'Target Warehouse', 'Zone'],
            data: categories.map((c) => [
              c.name,
              c.description ?? '-',
              c.targetWarehouseName ?? 'Default',
              c.targetZone ?? 'General',
            ]).toList(),
          ),
          _buildFooter(categories.length, label: 'Total Active Categories:'),
        ],
      ),
    );
    return pdf.save();
  }
  /// Generates a PDF report for audit logs
  Future<Uint8List> generateLogsPdf(List<AuditLogModel> logs, String dateRange) async {
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
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, font: _fontBold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
            cellAlignment: pw.Alignment.centerLeft,
            cellStyle: pw.TextStyle(fontSize: 8, font: _font),
            headers: ['Timestamp', 'Officer', 'Action', 'Entity', 'Details'],
            data: logs.map((l) {
              String detailsText = l.details != null ? l.details.toString() : '-';
              if (detailsText.length > 200) detailsText = '${detailsText.substring(0, 197)}...';
              
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

  /// Exports hold reasons to Excel
  Future<Uint8List?> exportHoldReasonsToExcel(List<HoldReasonModel> reasons) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['HoldReasons'];
    excel.delete('Sheet1');

    sheetObject.appendRow([TextCellValue('HOLD REASONS CONFIGURATION REPORT')]);
    sheetObject.appendRow([TextCellValue('Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}')]);
    sheetObject.appendRow([TextCellValue('')]);

    List<String> headers = ['Reason Text', 'Description', 'Status'];
    sheetObject.appendRow(headers.map((e) => TextCellValue(e)).toList());
    
    var headerRow = sheetObject.row(3);
    for (var cell in headerRow) {
      if (cell != null) cell.cellStyle = CellStyle(bold: true, backgroundColorHex: ExcelColor.fromHexString('#E3F2FD'));
    }

    for (var r in reasons) {
      sheetObject.appendRow([
        TextCellValue(r.reasonText),
        TextCellValue(r.description ?? ''),
        TextCellValue(r.isActive ? 'Active' : 'Inactive'),
      ]);
    }
    return Uint8List.fromList(excel.encode()!);
  }

  /// Exports package categories to Excel
  Future<Uint8List?> exportCategoriesToExcel(List<PackageCategory> categories) async {
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
  Future<Uint8List?> exportLogsToExcel(List<AuditLogModel> logs, String subTitle) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['AuditLogs'];
    excel.delete('Sheet1');

    sheetObject.appendRow([TextCellValue('SYSTEM ACTIVITY LOG AUDIT')]);
    sheetObject.appendRow([TextCellValue(subTitle)]);
    sheetObject.appendRow([TextCellValue('')]);

    List<String> headers = ['Timestamp', 'Officer', 'Action', 'Entity', 'Details'];
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
  Future<Uint8List> generateStaffPdf(List<ProfileModel> profiles, {PdfPageFormat? format}) async {
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
            headers: ['Full Name', 'Badge No', 'Role', 'Status', 'Registered Date'],
            data: profiles.map((p) => [
              p.fullName,
              p.badgeNumber ?? 'N/A',
              p.role.toUpperCase(),
              p.isActive ? 'Active' : 'Deactivated',
              DateFormat('yyyy-MM-dd').format(p.createdAt),
            ]).toList(),
          ),
          _buildFooter(profiles.length, label: 'Confidential Staff Audit Log - Total:'),
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
    List<String> headers = ['Full Name', 'Badge Number', 'Role', 'Status', 'Registered Date'];
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
  Future<Uint8List> generateWarehousesListPdf(List<WarehouseModel> warehouses, Map<String, int> stats) async {
    final pdf = pw.Document();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader('REGISTERED WAREHOUSES AUDIT', dateStr, 'Warehouse Occupancy & Status'),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
            headers: ['Code', 'Name', 'Location', 'Capacity', 'Active Held Items'],
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
            cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerLeft, 2: pw.Alignment.centerLeft, 3: pw.Alignment.center, 4: pw.Alignment.center},
          ),
          _buildFooter(warehouses.length, label: 'Total Warehouses:'),
        ],
      ),
    );
    return pdf.save();
  }

  /// Exports Warehouses List to Excel
  Future<Uint8List?> exportWarehousesListToExcel(List<WarehouseModel> warehouses, Map<String, int> stats) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Warehouses'];
    excel.delete('Sheet1');

    sheetObject.appendRow([TextCellValue('REGISTERED WAREHOUSES AUDIT')]);
    sheetObject.appendRow([TextCellValue('Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}')]);
    sheetObject.appendRow([TextCellValue('')]);

    List<String> headers = ['Code', 'Name', 'Location', 'Capacity', 'Active Held Items'];
    sheetObject.appendRow(headers.map((e) => TextCellValue(e)).toList());
    
    var headerRow = sheetObject.row(3);
    for (var cell in headerRow) {
      if (cell != null) cell.cellStyle = CellStyle(bold: true, backgroundColorHex: ExcelColor.fromHexString('#E3F2FD'));
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
  Future<Uint8List> generateFinancialPdf(List<WarehouseEntryModel> entries, List<PackageModel> packages, Map<DateTime, double> rates, {required bool isRevenue}) async {
    final pdf = pw.Document();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    
    double totalCharge = 0;
    final rowData = <List<String>>[];
    
    for (var entry in entries) {
      final package = packages.firstWhere((p) => p.id == entry.packageId, orElse: () => packages.first);
      final charge = entry.calculatePackageCharge(package.items, rates);
      totalCharge += charge;

      rowData.add([
        entry.srNumber ?? '-',
        entry.itemName ?? itemLabel(package.items),
        (entry.hsCode?.trim().isNotEmpty == true)
            ? entry.hsCode!.trim()
            : hsLabel(package.items),
        entry.isReturned ? (entry.returnedAt != null ? DateFormat('yyyy-MM-dd').format(entry.returnedAt!) : '-') : 'Active',
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
          _buildHeader(isRevenue ? 'RELEASED REVENUE REPORT' : 'OUTSTANDING STORAGE CHARGES REPORT', dateStr, 'Financial Audit'),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
            headers: ['SR Number', 'Item', 'HS Code', 'Release Date', 'Items', 'Days', 'Calculated Charge'],
            data: rowData,
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerLeft, 2: pw.Alignment.center, 3: pw.Alignment.centerLeft, 4: pw.Alignment.center, 5: pw.Alignment.center, 6: pw.Alignment.centerRight},
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text('Total: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
              pw.Text(NumberFormat.currency(symbol: 'LKR ', decimalDigits: 2).format(totalCharge), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14, color: PdfColors.blue900)),
            ]
          ),
          pw.SizedBox(height: 10),
          _buildFooter(entries.length, label: 'Total Entries:'),
        ],
      ),
    );
    return pdf.save();
  }

  /// Exports Financial Data to Excel
  Future<Uint8List?> exportFinancialToExcel(List<WarehouseEntryModel> entries, List<PackageModel> packages, Map<DateTime, double> rates, {required bool isRevenue}) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Financial'];
    excel.delete('Sheet1');

    sheetObject.appendRow([TextCellValue(isRevenue ? 'RELEASED REVENUE REPORT' : 'OUTSTANDING STORAGE CHARGES REPORT')]);
    sheetObject.appendRow([TextCellValue('Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}')]);
    sheetObject.appendRow([TextCellValue('')]);

    List<String> headers = ['SR Number', 'Item', 'HS Code', 'Release Date', 'Items', 'Days', 'Calculated Charge (LKR)'];
    sheetObject.appendRow(headers.map((e) => TextCellValue(e)).toList());

    var headerRow = sheetObject.row(3);
    for (var cell in headerRow) {
      if (cell != null) cell.cellStyle = CellStyle(bold: true, backgroundColorHex: ExcelColor.fromHexString('#E3F2FD'));
    }

    double totalCharge = 0;
    for (var entry in entries) {
      final package = packages.firstWhere((p) => p.id == entry.packageId, orElse: () => packages.first);
      final charge = entry.calculatePackageCharge(package.items, rates);
      totalCharge += charge;

      sheetObject.appendRow([
        TextCellValue(entry.srNumber ?? '-'),
        TextCellValue(entry.itemName ?? itemLabel(package.items)),
        TextCellValue((entry.hsCode?.trim().isNotEmpty == true)
            ? entry.hsCode!.trim()
            : hsLabel(package.items)),
        TextCellValue(entry.isReturned ? (entry.returnedAt != null ? DateFormat('yyyy-MM-dd').format(entry.returnedAt!) : '-') : 'Active'),
        IntCellValue(entry.itemCount),
        IntCellValue(entry.storageDays),
        DoubleCellValue(charge),
      ]);
    }

    sheetObject.appendRow([TextCellValue('')]);
    sheetObject.appendRow([TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue('Total:'), DoubleCellValue(totalCharge)]);
    
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
            pw.Container(
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
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Report Type: Status Specific Inventory Audit', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            pw.Text('Generated on: $date', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          ],
        ),
        pw.Divider(thickness: 1.5, color: PdfColor.fromInt(0xFF0D47A1)),
      ],
    );
  }

  pw.Widget _buildPackageTable(List<PackageModel> packages) {
    const headers = [
      'SR Number', 'Item', 'HS Code', 'Qty', 'Consignee', 'Status', 'Date',
      'Value (LKR)'
    ];

    // One row PER ITEM (an SR with several items shows several rows under the
    // same SR number). Packages with no items still get a single fallback row.
    final rows = <List<String>>[];
    for (final p in packages) {
      final dateStr =
          p.entryDate != null ? DateFormat('yyyy-MM-dd').format(p.entryDate!) : '-';
      if (p.items.isEmpty) {
        rows.add([
          p.srNumber, '—', '—', '—', p.consigneeName,
          p.status.toUpperCase(), dateStr,
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
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.white),
      cellStyle: const pw.TextStyle(fontSize: 7),
      headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0D47A1)),
      rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200))),
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

  pw.Widget _buildWarehouseTable(List<WarehouseEntryModel> entries, {bool isReturnedReport = false}) {
    final headers = [
      'SR No', 'Item', 'HS Code', 'Consignee', 'Warehouse', 'Reason',
      'Admitted', 'Items'
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
          row.add(e.returnedAt != null ? DateFormat('yyyy-MM-dd').format(e.returnedAt!) : '-');
        }
        return row;
      }).toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
      cellStyle: const pw.TextStyle(fontSize: 8),
      headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0D47A1)),
      rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200))),
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
            pw.Text('Report validated by SR Management System', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
            pw.Text('$label $count', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColor.fromInt(0xFF0D47A1))),
          ],
        ),
      ],
    );
  }

  // ── Generic forfeited-package list report (Forfeited / Sold / Destroyed) ──

  /// PDF for any list of forfeited packages (used by the yard-page reports:
  /// Forfeited, Sold, Destroyed, etc.). [title]/[subTitle] label the report.
  Future<Uint8List> generateForfeitedPdf(
    List<ForfeitedPackageModel> packages, {
    required String title,
    String subTitle = '',
    String dateHeader = 'Date',
  }) async {
    final pdf = pw.Document();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader(title, dateStr, subTitle),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            // No "Source" column — the report title already says which action
            // this is (FORFEITED / ABANDONED / OTHER), and it was identical on
            // every row. Yard replaced by Warehouse.
            headers: [
              'SR Number',
              'Item',
              'HS Code',
              'Consignee',
              'Warehouse',
              'Reason',
              dateHeader,
            ],
            headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1A237E)),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignment: pw.Alignment.centerLeft,
            data: packages.map((f) {
              final items = f.packageDetails?.items ?? const [];
              final name = f.itemName ?? itemLabel(items);
              return [
                f.srNumber,
                name,
                hsLabel(items),
                f.consigneeName,
                warehouseLabel(f),
                f.reason,
                DateFormat('yyyy-MM-dd').format(f.forfeitedAt),
              ];
            }).toList(),
          ),
          pw.SizedBox(height: 20),
          _buildFooter(packages.length),
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
    final headers = [
      'SR Number',
      'Item',
      'HS Code',
      'Consignee',
      'Warehouse',
      'Reason',
      dateHeader,
    ];
    sheet.appendRow(headers.map((e) => TextCellValue(e)).toList());
    for (final f in packages) {
      final items = f.packageDetails?.items ?? const [];
      final name = f.itemName ?? (items.isEmpty ? '' : itemLabel(items));
      sheet.appendRow([
        TextCellValue(f.srNumber),
        TextCellValue(name),
        TextCellValue(items.isEmpty ? '' : hsLabel(items)),
        TextCellValue(f.consigneeName),
        TextCellValue(warehouseLabel(f)),
        TextCellValue(f.reason),
        TextCellValue(DateFormat('yyyy-MM-dd').format(f.forfeitedAt)),
      ]);
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
              final overdue = DateTime.now().difference(p.appealDeadline).inDays;
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
      final overdue =
          DateTime.now().difference(p.appealDeadline).inDays;
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
}
