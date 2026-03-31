# Barcode Printing System - Usage Guide

## Overview
This system allows you to generate and print barcodes for every package registered in the Customs Yard Management System. Barcodes are automatically encoded with the SR (Shipping Record) number, making them easy to scan and track throughout the warehouse.

## Features

### 1. **Automatic Barcode Generation**
- Barcodes are generated automatically when a new SR is registered
- Each barcode encodes the unique SR number (e.g., GL1/SR/04/2026)
- Supports Code128 barcode format (enterprise-standard 1D barcode)

### 2. **Multiple Print Formats**

#### Detailed Labels (Full Page)
- **Use Case**: Initial labeling, official records
- **Contents**:
  - Large barcode (scannable from distance)
  - SR Number prominently displayed
  - Total item count
  - Consignee name
  - Origin country
  - Package weight
  - Declared value (LKR)
  - Case number
  - Package description
  - Itemized list of contents with warehouse assignments
- **Print Size**: One label per A4 page
- **Best For**: Detailed record keeping and initial processing

#### Batch Labels (Compact)
- **Use Case**: Quick printing, bulk operations
- **Contents**:
  - Compact barcode
  - SR Number
  - Consignee name (abbreviated)
  - Item count
- **Print Size**: Multiple labels per A4 page (~4-6 per page)
- **Best For**: High-volume printing, manual warehouse staging

### 3. **Integration Points**

#### Point 1: After SR Registration (Inspection Screen)
When you complete the SR registration and warehouse allocation, you'll see:
```
✅ ENTRY SAVED SUCCESSFULLY
[Print Barcode Label] button
```

Click **Print Barcode Label** to open the print dialog immediately.

#### Point 2: From Package Details
You can print barcodes for any existing package from the package details view.

#### Point 3: Batch Printing
Print barcodes for multiple packages at once using the batch format.

## How to Use

### Printing After SR Registration (Recommended Flow)

1. **Complete SR Registration Form**
   - Fill in all package details
   - Assign items to warehouses
   - Click "Send to Warehouses"

2. **Print Success Screen Appears**
   - You'll see the green success message: "ENTRY SAVED SUCCESSFULLY"
   - Click the yellow **"Print Barcode Label"** button

3. **Print Dialog Opens**
   - Label format options appear
   - Select either **"Detailed Labels"** or **"Batch Labels"**
   - Review the list of packages
   - Choose action:
     - **Print Now**: Send directly to your connected printer
     - **Save PDF**: Save to your device for later printing

4. **Printing**
   - For **Print Now**: Select your printer and print settings in the printer dialog
   - For **Save PDF**: PDF will be saved to your Downloads folder with timestamp

### Printing Existing Packages

1. Navigate to **Packages** screen
2. Find the package you need to print
3. Click the package details
4. Look for **"Print Barcode"** option (when available)
5. Follow the same print dialog flow

## PDF File Information

### File Naming
- Format: `barcode_[timestamp].pdf`
- Example: `barcode_1711900234567.pdf`
- Saved to: Default Downloads folder

### PDF Contents
Each package label includes:
- **Header**: "CUSTOMS YARD MANAGEMENT" with date/time
- **SR Information**: SR Number, total items
- **Barcode**: Code128 format, scannable
- **Package Details**: Consignee, origin, weight, value, case#, description
- **Item Breakdown**: Table with item names, quantities, and warehouse assignments

## Technical Details

### Barcode Format
- **Type**: Code128 (universal 1D barcode)
- **Data Encoded**: SR Number (e.g., "GL1/SR/04/2026")
- **Resolution**: 300 DPI (print quality)
- **Scanning**: Compatible with all standard barcode scanners

### Supported Printers
- Any printer connected to your Windows/Mac system
- Recommended: Thermal label printers for batch labels
- A4/Letter size printers for detailed labels
- Network printers supported

### PDF Compatibility
- Standard PDF format (ISO 32000)
- Compatible with all PDF readers and printers
- Maintains layout across different printer models

## Best Practices

