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

targets = ['Status', 'Delivery', 'Decision', 'Source', 'Payment', 'State', 'Stage', 'Disposition']

for f in files:
    if not os.path.exists(f): continue
    content = open(f, encoding='utf-8').read()
    
    # 1. First, temporarily change already centered headers to something else so they aren't processed again
    for t in targets:
        content = content.replace(f"label: Center(child: Text('{t}'))", f"__ALREADY_CENTERED_{t}__")
        # Same for multi-line
        content = re.sub(rf"label:\s*Center\(\s*child:\s*Text\('{t}'\)\s*\)", f"__ALREADY_CENTERED_{t}__", content)

    # 2. Now process the uncentered headers
    for t in targets:
        content = re.sub(rf"label:\s*Text\('{t}'\)", f"label: Center(child: Text('{t}'))", content)

    # 3. Put back the already centered ones
    for t in targets:
        content = content.replace(f"__ALREADY_CENTERED_{t}__", f"label: Center(child: Text('{t}'))")


    # Now for chips
    chip_names = ['_statusChip', '_deliveryChip', '_sourceChip', '_dispositionChip', '_stageChip', '_paymentChip', '_decisionChip']
    
    # 1. Temporarily replace already centered chips
    for c in chip_names:
        content = re.sub(rf"DataCell\(\s*Center\(\s*child:\s*{c}\((.*?)\)\s*\)\s*\)", rf"__ALREADY_CENTERED_CHIP_{c}(\1)__", content)

    # 2. Replace uncentered chips
    for c in chip_names:
        content = re.sub(rf"DataCell\(\s*{c}\((.*?)\)\s*\)", rf"DataCell(Center(child: {c}(\1)))", content)
        
    # 3. Put back already centered chips
    for c in chip_names:
        content = re.sub(rf"__ALREADY_CENTERED_CHIP_{c}\((.*?)\)__", rf"DataCell(Center(child: {c}(\1)))", content)

    # Also handle the manual Center(child: Container(...)) ones for Status column?
    # Let's see if there are any Mark Destroyed buttons. The user showed Destruction Sales -> Mark Destroyed button.
    # We should center it. It might be: DataCell(ElevatedButton(child: Text('Mark Destroyed'))) or similar.
    # Let's just fix the main chip names first.
    
    with open(f, 'w', encoding='utf-8') as out:
        out.write(content)
print('Done')
