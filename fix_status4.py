import os, re

files = [
    'lib/screens/admin/admin_screen.dart', 
    'lib/screens/admin/admin_dashboard_screen.dart',
    'lib/screens/appeal/appeal_dashboard_screen.dart', 
    'lib/screens/dashboard/dashboard_screen.dart', 
    'lib/screens/disposal/disposal_dashboard_screen.dart', 
    'lib/screens/disposal/taxes_tab.dart', 
    'lib/screens/forfeited_packages/forfeited_packages_screen.dart', 
    'lib/screens/forfeited_packages/tender_disposal_screen.dart', 
    'lib/screens/packages/abandoned_packages_screen.dart', 
    'lib/screens/packages/disposition_category_screen.dart', 
    'lib/screens/packages/other_packages_screen.dart', 
    'lib/screens/packages/packages_screen.dart', 
    'lib/screens/packages/returned_packages_screen.dart',
    'lib/screens/packages/sold_packages_screen.dart', 
    'lib/screens/valuation/valuation_dashboard_screen.dart', 
    'lib/screens/warehouses/warehouses_screen.dart', 
    'lib/screens/warehouses/warehouse_capacity_screen.dart'
]

chip_patterns = [
    r'_SourceChip',
    r'_DispositionChip',
    r'_DeliveryChip',
    r'_StatusChip',
    r'_StageChip',
    r'_DecisionChip',
    r'_PaymentChip',
    r'_DeliveryStatusChip'
]

# Let's also include the Mark Destroyed button
mark_destroyed_pattern = r"OutlinedButton\.icon\([\s\S]*?label:\s*const\s*Text\('Mark Destroyed'[\s\S]*?\)"

for f in files:
    if not os.path.exists(f): continue
    content = open(f, encoding='utf-8').read()
    
    # Simple replace for DataCell(_SourceChip(...)) where there are no complex nested parens that we can't handle.
    # Actually, Dart widgets can span multiple lines.
    # Let's find index of 'DataCell(' and see if it's followed by '_SourceChip('
    
    for chip in chip_patterns:
        idx = 0
        while True:
            # find the chip
            idx = content.find(chip + "(", idx)
            if idx == -1: break
            
            # check if it's inside a DataCell
            # go backwards to find DataCell
            datacell_idx = content.rfind("DataCell(", 0, idx)
            if datacell_idx != -1 and content[datacell_idx:idx].strip() == "DataCell(":
                # It is inside a DataCell. But is it already centered?
                center_idx = content.rfind("Center(", datacell_idx, idx)
                if center_idx != -1:
                    idx += 1
                    continue # already centered
                
                # Wrap it in Center
                # Count parens to find the end of DataCell
                count = 0
                end_idx = -1
                for i in range(datacell_idx, len(content)):
                    if content[i] == '(': count += 1
                    elif content[i] == ')': count -= 1
                    if count == 0:
                        end_idx = i
                        break
                
                if end_idx != -1:
                    # Replace DataCell(...) with DataCell(Center(child: ...))
                    content = content[:datacell_idx] + "DataCell(Center(child: " + content[datacell_idx+9:end_idx] + "))" + content[end_idx+1:]
                    idx = end_idx + 25
            idx += 1

    # Same for Mark Destroyed button
    # If a DataCell contains an OutlinedButton for 'Mark Destroyed'
    # The cell is DataCell(isSold ? ... : btn) or similar.
    # The user screenshot showed Mark Destroyed button. 
    # Let's just find any Mark Destroyed OutlinedButton and ensure its parent cell is centered if possible.
    # Actually, in destruction sales, it's:
    # return canDestroy ? btn : Tooltip(message: ..., child: btn);
    # This entire block is wrapped in DataCell( (() { ... })() )
    # Let's find "DataCell(isSold" or similar where 'Mark Destroyed' is present.
    # It's at line 4032.
    # Let's just wrap that specific DataCell in Center.
    md_idx = content.find("const Text('Mark Destroyed'")
    if md_idx != -1:
        dc_idx = content.rfind("DataCell(", 0, md_idx)
        if dc_idx != -1:
            c_idx = content.rfind("Center(", dc_idx, md_idx)
            if c_idx == -1:
                # Find end of DataCell
                count = 0
                end_idx = -1
                for i in range(dc_idx, len(content)):
                    if content[i] == '(': count += 1
                    elif content[i] == ')': count -= 1
                    if count == 0:
                        end_idx = i
                        break
                if end_idx != -1:
                    content = content[:dc_idx] + "DataCell(Center(child: " + content[dc_idx+9:end_idx] + "))" + content[end_idx+1:]

    with open(f, 'w', encoding='utf-8') as out:
        out.write(content)
print('Done')