### For Initial Processing
1. Use **Detailed Labels** during SR registration
2. Print immediately after warehouse allocation
3. Attach to physical package in warehouse
4. Keep a copy in office records

### For Warehouse Management
1. Use **Batch Labels** for staging and handling
2. Print multiple packages at once
3. Create label sheets for daily operations
4. Store PDF archive for audit trail

### For Returns and Releases
1. Print a barcode when marking as returned
2. Use barcode for quick tracking of returned items
3. Maintain chronological record of barcode labels

### Printer Setup Tips
1. **For Thermal Printers**: Use Batch Labels format (more compact)
2. **For Standard Printers**: Use Detailed Labels (better readability)
3. **Network Printers**: Test print one label before batch printing
4. **Regular Audit**: Keep PDF backups of all printed barcodes

## Troubleshooting

### Issue: Print dialog doesn't appear
**Solution**: 
- Ensure package was saved successfully (green success message)
- Check if a printer is installed and connected
- Try "Save PDF" instead if printer connection is unstable

### Issue: Barcode won't scan
**Solution**:
- Ensure print quality is at least 300 DPI
- Verify barcode is not damaged or faded
- Check scanner settings (may need Code128 support enabled)
- Try different scanning distance

### Issue: PDF won't open
**Solution**:
- Ensure Adobe Reader or compatible PDF viewer is installed
- Try opening with different PDF reader application
- Check file location and permissions

### Issue: Wrong printer selected
**Solution**:
- When clicked "Print Now", select correct printer from dialog
- To change default printer, go to Settings → Devices → Printers & Scanners

## Example Scenarios

### Scenario 1: Gold Import Jewelry Package (GL1/SR/04/2026)
```
Workflow:
1. Register SR with 13 items of jewelry
2. Assign all items to Warehouse 01, Zone A
3. Click "Send to Warehouses"
4. Success! Click "Print Barcode Label"
5. Select "Detailed Labels"
6. Print directly to office printer
7. Attach barcode to gold package in warehouse
8. Barcode can now be scanned for subsequent returns/releases
```

### Scenario 2: Electronics Shipment with Multiple Returns
```
Workflow:
1. Original SR registers 25 electronic items
2. First return: 15 items released → scan barcode
3. Second return: 8 items released → scan barcode
4. Remaining: 2 items held → use original barcode for reference
5. All transactions tracked by barcode
```

### Scenario 3: Bulk Warehouse Processing
```
Workflow:
1. Process 10 SRs in morning
2. After each SR completion → Print Barcode Label
3. Select "Batch Labels"
4. Print all 10 barcodes at once
5. Create label sheet
6. Apply labels to warehouse staging section
```

## Integration with Warehouse Systems

The barcode system integrates seamlessly with the existing warehouse management:

1. **Package Creation**: Barcode generated automatically
2. **Warehouse Entry**: Barcode identifies the item
3. **Returns Tracking**: Scan barcode when releasing items
4. **Audit Trail**: Each barcode printout creates PDF record
5. **Release Management**: Barcode simplifies multiple partial returns

## FAQ

**Q: Can I print barcodes for packages that were already released?**
A: Yes, you can print barcodes from the package details view at any time, even for historical packages.

**Q: What if I need to print additional labels later?**
A: Navigate to the package details and select the print option. The system will generate new labels with current date/time.

**Q: Are barcodes unique for each print?**
A: No, the barcode always encodes the same SR number. Multiple prints of the same package will have identical barcodes (by design).

**Q: Can I edit the barcode content?**
A: No, barcodes are automatically generated from the SR number. To change the barcode, modify the SR number (not recommended as it breaks audit trail).

**Q: Are PDFs automatically saved or do I need to save them?**
A: You control this with the "Save PDF" button. "Print Now" sends directly to printer without saving.

## Support

For issues with barcode generation or printing:
1. Check troubleshooting section above
2. Verify printer connectivity
3. Ensure Flutter app is up to date
4. Contact system administrator if barcode generation fails

---

**Last Updated**: March 31, 2026  
**Version**: 1.0  
**Supported Since**: SR Registration Enhancement
