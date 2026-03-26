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
          _buildHeader(title ?? (isReturnedReport ? 'Returned Packages Report' : 'Warehouse Status Report'), dateStr, ''),
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

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format ?? PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader(title, dateStr, ''),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headers: [periodLabel, 'Admitted', 'Returned', 'Net Change'],
            data: summaryData.map((d) => [
              d['period'],
              d['admitted'].toString(),
              d['returned'].toString(),
              (d['admitted'] - d['returned']).toString(),
            ]).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0D47A1)), // Customs Blue
            rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200))),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.center,
              2: pw.Alignment.center,
              3: pw.Alignment.center,
            },
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
    Sheet sheetObject = excel[isReturned ? 'Returned' : 'In_Warehouse'];
    excel.delete('Sheet1');

    // Add Headers
    List<String> headers = [
      'SR Number', 'Consignee', 'Warehouse', 'Admitted At', 'Reason', 'Items'
    ];
    if (isReturned) {
      headers.addAll(['Returned At', 'Return Notes']);
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

    sheetObject.appendRow([
      TextCellValue(periodLabel),
      TextCellValue('Admitted'),
      TextCellValue('Returned'),
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

    // Add Headers
    List<String> headers = [
      'SR Number', 'Date', 'Consignee', 'NIC', 'Status', 
      'Weight (kg)', 'Value (LKR)', 'Cusdec No', 'Origin', 'Description'
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

    // Add Data
    for (var p in packages) {
      sheetObject.appendRow([
        TextCellValue(p.srNumber),
        TextCellValue(p.entryDate != null ? DateFormat('yyyy-MM-dd').format(p.entryDate!) : ''),
        TextCellValue(p.consigneeName),
        TextCellValue(p.consigneeNic ?? ''),
        TextCellValue(p.status.toUpperCase()),
        DoubleCellValue(p.weightKg),
        DoubleCellValue(p.declaredValue),
        TextCellValue(p.cusdecNo ?? ''),
        TextCellValue(p.originCountry),
        TextCellValue(p.description ?? ''),
      ]);
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

  /// Generates a PDF report for customs rules
  Future<Uint8List> generateRulesPdf(List<CustomsRule> rules) async {
    final pdf = pw.Document();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader('CUSTOMS INSPECTION RULES AUDIT', dateStr, 'Automated Assessment Rules'),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
            headers: ['Rule Name', 'Type', 'Threshold/Value', 'Status'],
            data: rules.map((r) => [
              r.ruleName,
              r.ruleType.toUpperCase(),
              r.thresholdValue != null ? r.thresholdValue.toString() : (r.stringValue ?? '-'),
              r.isActive ? 'ENABLED' : 'DISABLED',
            ]).toList(),
          ),
          _buildFooter(rules.length, label: 'Total Governance Rules:'),
        ],
      ),
    );
    return pdf.save();
  }

  /// Generates a PDF report for audit logs
  Future<Uint8List> generateLogsPdf(List<AuditLogModel> logs, String dateRange) async {
    final pdf = pw.Document();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader('SYSTEM ACTIVITY LOG AUDIT', dateStr, dateRange),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
            headers: ['Timestamp', 'Officer', 'Action', 'Entity', 'Details'],
            data: logs.map((l) => [
              DateFormat('yyyy-MM-dd HH:mm').format(l.createdAt),
              l.userFullName ?? 'System',
              l.action,
              '${l.entityType.toUpperCase()} (#${l.entityId.substring(0, 8)})',
              l.details != null ? l.details.toString() : '-',
            ]).toList(),
          ),
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

  /// Exports customs rules to Excel
  Future<Uint8List?> exportRulesToExcel(List<CustomsRule> rules) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Rules'];
    excel.delete('Sheet1');

    sheetObject.appendRow([TextCellValue('CUSTOMS INSPECTION RULES AUDIT')]);
    sheetObject.appendRow([TextCellValue('')]);

    List<String> headers = ['Rule Name', 'Type', 'Threshold/Value', 'Status'];
    sheetObject.appendRow(headers.map((e) => TextCellValue(e)).toList());
    
    for (var r in rules) {
      sheetObject.appendRow([
        TextCellValue(r.ruleName),
        TextCellValue(r.ruleType),
        TextCellValue(r.thresholdValue?.toString() ?? r.stringValue ?? ''),
        TextCellValue(r.isActive ? 'Active' : 'Inactive'),
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
                    'Sri Lanka Customs - Inventory Management System', 
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
    const headers = ['SR Number', 'Consignee', 'NIC', 'Status', 'Date', 'Weight', 'Value', 'Origin'];

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: packages.map((p) => [
        p.srNumber,
        p.consigneeName,
        p.consigneeNic ?? '-',
        p.status.toUpperCase(),
        p.entryDate != null ? DateFormat('yyyy-MM-dd').format(p.entryDate!) : '-',
        p.weightKg.toStringAsFixed(1),
        NumberFormat.currency(symbol: '', decimalDigits: 0).format(p.declaredValue),
        p.originCountry,
      ]).toList(),
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
        4: pw.Alignment.center,
        5: pw.Alignment.centerRight,
        6: pw.Alignment.centerRight,
        7: pw.Alignment.center,
      },
    );
  }

  pw.Widget _buildWarehouseTable(List<WarehouseEntryModel> entries, {bool isReturnedReport = false}) {
    final headers = [
      'SR No', 'Consignee', 'Warehouse', 'Reason', 'Admitted', 'Items'
    ];
    if (isReturnedReport) {
      headers.add('Returned');
    }

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: entries.map((e) {
        final row = [
          e.srNumber ?? '-',
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
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.white),
      cellStyle: const pw.TextStyle(fontSize: 9),
      headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0D47A1)),
      rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200))),
      cellHeight: 20,
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.center,
        3: pw.Alignment.centerLeft,
        4: pw.Alignment.center,
        5: pw.Alignment.center,
        6: pw.Alignment.center,
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
            pw.Text('Report validated by Inventory Management System (Grey Line 1)', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
            pw.Text('$label $count', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColor.fromInt(0xFF0D47A1))),
          ],
        ),
      ],
    );
  }
}
