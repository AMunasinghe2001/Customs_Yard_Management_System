import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:barcode/barcode.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import '../models/models.dart';

class BarcodeService {
  /// Generate a barcode image for a package
  static Future<img.Image?> generateBarcodeImage(String srNumber,
      {int width = 400, int height = 100}) async {
    try {
      final bc = Barcode.code128();
      final svgString = bc.toSvg(srNumber, width: width.toDouble(), height: height.toDouble());
      
      // For now, return null as placeholder
      // In production, you'd convert SVG to image using a proper library
      return null;
    } catch (e) {
      print('Error generating barcode: $e');
      return null;
    }
  }

  /// Create a PDF document with barcodes for multiple packages
  static Future<pw.Document> createBarcodePDF(List<PackageModel> packages) async {
    final doc = pw.Document();
    final labels = _buildItemLabels(packages);
    _addLabelPages(
      doc,
      labels
          .map((label) => _buildDetailedItemLabel(label))
          .toList(),
      labelPerRow: 2,
      labelHeight: 180,
    );

    return doc;
  }

  /// Create a PDF document with multiple barcodes per page (for batch printing)
  static Future<pw.Document> createBatchBarcodesPDF(List<PackageModel> packages, {int labelPerRow = 2}) async {
    final doc = pw.Document();
    final barcodeLabelSize = PdfPageFormat.a4.width / labelPerRow;

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (context) {
          final children = <pw.Widget>[];

          for (int i = 0; i < packages.length; i += (4 ~/ (6 ~/ labelPerRow))) {
            children.add(
              pw.Wrap(
                spacing: 5,
                runSpacing: 5,
                children: packages
                    .skipWhile((p) => packages.indexOf(p) < i)
                    .take(4 ~/ (6 ~/ labelPerRow))
                    .map((package) {
                  final bc = Barcode.code128();
                  final svgString = bc.toSvg(package.srNumber, width: 200, height: 60);

                  return pw.Container(
                    width: barcodeLabelSize - 10,
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.black),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Text(package.srNumber,
                            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 5),
                        pw.SvgImage(svg: svgString),
                        pw.SizedBox(height: 3),
                        pw.Text(package.consigneeName,
                            style: pw.TextStyle(fontSize: 7),
                            textAlign: pw.TextAlign.center,
                            maxLines: 2),
                      ],
                    ),
                  );
                }).toList(),
              ),
            );
          }

          return pw.Column(children: children);
        },
      ),
    );

    return doc;
  }

  /// Create a PDF document with item-level barcodes (repeated by quantity)
  static Future<pw.Document> createItemBarcodePDF(List<PackageModel> packages,
      {int labelPerRow = 2}) async {
    final doc = pw.Document();
    final labels = _buildItemLabels(packages);

    _addLabelPages(
      doc,
      labels.map((label) => _buildCompactItemLabel(label)).toList(),
      labelPerRow: labelPerRow,
      labelHeight: 160,
    );

    return doc;
  }

  /// Print PDF to printer
  static Future<void> printPDF(pw.Document doc, String filename) async {
    try {
      await Printing.layoutPdf(
        onLayout: (format) async => doc.save(),
        name: filename,
        dynamicLayout: true,
      );
    } catch (e) {
      print('Error printing: $e');
      rethrow;
    }
  }

  /// Save PDF to file with location picker
  static Future<bool> savePDFToFile(pw.Document doc, String filename) async {
    try {
      final bytes = await doc.save();
      
      // Open file picker to save
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Please select where to save the Barcode PDF',
        fileName: filename,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (outputFile == null) {
        // User cancelled the picker
        return false;
      }

      final file = File(outputFile);
      await file.writeAsBytes(bytes);
      return true;
    } catch (e) {
      print('Error saving PDF: $e');
      rethrow;
    }
  }

  static pw.Widget _buildDetailRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.SizedBox(
            width: 70,
            child: pw.Text(label,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          ),
          pw.Text(value, style: pw.TextStyle(fontSize: 10)),
        ],
      ),
    );
  }

  static List<_ItemLabel> _buildItemLabels(List<PackageModel> packages) {
    final labels = <_ItemLabel>[];
    final formatter = DateFormat('yyyy-MM-dd');

    for (final package in packages) {
      for (int i = 0; i < package.items.length; i++) {
        final item = package.items[i];
        final count = item.quantity;
        for (int n = 1; n <= count; n++) {
          final whEntry = package.warehouseEntries.firstWhereOrNull((e) => e.packageItemId == item.id) ?? package.warehouseEntries.firstOrNull;
          final whZone = whEntry != null ? '${whEntry.warehouseName} | Zone: ${whEntry.zone ?? 'N/A'}' : 'N/A';

          labels.add(_ItemLabel(
            srNumber: package.srNumber,
            itemName: item.itemName,
            itemId: item.id.isNotEmpty
                ? item.id
                : '${package.srNumber}-${i + 1}',
            index: n,
            total: count,
            consigneeName: package.consigneeName,
            originCountry: package.originCountry,
            status: package.status,
            caseNumber: package.caseNumber ?? 'N/A',
            cusdecNo: package.cusdecNo ?? 'N/A',
            cusdecDate: package.cusdecDate ?? 'N/A',
            entryDate: package.entryDate != null ? formatter.format(package.entryDate!) : 'N/A',
            category: item.category ?? 'N/A',
            unitOfMeasure: item.unitOfMeasure,
            warehouseAndZone: whZone,
            consigneePhone: package.consigneePhone ?? 'N/A',
            hsCode: (item.hsCode?.trim().isNotEmpty == true)
                ? item.hsCode!.trim()
                : 'N/A',
          ));
        }
      }
    }
    return labels;
  }

  static void _addLabelPages(
    pw.Document doc,
    List<pw.Widget> labels, {
    int labelPerRow = 2,
    double labelHeight = 120,
  }) {
    const margin = 10.0;
    const hSpacing = 6.0;
    const vSpacing = 6.0;
    final pageWidth = PdfPageFormat.a4.width;
    final pageHeight = PdfPageFormat.a4.height;
    final labelWidth =
        (pageWidth - (margin * 2) - (hSpacing * (labelPerRow - 1))) /
            labelPerRow;
    final availableHeight = pageHeight - (margin * 2);
    final rowsPerPage =
        (availableHeight / (labelHeight + vSpacing)).floor();
    final labelsPerPage = rowsPerPage * labelPerRow;

    for (int start = 0; start < labels.length; start += labelsPerPage) {
      final pageLabels = labels.skip(start).take(labelsPerPage).toList();
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(margin),
          build: (context) {
            final rows = <pw.Widget>[];
            for (int row = 0; row < rowsPerPage; row++) {
              final rowStart = row * labelPerRow;
              if (rowStart >= pageLabels.length) break;
              final rowItems = pageLabels
                  .skip(rowStart)
                  .take(labelPerRow)
                  .toList();

              final cells = <pw.Widget>[];
              for (final label in rowItems) {
                cells.add(pw.Container(
                  width: labelWidth,
                  height: labelHeight,
                  child: label,
                ));
              }
              while (cells.length < labelPerRow) {
                cells.add(pw.Container(
                  width: labelWidth,
                  height: labelHeight,
                ));
              }

              rows.add(pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: cells,
              ));
              rows.add(pw.SizedBox(height: vSpacing));
            }

            return pw.Column(children: rows);
          },
        ),
      );
    }
  }

  static pw.Widget _detailRow(String label, String value, {double fontSize = 7, double labelWidth = 45}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: labelWidth,
            child: pw.Text('$label:',
                style: pw.TextStyle(
                    fontSize: fontSize,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey800)),
          ),
          pw.Expanded(
            child: pw.Text(value,
                style: pw.TextStyle(fontSize: fontSize),
                maxLines: 2,
                overflow: pw.TextOverflow.clip),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildCompactItemLabel(_ItemLabel label) {
    return _buildLabelCard(label, isCompact: true);
  }

  static pw.Widget _buildDetailedItemLabel(_ItemLabel label) {
    return _buildLabelCard(label, isCompact: false);
  }

  static pw.Widget _buildLabelCard(_ItemLabel label, {required bool isCompact}) {
    final qrCode = Barcode.qrCode(
      errorCorrectLevel: BarcodeQRCorrectionLevel.low,
    );
    final qrContent = [
      '--- SL CUSTOMS ---',
      'SR No: ${label.srNumber}',
      'Item Name: ${label.itemName}',
      'HS Code: ${label.hsCode ?? 'N/A'}',
      'Category: ${label.category}',
      'Quantity: ${label.index} of ${label.total} ${label.unitOfMeasure}',
      'Package # : ${label.index} / ${label.total}',
      'Cusdec No: ${label.cusdecNo}',
      'Cusdec Date: ${label.cusdecDate}',
      'Entry Date: ${label.entryDate}',
      'Case No: ${label.caseNumber}',
      'WH & Zone: ${label.warehouseAndZone}',
      'Consignee: ${label.consigneeName}',
      'Phone: ${label.consigneePhone}',
    ].join('\r\n\r\n'); // Use double CRLF for clear blank lines on all scanners
    final svgString = qrCode.toSvg(qrContent, width: 75, height: 75);

    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.8),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          // Header
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(label.srNumber,
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text('${label.index} / ${label.total}',
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.SizedBox(height: 1),
          pw.Divider(thickness: 0.5, color: PdfColors.grey),
          pw.SizedBox(height: 2),

          // Body: text on left, QR on right
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _detailRow('Item', label.itemName, fontSize: 8),
                    _detailRow('HS Code', label.hsCode ?? 'N/A', fontSize: 7),
                    _detailRow('Category', label.category ?? 'N/A', fontSize: 7),
                    _detailRow('Unit', label.unitOfMeasure ?? 'Pieces', fontSize: 7),
                    _detailRow('Cusdec', label.cusdecNo ?? 'N/A', fontSize: 7),
                    _detailRow('Case #', label.caseNumber, fontSize: 7),
                    _detailRow('Entry Dt', label.entryDate ?? 'N/A', fontSize: 7),
                  ],
                ),
              ),
              pw.SizedBox(width: 4),
              // Right side: QR code
              pw.Column(
                 crossAxisAlignment: pw.CrossAxisAlignment.center,
                 children: [
                    pw.SvgImage(svg: svgString, width: 75, height: 75),
                    pw.SizedBox(height: 2),
                    pw.Text('Scan for Info', style: pw.TextStyle(fontSize: 5, fontStyle: pw.FontStyle.italic, color: PdfColors.grey600)),
                 ]
              ),
            ],
          ),
          pw.SizedBox(height: 2),
          // Footer
          _detailRow('Location', label.warehouseAndZone ?? 'N/A', fontSize: 8),
          _detailRow('Consignee', label.consigneeName, fontSize: 8),
          _detailRow('Phone', label.consigneePhone ?? 'N/A', fontSize: 8),
        ],
      ),
    );
  }
}

class _ItemLabel {
  final String srNumber;
  final String itemName;
  final String itemId;
  final int index;
  final int total;
  final String consigneeName;
  final String originCountry;
  final String status;
  final String caseNumber;
  final String? cusdecNo;
  final String? cusdecDate;
  final String? entryDate;
  final String? category;
  final String? unitOfMeasure;
  final String? warehouseAndZone;
  final String? consigneePhone;
  final String? hsCode;

  _ItemLabel({
    required this.srNumber,
    required this.itemName,
    required this.itemId,
    required this.index,
    required this.total,
    required this.consigneeName,
    required this.originCountry,
    required this.status,
    required this.caseNumber,
    this.cusdecNo,
    this.cusdecDate,
    this.entryDate,
    this.category,
    this.unitOfMeasure,
    this.warehouseAndZone,
    this.consigneePhone,
    this.hsCode,
  });
}
