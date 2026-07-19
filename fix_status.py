import os, re

files = [
    'lib/screens/admin/admin_screen.dart', 
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
    'lib/screens/valuation/valuation_dashboard_screen.dart', 
    'lib/screens/warehouses/warehouses_screen.dart', 
    'lib/screens/warehouses/warehouse_capacity_screen.dart'
]

def process_file(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Center column headers
    targets = ['Status', 'Delivery', 'Decision', 'Source', 'Payment', 'State', 'Stage']
    for t in targets:
        content = re.sub(rf"DataColumn2\(label:\s*Text\('{t}'\)", f"DataColumn2(label: Center(child: Text('{t}')),", content)
        content = re.sub(rf"DataColumn2\(\s*label:\s*Text\('{t}'\)", f"DataColumn2(label: Center(child: Text('{t}')),", content)

    # For cells
    content = re.sub(r"DataCell\(_statusChip\((.*?)\)\),", r"DataCell(Center(child: _statusChip(\1))),", content)
    content = re.sub(r"DataCell\(_deliveryChip\((.*?)\)\),", r"DataCell(Center(child: _deliveryChip(\1))),", content)
    content = re.sub(r"DataCell\(_buildStatusChip\((.*?)\)\),", r"DataCell(Center(child: _buildStatusChip(\1))),", content)
    
    # We have to be very careful with Container replacing to not mess up parentheses.
    # It's better to manually replace those few files.
    
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)

for f in files:
    if os.path.exists(f):
        process_file(f)
print('Done')
