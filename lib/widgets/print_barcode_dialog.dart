import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:printing/printing.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../services/barcode_service.dart';

class PrintBarcodeDialog extends StatefulWidget {
  final List<PackageModel> packages;
  final VoidCallback? onPrinted;

  const PrintBarcodeDialog({
    super.key,
    required this.packages,
    this.onPrinted,
  });

  @override
  State<PrintBarcodeDialog> createState() => _PrintBarcodeDialogState();
}

class _PrintBarcodeDialogState extends State<PrintBarcodeDialog> {
  bool _isPrinting = false;
  String _printMode = 'detailed'; // 'detailed' or 'batch'
  bool _showPreview = true;

  Future<void> _handlePrint() async {
    setState(() => _isPrinting = true);
    try {
      final doc = _printMode == 'detailed'
          ? await BarcodeService.createBarcodePDF(widget.packages)
          : await BarcodeService.createBatchBarcodesPDF(widget.packages);

      await BarcodeService.printPDF(doc, 'barcode_${DateTime.now().millisecondsSinceEpoch}.pdf');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Print job sent to printer'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onPrinted?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  Future<void> _handleSave() async {
    setState(() => _isPrinting = true);
    try {
      final doc = _printMode == 'detailed'
          ? await BarcodeService.createBarcodePDF(widget.packages)
          : await BarcodeService.createBatchBarcodesPDF(widget.packages);

      await BarcodeService.savePDFToFile(
        doc,
        'barcode_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ PDF saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 800,
        decoration: BoxDecoration(
          color: context.colors.surfaceDark,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: context.colors.borderColor)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Package Barcode Printing',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Gap(8),
                      Text(
                        '${widget.packages.length} package${widget.packages.length != 1 ? 's' : ''} ready to print',
                        style: TextStyle(color: context.colors.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: context.colors.textMuted),
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Print Mode Selection
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: context.colors.cardDark,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.colors.borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Print Format',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: context.colors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          Gap(12),
                          _buildModeOption(
                            'Detailed Labels',
                            'Full package details with barcode',
                            'detailed',
                          ),
                          Gap(12),
                          _buildModeOption(
                            'Batch Labels',
                            'Compact labels for quick printing',
                            'batch',
                          ),
                        ],
                      ),
                    ),
                    Gap(20),
                    // Package List
                    Text(
                      'Packages to Print:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: context.colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    Gap(12),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: context.colors.borderColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: widget.packages.length,
                        separatorBuilder: (_, __) =>
                            Divider(color: context.colors.borderColor, height: 1),
                        itemBuilder: (context, index) {
                          final pkg = widget.packages[index];
                          return Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: context.colors.primaryGold.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: context.colors.primaryGold,
                                      ),
                                    ),
                                  ),
                                ),
                                Gap(12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        pkg.srNumber,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Gap(4),
                                      Row(
                                        children: [
                                          Text(
                                            pkg.consigneeName,
                                            style: TextStyle(
                                              color: context.colors.textMuted,
                                              fontSize: 12,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Gap(8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _getStatusColor(pkg.status)
                                                  .withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              pkg.status.toUpperCase(),
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: _getStatusColor(pkg.status),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${pkg.totalItemCount} items',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: context.colors.primaryGold,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: context.colors.borderColor)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isPrinting ? null : () => Navigator.of(context).pop(),
                    child: Text('Cancel',
                        style: TextStyle(color: context.colors.textMuted)),
                  ),
                  Gap(12),
                  ElevatedButton.icon(
                    onPressed: _isPrinting ? null : _handleSave,
                    icon: const Icon(Icons.save),
                    label: const Text('Save PDF'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.accentLightBlue.withOpacity(0.2),
                      foregroundColor: context.colors.accentLightBlue,
                    ),
                  ),
                  Gap(12),
                  ElevatedButton.icon(
                    onPressed: _isPrinting ? null : _handlePrint,
                    icon: _isPrinting
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.print),
                    label: Text(_isPrinting ? 'Printing...' : 'Print Now'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.primaryGold,
                      foregroundColor: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeOption(String title, String subtitle, String value) {
    return InkWell(
      onTap: () => setState(() => _printMode = value),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: _printMode == value
                ? context.colors.primaryGold
                : context.colors.borderColor,
            width: _printMode == value ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: _printMode == value
              ? context.colors.primaryGold.withOpacity(0.05)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Radio<String>(
              value: value,
              groupValue: _printMode,
              onChanged: (v) => setState(() => _printMode = v ?? 'detailed'),
              activeColor: context.colors.primaryGold,
            ),
            Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Gap(4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return context.colors.heldOrange;
      case 'cleared':
        return context.colors.successGreen;
      case 'returned':
        return context.colors.successGreen;
      case 'held':
        return context.colors.heldOrange;
      default:
        return context.colors.textMuted;
    }
  }
}
