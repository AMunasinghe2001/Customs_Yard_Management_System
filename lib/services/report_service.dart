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
  Future<void> generatePackagePdf(List<PackageModel> packages, {String? title}) async {
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

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: '${title?.replaceAll(' ', '_') ?? 'Package_Report'}_$dateStr.pdf',
    );
  }

  /// Generates a PDF report for warehouse entries
  Future<void> generateWarehousePdf(List<WarehouseEntryModel> entries, {String? title}) async {
    final pdf = pw.Document();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader(title ?? 'Warehouse Status Report', dateStr),
          pw.SizedBox(height: 20),
          _buildWarehouseTable(entries),
          pw.SizedBox(height: 20),
          _buildFooter(entries.length),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: '${title?.replaceAll(' ', '_') ?? 'Warehouse_Report'}_$dateStr.pdf',
    );
  }

  /// Exports package data to Excel
  Future<void> exportPackagesToExcel(List<PackageModel> packages) async {
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

    final bytes = excel.save();
    if (bytes != null) {
      final directory = await getApplicationDocumentsDirectory();
      final dateStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final filePath = '${directory.path}/Package_Export_$dateStr.xlsx';
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      
      // Since it's a desktop app, we can just let the user know where it's saved or try to open it
      // For now, we'll assume the UI will handle showing a success message with path.
    }
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

  pw.Widget _buildWarehouseTable(List<WarehouseEntryModel> entries) {
    const headers = ['SR No', 'Warehouse', 'Reason', 'Admitted', 'Items'];

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: entries.map((e) => [
        e.srNumber ?? '-',
        e.warehouseCode,
        e.holdReason,
        DateFormat('yyyy-MM-dd').format(e.admittedAt),
        e.itemCount.toString(),
      ]).toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellHeight: 25,
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.center,
        2: pw.Alignment.centerLeft,
        3: pw.Alignment.center,
        4: pw.Alignment.center,
      },
    );
  }

  pw.Widget _buildFooter(int count) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('Total Records: $count', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
    );
  }
}
