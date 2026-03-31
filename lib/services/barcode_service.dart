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
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

    for (final package in packages) {
      final bc = Barcode.code128();
      final svgString = bc.toSvg(package.srNumber, width: 300, height: 80);

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(10),
          build: (context) => pw.FittedBox(
            fit: pw.BoxFit.contain,
            child: pw.Container(
              width: PdfPageFormat.a4.width - 20,
              padding: const pw.EdgeInsets.all(15),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Header(
                    level: 0,
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('CUSTOMS YARD MANAGEMENT',
                                style: pw.TextStyle(
                                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
                            pw.Text('Package Barcode Label',
                                style: pw.TextStyle(fontSize: 10)),
                          ],
                        ),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text(dateFormat.format(DateTime.now()),
                                style: pw.TextStyle(fontSize: 8)),
                            pw.Text('Printed: ${DateTime.now().toLocal()}',
                                style: pw.TextStyle(fontSize: 7)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 15),
                  pw.Container(
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.black, width: 1),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                    ),
                    padding: const pw.EdgeInsets.all(12),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text('SR Number:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                                pw.Text(package.srNumber, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                              ],
                            ),
                            pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.end,
                              children: [
                                pw.Text('Total Items:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                                pw.Text('${package.totalItemCount}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 12),
                        pw.Center(
                          child: pw.Column(
                            children: [
                              pw.SvgImage(svg: svgString, width: 250),
                              pw.SizedBox(height: 5),
                              pw.Text(package.srNumber, style: pw.TextStyle(fontSize: 8)),
                            ],
                          ),
                        ),
                        pw.SizedBox(height: 12),
                        pw.Divider(thickness: 0.5),
                        pw.SizedBox(height: 8),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                _buildDetailRow('Consignee:', package.consigneeName),
                                _buildDetailRow('Origin:', package.originCountry),
                                _buildDetailRow('Weight:', '${package.weightKg} kg'),
                              ],
                            ),
                            pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                _buildDetailRow('Status:', package.status.toUpperCase()),
                                _buildDetailRow('Value:', 'LKR ${package.declaredValue.toStringAsFixed(2)}'),
                                _buildDetailRow('Case #:', package.caseNumber ?? 'N/A'),
                              ],
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 8),
                        pw.Text('Description: ${package.description ?? 'No description'}',
                            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Divider(thickness: 1),
                  pw.SizedBox(height: 8),
                  if (package.items.isNotEmpty) ...[
                    pw.Text('Package Items:',
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 5),
                    pw.Table(
                      border: pw.TableBorder.all(width: 0.5),
                      columnWidths: {
                        0: const pw.FlexColumnWidth(0.5),
                        1: const pw.FlexColumnWidth(2),
                        2: const pw.FlexColumnWidth(1),
                        3: const pw.FlexColumnWidth(1.5),
                      },
                      children: [
                        pw.TableRow(
                          decoration: pw.BoxDecoration(color: PdfColors.grey200),
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(3),
                              child: pw.Text('#', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(3),
                              child: pw.Text('Item Name', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(3),
                              child: pw.Text('Qty', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(3),
                              child: pw.Text('Warehouse', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                            ),
                          ],
                        ),
                        ...List.generate(
                          package.items.length,
                          (idx) {
                            final item = package.items[idx];
                            final warehouseEntry = package.warehouseEntries
                                .firstWhereOrNull(
                                  (e) => e.packageItemId == item.id && !e.isReturned,
                                ) ??
                                package.warehouseEntries.firstOrNull;

                            return pw.TableRow(
                              children: [
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(3),
                                  child: pw.Text('${idx + 1}', style: pw.TextStyle(fontSize: 8)),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(3),
                                  child: pw.Text(item.itemName, style: pw.TextStyle(fontSize: 8)),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(3),
                                  child: pw.Text('${item.quantity}', style: pw.TextStyle(fontSize: 8)),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(3),
                                  child: pw.Text(
                                    warehouseEntry?.warehouseName ?? 'TBD',
                                    style: pw.TextStyle(fontSize: 7),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

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

  /// Save PDF to file
  static Future<void> savePDFToFile(pw.Document doc, String filename) async {
    try {
      final bytes = await doc.save();
      await Printing.sharePdf(
        bytes: bytes,
        filename: filename,
      );
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
}
