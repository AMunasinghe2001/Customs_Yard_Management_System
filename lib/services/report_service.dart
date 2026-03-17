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
  Future<Uint8List> generatePackagePdf(List<PackageModel> packages, {String? title}) async {
    final pdf = pw.Document();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader(title ?? 'Package Summary Report', dateStr),
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
  Future<Uint8List> generateWarehousePdf(List<WarehouseEntryModel> entries, {String? title, bool isReturnedReport = false}) async {
    final pdf = pw.Document();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape, 
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader(title ?? (isReturnedReport ? 'Returned Packages Report' : 'Warehouse Status Report'), dateStr),
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
  }) async {
    final pdf = pw.Document();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader(title, dateStr),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headers: [periodLabel, 'Admitted', 'Returned', 'Net Change'],
            data: summaryData.map((d) => [
              d['period'],
              d['admitted'].toString(),
              d['returned'].toString(),
              (d['admitted'] - d['returned']).toString(),
            ]).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
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
  Future<Uint8List?> exportPackagesToExcel(List<PackageModel> packages) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Packages'];
    excel.delete('Sheet1');

    // Add Headers
    List<String> headers = [
      'SR Number', 'Date', 'Consignee', 'NIC', 'Status', 
      'Weight (kg)', 'Value (LKR)', 'Cusdec No', 'Origin', 'Description'
    ];
    sheetObject.appendRow(headers.map((e) => TextCellValue(e)).toList());

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

  /// Generates a PDF report for registered staff
  Future<Uint8List> generateStaffPdf(List<ProfileModel> profiles) async {
    final pdf = pw.Document();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader('Registered Staff Audit Report', dateStr),
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

  pw.Widget _buildHeader(String title, String date) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('Sri Lanka Customs - Yard Management System', style: const pw.TextStyle(fontSize: 12)),
        pw.Text('Generated on: $date', style: const pw.TextStyle(fontSize: 10)),
        pw.Divider(thickness: 1),
      ],
    );
  }

  pw.Widget _buildPackageTable(List<PackageModel> packages) {
    const headers = ['SR Number', 'Consignee', 'Status', 'Date', 'Value'];

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: packages.map((p) => [
        p.srNumber,
        p.consigneeName,
        p.status.toUpperCase(),
        p.entryDate != null ? DateFormat('yyyy-MM-dd').format(p.entryDate!) : '-',
        NumberFormat.currency(symbol: '', decimalDigits: 2).format(p.declaredValue),
      ]).toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellHeight: 25,
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.center,
        3: pw.Alignment.center,
        4: pw.Alignment.centerRight,
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
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
      cellStyle: const pw.TextStyle(fontSize: 9),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
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
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('$label $count', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
    );
  }
}
